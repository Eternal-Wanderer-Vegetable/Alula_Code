//! LSP 客户端（stdio JSON-RPC）：按需启动语言服务器、维护诊断快照、转发补全请求。
//!
//! MVP 范围（docs/02 §3 的最小实现）：
//! - Initialize/initialized 握手 + 退出握手；
//! - didOpen / didChange（全量同步；增量同步留待 Phase 1）；
//! - 接收 textDocument/publishDiagnostics（后台读线程，不阻塞 UI）；
//! - textDocument/completion（同步等待 + 超时；异步化留待 FRB 迁移）；
//! - 其余通知（$/progress、window/logMessage 等）静默忽略。

use std::collections::HashMap;
use std::io::{BufRead, BufReader, Read, Write};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Diagnostic {
    /// LSP severity：1=Error 2=Warning 3=Information 4=Hint
    pub severity: u32,
    pub line: u64,
    pub character: u64,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source: Option<String>,
}

struct Shared {
    diagnostics: Mutex<HashMap<String, Vec<Diagnostic>>>,
    pending: Mutex<HashMap<i64, mpsc::SyncSender<serde_json::Value>>>,
    server_capabilities: Mutex<Option<serde_json::Value>>,
    /// 写端（send_message 与读线程回复服务端请求共用）
    writer: Mutex<Option<ChildStdin>>,
}

impl Shared {
    fn new(writer: ChildStdin) -> Self {
        Shared {
            diagnostics: Mutex::new(HashMap::new()),
            pending: Mutex::new(HashMap::new()),
            server_capabilities: Mutex::new(None),
            writer: Mutex::new(Some(writer)),
        }
    }

    fn send(&self, value: &serde_json::Value) -> Result<(), String> {
        let body = serde_json::to_string(value).map_err(|e| e.to_string())?;
        let frame = format!("Content-Length: {}\r\n\r\n{body}", body.len());
        if std::env::var("ALULA_LSP_DEBUG").is_ok() {
            use std::io::Write as _;
            if let Ok(mut f) = std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open("alula_lsp_out.log")
            {
                let _ = f.write_all(frame.as_bytes());
            }
        }
        let mut guard = self.writer.lock().map_err(|_| "writer 锁中毒")?;
        let stdin = guard.as_mut().ok_or("stdin 已关闭")?;
        stdin
            .write_all(frame.as_bytes())
            .and_then(|_| stdin.flush())
            .map_err(|e| format!("写入 LSP 管道失败: {e}"))
    }
}

pub struct LspServer {
    child: Mutex<Child>,
    shared: Arc<Shared>,
    next_id: AtomicI64,
}

/// 路径 → file URI（ASCII 路径的朴素实现；含非 ASCII/空格时需 percent-encoding，
/// 由调用方保证或后续完善）。
/// URI 归一：Windows 盘符统一小写（rust-analyzer 等服务器推送诊断时会把
/// `file:///E:/` 归一为 `file:///e:/`，存储与查询必须用同一键口径）。
pub fn normalize_uri(uri: &str) -> String {
    if let Some(rest) = uri.strip_prefix("file:///") {
        let bytes = rest.as_bytes();
        if bytes.len() >= 2 && bytes[1] == b':' && bytes[0].is_ascii_alphabetic() {
            let lowered = (bytes[0] as char).to_ascii_lowercase();
            // "E:/x" → "file:///e:/x"（保留冒号与后续路径）
            return format!("file:///{lowered}:{}", &rest[2..]);
        }
    }
    uri.to_string()
}

pub fn path_to_uri(path: &str) -> String {
    let p = path.replace('\\', "/");
    let p = p.trim_start_matches('/');
    let bytes = p.as_bytes();
    if bytes.len() >= 2 && bytes[0].is_ascii_alphabetic() && bytes[1] == b':' {
        format!("file:///{p}")
    } else {
        format!("file:///{p}")
    }
}

impl LspServer {
    /// 启动服务器进程并完成 Initialize/initialized 握手。
    /// `cmd[0]` 为程序，其余为参数。
    pub fn spawn(workspace_root: &str, cmd: &[String]) -> Result<Self, String> {
        if cmd.is_empty() {
            return Err("cmd 为空".into());
        }
        let mut child = Command::new(&cmd[0])
            .args(&cmd[1..])
            .current_dir(workspace_root)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()
            .map_err(|e| format!("启动 {} 失败: {e}", cmd[0]))?;

        let stdin = child.stdin.take().ok_or("无法获取 stdin")?;
        let stdout = child.stdout.take().ok_or("无法获取 stdout")?;

        let shared = Arc::new(Shared::new(stdin));
        {
            let shared = Arc::clone(&shared);
            std::thread::Builder::new()
                .name("lsp-reader".into())
                .spawn(move || reader_loop(stdout, shared))
                .map_err(|e| format!("创建读线程失败: {e}"))?;
        }

        let server = LspServer {
            child: Mutex::new(child),
            shared,
            next_id: AtomicI64::new(1),
        };
        server.handshake(workspace_root)?;
        Ok(server)
    }

    fn send_message(&self, value: &serde_json::Value) -> Result<(), String> {
        self.shared.send(value)
    }

    fn handshake(&self, workspace_root: &str) -> Result<(), String> {
        let id = self.next_id.fetch_add(1, Ordering::SeqCst);
        let root_uri = path_to_uri(workspace_root);
        let params = serde_json::json!({
            "processId": std::process::id(),
            "rootUri": root_uri,
            "workspaceFolders": [{"uri": root_uri, "name": "workspace"}],
            "capabilities": {},
        });
        self.send_message(&serde_json::json!({
            "jsonrpc": "2.0", "id": id, "method": "initialize", "params": params,
        }))?;
        // 等待 initialize 响应（服务器启动可能较慢）
        let deadline = Instant::now() + Duration::from_secs(30);
        loop {
            if self.shared.server_capabilities.lock().map(|g| g.is_some()).unwrap_or(false) {
                break;
            }
            if Instant::now() > deadline {
                return Err("等待 initialize 响应超时（30s）".into());
            }
            std::thread::sleep(Duration::from_millis(25));
        }
        self.send_message(&serde_json::json!({
            "jsonrpc": "2.0", "method": "initialized", "params": {},
        }))?;
        // 与 VS Code 等客户端一致：给服务器一点处理 initialized 的时间，
        // 避免紧随其后的 didOpen 落在 workspace 加载完成之前（诊断调度被丢弃）。
        std::thread::sleep(Duration::from_secs(1));
        Ok(())
    }

    pub fn did_open(
        &self,
        uri: &str,
        language_id: &str,
        version: i64,
        text: &str,
    ) -> Result<(), String> {
        let uri = &normalize_uri(uri);
        self.send_message(&serde_json::json!({
            "jsonrpc": "2.0",
            "method": "textDocument/didOpen",
            "params": {
                "textDocument": {
                    "uri": uri, "languageId": language_id, "version": version, "text": text,
                }
            },
        }))
    }

    /// 全量 didChange（MVP；文本协议 TextSyncFull）。
    pub fn did_change_full(&self, uri: &str, version: i64, text: &str) -> Result<(), String> {
        let uri = &normalize_uri(uri);
        self.send_message(&serde_json::json!({
            "jsonrpc": "2.0",
            "method": "textDocument/didChange",
            "params": {
                "textDocument": {"uri": uri, "version": version},
                "contentChanges": [{"text": text}],
            },
        }))
    }

    /// 该 uri 的最新诊断快照（键按 normalize_uri 归一）。
    pub fn diagnostics(&self, uri: &str) -> Vec<Diagnostic> {
        let key = normalize_uri(uri);
        self.shared
            .diagnostics
            .lock()
            .map(|g| g.get(&key).cloned().unwrap_or_default())
            .unwrap_or_default()
    }

    /// didSave：触发 flycheck（cargo check）→ cargo 诊断推送。
    pub fn did_save(&self, uri: &str) -> Result<(), String> {
        let uri = &normalize_uri(uri);
        self.send_message(&serde_json::json!({
            "jsonrpc": "2.0",
            "method": "textDocument/didSave",
            "params": {"textDocument": {"uri": uri}},
        }))
    }

    /// 通用同步请求（pull diagnostics 等使用）。
    pub fn request(
        &self,
        method: &str,
        params: serde_json::Value,
        timeout_ms: u64,
    ) -> Result<serde_json::Value, String> {
        let id = self.next_id.fetch_add(1, Ordering::SeqCst);
        let (tx, rx) = mpsc::sync_channel::<serde_json::Value>(1);
        self.shared
            .pending
            .lock()
            .map_err(|_| "pending 锁中毒")?
            .insert(id, tx);
        let sent = self.send_message(&serde_json::json!({
            "jsonrpc": "2.0", "id": id, "method": method, "params": params,
        }));
        if let Err(e) = sent {
            self.shared.pending.lock().ok().map(|mut g| g.remove(&id));
            return Err(e);
        }
        rx.recv_timeout(Duration::from_millis(timeout_ms))
            .map_err(|_| format!("请求 {method} 响应超时（{timeout_ms}ms）"))
    }

    /// 同步补全请求（带超时）。返回每项的插入文本（insertText/textEdit.newText/label）。
    pub fn completion(
        &self,
        uri: &str,
        line: u64,
        character: u64,
        timeout_ms: u64,
    ) -> Result<Vec<String>, String> {
        let result = self.request(
            "textDocument/completion",
            serde_json::json!({
                "textDocument": {"uri": uri},
                "position": {"line": line, "character": character},
            }),
            timeout_ms,
        )?;
        Ok(extract_completion_labels(&result))
    }

    /// 服务器进程是否仍在运行。
    pub fn is_alive(&self) -> bool {
        match self.child.lock() {
            Ok(mut c) => c.try_wait().map(|s| s.is_none()).unwrap_or(false),
            Err(_) => false,
        }
    }

    /// shutdown + exit 握手并回收进程。
    pub fn shutdown(&self) -> Result<(), String> {
        let id = self.next_id.fetch_add(1, Ordering::SeqCst);
        let _ = self.send_message(&serde_json::json!({
            "jsonrpc": "2.0", "id": id, "method": "shutdown", "params": null,
        }));
        std::thread::sleep(Duration::from_millis(150));
        let _ = self.send_message(&serde_json::json!({
            "jsonrpc": "2.0", "method": "exit", "params": null,
        }));
        std::thread::sleep(Duration::from_millis(150));
        if let Ok(mut child) = self.child.lock() {
            let _ = child.kill();
            let _ = child.wait();
        }
        Ok(())
    }
}

/// 从 CompletionItem[] / {items:[]} / null 中提取插入文本。
pub fn extract_completion_labels(result: &serde_json::Value) -> Vec<String> {
    let items: Vec<serde_json::Value> = match result {
        serde_json::Value::Null => return Vec::new(),
        serde_json::Value::Array(a) => a.clone(),
        v if v.get("items").is_some() => v["items"].as_array().cloned().unwrap_or_default(),
        _ => return Vec::new(),
    };
    items
        .iter()
        .filter_map(|item| {
            if let Some(edit) = item.get("textEdit") {
                if let Some(t) = edit.get("newText").and_then(|v| v.as_str()) {
                    return Some(t.to_string());
                }
            }
            item.get("insertText")
                .and_then(|v| v.as_str())
                .or_else(|| item.get("label").and_then(|v| v.as_str()))
                .map(|s| s.to_string())
        })
        .collect()
}

// ---------- 后台读线程 ----------

fn reader_loop<R: Read + Send + 'static>(stdout: R, shared: Arc<Shared>) {
    let mut reader = BufReader::new(stdout);
    loop {
        // 读头部：直到空行，解析 Content-Length
        let mut content_length: Option<usize> = None;
        loop {
            let mut line = String::new();
            match reader.read_line(&mut line) {
                Ok(0) => return,           // EOF：服务器退出
                Ok(_) => {}
                Err(_) => return,
            }
            let line = line.trim_end().to_string();
            if line.is_empty() {
                break;
            }
            if let Some(v) = line.strip_prefix("Content-Length:") {
                content_length = v.trim().parse().ok();
            }
        }
        let Some(len) = content_length else { return };
        let mut body = vec![0u8; len];
        if reader.read_exact(&mut body).is_err() {
            return;
        }
        let msg: serde_json::Value = match serde_json::from_slice(&body) {
            Ok(v) => v,
            Err(_) => continue,
        };

        if std::env::var("ALULA_LSP_DEBUG").is_ok() {
            let method = msg.get("method").and_then(|m| m.as_str()).unwrap_or("<response>");
            eprintln!("[lsp-reader] 收到: {method}");
        }

        // 服务端请求（method + id）：必须回应，否则对端管线会阻塞等待。
        // MVP 统一回 null（workspace/diagnostic/refresh、client/registerCapability
        // 等以 null/空 为接受语义的请求均可）。
        if msg.get("method").is_some() && msg.get("id").is_some() {
            let _ = shared.send(&serde_json::json!({
                "jsonrpc": "2.0", "id": msg["id"], "result": null,
            }));
        }

        // 响应（带 id 且含 result/error）
        if let Some(id) = msg.get("id").and_then(|v| v.as_i64()) {
            if msg.get("result").is_some() || msg.get("error").is_some() {
                // initialize 响应特殊处理
                if msg.get("result").map(|r| r.get("capabilities").is_some()).unwrap_or(false) {
                    if let Ok(mut caps) = shared.server_capabilities.lock() {
                        *caps = msg.get("result").cloned();
                    }
                }
                let sender = shared.pending.lock().ok().and_then(|mut g| g.remove(&id));
                if let Some(tx) = sender {
                    let _ = tx.send(msg.get("result").cloned().unwrap_or(serde_json::Value::Null));
                }
                continue;
            }
        }

        // 服务端通知
        match msg.get("method").and_then(|v| v.as_str()) {
            Some("textDocument/publishDiagnostics") => {
                let params = &msg["params"];
                let uri = params
                    .get("uri")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();
                let diags: Vec<Diagnostic> = params
                    .get("diagnostics")
                    .and_then(|v| v.as_array())
                    .map(|arr| {
                        arr.iter()
                            .filter_map(|d| {
                                let range = d.get("range")?["start"].clone();
                                Some(Diagnostic {
                                    severity: d
                                        .get("severity")
                                        .and_then(|v| v.as_u64())
                                        .unwrap_or(3) as u32,
                                    line: range.get("line").and_then(|v| v.as_u64())?,
                                    character: range
                                        .get("character")
                                        .and_then(|v| v.as_u64())
                                        .unwrap_or(0),
                                    message: d
                                        .get("message")
                                        .and_then(|v| v.as_str())?
                                        .to_string(),
                                    source: d
                                        .get("source")
                                        .and_then(|v| v.as_str())
                                        .map(|s| s.to_string()),
                                })
                            })
                            .collect()
                    })
                    .unwrap_or_default();
                if std::env::var("ALULA_LSP_DEBUG").is_ok() {
                    eprintln!(
                        "[lsp-reader] publishDiagnostics uri={uri} 条数={}",
                        diags.len()
                    );
                }
                if let Ok(mut g) = shared.diagnostics.lock() {
                    g.insert(normalize_uri(&uri), diags);
                }
            }
            _ => {} // $/progress、window/logMessage 等：忽略
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_uri_lowercases_drive_only() {
        assert_eq!(
            normalize_uri("file:///E:/Alula_Code/x.rs"),
            "file:///e:/Alula_Code/x.rs"
        );
        assert_eq!(
            normalize_uri("file:///e:/a/b.rs"),
            "file:///e:/a/b.rs"
        );
        // 非 file:/// 前缀原样保留
        assert_eq!(normalize_uri("untitled:1"), "untitled:1");
    }

    use super::*;

    #[test]
    fn path_to_uri_windows_and_unix() {
        assert_eq!(path_to_uri("E:\\a\\b"), "file:///E:/a/b");
        assert_eq!(path_to_uri("/home/u/x"), "file:///home/u/x");
    }

    #[test]
    fn completion_labels_from_shapes() {
        let arr = serde_json::json!([
            {"label": "println!", "textEdit": {"newText": "println!()"}},
            {"label": "format", "insertText": "format!()"},
            {"label": "plain"},
        ]);
        assert_eq!(
            extract_completion_labels(&arr),
            vec!["println!()", "format!()", "plain"]
        );
        let wrapped = serde_json::json!({"isIncomplete": false, "items": [{"label": "x"}]});
        assert_eq!(extract_completion_labels(&wrapped), vec!["x"]);
        assert!(extract_completion_labels(&serde_json::Value::Null).is_empty());
    }
}
