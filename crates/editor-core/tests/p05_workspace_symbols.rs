use alula_core::ffi;
use serde_json::{json, Value};
use std::ffi::{CStr, CString};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

unsafe fn take(ptr: *mut std::ffi::c_char) -> Value {
    let text = CStr::from_ptr(ptr).to_string_lossy().into_owned();
    ffi::alula_string_free(ptr);
    serde_json::from_str(&text).unwrap()
}

#[test]
fn workspace_symbols_are_async_bounded_versioned_and_cancel_on_shutdown() {
    assert_eq!(ffi::alula_abi_version(), 41);
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root = std::env::temp_dir().join(format!("alula-workspace-symbols-{suffix}"));
    std::fs::create_dir_all(&root).unwrap();
    let trace = root.join("trace.log");
    let workspace = CString::new(root.to_string_lossy().as_bytes()).unwrap();
    let command = CString::new(
        json!([
            env!("CARGO_BIN_EXE_async_completion_fake_lsp"),
            trace.to_string_lossy(),
            "100"
        ])
        .to_string(),
    )
    .unwrap();
    let id = 765400;
    unsafe {
        let content = CString::new("😀\r\nhello").unwrap();
        assert_eq!(take(ffi::alula_doc_open(id, content.as_ptr()))["ok"], true);
        assert_eq!(
            take(ffi::alula_lsp_start(
                id,
                workspace.as_ptr(),
                command.as_ptr()
            ))["attached"],
            true
        );
        let query = CString::new("workspace").unwrap();
        let start = take(ffi::alula_workspace_symbols_start(id, query.as_ptr(), 2000));
        assert_eq!(start["supported"], true);
        let request_id = start["requestId"].as_u64().unwrap();
        let deadline = Instant::now() + Duration::from_secs(3);
        let result = loop {
            let result = take(ffi::alula_workspace_symbols_poll(request_id));
            if result["status"] != "pending" {
                break result;
            }
            assert!(Instant::now() < deadline);
            std::thread::sleep(Duration::from_millis(5));
        };
        assert_eq!(result["status"], "completed");
        assert_eq!(result["symbols"][0]["name"], "😀workspace_target");
        assert_eq!(result["symbols"][0]["character"], 3);
        assert_eq!(result["symbols"][0]["endCharacter"], 9);
        let slow = CString::new("slow").unwrap();
        let before = Instant::now();
        let pending = take(ffi::alula_workspace_symbols_start(id, slow.as_ptr(), 2000));
        assert!(before.elapsed() < Duration::from_millis(500));
        let pending_id = pending["requestId"].as_u64().unwrap();
        assert_eq!(
            take(ffi::alula_workspace_symbols_cancel(pending_id))["ok"],
            true
        );
        assert_eq!(
            take(ffi::alula_workspace_symbols_poll(pending_id))["status"],
            "cancelled"
        );
        let pending = take(ffi::alula_workspace_symbols_start(id, slow.as_ptr(), 2000));
        let pending_id = pending["requestId"].as_u64().unwrap();
        let ops = CString::new(json!([{"type":"insert","offset_utf16":0,"text":"x"}]).to_string())
            .unwrap();
        assert_eq!(take(ffi::alula_doc_apply(id, 1, ops.as_ptr()))["ok"], true);
        assert_eq!(
            take(ffi::alula_workspace_symbols_poll(pending_id))["status"],
            "stale"
        );
        let pending = take(ffi::alula_workspace_symbols_start(id, slow.as_ptr(), 2000));
        let pending_id = pending["requestId"].as_u64().unwrap();
        assert_eq!(
            take(ffi::alula_lsp_shutdown_workspace(workspace.as_ptr()))["ok"],
            true
        );
        assert_eq!(
            take(ffi::alula_workspace_symbols_poll(pending_id))["status"],
            "cancelled"
        );
        assert_eq!(take(ffi::alula_doc_close(id))["removed"], true);
    }
    let log = std::fs::read_to_string(&trace).unwrap();
    assert!(log.contains("workspace/symbol"));
    assert!(log.contains("$/cancelRequest"));
    std::fs::remove_dir_all(root).unwrap();
}
