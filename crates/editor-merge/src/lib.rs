//! Bounded, GUI-free three-way line merge projection.
//!
//! The projection keeps unresolved regions at their base text, automatically
//! applies one-sided and identical changes, and lets callers choose either
//! input for each unresolved conflict. Text slices are retained verbatim so
//! line endings, BOMs, final-newline state, and Unicode survive projection.

use std::error::Error;
use std::fmt;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum InputSide {
    Input1,
    Input2,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MergeLimits {
    /// Sum of the UTF-8 byte lengths for base, input1, and input2.
    pub max_total_input_bytes: usize,
    pub max_lines_per_input: usize,
    /// Myers frontier slots retained for one base-to-input comparison.
    pub max_trace_cells: usize,
    /// Frontier and equality operations across both input comparisons.
    pub max_work: usize,
    pub max_conflicts: usize,
    /// Owned text retained by the projection, including conflict choices.
    pub max_projection_bytes: usize,
}

impl Default for MergeLimits {
    fn default() -> Self {
        Self {
            max_total_input_bytes: 8 * 1024 * 1024,
            max_lines_per_input: 8_192,
            max_trace_cells: 2_000_000,
            max_work: 4_000_000,
            max_conflicts: 1_024,
            max_projection_bytes: 16 * 1024 * 1024,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MergeError {
    InputByteLimit,
    LineLimit,
    TraceLimit,
    WorkLimit,
    ConflictLimit,
    ProjectionLimit,
    UnknownConflict(usize),
    InvalidDiff,
}

impl fmt::Display for MergeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InputByteLimit => write!(f, "three-way merge input byte limit exceeded"),
            Self::LineLimit => write!(f, "three-way merge line limit exceeded"),
            Self::TraceLimit => write!(f, "three-way merge diff trace limit exceeded"),
            Self::WorkLimit => write!(f, "three-way merge work limit exceeded"),
            Self::ConflictLimit => write!(f, "three-way merge conflict limit exceeded"),
            Self::ProjectionLimit => write!(f, "three-way merge projection limit exceeded"),
            Self::UnknownConflict(id) => write!(f, "unknown merge conflict {id}"),
            Self::InvalidDiff => write!(f, "three-way merge diff ranges are inconsistent"),
        }
    }
}

impl Error for MergeError {}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MergeConflict {
    pub id: usize,
    /// Zero-based, end-exclusive line range in the base input.
    pub base_start_line: usize,
    pub base_end_line_exclusive: usize,
    pub base_text: String,
    pub input1_text: String,
    pub input2_text: String,
    pub resolution: Option<InputSide>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum MergeSegment {
    Text(String),
    Conflict(MergeConflict),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MergeProjection {
    segments: Vec<MergeSegment>,
}

impl MergeProjection {
    pub fn new(base: &str, input1: &str, input2: &str) -> Result<Self, MergeError> {
        Self::with_limits(base, input1, input2, MergeLimits::default())
    }

    pub fn with_limits(
        base: &str,
        input1: &str,
        input2: &str,
        limits: MergeLimits,
    ) -> Result<Self, MergeError> {
        let input_bytes = base
            .len()
            .checked_add(input1.len())
            .and_then(|n| n.checked_add(input2.len()))
            .ok_or(MergeError::InputByteLimit)?;
        if input_bytes > limits.max_total_input_bytes {
            return Err(MergeError::InputByteLimit);
        }

        let base_lines = split_lines_preserving_endings(base);
        let input1_lines = split_lines_preserving_endings(input1);
        let input2_lines = split_lines_preserving_endings(input2);
        if base_lines.len() > limits.max_lines_per_input
            || input1_lines.len() > limits.max_lines_per_input
            || input2_lines.len() > limits.max_lines_per_input
        {
            return Err(MergeError::LineLimit);
        }

        let mut work = 0;
        let changes1 = compute_changes(
            &base_lines,
            &input1_lines,
            InputSide::Input1,
            limits,
            &mut work,
        )?;
        let changes2 = compute_changes(
            &base_lines,
            &input2_lines,
            InputSide::Input2,
            limits,
            &mut work,
        )?;
        let mut changes = changes1;
        changes.extend(changes2);
        changes.sort_by_key(|change| {
            (
                change.base_start,
                change.base_end,
                change.side,
                change.input_start,
            )
        });

        let mut segments = Vec::new();
        let mut base_cursor = 0;
        let mut index = 0;
        let mut conflict_count = 0;
        while index < changes.len() {
            let start = changes[index].base_start;
            let mut end = changes[index].base_end;
            let mut group = vec![changes[index]];
            index += 1;
            while index < changes.len()
                && group
                    .iter()
                    .any(|existing| ranges_conflict(*existing, changes[index]))
            {
                end = end.max(changes[index].base_end);
                group.push(changes[index]);
                index += 1;
            }

            if start < base_cursor || end > base_lines.len() {
                return Err(MergeError::InvalidDiff);
            }
            if base_cursor < start {
                segments.push(MergeSegment::Text(join_lines(
                    &base_lines[base_cursor..start],
                )));
            }

            let side1 = changes_for_side(&group, InputSide::Input1);
            let side2 = changes_for_side(&group, InputSide::Input2);
            let candidate1 = apply_changes(
                &base_lines,
                &input1_lines,
                &input2_lines,
                start,
                end,
                &side1,
            )?;
            let candidate2 = apply_changes(
                &base_lines,
                &input1_lines,
                &input2_lines,
                start,
                end,
                &side2,
            )?;
            let base_text = join_lines(&base_lines[start..end]);

            let has_conflict = has_cross_side_overlap(&side1, &side2);
            if has_conflict && candidate1 != candidate2 {
                if conflict_count >= limits.max_conflicts {
                    return Err(MergeError::ConflictLimit);
                }
                segments.push(MergeSegment::Conflict(MergeConflict {
                    id: conflict_count,
                    base_start_line: start,
                    base_end_line_exclusive: end,
                    base_text,
                    input1_text: candidate1,
                    input2_text: candidate2,
                    resolution: None,
                }));
                conflict_count += 1;
            } else if has_conflict {
                segments.push(MergeSegment::Text(candidate1));
            } else {
                let combined = apply_changes(
                    &base_lines,
                    &input1_lines,
                    &input2_lines,
                    start,
                    end,
                    &group,
                )?;
                segments.push(MergeSegment::Text(combined));
            }
            base_cursor = end;
        }

        if base_cursor < base_lines.len() {
            segments.push(MergeSegment::Text(join_lines(&base_lines[base_cursor..])));
        }

        let projection_bytes = segments.iter().try_fold(0usize, |sum, segment| {
            let segment_bytes = match segment {
                MergeSegment::Text(text) => Some(text.len()),
                MergeSegment::Conflict(conflict) => conflict
                    .base_text
                    .len()
                    .checked_add(conflict.input1_text.len())
                    .and_then(|n| n.checked_add(conflict.input2_text.len())),
            };
            sum.checked_add(segment_bytes?)
        });
        if projection_bytes.ok_or(MergeError::ProjectionLimit)? > limits.max_projection_bytes {
            return Err(MergeError::ProjectionLimit);
        }

        Ok(Self { segments })
    }

    pub fn result_text(&self) -> String {
        let capacity = self.segments.iter().map(MergeSegment::result_len).sum();
        let mut result = String::with_capacity(capacity);
        for segment in &self.segments {
            result.push_str(segment.result_text());
        }
        result
    }

    pub fn conflicts(&self) -> impl Iterator<Item = &MergeConflict> {
        self.segments.iter().filter_map(|segment| match segment {
            MergeSegment::Text(_) => None,
            MergeSegment::Conflict(conflict) => Some(conflict),
        })
    }

    /// Iterate conflicts with their half-open UTF-16 ranges in the current result.
    ///
    /// The range follows the active contribution: unresolved conflicts use the
    /// base fallback, while resolved conflicts use the selected input. Callers
    /// must recompute ranges after changing a resolution.
    pub fn conflicts_with_result_ranges(
        &self,
    ) -> impl Iterator<Item = (&MergeConflict, usize, usize)> + '_ {
        let mut result_offset_utf16 = 0;
        self.segments.iter().filter_map(move |segment| {
            let result_start_utf16 = result_offset_utf16;
            let text = segment.result_text();
            result_offset_utf16 += text.encode_utf16().count();
            match segment {
                MergeSegment::Text(_) => None,
                MergeSegment::Conflict(conflict) => {
                    Some((conflict, result_start_utf16, result_offset_utf16))
                }
            }
        })
    }

    pub fn conflict_count(&self) -> usize {
        self.conflicts().count()
    }

    pub fn unresolved_conflict_count(&self) -> usize {
        self.conflicts()
            .filter(|conflict| conflict.resolution.is_none())
            .count()
    }

    pub fn accept_conflict(&mut self, id: usize, side: InputSide) -> Result<bool, MergeError> {
        for segment in &mut self.segments {
            if let MergeSegment::Conflict(conflict) = segment {
                if conflict.id == id {
                    let changed = conflict.resolution != Some(side);
                    conflict.resolution = Some(side);
                    return Ok(changed);
                }
            }
        }
        Err(MergeError::UnknownConflict(id))
    }

    pub fn accept_all(&mut self, side: InputSide) -> usize {
        let mut changed = 0;
        for segment in &mut self.segments {
            if let MergeSegment::Conflict(conflict) = segment {
                if conflict.resolution != Some(side) {
                    conflict.resolution = Some(side);
                    changed += 1;
                }
            }
        }
        changed
    }
}

impl MergeSegment {
    fn result_text(&self) -> &str {
        match self {
            Self::Text(text) => text,
            Self::Conflict(conflict) => match conflict.resolution {
                Some(InputSide::Input1) => &conflict.input1_text,
                Some(InputSide::Input2) => &conflict.input2_text,
                None => &conflict.base_text,
            },
        }
    }

    fn result_len(&self) -> usize {
        self.result_text().len()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Change {
    side: InputSide,
    base_start: usize,
    base_end: usize,
    input_start: usize,
    input_end: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Edit {
    Equal,
    Delete,
    Insert,
}

fn split_lines_preserving_endings(text: &str) -> Vec<&str> {
    let bytes = text.as_bytes();
    let mut lines = Vec::new();
    let mut start = 0;
    let mut index = 0;
    while index < bytes.len() {
        match bytes[index] {
            b'\n' => {
                index += 1;
                lines.push(&text[start..index]);
                start = index;
            }
            b'\r' => {
                index += if bytes.get(index + 1) == Some(&b'\n') {
                    2
                } else {
                    1
                };
                lines.push(&text[start..index]);
                start = index;
            }
            _ => index += 1,
        }
    }
    if start < bytes.len() {
        lines.push(&text[start..]);
    }
    lines
}

fn join_lines(lines: &[&str]) -> String {
    let capacity = lines.iter().map(|line| line.len()).sum();
    let mut text = String::with_capacity(capacity);
    for line in lines {
        text.push_str(line);
    }
    text
}

fn compute_changes(
    base: &[&str],
    input: &[&str],
    side: InputSide,
    limits: MergeLimits,
    work: &mut usize,
) -> Result<Vec<Change>, MergeError> {
    let edits = myers_edits(base, input, limits, work)?;
    let mut changes = Vec::new();
    let mut base_index = 0;
    let mut input_index = 0;
    let mut start = None;

    for edit in edits {
        match edit {
            Edit::Equal => {
                if let Some((base_start, input_start)) = start.take() {
                    changes.push(Change {
                        side,
                        base_start,
                        base_end: base_index,
                        input_start,
                        input_end: input_index,
                    });
                }
                base_index += 1;
                input_index += 1;
            }
            Edit::Delete => {
                start.get_or_insert((base_index, input_index));
                base_index += 1;
            }
            Edit::Insert => {
                start.get_or_insert((base_index, input_index));
                input_index += 1;
            }
        }
    }
    if let Some((base_start, input_start)) = start {
        changes.push(Change {
            side,
            base_start,
            base_end: base_index,
            input_start,
            input_end: input_index,
        });
    }
    Ok(changes)
}

fn myers_edits(
    original: &[&str],
    modified: &[&str],
    limits: MergeLimits,
    work: &mut usize,
) -> Result<Vec<Edit>, MergeError> {
    if original == modified {
        return Ok(Vec::new());
    }
    let n = original.len();
    let m = modified.len();
    let max_distance = n.checked_add(m).ok_or(MergeError::TraceLimit)?;
    let offset = max_distance.checked_add(1).ok_or(MergeError::TraceLimit)? as isize;
    let frontier_len = max_distance
        .checked_mul(2)
        .and_then(|value| value.checked_add(3))
        .ok_or(MergeError::TraceLimit)?;

    let mut frontier = vec![0isize; frontier_len];
    let mut trace: Vec<Vec<isize>> = Vec::new();
    let mut trace_cells = 0usize;
    let mut reached_end = false;

    for distance in 0..=max_distance {
        let active_trace_cells = distance
            .checked_mul(2)
            .and_then(|value| value.checked_add(1))
            .ok_or(MergeError::TraceLimit)?;
        trace_cells = trace_cells
            .checked_add(active_trace_cells)
            .ok_or(MergeError::TraceLimit)?;
        if trace_cells > limits.max_trace_cells {
            return Err(MergeError::TraceLimit);
        }
        let trace_start = offset as usize - distance;
        let trace_end = offset as usize + distance + 1;
        trace.push(frontier[trace_start..trace_end].to_vec());
        let distance = distance as isize;
        let mut diagonal = -distance;
        while diagonal <= distance {
            charge_work(work, limits.max_work)?;
            let index = (offset + diagonal) as usize;
            let mut x = if diagonal == -distance
                || (diagonal != distance && frontier[index - 1] < frontier[index + 1])
            {
                frontier[index + 1]
            } else {
                frontier[index - 1] + 1
            };
            let mut y = x - diagonal;
            while x < n as isize && y < m as isize {
                charge_work(work, limits.max_work)?;
                if original[x as usize] != modified[y as usize] {
                    break;
                }
                x += 1;
                y += 1;
            }
            frontier[index] = x;
            if x >= n as isize && y >= m as isize {
                reached_end = true;
                break;
            }
            diagonal += 2;
        }
        if reached_end {
            return backtrack(&trace, n, m);
        }
    }
    Err(MergeError::WorkLimit)
}

fn charge_work(work: &mut usize, max_work: usize) -> Result<(), MergeError> {
    *work = work.checked_add(1).ok_or(MergeError::WorkLimit)?;
    if *work > max_work {
        return Err(MergeError::WorkLimit);
    }
    Ok(())
}

fn backtrack(
    trace: &[Vec<isize>],
    original_len: usize,
    modified_len: usize,
) -> Result<Vec<Edit>, MergeError> {
    let mut x = original_len as isize;
    let mut y = modified_len as isize;
    let mut reversed = Vec::new();

    for distance in (0..trace.len()).rev() {
        let frontier = &trace[distance];
        let distance = distance as isize;
        let diagonal = x - y;
        let previous_diagonal = if diagonal == -distance
            || (diagonal != distance
                && frontier[(diagonal - 1 + distance) as usize]
                    < frontier[(diagonal + 1 + distance) as usize])
        {
            diagonal + 1
        } else {
            diagonal - 1
        };
        let previous_x = if previous_diagonal < -distance || previous_diagonal > distance {
            0
        } else {
            *frontier
                .get((previous_diagonal + distance) as usize)
                .ok_or(MergeError::InvalidDiff)?
        };
        let previous_y = previous_x - previous_diagonal;

        while x > previous_x && y > previous_y {
            reversed.push(Edit::Equal);
            x -= 1;
            y -= 1;
        }
        if distance == 0 {
            break;
        }
        if x == previous_x {
            reversed.push(Edit::Insert);
            y -= 1;
        } else {
            reversed.push(Edit::Delete);
            x -= 1;
        }
    }
    while x > 0 && y > 0 {
        reversed.push(Edit::Equal);
        x -= 1;
        y -= 1;
    }
    while x > 0 {
        reversed.push(Edit::Delete);
        x -= 1;
    }
    while y > 0 {
        reversed.push(Edit::Insert);
        y -= 1;
    }
    reversed.reverse();
    Ok(reversed)
}

fn changes_for_side(changes: &[Change], side: InputSide) -> Vec<Change> {
    changes
        .iter()
        .copied()
        .filter(|change| change.side == side)
        .collect()
}

fn has_cross_side_overlap(input1: &[Change], input2: &[Change]) -> bool {
    let (mut i, mut j) = (0, 0);
    while i < input1.len() && j < input2.len() {
        let left = input1[i];
        let right = input2[j];
        if ranges_conflict(left, right) {
            return true;
        }
        if left.base_end <= right.base_start {
            i += 1;
        } else if right.base_end <= left.base_start {
            j += 1;
        } else if left.base_end <= right.base_end {
            i += 1;
        } else {
            j += 1;
        }
    }
    false
}

fn ranges_conflict(left: Change, right: Change) -> bool {
    let left_insert = left.base_start == left.base_end;
    let right_insert = right.base_start == right.base_end;
    match (left_insert, right_insert) {
        (true, true) => left.base_start == right.base_start,
        (true, false) => left.base_start > right.base_start && left.base_start < right.base_end,
        (false, true) => right.base_start > left.base_start && right.base_start < left.base_end,
        (false, false) => left.base_start < right.base_end && right.base_start < left.base_end,
    }
}

fn apply_changes(
    base: &[&str],
    input1: &[&str],
    input2: &[&str],
    start: usize,
    end: usize,
    changes: &[Change],
) -> Result<String, MergeError> {
    let capacity = changes
        .iter()
        .map(|change| match change.side {
            InputSide::Input1 => input1[change.input_start..change.input_end]
                .iter()
                .map(|line| line.len())
                .sum::<usize>(),
            InputSide::Input2 => input2[change.input_start..change.input_end]
                .iter()
                .map(|line| line.len())
                .sum::<usize>(),
        })
        .sum::<usize>()
        + base[start..end]
            .iter()
            .map(|line| line.len())
            .sum::<usize>();
    let mut output = String::with_capacity(capacity);
    let mut cursor = start;
    for change in changes {
        if change.base_start < cursor
            || change.base_start < start
            || change.base_end > end
            || change.input_start > change.input_end
        {
            return Err(MergeError::InvalidDiff);
        }
        append_lines(&mut output, &base[cursor..change.base_start]);
        let source = match change.side {
            InputSide::Input1 => input1,
            InputSide::Input2 => input2,
        };
        let replacement = source
            .get(change.input_start..change.input_end)
            .ok_or(MergeError::InvalidDiff)?;
        append_lines(&mut output, replacement);
        cursor = change.base_end;
    }
    append_lines(&mut output, &base[cursor..end]);
    Ok(output)
}

fn append_lines(output: &mut String, lines: &[&str]) {
    for line in lines {
        output.push_str(line);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn utf16_slice(text: &str, start: usize, end: usize) -> String {
        let units = text.encode_utf16().collect::<Vec<_>>();
        String::from_utf16(&units[start..end]).expect("range splits only at UTF-16 boundaries")
    }

    fn assert_conflict_ranges_match_result(merge: &MergeProjection) {
        let result = merge.result_text();
        let result_units = result.encode_utf16().count();
        for (conflict, start, end) in merge.conflicts_with_result_ranges() {
            assert!(start <= end);
            assert!(end <= result_units);
            let expected = match conflict.resolution {
                Some(InputSide::Input1) => &conflict.input1_text,
                Some(InputSide::Input2) => &conflict.input2_text,
                None => &conflict.base_text,
            };
            assert_eq!(utf16_slice(&result, start, end), expected.as_str());
        }
    }

    #[test]
    fn unchanged_input_returns_the_base_without_conflicts() {
        let merge = MergeProjection::new("one\ntwo\n", "one\ntwo\n", "one\ntwo\n")
            .expect("projection succeeds");

        assert_eq!(merge.result_text(), "one\ntwo\n");
        assert_eq!(merge.conflict_count(), 0);
        assert_eq!(merge.unresolved_conflict_count(), 0);
    }

    #[test]
    fn merges_one_sided_changes_from_both_inputs_including_adjacent_lines() {
        let merge = MergeProjection::new(
            "one\ntwo\nthree\nfour",
            "ONE\ntwo\nthree\nfour",
            "one\nTWO\nTHREE\nfour",
        )
        .expect("projection succeeds");

        assert_eq!(merge.result_text(), "ONE\nTWO\nTHREE\nfour");
        assert_eq!(merge.conflict_count(), 0);
    }

    #[test]
    fn identical_overlapping_edits_are_applied_once() {
        let merge =
            MergeProjection::new("a\nb\nc", "a\nB\nc", "a\nB\nc").expect("projection succeeds");

        assert_eq!(merge.result_text(), "a\nB\nc");
        assert_eq!(merge.unresolved_conflict_count(), 0);
    }

    #[test]
    fn divergent_overlap_starts_from_base_and_can_choose_either_input() {
        let mut merge = MergeProjection::new("a\nbase\nc\n", "a\nleft\nc\n", "a\nright\nc\n")
            .expect("projection succeeds");

        assert_eq!(merge.result_text(), "a\nbase\nc\n");
        assert_eq!(merge.conflict_count(), 1);
        assert_eq!(merge.unresolved_conflict_count(), 1);
        let conflict = merge.conflicts().next().expect("conflict exists");
        assert_eq!(conflict.id, 0);
        assert_eq!(conflict.base_text, "base\n");
        assert_eq!(conflict.input1_text, "left\n");
        assert_eq!(conflict.input2_text, "right\n");

        assert!(merge
            .accept_conflict(0, InputSide::Input2)
            .expect("known conflict"));
        assert_eq!(merge.result_text(), "a\nright\nc\n");
        assert_eq!(merge.unresolved_conflict_count(), 0);
        assert!(!merge
            .accept_conflict(0, InputSide::Input2)
            .expect("same choice is idempotent"));
        assert!(merge
            .accept_conflict(0, InputSide::Input1)
            .expect("known conflict can switch sides"));
        assert_eq!(merge.result_text(), "a\nleft\nc\n");
    }

    #[test]
    fn multiple_conflicts_keep_order_and_accept_all_changes_only_conflicts() {
        let mut merge = MergeProjection::new(
            "a\nb\nc\nd\ne",
            "a\nleft-1\nc\nleft-2\ne",
            "a\nright-1\nc\nright-2\ne",
        )
        .expect("projection succeeds");

        let conflicts: Vec<_> = merge.conflicts().map(|conflict| conflict.id).collect();
        assert_eq!(conflicts, [0, 1]);
        assert_eq!(merge.result_text(), "a\nb\nc\nd\ne");
        assert_eq!(merge.accept_all(InputSide::Input1), 2);
        assert_eq!(merge.result_text(), "a\nleft-1\nc\nleft-2\ne");
        assert_eq!(merge.unresolved_conflict_count(), 0);
        assert_eq!(merge.accept_all(InputSide::Input1), 0);
    }

    #[test]
    fn conflict_result_ranges_follow_current_utf16_projection_after_resolution() {
        let mut merge = MergeProjection::new(
            "\u{feff}😀\r\nold\r\nmiddle\rold2\n",
            "\u{feff}😀\r\nlonger 🦊\r\nmiddle\rours2\n",
            "\u{feff}😀\r\nincoming\r\nmiddle\rother2",
        )
        .expect("projection succeeds");
        let result_before = merge.result_text();
        let ranges_before = merge
            .conflicts_with_result_ranges()
            .map(|(conflict, start, end)| (conflict.id, start, end))
            .collect::<Vec<_>>();

        assert_eq!(ranges_before.len(), 2);
        assert_eq!(ranges_before[0].1, 5); // BOM + surrogate pair + CRLF
        assert_eq!(
            utf16_slice(&result_before, ranges_before[0].1, ranges_before[0].2),
            "old\r\n"
        );
        assert_conflict_ranges_match_result(&merge);

        merge
            .accept_conflict(0, InputSide::Input1)
            .expect("first conflict exists");
        let result_after = merge.result_text();
        let ranges_after = merge
            .conflicts_with_result_ranges()
            .map(|(conflict, start, end)| (conflict.id, start, end))
            .collect::<Vec<_>>();

        assert_eq!(ranges_after[0].1, ranges_before[0].1);
        assert_eq!(ranges_after[0].2 - ranges_after[0].1, 11);
        assert_eq!(ranges_after[1].1, ranges_before[1].1 + 6);
        assert_eq!(
            utf16_slice(&result_after, ranges_after[0].1, ranges_after[0].2),
            "longer 🦊\r\n"
        );
        assert_conflict_ranges_match_result(&merge);

        merge
            .accept_conflict(1, InputSide::Input2)
            .expect("second conflict exists");
        let final_result = merge.result_text();
        let final_range = merge
            .conflicts_with_result_ranges()
            .map(|(_, start, end)| (start, end))
            .nth(1)
            .expect("second conflict exists");
        assert_eq!(
            utf16_slice(&final_result, final_range.0, final_range.1),
            "other2"
        );
        assert!(!final_result.ends_with('\n'));
        assert_conflict_ranges_match_result(&merge);
    }

    #[test]
    fn conflict_result_ranges_allow_empty_deletion_contributions() {
        let mut merge = MergeProjection::new(
            "prefix\nremoved\nsuffix\n",
            "prefix\nsuffix\n",
            "prefix\nchanged\nsuffix\n",
        )
        .expect("projection succeeds");
        let unresolved_range = merge
            .conflicts_with_result_ranges()
            .map(|(_, start, end)| (start, end))
            .next()
            .expect("conflict exists");
        assert!(unresolved_range.0 < unresolved_range.1);
        assert_conflict_ranges_match_result(&merge);

        merge
            .accept_conflict(0, InputSide::Input1)
            .expect("deletion side exists");
        let deletion_range = merge
            .conflicts_with_result_ranges()
            .map(|(_, start, end)| (start, end))
            .next()
            .expect("conflict exists");
        assert_eq!(deletion_range.0, deletion_range.1);
        assert_eq!(merge.result_text(), "prefix\nsuffix\n");
        assert_conflict_ranges_match_result(&merge);

        merge
            .accept_conflict(0, InputSide::Input2)
            .expect("replacement side exists");
        let replacement_range = merge
            .conflicts_with_result_ranges()
            .map(|(_, start, end)| (start, end))
            .next()
            .expect("conflict exists");
        assert_eq!(replacement_range.1 - replacement_range.0, 8);
        assert_conflict_ranges_match_result(&merge);

        let mut insertion = MergeProjection::new(
            "before\nafter\n",
            "before\nours\nafter\n",
            "before\ntheirs\nafter\n",
        )
        .expect("projection succeeds");
        let unresolved_insertion = insertion
            .conflicts_with_result_ranges()
            .map(|(_, start, end)| (start, end))
            .next()
            .expect("insertion conflict exists");
        assert_eq!(unresolved_insertion, (7, 7));
        assert_conflict_ranges_match_result(&insertion);

        insertion
            .accept_conflict(0, InputSide::Input2)
            .expect("inserted text side exists");
        let resolved_result = insertion.result_text();
        let resolved_insertion = insertion
            .conflicts_with_result_ranges()
            .map(|(_, start, end)| (start, end))
            .next()
            .expect("insertion conflict exists");
        assert_eq!(resolved_insertion, (7, 14));
        assert_eq!(
            utf16_slice(&resolved_result, resolved_insertion.0, resolved_insertion.1),
            "theirs\n"
        );
        assert_conflict_ranges_match_result(&insertion);
    }

    #[test]
    fn adjacent_nonconflicting_edit_survives_resolution_of_neighboring_conflict() {
        let mut merge = MergeProjection::new("a\nb\nc\nd", "a\nleft\nC1\nd", "a\nright\nc\nD2")
            .expect("projection succeeds");

        assert_eq!(merge.unresolved_conflict_count(), 1);
        assert_eq!(merge.result_text(), "a\nb\nc\nD2");
        merge.accept_all(InputSide::Input1);
        assert_eq!(merge.result_text(), "a\nleft\nC1\nD2");
    }

    #[test]
    fn nonoverlapping_insert_and_delete_are_combined() {
        let merge = MergeProjection::new("a\nb\nc\nd\n", "a\nc\nd\n", "a\nb\nc\nx\nd\n")
            .expect("projection succeeds");

        assert_eq!(merge.result_text(), "a\nc\nx\nd\n");
        assert_eq!(merge.unresolved_conflict_count(), 0);
    }

    #[test]
    fn empty_input_and_final_newline_state_are_preserved() {
        let inserted = MergeProjection::new("", "new", "").expect("projection succeeds");
        let no_final_newline =
            MergeProjection::new("a\nb", "A\nb", "a\nb").expect("projection succeeds");

        assert_eq!(inserted.result_text(), "new");
        assert_eq!(no_final_newline.result_text(), "A\nb");
    }

    #[test]
    fn preserves_bom_emoji_crlf_and_cr_slices_verbatim() {
        let base = "\u{feff}fn main() {\r\n  println!(\"base 🙂\");\r\n}\r\n";
        let input1 = base.replace("base", "local");
        let input2 = base.replace("}\r\n", "// remote\r\n}\r\n");
        let merge = MergeProjection::new(base, &input1, &input2).expect("projection succeeds");
        assert_eq!(
            merge.result_text(),
            "\u{feff}fn main() {\r\n  println!(\"local 🙂\");\r\n// remote\r\n}\r\n"
        );

        let cr_base = "a\rb\rc\r";
        let cr_merge =
            MergeProjection::new(cr_base, "A\rb\rc\r", "a\rb\rC\r").expect("projection succeeds");
        assert_eq!(cr_merge.result_text(), "A\rb\rC\r");
    }

    #[test]
    fn small_change_distance_on_a_large_file_fits_the_trace_bound() {
        let base_lines: Vec<String> = (0..5_000).map(|line| format!("line-{line}")).collect();
        let base = base_lines.join("\n");
        let mut input1_lines = base_lines.clone();
        input1_lines[100] = "local-change".into();
        let mut input2_lines = base_lines;
        input2_lines[4_900] = "remote-change".into();
        let input1 = input1_lines.join("\n");
        let input2 = input2_lines.join("\n");

        let merge = MergeProjection::new(&base, &input1, &input2)
            .expect("low-distance large projection fits limits");
        let mut expected = input1_lines;
        expected[4_900] = "remote-change".into();
        assert_eq!(merge.result_text(), expected.join("\n"));
        assert_eq!(merge.unresolved_conflict_count(), 0);
    }

    #[test]
    fn insertion_inside_another_inputs_replacement_is_explicitly_conflicted() {
        let mut merge = MergeProjection::new("a\nb\nc\nd", "a\nb\ninserted\nc\nd", "a\nB\nC\nd")
            .expect("projection succeeds");

        assert_eq!(merge.unresolved_conflict_count(), 1);
        assert_eq!(merge.result_text(), "a\nb\nc\nd");
        merge.accept_all(InputSide::Input1);
        assert_eq!(merge.result_text(), "a\nb\ninserted\nc\nd");
    }

    #[test]
    fn each_resource_bound_fails_without_returning_a_partial_projection() {
        let base = MergeLimits {
            max_total_input_bytes: 3,
            ..MergeLimits::default()
        };
        assert_eq!(
            MergeProjection::with_limits("a", "bb", "a", base),
            Err(MergeError::InputByteLimit)
        );

        let line_limit = MergeLimits {
            max_lines_per_input: 1,
            ..MergeLimits::default()
        };
        assert_eq!(
            MergeProjection::with_limits("a", "a\nb", "a", line_limit),
            Err(MergeError::LineLimit)
        );

        let trace_limit = MergeLimits {
            max_trace_cells: 8,
            ..MergeLimits::default()
        };
        assert_eq!(
            MergeProjection::with_limits("a", "b", "a", trace_limit),
            Err(MergeError::TraceLimit)
        );

        let work_limit = MergeLimits {
            max_work: 0,
            ..MergeLimits::default()
        };
        assert_eq!(
            MergeProjection::with_limits("a", "b", "a", work_limit),
            Err(MergeError::WorkLimit)
        );

        let conflict_limit = MergeLimits {
            max_conflicts: 0,
            ..MergeLimits::default()
        };
        assert_eq!(
            MergeProjection::with_limits("base", "left", "right", conflict_limit),
            Err(MergeError::ConflictLimit)
        );

        let projection_limit = MergeLimits {
            max_projection_bytes: 8,
            ..MergeLimits::default()
        };
        assert_eq!(
            MergeProjection::with_limits("abc", "def", "ghi", projection_limit),
            Err(MergeError::ProjectionLimit)
        );
    }

    #[test]
    fn unknown_conflict_is_rejected_without_changing_projection() {
        let mut merge = MergeProjection::new("base", "left", "right").expect("projection succeeds");
        let before = merge.result_text();

        assert_eq!(
            merge.accept_conflict(9, InputSide::Input1),
            Err(MergeError::UnknownConflict(9))
        );
        assert_eq!(merge.result_text(), before);
        assert_eq!(merge.unresolved_conflict_count(), 1);
    }

    #[test]
    fn deterministic_small_projections_preserve_single_side_and_equal_side_inputs() {
        let values = ["a", "b", "", "😊"];
        let mut seed = 0x19_u32;
        let mut next = || {
            seed = seed.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
            seed
        };
        let mut make_text = || {
            let count = (next() % 7) as usize;
            let mut lines = Vec::with_capacity(count);
            for _ in 0..count {
                lines.push(values[(next() as usize) % values.len()]);
            }
            lines.join("\n")
        };

        for _ in 0..200 {
            let base = make_text();
            let input = make_text();
            let from_input1 = MergeProjection::new(&base, &input, &base)
                .expect("single-sided projection succeeds");
            let from_input2 = MergeProjection::new(&base, &base, &input)
                .expect("single-sided projection succeeds");
            let identical = MergeProjection::new(&base, &input, &input)
                .expect("identical-side projection succeeds");

            assert_eq!(from_input1.result_text(), input);
            assert_eq!(from_input2.result_text(), input);
            assert_eq!(identical.result_text(), input);
            assert_eq!(identical.unresolved_conflict_count(), 0);
        }
    }
}
