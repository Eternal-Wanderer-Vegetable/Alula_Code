//! P00.3 REF-07 process-close baseline through the public FFI close path.

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
fn closing_all_workspace_documents_leaves_server_process_alive() {
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root_path = std::env::temp_dir().join(format!("alula-p00-close-{suffix}"));
    std::fs::create_dir_all(&root_path).expect("create temporary workspace root");
    let root = root_path.to_string_lossy().into_owned();
    let command = vec![env!("CARGO_BIN_EXE_workspace_lifecycle_fake_lsp").to_string()];
    let server = lsp_start_for_workspace(&root, &command).expect("spawn lifecycle fake LSP");
    let doc_id = 9_871_001;

    unsafe {
        let content = CString::new("fn main() {}\n").unwrap();
        assert!(
            take_json(ffi::alula_doc_open(doc_id, content.as_ptr()))["ok"]
                .as_bool()
                .unwrap()
        );

        let workspace = CString::new(root.clone()).unwrap();
        let command_json = CString::new(serde_json::to_string(&command).unwrap()).unwrap();
        assert!(take_json(ffi::alula_lsp_start(
            doc_id,
            workspace.as_ptr(),
            command_json.as_ptr(),
        ))["attached"]
            .as_bool()
            .unwrap());

        assert!(take_json(ffi::alula_doc_close(doc_id))["removed"]
            .as_bool()
            .unwrap());
    }

    let alive_after_close = server.is_alive();
    println!(
        "P00.3_FIXTURE={{\"fixture\":\"parity-ref-07-close-process-01\",\"allDocumentsClosed\":true,\"workspaceProcessAlive\":{alive_after_close}}}"
    );
    // Current baseline: the workspace server registry still owns the child process.
    assert!(alive_after_close);
    server.shutdown().expect("cleanup lifecycle fake LSP");
    assert!(!server.is_alive());
    std::fs::remove_dir_all(root_path).expect("remove temporary workspace root");
}
