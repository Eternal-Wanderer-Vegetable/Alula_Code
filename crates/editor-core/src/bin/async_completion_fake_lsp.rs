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
    let option = args.next();
    let provide_references = option.as_deref() != Some(std::ffi::OsStr::new("no-references"));
    let provide_symbol_locations =
        option.as_deref() != Some(std::ffi::OsStr::new("no-symbol-locations"));
    let provide_hierarchy = option.as_deref() == Some(std::ffi::OsStr::new("hierarchy"));
    let stdin = std::io::stdin();
    let mut reader = BufReader::new(stdin.lock());
    let pending_completions = Arc::new((Mutex::new(HashSet::<i64>::new()), Condvar::new()));
    while let Some(message) = read_message(&mut reader) {
        let method = message.get("method").and_then(Value::as_str).unwrap_or("");
        match method {
            "initialize" => {
                for kind in [
                    "definition",
                    "declaration",
                    "implementation",
                    "typeDefinition",
                ] {
                    let capability =
                        format!("/params/capabilities/textDocument/{kind}/linkSupport");
                    if message.pointer(&capability).and_then(Value::as_bool) == Some(true) {
                        trace(&trace_path, &format!("{kind}.linkSupport"));
                    }
                }
                for kind in ["callHierarchy", "typeHierarchy"] {
                    let name =
                        format!("/params/capabilities/textDocument/{kind}/dynamicRegistration");
                    if message.pointer(&name) == Some(&json!(false)) {
                        trace(&trace_path, &format!("{kind}.static"));
                    }
                }
                let implementation_provider = if provide_symbol_locations {
                    json!({"workDoneProgress": false})
                } else {
                    json!(false)
                };
                send(json!({
                    "jsonrpc": "2.0",
                    "id": message["id"],
                    "result": {"capabilities": {
                        "textDocumentSync": 1,
                        "workspaceSymbolProvider": true,
                        "definitionProvider": true,
                        "declarationProvider": provide_symbol_locations,
                        "implementationProvider": implementation_provider,
                        "typeDefinitionProvider": provide_symbol_locations,
                        "referencesProvider": provide_references,
                        "callHierarchyProvider": provide_hierarchy,
                        "typeHierarchyProvider": if provide_hierarchy {
                            json!({"workDoneProgress": false})
                        } else {
                            json!(false)
                        }
                    }},
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
            "textDocument/declaration"
            | "textDocument/implementation"
            | "textDocument/typeDefinition" => {
                let params = &message["params"];
                trace(&trace_path, &format!("{method} {params}"));
                let location = |uri, line, start, end| {
                    json!({"uri": uri, "range": {
                        "start": {"line": line, "character": start},
                        "end": {"line": line, "character": end}
                    }})
                };
                let link = |uri, line, start, end| {
                    json!({"targetUri": uri, "targetRange": {
                        "start": {"line": line, "character": 0},
                        "end": {"line": line, "character": end + 4}
                    }, "targetSelectionRange": {
                        "start": {"line": line, "character": start},
                        "end": {"line": line, "character": end}
                    }})
                };
                let result = if params["position"]["character"] == 0 {
                    Value::Null
                } else {
                    match method {
                        "textDocument/declaration" => {
                            location("file:///workspace/kind.rs", 1, 7, 10)
                        }
                        "textDocument/implementation" => json!([
                            link("file:///workspace/imp.rs", 2, 13, 19),
                            link("file:///workspace/other_imp.rs", 6, 13, 18)
                        ]),
                        _ => json!([location("file:///workspace/imp.rs", 1, 11, 17)]),
                    }
                };
                let id = message["id"].clone();
                thread::spawn(move || {
                    thread::sleep(Duration::from_millis(delay_ms));
                    send(json!({"jsonrpc": "2.0", "id": id, "result": result}));
                });
            }
            "textDocument/references" => {
                let params = &message["params"];
                trace(&trace_path, &format!("{method} {params}"));
                let position = &params["position"];
                let error = match position["character"].as_u64() {
                    Some(4) => Some((-32603, "fixture references provider failure")),
                    Some(5) => Some((-32801, "fixture invalidated analysis")),
                    Some(6) => Some((-32800, "fixture request cancelled")),
                    Some(7) => Some((-32802, "fixture server cancelled")),
                    _ => None,
                };
                if let Some((code, detail)) = error {
                    send(json!({
                        "jsonrpc": "2.0",
                        "id": message["id"],
                        "error": {"code": code, "message": detail}
                    }));
                    continue;
                }
                let usage = |uri, line, character| {
                    json!({"uri": uri, "range": {
                        "start": {"line": line, "character": character},
                        "end": {"line": line, "character": character + 6}
                    }})
                };
                let result = match position["character"].as_u64() {
                    Some(0) => Value::Null,
                    Some(3) => json!(vec![usage("file:///workspace/target.rs", 1, 2); 2001]),
                    _ => {
                        let mut locations = vec![
                            usage("file:///workspace/target.rs", 1, 2),
                            usage("file:///workspace/other.rs", 3, 5),
                        ];
                        if params["context"]["includeDeclaration"] == true {
                            locations.push(usage("file:///workspace/definition.rs", 0, 3));
                        }
                        json!(locations)
                    }
                };
                let id = message["id"].clone();
                thread::spawn(move || {
                    thread::sleep(Duration::from_millis(delay_ms));
                    send(json!({"jsonrpc": "2.0", "id": id, "result": result}));
                });
            }
            "textDocument/prepareCallHierarchy"
            | "textDocument/prepareTypeHierarchy"
            | "callHierarchy/incomingCalls"
            | "callHierarchy/outgoingCalls"
            | "typeHierarchy/supertypes"
            | "typeHierarchy/subtypes" => {
                let params = &message["params"];
                trace(&trace_path, &format!("{method} {params}"));
                let character = params
                    .pointer("/position/character")
                    .and_then(Value::as_u64);
                if let Some(code) = match character {
                    Some(4) => Some(-32603),
                    Some(5) => Some(-32801),
                    Some(6) => Some(-32800),
                    _ => None,
                } {
                    send(json!({
                        "jsonrpc": "2.0",
                        "id": message["id"],
                        "error": {"code": code, "message": "fixture hierarchy status"}
                    }));
                    continue;
                }

                let span = |line, start, end| {
                    json!({
                        "start": {"line": line, "character": start},
                        "end": {"line": line, "character": end},
                    })
                };
                let item = |name, kind, file, line, start, end| {
                    json!({
                        "name": name,
                        "kind": kind,
                        "detail": "fixture module",
                        "uri": format!("file:///E:/workspace/{file}"),
                        "range": span(line, 0, 40),
                        "selectionRange": span(line, start, end),
                        "data": {"id": [name, "🦊", 7], "context": {"project": 1}},
                        "providerTag": [true, null, name],
                    })
                };
                let result = if character == Some(0) {
                    Value::Null
                } else {
                    match method {
                        "textDocument/prepareCallHierarchy" => {
                            json!([item("root", 12, "main.rs", 1, 2, 8)])
                        }
                        "textDocument/prepareTypeHierarchy" => {
                            json!([item("Root", 23, "main.rs", 1, 2, 8)])
                        }
                        "callHierarchy/incomingCalls" => json!([{
                            "from": item("caller", 12, "caller.rs", 0, 7, 13),
                            "fromRanges": [span(0, 15, 21), span(0, 30, 36)]
                        }]),
                        "callHierarchy/outgoingCalls" => json!([{
                            "to": item("leaf", 12, "leaf.rs", 2, 8, 12),
                            "fromRanges": [span(1, 12, 16)]
                        }]),
                        "typeHierarchy/supertypes" => {
                            json!([item("Base", 11, "base.rs", 0, 6, 10)])
                        }
                        _ => json!([item("Derived", 23, "derived.rs", 3, 7, 14)]),
                    }
                };
                let id = message["id"].clone();
                thread::spawn(move || {
                    thread::sleep(Duration::from_millis(delay_ms));
                    send(json!({"jsonrpc": "2.0", "id": id, "result": result}));
                });
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
