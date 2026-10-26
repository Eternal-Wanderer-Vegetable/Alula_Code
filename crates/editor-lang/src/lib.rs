//! Tree-sitter 语法引擎：增量文本 → 高亮 token（UTF-16 区间 + 语义类别）。
//!
//! MVP 为整篇重解析（小文件毫秒级）；增量解析（edit + parse(old_tree)）
//! 列入 Phase 1（docs/02 §1 editor-lang 职责）。捕获类别直接透传
//! tree-sitter-rust 的 highlights query 捕获名（keyword/function/string/
//! comment/type/…），由 UI 层映射颜色。

use tree_sitter::{Parser, Query, QueryCursor, StreamingIterator};

#[derive(Debug, Clone, serde::Serialize)]
pub struct Token {
    /// UTF-16 code unit 起始（与 Dart / LSP 口径一致）
    pub start_utf16: usize,
    /// UTF-16 code unit 结束（不含）
    pub end_utf16: usize,
    /// tree-sitter highlights query 的捕获名（如 "keyword"、"string"）
    pub kind: String,
}

pub struct SyntaxEngine {
    parser: Parser,
    query: Query,
    capture_names: Vec<String>,
}

/// 频繁出现的捕获名白名单：过滤 query 里的非着色捕获，减少 token 量。
const INTERESTING: &[&str] = &[
    "keyword",
    "keyword.function",
    "keyword.conditional",
    "keyword.repeat",
    "keyword.modifier",
    "function",
    "function.call",
    "method",
    "string",
    "comment",
    "type",
    "constant",
    "number",
    "property",
    "variable",
];

impl SyntaxEngine {
    /// Rust 语法引擎。
    pub fn rust() -> Result<Self, String> {
        let mut parser = Parser::new();
        let language = tree_sitter_rust::LANGUAGE.into();
        parser
            .set_language(&language)
            .map_err(|e| format!("set_language 失败: {e}"))?;
        let query_text: &str = tree_sitter_rust::HIGHLIGHTS_QUERY;
        let query = Query::new(&language, query_text)
            .map_err(|e| format!("highlights query 编译失败: {e}"))?;
        let capture_names = query
            .capture_names()
            .iter()
            .map(|s| s.to_string())
            .collect();
        Ok(SyntaxEngine {
            parser,
            query,
            capture_names,
        })
    }

    /// 解析全文并输出高亮 token（按文档顺序，区间不重叠）。
    pub fn parse(&mut self, text: &str) -> Result<Vec<Token>, String> {
        let tree = self
            .parser
            .parse(text, None)
            .ok_or("tree-sitter 解析返回 None")?;
        let mut cursor = QueryCursor::new();
        let mut matches = cursor.matches(&self.query, tree.root_node(), text.as_bytes());

        // (byte_start, byte_end, kind)；同一区间取先出现的类别
        let mut spans: Vec<(usize, usize, String)> = Vec::new();
        while let Some(m) = matches.next() {
            for cap in m.captures {
                let name = self
                    .capture_names
                    .get(cap.index as usize)
                    .cloned()
                    .unwrap_or_default();
                if !INTERESTING.iter().any(|k| name.starts_with(k)) {
                    continue;
                }
                let start = cap.node.start_byte();
                let end = cap.node.end_byte();
                if end <= start || end > text.len() {
                    continue;
                }
                spans.push((start, end, name));
            }
        }
        spans.sort_by_key(|(s, e, _)| (*s, std::cmp::Reverse(*e)));

        // 字节偏移 → UTF-16 偏移，并合并重叠区间
        let mut tokens = Vec::new();
        let mut covered_end_byte = 0usize;

        // 预计算：逐 span 转换（文本量小；增量/缓存优化留待 Phase 1）
        let u16_at =
            |byte_off: usize, text: &str| -> usize { text[..byte_off].encode_utf16().count() };

        for (start, end, kind) in spans {
            if start < covered_end_byte {
                continue; // 与前一个 token 重叠：丢弃（保留先出现的）
            }
            let start_u16 = u16_at(start, text);
            let end_u16 = u16_at(end, text);
            if end_u16 > start_u16 {
                tokens.push(Token {
                    start_utf16: start_u16,
                    end_utf16: end_u16,
                    kind: kind.clone(),
                });
            }
            covered_end_byte = end;
        }
        Ok(tokens)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rust_tokens_extracted_with_utf16_offsets() {
        let mut engine = SyntaxEngine::rust().unwrap();
        // 中文字符串：UTF-16 与字节偏移必须都正确
        let code = "fn main() {\n    let s = \"你好\"; // 注释\n}\n";
        let tokens = engine.parse(code).unwrap();

        let has = |kind: &str| tokens.iter().any(|t| t.kind.starts_with(kind));
        assert!(has("keyword"), "应含 keyword（fn/let）");
        assert!(has("function"), "应含 function（main）");
        assert!(has("string"), "应含 string");
        assert!(has("comment"), "应含 comment");

        // 抽取每个 token 的原文验证偏移正确性（UTF-16 → Dart 端将做同样切分）
        let u16s: Vec<u16> = code.encode_utf16().collect();
        for t in &tokens {
            let piece: String = String::from_utf16_lossy(&u16s[t.start_utf16..t.end_utf16]);
            assert!(!piece.is_empty());
            // string token 的原文应包含引号内内容
            if t.kind == "string" {
                assert!(piece.contains("你好"), "string token 原文应含中文: {piece}");
            }
            if t.kind == "comment" {
                assert!(
                    piece.contains("注释"),
                    "comment token 原文应含中文: {piece}"
                );
            }
        }
    }

    #[test]
    fn empty_and_invalid_input() {
        let mut engine = SyntaxEngine::rust().unwrap();
        assert!(engine.parse("").unwrap().is_empty());
        // 语法错误的文本也应产出 token（tree-sitter 容错解析）
        let tokens = engine.parse("fn broken( {{").unwrap();
        assert!(!tokens.is_empty());
    }
}
