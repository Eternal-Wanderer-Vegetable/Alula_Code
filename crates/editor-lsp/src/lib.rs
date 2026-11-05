//! LSP 客户端（stdio JSON-RPC）：按需启动语言服务器、维护诊断快照、转发补全请求。
//!
//! MVP 范围（docs/02 §3 的最小实现）：
//! - Initialize/initialized 握手 + 退出握手；
//! - didOpen / didChange（全量同步；增量同步留待 Phase 1）；
//! - 接收 textDocument/publishDiagnostics（后台读线程，不阻塞 UI）；
//! - textDocument/definition / completion / semanticTokens（可取消异步请求）；
//! - 其余通知（$/progress、window/logMessage 等）静默忽略。

use std::collections::HashMap;
use std::io::{BufRead, BufReader, Read, Write};
use std::process::{ChildStdin, Command, Stdio};
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use editor_process::{ProcessKind, ProcessMetadata, ProcessSupervisor, SupervisedChild};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Diagnostic {
    /// LSP severity：1=Error 2=Warning 3=Information 4=Hint
    pub severity: u32,
    pub line: u64,
    pub character: u64,
    #[serde(rename = "endLine", skip_serializing_if = "Option::is_none")]
    pub end_line: Option<u64>,
    #[serde(rename = "endCharacter", skip_serializing_if = "Option::is_none")]
    pub end_character: Option<u64>,
    #[serde(rename = "documentVersion", skip_serializing_if = "Option::is_none")]
    pub document_version: Option<i64>,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SemanticTokenLegend {
    pub token_types: Vec<String>,
    pub token_modifiers: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SemanticToken {
    pub line: u32,
    pub start_character: u32,
    pub length: u32,
    pub kind: String,
}

/// First usable LSP definition target. `line` and `character` use LSP's
/// zero-based UTF-16 coordinates.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DefinitionLocation {
    pub uri: String,
    pub line: u64,
    pub character: u64,
}

/// Read the first Location or LocationLink from a definition response.
/// Invalid entries are ignored so one malformed link does not hide later
/// usable results.
pub fn extract_definition_location(value: &serde_json::Value) -> Option<DefinitionLocation> {
    let entries = match value {
        serde_json::Value::Array(entries) => entries.iter().collect::<Vec<_>>(),
        serde_json::Value::Null => return None,
        value => vec![value],
    };

    entries.into_iter().find_map(|entry| {
        let uri = entry
            .get("targetUri")
            .or_else(|| entry.get("uri"))?
            .as_str()?;
        let start = entry
            .get("targetSelectionRange")
            .or_else(|| entry.get("range"))?
            .get("start")?;
        let line = start.get("line")?.as_u64()?;
        let character = start.get("character")?.as_u64()?;
        (!uri.is_empty()).then(|| DefinitionLocation {
            uri: uri.to_string(),
            line,
            character,
        })
    })
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
    child: Mutex<SupervisedChild>,
    shared: Arc<Shared>,
    next_id: AtomicI64,
}

/// 已发送的 JSON-RPC 请求。创建与轮询均不等待服务端响应；调用方应在完成、
/// 超时或生命周期结束时显式取消，以释放 pending 项并通知语言服务器。
pub struct LspPendingRequest {
    id: i64,
    method: String,
    receiver: mpsc::Receiver<serde_json::Value>,
    shared: Arc<Shared>,
    completed: bool,
}

impl LspPendingRequest {
    pub fn id(&self) -> i64 {
        self.id
    }

    /// 立即检查响应；None 表示仍在等待。
    pub fn try_recv(&mut self) -> Result<Option<serde_json::Value>, String> {
        match self.receiver.try_recv() {
            Ok(value) => {
                self.completed = true;
                Ok(Some(value))
            }
            Err(mpsc::TryRecvError::Empty) => Ok(None),
            Err(mpsc::TryRecvError::Disconnected) => {
                if let Ok(mut pending) = self.shared.pending.lock() {
                    pending.remove(&self.id);
                }
                self.completed = true;
                Err(format!("请求 {} 的 LSP 响应通道已关闭", self.method))
            }
        }
    }

    /// 同步兼容入口使用的有界等待。
    pub fn wait(&mut self, timeout_ms: u64) -> Result<serde_json::Value, String> {
        match self
            .receiver
            .recv_timeout(Duration::from_millis(timeout_ms))
        {
            Ok(value) => {
                self.completed = true;
                Ok(value)
            }
            Err(_) => {
                let _ = self.cancel();
                Err(format!("请求 {} 响应超时（{timeout_ms}ms）", self.method))
            }
        }
    }

    /// 删除本地 pending 项并发送标准 LSP $/cancelRequest 通知。
    pub fn cancel(&mut self) -> Result<(), String> {
        if self.completed {
            return Ok(());
        }
        if let Ok(mut pending) = self.shared.pending.lock() {
            pending.remove(&self.id);
        }
        self.completed = true;
        self.shared.send(&serde_json::json!({
            "jsonrpc": "2.0",
            "method": "$/cancelRequest",
            "params": {"id": self.id},
        }))
    }
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
    // Windows「E:\a\b」→「file:///E:/a/b」；POSIX「/a/b」→「file:///a/b」
    let p = path.replace('\\', "/");
    let p = p.trim_start_matches('/');
    format!("file:///{p}")
}

impl LspServer {
    /// 启动服务器进程并完成 Initialize/initialized 握手。
    /// `cmd[0]` 为程序，其余为参数。
    pub fn spawn(workspace_root: &str, cmd: &[String]) -> Result<Self, String> {
        if cmd.is_empty() {
            return Err("cmd 为空".into());
        }
        let mut command = Command::new(&cmd[0]);
        command
            .args(&cmd[1..])
            .current_dir(workspace_root)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit());
        let mut child = ProcessSupervisor::global()
            .spawn(
                &mut command,
                ProcessMetadata::new(
                    cmd[0].clone(),
                    ProcessKind::LanguageServer,
                    Some(workspace_root.to_string()),
                ),
            )
            .map_err(|e| format!("启动 {} 失败: {e}", cmd[0]))?;

        let stdin = child.take_stdin().ok_or("无法获取 stdin")?;
        let stdout = child.take_stdout().ok_or("无法获取 stdout")?;

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
            "capabilities": {
                "general": {"positionEncodings": ["utf-16"]},
                "textDocument": {
                    "semanticTokens": {
                        "dynamicRegistration": false,
                        "requests": {"range": false, "full": {"delta": false}},
                        "tokenTypes": [
                            "namespace", "type", "class", "enum", "interface", "struct",
                            "typeParameter", "parameter", "variable", "property", "enumMember",
                            "event", "function", "method", "macro", "keyword", "modifier",
                            "comment", "string", "number", "regexp", "operator", "decorator",
                            "attribute", "builtinAttribute", "builtinType", "derive",
                            "deriveHelper", "formatSpecifier", "generic", "invalidEscapeSequence",
                            "selfKeyword", "lifetime", "macroBang", "punctuation",
                            "unresolvedReference", "angle", "arithmetic", "attributeBracket",
                            "bitwise", "boolean", "brace", "bracket", "character", "colon",
                            "comma", "comparison", "const", "constParameter", "dot",
                            "escapeSequence", "logical", "negation", "parenthesis", "procMacro",
                            "selfTypeKeyword", "semicolon", "toolModule", "union", "typeAlias"
                        ],
                        "tokenModifiers": [
                            "declaration", "definition", "readonly", "static", "deprecated",
                            "abstract", "async", "modification", "documentation", "defaultLibrary",
                            "mutable", "consuming", "unsafe", "attribute", "callable", "constant",
                            "associated", "controlFlow", "crateRoot", "injected", "intraDocLink",
                            "library", "macro", "procMacro", "public", "reference", "trait"
                        ],
                        "formats": ["relative"],
                        "overlappingTokenSupport": false,
                        "multilineTokenSupport": false
                    }
                }
            },
        });
        self.send_message(&serde_json::json!({
            "jsonrpc": "2.0", "id": id, "method": "initialize", "params": params,
        }))?;
        // 等待 initialize 响应（服务器启动可能较慢）
        let deadline = Instant::now() + Duration::from_secs(30);
        loop {
            if self
                .shared
                .server_capabilities
                .lock()
                .map(|g| g.is_some())
                .unwrap_or(false)
            {
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

    /// 文档关闭通知。
    pub fn did_close(&self, uri: &str) -> Result<(), String> {
        let uri = &normalize_uri(uri);
        self.send_message(&serde_json::json!({
            "jsonrpc": "2.0",
            "method": "textDocument/didClose",
            "params": {"textDocument": {"uri": uri}},
        }))
    }

    /// 通用异步请求：只注册 pending 并发送 JSON-RPC 消息，不等待响应。
    pub fn request_async(
        &self,
        method: &str,
        params: serde_json::Value,
    ) -> Result<LspPendingRequest, String> {
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
        Ok(LspPendingRequest {
            id,
            method: method.to_string(),
            receiver: rx,
            shared: Arc::clone(&self.shared),
            completed: false,
        })
    }

    /// 通用同步兼容请求（pull diagnostics 等非 UI 调用使用）。
    pub fn request(
        &self,
        method: &str,
        params: serde_json::Value,
        timeout_ms: u64,
    ) -> Result<serde_json::Value, String> {
        self.request_async(method, params)?.wait(timeout_ms)
    }

    pub fn semantic_token_legend(&self) -> Option<SemanticTokenLegend> {
        let capabilities = self.shared.server_capabilities.lock().ok()?;
        let provider = capabilities
            .as_ref()?
            .get("capabilities")?
            .get("semanticTokensProvider")?;
        let full = provider.get("full")?;
        if full != true && !full.is_object() {
            return None;
        }
        let legend = provider.get("legend")?;
        let token_types = legend
            .get("tokenTypes")?
            .as_array()?
            .iter()
            .map(|value| value.as_str().map(str::to_owned))
            .collect::<Option<Vec<_>>>()?;
        let token_modifiers = legend
            .get("tokenModifiers")?
            .as_array()?
            .iter()
            .map(|value| value.as_str().map(str::to_owned))
            .collect::<Option<Vec<_>>>()?;
        Some(SemanticTokenLegend {
            token_types,
            token_modifiers,
        })
    }

    pub fn semantic_tokens_async(&self, uri: &str) -> Result<Option<LspPendingRequest>, String> {
        if self.semantic_token_legend().is_none() {
            return Ok(None);
        }
        self.request_async(
            "textDocument/semanticTokens/full",
            serde_json::json!({"textDocument": {"uri": normalize_uri(uri)}}),
        )
        .map(Some)
    }

    /// Send an asynchronous textDocument/definition request.
    pub fn definition_async(
        &self,
        uri: &str,
        line: u64,
        character: u64,
    ) -> Result<LspPendingRequest, String> {
        self.request_async(
            "textDocument/definition",
            serde_json::json!({
                "textDocument": {"uri": normalize_uri(uri)},
                "position": {"line": line, "character": character},
            }),
        )
    }

    /// 发送异步补全请求。返回值可立即轮询或取消。
    pub fn completion_async(
        &self,
        uri: &str,
        line: u64,
        character: u64,
    ) -> Result<LspPendingRequest, String> {
        self.request_async(
            "textDocument/completion",
            serde_json::json!({
                "textDocument": {"uri": uri},
                "position": {"line": line, "character": character},
            }),
        )
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
            Ok(mut child) => child.try_wait().map(|s| s.is_none()).unwrap_or(false),
            Err(_) => false,
        }
    }

    /// shutdown + exit 握手并回收进程。
    pub fn shutdown(&self) -> Result<(), String> {
        if !self.is_alive() {
            return Ok(());
        }

        let shutdown = self.request("shutdown", serde_json::Value::Null, 1_000);
        let exit = self.send_message(&serde_json::json!({
            "jsonrpc": "2.0", "method": "exit", "params": null,
        }));

        let deadline = Instant::now() + Duration::from_secs(1);
        loop {
            let status = self
                .child
                .lock()
                .map_err(|_| "LSP child 锁中毒")?
                .try_wait()
                .map_err(|e| format!("等待 LSP 退出失败: {e}"))?;
            if status.is_some() {
                break;
            }
            if Instant::now() >= deadline {
                if let Ok(mut child) = self.child.lock() {
                    let _ = child.kill_tree_and_wait();
                }
                return Err("LSP 未在 exit 通知后 1 秒内退出，已强制终止其进程树".into());
            }
            std::thread::sleep(Duration::from_millis(25));
        }

        shutdown?;
        exit?;
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

pub fn decode_semantic_tokens(
    result: &serde_json::Value,
    legend: &SemanticTokenLegend,
) -> Result<Vec<SemanticToken>, String> {
    let Some(data) = result.get("data") else {
        if result.is_null() {
            return Ok(Vec::new());
        }
        return Err("semanticTokens/full 响应缺少 data".into());
    };
    let data = data
        .as_array()
        .ok_or_else(|| "semanticTokens/full data 不是数组".to_string())?;
    let (chunks, remainder) = data.as_slice().as_chunks::<5>();
    if !remainder.is_empty() {
        return Err("semanticTokens/full data 长度不是 5 的倍数".into());
    }

    let mut tokens = Vec::with_capacity(chunks.len());
    let (mut line, mut character) = (0u32, 0u32);
    for values in chunks {
        let value = |index: usize| {
            values[index]
                .as_u64()
                .and_then(|number| u32::try_from(number).ok())
                .ok_or_else(|| "semantic token 字段超出 u32 范围".to_string())
        };
        let delta_line = value(0)?;
        let delta_start = value(1)?;
        let length = value(2)?;
        let token_type = value(3)? as usize;
        let modifiers = value(4)?;
        if length == 0 {
            return Err("semantic token 长度为零".into());
        }
        if delta_line == 0 {
            character = character
                .checked_add(delta_start)
                .ok_or_else(|| "semantic token character 溢出".to_string())?;
        } else {
            line = line
                .checked_add(delta_line)
                .ok_or_else(|| "semantic token line 溢出".to_string())?;
            character = delta_start;
        }
        let mut kind = legend
            .token_types
            .get(token_type)
            .ok_or_else(|| "semantic token type 索引超出 legend".to_string())?
            .clone();
        for (index, modifier) in legend.token_modifiers.iter().enumerate() {
            if index < u32::BITS as usize && modifiers & (1 << index) != 0 {
                kind.push('.');
                kind.push_str(modifier);
            }
        }
        character
            .checked_add(length)
            .ok_or_else(|| "semantic token end character 溢出".to_string())?;
        tokens.push(SemanticToken {
            line,
            start_character: character,
            length,
            kind,
        });
    }
    Ok(tokens)
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
                Ok(0) => return, // EOF：服务器退出
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
            let method = msg
                .get("method")
                .and_then(|m| m.as_str())
                .unwrap_or("<response>");
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
                if msg
                    .get("result")
                    .map(|r| r.get("capabilities").is_some())
                    .unwrap_or(false)
                {
                    if let Ok(mut caps) = shared.server_capabilities.lock() {
                        *caps = msg.get("result").cloned();
                    }
                }
                let sender = shared.pending.lock().ok().and_then(|mut g| g.remove(&id));
                if let Some(tx) = sender {
                    let _ = tx.send(
                        msg.get("result")
                            .cloned()
                            .unwrap_or(serde_json::Value::Null),
                    );
                }
                continue;
            }
        }

        // 服务端通知；$/progress、window/logMessage 等其余通知：忽略
        if let Some("textDocument/publishDiagnostics") = msg.get("method").and_then(|v| v.as_str())
        {
            let params = &msg["params"];
            let uri = params
                .get("uri")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            let document_version = params.get("version").and_then(|v| v.as_i64());
            let diags: Vec<Diagnostic> = params
                .get("diagnostics")
                .and_then(|v| v.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|d| {
                            let range = d.get("range")?;
                            let start = range.get("start")?;
                            let end = range.get("end");
                            Some(Diagnostic {
                                severity: d.get("severity").and_then(|v| v.as_u64()).unwrap_or(3)
                                    as u32,
                                line: start.get("line").and_then(|v| v.as_u64())?,
                                character: start
                                    .get("character")
                                    .and_then(|v| v.as_u64())
                                    .unwrap_or(0),
                                end_line: end
                                    .and_then(|position| position.get("line"))
                                    .and_then(|v| v.as_u64()),
                                end_character: end
                                    .and_then(|position| position.get("character"))
                                    .and_then(|v| v.as_u64()),
                                document_version,
                                message: d.get("message").and_then(|v| v.as_str())?.to_string(),
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
        assert_eq!(normalize_uri("file:///e:/a/b.rs"), "file:///e:/a/b.rs");
        // 非 file:/// 前缀原样保留
        assert_eq!(normalize_uri("untitled:1"), "untitled:1");
    }

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

    #[test]
    fn decode_semantic_tokens_uses_relative_utf16_positions_and_legend() {
        let legend = SemanticTokenLegend {
            token_types: vec!["function".into(), "variable".into()],
            token_modifiers: vec!["readonly".into(), "declaration".into()],
        };
        let result = serde_json::json!({"data": [0, 3, 4, 0, 1, 1, 2, 3, 1, 2]});
        assert_eq!(
            decode_semantic_tokens(&result, &legend).unwrap(),
            vec![
                SemanticToken {
                    line: 0,
                    start_character: 3,
                    length: 4,
                    kind: "function.readonly".into(),
                },
                SemanticToken {
                    line: 1,
                    start_character: 2,
                    length: 3,
                    kind: "variable.declaration".into(),
                },
            ]
        );
    }

    #[test]
    fn decode_semantic_tokens_rejects_malformed_data_and_legend_indices() {
        let legend = SemanticTokenLegend {
            token_types: vec!["function".into()],
            token_modifiers: vec![],
        };
        assert!(decode_semantic_tokens(&serde_json::json!({"data": [0, 1]}), &legend).is_err());
        assert!(
            decode_semantic_tokens(&serde_json::json!({"data": [0, 1, 2, 3, 0]}), &legend).is_err()
        );
        assert!(
            decode_semantic_tokens(&serde_json::json!({"data": [0, 1, 0, 0, 0]}), &legend).is_err()
        );
    }

    #[test]
    fn definition_response_accepts_location_and_location_link_utf16_positions() {
        let location = serde_json::json!({
            "uri": "file:///workspace/target.rs",
            "range": {"start": {"line": 2, "character": 5}}
        });
        assert_eq!(
            extract_definition_location(&location),
            Some(DefinitionLocation {
                uri: "file:///workspace/target.rs".into(),
                line: 2,
                character: 5,
            })
        );

        let links = serde_json::json!([
            {"not": "a location"},
            {
                "targetUri": "file:///workspace/target.rs",
                "targetRange": {"start": {"line": 8, "character": 0}},
                "targetSelectionRange": {"start": {"line": 3, "character": 7}}
            }
        ]);
        assert_eq!(
            extract_definition_location(&links),
            Some(DefinitionLocation {
                uri: "file:///workspace/target.rs".into(),
                line: 3,
                character: 7,
            })
        );
        assert_eq!(extract_definition_location(&serde_json::Value::Null), None);
    }
}
