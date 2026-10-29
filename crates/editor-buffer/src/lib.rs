//! Alula Code 的文本缓冲区：Ropey 之上的增量操作层。
//!
//! 坐标口径（见 docs/02-关键技术设计 §2.3）：跨 FFI / LSP 边界的 offset 一律使用
//! UTF-16 code unit；本 crate 负责向 Ropey 的 char 索引换算，并拒绝落在
//! 代理对中间等非法边界上的操作。

use ropey::Rope;
use serde::{Deserialize, Serialize};

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
        }
    }
}

impl std::error::Error for BufferError {}

/// 权威文本状态（V1：作为 Rust 侧同步分析副本；见 docs/02 §5）。
/// version 从 1 开始，每成功应用一个操作 +1。
#[derive(Clone)]
pub struct TextBuffer {
    rope: Rope,
    version: u64,
}

impl TextBuffer {
    pub fn open(content: &str) -> Self {
        TextBuffer {
            rope: Rope::from_str(content),
            version: 1,
        }
    }

    pub fn version(&self) -> u64 {
        self.version
    }

    pub fn text(&self) -> String {
        self.rope.to_string()
    }

    pub fn len_utf16(&self) -> usize {
        self.rope.len_utf16_cu()
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
