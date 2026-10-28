//! P00 LSP workspace shutdown lifecycle through the public FFI paths.

use alula_core::{ffi, lsp_start_for_workspace};
use serde_json::Value;
use std::ffi::{CStr, CString};
use std::time::{SystemTime, UNIX_EPOCH};

unsafe fn take_json(ptr: *mut std::ffi::c_char) -> Value {
    let value = CStr::from_ptr(ptr).to_string_lossy().into_owned();
    ffi::alula_string_free(ptr);
    serde_json::from_str(&value).expect("FFI JSON response")
}

#[test]
fn closing_one_document_keeps_shared_server_alive_and_workspace_shutdown_is_graceful() {
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root_path = std::env::temp_dir().join(format!("alula-p00-close-{suffix}"));
    std::fs::create_dir_all(&root_path).expect("create temporary workspace root");
    let root = root_path.to_string_lossy().into_owned();
    let trace_path = root_path.join("lsp-trace.log");
    let command = vec![
        env!("CARGO_BIN_EXE_workspace_lifecycle_fake_lsp").to_string(),
        trace_path.to_string_lossy().into_owned(),
    ];
    let server = lsp_start_for_workspace(&root, &command).expect("spawn lifecycle fake LSP");
    let first_doc_id = 9_871_001;
    let second_doc_id = 9_871_002;

    unsafe {
        let content = CString::new("fn main() {}\n").unwrap();
        let workspace = CString::new(root.clone()).unwrap();
        let command_json = CString::new(serde_json::to_string(&command).unwrap()).unwrap();
        for (doc_id, file_name) in [(first_doc_id, "first.rs"), (second_doc_id, "second.rs")] {
            assert!(
                take_json(ffi::alula_doc_open(doc_id, content.as_ptr()))["ok"]
                    .as_bool()
                    .unwrap()
            );
            assert!(take_json(ffi::alula_lsp_start(
                doc_id,
                workspace.as_ptr(),
                command_json.as_ptr(),
            ))["attached"]
                .as_bool()
                .unwrap());
            let uri = CString::new(format!("file://{}/{}", root, file_name)).unwrap();
            assert!(
                take_json(ffi::alula_doc_set_uri(doc_id, uri.as_ptr()))["known"]
                    .as_bool()
                    .unwrap()
            );
            let language = CString::new("rust").unwrap();
            assert!(
                take_json(ffi::alula_lsp_did_open(doc_id, language.as_ptr()))["ok"]
                    .as_bool()
                    .unwrap()
            );
        }

        assert!(take_json(ffi::alula_doc_close(first_doc_id))["removed"]
            .as_bool()
            .unwrap());
    }

    let alive_after_tab_close = server.is_alive();
    println!(
        "P00.4_FIXTURE={{\"fixture\":\"workspace-lsp-graceful-close\",\"tabCloseKeepsWorkspaceProcessAlive\":{alive_after_tab_close}}}"
    );
    assert!(alive_after_tab_close);

    unsafe {
        let workspace = CString::new(root.clone()).unwrap();
        let shutdown = take_json(ffi::alula_lsp_shutdown_workspace(workspace.as_ptr()));
        assert_eq!(shutdown["ok"], true);
        assert_eq!(shutdown["stopped"], true);
        assert!(take_json(ffi::alula_doc_close(second_doc_id))["removed"]
            .as_bool()
            .unwrap());
    }

    assert!(!server.is_alive());
    let trace = std::fs::read_to_string(&trace_path).expect("read fake LSP trace");
    assert_eq!(
        trace.lines().collect::<Vec<_>>(),
        [
            "textDocument/didOpen",
            "textDocument/didOpen",
            "textDocument/didClose",
            "textDocument/didClose",
            "shutdown",
            "exit",
        ]
    );
    std::fs::remove_dir_all(root_path).expect("remove temporary workspace root");
}
