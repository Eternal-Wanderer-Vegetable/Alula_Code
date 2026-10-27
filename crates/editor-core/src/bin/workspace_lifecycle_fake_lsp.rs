//! P00.3 process-lifecycle fixture used by the editor-core integration test.

use serde_json::{json, Value};
use std::io::{BufRead, BufReader, Write};

fn read_message(reader: &mut impl BufRead) -> Option<Value> {
    let mut content_length = None;
    loop {
        let mut line = String::new();
        if reader.read_line(&mut line).ok()? == 0 {
            return None;
        }
        let line = line.trim_end();
        if line.is_empty() {
            break;
        }
        if let Some(value) = line.strip_prefix("Content-Length:") {
            content_length = value.trim().parse::<usize>().ok();
        }
    }
    let mut body = vec![0; content_length?];
    reader.read_exact(&mut body).ok()?;
    serde_json::from_slice(&body).ok()
}

fn send(value: &Value) {
    let body = serde_json::to_vec(value).unwrap();
    let stdout = std::io::stdout();
    let mut lock = stdout.lock();
    write!(lock, "Content-Length: {}\r\n\r\n", body.len()).unwrap();
    lock.write_all(&body).unwrap();
    lock.flush().unwrap();
}

fn main() {
    let stdin = std::io::stdin();
    let mut reader = BufReader::new(stdin.lock());
    while let Some(message) = read_message(&mut reader) {
        match message.get("method").and_then(Value::as_str).unwrap_or("") {
            "initialize" => send(&json!({
                "jsonrpc": "2.0",
                "id": message["id"],
                "result": {"capabilities": {"textDocumentSync": 1}},
            })),
            "shutdown" => send(&json!({
                "jsonrpc": "2.0",
                "id": message["id"],
                "result": null,
            })),
            "exit" => break,
            _ => {}
        }
    }
}
