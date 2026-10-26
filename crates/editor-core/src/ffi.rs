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
//! `alula_completion` 为阻塞式请求（带超时），UI 需在提示状态后调用。

use std::ffi::{c_char, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::{Mutex, MutexGuard, OnceLock};

use editor_buffer::TextOp;
use serde_json::json;

use crate::{ApplyError, DocRegistry};

/// ABI/协议版本；Dart 侧加载后应校验。
pub const ALULA_ABI_VERSION: u32 = 3;

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
        match registry_lock().apply(id, base_version, &ops) {
            Ok(version) => to_c_ptr(json!({ "ok": true, "version": version }).to_string()),
            Err(ApplyError::VersionMismatch { current }) => {
                err_json("VersionMismatch", json!({ "current": current }))
            }
            Err(ApplyError::UnknownDoc) => err_json("UnknownDoc", json!({ "id": id })),
            Err(ApplyError::Buffer(e)) => err_json("BufferError", json!(e.to_string())),
        }
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_doc_apply")))
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

/// 关闭文档并释放其缓冲区。
#[no_mangle]
pub extern "C" fn alula_doc_close(id: u64) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| {
        // 关闭文档前先断开 LSP（不做 shutdown 握手——文档级断接即可）
        registry_lock().detach_lsp(id);
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
        let server = registry_lock().detach_lsp(id);
        // detach 只移除映射；进程由调用方通过返回值决定是否显式 shutdown。
        // MVP 简化：registry 不再持有 Arc 后，shutdown 在此无引用可用——
        // 因此 lsp_stop 的语义是「解除挂接」，进程随文档关闭/应用退出由 OS 回收。
        to_c_ptr(json!({ "ok": true, "detached": server }).to_string())
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_lsp_stop")))
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

/// 同步补全请求（阻塞至响应或超时）。offset 为文档 UTF-16 口径。
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
            Err(e) => err_json("SaveFailed", json!(e.to_string())),
        }
    }))
    .unwrap_or_else(|_| err_json("Internal", json!("panic in alula_doc_save_file")))
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
