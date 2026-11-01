//! Alula Code 的文本缓冲区：Ropey 之上的增量操作层。
//!
//! 坐标口径（见 docs/02-关键技术设计 §2.3）：跨 FFI / LSP 边界的 offset 一律使用
//! UTF-16 code unit；本 crate 负责向 Ropey 的 char 索引换算，并拒绝落在
//! 代理对中间等非法边界上的操作。

use regex::{Captures, Regex};
use ropey::{Rope, RopeSlice};
use serde::{Deserialize, Serialize};
use std::sync::OnceLock;

/// Maximum UTF-16 units requested by one bounded document read.
pub const MAX_READ_RANGE_UTF16: usize = 64 * 1024;
/// Maximum number of line windows returned by one editor viewport request.
pub const MAX_READ_LINES: usize = 256;
/// Maximum rows returned for one rectangular editor selection.
pub const MAX_COLUMN_SELECTIONS: usize = 10_000;
/// Maximum number of caret positions accepted by one word-delete query.
pub const MAX_WORD_DELETE_CARETS: usize = 10_000;
/// Maximum number of selections accepted by one line-delete query.
pub const MAX_LINE_DELETE_RANGES: usize = 10_000;
/// Maximum number of caret positions accepted by one transpose query.
pub const MAX_TRANSPOSE_CARETS: usize = 10_000;
/// Maximum number of selections accepted by one overtype-paste query.
pub const MAX_OVERTYPE_PASTE_RANGES: usize = 10_000;
/// Maximum number of representative lines returned by one minimap snapshot.
pub const MAX_MINIMAP_SAMPLE_LINES: usize = 512;
/// Maximum text kept for each representative minimap line, in UTF-16 units.
pub const MAX_MINIMAP_LINE_SAMPLE_UTF16: usize = 48;

const WORD_SEPARATORS: &str = "`~!@#$%^&*()-=+[{]}\\|;:'\",.<>/?";

/// Apply Unicode full case mappings to a text fragment.
pub fn transform_case_text(text: &str, uppercase: bool) -> String {
    if uppercase {
        text.to_uppercase()
    } else {
        text.to_lowercase()
    }
}

static TITLE_CASE_BOUNDARY: OnceLock<Option<Regex>> = OnceLock::new();

fn title_case_boundary() -> Option<&'static Regex> {
    TITLE_CASE_BOUNDARY
        .get_or_init(|| Regex::new(r"(?m)(^|[^\p{L}\p{N}']|((^|\P{L})'))\p{L}").ok())
        .as_ref()
}

/// Apply the fixed Code-OSS Unicode title-boundary transform to a text fragment.
pub fn transform_title_case_text(text: &str) -> String {
    let Some(boundary) = title_case_boundary() else {
        return text.to_owned();
    };
    let lowered = text.to_lowercase();
    boundary
        .replace_all(&lowered, |captures: &Captures<'_>| {
            captures[0].to_uppercase()
        })
        .into_owned()
}

struct CamelCasePatterns {
    single_line_word_boundary: Regex,
    multi_line_word_boundary: Regex,
    valid_word_start: Regex,
}

static CAMEL_CASE_PATTERNS: OnceLock<Option<CamelCasePatterns>> = OnceLock::new();

fn camel_case_patterns() -> Option<&'static CamelCasePatterns> {
    CAMEL_CASE_PATTERNS
        .get_or_init(|| {
            Some(CamelCasePatterns {
                single_line_word_boundary: Regex::new(
                    r"[_\t-\r \u{00A0}\u{1680}\u{2000}-\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}-]+",
                )
                .ok()?,
                multi_line_word_boundary: Regex::new(r"[_-]+").ok()?,
                // Code-OSS uses ^ with the multiline flag and lowercases the
                // matched uppercase letter plus its following non-uppercase
                // code point. Include all ECMAScript line terminators because
                // Rust's multiline anchor only recognizes LF.
                valid_word_start: Regex::new(r"(^|[\r\n\u{2028}\u{2029}])(\p{Lu}[^\p{Lu}])")
                    .ok()?,
            })
        })
        .as_ref()
}

fn uppercase_first_utf16_code_unit(text: &str) -> String {
    let Some(first) = text.chars().next() else {
        return String::new();
    };
    // The upstream implementation calls substring(0, 1) before uppercasing.
    // A supplementary scalar is therefore passed as a lone surrogate and is
    // left unchanged by JavaScript; preserve it rather than casing the scalar.
    if first.len_utf16() != 1 {
        return text.to_owned();
    }
    let mut result = first.to_uppercase().collect::<String>();
    result.push_str(&text[first.len_utf8()..]);
    result
}

/// Apply the fixed Code-OSS Unicode camel-case transform to a text fragment.
pub fn transform_camel_case_text(text: &str) -> String {
    let Some(patterns) = camel_case_patterns() else {
        return text.to_owned();
    };
    let boundary = if text.contains(['\r', '\n']) {
        &patterns.multi_line_word_boundary
    } else {
        &patterns.single_line_word_boundary
    };
    let mut words = boundary.split(text);
    let Some(first_word) = words.next() else {
        return String::new();
    };
    let first_word = patterns
        .valid_word_start
        .replace_all(first_word, |captures: &Captures<'_>| {
            format!("{}{}", &captures[1], captures[2].to_lowercase())
        });
    let mut result = first_word.into_owned();
    for word in words {
        result.push_str(&uppercase_first_utf16_code_unit(word));
    }
    result
}

struct SnakeCasePatterns {
    case_boundary: Regex,
    single_letters: Regex,
}

static SNAKE_CASE_PATTERNS: OnceLock<Option<SnakeCasePatterns>> = OnceLock::new();

fn snake_case_patterns() -> Option<&'static SnakeCasePatterns> {
    SNAKE_CASE_PATTERNS
        .get_or_init(|| {
            Some(SnakeCasePatterns {
                case_boundary: Regex::new(r"(\p{Ll})(\p{Lu})").ok()?,
                single_letters: Regex::new(r"(\p{Lu}|\p{N})(\p{Lu})(\p{Ll})").ok()?,
            })
        })
        .as_ref()
}

/// Apply the fixed Code-OSS Unicode snake-case transform to a text fragment.
pub fn transform_snake_case_text(text: &str) -> String {
    let Some(patterns) = snake_case_patterns() else {
        return text.to_owned();
    };
    let case_boundaries = patterns
        .case_boundary
        .replace_all(text, |captures: &Captures<'_>| {
            format!("{}_{}", &captures[1], &captures[2])
        });
    patterns
        .single_letters
        .replace_all(case_boundaries.as_ref(), |captures: &Captures<'_>| {
            format!("{}_{}{}", &captures[1], &captures[2], &captures[3])
        })
        .to_lowercase()
}

struct PascalCasePatterns {
    word_boundary: Regex,
    upper_case_word: Regex,
}

static PASCAL_CASE_PATTERNS: OnceLock<Option<PascalCasePatterns>> = OnceLock::new();

fn pascal_case_patterns() -> Option<&'static PascalCasePatterns> {
    PASCAL_CASE_PATTERNS
        .get_or_init(|| {
            Some(PascalCasePatterns {
                // Code-OSS keeps dots attached to the preceding segment and
                // only treats underscore, ASCII space, tab, and hyphen as
                // word separators.
                word_boundary: Regex::new(r"[_ \t-]+").ok()?,
                // JavaScript's multiline anchors also recognize CR, U+2028,
                // and U+2029. Rust regex's multiline anchors recognize LF only.
                upper_case_word: Regex::new(
                    r"(?:^|[\r\n\u{2028}\u{2029}])\p{Lu}+(?:$|[\r\n\u{2028}\u{2029}])",
                )
                .ok()?,
            })
        })
        .as_ref()
}

fn pascal_case_word(word: &str, upper_case_word: &Regex) -> String {
    let Some(first_char) = word.chars().next() else {
        return String::new();
    };
    let suffix = &word[first_char.len_utf8()..];
    let first = if first_char.len_utf16() == 1 {
        first_char.to_uppercase().collect::<String>()
    } else {
        // JavaScript charAt(0) returns half of a surrogate pair, which case
        // mapping leaves untouched. Preserve the scalar as the visible result.
        first_char.to_string()
    };
    let mut result = first;
    if word.encode_utf16().count() > 1 && upper_case_word.is_match(word) {
        result.push_str(&suffix.to_lowercase());
    } else {
        result.push_str(suffix);
    }
    result
}

/// Apply the fixed Code-OSS Unicode Pascal-case transform to a text fragment.
pub fn transform_pascal_case_text(text: &str) -> String {
    let Some(patterns) = pascal_case_patterns() else {
        return text.to_owned();
    };

    let mut result = String::with_capacity(text.len());
    for segment in text.split_inclusive('.') {
        let mut words = patterns.word_boundary.split(segment);
        if let Some(first_word) = words.next() {
            result.push_str(&pascal_case_word(first_word, &patterns.upper_case_word));
        }
        for word in words {
            result.push_str(&pascal_case_word(word, &patterns.upper_case_word));
        }
    }
    result
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WordPartDirection {
    Left,
    Right,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WordDeleteDirection {
    Left,
    Right,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LineDeleteDirection {
    Left,
    Right,
}

/// A deletion range in absolute UTF-16 document coordinates.
#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct TextDeleteRange {
    pub start_utf16: usize,
    pub end_utf16: usize,
}

/// One Code-OSS transpose operation resolved against a Rust document snapshot.
#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct TextTransposePlan {
    pub start_utf16: usize,
    pub end_utf16: usize,
    pub removed_text: String,
    pub inserted_text: String,
}

#[derive(Debug, Clone, Copy)]
struct TransposeLineBounds {
    start_char: usize,
    end_char: usize,
    previous_line_end_char: Option<usize>,
    next_line_start_char: Option<usize>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct WordToken {
    start: usize,
    end: usize,
    is_separator: bool,
}

fn word_char_class(ch: char) -> Option<bool> {
    if ch == ' ' || ('\t'..='\r').contains(&ch) {
        return None;
    }
    Some(WORD_SEPARATORS.contains(ch))
}

fn delete_word_char_class(ch: char) -> Option<bool> {
    if ch == ' ' || ch == '\t' {
        return None;
    }
    Some(WORD_SEPARATORS.contains(ch))
}

fn delete_previous_word_token(line: RopeSlice<'_>, before: usize) -> Option<WordToken> {
    let mut index = before.min(line.len_chars());
    let class = loop {
        if index == 0 {
            return None;
        }
        index -= 1;
        if let Some(class) = delete_word_char_class(line.char(index)) {
            break class;
        }
    };

    let mut start = index;
    while start > 0 && delete_word_char_class(line.char(start - 1)) == Some(class) {
        start -= 1;
    }
    let mut end = index + 1;
    while end < line.len_chars() && delete_word_char_class(line.char(end)) == Some(class) {
        end += 1;
    }
    Some(WordToken {
        start,
        end,
        is_separator: class,
    })
}

fn delete_next_word_token(line: RopeSlice<'_>, from: usize) -> Option<WordToken> {
    let mut index = from.min(line.len_chars());
    let class = loop {
        if index == line.len_chars() {
            return None;
        }
        if let Some(class) = delete_word_char_class(line.char(index)) {
            break class;
        }
        index += 1;
    };

    let mut start = index;
    while start > 0 && delete_word_char_class(line.char(start - 1)) == Some(class) {
        start -= 1;
    }
    let mut end = index + 1;
    while end < line.len_chars() && delete_word_char_class(line.char(end)) == Some(class) {
        end += 1;
    }
    Some(WordToken {
        start,
        end,
        is_separator: class,
    })
}

fn previous_word_token(line: RopeSlice<'_>, before: usize) -> Option<WordToken> {
    let mut index = before.min(line.len_chars());
    let class = loop {
        if index == 0 {
            return None;
        }
        index -= 1;
        if let Some(class) = word_char_class(line.char(index)) {
            break class;
        }
    };

    let mut start = index;
    while start > 0 && word_char_class(line.char(start - 1)) == Some(class) {
        start -= 1;
    }
    let mut end = index + 1;
    while end < line.len_chars() && word_char_class(line.char(end)) == Some(class) {
        end += 1;
    }
    Some(WordToken {
        start,
        end,
        is_separator: class,
    })
}

fn next_word_token(line: RopeSlice<'_>, from: usize) -> Option<WordToken> {
    let mut index = from.min(line.len_chars());
    let class = loop {
        if index == line.len_chars() {
            return None;
        }
        if let Some(class) = word_char_class(line.char(index)) {
            break class;
        }
        index += 1;
    };

    let mut start = index;
    while start > 0 && word_char_class(line.char(start - 1)) == Some(class) {
        start -= 1;
    }
    let mut end = index + 1;
    while end < line.len_chars() && word_char_class(line.char(end)) == Some(class) {
        end += 1;
    }
    Some(WordToken {
        start,
        end,
        is_separator: class,
    })
}

fn line_content_char_len(line: RopeSlice<'_>) -> usize {
    let mut len = line.len_chars();
    if len > 0 && line.char(len - 1) == '\n' {
        len -= 1;
        if len > 0 && line.char(len - 1) == '\r' {
            len -= 1;
        }
    }
    len
}

fn transpose_line_content_char_len(line: RopeSlice<'_>) -> usize {
    let mut len = line.len_chars();
    if len > 0 && line.char(len - 1) == '\n' {
        len -= 1;
        if len > 0 && line.char(len - 1) == '\r' {
            len -= 1;
        }
    } else if len > 0 && line.char(len - 1) == '\r' {
        len -= 1;
    }
    len
}

fn utf16_column_char(line: RopeSlice<'_>, column_utf16: usize, round_up: bool) -> usize {
    let column_utf16 = column_utf16.min(line.len_utf16_cu());
    let char_index = line.utf16_cu_to_char(column_utf16);
    let actual_utf16 = line.char_to_utf16_cu(char_index);
    if round_up && actual_utf16 < column_utf16 {
        (char_index + 1).min(line.len_chars())
    } else {
        char_index
    }
}

fn previous_word_part_boundary(line: RopeSlice<'_>, cursor: usize) -> Option<usize> {
    for boundary in (1..cursor).rev() {
        let left = line.char(boundary - 1);
        let right = line.char(boundary);
        if (left == '_' && right != '_')
            || (left == '-' && right != '-')
            || ((left.is_ascii_lowercase() || left.is_ascii_digit()) && right.is_ascii_uppercase())
        {
            return Some(boundary);
        }
        if left.is_ascii_uppercase()
            && right.is_ascii_uppercase()
            && boundary + 1 < line.len_chars()
        {
            let right_right = line.char(boundary + 1);
            if right_right.is_ascii_lowercase() || right_right.is_ascii_digit() {
                return Some(boundary);
            }
        }
    }
    None
}

fn next_word_part_boundary(line: RopeSlice<'_>, cursor: usize) -> Option<usize> {
    for boundary in (cursor + 1)..line.len_chars() {
        let left = line.char(boundary - 1);
        let right = line.char(boundary);
        if (left != '_' && right == '_')
            || (left != '-' && right == '-')
            || ((left.is_ascii_lowercase() || left.is_ascii_digit()) && right.is_ascii_uppercase())
        {
            return Some(boundary);
        }
        if left.is_ascii_uppercase()
            && right.is_ascii_uppercase()
            && boundary + 1 < line.len_chars()
        {
            let right_right = line.char(boundary + 1);
            if right_right.is_ascii_lowercase() || right_right.is_ascii_digit() {
                return Some(boundary);
            }
        }
    }
    None
}

/// A bounded read from the Rust-authoritative document.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TextRangeRead {
    pub version: u64,
    pub total_utf16_length: usize,
    pub line_count: usize,
    pub start_utf16: usize,
    pub end_utf16: usize,
    pub start_line: usize,
    pub start_character: usize,
    pub text: String,
}

/// Absolute UTF-16 start offset for one zero-based document line.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TextLineOffset {
    pub version: u64,
    pub total_utf16_length: usize,
    pub line_count: usize,
    pub line: usize,
    pub offset_utf16: usize,
}

/// UTF-16 boundaries for the logical line containing one absolute offset.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TextLineBoundary {
    pub version: u64,
    pub line: usize,
    pub start_utf16: usize,
    pub first_non_whitespace_utf16: usize,
    pub end_utf16: usize,
}

/// One row in a rectangular selection. Offsets are absolute UTF-16 document
/// positions; the active row is returned first for the platform caret.
#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct TextColumnSelection {
    pub line: usize,
    pub base_offset_utf16: usize,
    pub extent_offset_utf16: usize,
}

/// One bounded UTF-16 window from a document line.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TextLineRead {
    pub line: usize,
    pub start_utf16: usize,
    pub end_utf16: usize,
    pub text: String,
}

/// A bounded set of line windows from one immutable buffer snapshot.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TextLinesRead {
    pub version: u64,
    pub total_utf16_length: usize,
    pub line_count: usize,
    pub first_line: usize,
    pub lines: Vec<TextLineRead>,
}

/// A bounded, evenly sampled overview of a Rust-authoritative document.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TextMinimapSample {
    pub version: u64,
    pub total_utf16_length: usize,
    pub line_count: usize,
    pub lines: Vec<TextMinimapLine>,
}

/// One representative line in a minimap snapshot. `utf16_length` is the full
/// line length; `text` contains only a scalar-safe prefix for rendering.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TextMinimapLine {
    pub line: usize,
    pub start_utf16: usize,
    pub utf16_length: usize,
    pub text: String,
}

/// 单个增量编辑操作。offset/len 均为 UTF-16 code unit 口径。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum TextOp {
    Insert {
        offset_utf16: usize,
        text: String,
    },
    Delete {
        offset_utf16: usize,
        len_utf16: usize,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BufferError {
    /// offset 不是合法的 UTF-16 边界（如落在代理对中间）或越界。
    InvalidUtf16Offset { offset_utf16: usize },
    /// 删除区间越界（offset+len 超过文档末尾）。
    DeleteOutOfBounds {
        offset_utf16: usize,
        len_utf16: usize,
    },
    /// A bounded read requested more than the API's per-call limit.
    ReadRangeTooLarge { requested: usize, max: usize },
    /// A requested zero-based line is outside the document.
    InvalidLine { line: usize, line_count: usize },
    /// A viewport line request has invalid bounds or a budget smaller than its
    /// per-line worst case.
    InvalidLineWindow {
        max_lines: usize,
        max_line_utf16: usize,
        max_total_utf16: usize,
    },
    /// A viewport request contains too many line windows.
    ReadLineCountTooLarge { requested: usize, max: usize },
    /// A word-delete query contains more caret positions than the bounded API accepts.
    WordDeleteCountTooLarge { requested: usize, max: usize },
    /// A line-delete query contains more selections than the bounded API accepts.
    LineDeleteCountTooLarge { requested: usize, max: usize },
    /// An overtype-paste query contains more selections than the bounded API accepts.
    OvertypePasteCountTooLarge { requested: usize, max: usize },
    /// A line-delete selection has its end before its start.
    InvalidDeleteRange {
        start_utf16: usize,
        end_utf16: usize,
    },
    /// A transpose query contains more caret positions than the bounded API accepts.
    TransposeCountTooLarge { requested: usize, max: usize },
    /// An overtype-paste selection has its end before its start.
    InvalidOvertypePasteRange {
        start_utf16: usize,
        end_utf16: usize,
    },
}

impl std::fmt::Display for BufferError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            BufferError::InvalidUtf16Offset { offset_utf16 } => {
                write!(
                    f,
                    "invalid UTF-16 offset {offset_utf16} (not a boundary or out of range)"
                )
            }
            BufferError::DeleteOutOfBounds {
                offset_utf16,
                len_utf16,
            } => {
                write!(f, "delete range {offset_utf16}+{len_utf16} out of bounds")
            }
            BufferError::ReadRangeTooLarge { requested, max } => {
                write!(f, "read range length {requested} exceeds maximum {max}")
            }
            BufferError::InvalidLine { line, line_count } => {
                write!(f, "line {line} is outside document line count {line_count}")
            }
            BufferError::InvalidLineWindow {
                max_lines,
                max_line_utf16,
                max_total_utf16,
            } => write!(
                f,
                "invalid line window ({max_lines} lines × {max_line_utf16} UTF-16 units; total budget {max_total_utf16})"
            ),
            BufferError::ReadLineCountTooLarge { requested, max } => {
                write!(f, "line window count {requested} exceeds maximum {max}")
            }
            BufferError::WordDeleteCountTooLarge { requested, max } => {
                write!(f, "word-delete caret count {requested} exceeds maximum {max}")
            }
            BufferError::LineDeleteCountTooLarge { requested, max } => {
                write!(f, "line-delete selection count {requested} exceeds maximum {max}")
            }
            BufferError::TransposeCountTooLarge { requested, max } => {
                write!(f, "transpose caret count {requested} exceeds maximum {max}")
            }
            BufferError::OvertypePasteCountTooLarge { requested, max } => write!(
                f,
                "overtype-paste selection count {requested} exceeds maximum {max}"
            ),
            BufferError::InvalidDeleteRange {
                start_utf16,
                end_utf16,
            } => write!(
                f,
                "line-delete range end {end_utf16} precedes start {start_utf16}"
            ),
            BufferError::InvalidOvertypePasteRange {
                start_utf16,
                end_utf16,
            } => write!(
                f,
                "overtype-paste range end {end_utf16} precedes start {start_utf16}"
            ),
        }
    }
}

impl std::error::Error for BufferError {}

/// 权威文本状态（V1：作为 Rust 侧同步分析副本；见 docs/02 §5）。
/// version 从 1 开始，每成功应用一个操作 +1。
#[derive(Clone)]
pub struct TextBuffer {
    rope: Rope,
    savepoint: Rope,
    version: u64,
}

impl TextBuffer {
    pub fn open(content: &str) -> Self {
        let rope = Rope::from_str(content);
        TextBuffer {
            savepoint: rope.clone(),
            rope,
            version: 1,
        }
    }

    pub fn version(&self) -> u64 {
        self.version
    }

    pub fn text(&self) -> String {
        self.rope.to_string()
    }

    /// Mark the current Rope snapshot as the document savepoint.
    pub fn mark_saved(&mut self) {
        self.savepoint = self.rope.clone();
    }

    /// Set the savepoint to text loaded from disk or a recovery journal.
    pub fn set_savepoint_text(&mut self, text: &str) {
        self.savepoint = Rope::from_str(text);
    }

    /// Compare exact UTF-8 bytes without materializing either Rope as a String.
    pub fn is_dirty(&self) -> bool {
        !self.rope.bytes().eq(self.savepoint.bytes())
    }

    /// Compare an external snapshot with the current savepoint.
    pub fn savepoint_matches_text(&self, text: &str) -> bool {
        self.savepoint.bytes().eq(text.bytes())
    }

    pub fn len_utf16(&self) -> usize {
        self.rope.len_utf16_cu()
    }

    /// Resolve a zero-based line to its absolute UTF-16 start without reading
    /// or materialising document text.
    pub fn line_offset_utf16(&self, line: usize) -> Result<TextLineOffset, BufferError> {
        let line_count = self.rope.len_lines();
        if line >= line_count {
            return Err(BufferError::InvalidLine { line, line_count });
        }
        let char_index = self.rope.line_to_char(line);
        Ok(TextLineOffset {
            version: self.version,
            total_utf16_length: self.len_utf16(),
            line_count,
            line,
            offset_utf16: self.rope.char_to_utf16_cu(char_index),
        })
    }

    /// Resolve Home/End targets for the logical line containing an absolute
    /// UTF-16 offset. Leading spaces and tabs form the smart-Home indentation
    /// boundary. Line terminators, including CRLF, are excluded from End.
    pub fn line_boundary_utf16(
        &self,
        offset_utf16: usize,
    ) -> Result<TextLineBoundary, BufferError> {
        let caret_char = self.char_idx_at_utf16(offset_utf16)?;
        let line_index = self.rope.char_to_line(caret_char);
        let line_start_char = self.rope.line_to_char(line_index);
        let line = self.rope.line(line_index);
        let content_len = line_content_char_len(line);
        let first_non_whitespace_char = line
            .slice(..content_len)
            .chars()
            .position(|ch| ch != ' ' && ch != '\t')
            .unwrap_or(content_len);

        Ok(TextLineBoundary {
            version: self.version,
            line: line_index,
            start_utf16: self.rope.char_to_utf16_cu(line_start_char),
            first_non_whitespace_utf16: self
                .rope
                .char_to_utf16_cu(line_start_char + first_non_whitespace_char),
            end_utf16: self.rope.char_to_utf16_cu(line_start_char + content_len),
        })
    }

    /// Resolve the rows of a rectangular selection without reading the whole
    /// document into the UI process. Columns use UTF-16 units; ranges are
    /// snapped outward at scalar boundaries so a supplementary character is
    /// never split. `max_selections` bounds the returned allocation.
    pub fn column_selections_utf16(
        &self,
        anchor_line: usize,
        anchor_column_utf16: usize,
        active_line: usize,
        active_column_utf16: usize,
        max_selections: usize,
    ) -> Result<Vec<TextColumnSelection>, BufferError> {
        let line_count = self.rope.len_lines();
        for line in [anchor_line, active_line] {
            if line >= line_count {
                return Err(BufferError::InvalidLine { line, line_count });
            }
        }
        let first_line = anchor_line.min(active_line);
        let last_line = anchor_line.max(active_line);
        let selection_count = last_line - first_line + 1;
        let selection_limit = max_selections.min(MAX_COLUMN_SELECTIONS);
        if selection_count > selection_limit {
            return Err(BufferError::ReadLineCountTooLarge {
                requested: selection_count,
                max: selection_limit,
            });
        }

        let anchor_is_left = anchor_column_utf16 <= active_column_utf16;
        let low_column = anchor_column_utf16.min(active_column_utf16);
        let high_column = anchor_column_utf16.max(active_column_utf16);
        let mut selections = Vec::with_capacity(selection_count);
        for line_index in first_line..=last_line {
            let line_start_char = self.rope.line_to_char(line_index);
            let line = self.rope.line(line_index);
            let content = line.slice(..line_content_char_len(line));
            let content_utf16 = content.len_utf16_cu();
            let low = utf16_column_char(content, low_column.min(content_utf16), false);
            let high = utf16_column_char(content, high_column.min(content_utf16), true);
            let (base_char, extent_char) = if anchor_is_left {
                (low, high)
            } else {
                (high, low)
            };
            let line_start_utf16 = self.rope.char_to_utf16_cu(line_start_char);
            selections.push(TextColumnSelection {
                line: line_index,
                base_offset_utf16: line_start_utf16 + content.char_to_utf16_cu(base_char),
                extent_offset_utf16: line_start_utf16 + content.char_to_utf16_cu(extent_char),
            });
        }
        if let Some(active_index) = selections.iter().position(|item| item.line == active_line) {
            let active = selections.remove(active_index);
            selections.insert(0, active);
        }
        Ok(selections)
    }

    /// Move by one VS Code word part using absolute UTF-16 document offsets.
    /// The operation scans only the current Rope line and never materializes
    /// the full document or line as a `String`.
    pub fn word_part_offset_utf16(
        &self,
        offset_utf16: usize,
        direction: WordPartDirection,
    ) -> Result<usize, BufferError> {
        let caret_char = self.char_idx_at_utf16(offset_utf16)?;
        let line_index = self.rope.char_to_line(caret_char);
        let line_start_char = self.rope.line_to_char(line_index);
        let line = self.rope.line(line_index);
        let content_len = line_content_char_len(line);
        let cursor = caret_char.saturating_sub(line_start_char).min(content_len);
        let content = line.slice(..content_len);
        let line_start_utf16 = self.rope.char_to_utf16_cu(line_start_char);
        let cursor_utf16 = line_start_utf16 + content.char_to_utf16_cu(cursor);

        match direction {
            WordPartDirection::Left if cursor == 0 => {
                if line_index == 0 {
                    return Ok(cursor_utf16);
                }
                let previous_line_start = self.rope.line_to_char(line_index - 1);
                let previous_line = self.rope.line(line_index - 1);
                let previous_content_len = line_content_char_len(previous_line);
                return Ok(self.rope.char_to_utf16_cu(previous_line_start)
                    + previous_line.char_to_utf16_cu(previous_content_len));
            }
            WordPartDirection::Right if cursor == content_len => {
                if line_index + 1 == self.rope.len_lines() {
                    return Ok(cursor_utf16);
                }
                return Ok(self
                    .rope
                    .char_to_utf16_cu(self.rope.line_to_char(line_index + 1)));
            }
            _ => {}
        }

        let destination = match direction {
            WordPartDirection::Left => {
                let previous_token = previous_word_token(content, cursor);
                let word_start = previous_token.map_or(0, |token| token.start);
                let word_end = previous_token.map_or(0, |token| {
                    if cursor <= token.end {
                        previous_word_token(content, token.start).map_or(0, |previous| previous.end)
                    } else {
                        token.end
                    }
                });
                let subword = previous_word_part_boundary(content, cursor).unwrap_or(0);
                word_start.max(word_end).max(subword)
            }
            WordPartDirection::Right => {
                let next_token = next_word_token(content, cursor);
                let word_start = next_token.map_or(content_len, |token| {
                    if cursor >= token.start {
                        next_word_token(content, token.end).map_or(content_len, |next| next.start)
                    } else {
                        token.start
                    }
                });
                let word_end = next_token.map_or(content_len, |token| {
                    if token.is_separator
                        && token.end - token.start == 1
                        && token.end < content_len
                        && word_char_class(content.char(token.end)) == Some(false)
                    {
                        next_word_token(content, token.end).map_or(content_len, |next| next.end)
                    } else {
                        token.end
                    }
                });
                let subword = next_word_part_boundary(content, cursor).unwrap_or(content_len);
                word_start.min(word_end).min(subword)
            }
        };

        Ok(line_start_utf16 + content.char_to_utf16_cu(destination))
    }

    /// Resolve a VS Code style delete-word range without materialising the
    /// document. The scan is limited to the current logical line and all
    /// returned offsets use UTF-16 code units.
    pub fn word_delete_range_utf16(
        &self,
        offset_utf16: usize,
        direction: WordDeleteDirection,
    ) -> Result<TextDeleteRange, BufferError> {
        let caret_char = self.char_idx_at_utf16(offset_utf16)?;
        let line_index = self.rope.char_to_line(caret_char);
        let line_start_char = self.rope.line_to_char(line_index);
        let line = self.rope.line(line_index);
        let content_len = line_content_char_len(line);
        let cursor = caret_char.saturating_sub(line_start_char).min(content_len);
        let content = line.slice(..content_len);

        let (start_char, end_char) = match direction {
            WordDeleteDirection::Left if cursor == 0 => {
                if line_index == 0 {
                    (caret_char, caret_char)
                } else {
                    let previous_line_start = self.rope.line_to_char(line_index - 1);
                    let previous_line = self.rope.line(line_index - 1);
                    let previous_content_len = line_content_char_len(previous_line);
                    (previous_line_start + previous_content_len, line_start_char)
                }
            }
            WordDeleteDirection::Left => {
                let mut whitespace_start = cursor;
                while whitespace_start > 0
                    && matches!(content.char(whitespace_start - 1), ' ' | '\t')
                {
                    whitespace_start -= 1;
                }
                if cursor - whitespace_start > 1 {
                    (line_start_char + whitespace_start, caret_char)
                } else {
                    let start =
                        delete_previous_word_token(content, cursor).map_or(0, |token| token.start);
                    (line_start_char + start, caret_char)
                }
            }
            WordDeleteDirection::Right => {
                let mut whitespace_end = cursor;
                while whitespace_end < content_len
                    && matches!(content.char(whitespace_end), ' ' | '\t')
                {
                    whitespace_end += 1;
                }
                if whitespace_end > cursor {
                    (caret_char, line_start_char + whitespace_end)
                } else if let Some(token) = delete_next_word_token(content, cursor) {
                    (caret_char, line_start_char + token.end)
                } else if cursor < content_len || line_index + 1 == self.rope.len_lines() {
                    (caret_char, line_start_char + content_len)
                } else {
                    let next_line_start = self.rope.line_to_char(line_index + 1);
                    let next_line = self.rope.line(line_index + 1);
                    let next_content_len = line_content_char_len(next_line);
                    let next_content = next_line.slice(..next_content_len);
                    let next_end = delete_next_word_token(next_content, 0)
                        .map_or(next_content_len, |token| token.start);
                    (caret_char, next_line_start + next_end)
                }
            }
        };

        Ok(TextDeleteRange {
            start_utf16: self.rope.char_to_utf16_cu(start_char),
            end_utf16: self.rope.char_to_utf16_cu(end_char),
        })
    }

    /// Resolve many word-delete ranges against one immutable buffer version.
    pub fn word_delete_ranges_utf16(
        &self,
        offsets_utf16: &[usize],
        direction: WordDeleteDirection,
    ) -> Result<Vec<TextDeleteRange>, BufferError> {
        if offsets_utf16.len() > MAX_WORD_DELETE_CARETS {
            return Err(BufferError::WordDeleteCountTooLarge {
                requested: offsets_utf16.len(),
                max: MAX_WORD_DELETE_CARETS,
            });
        }
        offsets_utf16
            .iter()
            .map(|&offset| self.word_delete_range_utf16(offset, direction))
            .collect()
    }

    /// Resolve VS Code style delete-to-line-boundary ranges for absolute
    /// UTF-16 selections from one immutable buffer version. `Left` extends a
    /// nonempty selection to its line start; `Right` keeps that selection.
    pub fn line_delete_ranges_utf16(
        &self,
        selections_utf16: &[(usize, usize)],
        direction: LineDeleteDirection,
    ) -> Result<Vec<TextDeleteRange>, BufferError> {
        if selections_utf16.len() > MAX_LINE_DELETE_RANGES {
            return Err(BufferError::LineDeleteCountTooLarge {
                requested: selections_utf16.len(),
                max: MAX_LINE_DELETE_RANGES,
            });
        }

        selections_utf16
            .iter()
            .map(|&(start_utf16, end_utf16)| {
                if start_utf16 > end_utf16 {
                    return Err(BufferError::InvalidDeleteRange {
                        start_utf16,
                        end_utf16,
                    });
                }
                self.char_idx_at_utf16(start_utf16)?;
                self.char_idx_at_utf16(end_utf16)?;

                let boundary = self.line_boundary_utf16(start_utf16)?;
                if start_utf16 < end_utf16 {
                    let range_start = match direction {
                        LineDeleteDirection::Left => boundary.start_utf16,
                        LineDeleteDirection::Right => start_utf16,
                    };
                    return Ok(TextDeleteRange {
                        start_utf16: range_start,
                        end_utf16,
                    });
                }

                match direction {
                    LineDeleteDirection::Left if start_utf16 == boundary.start_utf16 => {
                        if boundary.line == 0 {
                            Ok(TextDeleteRange {
                                start_utf16,
                                end_utf16,
                            })
                        } else {
                            let previous_line_start = self.rope.line_to_char(boundary.line - 1);
                            let previous_line = self.rope.line(boundary.line - 1);
                            let previous_content_end =
                                previous_line_start + line_content_char_len(previous_line);
                            Ok(TextDeleteRange {
                                start_utf16: self.rope.char_to_utf16_cu(previous_content_end),
                                end_utf16: start_utf16,
                            })
                        }
                    }
                    LineDeleteDirection::Left => Ok(TextDeleteRange {
                        start_utf16: boundary.start_utf16,
                        end_utf16: start_utf16,
                    }),
                    LineDeleteDirection::Right => {
                        let next_line = boundary.line + 1;
                        if start_utf16 >= boundary.end_utf16 && next_line < self.rope.len_lines() {
                            let next_line_start = self.rope.line_to_char(next_line);
                            Ok(TextDeleteRange {
                                start_utf16,
                                end_utf16: self.rope.char_to_utf16_cu(next_line_start),
                            })
                        } else {
                            Ok(TextDeleteRange {
                                start_utf16,
                                end_utf16: boundary.end_utf16.max(start_utf16),
                            })
                        }
                    }
                }
            })
            .collect()
    }

    /// Resolve the Code-OSS transpose range for each collapsed UTF-16 caret.
    /// Each result is `None` when the action has no character pair to swap.
    pub fn transpose_ranges_utf16(
        &self,
        offsets_utf16: &[usize],
    ) -> Result<Vec<Option<TextTransposePlan>>, BufferError> {
        if offsets_utf16.len() > MAX_TRANSPOSE_CARETS {
            return Err(BufferError::TransposeCountTooLarge {
                requested: offsets_utf16.len(),
                max: MAX_TRANSPOSE_CARETS,
            });
        }

        offsets_utf16
            .iter()
            .map(|&offset_utf16| self.transpose_range_utf16(offset_utf16))
            .collect()
    }

    fn transpose_range_utf16(
        &self,
        offset_utf16: usize,
    ) -> Result<Option<TextTransposePlan>, BufferError> {
        let caret_char = self.char_idx_at_utf16(offset_utf16)?;
        let line_bounds = self.transpose_line_bounds(caret_char);
        // VS Code positions stop before line terminators. A caret inside CRLF
        // is normalized to that same logical line end.
        let caret_char = caret_char.clamp(line_bounds.start_char, line_bounds.end_char);

        if line_bounds.start_char == 0 && caret_char == 0 {
            return Ok(None);
        }

        let end_char = if caret_char == line_bounds.end_char {
            caret_char
        } else {
            self.transpose_right_position(caret_char)
        };
        let middle_char = self.transpose_left_position(end_char);
        let begin_char = self.transpose_left_position(middle_char);
        if begin_char >= middle_char || middle_char >= end_char {
            return Ok(None);
        }

        let left_text = self.rope.slice(begin_char..middle_char).to_string();
        let right_text = self.rope.slice(middle_char..end_char).to_string();
        let mut inserted_text = String::with_capacity(left_text.len() + right_text.len());
        inserted_text.push_str(&right_text);
        inserted_text.push_str(&left_text);

        Ok(Some(TextTransposePlan {
            start_utf16: self.rope.char_to_utf16_cu(begin_char),
            end_utf16: self.rope.char_to_utf16_cu(end_char),
            removed_text: format!("{left_text}{right_text}"),
            inserted_text,
        }))
    }

    fn transpose_line_bounds(&self, position_char: usize) -> TransposeLineBounds {
        let rope_line = self.rope.char_to_line(position_char);
        let line_start = self.rope.line_to_char(rope_line);
        let line = self.rope.line(rope_line);
        let line_end = line_start + transpose_line_content_char_len(line);
        let previous_line_end = if rope_line > 0 {
            let previous_line_start = self.rope.line_to_char(rope_line - 1);
            let previous_line = self.rope.line(rope_line - 1);
            Some(previous_line_start + transpose_line_content_char_len(previous_line))
        } else {
            None
        };

        TransposeLineBounds {
            start_char: line_start,
            end_char: line_end,
            previous_line_end_char: previous_line_end,
            next_line_start_char: (rope_line + 1 < self.rope.len_lines())
                .then(|| self.rope.line_to_char(rope_line + 1)),
        }
    }

    fn transpose_left_position(&self, position_char: usize) -> usize {
        let bounds = self.transpose_line_bounds(position_char);
        if position_char > bounds.start_char {
            return position_char - 1;
        }
        bounds.previous_line_end_char.unwrap_or(bounds.start_char)
    }

    fn transpose_right_position(&self, position_char: usize) -> usize {
        let bounds = self.transpose_line_bounds(position_char);
        if position_char < bounds.end_char {
            return position_char + 1;
        }
        bounds.next_line_start_char.unwrap_or(bounds.end_char)
    }

    /// Resolve the replacement ranges VS Code uses for paste while in
    /// overtype mode. The inserted UTF-16 length extends the selection on its
    /// current logical line; line terminators are never consumed. Returned
    /// endpoints are snapped forward when the requested UTF-16 width would
    /// split a supplementary scalar.
    pub fn overtype_paste_ranges_utf16(
        &self,
        selections_utf16: &[(usize, usize, usize)],
    ) -> Result<Vec<TextDeleteRange>, BufferError> {
        if selections_utf16.len() > MAX_OVERTYPE_PASTE_RANGES {
            return Err(BufferError::OvertypePasteCountTooLarge {
                requested: selections_utf16.len(),
                max: MAX_OVERTYPE_PASTE_RANGES,
            });
        }

        selections_utf16
            .iter()
            .map(|&(start_utf16, end_utf16, inserted_utf16)| {
                if start_utf16 > end_utf16 {
                    return Err(BufferError::InvalidOvertypePasteRange {
                        start_utf16,
                        end_utf16,
                    });
                }
                self.char_idx_at_utf16(start_utf16)?;
                self.char_idx_at_utf16(end_utf16)?;

                let line = self.line_boundary_utf16(end_utf16)?;
                let additional_utf16 = if start_utf16 == end_utf16 {
                    inserted_utf16
                } else {
                    inserted_utf16.saturating_sub(1)
                };
                let requested_end = end_utf16
                    .saturating_add(additional_utf16)
                    .min(line.end_utf16);
                let end_utf16 = if self.char_idx_at_utf16(requested_end).is_ok() {
                    requested_end
                } else {
                    requested_end.saturating_add(1).min(line.end_utf16)
                };
                self.char_idx_at_utf16(end_utf16)?;

                Ok(TextDeleteRange {
                    start_utf16,
                    end_utf16,
                })
            })
            .collect()
    }

    /// Read a bounded UTF-16 range without materialising the whole document.
    ///
    /// Range starts must be valid UTF-16 boundaries. The end is shortened by
    /// one unit when the requested boundary would split a surrogate pair. If
    /// a one-unit request starts at a supplementary scalar, the complete
    /// scalar is returned so callers can always advance without splitting it.
    pub fn read_range_utf16(
        &self,
        start_utf16: usize,
        max_len_utf16: usize,
    ) -> Result<TextRangeRead, BufferError> {
        if max_len_utf16 > MAX_READ_RANGE_UTF16 {
            return Err(BufferError::ReadRangeTooLarge {
                requested: max_len_utf16,
                max: MAX_READ_RANGE_UTF16,
            });
        }

        let start_char = self.char_idx_at_utf16(start_utf16)?;
        let total_utf16_length = self.len_utf16();
        let desired_end = start_utf16
            .saturating_add(max_len_utf16)
            .min(total_utf16_length);
        let mut end_utf16 = desired_end;
        let mut end_char = match self.char_idx_at_utf16(end_utf16) {
            Ok(char_idx) => char_idx,
            Err(BufferError::InvalidUtf16Offset { .. }) if end_utf16 > start_utf16 => {
                end_utf16 -= 1;
                self.char_idx_at_utf16(end_utf16)?
            }
            Err(error) => return Err(error),
        };

        if max_len_utf16 > 0 && end_utf16 == start_utf16 && start_utf16 < total_utf16_length {
            end_char = start_char + 1;
            end_utf16 = self.rope.char_to_utf16_cu(end_char);
        }

        let start_line = self.rope.char_to_line(start_char);
        let line_start_char = self.rope.line_to_char(start_line);
        let start_character = self
            .rope
            .line(start_line)
            .char_to_utf16_cu(start_char - line_start_char);

        Ok(TextRangeRead {
            version: self.version,
            total_utf16_length,
            line_count: self.rope.len_lines(),
            start_utf16,
            end_utf16,
            start_line,
            start_character,
            text: self.rope.slice(start_char..end_char).to_string(),
        })
    }

    /// Read a bounded page of per-line horizontal windows from one Rust
    /// snapshot. Line separators are excluded from each returned window.
    ///
    /// `max_line_utf16 * max_lines` must fit within `max_total_utf16`, making
    /// the response size predictable even when every requested line is long.
    /// Horizontal positions are UTF-16 columns; a position inside a surrogate
    /// pair is moved back to the scalar start.
    pub fn read_lines_utf16(
        &self,
        first_line: usize,
        max_lines: usize,
        horizontal_start_utf16: usize,
        max_line_utf16: usize,
        max_total_utf16: usize,
    ) -> Result<TextLinesRead, BufferError> {
        let line_count = self.rope.len_lines();
        if first_line >= line_count {
            return Err(BufferError::InvalidLine {
                line: first_line,
                line_count,
            });
        }
        if max_lines > MAX_READ_LINES {
            return Err(BufferError::ReadLineCountTooLarge {
                requested: max_lines,
                max: MAX_READ_LINES,
            });
        }
        if max_lines == 0
            || max_line_utf16 < 2
            || max_total_utf16 == 0
            || max_line_utf16 > MAX_READ_RANGE_UTF16
            || max_total_utf16 > MAX_READ_RANGE_UTF16
            || max_line_utf16.saturating_mul(max_lines) > max_total_utf16
        {
            return Err(BufferError::InvalidLineWindow {
                max_lines,
                max_line_utf16,
                max_total_utf16,
            });
        }

        let returned_line_count = max_lines.min(line_count - first_line);
        let mut lines = Vec::with_capacity(returned_line_count);
        for line_index in first_line..first_line + returned_line_count {
            let line_slice = self.rope.line(line_index);
            let mut content_chars = line_slice.len_chars();
            if content_chars > 0 && line_slice.char(content_chars - 1) == '\n' {
                content_chars -= 1;
                if content_chars > 0 && line_slice.char(content_chars - 1) == '\r' {
                    content_chars -= 1;
                }
            }

            let content_start_char = self.rope.line_to_char(line_index);
            let content_end_char = content_start_char + content_chars;
            let content_start_utf16 = self.rope.char_to_utf16_cu(content_start_char);
            let content_end_utf16 = self.rope.char_to_utf16_cu(content_end_char);
            let content_length = content_end_utf16 - content_start_utf16;
            let requested_column = horizontal_start_utf16.min(content_length);
            let requested_start = content_start_utf16 + requested_column;
            let start_char = match self.char_idx_at_utf16(requested_start) {
                Ok(char_index) => char_index,
                Err(BufferError::InvalidUtf16Offset { .. }) if requested_start > 0 => {
                    self.char_idx_at_utf16(requested_start - 1)?
                }
                Err(error) => return Err(error),
            };
            let start_utf16 = self.rope.char_to_utf16_cu(start_char);
            let requested_end = start_utf16
                .saturating_add(max_line_utf16)
                .min(content_end_utf16);
            let end_char = match self.char_idx_at_utf16(requested_end) {
                Ok(char_index) => char_index,
                Err(BufferError::InvalidUtf16Offset { .. }) if requested_end > start_utf16 => {
                    self.char_idx_at_utf16(requested_end - 1)?
                }
                Err(error) => return Err(error),
            };
            let end_utf16 = self.rope.char_to_utf16_cu(end_char);

            lines.push(TextLineRead {
                line: line_index,
                start_utf16,
                end_utf16,
                text: self.rope.slice(start_char..end_char).to_string(),
            });
        }

        Ok(TextLinesRead {
            version: self.version,
            total_utf16_length: self.len_utf16(),
            line_count,
            first_line,
            lines,
        })
    }

    /// Return an evenly sampled, bounded overview without materializing the
    /// document. The response contains at most 512 lines × 48 UTF-16 units.
    pub fn minimap_sample(&self) -> TextMinimapSample {
        let line_count = self.rope.len_lines();
        let sample_count = line_count.min(MAX_MINIMAP_SAMPLE_LINES);
        let mut lines = Vec::with_capacity(sample_count);

        for sample_index in 0..sample_count {
            let line_index = if sample_count <= 1 {
                0
            } else {
                sample_index.saturating_mul(line_count - 1) / (sample_count - 1)
            };
            let start_char = self.rope.line_to_char(line_index);
            let start_utf16 = self.rope.char_to_utf16_cu(start_char);
            let line = self.rope.line(line_index);
            let mut content_chars = line.len_chars();
            if content_chars > 0 && line.char(content_chars - 1) == '\n' {
                content_chars -= 1;
                if content_chars > 0 && line.char(content_chars - 1) == '\r' {
                    content_chars -= 1;
                }
            }

            let utf16_length = line.char_to_utf16_cu(content_chars);
            let mut text = String::new();
            let mut sampled_utf16 = 0;
            for char_index in 0..content_chars {
                let ch = line.char(char_index);
                let units = ch.len_utf16();
                if sampled_utf16 + units > MAX_MINIMAP_LINE_SAMPLE_UTF16 {
                    break;
                }
                text.push(ch);
                sampled_utf16 += units;
            }

            lines.push(TextMinimapLine {
                line: line_index,
                start_utf16,
                utf16_length,
                text,
            });
        }

        TextMinimapSample {
            version: self.version,
            total_utf16_length: self.len_utf16(),
            line_count,
            lines,
        }
    }

    /// 应用一个操作。成功则版本号 +1。
    pub fn apply(&mut self, op: &TextOp) -> Result<(), BufferError> {
        match op {
            TextOp::Insert { offset_utf16, text } => {
                let char_idx = self.char_idx_at_utf16(*offset_utf16)?;
                self.rope.insert(char_idx, text);
            }
            TextOp::Delete {
                offset_utf16,
                len_utf16,
            } => {
                let start = self.char_idx_at_utf16(*offset_utf16)?;
                let end_utf16 =
                    offset_utf16
                        .checked_add(*len_utf16)
                        .ok_or(BufferError::DeleteOutOfBounds {
                            offset_utf16: *offset_utf16,
                            len_utf16: *len_utf16,
                        })?;
                if end_utf16 > self.rope.len_utf16_cu() {
                    return Err(BufferError::DeleteOutOfBounds {
                        offset_utf16: *offset_utf16,
                        len_utf16: *len_utf16,
                    });
                }
                let end = self.char_idx_at_utf16(end_utf16)?;
                self.rope.remove(start..end);
            }
        }
        self.version += 1;
        Ok(())
    }

    /// 按序应用一批操作，任一失败即整体失败（rope 的已完成修改不回滚）。
    /// 调用方（editor-core）在版本校验通过后才调用本方法，失败时文档应视为
    /// 需要重新同步（resync），因此不做部分回滚。
    pub fn apply_ops(&mut self, ops: &[TextOp]) -> Result<(), BufferError> {
        for op in ops {
            self.apply(op)?;
        }
        Ok(())
    }

    /// UTF-16 offset → LSP 位置（0 基行号 + 行内 UTF-16 列）。
    /// 供 editor-lsp 的 didOpen/completion 等使用。
    pub fn line_col_utf16(&self, offset_utf16: usize) -> Option<(u64, u64)> {
        let char_idx = self.char_idx_at_utf16(offset_utf16).ok()?;
        let line = self.rope.char_to_line(char_idx);
        let line_start_char = self.rope.line_to_char(line);
        let col_chars = char_idx - line_start_char;
        let col_utf16 = self.rope.line(line).char_to_utf16_cu(col_chars);
        Some((line as u64, col_utf16 as u64))
    }

    /// UTF-16 offset → Ropey char 索引；非法边界（代理对中间）或越界返回错误。
    fn char_idx_at_utf16(&self, offset_utf16: usize) -> Result<usize, BufferError> {
        if offset_utf16 > self.rope.len_utf16_cu() {
            return Err(BufferError::InvalidUtf16Offset { offset_utf16 });
        }
        let char_idx = self.rope.utf16_cu_to_char(offset_utf16);
        // utf16_cu_to_char 对落在代理对中间的 offset 会向下取整到所在 char，
        // 因此必须回验：转换后的 char 的起始 UTF-16 offset 必须与输入一致。
        if self.rope.char_to_utf16_cu(char_idx) != offset_utf16 {
            return Err(BufferError::InvalidUtf16Offset { offset_utf16 });
        }
        Ok(char_idx)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn open_assigns_version_one_and_keeps_content() {
        let buf = TextBuffer::open("hello\nworld\n");
        assert_eq!(buf.version(), 1);
        assert_eq!(buf.text(), "hello\nworld\n");
    }

    #[test]
    fn case_transform_uses_full_unicode_mappings() {
        assert_eq!(transform_case_text("straße", true), "STRASSE");
        assert_eq!(transform_case_text("ﬃ", true), "FFI");
        assert_eq!(transform_case_text("İ", false), "i\u{307}");
        assert_eq!(transform_case_text("A\0B", true), "A\0B");
    }

    #[test]
    fn title_case_uses_code_oss_unicode_letter_boundaries() {
        assert_eq!(transform_title_case_text("hELLO wORLD"), "Hello World");
        assert_eq!(
            transform_title_case_text("DON'T rock'n'roll 'tIS"),
            "Don't Rock'n'roll 'Tis"
        );
        assert_eq!(
            transform_title_case_text("ßETA O’NEIL 2FAST\nΩMEGA"),
            "SSeta O’Neil 2fast\nΩmega"
        );
        assert_eq!(
            transform_title_case_text("İSTANBUL\0eCLAIR"),
            "I\u{307}Stanbul\0Eclair"
        );
    }

    #[test]
    fn camel_case_uses_code_oss_unicode_word_boundaries() {
        assert_eq!(transform_camel_case_text("linux-save-ok"), "linuxSaveOk");
        assert_eq!(transform_camel_case_text("Foo-bar"), "fooBar");
        assert_eq!(transform_camel_case_text("FOO-bar"), "FOOBar");
        assert_eq!(transform_camel_case_text("my name_here"), "myNameHere");
        assert_eq!(
            transform_camel_case_text("foo_bar\nqux-baz"),
            "fooBar\nquxBaz"
        );
        assert_eq!(transform_camel_case_text("Foo\r\nBar"), "foo\r\nbar");
        assert_eq!(transform_camel_case_text("🌱-seed"), "🌱Seed");
        assert_eq!(transform_camel_case_text("foo-𐐀bar"), "foo𐐀bar");
        assert_eq!(
            transform_camel_case_text("foo\u{0085}bar"),
            "foo\u{0085}bar"
        );
        assert_eq!(transform_camel_case_text("foo\u{FEFF}bar"), "fooBar");
        assert_eq!(transform_camel_case_text("foo\u{2028}bar"), "fooBar");
        assert_eq!(transform_camel_case_text("Istanbul-İzmir"), "istanbulİzmir");
        assert_eq!(transform_camel_case_text("foo\0-bar"), "foo\0Bar");
    }

    #[test]
    fn snake_case_uses_code_oss_unicode_case_boundaries() {
        assert_eq!(transform_snake_case_text("fooBar"), "foo_bar");
        assert_eq!(
            transform_snake_case_text("XMLHttpRequest"),
            "xml_http_request"
        );
        assert_eq!(transform_snake_case_text("fooBARBaz"), "foo_bar_baz");
        assert_eq!(transform_snake_case_text("2FastNumber"), "2_fast_number");
        assert_eq!(transform_snake_case_text("foo2Bar"), "foo2_bar");
        assert_eq!(transform_snake_case_text("O’Neil"), "o’neil");
        assert_eq!(transform_snake_case_text("foo__Bar"), "foo__bar");
        assert_eq!(transform_snake_case_text("éclairÉté"), "éclair_été");
        assert_eq!(transform_snake_case_text("A1B2"), "a1b2");
        assert_eq!(
            transform_snake_case_text("HTTPServer\nNextLine"),
            "http_server\nnext_line"
        );
    }

    #[test]
    fn pascal_case_uses_code_oss_word_and_dot_boundaries() {
        assert_eq!(transform_pascal_case_text("linux-save-ok"), "LinuxSaveOk");
        assert_eq!(transform_pascal_case_text("foo.bar-baz"), "Foo.BarBaz");
        assert_eq!(transform_pascal_case_text("FOO_HTTP"), "FooHttp");
        assert_eq!(transform_pascal_case_text("ßETA"), "SSETA");
        assert_eq!(transform_pascal_case_text("HTTPServer"), "HTTPServer");
        assert_eq!(transform_pascal_case_text("foo\nbar"), "Foo\nbar");
        assert_eq!(transform_pascal_case_text("foo\nBAR"), "Foo\nbar");
        assert_eq!(transform_pascal_case_text("foo\r\nBAR"), "Foo\r\nbar");
        assert_eq!(
            transform_pascal_case_text("foo\u{2028}BAR"),
            "Foo\u{2028}bar"
        );
        assert_eq!(transform_pascal_case_text("éclair-été"), "ÉclairÉté");
        assert_eq!(transform_pascal_case_text("🌱-seed"), "🌱Seed");
        assert_eq!(transform_pascal_case_text("𐐀ABC"), "𐐀abc");
        assert_eq!(transform_pascal_case_text("foo\0-bar"), "Foo\0Bar");
        assert_eq!(transform_pascal_case_text("  foo--bar_\t"), "FooBar");
    }

    #[test]
    fn insert_bumps_version() {
        let mut buf = TextBuffer::open("hello");
        buf.apply(&TextOp::Insert {
            offset_utf16: 5,
            text: " world".into(),
        })
        .unwrap();
        assert_eq!(buf.text(), "hello world");
        assert_eq!(buf.version(), 2);
    }

    #[test]
    fn delete_bumps_version() {
        let mut buf = TextBuffer::open("hello world");
        buf.apply(&TextOp::Delete {
            offset_utf16: 5,
            len_utf16: 6,
        })
        .unwrap();
        assert_eq!(buf.text(), "hello");
        assert_eq!(buf.version(), 2);
    }

    #[test]
    fn utf16_offsets_with_cjk_and_emoji() {
        // "a中b🦊!" — UTF-16 长度：a=1 中=1 b=1 🦊=2(代理对) !=1，共 6
        let mut buf = TextBuffer::open("a中b\u{1F98A}!");
        assert_eq!(buf.len_utf16(), 6);

        // 在 🦊 之后插入（UTF-16 offset 5）
        buf.apply(&TextOp::Insert {
            offset_utf16: 5,
            text: "X".into(),
        })
        .unwrap();
        assert_eq!(buf.text(), "a中b\u{1F98A}X!");

        // 删除整个 🦊（offset 3, len 2）
        buf.apply(&TextOp::Delete {
            offset_utf16: 3,
            len_utf16: 2,
        })
        .unwrap();
        assert_eq!(buf.text(), "a中bX!");
        assert_eq!(buf.version(), 3);
    }

    #[test]
    fn offset_inside_surrogate_pair_is_rejected() {
        let mut buf = TextBuffer::open("a\u{1F98A}b");
        // 🦊 从 UTF-16 offset 1 开始，占 1..3；offset 2 在代理对中间
        let err = buf.apply(&TextOp::Insert {
            offset_utf16: 2,
            text: "x".into(),
        });
        assert_eq!(
            err,
            Err(BufferError::InvalidUtf16Offset { offset_utf16: 2 })
        );
        // 失败的操作不改变版本号
        assert_eq!(buf.version(), 1);
        assert_eq!(buf.text(), "a\u{1F98A}b");
    }

    #[test]
    fn delete_out_of_bounds_is_rejected() {
        let mut buf = TextBuffer::open("abc");
        let err = buf.apply(&TextOp::Delete {
            offset_utf16: 2,
            len_utf16: 5,
        });
        assert_eq!(
            err,
            Err(BufferError::DeleteOutOfBounds {
                offset_utf16: 2,
                len_utf16: 5,
            })
        );
    }

    #[test]
    fn crlf_and_final_newline_preserved() {
        let mut buf = TextBuffer::open("line1\r\nline2\r\n");
        buf.apply(&TextOp::Insert {
            offset_utf16: 14,
            text: "line3".into(),
        })
        .unwrap();
        assert_eq!(buf.text(), "line1\r\nline2\r\nline3");
    }

    #[test]
    fn line_col_utf16_handles_multibyte() {
        // 行0: "中文 fn"（中文各占 1 个 UTF-16 单位，共 7）；行1: "  hello"
        let buf = TextBuffer::open("中文 fn\n  hello\n");
        assert_eq!(buf.line_col_utf16(0), Some((0, 0)));
        // 'f' 前有 中(1)文(1)空(1) → (0,3)
        assert_eq!(buf.line_col_utf16(3), Some((0, 3)));
        // 行0 共 5 单位 + \n 1 = 6；行1 缩进 2 → 'h' 在 offset 8，列 2
        assert_eq!(buf.line_col_utf16(8), Some((1, 2)));
        assert_eq!(buf.line_col_utf16(10), Some((1, 4)));
        // 代理对中间 → None
        let buf2 = TextBuffer::open("a🦊b");
        assert_eq!(buf2.line_col_utf16(2), None);
        // Emoji 行内列按 UTF-16 计：a(1) 🦊(2) → 'b' 在 (0,3)
        assert_eq!(buf2.line_col_utf16(3), Some((0, 3)));
    }

    #[test]
    fn word_delete_matches_vs_code_space_and_word_rules() {
        let left = TextBuffer::open("aa bb");
        assert_eq!(
            left.word_delete_range_utf16(3, WordDeleteDirection::Left),
            Ok(TextDeleteRange {
                start_utf16: 0,
                end_utf16: 3,
            })
        );

        let many_spaces = TextBuffer::open("aa   bb");
        assert_eq!(
            many_spaces.word_delete_range_utf16(5, WordDeleteDirection::Left),
            Ok(TextDeleteRange {
                start_utf16: 2,
                end_utf16: 5,
            })
        );
        assert_eq!(
            many_spaces.word_delete_range_utf16(2, WordDeleteDirection::Right),
            Ok(TextDeleteRange {
                start_utf16: 2,
                end_utf16: 5,
            })
        );

        assert_eq!(
            left.word_delete_range_utf16(3, WordDeleteDirection::Right),
            Ok(TextDeleteRange {
                start_utf16: 3,
                end_utf16: 5,
            })
        );
        assert_eq!(
            left.word_delete_range_utf16(0, WordDeleteDirection::Left),
            Ok(TextDeleteRange {
                start_utf16: 0,
                end_utf16: 0,
            })
        );
        assert_eq!(
            left.word_delete_range_utf16(5, WordDeleteDirection::Right),
            Ok(TextDeleteRange {
                start_utf16: 5,
                end_utf16: 5,
            })
        );
    }

    #[test]
    fn word_delete_crosses_crlf_to_next_line_word_start() {
        let buffer = TextBuffer::open("aa\r\n   bb\ncc");
        assert_eq!(
            buffer.word_delete_range_utf16(2, WordDeleteDirection::Right),
            Ok(TextDeleteRange {
                start_utf16: 2,
                end_utf16: 7,
            })
        );
        assert_eq!(
            buffer.word_delete_range_utf16(7, WordDeleteDirection::Left),
            Ok(TextDeleteRange {
                start_utf16: 4,
                end_utf16: 7,
            })
        );
        assert_eq!(
            buffer.word_delete_range_utf16(10, WordDeleteDirection::Left),
            Ok(TextDeleteRange {
                start_utf16: 9,
                end_utf16: 10,
            })
        );
    }

    #[test]
    fn word_delete_uses_utf16_boundaries_and_scans_beyond_editor_window() {
        let buffer = TextBuffer::open("fn🦊Value");
        assert_eq!(
            buffer.word_delete_range_utf16(4, WordDeleteDirection::Left),
            Ok(TextDeleteRange {
                start_utf16: 0,
                end_utf16: 4,
            })
        );
        assert_eq!(
            buffer.word_delete_range_utf16(3, WordDeleteDirection::Left),
            Err(BufferError::InvalidUtf16Offset { offset_utf16: 3 })
        );

        let long = format!("{} 🦊end", "word".repeat(5000));
        let long_buffer = TextBuffer::open(&long);
        let expected_end = "word".repeat(5000).encode_utf16().count() + 1;
        assert_eq!(
            long_buffer.word_delete_range_utf16(expected_end, WordDeleteDirection::Right),
            Ok(TextDeleteRange {
                start_utf16: expected_end,
                end_utf16: long_buffer.len_utf16(),
            })
        );
    }

    #[test]
    fn word_delete_batches_ranges_and_bounds_caret_count() {
        let buffer = TextBuffer::open("one two");
        assert_eq!(
            buffer.word_delete_ranges_utf16(&[3, 7], WordDeleteDirection::Left),
            Ok(vec![
                TextDeleteRange {
                    start_utf16: 0,
                    end_utf16: 3,
                },
                TextDeleteRange {
                    start_utf16: 4,
                    end_utf16: 7,
                },
            ])
        );
        assert_eq!(
            buffer.word_delete_ranges_utf16(
                &vec![0; MAX_WORD_DELETE_CARETS + 1],
                WordDeleteDirection::Right,
            ),
            Err(BufferError::WordDeleteCountTooLarge {
                requested: MAX_WORD_DELETE_CARETS + 1,
                max: MAX_WORD_DELETE_CARETS,
            })
        );
    }

    #[test]
    fn word_part_movement_matches_camel_and_acronym_boundaries() {
        let buffer = TextBuffer::open("thisIsACamelCaseVar");
        let expected = [0, 4, 6, 7, 12, 16, 19];
        let mut offset = 0;
        let mut stops = vec![offset];
        loop {
            let next = buffer
                .word_part_offset_utf16(offset, WordPartDirection::Right)
                .unwrap();
            if next == offset {
                break;
            }
            offset = next;
            stops.push(offset);
        }
        assert_eq!(stops, expected);

        let mut offset = buffer.len_utf16();
        let mut reverse = vec![offset];
        loop {
            let next = buffer
                .word_part_offset_utf16(offset, WordPartDirection::Left)
                .unwrap();
            if next == offset {
                break;
            }
            offset = next;
            reverse.push(offset);
        }
        assert_eq!(reverse, expected.into_iter().rev().collect::<Vec<_>>());

        let acronym = TextBuffer::open("HTTPServer");
        assert_eq!(
            acronym.word_part_offset_utf16(0, WordPartDirection::Right),
            Ok(4)
        );
    }

    #[test]
    fn word_part_movement_splits_underscores_and_skips_default_separators() {
        let buffer = TextBuffer::open("snake_case;next");
        let mut offset = 0;
        let mut right = vec![offset];
        loop {
            let next = buffer
                .word_part_offset_utf16(offset, WordPartDirection::Right)
                .unwrap();
            if next == offset {
                break;
            }
            offset = next;
            right.push(offset);
        }
        assert_eq!(right, [0, 5, 10, 11, 15]);

        let mut offset = buffer.len_utf16();
        let mut left = vec![offset];
        loop {
            let next = buffer
                .word_part_offset_utf16(offset, WordPartDirection::Left)
                .unwrap();
            if next == offset {
                break;
            }
            offset = next;
            left.push(offset);
        }
        assert_eq!(left, [15, 11, 10, 6, 0]);
    }

    #[test]
    fn word_part_movement_keeps_emoji_scalar_safe_and_crosses_crlf_lines() {
        let unicode = TextBuffer::open("go🦊ToValue");
        assert_eq!(
            unicode
                .word_part_offset_utf16(0, WordPartDirection::Right)
                .unwrap(),
            6
        );
        assert_eq!(
            unicode
                .word_part_offset_utf16(unicode.len_utf16(), WordPartDirection::Left)
                .unwrap(),
            6
        );
        assert!(unicode
            .word_part_offset_utf16(3, WordPartDirection::Left)
            .is_err());

        let crlf = TextBuffer::open("firstPart\r\nnextPart");
        assert_eq!(
            crlf.word_part_offset_utf16(9, WordPartDirection::Right)
                .unwrap(),
            11
        );
        assert_eq!(
            crlf.word_part_offset_utf16(11, WordPartDirection::Left)
                .unwrap(),
            9
        );
    }

    #[test]
    fn word_part_movement_scans_long_rope_lines_without_window_limits() {
        let prefix = "a".repeat(100_000);
        let buffer = TextBuffer::open(&format!("{prefix}CamelCase"));
        let end = buffer.len_utf16();
        assert_eq!(
            buffer
                .word_part_offset_utf16(end, WordPartDirection::Left)
                .unwrap(),
            100_005
        );
    }

    #[test]
    fn bounded_read_preserves_bom_crlf_and_utf16_metadata() {
        let buf = TextBuffer::open("\u{FEFF}甲🦊\r\nsecond");
        let first = buf.read_range_utf16(0, 3).unwrap();
        assert_eq!(first.text, "\u{FEFF}甲");
        assert_eq!(first.end_utf16, 2);
        assert_eq!(first.total_utf16_length, 12);
        assert_eq!(first.line_count, 2);
        assert_eq!((first.start_line, first.start_character), (0, 0));

        let emoji = buf.read_range_utf16(2, 1).unwrap();
        assert_eq!(emoji.text, "🦊");
        assert_eq!((emoji.start_line, emoji.start_character), (0, 2));
        assert_eq!(emoji.end_utf16, 4);

        let second_line = buf.read_range_utf16(6, 6).unwrap();
        assert_eq!(second_line.text, "second");
        assert_eq!(
            (second_line.start_line, second_line.start_character),
            (1, 0)
        );
    }

    #[test]
    fn bounded_read_rejects_surrogate_start_and_oversized_request() {
        let buf = TextBuffer::open("a🦊b");
        assert_eq!(
            buf.read_range_utf16(2, 2),
            Err(BufferError::InvalidUtf16Offset { offset_utf16: 2 })
        );
        assert_eq!(
            buf.read_range_utf16(0, MAX_READ_RANGE_UTF16 + 1),
            Err(BufferError::ReadRangeTooLarge {
                requested: MAX_READ_RANGE_UTF16 + 1,
                max: MAX_READ_RANGE_UTF16,
            })
        );
    }

    #[test]
    fn bounded_read_pages_a_very_long_single_line() {
        let text = "x".repeat(100_000);
        let buf = TextBuffer::open(&text);
        let page = buf.read_range_utf16(49_000, 4_096).unwrap();
        assert_eq!(page.text.len(), 4_096);
        assert_eq!(page.text, "x".repeat(4_096));
        assert_eq!(page.total_utf16_length, 100_000);
        assert_eq!(page.line_count, 1);
        assert_eq!(page.end_utf16, 53_096);
    }

    #[test]
    fn line_offsets_are_utf16_absolute_across_bom_emoji_and_crlf() {
        let buf = TextBuffer::open("\u{FEFF}a🦊\r\nb\n");
        assert_eq!(buf.line_offset_utf16(0).unwrap().offset_utf16, 0);
        assert_eq!(buf.line_offset_utf16(1).unwrap().offset_utf16, 6);
        assert_eq!(buf.line_offset_utf16(2).unwrap().offset_utf16, 8);
        assert_eq!(buf.line_offset_utf16(2).unwrap().line_count, 3);
        assert_eq!(
            buf.line_offset_utf16(3),
            Err(BufferError::InvalidLine {
                line: 3,
                line_count: 3,
            })
        );
    }

    #[test]
    fn rectangular_selection_offsets_are_bounded_and_scalar_safe() {
        let buffer = TextBuffer::open("\u{feff}a\n🦊xy\r\nz");
        let selections = buffer.column_selections_utf16(0, 0, 2, 1, 10).unwrap();
        assert_eq!(
            selections,
            vec![
                TextColumnSelection {
                    line: 2,
                    base_offset_utf16: 9,
                    extent_offset_utf16: 10,
                },
                TextColumnSelection {
                    line: 0,
                    base_offset_utf16: 0,
                    extent_offset_utf16: 1,
                },
                TextColumnSelection {
                    line: 1,
                    base_offset_utf16: 3,
                    extent_offset_utf16: 5,
                },
            ]
        );

        let reverse = buffer.column_selections_utf16(1, 2, 0, 0, 10).unwrap();
        assert_eq!(reverse[0].line, 0);
        assert!(reverse[1].base_offset_utf16 > reverse[1].extent_offset_utf16);
        assert_eq!(reverse[1].base_offset_utf16, 5);
        assert_eq!(reverse[1].extent_offset_utf16, 3);
    }

    #[test]
    fn rectangular_selection_rejects_invalid_lines_and_excess_rows() {
        let buffer = TextBuffer::open("a\nb\nc");
        assert_eq!(
            buffer.column_selections_utf16(0, 0, 3, 1, 10),
            Err(BufferError::InvalidLine {
                line: 3,
                line_count: 3,
            })
        );
        assert_eq!(
            buffer.column_selections_utf16(0, 0, 2, 1, 2),
            Err(BufferError::ReadLineCountTooLarge {
                requested: 3,
                max: 2,
            })
        );
    }

    #[test]
    fn line_boundaries_are_utf16_absolute_and_exclude_crlf() {
        let buffer = TextBuffer::open("\t  🦊value \r\n \t\nfinal\n");

        let first = buffer.line_boundary_utf16(5).unwrap();
        assert_eq!(first.version, 1);
        assert_eq!(first.line, 0);
        assert_eq!(first.start_utf16, 0);
        assert_eq!(first.first_non_whitespace_utf16, 3);
        assert_eq!(first.end_utf16, 11);

        let blank = buffer.line_boundary_utf16(13).unwrap();
        assert_eq!(blank.line, 1);
        assert_eq!(blank.start_utf16, 13);
        assert_eq!(blank.first_non_whitespace_utf16, 15);
        assert_eq!(blank.end_utf16, 15);

        let final_empty = buffer.line_boundary_utf16(buffer.len_utf16()).unwrap();
        assert_eq!(final_empty.line, 3);
        assert_eq!(final_empty.start_utf16, 22);
        assert_eq!(final_empty.first_non_whitespace_utf16, 22);
        assert_eq!(final_empty.end_utf16, 22);

        assert_eq!(
            buffer.line_boundary_utf16(4),
            Err(BufferError::InvalidUtf16Offset { offset_utf16: 4 })
        );
    }

    #[test]
    fn line_delete_ranges_follow_boundary_and_selection_semantics() {
        let buffer = TextBuffer::open("ab\r\ncd\nxy");
        assert_eq!(
            buffer
                .line_delete_ranges_utf16(&[(4, 4)], LineDeleteDirection::Left)
                .unwrap(),
            vec![TextDeleteRange {
                start_utf16: 2,
                end_utf16: 4,
            }]
        );
        assert_eq!(
            buffer
                .line_delete_ranges_utf16(&[(2, 2)], LineDeleteDirection::Right)
                .unwrap(),
            vec![TextDeleteRange {
                start_utf16: 2,
                end_utf16: 4,
            }]
        );
        assert_eq!(
            buffer
                .line_delete_ranges_utf16(&[(5, 6)], LineDeleteDirection::Left)
                .unwrap(),
            vec![TextDeleteRange {
                start_utf16: 4,
                end_utf16: 6,
            }]
        );
        assert_eq!(
            buffer
                .line_delete_ranges_utf16(&[(5, 6)], LineDeleteDirection::Right)
                .unwrap(),
            vec![TextDeleteRange {
                start_utf16: 5,
                end_utf16: 6,
            }]
        );
        assert_eq!(
            buffer
                .line_delete_ranges_utf16(&[(4, 4), (5, 5)], LineDeleteDirection::Right,)
                .unwrap(),
            vec![
                TextDeleteRange {
                    start_utf16: 4,
                    end_utf16: 6,
                },
                TextDeleteRange {
                    start_utf16: 5,
                    end_utf16: 6,
                },
            ]
        );

        let unicode = TextBuffer::open("\u{FEFF}a🦊x\r\nb");
        assert_eq!(
            unicode
                .line_delete_ranges_utf16(&[(7, 7)], LineDeleteDirection::Left)
                .unwrap(),
            vec![TextDeleteRange {
                start_utf16: 5,
                end_utf16: 7,
            }]
        );
        assert_eq!(
            unicode
                .line_delete_ranges_utf16(&[(5, 5)], LineDeleteDirection::Right)
                .unwrap(),
            vec![TextDeleteRange {
                start_utf16: 5,
                end_utf16: 7,
            }]
        );
    }

    #[test]
    fn line_delete_ranges_validate_utf16_offsets_ranges_and_count() {
        let buffer = TextBuffer::open("🦊\r\nx");
        assert_eq!(
            buffer.line_delete_ranges_utf16(&[(1, 1)], LineDeleteDirection::Left),
            Err(BufferError::InvalidUtf16Offset { offset_utf16: 1 })
        );
        assert_eq!(
            buffer.line_delete_ranges_utf16(&[(2, 1)], LineDeleteDirection::Right),
            Err(BufferError::InvalidDeleteRange {
                start_utf16: 2,
                end_utf16: 1,
            })
        );
        assert_eq!(
            buffer.line_delete_ranges_utf16(
                &vec![(0, 0); MAX_LINE_DELETE_RANGES + 1],
                LineDeleteDirection::Left,
            ),
            Err(BufferError::LineDeleteCountTooLarge {
                requested: MAX_LINE_DELETE_RANGES + 1,
                max: MAX_LINE_DELETE_RANGES,
            })
        );
    }

    #[test]
    fn transpose_ranges_match_code_oss_caret_and_end_of_line_rules() {
        let buffer = TextBuffer::open("abc\nxy");
        assert_eq!(
            buffer.transpose_ranges_utf16(&[1, 3]).unwrap(),
            vec![
                Some(TextTransposePlan {
                    start_utf16: 0,
                    end_utf16: 2,
                    removed_text: "ab".to_owned(),
                    inserted_text: "ba".to_owned(),
                }),
                Some(TextTransposePlan {
                    start_utf16: 1,
                    end_utf16: 3,
                    removed_text: "bc".to_owned(),
                    inserted_text: "cb".to_owned(),
                }),
            ]
        );
        assert_eq!(
            buffer.transpose_ranges_utf16(&[3]).unwrap(),
            vec![Some(TextTransposePlan {
                start_utf16: 1,
                end_utf16: 3,
                removed_text: "bc".to_owned(),
                inserted_text: "cb".to_owned(),
            })]
        );
    }

    #[test]
    fn transpose_ranges_swap_unicode_scalars_and_crlf_boundary_tokens() {
        let unicode = TextBuffer::open("🦊a");
        assert_eq!(
            unicode.transpose_ranges_utf16(&[2]).unwrap(),
            vec![Some(TextTransposePlan {
                start_utf16: 0,
                end_utf16: 3,
                removed_text: "🦊a".to_owned(),
                inserted_text: "a🦊".to_owned(),
            })]
        );
        assert_eq!(
            unicode.transpose_ranges_utf16(&[1]),
            Err(BufferError::InvalidUtf16Offset { offset_utf16: 1 })
        );

        let crlf = TextBuffer::open("ab\r\ncd");
        assert_eq!(
            crlf.transpose_ranges_utf16(&[4]).unwrap(),
            vec![Some(TextTransposePlan {
                start_utf16: 2,
                end_utf16: 5,
                removed_text: "\r\nc".to_owned(),
                inserted_text: "c\r\n".to_owned(),
            })]
        );

        let cr_only = TextBuffer::open("ab\rcd");
        assert_eq!(cr_only.rope.len_lines(), 2);
        assert_eq!(
            cr_only.transpose_ranges_utf16(&[2, 3]).unwrap(),
            vec![
                Some(TextTransposePlan {
                    start_utf16: 0,
                    end_utf16: 2,
                    removed_text: "ab".to_owned(),
                    inserted_text: "ba".to_owned(),
                }),
                Some(TextTransposePlan {
                    start_utf16: 2,
                    end_utf16: 4,
                    removed_text: "\rc".to_owned(),
                    inserted_text: "c\r".to_owned(),
                }),
            ]
        );
    }

    #[test]
    fn transpose_ranges_keep_file_start_and_single_character_noops() {
        let buffer = TextBuffer::open("a");
        assert_eq!(
            buffer.transpose_ranges_utf16(&[0, 1]).unwrap(),
            vec![None, None]
        );
        assert_eq!(
            TextBuffer::open("a\n")
                .transpose_ranges_utf16(&[2])
                .unwrap(),
            vec![Some(TextTransposePlan {
                start_utf16: 0,
                end_utf16: 2,
                removed_text: "a\n".to_owned(),
                inserted_text: "\na".to_owned(),
            })]
        );
    }

    #[test]
    fn transpose_ranges_validate_count_limit() {
        let buffer = TextBuffer::open("ab");
        assert_eq!(
            buffer.transpose_ranges_utf16(&vec![0; MAX_TRANSPOSE_CARETS + 1]),
            Err(BufferError::TransposeCountTooLarge {
                requested: MAX_TRANSPOSE_CARETS + 1,
                max: MAX_TRANSPOSE_CARETS,
            })
        );
    }

    #[test]
    fn overtype_paste_ranges_use_utf16_and_stop_before_line_terminators() {
        let buffer = TextBuffer::open("\u{FEFF}a🦊z\r\nnext");
        assert_eq!(
            buffer
                .overtype_paste_ranges_utf16(&[(2, 2, 3), (2, 4, 1), (4, 4, 2), (7, 7, 2)])
                .unwrap(),
            vec![
                TextDeleteRange {
                    start_utf16: 2,
                    end_utf16: 5,
                },
                TextDeleteRange {
                    start_utf16: 2,
                    end_utf16: 4,
                },
                TextDeleteRange {
                    start_utf16: 4,
                    end_utf16: 5,
                },
                TextDeleteRange {
                    start_utf16: 7,
                    end_utf16: 9,
                },
            ]
        );
    }

    #[test]
    fn overtype_paste_ranges_snap_surrogate_and_clamp_multiline_paste_to_active_line() {
        let emoji = TextBuffer::open("a🦊b");
        assert_eq!(
            emoji.overtype_paste_ranges_utf16(&[(1, 1, 1)]).unwrap(),
            vec![TextDeleteRange {
                start_utf16: 1,
                end_utf16: 3,
            }]
        );

        let multiline = TextBuffer::open("abcdef\nnext");
        assert_eq!(
            multiline
                .overtype_paste_ranges_utf16(&[(1, 1, 32)])
                .unwrap(),
            vec![TextDeleteRange {
                start_utf16: 1,
                end_utf16: 6,
            }]
        );
    }

    #[test]
    fn overtype_paste_ranges_validate_offsets_order_and_count() {
        let buffer = TextBuffer::open("🦊\r\nx");
        assert_eq!(
            buffer.overtype_paste_ranges_utf16(&[(1, 1, 1)]),
            Err(BufferError::InvalidUtf16Offset { offset_utf16: 1 })
        );
        assert_eq!(
            buffer.overtype_paste_ranges_utf16(&[(2, 1, 1)]),
            Err(BufferError::InvalidOvertypePasteRange {
                start_utf16: 2,
                end_utf16: 1,
            })
        );
        assert_eq!(
            buffer.overtype_paste_ranges_utf16(&vec![(0, 0, 1); MAX_OVERTYPE_PASTE_RANGES + 1]),
            Err(BufferError::OvertypePasteCountTooLarge {
                requested: MAX_OVERTYPE_PASTE_RANGES + 1,
                max: MAX_OVERTYPE_PASTE_RANGES,
            })
        );
    }

    #[test]
    fn line_boundaries_find_smart_home_on_a_long_rope_line() {
        let indentation = " ".repeat(100_000);
        let buffer = TextBuffer::open(&format!("{indentation}🦊tail"));
        let boundary = buffer.line_boundary_utf16(100_004).unwrap();
        assert_eq!(boundary.start_utf16, 0);
        assert_eq!(boundary.first_non_whitespace_utf16, 100_000);
        assert_eq!(boundary.end_utf16, 100_006);
    }

    #[test]
    fn final_empty_line_has_document_end_offset() {
        let buf = TextBuffer::open("last\n");
        let last = buf.line_offset_utf16(1).unwrap();
        assert_eq!(last.offset_utf16, 5);
        assert_eq!(last.total_utf16_length, 5);
    }

    #[test]
    fn bounded_line_windows_trim_bom_crlf_and_keep_utf16_offsets() {
        let buf = TextBuffer::open("\u{FEFF}a🦊\r\nsecond\n");
        let page = buf.read_lines_utf16(0, 3, 0, 8, 24).unwrap();
        assert_eq!(page.version, 1);
        assert_eq!(page.total_utf16_length, 13);
        assert_eq!(page.line_count, 3);
        assert_eq!(page.first_line, 0);
        assert_eq!(page.lines.len(), 3);
        assert_eq!(page.lines[0].text, "\u{FEFF}a🦊");
        assert_eq!((page.lines[0].start_utf16, page.lines[0].end_utf16), (0, 4));
        assert_eq!(page.lines[1].text, "second");
        assert_eq!(
            (page.lines[1].start_utf16, page.lines[1].end_utf16),
            (6, 12)
        );
        assert_eq!(page.lines[2].text, "");
        assert_eq!(
            (page.lines[2].start_utf16, page.lines[2].end_utf16),
            (13, 13)
        );
    }

    #[test]
    fn line_window_horizontal_offset_moves_back_from_surrogate_middle() {
        let buf = TextBuffer::open("a🦊z\r\nnext");
        let page = buf.read_lines_utf16(0, 2, 2, 8, 16).unwrap();
        assert_eq!(page.lines[0].text, "🦊z");
        assert_eq!((page.lines[0].start_utf16, page.lines[0].end_utf16), (1, 4));
        assert_eq!(page.lines[1].text, "xt");
        assert_eq!(
            (page.lines[1].start_utf16, page.lines[1].end_utf16),
            (8, 10)
        );
    }

    #[test]
    fn long_line_windows_are_bounded_and_can_jump_horizontally() {
        let buf = TextBuffer::open(&"x".repeat(100_000));
        let page = buf.read_lines_utf16(0, 1, 90_000, 2_048, 2_048).unwrap();
        assert_eq!(page.line_count, 1);
        assert_eq!(page.lines[0].start_utf16, 90_000);
        assert_eq!(page.lines[0].end_utf16, 92_048);
        assert_eq!(page.lines[0].text, "x".repeat(2_048));
    }

    #[test]
    fn bounded_line_windows_address_the_end_of_a_10k_line_document() {
        let text = (0..10_000)
            .map(|line| format!("line-{line}"))
            .collect::<Vec<_>>()
            .join("\n");
        let buf = TextBuffer::open(&text);
        let page = buf.read_lines_utf16(9_984, 16, 0, 32, 512).unwrap();
        assert_eq!(page.line_count, 10_000);
        assert_eq!(page.first_line, 9_984);
        assert_eq!(page.lines.len(), 16);
        assert_eq!(page.lines.last().unwrap().line, 9_999);
        assert_eq!(page.lines.last().unwrap().text, "line-9999");
    }

    #[test]
    fn line_window_rejects_unbounded_or_inconsistent_limits() {
        let buf = TextBuffer::open("a\nb");
        assert_eq!(
            buf.read_lines_utf16(0, 257, 0, 2, 514),
            Err(BufferError::ReadLineCountTooLarge {
                requested: 257,
                max: 256,
            })
        );
        assert_eq!(
            buf.read_lines_utf16(0, 2, 0, 4, 7),
            Err(BufferError::InvalidLineWindow {
                max_lines: 2,
                max_line_utf16: 4,
                max_total_utf16: 7,
            })
        );
    }

    #[test]
    fn minimap_sample_is_evenly_distributed_and_bounded_for_large_documents() {
        let text = (0..10_000)
            .map(|line| format!("line-{line}-{}", "x".repeat(100)))
            .collect::<Vec<_>>()
            .join("\n");
        let buffer = TextBuffer::open(&text);

        let sample = buffer.minimap_sample();

        assert_eq!(sample.version, buffer.version());
        assert_eq!(sample.line_count, 10_000);
        assert_eq!(sample.lines.len(), MAX_MINIMAP_SAMPLE_LINES);
        assert_eq!(sample.lines.first().unwrap().line, 0);
        assert_eq!(sample.lines.last().unwrap().line, 9_999);
        assert_eq!(sample.lines.first().unwrap().start_utf16, 0);
        assert!(sample
            .lines
            .windows(2)
            .all(|pair| pair[0].start_utf16 < pair[1].start_utf16));
        assert!(sample
            .lines
            .windows(2)
            .all(|pair| pair[0].line < pair[1].line));
        assert!(sample
            .lines
            .iter()
            .all(|line| line.text.encode_utf16().count() <= MAX_MINIMAP_LINE_SAMPLE_UTF16));
        assert_eq!(
            sample.lines.last().unwrap().utf16_length,
            "line-9999-".len() + 100
        );
    }

    #[test]
    fn minimap_sample_trims_crlf_and_keeps_utf16_lengths_and_scalar_boundaries() {
        let buffer = TextBuffer::open(&format!("a\r\n{}\n", "🦊".repeat(80)));

        let sample = buffer.minimap_sample();

        assert_eq!(sample.line_count, 3);
        assert_eq!(sample.lines[0].text, "a");
        assert_eq!(sample.lines[0].start_utf16, 0);
        assert_eq!(sample.lines[0].utf16_length, 1);
        assert_eq!(sample.lines[1].utf16_length, 160);
        assert_eq!(sample.lines[1].start_utf16, 3);
        assert_eq!(sample.lines[1].text, "🦊".repeat(24));
        assert_eq!(sample.lines[1].text.encode_utf16().count(), 48);
        assert_eq!(sample.lines[2].text, "");
        assert_eq!(sample.lines[2].start_utf16, 164);
        assert_eq!(sample.lines[2].utf16_length, 0);
    }

    #[test]
    fn apply_ops_is_sequential() {
        let mut buf = TextBuffer::open("{}");
        buf.apply_ops(&[
            TextOp::Insert {
                offset_utf16: 1,
                text: "a".into(),
            },
            TextOp::Insert {
                offset_utf16: 2,
                text: "b".into(),
            },
        ])
        .unwrap();
        assert_eq!(buf.text(), "{ab}");
        assert_eq!(buf.version(), 3);
    }

    #[test]
    fn savepoint_tracks_exact_utf8_text_and_revert_without_bumping_version() {
        let mut buf = TextBuffer::open("\u{FEFF}甲🦊\r\n");
        assert!(!buf.is_dirty());
        assert!(buf.savepoint_matches_text("\u{FEFF}甲🦊\r\n"));

        buf.apply(&TextOp::Insert {
            offset_utf16: buf.len_utf16(),
            text: "x".into(),
        })
        .unwrap();
        assert!(buf.is_dirty());
        assert!(buf.savepoint_matches_text("\u{FEFF}甲🦊\r\n"));

        buf.apply(&TextOp::Delete {
            offset_utf16: buf.len_utf16() - 1,
            len_utf16: 1,
        })
        .unwrap();
        assert!(!buf.is_dirty());

        let version_before_mark = buf.version();
        buf.mark_saved();
        assert_eq!(buf.version(), version_before_mark);
        assert!(!buf.is_dirty());

        buf.set_savepoint_text("disk 🦊\r\n");
        assert_eq!(buf.version(), version_before_mark);
        assert!(buf.is_dirty());
        assert!(buf.savepoint_matches_text("disk 🦊\r\n"));
        assert!(!buf.savepoint_matches_text("disk 🦊\n"));
    }

    #[test]
    fn emoji_insertion_from_diff_style_ops_roundtrips() {
        // 模拟 Dart 侧 diff 产生的操作序列：在中文与 Emoji 混排文本中编辑。
        // "打印 hello..." 中 'h' 位于 UTF-16 offset 3（打=1 印=1 空格=1）。
        let mut buf = TextBuffer::open("打印 hello\n运行 🚀 model\n");
        buf.apply_ops(&[
            TextOp::Delete {
                offset_utf16: 3,
                len_utf16: 1, // 换掉 h
            },
            TextOp::Insert {
                offset_utf16: 3,
                text: "H".into(),
            },
        ])
        .unwrap();
        assert_eq!(buf.text(), "打印 Hello\n运行 🚀 model\n");
    }
}
