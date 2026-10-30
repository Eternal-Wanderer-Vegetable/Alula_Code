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

/// 一个符号定义（大纲用）：tree-sitter 定义节点提取。
#[derive(Debug, Clone, serde::Serialize)]
pub struct Symbol {
    /// 类别标签：function/struct/enum/trait/impl/mod/const/static/type/macro
    pub kind: String,
    /// 符号名（impl 为被实现类型，如 "Foo"；trait impl 为 "Trait for Foo"）。
    pub name: String,
    /// UTF-16 code unit 起始偏移（与 Dart/LSP 口径一致）。
    pub start_utf16: usize,
    /// 1-based 起始行。
    pub line: usize,
    /// 1-based 结束行（含），用于折叠范围与 sticky scroll。
    pub end_line: usize,
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

    /// 提取符号定义（大纲视图用）：遍历语法树收集定义类节点。
    /// 含嵌套（impl 里的方法、mod 里的项），按文档顺序输出。
    pub fn symbols(&mut self, text: &str) -> Result<Vec<Symbol>, String> {
        let tree = self
            .parser
            .parse(text, None)
            .ok_or("tree-sitter 解析返回 None")?;

        // 字节偏移 → UTF-16（与 parse 相同口径）
        let u16_at =
            |byte_off: usize, text: &str| -> usize { text[..byte_off].encode_utf16().count() };

        let mut out: Vec<Symbol> = Vec::new();

        // 定义类节点：kind → 类别标签
        const DEF_KINDS: &[(&str, &str)] = &[
            ("function_item", "function"),
            ("struct_item", "struct"),
            ("enum_item", "enum"),
            ("trait_item", "trait"),
            ("impl_item", "impl"),
            ("mod_item", "mod"),
            ("const_item", "const"),
            ("static_item", "static"),
            ("type_item", "type"),
            ("macro_definition", "macro"),
        ];

        fn walk(
            node: tree_sitter::Node,
            text: &str,
            u16_at: &dyn Fn(usize, &str) -> usize,
            defs: &[(&str, &str)],
            out: &mut Vec<Symbol>,
            depth: usize,
        ) {
            if depth > 12 {
                return; // 深度保险
            }
            let kind = node.kind();
            if let Some((_, label)) = defs.iter().find(|(k, _)| *k == kind) {
                let name_node = if kind == "impl_item" {
                    // impl 没有 name 字段：取被实现类型（含 trait 前缀）
                    node.child_by_field_name("trait")
                        .map(|t| {
                            let ty = node
                                .child_by_field_name("type")
                                .map(|n| n.utf8_text(text.as_bytes()).unwrap_or("?"))
                                .unwrap_or("?");
                            format!("{} for {}", t.utf8_text(text.as_bytes()).unwrap_or("?"), ty)
                        })
                        .unwrap_or_else(|| {
                            node.child_by_field_name("type")
                                .map(|n| n.utf8_text(text.as_bytes()).unwrap_or("?").to_string())
                                .unwrap_or_default()
                        })
                } else {
                    node.child_by_field_name("name")
                        .map(|n| n.utf8_text(text.as_bytes()).unwrap_or("?").to_string())
                        .unwrap_or_default()
                };
                if !name_node.is_empty() {
                    out.push(Symbol {
                        kind: (*label).to_string(),
                        name: name_node,
                        start_utf16: u16_at(node.start_byte(), text),
                        line: node.start_position().row + 1,
                        end_line: node.end_position().row + 1,
                    });
                }
            }
            let mut cursor = node.walk();
            for child in node.children(&mut cursor) {
                walk(child, text, u16_at, defs, out, depth + 1);
            }
        }

        let root = tree.root_node();
        walk(root, text, &u16_at, DEF_KINDS, &mut out, 0);
        out.sort_by_key(|sym| sym.start_utf16);
        Ok(out)
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
    fn symbols_extracted_with_kinds_lines_utf16() {
        let mut engine = SyntaxEngine::rust().unwrap();
        let code = "// 中文注释
fn main() {
    inner_fn();
}
            struct Point { x: i32 }
enum Color { Red }
trait Shape {
    fn area(&self) -> f64;
}
            impl Shape for Point {
    fn area(&self) -> f64 { 0.0 }
}
            mod inner {
    pub fn helper() {}
}
const MAX: i32 = 10;
";
        let symbols = engine.symbols(code).unwrap();

        let kinds: Vec<&str> = symbols.iter().map(|s| s.kind.as_str()).collect();
        assert!(
            kinds.contains(&"function"),
            "应含 function（main/area/helper）"
        );
        assert!(kinds.contains(&"struct"));
        assert!(kinds.contains(&"enum"));
        assert!(kinds.contains(&"trait"));
        assert!(kinds.contains(&"impl"));
        assert!(kinds.contains(&"mod"));
        assert!(kinds.contains(&"const"));

        // impl 的名字 = "Trait for Type"
        let imp = symbols.iter().find(|s| s.kind == "impl").unwrap();
        assert_eq!(imp.name, "Shape for Point");

        // main 在第 2 行（中文注释占第 1 行）
        let main = symbols.iter().find(|s| s.name == "main").unwrap();
        assert_eq!(main.line, 2);
        // UTF-16 偏移切片回验：偏移处应是 "fn"
        let u16s: Vec<u16> = code.encode_utf16().collect();
        let piece: String = String::from_utf16_lossy(&u16s[main.start_utf16..main.start_utf16 + 2]);
        assert_eq!(piece, "fn");

        // 按文档顺序
        let starts: Vec<usize> = symbols.iter().map(|s| s.start_utf16).collect();
        let mut sorted = starts.clone();
        sorted.sort_unstable();
        assert_eq!(starts, sorted, "应按文档顺序输出");

        // helper（mod 内嵌套函数）也被收集
        assert!(symbols.iter().any(|s| s.name == "helper"));
    }

    #[test]
    fn symbol_end_lines_cover_nested_scopes_with_bom_emoji_and_crlf() {
        let mut engine = SyntaxEngine::rust().unwrap();
        let code = "\u{FEFF}// 🦊\r\nfn outer() {\r\n    fn inner() {}\r\n}\r\n";
        let symbols = engine.symbols(code).unwrap();
        let outer = symbols
            .iter()
            .find(|symbol| symbol.name == "outer")
            .unwrap();
        let inner = symbols
            .iter()
            .find(|symbol| symbol.name == "inner")
            .unwrap();

        assert_eq!(outer.line, 2);
        assert_eq!(outer.end_line, 4);
        assert_eq!(
            outer.start_utf16,
            "\u{FEFF}// 🦊\r\n".encode_utf16().count()
        );
        assert_eq!(inner.line, 3);
        assert_eq!(inner.end_line, 3);
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
