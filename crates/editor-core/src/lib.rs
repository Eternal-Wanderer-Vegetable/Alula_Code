//! Alula Code 的核心组装层：文档注册表 + 增量同步协议（见 docs/02-关键技术设计 §2）。
//!
//! 协议要点：
//! - 每个文档带单调递增版本号；Dart 侧提交操作时必须携带其基于的版本号；
//! - 版本不符即拒绝（VersionMismatch），Dart 侧应 resync 重建；
//! - 所有 offset 为 UTF-16 口径（换算见 editor-buffer）。

use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};

use editor_buffer::{BufferError, TextBuffer, TextOp};
use editor_lang::SyntaxEngine;
use editor_lsp::LspServer;

pub mod ffi;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ApplyError {
    UnknownDoc,
    VersionMismatch { current: u64 },
    Buffer(BufferError),
}

impl std::fmt::Display for ApplyError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ApplyError::UnknownDoc => write!(f, "unknown doc id"),
            ApplyError::VersionMismatch { current } => {
                write!(f, "version mismatch, current version is {current}")
            }
            ApplyError::Buffer(e) => write!(f, "buffer error: {e}"),
        }
    }
}

impl std::error::Error for ApplyError {}

impl From<BufferError> for ApplyError {
    fn from(e: BufferError) -> Self {
        ApplyError::Buffer(e)
    }
}

/// 文档注册表：MVP 阶段内存态；journal/原子保存由后续的 editor-doc 承接。
pub struct DocRegistry {
    docs: HashMap<u64, TextBuffer>,
    uris: HashMap<u64, String>,
    lsp: HashMap<u64, Arc<LspServer>>,
}

impl DocRegistry {
    pub fn new() -> Self {
        DocRegistry {
            docs: HashMap::new(),
            uris: HashMap::new(),
            lsp: HashMap::new(),
        }
    }

    pub fn open(&mut self, id: u64, content: &str) -> u64 {
        let buf = TextBuffer::open(content);
        let version = buf.version();
        self.docs.insert(id, buf);
        version
    }

    /// 校验 base_version 后按序应用 ops，返回应用后的新版本号。
    /// 若文档挂接了 LSP，自动随发全量 didChange（docs/02 §3：MVP 用全量同步）。
    pub fn apply(&mut self, id: u64, base_version: u64, ops: &[TextOp]) -> Result<u64, ApplyError> {
        let buf = self.docs.get_mut(&id).ok_or(ApplyError::UnknownDoc)?;
        let current = buf.version();
        if current != base_version {
            return Err(ApplyError::VersionMismatch { current });
        }
        buf.apply_ops(ops)?;
        let version = buf.version();
        if let (Some(uri), Some(lsp)) = (self.uris.get(&id), self.lsp.get(&id)) {
            // 尽力而为：LSP 同步失败不影响编辑主链路
            let _ = lsp.did_change_full(uri, version as i64, &buf.text());
        }
        Ok(version)
    }

    pub fn content(&self, id: u64) -> Option<(u64, String)> {
        self.docs.get(&id).map(|b| (b.version(), b.text()))
    }

    pub fn text_of(&self, id: u64) -> Option<String> {
        self.docs.get(&id).map(|b| b.text())
    }

    pub fn version_of(&self, id: u64) -> Option<u64> {
        self.docs.get(&id).map(|b| b.version())
    }

    /// UTF-16 offset → LSP 行列（0 基）。
    pub fn line_col(&self, id: u64, offset_utf16: usize) -> Option<(u64, u64)> {
        self.docs.get(&id)?.line_col_utf16(offset_utf16)
    }

    pub fn set_uri(&mut self, id: u64, uri: String) -> bool {
        if self.docs.contains_key(&id) {
            self.uris.insert(id, uri);
            true
        } else {
            false
        }
    }

    pub fn uri_of(&self, id: u64) -> Option<String> {
        self.uris.get(&id).cloned()
    }

    pub fn attach_lsp(&mut self, id: u64, server: Arc<LspServer>) -> bool {
        if self.docs.contains_key(&id) {
            self.lsp.insert(id, server);
            true
        } else {
            false
        }
    }

    pub fn detach_lsp(&mut self, id: u64) -> bool {
        self.lsp.remove(&id).is_some()
    }

    pub fn lsp_of(&self, id: u64) -> Option<Arc<LspServer>> {
        self.lsp.get(&id).cloned()
    }

    /// Detach every document using this workspace server and return their URIs
    /// so the caller can send didClose before the server shutdown handshake.
    pub fn detach_lsp_server(&mut self, server: &Arc<LspServer>) -> Vec<String> {
        let ids: Vec<u64> = self
            .lsp
            .iter()
            .filter_map(|(id, attached)| Arc::ptr_eq(attached, server).then_some(*id))
            .collect();
        for id in &ids {
            self.lsp.remove(id);
        }
        ids.into_iter()
            .filter_map(|id| self.uris.get(&id).cloned())
            .collect()
    }

    pub fn close(&mut self, id: u64) -> bool {
        self.uris.remove(&id);
        self.lsp.remove(&id);
        self.docs.remove(&id).is_some()
    }

    pub fn len(&self) -> usize {
        self.docs.len()
    }

    pub fn is_empty(&self) -> bool {
        self.docs.is_empty()
    }
}

impl Default for DocRegistry {
    fn default() -> Self {
        Self::new()
    }
}

// ---------- 语法引擎（全局共享一个 tree-sitter 解析器） ----------

static SYNTAX: OnceLock<Mutex<SyntaxEngine>> = OnceLock::new();

pub fn syntax_engine() -> &'static Mutex<SyntaxEngine> {
    SYNTAX
        .get_or_init(|| Mutex::new(SyntaxEngine::rust().expect("初始化 tree-sitter rust 引擎失败")))
}

/// 解析文档当前全文，返回 (版本, tokens)。未挂语法引擎的文档也可调用。
pub fn syntax_tokens(id: u64) -> Option<(u64, Vec<editor_lang::Token>)> {
    let text = {
        let reg = registry_shared().lock().ok()?;
        reg.text_of(id)?
    };
    let mut engine = syntax_engine().lock().ok()?;
    let tokens = engine.parse(&text).ok()?;
    drop(engine);
    let version = registry_shared().lock().ok()?.version_of(id)?;
    Some((version, tokens))
}

/// 提取文档符号定义（大纲视图）。未挂语法引擎的文档也可调用。
pub fn doc_symbols(id: u64) -> Option<(u64, Vec<editor_lang::Symbol>)> {
    let text = {
        let reg = registry_shared().lock().ok()?;
        reg.text_of(id)?
    };
    let mut engine = syntax_engine().lock().ok()?;
    let symbols = engine.symbols(&text).ok()?;
    drop(engine);
    let version = registry_shared().lock().ok()?.version_of(id)?;
    Some((version, symbols))
}

// FFI 层与语法层共享同一个注册表实例。
pub(crate) fn registry_shared() -> &'static Mutex<DocRegistry> {
    ffi::registry()
}

// ---------- 工作区级 LSP 服务器（同一工作区所有文档共享一个服务器进程） ----------

static WORKSPACE_SERVERS: OnceLock<Mutex<HashMap<String, Arc<LspServer>>>> = OnceLock::new();

fn workspace_servers() -> &'static Mutex<HashMap<String, Arc<LspServer>>> {
    WORKSPACE_SERVERS.get_or_init(|| Mutex::new(HashMap::new()))
}

/// 获取（或启动）工作区对应的 LSP 服务器。同一 root 复用同一进程。
pub fn lsp_start_for_workspace(root: &str, cmd: &[String]) -> Result<Arc<LspServer>, String> {
    let mut servers = workspace_servers()
        .lock()
        .map_err(|_| "workspace servers 锁中毒")?;
    if let Some(existing) = servers.get(root) {
        // 探活：若进程已退出则移除并重启
        if existing.is_alive() {
            return Ok(Arc::clone(existing));
        }
        servers.remove(root);
    }
    let server = Arc::new(LspServer::spawn(root, cmd)?);
    servers.insert(root.to_string(), Arc::clone(&server));
    Ok(server)
}

/// Close all documents attached to a workspace server, perform the LSP
/// shutdown/exit handshake, and reap its process.
pub fn lsp_shutdown_for_workspace(root: &str) -> Result<bool, String> {
    let mut servers = workspace_servers()
        .lock()
        .map_err(|_| "workspace servers 锁中毒")?;
    let Some(server) = servers.get(root).cloned() else {
        return Ok(false);
    };

    let uris = registry_shared()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .detach_lsp_server(&server);
    for uri in uris {
        // Closing the workspace must still reap its server if a best-effort
        // didClose notification fails; the shutdown handshake reports its own
        // result below.
        let _ = server.did_close(&uri);
    }

    let result = server.shutdown();
    servers.remove(root);
    result?;
    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn open_apply_flow() {
        let mut reg = DocRegistry::new();
        assert_eq!(reg.open(1, "hello"), 1);
        let v = reg
            .apply(
                1,
                1,
                &[TextOp::Insert {
                    offset_utf16: 5,
                    text: "!".into(),
                }],
            )
            .unwrap();
        assert_eq!(v, 2);
        assert_eq!(reg.content(1), Some((2, "hello!".to_string())));
    }

    #[test]
    fn stale_version_is_rejected_with_current() {
        let mut reg = DocRegistry::new();
        reg.open(1, "abc");
        let err = reg.apply(1, 99, &[]).unwrap_err();
        assert_eq!(err, ApplyError::VersionMismatch { current: 1 });
    }

    #[test]
    fn unknown_doc_is_rejected() {
        let mut reg = DocRegistry::new();
        let err = reg.apply(42, 1, &[]).unwrap_err();
        assert_eq!(err, ApplyError::UnknownDoc);
    }

    #[test]
    fn close_removes_doc_and_side_state() {
        let mut reg = DocRegistry::new();
        reg.open(7, "x");
        assert!(reg.set_uri(7, "file:///x.rs".into()));
        assert!(reg.close(7));
        assert!(!reg.close(7));
        assert!(reg.is_empty());
        assert!(reg.uri_of(7).is_none());
    }

    #[test]
    fn line_col_roundtrip() {
        let mut reg = DocRegistry::new();
        reg.open(9, "中文 fn\n  x\n");
        assert_eq!(reg.line_col(9, 3), Some((0, 3)));
        assert_eq!(reg.line_col(9, 999), None);
    }
}
