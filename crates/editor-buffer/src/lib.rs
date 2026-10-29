//! Alula Code 的文本缓冲区：Ropey 之上的增量操作层。
//!
//! 坐标口径（见 docs/02-关键技术设计 §2.3）：跨 FFI / LSP 边界的 offset 一律使用
//! UTF-16 code unit；本 crate 负责向 Ropey 的 char 索引换算，并拒绝落在
//! 代理对中间等非法边界上的操作。

use ropey::Rope;
use serde::{Deserialize, Serialize};

/// Maximum UTF-16 units requested by one bounded document read.
pub const MAX_READ_RANGE_UTF16: usize = 64 * 1024;
/// Maximum number of line windows returned by one editor viewport request.
pub const MAX_READ_LINES: usize = 256;

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
