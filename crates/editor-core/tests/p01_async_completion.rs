//! P01.1 verifies the async completion FFI contract and request bounds.

use alula_core::ffi;
use serde_json::{json, Value};
use std::{
    ffi::{CStr, CString},
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

unsafe fn take_json(ptr: *mut std::ffi::c_char) -> Value {
    let value = CStr::from_ptr(ptr).to_string_lossy().into_owned();
    ffi::alula_string_free(ptr);
    serde_json::from_str(&value).expect("FFI JSON response")
}

#[test]
fn completion_is_async_versioned_cancellable_and_bounded() {
    assert_eq!(ffi::alula_abi_version(), 6);

    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root_path = std::env::temp_dir().join(format!("alula-p01-async-{suffix}"));
    std::fs::create_dir_all(&root_path).expect("create temporary workspace root");
    let root = root_path.to_string_lossy().into_owned();
    let trace_path = root_path.join("lsp-trace.log");
    let command = vec![
        env!("CARGO_BIN_EXE_async_completion_fake_lsp").to_string(),
        trace_path.to_string_lossy().into_owned(),
        "700".to_string(),
    ];
    let command_json = CString::new(serde_json::to_string(&command).unwrap()).unwrap();
    let workspace = CString::new(root.clone()).unwrap();
    let uri = CString::new(format!("file://{root}/main.rs")).unwrap();
    let language = CString::new("rust").unwrap();
    let doc_id = (suffix % 1_000_000_000) as u64 + 7_000_000;

    unsafe {
        let content = CString::new("abc").unwrap();
        assert_eq!(
            take_json(ffi::alula_doc_open(doc_id, content.as_ptr()))["ok"],
            true
        );
        assert_eq!(
            take_json(ffi::alula_lsp_start(
                doc_id,
                workspace.as_ptr(),
                command_json.as_ptr(),
            ))["attached"],
            true
        );
        assert_eq!(
            take_json(ffi::alula_doc_set_uri(doc_id, uri.as_ptr()))["known"],
            true
        );
        assert_eq!(
            take_json(ffi::alula_lsp_did_open(doc_id, language.as_ptr()))["ok"],
            true
        );

        let started = Instant::now();
        let first = take_json(ffi::alula_completion_start(doc_id, 3, 5_000));
        assert_eq!(first["ok"], true);
        assert_eq!(first["version"], 1);
        assert!(started.elapsed() < Duration::from_millis(500));
        let first_id = first["requestId"].as_u64().unwrap();
        assert_eq!(
            take_json(ffi::alula_completion_poll(first_id))["status"],
            "pending"
        );

        let ops = CString::new(json!([{"type":"insert","offset_utf16":3,"text":"x"}]).to_string())
            .unwrap();
        assert_eq!(
            take_json(ffi::alula_doc_apply(doc_id, 1, ops.as_ptr()))["version"],
            2
        );
        assert_eq!(
            take_json(ffi::alula_completion_poll(first_id))["status"],
            "cancelled"
        );

        let second = take_json(ffi::alula_completion_start(doc_id, 4, 5_000));
        assert_eq!(second["version"], 2);
        let second_id = second["requestId"].as_u64().unwrap();
        let deadline = Instant::now() + Duration::from_secs(4);
        let completed = loop {
            let response = take_json(ffi::alula_completion_poll(second_id));
            if response["status"] != "pending" {
                break response;
            }
            assert!(Instant::now() < deadline, "completion timed out in fixture");
            std::thread::sleep(Duration::from_millis(10));
        };
        assert_eq!(completed["status"], "completed");
        assert_eq!(completed["version"], 2);
        assert_eq!(completed["items"], json!(["async_completion"]));

        let mut request_ids = Vec::new();
        for _ in 0..32 {
            let response = take_json(ffi::alula_completion_start(doc_id, 4, 5_000));
            assert_eq!(response["ok"], true);
            request_ids.push(response["requestId"].as_u64().unwrap());
        }
        let overflow = take_json(ffi::alula_completion_start(doc_id, 4, 5_000));
        assert_eq!(overflow["ok"], false);
        assert_eq!(overflow["error"]["code"], "Backpressure");
        for request_id in request_ids {
            assert_eq!(
                take_json(ffi::alula_completion_cancel(request_id))["status"],
                "cancelled"
            );
        }

        let during_shutdown = take_json(ffi::alula_completion_start(doc_id, 4, 5_000));
        let during_shutdown_id = during_shutdown["requestId"].as_u64().unwrap();
        assert_eq!(
            take_json(ffi::alula_lsp_shutdown_workspace(workspace.as_ptr()))["stopped"],
            true
        );
        assert_eq!(
            take_json(ffi::alula_completion_poll(during_shutdown_id))["status"],
            "cancelled"
        );
        assert_eq!(take_json(ffi::alula_doc_close(doc_id))["removed"], true);
    }

    let trace = std::fs::read_to_string(&trace_path).expect("read fake LSP trace");
    assert!(trace.contains("$/cancelRequest"));
    assert!(trace.ends_with("textDocument/didClose\nshutdown\nexit\n"));
    std::fs::remove_dir_all(root_path).expect("remove temporary workspace root");
}
