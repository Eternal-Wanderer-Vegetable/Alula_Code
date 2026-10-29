//! P00.3 process-lifecycle fixture used by the editor-core integration test.

use serde_json::{json, Value};
use std::{
    fs::OpenOptions,
    io::{BufRead, BufReader, Write},
    path::PathBuf,
};

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

fn trace(path: &PathBuf, method: &str) {
    let mut file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .expect("open trace file");
    writeln!(file, "{method}").expect("write trace file");
    file.flush().expect("flush trace file");
}

fn main() {
    let trace_path = std::env::args_os()
        .nth(1)
        .map(PathBuf::from)
        .expect("trace path argument");
    let stdin = std::io::stdin();
    let mut reader = BufReader::new(stdin.lock());
    while let Some(message) = read_message(&mut reader) {
        let method = message.get("method").and_then(Value::as_str).unwrap_or("");
        match method {
            "initialize" => send(&json!({
                "jsonrpc": "2.0",
                "id": message["id"],
                "result": {"capabilities": {"textDocumentSync": 1}},
            })),
            "textDocument/didOpen" | "textDocument/didClose" | "shutdown" | "exit" => {
                trace(&trace_path, method);
                if method == "shutdown" {
                    send(&json!({
                        "jsonrpc": "2.0",
                        "id": message["id"],
                        "result": null,
                    }));
                } else if method == "exit" {
                    break;
                }
            }
            _ => {}
        }
    }
}
