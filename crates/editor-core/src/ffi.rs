//! 手写 C ABI（MVP 阶段不引入 flutter_rust_bridge 代码生成，保持工具链最简；
//! ABI 面窄且 JSON 承载语义，后续迁移 FRB 时本模块整体替换即可，见 docs/02 §2.2）。
//!
//! 约定：
//! - 所有返回字符串的函数返回 `*mut c_char`（JSON，UTF-8，调用方用
//!   `alula_string_free` 释放）；
//! - 所有跨 FFI 的 offset 为 UTF-16 code unit；
//! - 结果统一为 `{"ok":true,...}` / `{"ok":false,"error":{"code":...}}`。
//!
//! 诊断/补全轮询说明（docs/02 §2.2 的 FRB 事件流迁移前的过渡方案）：
//! Dart 侧以 500ms 级别轮询 `alula_diagnostics` / `alula_syntax`；
//! `alula_completion_start/poll/cancel` 提供有界、可取消的异步补全请求；
//! `alula_completion` 保留为旧调用方的同步兼容入口。

use std::collections::HashMap;
use std::ffi::{c_char, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, OnceLock};
use std::time::{Duration, Instant};

use editor_buffer::{BufferError, TextOp};
use editor_doc::{LineEnding, TextEncoding, TextFileOptions};
use editor_lsp::{
    decode_semantic_tokens, extract_completion_labels, extract_definition_location,
    DefinitionLocation, LspPendingRequest, LspServer, SemanticToken, SemanticTokenLegend,
};
use editor_process::{ProcessKind, ProcessMetadata, ProcessSupervisor, ResourcePressureMonitor};
use serde::Deserialize;
use serde_json::json;

use crate::{ApplyError, DocRegistry, WorkspaceEditError};

/// ABI/协议版本；Dart 侧加载后应校验。
pub const ALULA_ABI_VERSION: u32 = 20;

const MAX_PENDING_COMPLETIONS: usize = 32;
static NEXT_COMPLETION_ID: AtomicU64 = AtomicU64::new(1);
const MAX_PENDING_SEMANTIC_TOKENS: usize = 16;
const MAX_SEMANTIC_TOKENS_PER_DOCUMENT: usize = 100_000;
static NEXT_SEMANTIC_TOKENS_ID: AtomicU64 = AtomicU64::new(1);
const MAX_PENDING_DEFINITIONS: usize = 16;
static NEXT_DEFINITION_ID: AtomicU64 = AtomicU64::new(1);

#[derive(Deserialize)]
struct WorkspaceEditDocumentInput {
    id: u64,
    base_version: u64,
    ops: Vec<TextOp>,
}

struct PendingCompletion {
    document_id: u64,
    document_version: u64,
    server: Arc<LspServer>,
    request: LspPendingRequest,
    deadline: Instant,
}

struct PendingSemanticTokens {
    document_id: u64,
    document_version: u64,
    server: Arc<LspServer>,
    legend: SemanticTokenLegend,
    request: LspPendingRequest,
    deadline: Instant,
}

struct PendingDefinition {
    document_id: u64,
    document_version: u64,
    server: Arc<LspServer>,
    request: LspPendingRequest,
    deadline: Instant,
}

static PENDING_COMPLETIONS: OnceLock<Mutex<HashMap<u64, PendingCompletion>>> = OnceLock::new();
static PENDING_SEMANTIC_TOKENS: OnceLock<Mutex<HashMap<u64, PendingSemanticTokens>>> =
    OnceLock::new();
static PENDING_DEFINITIONS: OnceLock<Mutex<HashMap<u64, PendingDefinition>>> = OnceLock::new();
static RESOURCE_MONITOR: OnceLock<Mutex<Option<ResourcePressureMonitor>>> = OnceLock::new();

fn pending_completions() -> &'static Mutex<HashMap<u64, PendingCompletion>> {
    PENDING_COMPLETIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn pending_completions_lock() -> MutexGuard<'static, HashMap<u64, PendingCompletion>> {
    pending_completions()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn take_pending_completions(
    mut matches: impl FnMut(&PendingCompletion) -> bool,
) -> Vec<PendingCompletion> {
    let mut pending = pending_completions_lock();
    let ids: Vec<u64> = pending
        .iter()
        .filter_map(|(id, request)| matches(request).then_some(*id))
        .collect();
    ids.into_iter()
        .filter_map(|id| pending.remove(&id))
        .collect()
}

fn cancel_requests(requests: Vec<PendingCompletion>) {
    for mut pending in requests {
        let _ = pending.request.cancel();
    }
}

fn cancel_all_completions() {
    cancel_requests(take_pending_completions(|_| true));
}

fn sample_resource_pressure() -> Result<editor_process::MemorySnapshot, String> {
    let monitor = RESOURCE_MONITOR.get_or_init(|| Mutex::new(None));
    let mut monitor = monitor
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if monitor.is_none() {
        *monitor = Some(ResourcePressureMonitor::new().map_err(|e| e.to_string())?);
    }
    monitor
        .as_mut()
        .expect("resource monitor initialized")
        .sample()
        .map_err(|e| e.to_string())
}

fn cancel_completions_for_doc(id: u64) {
    cancel_requests(take_pending_completions(|request| {
        request.document_id == id
    }));
}

fn pending_semantic_tokens_lock() -> MutexGuard<'static, HashMap<u64, PendingSemanticTokens>> {
    PENDING_SEMANTIC_TOKENS
        .get_or_init(|| Mutex::new(HashMap::new()))
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn cancel_semantic_tokens_for_doc(id: u64) {
    let requests: Vec<_> = {
        let mut pending = pending_semantic_tokens_lock();
        let ids: Vec<_> = pending
            .iter()
            .filter_map(|(request_id, request)| (request.document_id == id).then_some(*request_id))
            .collect();
        ids.into_iter()
            .filter_map(|request_id| pending.remove(&request_id))
            .collect()
    };
    for mut pending in requests {
        let _ = pending.request.cancel();
    }
}

pub(crate) fn cancel_semantic_tokens_for_server(server: &Arc<LspServer>) {
    let requests: Vec<_> = {
        let mut pending = pending_semantic_tokens_lock();
        let ids: Vec<_> = pending
            .iter()
            .filter_map(|(request_id, request)| {
                Arc::ptr_eq(&request.server, server).then_some(*request_id)
            })
            .collect();
        ids.into_iter()
            .filter_map(|request_id| pending.remove(&request_id))
            .collect()
    };
    for mut pending in requests {
        let _ = pending.request.cancel();
    }
}

fn pending_definitions_lock() -> MutexGuard<'static, HashMap<u64, PendingDefinition>> {
    PENDING_DEFINITIONS
        .get_or_init(|| Mutex::new(HashMap::new()))
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn cancel_definitions_for_doc(id: u64) {
    let requests: Vec<_> = {
        let mut pending = pending_definitions_lock();
        let ids: Vec<_> = pending
            .iter()
            .filter_map(|(request_id, request)| (request.document_id == id).then_some(*request_id))
            .collect();
        ids.into_iter()
            .filter_map(|request_id| pending.remove(&request_id))
            .collect()
    };
    for mut pending in requests {
        let _ = pending.request.cancel();
    }
}

pub(crate) fn cancel_definitions_for_server(server: &Arc<LspServer>) {
    let requests: Vec<_> = {
        let mut pending = pending_definitions_lock();
        let ids: Vec<_> = pending
            .iter()
            .filter_map(|(request_id, request)| {
                Arc::ptr_eq(&request.server, server).then_some(*request_id)
            })
            .collect();
        ids.into_iter()
            .filter_map(|request_id| pending.remove(&request_id))
            .collect()
    };
    for mut pending in requests {
        let _ = pending.request.cancel();
    }
}

fn cancel_all_definitions() {
    let requests: Vec<_> = pending_definitions_lock()
        .drain()
        .map(|(_, request)| request)
        .collect();
    for mut pending in requests {
        let _ = pending.request.cancel();
    }
}

fn semantic_token_ranges(
    tokens: &[SemanticToken],
    document_version: u64,
    mut line_offset: impl FnMut(usize) -> Option<Result<editor_buffer::TextLineOffset, BufferError>>,
) -> Result<Vec<serde_json::Value>, String> {
    let mut absolute = Vec::with_capacity(tokens.len());
    let mut previous_end = 0usize;
    for token in tokens {
        let line = line_offset(token.line as usize)
            .ok_or_else(|| "semantic token line is outside the document".to_string())?
            .map_err(|error| error.to_string())?;
        if line.version != document_version {
            return Err("semantic token document version changed".into());
        }
        let start = line
            .offset_utf16
            .checked_add(token.start_character as usize)
            .ok_or_else(|| "semantic token start overflow".to_string())?;
        let end = start
            .checked_add(token.length as usize)
            .ok_or_else(|| "semantic token end overflow".to_string())?;
        if end > line.total_utf16_length || start < previous_end {
            return Err("semantic token range is outside document or overlaps".into());
        }
        previous_end = end;
        absolute.push(json!({
            "start_utf16": start,
            "end_utf16": end,
            "kind": token.kind,
        }));
    }
    Ok(absolute)
}

pub(crate) fn cancel_completions_for_server(server: &Arc<LspServer>) {
    cancel_requests(take_pending_completions(|request| {
        Arc::ptr_eq(&request.server, server)
    }));
}

static REGISTRY: OnceLock<Mutex<DocRegistry>> = OnceLock::new();

pub(crate) fn registry() -> &'static Mutex<DocRegistry> {
    REGISTRY.get_or_init(|| Mutex::new(DocRegistry::new()))
}

fn registry_lock() -> MutexGuard<'static, DocRegistry> {
    // 中毒即恢复：MVP 下 panic 后注册表内容仍是有效文档状态。
    registry().lock().unwrap_or_else(|p| p.into_inner())
}

// ---------- JSON / C 字符串辅助 ----------

fn to_c_ptr(s: String) -> *mut c_char {
    // JSON 序列化不会产生内部 NUL；万一出现则返回错误 JSON。
    match CString::new(s) {
        Ok(c) => c.into_raw(),
        Err(_) => CString::new(r#"{"ok":false,"error":{"code":"Internal"}}"#)
            .unwrap()
            .into_raw(),
    }
}

fn err_json(code: &str, detail: serde_json::Value) -> *mut c_char {
    to_c_ptr(
        json!({
            "ok": false,
            "error": { "code": code, "detail": detail }
        })
        .to_string(),
    )
}

/// # Safety
/// `ptr` 必须是本库返回的指针，且只能释放一次；为 NULL 时不做任何事。
#[no_mangle]
pub unsafe extern "C" fn alula_string_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}

unsafe fn read_c_str<'a>(ptr: *const c_char) -> Result<&'a str, *mut c_char> {
    if ptr.is_null() {
        return Err(err_json("InvalidArgument", json!("null string pointer")));
    }
    CStr::from_ptr(ptr)
        .to_str()
        .map_err(|_| err_json("InvalidArgument", json!("string is not valid UTF-8")))
}

// ---------- 导出函数：文档核心 ----------

/// 返回 ABI/协议版本。
#[no_mangle]
pub extern "C" fn alula_abi_version() -> u32 {
    ALULA_ABI_VERSION
}

/// Sample system/cgroup memory pressure. On a transition to Critical, cancel pending
/// completions/definition requests and stop registered search processes; editing remains enabled.
#[no_mangle]
pub extern "C" fn alula_resource_status() -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        let snapshot = match sample_resource_pressure() {
            Ok(snapshot) => snapshot,
            Err(error) => return err_json("ResourceUnavailable", json!(error)),
        };
        let mut stopped_searches = 0;
        let mut reclaim_error = None;
        if snapshot.transitioned_to_critical {
            cancel_all_completions();
            cancel_all_definitions();
            match ProcessSupervisor::global().stop_registered_kind(ProcessKind::Search) {
                Ok(stopped) => stopped_searches = stopped,
                Err(error) => reclaim_error = Some(error.to_string()),
            }
        }
        to_c_ptr(
            json!({
                "ok": true,
                "pressure": snapshot.pressure.as_str(),
                "totalBytes": snapshot.total_bytes,
                "availableBytes": snapshot.available_bytes,
                "source": snapshot.source.as_str(),
                "transitionedToCritical": snapshot.transitioned_to_critical,
                "stoppedSearchProcesses": stopped_searches,
                "reclaimError": reclaim_error,
            })
            .to_string(),
        )
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_resource_status")))
}

/// Return an on-demand process-tree snapshot for processes registered by Rust or Dart.
#[no_mangle]
pub extern "C" fn alula_process_snapshot() -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        let processes = match ProcessSupervisor::global().snapshot() {
            Ok(processes) => processes,
            Err(error) => return err_json("ProcessSnapshotFailed", json!(error.to_string())),
        };
        let processes: Vec<_> = processes
            .into_iter()
            .map(|process| {
                json!({
                    "rootPid": process.root_pid,
                    "pid": process.pid,
                    "parentPid": process.parent_pid,
                    "name": process.name,
                    "label": process.label,
                    "kind": process.kind.as_str(),
                    "workspace": process.workspace,
                    "residentBytes": process.resident_bytes,
                })
            })
            .collect();
        to_c_ptr(json!({ "ok": true, "processes": processes }).to_string())
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_process_snapshot")))
}

/// Register a host-layer child process (for example Dart `Process.start`) for ownership and
/// process-tree reporting. `workspace` may be NULL.
///
/// # Safety
/// `kind` and `label`, and non-null `workspace`, must point to valid NUL-terminated UTF-8 strings
/// that remain readable for the duration of this call.
#[no_mangle]
pub unsafe extern "C" fn alula_process_register(
    pid: u32,
    kind: *const c_char,
    label: *const c_char,
    workspace: *const c_char,
) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        let kind = match read_c_str(kind) {
            Ok(value) => ProcessKind::from_tag(value),
            Err(error) => return error,
        };
        let label = match read_c_str(label) {
            Ok(value) => value.to_string(),
            Err(error) => return error,
        };
        let workspace = if workspace.is_null() {
            None
        } else {
            match read_c_str(workspace) {
                Ok(value) => Some(value.to_string()),
                Err(error) => return error,
            }
        };
        if pid == 0 {
            return err_json("InvalidArgument", json!("pid must be positive"));
        }
        match ProcessSupervisor::global().register_external(
            pid,
            ProcessMetadata {
                label,
                kind,
                workspace,
            },
        ) {
            Ok(()) => to_c_ptr(json!({ "ok": true }).to_string()),
            Err(error) => err_json("ProcessRegisterFailed", json!(error.to_string())),
        }
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_process_register")))
}

/// Remove a host-layer child registration after its exit future completes.
#[no_mangle]
pub extern "C" fn alula_process_unregister(pid: u32) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        match ProcessSupervisor::global().unregister_external(pid) {
            Ok(()) => to_c_ptr(json!({ "ok": true }).to_string()),
            Err(error) => err_json("ProcessUnregisterFailed", json!(error.to_string())),
        }
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_process_unregister")))
}

/// 打开文档（初始全量传输仅此一次）。返回 `{"ok":true,"version":1}`。
///
/// # Safety
/// `content` 必须是合法的 NUL 结尾 UTF-8 C 字符串。
#[no_mangle]
pub unsafe extern "C" fn alula_doc_open(id: u64, content: *const c_char) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        let content = match read_c_str(content) {
            Ok(s) => s,
            Err(e) => return e,
        };
        let version = registry_lock().open(id, content);
        to_c_ptr(json!({ "ok": true, "version": version }).to_string())
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_doc_open")))
}

/// Set a document's disk/recovery savepoint without changing its text version.
///
/// # Safety
/// `content` must be a valid NUL-terminated UTF-8 C string.
#[no_mangle]
pub unsafe extern "C" fn alula_doc_set_savepoint(id: u64, content: *const c_char) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        let content = match read_c_str(content) {
            Ok(content) => content,
            Err(error) => return error,
        };
        if registry_lock().set_savepoint_text(id, content) {
            to_c_ptr(json!({ "ok": true }).to_string())
        } else {
            err_json("UnknownDoc", json!({ "id": id }))
        }
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_doc_set_savepoint")))
}

/// Mark the current document text as its savepoint without changing its version.
#[no_mangle]
pub extern "C" fn alula_doc_mark_saved(id: u64) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        if registry_lock().mark_saved(id) {
            to_c_ptr(json!({ "ok": true }).to_string())
        } else {
            err_json("UnknownDoc", json!({ "id": id }))
        }
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_doc_mark_saved")))
}

/// Return exact dirty state compared with the Rust-owned savepoint.
#[no_mangle]
pub extern "C" fn alula_doc_is_dirty(id: u64) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| match registry_lock().is_dirty(id) {
        Some(dirty) => to_c_ptr(json!({ "ok": true, "dirty": dirty }).to_string()),
        None => err_json("UnknownDoc", json!({ "id": id })),
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_doc_is_dirty")))
}

/// Compare an external text snapshot with the Rust-owned savepoint.
///
/// # Safety
/// `content` must be a valid NUL-terminated UTF-8 C string.
#[no_mangle]
pub unsafe extern "C" fn alula_doc_savepoint_matches(
    id: u64,
    content: *const c_char,
) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        let content = match read_c_str(content) {
            Ok(content) => content,
            Err(error) => return error,
        };
        match registry_lock().savepoint_matches_text(id, content) {
            Some(matches) => to_c_ptr(json!({ "ok": true, "matches": matches }).to_string()),
            None => err_json("UnknownDoc", json!({ "id": id })),
        }
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_doc_savepoint_matches")))
}

/// 应用增量操作。`ops_json` 为 `TextOp` 数组的 JSON（格式见 editor-buffer）。
///
/// # Safety
/// `ops_json` 必须是合法的 NUL 结尾 UTF-8 C 字符串。
#[no_mangle]
pub unsafe extern "C" fn alula_doc_apply(
    id: u64,
    base_version: u64,
    ops_json: *const c_char,
) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        let s = match read_c_str(ops_json) {
            Ok(s) => s,
            Err(e) => return e,
        };
        let ops: Vec<TextOp> = match serde_json::from_str(s) {
            Ok(v) => v,
            Err(e) => return err_json("ParseError", json!(e.to_string())),
        };
        let result = { registry_lock().apply(id, base_version, &ops) };
        match result {
            Ok(version) => {
                cancel_completions_for_doc(id);
                cancel_semantic_tokens_for_doc(id);
                to_c_ptr(json!({ "ok": true, "version": version }).to_string())
            }
            Err(ApplyError::VersionMismatch { current }) => {
                err_json("VersionMismatch", json!({ "current": current }))
            }
            Err(ApplyError::UnknownDoc) => err_json("UnknownDoc", json!({ "id": id })),
            Err(ApplyError::Buffer(e)) => err_json("BufferError", json!(e.to_string())),
        }
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_doc_apply")))
}

/// Apply a multi-document transaction after validating every document version and range.
/// `edits_json` is an array of `{id, base_version, ops}` objects.
///
/// # Safety
/// `edits_json` must be a valid NUL-terminated UTF-8 C string.
#[no_mangle]
pub unsafe extern "C" fn alula_workspace_edit_transaction(
    edits_json: *const c_char,
) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        let source = match read_c_str(edits_json) {
            Ok(source) => source,
            Err(error) => return error,
        };
        let inputs: Vec<WorkspaceEditDocumentInput> = match serde_json::from_str(source) {
            Ok(inputs) => inputs,
            Err(error) => return err_json("ParseError", json!(error.to_string())),
        };
        let edits: Vec<_> = inputs
            .into_iter()
            .map(|edit| (edit.id, edit.base_version, edit.ops))
            .collect();
        let result = { registry_lock().apply_workspace_edit(&edits) };
        match result {
            Ok(versions) => {
                for (id, _) in &versions {
                    cancel_completions_for_doc(*id);
                    cancel_semantic_tokens_for_doc(*id);
                }
                to_c_ptr(
                    json!({
                        "ok": true,
                        "versions": versions.iter().map(|(id, version)| json!({
                            "id": id,
                            "version": version,
                        })).collect::<Vec<_>>(),
                    })
                    .to_string(),
                )
            }
            Err(WorkspaceEditError::Empty) => {
                err_json("InvalidWorkspaceEdit", json!("empty transaction"))
            }
            Err(WorkspaceEditError::DuplicateDocument { id }) => {
                err_json("InvalidWorkspaceEdit", json!({ "duplicateDocument": id }))
            }
            Err(WorkspaceEditError::UnknownDocument { id }) => {
                err_json("UnknownDoc", json!({ "id": id }))
            }
            Err(WorkspaceEditError::VersionMismatch { id, current }) => {
                err_json("VersionMismatch", json!({ "id": id, "current": current }))
            }
            Err(WorkspaceEditError::Buffer { id, source }) => err_json(
                "BufferError",
                json!({ "id": id, "detail": source.to_string() }),
            ),
        }
    }))
    .unwrap_or_else(|_| {
        err_json(
            "Internal",
            json!("panic in alula_workspace_edit_transaction"),
        )
    })
}

/// 全量重同步：返回文档当前版本与全文，Dart 侧据此重建本地状态。
///
/// # Safety
/// 无。
#[no_mangle]
pub extern "C" fn alula_doc_resync(id: u64) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| match registry_lock().content(id) {
        Some((version, content)) => {
            to_c_ptr(json!({ "ok": true, "version": version, "content": content }).to_string())
        }
        None => err_json("UnknownDoc", json!({ "id": id })),
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_doc_resync")))
}

/// Read a bounded UTF-16 range from the Rust-authoritative document.
/// The returned JSON includes the snapshot version, document size, line count,
/// absolute range and its line/column origin.
#[no_mangle]
pub extern "C" fn alula_doc_read_range(
    id: u64,
    start_utf16: u64,
    max_len_utf16: u64,
) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        let Ok(start_utf16) = usize::try_from(start_utf16) else {
            return err_json(
                "InvalidArgument",
                json!("start offset is not representable"),
            );
        };
        let Ok(max_len_utf16) = usize::try_from(max_len_utf16) else {
            return err_json("InvalidArgument", json!("read length is not representable"));
        };
        match registry_lock().read_range(id, start_utf16, max_len_utf16) {
            None => err_json("UnknownDoc", json!({ "id": id })),
            Some(Ok(range)) => to_c_ptr(
                json!({
                    "ok": true,
                    "version": range.version,
                    "totalUtf16Length": range.total_utf16_length,
                    "lineCount": range.line_count,
                    "startUtf16": range.start_utf16,
                    "endUtf16": range.end_utf16,
                    "startLine": range.start_line,
                    "startCharacter": range.start_character,
                    "text": range.text,
                })
                .to_string(),
            ),
            Some(Err(BufferError::InvalidUtf16Offset { offset_utf16 })) => {
                err_json("InvalidUtf16Offset", json!({ "offsetUtf16": offset_utf16 }))
            }
            Some(Err(BufferError::ReadRangeTooLarge { requested, max })) => err_json(
                "ReadRangeTooLarge",
                json!({ "requested": requested, "max": max }),
            ),
            Some(Err(error)) => err_json("InvalidRange", json!(error.to_string())),
        }
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_doc_read_range")))
}

/// Resolve a zero-based line to its absolute UTF-16 start offset.
#[no_mangle]
pub extern "C" fn alula_doc_line_offset(id: u64, line: u64) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        let Ok(line) = usize::try_from(line) else {
            return err_json("InvalidArgument", json!("line index is not representable"));
        };
        match registry_lock().line_offset_utf16(id, line) {
            None => err_json("UnknownDoc", json!({ "id": id })),
            Some(Ok(offset)) => to_c_ptr(
                json!({
                    "ok": true,
                    "version": offset.version,
                    "totalUtf16Length": offset.total_utf16_length,
                    "lineCount": offset.line_count,
                    "line": offset.line,
                    "offsetUtf16": offset.offset_utf16,
                })
                .to_string(),
            ),
            Some(Err(BufferError::InvalidLine { line, line_count })) => err_json(
                "InvalidLine",
                json!({ "line": line, "lineCount": line_count }),
            ),
            Some(Err(error)) => err_json("InvalidRange", json!(error.to_string())),
        }
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_doc_line_offset")))
}

/// Convert an absolute Rust-document UTF-16 offset to an LSP UTF-16 position.
#[no_mangle]
pub extern "C" fn alula_doc_position(id: u64, offset_utf16: u64) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        let Ok(offset_utf16) = usize::try_from(offset_utf16) else {
            return err_json("InvalidArgument", json!("offset is not representable"));
        };
        let reg = registry_lock();
        let Some(version) = reg.version_of(id) else {
            return err_json("UnknownDoc", json!({ "id": id }));
        };
        let Some((line, character)) = reg.line_col(id, offset_utf16) else {
            return err_json(
                "InvalidUtf16Offset",
                json!({ "id": id, "offsetUtf16": offset_utf16 }),
            );
        };
        to_c_ptr(
            json!({
                "ok": true,
                "version": version,
                "line": line,
                "character": character,
                "offsetUtf16": offset_utf16,
            })
            .to_string(),
        )
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_doc_position")))
}

/// Convert a zero-based LSP UTF-16 line/character position to an absolute
/// Rust-document UTF-16 offset. Columns beyond line end are clamped; a column
/// inside a surrogate pair is moved back to its scalar boundary.
#[no_mangle]
pub extern "C" fn alula_doc_position_offset(id: u64, line: u64, character: u64) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        let (line, character) = match (usize::try_from(line), usize::try_from(character)) {
            (Ok(line), Ok(character)) => (line, character),
            _ => return err_json("InvalidArgument", json!("position is not representable")),
        };
        let reg = registry_lock();
        if reg.version_of(id).is_none() {
            return err_json("UnknownDoc", json!({ "id": id }));
        }
        let Some(Ok(line_start)) = reg.line_offset_utf16(id, line) else {
            return err_json("InvalidLine", json!({ "id": id, "line": line }));
        };
        let line_end = if line
            .checked_add(1)
            .is_some_and(|next| next < line_start.line_count)
        {
            let next_line = line + 1;
            match reg.line_offset_utf16(id, next_line) {
                Some(Ok(next)) if next.version == line_start.version => next.offset_utf16,
                _ => return err_json("InvalidLine", json!({ "id": id, "line": next_line })),
            }
        } else {
            line_start.total_utf16_length
        };

        let mut line_ending_len = 0usize;
        if line_end > line_start.offset_utf16 {
            if let Some(Ok(last)) = reg.read_range(id, line_end - 1, 1) {
                if last.text == "\n" {
                    line_ending_len = 1;
                    if line_end >= line_start.offset_utf16 + 2 {
                        if let Some(Ok(before_last)) = reg.read_range(id, line_end - 2, 1) {
                            if before_last.text == "\r" {
                                line_ending_len = 2;
                            }
                        }
                    }
                }
            }
        }

        let content_end = line_end.saturating_sub(line_ending_len);
        let content_len = content_end.saturating_sub(line_start.offset_utf16);
        let mut offset_utf16 = line_start.offset_utf16 + character.min(content_len);
        if offset_utf16 > line_start.offset_utf16
            && matches!(
                reg.read_range(id, offset_utf16, 1),
                Some(Err(BufferError::InvalidUtf16Offset { .. }))
            )
        {
            offset_utf16 -= 1;
        }
        to_c_ptr(
            json!({
                "ok": true,
                "version": line_start.version,
                "line": line,
                "character": offset_utf16 - line_start.offset_utf16,
                "offsetUtf16": offset_utf16,
            })
            .to_string(),
        )
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_doc_position_offset")))
}

/// Read a bounded batch of UTF-16 line windows from one Rust document snapshot.
#[no_mangle]
pub extern "C" fn alula_doc_read_lines(
    id: u64,
    first_line: u64,
    max_lines: u64,
    horizontal_start_utf16: u64,
    max_line_utf16: u64,
    max_total_utf16: u64,
) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        let Ok(first_line) = usize::try_from(first_line) else {
            return err_json("InvalidArgument", json!("first line is not representable"));
        };
        let Ok(max_lines) = usize::try_from(max_lines) else {
            return err_json("InvalidArgument", json!("line count is not representable"));
        };
        let Ok(horizontal_start_utf16) = usize::try_from(horizontal_start_utf16) else {
            return err_json(
                "InvalidArgument",
                json!("horizontal offset is not representable"),
            );
        };
        let Ok(max_line_utf16) = usize::try_from(max_line_utf16) else {
            return err_json(
                "InvalidArgument",
                json!("per-line read length is not representable"),
            );
        };
        let Ok(max_total_utf16) = usize::try_from(max_total_utf16) else {
            return err_json(
                "InvalidArgument",
                json!("total read length is not representable"),
            );
        };

        match registry_lock().read_lines(
            id,
            first_line,
            max_lines,
            horizontal_start_utf16,
            max_line_utf16,
            max_total_utf16,
        ) {
            None => err_json("UnknownDoc", json!({ "id": id })),
            Some(Ok(page)) => to_c_ptr(
                json!({
                    "ok": true,
                    "version": page.version,
                    "totalUtf16Length": page.total_utf16_length,
                    "lineCount": page.line_count,
                    "firstLine": page.first_line,
                    "lines": page.lines.into_iter().map(|line| json!({
                        "line": line.line,
                        "startUtf16": line.start_utf16,
                        "endUtf16": line.end_utf16,
                        "text": line.text,
                    })).collect::<Vec<_>>(),
                })
                .to_string(),
            ),
            Some(Err(BufferError::InvalidLine { line, line_count })) => err_json(
                "InvalidLine",
                json!({ "line": line, "lineCount": line_count }),
            ),
            Some(Err(BufferError::ReadRangeTooLarge { requested, max })) => err_json(
                "ReadRangeTooLarge",
                json!({ "requested": requested, "max": max }),
            ),
            Some(Err(BufferError::ReadLineCountTooLarge { requested, max })) => err_json(
                "ReadLineCountTooLarge",
                json!({ "requested": requested, "max": max }),
            ),
            Some(Err(BufferError::InvalidLineWindow { .. })) => {
                err_json("InvalidLineWindow", json!("invalid line window limits"))
            }
            Some(Err(error)) => err_json("InvalidRange", json!(error.to_string())),
        }
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_doc_read_lines")))
}

/// Read a bounded, evenly sampled minimap snapshot from one Rust document.
#[no_mangle]
pub extern "C" fn alula_doc_minimap_sample(id: u64) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        match registry_lock().minimap_sample(id) {
            None => err_json("UnknownDoc", json!({ "id": id })),
            Some(sample) => to_c_ptr(
                json!({
                    "ok": true,
                    "version": sample.version,
                    "totalUtf16Length": sample.total_utf16_length,
                    "lineCount": sample.line_count,
                    "lines": sample.lines.into_iter().map(|line| json!({
                        "line": line.line,
                        "startUtf16": line.start_utf16,
                        "utf16Length": line.utf16_length,
                        "text": line.text,
                    })).collect::<Vec<_>>(),
                })
                .to_string(),
            ),
        }
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_doc_minimap_sample")))
}

/// 关闭文档并释放其缓冲区。
#[no_mangle]
pub extern "C" fn alula_doc_close(id: u64) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        cancel_completions_for_doc(id);
        cancel_semantic_tokens_for_doc(id);
        cancel_definitions_for_doc(id);
        let (server, uri) = {
            let reg = registry_lock();
            (reg.lsp_of(id), reg.uri_of(id))
        };
        if let (Some(server), Some(uri)) = (server, uri) {
            // A tab can close while its workspace server remains shared by
            // other documents, so notify the server before dropping the URI.
            let _ = server.did_close(&uri);
        }
        let removed = registry_lock().close(id);
        to_c_ptr(json!({ "ok": true, "removed": removed }).to_string())
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_doc_close")))
}

// ---------- 导出函数：文档 URI ----------

/// # Safety
/// `uri` 必须是合法的 NUL 结尾 UTF-8 C 字符串。
#[no_mangle]
pub unsafe extern "C" fn alula_doc_set_uri(id: u64, uri: *const c_char) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        let uri = match read_c_str(uri) {
            Ok(s) => s.to_string(),
            Err(e) => return e,
        };
        cancel_semantic_tokens_for_doc(id);
        cancel_definitions_for_doc(id);
        let known = registry_lock().set_uri(id, uri);
        to_c_ptr(json!({ "ok": true, "known": known }).to_string())
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_doc_set_uri")))
}

// ---------- 导出函数：LSP ----------

/// 启动语言服务器并挂接到文档。
/// `cmd_json` 为命令数组 JSON，如 `["rust-analyzer"]`。
///
/// # Safety
/// 两个字符串参数必须是合法的 NUL 结尾 UTF-8。
#[no_mangle]
pub unsafe extern "C" fn alula_lsp_start(
    id: u64,
    workspace_root: *const c_char,
    cmd_json: *const c_char,
) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        let root = match read_c_str(workspace_root) {
            Ok(s) => s.to_string(),
            Err(e) => return e,
        };
        let cmd_s = match read_c_str(cmd_json) {
            Ok(s) => s,
            Err(e) => return e,
        };
        let cmd: Vec<String> = match serde_json::from_str(cmd_s) {
            Ok(v) => v,
            Err(e) => return err_json("ParseError", json!(e.to_string())),
        };
        // 同一工作区复用同一服务器进程（docs/02 §3：一区一语言一服务器）
        let server = match crate::lsp_start_for_workspace(&root, &cmd) {
            Ok(s) => s,
            Err(e) => return err_json("SpawnFailed", json!(e)),
        };
        let known = registry_lock().attach_lsp(id, server);
        to_c_ptr(json!({ "ok": true, "attached": known }).to_string())
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_lsp_start")))
}

/// 停止并回收文档的 LSP 进程。
#[no_mangle]
pub extern "C" fn alula_lsp_stop(id: u64) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        cancel_completions_for_doc(id);
        cancel_semantic_tokens_for_doc(id);
        cancel_definitions_for_doc(id);
        let server = registry_lock().detach_lsp(id);
        // detach 只移除映射；进程由调用方通过返回值决定是否显式 shutdown。
        // MVP 简化：registry 不再持有 Arc 后，shutdown 在此无引用可用——
        // 因此 lsp_stop 的语义是「解除挂接」，进程随文档关闭/应用退出由 OS 回收。
        to_c_ptr(json!({ "ok": true, "detached": server }).to_string())
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_lsp_stop")))
}

/// 完成指定工作区的 LSP shutdown/exit 握手并回收服务进程。
///
/// # Safety
/// `workspace_root` 必须是合法的 NUL 结尾 UTF-8。
#[no_mangle]
pub unsafe extern "C" fn alula_lsp_shutdown_workspace(
    workspace_root: *const c_char,
) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        let root = match read_c_str(workspace_root) {
            Ok(s) => s.to_string(),
            Err(e) => return e,
        };
        match crate::lsp_shutdown_for_workspace(&root) {
            Ok(stopped) => to_c_ptr(json!({ "ok": true, "stopped": stopped }).to_string()),
            Err(e) => err_json("ShutdownFailed", json!(e)),
        }
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_lsp_shutdown_workspace")))
}

/// 以文档当前全文发送 didOpen（需已 set_uri）。版本取当前版本。
///
/// # Safety
/// `language_id` 必须是合法的 NUL 结尾 UTF-8。
#[no_mangle]
pub unsafe extern "C" fn alula_lsp_did_open(id: u64, language_id: *const c_char) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        let lang = match read_c_str(language_id) {
            Ok(s) => s.to_string(),
            Err(e) => return e,
        };
        let reg = registry_lock();
        let Some(uri) = reg.uri_of(id) else {
            return err_json("UnknownDoc", json!("doc 未设置 uri"));
        };
        let Some(server) = reg.lsp_of(id) else {
            return err_json("NoLsp", json!({ "id": id }));
        };
        let Some((version, text)) = reg.content(id) else {
            return err_json("UnknownDoc", json!({ "id": id }));
        };
        drop(reg);
        match server.did_open(&uri, &lang, version as i64, &text) {
            Ok(()) => to_c_ptr(json!({ "ok": true }).to_string()),
            Err(e) => err_json("SendFailed", json!(e)),
        }
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_lsp_did_open")))
}

/// 发送文档 didClose，但保留 Rust 文档缓冲区，供 URI 迁移后重新 didOpen。
#[no_mangle]
pub extern "C" fn alula_lsp_did_close(id: u64) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        cancel_semantic_tokens_for_doc(id);
        cancel_definitions_for_doc(id);
        let reg = registry_lock();
        if reg.version_of(id).is_none() {
            return err_json("UnknownDoc", json!({ "id": id }));
        }
        let Some(uri) = reg.uri_of(id) else {
            return to_c_ptr(json!({ "ok": true, "closed": false }).to_string());
        };
        let Some(server) = reg.lsp_of(id) else {
            return to_c_ptr(json!({ "ok": true, "closed": false }).to_string());
        };
        drop(reg);
        match server.did_close(&uri) {
            Ok(()) => to_c_ptr(json!({ "ok": true, "closed": true }).to_string()),
            Err(e) => err_json("SendFailed", json!(e)),
        }
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_lsp_did_close")))
}

/// 该文档 URI 的最新诊断快照（轮询式；RA 在后台推送，这里只读缓存）。
#[no_mangle]
pub extern "C" fn alula_diagnostics(id: u64) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        let reg = registry_lock();
        let Some(uri) = reg.uri_of(id) else {
            return err_json("UnknownDoc", json!("doc 未设置 uri"));
        };
        let Some(server) = reg.lsp_of(id) else {
            return err_json("NoLsp", json!({ "id": id }));
        };
        let diags = server.diagnostics(&uri);
        to_c_ptr(
            json!({
                "ok": true,
                "count": diags.len(),
                "items": diags,
            })
            .to_string(),
        )
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_diagnostics")))
}

/// Start one cancellable full semantic-token request for a Rust document.
#[no_mangle]
pub extern "C" fn alula_semantic_tokens_start(id: u64, timeout_ms: u64) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        let (uri, server, version) = {
            let reg = registry_lock();
            let Some(uri) = reg.uri_of(id) else {
                return err_json("UnknownDoc", json!({ "id": id }));
            };
            let Some(server) = reg.lsp_of(id) else {
                return err_json("NoLsp", json!({ "id": id }));
            };
            let Some(version) = reg.version_of(id) else {
                return err_json("UnknownDoc", json!({ "id": id }));
            };
            (uri, server, version)
        };
        let Some(legend) = server.semantic_token_legend() else {
            return to_c_ptr(json!({ "ok": true, "supported": false }).to_string());
        };

        cancel_semantic_tokens_for_doc(id);
        let request = match server.semantic_tokens_async(&uri) {
            Ok(Some(request)) => request,
            Ok(None) => return to_c_ptr(json!({ "ok": true, "supported": false }).to_string()),
            Err(error) => return err_json("SemanticTokensFailed", json!(error)),
        };
        let mut pending = pending_semantic_tokens_lock();
        if pending.len() >= MAX_PENDING_SEMANTIC_TOKENS {
            drop(pending);
            let mut request = request;
            let _ = request.cancel();
            return err_json(
                "Backpressure",
                json!({ "limit": MAX_PENDING_SEMANTIC_TOKENS }),
            );
        }
        let request_id = NEXT_SEMANTIC_TOKENS_ID.fetch_add(1, Ordering::Relaxed);
        let now = Instant::now();
        let deadline = now
            .checked_add(Duration::from_millis(timeout_ms))
            .unwrap_or_else(|| now + Duration::from_secs(86_400));
        pending.insert(
            request_id,
            PendingSemanticTokens {
                document_id: id,
                document_version: version,
                server,
                legend,
                request,
                deadline,
            },
        );
        to_c_ptr(
            json!({ "ok": true, "supported": true, "requestId": request_id, "version": version })
                .to_string(),
        )
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_semantic_tokens_start")))
}

/// Poll a semantic-token request and convert LSP relative UTF-16 positions to
/// absolute Rust-document UTF-16 offsets only if the captured version is current.
#[no_mangle]
pub extern "C" fn alula_semantic_tokens_poll(request_id: u64) -> *mut c_char {
    enum PollResult {
        Pending,
        Timeout(PendingSemanticTokens),
        Complete(PendingSemanticTokens, serde_json::Value),
        Failed(String),
    }

    catch_unwind(AssertUnwindSafe(|| {
        let result = {
            let mut requests = pending_semantic_tokens_lock();
            let Some(mut pending) = requests.remove(&request_id) else {
                return to_c_ptr(
                    json!({ "ok": true, "status": "cancelled", "requestId": request_id })
                        .to_string(),
                );
            };
            if Instant::now() >= pending.deadline {
                PollResult::Timeout(pending)
            } else {
                match pending.request.try_recv() {
                    Ok(Some(response)) => PollResult::Complete(pending, response),
                    Ok(None) => {
                        requests.insert(request_id, pending);
                        PollResult::Pending
                    }
                    Err(error) => PollResult::Failed(error),
                }
            }
        };

        match result {
            PollResult::Pending => to_c_ptr(
                json!({ "ok": true, "status": "pending", "requestId": request_id }).to_string(),
            ),
            PollResult::Timeout(mut pending) => {
                let _ = pending.request.cancel();
                to_c_ptr(
                    json!({ "ok": true, "status": "timeout", "requestId": request_id }).to_string(),
                )
            }
            PollResult::Failed(error) => err_json("SemanticTokensFailed", json!(error)),
            PollResult::Complete(pending, response) => {
                let (version, tokens) = {
                    let reg = registry_lock();
                    let Some(version) = reg.version_of(pending.document_id) else {
                        return to_c_ptr(
                            json!({ "ok": true, "status": "stale", "requestId": request_id })
                                .to_string(),
                        );
                    };
                    if version != pending.document_version {
                        return to_c_ptr(
                            json!({ "ok": true, "status": "stale", "requestId": request_id })
                                .to_string(),
                        );
                    }
                    let token_count = response
                        .get("data")
                        .and_then(serde_json::Value::as_array)
                        .map(|data| data.len() / 5);
                    if token_count.is_some_and(|count| count > MAX_SEMANTIC_TOKENS_PER_DOCUMENT) {
                        return err_json(
                            "SemanticTokensTooLarge",
                            json!({
                                "count": token_count,
                                "limit": MAX_SEMANTIC_TOKENS_PER_DOCUMENT,
                            }),
                        );
                    }
                    let decoded = match decode_semantic_tokens(&response, &pending.legend) {
                        Ok(decoded) => decoded,
                        Err(error) => return err_json("InvalidSemanticTokens", json!(error)),
                    };
                    if decoded.len() > MAX_SEMANTIC_TOKENS_PER_DOCUMENT {
                        return err_json(
                            "SemanticTokensTooLarge",
                            json!({
                                "count": decoded.len(),
                                "limit": MAX_SEMANTIC_TOKENS_PER_DOCUMENT,
                            }),
                        );
                    }
                    let absolute = match semantic_token_ranges(&decoded, version, |line| {
                        reg.line_offset_utf16(pending.document_id, line)
                    }) {
                        Ok(tokens) => tokens,
                        Err(error) if error.contains("version changed") => {
                            return to_c_ptr(
                                json!({ "ok": true, "status": "stale", "requestId": request_id })
                                    .to_string(),
                            );
                        }
                        Err(error) => return err_json("InvalidSemanticTokens", json!(error)),
                    };
                    (version, absolute)
                };
                to_c_ptr(
                    json!({
                        "ok": true,
                        "status": "completed",
                        "requestId": request_id,
                        "version": version,
                        "tokens": tokens,
                    })
                    .to_string(),
                )
            }
        }
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_semantic_tokens_poll")))
}

/// Cancel a pending semantic-token request.
#[no_mangle]
pub extern "C" fn alula_semantic_tokens_cancel(request_id: u64) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        if let Some(mut pending) = pending_semantic_tokens_lock().remove(&request_id) {
            let _ = pending.request.cancel();
        }
        to_c_ptr(json!({ "ok": true, "requestId": request_id }).to_string())
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_semantic_tokens_cancel")))
}

/// 发起非阻塞补全请求。offset 为文档 UTF-16 口径。
/// 成功返回 request_id 与服务端文档版本；最多允许 32 个待处理请求。
#[no_mangle]
pub extern "C" fn alula_completion_start(
    id: u64,
    offset_utf16: u64,
    timeout_ms: u64,
) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        let position = {
            let reg = registry_lock();
            let Some((line, character)) = reg.line_col(id, offset_utf16 as usize) else {
                return err_json("UnknownDoc", json!({ "id": id }));
            };
            let Some(uri) = reg.uri_of(id) else {
                return err_json("UnknownDoc", json!("doc 未设置 uri"));
            };
            let Some(server) = reg.lsp_of(id) else {
                return err_json("NoLsp", json!({ "id": id }));
            };
            let Some(version) = reg.version_of(id) else {
                return err_json("UnknownDoc", json!({ "id": id }));
            };
            (uri, server, line, character, version)
        };
        let (uri, server, line, character, version) = position;
        let mut pending = pending_completions_lock();
        if pending.len() >= MAX_PENDING_COMPLETIONS {
            return err_json("Backpressure", json!({ "limit": MAX_PENDING_COMPLETIONS }));
        }
        let request = match server.completion_async(&uri, line, character) {
            Ok(request) => request,
            Err(error) => return err_json("CompletionFailed", json!(error)),
        };
        let request_id = NEXT_COMPLETION_ID.fetch_add(1, Ordering::Relaxed);
        let now = Instant::now();
        let deadline = now
            .checked_add(Duration::from_millis(timeout_ms))
            .unwrap_or_else(|| now + Duration::from_secs(86_400));
        pending.insert(
            request_id,
            PendingCompletion {
                document_id: id,
                document_version: version,
                server,
                request,
                deadline,
            },
        );
        to_c_ptr(json!({ "ok": true, "requestId": request_id, "version": version }).to_string())
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_completion_start")))
}

/// 立即查询请求；状态为 pending/completed/stale/timeout/cancelled。
#[no_mangle]
pub extern "C" fn alula_completion_poll(request_id: u64) -> *mut c_char {
    enum PollResult {
        Pending,
        Timeout(PendingCompletion),
        Complete(PendingCompletion, serde_json::Value),
        Failed(PendingCompletion, String),
    }

    catch_unwind(AssertUnwindSafe(|| {
        let result = {
            let mut requests = pending_completions_lock();
            let Some(mut pending) = requests.remove(&request_id) else {
                return to_c_ptr(
                    json!({ "ok": true, "status": "cancelled", "requestId": request_id })
                        .to_string(),
                );
            };
            if Instant::now() >= pending.deadline {
                PollResult::Timeout(pending)
            } else {
                match pending.request.try_recv() {
                    Ok(Some(response)) => PollResult::Complete(pending, response),
                    Ok(None) => {
                        requests.insert(request_id, pending);
                        PollResult::Pending
                    }
                    Err(error) => PollResult::Failed(pending, error),
                }
            }
        };

        match result {
            PollResult::Pending => to_c_ptr(
                json!({ "ok": true, "status": "pending", "requestId": request_id }).to_string(),
            ),
            PollResult::Timeout(mut pending) => {
                let _ = pending.request.cancel();
                to_c_ptr(
                    json!({ "ok": true, "status": "timeout", "requestId": request_id }).to_string(),
                )
            }
            PollResult::Complete(pending, response) => {
                let current_version = registry_lock().version_of(pending.document_id);
                if current_version != Some(pending.document_version) {
                    return to_c_ptr(
                        json!({ "ok": true, "status": "stale", "requestId": request_id })
                            .to_string(),
                    );
                }
                to_c_ptr(
                    json!({
                        "ok": true,
                        "status": "completed",
                        "requestId": request_id,
                        "version": pending.document_version,
                        "items": extract_completion_labels(&response),
                    })
                    .to_string(),
                )
            }
            PollResult::Failed(mut pending, error) => {
                let _ = pending.request.cancel();
                err_json("CompletionFailed", json!(error))
            }
        }
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_completion_poll")))
}

/// 显式取消请求；重复取消是安全的。
#[no_mangle]
pub extern "C" fn alula_completion_cancel(request_id: u64) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        if let Some(mut pending) = pending_completions_lock().remove(&request_id) {
            let _ = pending.request.cancel();
        }
        to_c_ptr(json!({ "ok": true, "status": "cancelled", "requestId": request_id }).to_string())
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_completion_cancel")))
}

/// Start a bounded, cancellable LSP definition request. `offset_utf16` is an
/// absolute document offset in UTF-16 code units.
#[no_mangle]
pub extern "C" fn alula_definition_start(
    id: u64,
    offset_utf16: u64,
    timeout_ms: u64,
) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        let (uri, server, line, character, version) = {
            let reg = registry_lock();
            let Ok(offset_utf16) = usize::try_from(offset_utf16) else {
                return err_json("InvalidArgument", json!("offset is not representable"));
            };
            let Some(uri) = reg.uri_of(id) else {
                return err_json("UnknownDoc", json!("doc 未设置 uri"));
            };
            let Some(server) = reg.lsp_of(id) else {
                return err_json("NoLsp", json!({ "id": id }));
            };
            let Some(version) = reg.version_of(id) else {
                return err_json("UnknownDoc", json!({ "id": id }));
            };
            let Some((line, character)) = reg.line_col(id, offset_utf16) else {
                return err_json(
                    "InvalidUtf16Offset",
                    json!({ "id": id, "offsetUtf16": offset_utf16 }),
                );
            };
            (uri, server, line, character, version)
        };

        cancel_definitions_for_doc(id);
        let request = match server.definition_async(&uri, line, character) {
            Ok(request) => request,
            Err(error) => return err_json("DefinitionFailed", json!(error)),
        };
        let mut pending = pending_definitions_lock();
        if pending.len() >= MAX_PENDING_DEFINITIONS {
            drop(pending);
            let mut request = request;
            let _ = request.cancel();
            return err_json("Backpressure", json!({ "limit": MAX_PENDING_DEFINITIONS }));
        }
        let request_id = NEXT_DEFINITION_ID.fetch_add(1, Ordering::Relaxed);
        let now = Instant::now();
        let deadline = now
            .checked_add(Duration::from_millis(timeout_ms))
            .unwrap_or_else(|| now + Duration::from_secs(86_400));
        pending.insert(
            request_id,
            PendingDefinition {
                document_id: id,
                document_version: version,
                server,
                request,
                deadline,
            },
        );
        to_c_ptr(json!({ "ok": true, "requestId": request_id, "version": version }).to_string())
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_definition_start")))
}

/// Poll a definition request. A response is returned only while the source
/// document remains at the version captured by `alula_definition_start`.
#[no_mangle]
pub extern "C" fn alula_definition_poll(request_id: u64) -> *mut c_char {
    enum PollResult {
        Pending,
        Timeout(PendingDefinition),
        Complete(PendingDefinition, serde_json::Value),
        Failed(PendingDefinition, String),
    }

    catch_unwind(AssertUnwindSafe(|| {
        let result = {
            let mut requests = pending_definitions_lock();
            let Some(mut pending) = requests.remove(&request_id) else {
                return to_c_ptr(
                    json!({ "ok": true, "status": "cancelled", "requestId": request_id })
                        .to_string(),
                );
            };
            if Instant::now() >= pending.deadline {
                PollResult::Timeout(pending)
            } else {
                match pending.request.try_recv() {
                    Ok(Some(response)) => PollResult::Complete(pending, response),
                    Ok(None) => {
                        requests.insert(request_id, pending);
                        PollResult::Pending
                    }
                    Err(error) => PollResult::Failed(pending, error),
                }
            }
        };

        match result {
            PollResult::Pending => to_c_ptr(
                json!({ "ok": true, "status": "pending", "requestId": request_id }).to_string(),
            ),
            PollResult::Timeout(mut pending) => {
                let _ = pending.request.cancel();
                to_c_ptr(
                    json!({ "ok": true, "status": "timeout", "requestId": request_id }).to_string(),
                )
            }
            PollResult::Complete(pending, response) => {
                if registry_lock().version_of(pending.document_id) != Some(pending.document_version) {
                    return to_c_ptr(
                        json!({ "ok": true, "status": "stale", "requestId": request_id })
                            .to_string(),
                    );
                }
                let definition = extract_definition_location(&response);
                let definition_json = definition.map_or(serde_json::Value::Null, |location: DefinitionLocation| {
                    json!({ "uri": location.uri, "line": location.line, "character": location.character })
                });
                to_c_ptr(
                    json!({
                        "ok": true,
                        "status": "completed",
                        "requestId": request_id,
                        "version": pending.document_version,
                        "definition": definition_json,
                    })
                    .to_string(),
                )
            }
            PollResult::Failed(mut pending, error) => {
                let _ = pending.request.cancel();
                err_json("DefinitionFailed", json!(error))
            }
        }
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_definition_poll")))
}

/// Cancel a pending definition request. Repeated cancellation is safe.
#[no_mangle]
pub extern "C" fn alula_definition_cancel(request_id: u64) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        if let Some(mut pending) = pending_definitions_lock().remove(&request_id) {
            let _ = pending.request.cancel();
        }
        to_c_ptr(json!({ "ok": true, "requestId": request_id }).to_string())
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_definition_cancel")))
}

/// 同步兼容补全请求（阻塞至响应或超时）。offset 为文档 UTF-16 口径。
#[no_mangle]
pub extern "C" fn alula_completion(id: u64, offset_utf16: u64, timeout_ms: u64) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        let position = {
            let reg = registry_lock();
            let Some((line, character)) = reg.line_col(id, offset_utf16 as usize) else {
                return err_json("UnknownDoc", json!({ "id": id }));
            };
            let Some(uri) = reg.uri_of(id) else {
                return err_json("UnknownDoc", json!("doc 未设置 uri"));
            };
            let Some(server) = reg.lsp_of(id) else {
                return err_json("NoLsp", json!({ "id": id }));
            };
            (uri, server, line, character)
        };
        let (uri, server, line, character) = position;
        match server.completion(&uri, line, character, timeout_ms) {
            Ok(items) => to_c_ptr(json!({ "ok": true, "items": items }).to_string()),
            Err(e) => err_json("CompletionFailed", json!(e)),
        }
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_completion")))
}

// ---------- 导出函数：Tree-sitter 语法 ----------

/// 当前文档的语法高亮 token（UTF-16 区间 + 捕获类别）。
#[no_mangle]
pub extern "C" fn alula_symbols(id: u64) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| match crate::doc_symbols(id) {
        Some((version, symbols)) => {
            to_c_ptr(json!({ "ok": true, "version": version, "symbols": symbols }).to_string())
        }
        None => err_json("UnknownDoc", json!({ "id": id })),
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_symbols")))
}

#[no_mangle]
pub extern "C" fn alula_syntax(id: u64) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| match crate::syntax_tokens(id) {
        Some((version, tokens)) => {
            to_c_ptr(json!({ "ok": true, "version": version, "tokens": tokens }).to_string())
        }
        None => err_json("UnknownDoc", json!({ "id": id })),
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_syntax")))
}

// ---------- 导出函数：工作区文件系统 / 原子保存 ----------

/// 枚举目录。
///
/// # Safety
/// `path` 必须是合法的 NUL 结尾 UTF-8。
#[no_mangle]
pub unsafe extern "C" fn alula_ws_list_dir(path: *const c_char) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        let path = match read_c_str(path) {
            Ok(s) => s,
            Err(e) => return e,
        };
        match editor_workspace::list_dir(path) {
            Ok(entries) => to_c_ptr(json!({ "ok": true, "entries": entries }).to_string()),
            Err(e) => err_json(e_code(&e), json!(e.to_string())),
        }
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_ws_list_dir")))
}

/// 读取 UTF-8 文本文件。
///
/// # Safety
/// `path` 必须是合法的 NUL 结尾 UTF-8。
#[no_mangle]
pub unsafe extern "C" fn alula_ws_read_file(path: *const c_char) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        let path = match read_c_str(path) {
            Ok(s) => s,
            Err(e) => return e,
        };
        match editor_workspace::read_file(path) {
            Ok(content) => to_c_ptr(json!({ "ok": true, "content": content }).to_string()),
            Err(e) => err_json(e_code(&e), json!(e.to_string())),
        }
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_ws_read_file")))
}

/// 读取文本文件并返回规范 LF 内容及编码/BOM/EOL 元数据；可选指定重开编码。
///
/// # Safety
/// `path` 必须是合法的 NUL 结尾 UTF-8；`encoding_override` 为 NULL 或合法 UTF-8。
#[no_mangle]
pub unsafe extern "C" fn alula_ws_read_file_document(
    path: *const c_char,
    encoding_override: *const c_char,
) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        let path = match read_c_str(path) {
            Ok(s) => s,
            Err(e) => return e,
        };
        let encoding = if encoding_override.is_null() {
            None
        } else {
            let id = match read_c_str(encoding_override) {
                Ok(s) => s,
                Err(e) => return e,
            };
            let Some(encoding) = TextEncoding::from_id(id) else {
                return err_json("InvalidArgument", json!({ "encoding": id }));
            };
            Some(encoding)
        };
        match editor_workspace::read_file_document(path, encoding) {
            Ok(document) => to_c_ptr(
                json!({
                    "ok": true,
                    "content": document.text,
                    "encoding": document.options.encoding.id(),
                    "bom": document.options.bom,
                    "lineEnding": document.options.line_ending.id(),
                })
                .to_string(),
            ),
            Err(e) => err_json(e_code(&e), json!(e.to_string())),
        }
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_ws_read_file_document")))
}

/// 将文档当前全文原子保存到指定路径（校验 base_version；docs/02 §6.3）。
///
/// # Safety
/// `path` 必须是合法的 NUL 结尾 UTF-8。
#[no_mangle]
pub unsafe extern "C" fn alula_doc_save_file(
    id: u64,
    path: *const c_char,
    base_version: u64,
) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        let path = match read_c_str(path) {
            Ok(s) => s.to_string(),
            Err(e) => return e,
        };
        let (version, text) = {
            let reg = registry_lock();
            match reg.content(id) {
                Some(vt) => vt,
                None => return err_json("UnknownDoc", json!({ "id": id })),
            }
        };
        if version != base_version {
            return err_json("VersionMismatch", json!({ "current": version }));
        }
        match editor_doc::atomic_save(&path, &text) {
            Ok(()) => to_c_ptr(json!({ "ok": true, "version": version, "path": path }).to_string()),
            Err(editor_doc::SaveError::ReadOnlyTarget(path)) => {
                err_json("ReadOnlyFile", json!({ "path": path }))
            }
            Err(e) => err_json("SaveFailed", json!(e.to_string())),
        }
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_doc_save_file")))
}

/// 按指定编码/BOM/EOL 原子保存文档当前全文，并校验版本。
///
/// # Safety
/// 所有字符串参数必须是合法的 NUL 结尾 UTF-8。
#[no_mangle]
pub unsafe extern "C" fn alula_doc_save_file_with_options(
    id: u64,
    path: *const c_char,
    base_version: u64,
    encoding: *const c_char,
    bom: u8,
    line_ending: *const c_char,
) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        let path = match read_c_str(path) {
            Ok(s) => s.to_string(),
            Err(e) => return e,
        };
        let encoding_id = match read_c_str(encoding) {
            Ok(s) => s,
            Err(e) => return e,
        };
        let Some(encoding) = TextEncoding::from_id(encoding_id) else {
            return err_json("InvalidArgument", json!({ "encoding": encoding_id }));
        };
        if bom > 1 {
            return err_json("InvalidArgument", json!({ "bom": bom }));
        }
        let line_ending_id = match read_c_str(line_ending) {
            Ok(s) => s,
            Err(e) => return e,
        };
        let Some(line_ending) = LineEnding::from_id(line_ending_id) else {
            return err_json("InvalidArgument", json!({ "lineEnding": line_ending_id }));
        };
        let (version, text) = {
            let reg = registry_lock();
            match reg.content(id) {
                Some(vt) => vt,
                None => return err_json("UnknownDoc", json!({ "id": id })),
            }
        };
        if version != base_version {
            return err_json("VersionMismatch", json!({ "current": version }));
        }
        let options = TextFileOptions {
            encoding,
            bom: bom != 0,
            line_ending,
        };
        match editor_doc::atomic_save_with_options(&path, &text, options) {
            Ok(()) => to_c_ptr(json!({ "ok": true, "version": version, "path": path }).to_string()),
            Err(editor_doc::SaveError::UnrepresentableCharacters(encoding)) => {
                err_json("UnrepresentableCharacter", json!({ "encoding": encoding }))
            }
            Err(editor_doc::SaveError::ReadOnlyTarget(path)) => {
                err_json("ReadOnlyFile", json!({ "path": path }))
            }
            Err(e) => err_json("SaveFailed", json!(e.to_string())),
        }
    }))
    .unwrap_or_else(|_| {
        err_json(
            "Internal",
            json!("panic in alula_doc_save_file_with_options"),
        )
    })
}

/// didSave（触发 flycheck 等）。
#[no_mangle]
pub extern "C" fn alula_lsp_did_save(id: u64) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        let reg = registry_lock();
        let Some(uri) = reg.uri_of(id) else {
            return err_json("UnknownDoc", json!("doc 未设置 uri"));
        };
        let Some(server) = reg.lsp_of(id) else {
            return err_json("NoLsp", json!({ "id": id }));
        };
        match server.did_save(&uri) {
            Ok(()) => to_c_ptr(json!({ "ok": true }).to_string()),
            Err(e) => err_json("SendFailed", json!(e)),
        }
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_lsp_did_save")))
}

fn e_code(e: &editor_workspace::WorkspaceError) -> &'static str {
    use editor_workspace::WorkspaceError as E;
    match e {
        E::NotFound(_) => "NotFound",
        E::NotADirectory(_) => "NotADirectory",
        E::BinaryFile(_) => "BinaryFile",
        E::UnsupportedEncoding(_, _) => "UnsupportedEncoding",
        E::Io(_) => "IoError",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    fn take(ptr: *mut c_char) -> serde_json::Value {
        assert!(!ptr.is_null());
        let s = unsafe { CStr::from_ptr(ptr) }.to_str().unwrap().to_string();
        unsafe { alula_string_free(ptr) };
        serde_json::from_str(&s).unwrap()
    }

    fn c(s: &str) -> CString {
        CString::new(s).unwrap()
    }

    #[test]
    fn abi_version_is_exposed() {
        assert_eq!(alula_abi_version(), ALULA_ABI_VERSION);
    }

    #[test]
    fn semantic_token_ffi_requires_a_registered_lsp_document() {
        assert_eq!(
            take(alula_semantic_tokens_start(91_000, 1_000))["error"]["code"],
            "UnknownDoc"
        );
        assert_eq!(
            take(alula_semantic_tokens_poll(91_000))["status"],
            "cancelled"
        );
        assert_eq!(take(alula_semantic_tokens_cancel(91_000))["ok"], true);
    }

    #[test]
    fn semantic_token_ranges_map_utf16_lines_to_absolute_offsets() {
        let buffer = editor_buffer::TextBuffer::open("🦊x\r\nz");
        let version = buffer.version();
        let tokens = vec![
            SemanticToken {
                line: 0,
                start_character: 2,
                length: 1,
                kind: "variable".into(),
            },
            SemanticToken {
                line: 1,
                start_character: 0,
                length: 1,
                kind: "function".into(),
            },
        ];
        let ranges = semantic_token_ranges(&tokens, version, |line| {
            Some(buffer.line_offset_utf16(line))
        })
        .unwrap();
        assert_eq!(ranges[0]["start_utf16"], 2);
        assert_eq!(ranges[0]["end_utf16"], 3);
        assert_eq!(ranges[1]["start_utf16"], 5);
        assert_eq!(ranges[1]["end_utf16"], 6);
        assert!(semantic_token_ranges(&tokens, version + 1, |line| {
            Some(buffer.line_offset_utf16(line))
        })
        .is_err());
    }

    #[test]
    fn lsp_did_close_without_server_keeps_document_open() {
        let id = 209;
        take(unsafe { alula_doc_open(id, c("still open").as_ptr()) });
        take(unsafe { alula_doc_set_uri(id, c("file:///still-open.txt").as_ptr()) });

        let closed = take(alula_lsp_did_close(id));
        assert_eq!(closed["ok"], true);
        assert_eq!(closed["closed"], false);
        assert_eq!(take(alula_doc_resync(id))["content"], "still open");
    }

    #[test]
    fn open_apply_resync_roundtrip_over_ffi() {
        let id = 201;
        let r = take(unsafe { alula_doc_open(id, c("print('hi')\n").as_ptr()) });
        assert_eq!(r["ok"], true);
        assert_eq!(r["version"], 1);

        let ops = c(r#"[{"type":"insert","offset_utf16":10,"text":"!"}]"#);
        let r = take(unsafe { alula_doc_apply(id, 1, ops.as_ptr()) });
        assert_eq!(r["ok"], true);
        assert_eq!(r["version"], 2);

        let r = take(alula_doc_resync(id));
        assert_eq!(r["ok"], true);
        assert_eq!(r["version"], 2);
        // offset 10 位于 ' 与 ) 之间
        assert_eq!(r["content"], "print('hi'!)\n");
    }

    #[test]
    fn rust_owned_savepoint_roundtrip_over_ffi_keeps_document_version() {
        let id = 92_850;
        let opened = take(unsafe { alula_doc_open(id, c("甲🦊\r\n").as_ptr()) });
        assert_eq!(opened["version"], 1);
        assert_eq!(take(alula_doc_is_dirty(id))["dirty"], false);

        let insert = c(r#"[{"type":"insert","offset_utf16":5,"text":"x"}]"#);
        let changed = take(unsafe { alula_doc_apply(id, 1, insert.as_ptr()) });
        assert_eq!(changed["version"], 2);
        assert_eq!(take(alula_doc_is_dirty(id))["dirty"], true);
        assert_eq!(
            take(unsafe { alula_doc_savepoint_matches(id, c("甲🦊\r\n").as_ptr()) })["matches"],
            true
        );

        let baseline = c("disk 🦊\r\n");
        assert_eq!(
            take(unsafe { alula_doc_set_savepoint(id, baseline.as_ptr()) })["ok"],
            true
        );
        assert_eq!(take(alula_doc_resync(id))["version"], 2);
        assert_eq!(take(alula_doc_is_dirty(id))["dirty"], true);
        assert_eq!(
            take(unsafe { alula_doc_savepoint_matches(id, baseline.as_ptr()) })["matches"],
            true
        );

        assert_eq!(take(alula_doc_mark_saved(id))["ok"], true);
        assert_eq!(take(alula_doc_is_dirty(id))["dirty"], false);
        assert_eq!(take(alula_doc_resync(id))["version"], 2);
        take(alula_doc_close(id));
    }

    #[test]
    fn savepoint_ffi_reports_unknown_document() {
        let id = 92_815;
        assert_eq!(take(alula_doc_is_dirty(id))["error"]["code"], "UnknownDoc");
        assert_eq!(
            take(alula_doc_mark_saved(id))["error"]["code"],
            "UnknownDoc"
        );
        assert_eq!(
            take(unsafe { alula_doc_set_savepoint(id, c("baseline").as_ptr()) })["error"]["code"],
            "UnknownDoc"
        );
        assert_eq!(
            take(unsafe { alula_doc_savepoint_matches(id, c("baseline").as_ptr()) })["error"]
                ["code"],
            "UnknownDoc"
        );
    }

    #[test]
    fn bounded_utf16_range_read_over_ffi_reports_snapshot_and_line_origin() {
        let id = 92_811;
        take(unsafe { alula_doc_open(id, c("\u{FEFF}甲🦊\r\nsecond").as_ptr()) });

        let first = take(alula_doc_read_range(id, 0, 3));
        assert_eq!(first["ok"], true);
        assert_eq!(first["version"], 1);
        assert_eq!(first["totalUtf16Length"], 12);
        assert_eq!(first["lineCount"], 2);
        assert_eq!(first["startUtf16"], 0);
        assert_eq!(first["endUtf16"], 2);
        assert_eq!(first["startLine"], 0);
        assert_eq!(first["startCharacter"], 0);
        assert_eq!(first["text"], "\u{FEFF}甲");

        let emoji = take(alula_doc_read_range(id, 2, 1));
        assert_eq!(emoji["text"], "🦊");
        assert_eq!(emoji["endUtf16"], 4);

        let split_surrogate = take(alula_doc_read_range(id, 3, 1));
        assert_eq!(split_surrogate["ok"], false);
        assert_eq!(split_surrogate["error"]["code"], "InvalidUtf16Offset");

        let oversized = take(alula_doc_read_range(id, 0, 65_537));
        assert_eq!(oversized["ok"], false);
        assert_eq!(oversized["error"]["code"], "ReadRangeTooLarge");

        take(alula_doc_close(id));
    }

    #[test]
    fn line_offset_over_ffi_uses_utf16_and_reports_invalid_line() {
        let id = 92_812;
        take(unsafe { alula_doc_open(id, c("\u{FEFF}a🦊\r\nb\n").as_ptr()) });

        let first = take(alula_doc_line_offset(id, 0));
        assert_eq!(first["offsetUtf16"], 0);
        assert_eq!(first["totalUtf16Length"], 8);
        assert_eq!(first["lineCount"], 3);

        let second = take(alula_doc_line_offset(id, 1));
        assert_eq!(second["offsetUtf16"], 6);
        assert_eq!(second["version"], 1);

        let after_emoji = take(alula_doc_position(id, 4));
        assert_eq!(after_emoji["line"], 0);
        assert_eq!(after_emoji["character"], 4);
        let after_crlf = take(alula_doc_position(id, 6));
        assert_eq!(after_crlf["line"], 1);
        assert_eq!(after_crlf["character"], 0);
        let split_surrogate = take(alula_doc_position(id, 3));
        assert_eq!(split_surrogate["error"]["code"], "InvalidUtf16Offset");

        let third = take(alula_doc_line_offset(id, 2));
        assert_eq!(third["offsetUtf16"], 8);

        let invalid = take(alula_doc_line_offset(id, 3));
        assert_eq!(invalid["ok"], false);
        assert_eq!(invalid["error"]["code"], "InvalidLine");

        take(alula_doc_close(id));
    }

    #[test]
    fn lsp_position_offset_uses_utf16_and_clamps_crlf_and_surrogates() {
        let id = 92_818;
        take(unsafe { alula_doc_open(id, c("\u{FEFF}a🦊\r\nb\n").as_ptr()) });

        let split_pair = take(alula_doc_position_offset(id, 0, 3));
        assert_eq!(split_pair["version"], 1);
        assert_eq!(split_pair["offsetUtf16"], 2);
        assert_eq!(split_pair["character"], 2);

        let end_of_line = take(alula_doc_position_offset(id, 0, 99));
        assert_eq!(end_of_line["offsetUtf16"], 4);
        let second_line = take(alula_doc_position_offset(id, 1, 1));
        assert_eq!(second_line["offsetUtf16"], 7);
        let empty_line = take(alula_doc_position_offset(id, 2, 0));
        assert_eq!(empty_line["offsetUtf16"], 8);

        let invalid = take(alula_doc_position_offset(id, 3, 0));
        assert_eq!(invalid["ok"], false);
        assert_eq!(invalid["error"]["code"], "InvalidLine");
        take(alula_doc_close(id));
    }

    #[test]
    fn bounded_line_windows_over_ffi_share_a_rust_snapshot() {
        let id = 92_813;
        take(unsafe { alula_doc_open(id, c("\u{FEFF}a🦊\r\nsecond\n").as_ptr()) });

        let page = take(alula_doc_read_lines(id, 0, 3, 0, 8, 24));
        assert_eq!(page["ok"], true);
        assert_eq!(page["version"], 1);
        assert_eq!(page["totalUtf16Length"], 13);
        assert_eq!(page["lineCount"], 3);
        assert_eq!(page["firstLine"], 0);
        assert_eq!(page["lines"][0]["text"], "\u{FEFF}a🦊");
        assert_eq!(page["lines"][0]["startUtf16"], 0);
        assert_eq!(page["lines"][0]["endUtf16"], 4);
        assert_eq!(page["lines"][1]["text"], "second");
        assert_eq!(page["lines"][1]["startUtf16"], 6);
        assert_eq!(page["lines"][1]["endUtf16"], 12);
        assert_eq!(page["lines"][2]["text"], "");

        let long_line_id = id + 1;
        take(unsafe {
            alula_doc_open(
                long_line_id,
                c(&format!("{}🦊tail", "x".repeat(90_000))).as_ptr(),
            )
        });
        let horizontal = take(alula_doc_read_lines(
            long_line_id,
            0,
            1,
            90_000,
            2_048,
            2_048,
        ));
        assert_eq!(horizontal["lines"][0]["text"], "🦊tail");
        assert_eq!(horizontal["lines"][0]["startUtf16"], 90_000);

        let invalid_window = take(alula_doc_read_lines(id, 0, 2, 0, 8, 15));
        assert_eq!(invalid_window["ok"], false);
        assert_eq!(invalid_window["error"]["code"], "InvalidLineWindow");
        let invalid_count = take(alula_doc_read_lines(id, 0, 257, 0, 2, 514));
        assert_eq!(invalid_count["ok"], false);
        assert_eq!(invalid_count["error"]["code"], "ReadLineCountTooLarge");

        take(alula_doc_close(id));
        take(alula_doc_close(long_line_id));
    }

    #[test]
    fn minimap_sample_over_ffi_is_versioned_and_bounded() {
        let id = 92_840;
        let content = (0..1_000)
            .map(|line| format!("line-{line}-{}", "x".repeat(100)))
            .collect::<Vec<_>>()
            .join("\n");
        take(unsafe { alula_doc_open(id, c(&content).as_ptr()) });

        let sample = take(alula_doc_minimap_sample(id));
        assert_eq!(sample["ok"], true);
        assert_eq!(sample["version"], 1);
        assert_eq!(sample["lineCount"], 1_000);
        assert_eq!(sample["lines"].as_array().unwrap().len(), 512);
        assert_eq!(sample["lines"][0]["line"], 0);
        assert_eq!(sample["lines"][511]["line"], 999);
        assert_eq!(sample["lines"][0]["startUtf16"], 0);
        assert_eq!(
            sample["lines"][511]["startUtf16"],
            content[..content.rfind('\n').unwrap() + 1]
                .encode_utf16()
                .count()
        );
        assert!(sample["lines"]
            .as_array()
            .unwrap()
            .iter()
            .all(|line| { line["text"].as_str().unwrap().encode_utf16().count() <= 48 }));

        let unknown = take(alula_doc_minimap_sample(id + 1));
        assert_eq!(unknown["error"]["code"], "UnknownDoc");
        take(alula_doc_close(id));
    }

    #[test]
    fn version_mismatch_over_ffi() {
        let id = 202;
        take(unsafe { alula_doc_open(id, c("x").as_ptr()) });
        let ops = c("[]");
        let r = take(unsafe { alula_doc_apply(id, 42, ops.as_ptr()) });
        assert_eq!(r["ok"], false);
        assert_eq!(r["error"]["code"], "VersionMismatch");
        assert_eq!(r["error"]["detail"]["current"], 1);
    }

    #[test]
    fn workspace_edit_transaction_over_ffi_is_atomic() {
        let first = 92_001;
        let second = 92_002;
        take(unsafe { alula_doc_open(first, c("alpha").as_ptr()) });
        take(unsafe { alula_doc_open(second, c("beta").as_ptr()) });

        let success = c(r#"[
                {"id":92001,"base_version":1,"ops":[{"type":"insert","offset_utf16":5,"text":"!"}]},
                {"id":92002,"base_version":1,"ops":[{"type":"insert","offset_utf16":0,"text":"new "}]}
            ]"#);
        let result = take(unsafe { alula_workspace_edit_transaction(success.as_ptr()) });
        assert_eq!(result["ok"], true);
        assert_eq!(
            result["versions"],
            json!([
                {"id": first, "version": 2},
                {"id": second, "version": 2},
            ])
        );
        assert_eq!(take(alula_doc_resync(first))["content"], "alpha!");
        assert_eq!(take(alula_doc_resync(second))["content"], "new beta");

        let stale = c(r#"[
                {"id":92001,"base_version":2,"ops":[{"type":"insert","offset_utf16":0,"text":"changed "}]},
                {"id":92002,"base_version":1,"ops":[{"type":"insert","offset_utf16":0,"text":"changed "}]}
            ]"#);
        let result = take(unsafe { alula_workspace_edit_transaction(stale.as_ptr()) });
        assert_eq!(result["ok"], false);
        assert_eq!(result["error"]["code"], "VersionMismatch");
        assert_eq!(take(alula_doc_resync(first))["content"], "alpha!");
        assert_eq!(take(alula_doc_resync(second))["content"], "new beta");

        take(alula_doc_close(first));
        take(alula_doc_close(second));
    }

    #[test]
    fn syntax_tokens_over_ffi() {
        let id = 203;
        take(unsafe { alula_doc_open(id, c("fn main() {}\n").as_ptr()) });
        take(unsafe { alula_doc_set_uri(id, c("file:///m.rs").as_ptr()) });
        let r = take(alula_syntax(id));
        assert_eq!(r["ok"], true);
        assert!(
            !r["tokens"].as_array().unwrap().is_empty(),
            "应提取到 token"
        );
    }

    #[test]
    fn lsp_gated_ffi_returns_no_lsp_without_start() {
        let id = 204;
        take(unsafe { alula_doc_open(id, c("fn x() {}\n").as_ptr()) });
        take(unsafe { alula_doc_set_uri(id, c("file:///n.rs").as_ptr()) });
        let r = take(alula_diagnostics(id));
        assert_eq!(r["error"]["code"], "NoLsp");
        let r = take(alula_completion(id, 0, 1000));
        assert_eq!(r["error"]["code"], "NoLsp");
    }

    #[test]
    fn null_pointer_yields_invalid_argument() {
        let r = take(unsafe { alula_doc_open(205, std::ptr::null()) });
        assert_eq!(r["ok"], false);
        assert_eq!(r["error"]["code"], "InvalidArgument");
    }

    #[test]
    fn close_and_resync_unknown_doc() {
        let r = take(alula_doc_close(206));
        assert_eq!(r["ok"], true);
        assert_eq!(r["removed"], false);

        let r = take(alula_doc_resync(206));
        assert_eq!(r["ok"], false);
        assert_eq!(r["error"]["code"], "UnknownDoc");
    }
}
