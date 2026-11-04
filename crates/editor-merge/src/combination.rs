//! Bounded smart-combination candidate planning for one three-way conflict.
//!
//! This module is deliberately independent from MergeProjection: it computes
//! a candidate without changing the projection or its conflict resolutions.

use std::error::Error;
use std::fmt;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CombinationLimits {
    /// Sum of the UTF-8 byte lengths of the base and both inputs.
    pub max_total_input_bytes: usize,
    /// Total Myers frontier cells retained or being constructed.
    pub max_trace_cells: usize,
    /// Frontier steps and character comparisons across both diffs.
    pub max_work: usize,
}

impl Default for CombinationLimits {
    fn default() -> Self {
        Self {
            max_total_input_bytes: 2 * 1024 * 1024,
            max_trace_cells: 1_000_000,
            max_work: 2_000_000,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CombinationError {
    InputByteLimit,
    TraceLimit,
    WorkLimit,
    InvalidDiff,
}

impl fmt::Display for CombinationError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InputByteLimit => write!(f, "merge combination input byte limit exceeded"),
            Self::TraceLimit => write!(f, "merge combination diff trace limit exceeded"),
            Self::WorkLimit => write!(f, "merge combination work limit exceeded"),
            Self::InvalidDiff => write!(f, "merge combination diff ranges are inconsistent"),
        }
    }
}

impl Error for CombinationError {}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
enum InputSide {
    Input1,
    Input2,
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

/// Compute a complete candidate from non-overlapping edits in both inputs.
///
/// Same-position edits are emitted in Input 1 then Input 2 order, including
/// insertions. If either input is unchanged or the edit sets overlap, there is
/// no smart-combination candidate.
pub fn combine_conflict(
    base: &str,
    input1: &str,
    input2: &str,
    limits: CombinationLimits,
) -> Result<Option<String>, CombinationError> {
    let input_bytes = base
        .len()
        .checked_add(input1.len())
        .and_then(|sum| sum.checked_add(input2.len()))
        .ok_or(CombinationError::InputByteLimit)?;
    if input_bytes > limits.max_total_input_bytes {
        return Err(CombinationError::InputByteLimit);
    }
    if input1 == base || input2 == base {
        return Ok(None);
    }

    // Rust chars are Unicode scalar values, so the planner never creates an
    // edit boundary inside a UTF-8 sequence or a UTF-16 surrogate pair.
    let base_chars: Vec<char> = base.chars().collect();
    let input1_chars: Vec<char> = input1.chars().collect();
    let input2_chars: Vec<char> = input2.chars().collect();
    let mut trace_cells = 0;
    let mut work = 0;

    let changes1 = compute_changes(
        &base_chars,
        &input1_chars,
        InputSide::Input1,
        limits,
        &mut trace_cells,
        &mut work,
    )?;
    let changes2 = compute_changes(
        &base_chars,
        &input2_chars,
        InputSide::Input2,
        limits,
        &mut trace_cells,
        &mut work,
    )?;

    if has_cross_side_overlap(&changes1, &changes2) {
        return Ok(None);
    }

    let mut changes = Vec::with_capacity(changes1.len() + changes2.len());
    let (mut index1, mut index2) = (0, 0);
    while index1 < changes1.len() && index2 < changes2.len() {
        if change_order(changes1[index1], changes2[index2]) != std::cmp::Ordering::Greater {
            changes.push(changes1[index1]);
            index1 += 1;
        } else {
            changes.push(changes2[index2]);
            index2 += 1;
        }
    }
    changes.extend_from_slice(&changes1[index1..]);
    changes.extend_from_slice(&changes2[index2..]);

    let mut output = String::with_capacity(input_bytes);
    let mut base_cursor = 0;
    let mut change_index = 0;
    while change_index < changes.len() {
        let start = changes[change_index].base_start;
        if start < base_cursor || start > base_chars.len() {
            return Ok(None);
        }
        append_chars(&mut output, &base_chars[base_cursor..start]);

        let mut group_end = change_index + 1;
        while group_end < changes.len() && changes[group_end].base_start == start {
            group_end += 1;
        }

        let mut next_base_cursor = start;
        for change in &changes[change_index..group_end] {
            if change.base_end < change.base_start
                || change.base_end > base_chars.len()
                || change.input_start > change.input_end
            {
                return Ok(None);
            }
            let Some(replacement) = (match change.side {
                InputSide::Input1 => input1_chars.get(change.input_start..change.input_end),
                InputSide::Input2 => input2_chars.get(change.input_start..change.input_end),
            }) else {
                return Ok(None);
            };
            append_chars(&mut output, replacement);

            if change.base_end > start {
                if next_base_cursor != start {
                    return Err(CombinationError::InvalidDiff);
                }
                next_base_cursor = change.base_end;
            }
        }

        base_cursor = next_base_cursor;
        change_index = group_end;
    }
    append_chars(&mut output, &base_chars[base_cursor..]);
    Ok(Some(output))
}

fn change_order(left: Change, right: Change) -> std::cmp::Ordering {
    left.base_start
        .cmp(&right.base_start)
        .then_with(|| left.side.cmp(&right.side))
        .then_with(|| left.base_end.cmp(&right.base_end))
        .then_with(|| left.input_start.cmp(&right.input_start))
}

fn append_chars(output: &mut String, chars: &[char]) {
    for character in chars {
        output.push(*character);
    }
}

fn compute_changes(
    base: &[char],
    input: &[char],
    side: InputSide,
    limits: CombinationLimits,
    trace_cells: &mut usize,
    work: &mut usize,
) -> Result<Vec<Change>, CombinationError> {
    let edits = myers_edits(base, input, limits, trace_cells, work)?;
    let mut changes = Vec::new();
    let (mut base_index, mut input_index) = (0, 0);
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
    if base_index != base.len() || input_index != input.len() {
        return Err(CombinationError::InvalidDiff);
    }
    if changes
        .windows(2)
        .any(|pair| pair[1].base_start < pair[0].base_end)
    {
        return Err(CombinationError::InvalidDiff);
    }
    Ok(changes)
}

fn myers_edits(
    original: &[char],
    modified: &[char],
    limits: CombinationLimits,
    trace_cells: &mut usize,
    work: &mut usize,
) -> Result<Vec<Edit>, CombinationError> {
    if original == modified {
        return Ok(Vec::new());
    }

    let max_distance = original
        .len()
        .checked_add(modified.len())
        .ok_or(CombinationError::TraceLimit)?;
    let max_distance = isize::try_from(max_distance).map_err(|_| CombinationError::TraceLimit)?;
    let mut trace: Vec<Vec<isize>> = Vec::new();

    for distance in 0..=max_distance {
        let width = usize::try_from(
            distance
                .checked_mul(2)
                .and_then(|value| value.checked_add(1))
                .ok_or(CombinationError::TraceLimit)?,
        )
        .map_err(|_| CombinationError::TraceLimit)?;
        let next_trace_cells = trace_cells
            .checked_add(width)
            .ok_or(CombinationError::TraceLimit)?;
        if next_trace_cells > limits.max_trace_cells {
            return Err(CombinationError::TraceLimit);
        }

        let mut frontier = Vec::with_capacity(width);
        let mut diagonal = -distance;
        let mut reached_end = false;
        while diagonal <= distance {
            charge_work(work, limits.max_work)?;
            let mut x = if distance == 0 {
                0
            } else {
                let previous = trace.last().ok_or(CombinationError::InvalidDiff)?;
                let previous_distance = distance - 1;
                if diagonal == -distance
                    || (diagonal != distance
                        && frontier_at(previous, previous_distance, diagonal - 1)?
                            < frontier_at(previous, previous_distance, diagonal + 1)?)
                {
                    frontier_at(previous, previous_distance, diagonal + 1)?
                } else {
                    frontier_at(previous, previous_distance, diagonal - 1)? + 1
                }
            };
            let mut y = x - diagonal;
            while x >= 0
                && y >= 0
                && usize::try_from(x).is_ok_and(|index| index < original.len())
                && usize::try_from(y).is_ok_and(|index| index < modified.len())
            {
                charge_work(work, limits.max_work)?;
                if original[x as usize] != modified[y as usize] {
                    break;
                }
                x += 1;
                y += 1;
            }
            frontier.push(x);
            if x >= original.len() as isize && y >= modified.len() as isize {
                reached_end = true;
                break;
            }
            diagonal += 2;
        }

        *trace_cells = next_trace_cells;
        if reached_end {
            return backtrack(&trace, original, modified);
        }
        trace.push(frontier);
    }
    Err(CombinationError::InvalidDiff)
}

fn frontier_at(
    frontier: &[isize],
    distance: isize,
    diagonal: isize,
) -> Result<isize, CombinationError> {
    let offset = diagonal
        .checked_add(distance)
        .ok_or(CombinationError::InvalidDiff)?;
    if offset < 0 || offset % 2 != 0 {
        return Err(CombinationError::InvalidDiff);
    }
    frontier
        .get((offset / 2) as usize)
        .copied()
        .ok_or(CombinationError::InvalidDiff)
}

fn charge_work(work: &mut usize, max_work: usize) -> Result<(), CombinationError> {
    *work = work.checked_add(1).ok_or(CombinationError::WorkLimit)?;
    if *work > max_work {
        return Err(CombinationError::WorkLimit);
    }
    Ok(())
}

fn backtrack(
    trace: &[Vec<isize>],
    original: &[char],
    modified: &[char],
) -> Result<Vec<Edit>, CombinationError> {
    let mut x = isize::try_from(original.len()).map_err(|_| CombinationError::InvalidDiff)?;
    let mut y = isize::try_from(modified.len()).map_err(|_| CombinationError::InvalidDiff)?;
    let mut reversed = Vec::new();

    for distance in (1..=trace.len()).rev() {
        let previous = &trace[distance - 1];
        let distance = isize::try_from(distance).map_err(|_| CombinationError::InvalidDiff)?;
        let diagonal = x - y;
        let previous_distance = distance - 1;
        let previous_diagonal = if diagonal == -distance
            || (diagonal != distance
                && frontier_at(previous, previous_distance, diagonal - 1)?
                    < frontier_at(previous, previous_distance, diagonal + 1)?)
        {
            diagonal + 1
        } else {
            diagonal - 1
        };
        let previous_x = frontier_at(previous, previous_distance, previous_diagonal)?;
        let previous_y = previous_x - previous_diagonal;

        while x > previous_x && y > previous_y {
            if original[(x - 1) as usize] != modified[(y - 1) as usize] {
                return Err(CombinationError::InvalidDiff);
            }
            reversed.push(Edit::Equal);
            x -= 1;
            y -= 1;
        }
        if x == previous_x {
            reversed.push(Edit::Insert);
        } else {
            reversed.push(Edit::Delete);
        }
        x = previous_x;
        y = previous_y;
    }

    while x > 0 && y > 0 {
        if original[(x - 1) as usize] != modified[(y - 1) as usize] {
            return Err(CombinationError::InvalidDiff);
        }
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

fn has_cross_side_overlap(input1: &[Change], input2: &[Change]) -> bool {
    let (mut index1, mut index2) = (0, 0);
    while index1 < input1.len() && index2 < input2.len() {
        let left = input1[index1];
        let right = input2[index2];
        if changes_overlap(left, right) {
            return true;
        }

        let left_end = left.base_end;
        let right_end = right.base_end;
        if left_end <= right_end {
            index1 += 1;
        }
        if right_end <= left_end {
            index2 += 1;
        }
    }
    false
}

fn changes_overlap(left: Change, right: Change) -> bool {
    let left_insertion = left.base_start == left.base_end;
    let right_insertion = right.base_start == right.base_end;
    match (left_insertion, right_insertion) {
        (true, true) => false,
        (true, false) => right.base_start < left.base_start && left.base_start < right.base_end,
        (false, true) => left.base_start < right.base_start && right.base_start < left.base_end,
        (false, false) => left.base_start < right.base_end && right.base_start < left.base_end,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn limits() -> CombinationLimits {
        CombinationLimits::default()
    }

    #[test]
    fn combines_non_overlapping_changes_on_one_line() {
        assert_eq!(
            combine_conflict("abc", "Abc", "abC", limits()).unwrap(),
            Some("AbC".to_owned())
        );
    }

    #[test]
    fn combines_non_overlapping_changes_across_lines() {
        assert_eq!(
            combine_conflict("a\nb\nc", "A\nb\nc", "a\nb\nC", limits()).unwrap(),
            Some("A\nb\nC".to_owned())
        );
    }

    #[test]
    fn overlapping_and_duplicate_replacements_have_no_candidate() {
        assert_eq!(
            combine_conflict("abc", "axc", "ayc", limits()).unwrap(),
            None
        );
        assert_eq!(
            combine_conflict("abc", "axc", "axc", limits()).unwrap(),
            None
        );
        assert_eq!(
            combine_conflict("abcdef", "aef", "abf", limits()).unwrap(),
            None
        );
    }

    #[test]
    fn same_position_insertions_follow_input_order() {
        assert_eq!(
            combine_conflict("ab", "a1b", "a2b", limits()).unwrap(),
            Some("a12b".to_owned())
        );
        assert_eq!(
            combine_conflict("ab", "Xb", "1ab", limits()).unwrap(),
            Some("X1b".to_owned())
        );
        assert_eq!(
            combine_conflict("ab", "1ab", "Xb", limits()).unwrap(),
            Some("1Xb".to_owned())
        );
    }

    #[test]
    fn insertion_at_a_deletion_boundary_combines_but_interior_insertions_do_not() {
        assert_eq!(
            combine_conflict("abc", "ac", "abC", limits()).unwrap(),
            Some("aC".to_owned())
        );
        assert_eq!(
            combine_conflict("abcd", "aXd", "abcYd", limits()).unwrap(),
            Some("aXYd".to_owned())
        );
        assert_eq!(
            combine_conflict("abcd", "aXd", "abYcd", limits()).unwrap(),
            None
        );
    }

    #[test]
    fn unchanged_and_empty_inputs_are_handled_without_partial_candidates() {
        assert_eq!(
            combine_conflict("base", "left", "base", limits()).unwrap(),
            None
        );
        assert_eq!(combine_conflict("", "left", "", limits()).unwrap(), None);
        assert_eq!(
            combine_conflict("", "left", "right", limits()).unwrap(),
            Some("leftright".to_owned())
        );
        assert_eq!(
            combine_conflict("a\nb", "A\nb", "a\nB", limits()).unwrap(),
            Some("A\nB".to_owned())
        );
    }

    #[test]
    fn preserves_bom_unicode_and_original_line_endings() {
        let base = "\u{feff}a😀b\r\nc\r\n";
        let input1 = "\u{feff}A😀b\r\nc\r\n";
        let input2 = "\u{feff}a😀B\r\nc\r\n";
        let original_inputs = (base.to_owned(), input1.to_owned(), input2.to_owned());
        assert_eq!(
            combine_conflict(base, input1, input2, limits()).unwrap(),
            Some("\u{feff}A😀B\r\nc\r\n".to_owned())
        );
        assert_eq!(
            (base, input1, input2),
            (
                original_inputs.0.as_str(),
                original_inputs.1.as_str(),
                original_inputs.2.as_str()
            )
        );

        let cr_base = "a\rb\rc\r";
        assert_eq!(
            combine_conflict(cr_base, "A\rb\rc\r", "a\rb\rC\r", limits()).unwrap(),
            Some("A\rb\rC\r".to_owned())
        );
    }

    #[test]
    fn enforces_byte_trace_and_work_limits_at_their_boundaries() {
        let base = "a";
        let input1 = "b";
        let input2 = "c";

        assert_eq!(
            combine_conflict(
                base,
                input1,
                input2,
                CombinationLimits {
                    max_total_input_bytes: 3,
                    max_trace_cells: 18,
                    max_work: 12,
                },
            )
            .unwrap(),
            None
        );
        assert_eq!(
            combine_conflict(
                base,
                input1,
                input2,
                CombinationLimits {
                    max_total_input_bytes: 2,
                    ..limits()
                },
            ),
            Err(CombinationError::InputByteLimit)
        );
        assert_eq!(
            combine_conflict(
                base,
                input1,
                input2,
                CombinationLimits {
                    max_trace_cells: 17,
                    ..limits()
                },
            ),
            Err(CombinationError::TraceLimit)
        );
        assert_eq!(
            combine_conflict(
                base,
                input1,
                input2,
                CombinationLimits {
                    max_work: 11,
                    ..limits()
                },
            ),
            Err(CombinationError::WorkLimit)
        );
    }

    #[test]
    fn myers_scripts_reconstruct_small_unicode_scalar_sequences() {
        let sequences = all_sequences(&['a', 'b', '😀'], 3);
        for original in &sequences {
            for modified in &sequences {
                let mut trace_cells = 0;
                let mut work = 0;
                let edits = myers_edits(
                    original,
                    modified,
                    CombinationLimits {
                        max_trace_cells: 10_000,
                        max_work: 10_000,
                        ..limits()
                    },
                    &mut trace_cells,
                    &mut work,
                )
                .unwrap();
                if original == modified {
                    assert!(edits.is_empty());
                    continue;
                }

                let (mut original_index, mut modified_index) = (0, 0);
                let mut reconstructed = Vec::new();
                for edit in edits {
                    match edit {
                        Edit::Equal => {
                            assert_eq!(original[original_index], modified[modified_index]);
                            reconstructed.push(original[original_index]);
                            original_index += 1;
                            modified_index += 1;
                        }
                        Edit::Delete => original_index += 1,
                        Edit::Insert => {
                            reconstructed.push(modified[modified_index]);
                            modified_index += 1;
                        }
                    }
                }
                assert_eq!(original_index, original.len());
                assert_eq!(modified_index, modified.len());
                assert_eq!(reconstructed, *modified);
            }
        }
    }

    fn all_sequences(alphabet: &[char], max_len: usize) -> Vec<Vec<char>> {
        let mut sequences = vec![Vec::new()];
        let mut level = vec![Vec::new()];
        for _ in 0..max_len {
            let mut next = Vec::new();
            for prefix in &level {
                for character in alphabet {
                    let mut sequence = prefix.clone();
                    sequence.push(*character);
                    sequences.push(sequence.clone());
                    next.push(sequence);
                }
            }
            level = next;
        }
        sequences
    }
}
