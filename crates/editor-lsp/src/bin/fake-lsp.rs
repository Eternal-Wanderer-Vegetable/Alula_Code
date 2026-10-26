//! 测试用最小 LSP 服务器：
//! - initialize → 返回 capabilities
//! - textDocument/didOpen → 推送一条 publishDiagnostics
//! - textDocument/completion → 返回固定补全项
//! 仅用于 editor-lsp 的集成测试，覆盖客户端的帧解析与双向消息路由。

use std::io::{BufRead, BufReader, Read, Write};
use std::process::exit;

fn read_message(reader: &mut impl BufRead) -> Option<serde_json::Value> {
    let mut content_length: Option<usize> = None;
    loop {
        let mut line = String::new();
        let n = reader.read_line(&mut line).ok()?;
        if n == 0 {
            return None;
        }
        let line = line.trim_end();
        if line.is_empty() {
            break;
        }
        if let Some(v) = line.strip_prefix("Content-Length:") {
            content_length = v.trim().parse().ok();
        }
    }
    let len = content_length?;
    let mut body = vec![0u8; len];
    reader.read_exact(&mut body).ok()?;
    serde_json::from_slice(&body).ok()
}

fn send(value: &serde_json::Value) {
    let body = serde_json::to_string(value).unwrap();
    let stdout = std::io::stdout();
    let mut lock = stdout.lock();
    // 精确 LSP 帧：头部与正文以 \r\n\r\n 分隔，正文后不留多余字节
    write!(lock, "Content-Length: {}\r\n\r\n{}", body.len(), body).unwrap();
    lock.flush().unwrap();
}

fn main() {
    let stdin = std::io::stdin();
    let mut reader = BufReader::new(stdin.lock());
    while let Some(msg) = read_message(&mut reader) {
        let method = msg.get("method").and_then(|m| m.as_str()).unwrap_or("");
        match method {
            "initialize" => {
                send(&serde_json::json!({
                    "jsonrpc": "2.0",
                    "id": msg["id"],
                    "result": {"capabilities": {"textDocumentSync": 1}},
                }));
            }
            "initialized" => {}
            "textDocument/didOpen" => {
                let uri = msg["params"]["textDocument"]["uri"].clone();
                send(&serde_json::json!({
                    "jsonrpc": "2.0",
                    "method": "textDocument/publishDiagnostics",
                    "params": {
                        "uri": uri,
                        "diagnostics": [{
                            "range": {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 1}},
                            "severity": 1,
                            "message": "fake error from fake-lsp",
                            "source": "fake-lsp",
                        }],
                    },
                }));
            }
            "textDocument/completion" => {
                send(&serde_json::json!({
                    "jsonrpc": "2.0",
                    "id": msg["id"],
                    "result": [
                        {"label": "fake_completion_a", "insertText": "fake_a()"},
                        {"label": "fake_completion_b"},
                    ],
                }));
            }
            "shutdown" => {
                send(&serde_json::json!({"jsonrpc": "2.0", "id": msg["id"], "result": null}));
            }
            "exit" => exit(0),
            _ => {}
        }
    }
}
