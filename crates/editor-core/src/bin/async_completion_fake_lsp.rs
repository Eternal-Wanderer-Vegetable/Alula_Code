//! P01 fixture for asynchronous completion, cancellation, and workspace cleanup.

use serde_json::{json, Value};
use std::{
    collections::HashSet,
    fs::OpenOptions,
    io::{BufRead, BufReader, Write},
    path::PathBuf,
    sync::{Arc, Condvar, Mutex},
    thread,
    time::Duration,
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

fn send(value: Value) {
    let body = serde_json::to_vec(&value).unwrap();
    let stdout = std::io::stdout();
    let mut lock = stdout.lock();
    write!(lock, "Content-Length: {}\r\n\r\n", body.len()).unwrap();
    lock.write_all(&body).unwrap();
    lock.flush().unwrap();
}

fn trace(path: &PathBuf, value: &str) {
    let mut file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .expect("open trace file");
    writeln!(file, "{value}").expect("write trace file");
    file.flush().expect("flush trace file");
}

fn main() {
    let mut args = std::env::args_os().skip(1);
    let trace_path = PathBuf::from(args.next().expect("trace path argument"));
    let delay_ms = args
        .next()
        .and_then(|value| value.to_string_lossy().parse::<u64>().ok())
        .unwrap_or(250);
    let stdin = std::io::stdin();
    let mut reader = BufReader::new(stdin.lock());
    let pending_completions = Arc::new((Mutex::new(HashSet::<i64>::new()), Condvar::new()));
    while let Some(message) = read_message(&mut reader) {
        let method = message.get("method").and_then(Value::as_str).unwrap_or("");
        match method {
            "initialize" => {
                if message
                    .pointer("/params/capabilities/textDocument/definition/linkSupport")
                    .and_then(Value::as_bool)
                    == Some(true)
                {
                    trace(&trace_path, "definition.linkSupport");
                }
                send(json!({
                    "jsonrpc": "2.0",
                    "id": message["id"],
                    "result": {"capabilities": {"textDocumentSync": 1, "workspaceSymbolProvider": true, "definitionProvider": true}},
                }));
            }
            "textDocument/didOpen" | "textDocument/didChange" | "textDocument/didClose" => {
                trace(&trace_path, method)
            }
            "$/cancelRequest" => {
                trace(&trace_path, method);
                if let Some(request_id) = message.pointer("/params/id").and_then(Value::as_i64) {
                    if let Ok(mut pending) = pending_completions.0.lock() {
                        pending.remove(&request_id);
                    }
                    pending_completions.1.notify_all();
                }
            }
            "textDocument/completion" => {
                let request_id = message["id"].clone();
                let Some(pending_id) = request_id.as_i64() else {
                    continue;
                };
                if let Ok(mut pending) = pending_completions.0.lock() {
                    pending.insert(pending_id);
                }
                let pending_completions = Arc::clone(&pending_completions);
                thread::spawn(move || {
                    let (pending, cancelled) = &*pending_completions;
                    let Ok(pending) = pending.lock() else {
                        return;
                    };
                    let Ok((mut pending, _)) = cancelled.wait_timeout_while(
                        pending,
                        Duration::from_millis(delay_ms),
                        |active| active.contains(&pending_id),
                    ) else {
                        return;
                    };
                    let should_respond = pending.remove(&pending_id);
                    drop(pending);
                    if should_respond {
                        send(json!({
                            "jsonrpc": "2.0",
                            "id": request_id,
                            "result": [{"label": "async_completion"}],
                        }));
                    }
                });
            }
            "workspace/symbol" => {
                trace(&trace_path, method);
                let id = message["id"].clone();
                let delayed =
                    message.pointer("/params/query").and_then(Value::as_str) == Some("slow");
                thread::spawn(move || {
                    if delayed {
                        thread::sleep(Duration::from_millis(delay_ms));
                    }
                    send(json!({"jsonrpc": "2.0", "id": id, "result": [{
                        "name": "😀workspace_target", "kind": 12, "containerName": "fixture",
                        "location": {"uri": "file:///workspace/target.rs", "range": {
                            "start": {"line": 1, "character": 3},
                            "end": {"line": 1, "character": 9}
                        }}
                    }]}));
                });
            }
            "textDocument/definition" => {
                trace(&trace_path, method);
                send(json!({
                    "jsonrpc": "2.0",
                    "id": message["id"],
                    "result": [{
                        "targetUri": "file:///workspace/target.rs",
                        "targetRange": {
                            "start": {"line": 1, "character": 0},
                            "end": {"line": 1, "character": 10}
                        },
                        "targetSelectionRange": {
                            "start": {"line": 1, "character": 3},
                            "end": {"line": 1, "character": 9}
                        }
                    }, {
                        "targetUri": "file:///workspace/other.rs",
                        "targetRange": {
                            "start": {"line": 2, "character": 0},
                            "end": {"line": 4, "character": 1}
                        },
                        "targetSelectionRange": {
                            "start": {"line": 3, "character": 5},
                            "end": {"line": 3, "character": 11}
                        }
                    }]
                }));
            }
            "shutdown" => {
                trace(&trace_path, method);
                send(json!({
                    "jsonrpc": "2.0",
                    "id": message["id"],
                    "result": null,
                }));
            }
            "exit" => {
                trace(&trace_path, method);
                break;
            }
            _ => {}
        }
    }
}
