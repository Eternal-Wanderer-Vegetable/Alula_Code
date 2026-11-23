//! Exercise the References provider across the native ABI and LSP wire.

use alula_core::ffi;
use serde_json::{json, Value};
use std::{
    ffi::{c_char, CStr, CString},
    path::Path,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

fn take_json(ptr: *mut c_char) -> Value {
    unsafe {
        let value = serde_json::from_slice(CStr::from_ptr(ptr).to_bytes());
        ffi::alula_string_free(ptr);
        value.expect("FFI JSON response")
    }
}

fn attach_server(doc_id: u64, root: &CString, trace: &Path, supported: bool) {
    let mut command = vec![
        env!("CARGO_BIN_EXE_async_completion_fake_lsp").to_string(),
        trace.to_string_lossy().into_owned(),
        "120".to_string(),
    ];
    if !supported {
        command.push("no-references".into());
    }
    let command = CString::new(serde_json::to_string(&command).unwrap()).unwrap();
    let response =
        take_json(unsafe { ffi::alula_lsp_start(doc_id, root.as_ptr(), command.as_ptr()) });
    assert_eq!(response["attached"], true, "{response}");
}

fn start(doc_id: u64, offset: u64, include_declaration: u8, timeout: u64) -> u64 {
    let response = take_json(ffi::alula_references_start(
        doc_id,
        offset,
        include_declaration,
        timeout,
    ));
    assert_eq!(response["supported"], true, "{response}");
    response["requestId"].as_u64().unwrap()
}

fn wait(request: u64) -> Value {
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        let response = take_json(ffi::alula_references_poll(request));
        if response["status"] != "pending" {
            return response;
        }
        assert!(Instant::now() < deadline, "reference query did not resolve");
        std::thread::sleep(Duration::from_millis(10));
    }
}

#[test]
fn references_are_versioned_cancellable_and_drained() {
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root = std::env::temp_dir().join(format!("alula-p05-references-{suffix}"));
    std::fs::create_dir_all(&root).unwrap();
    let root_arg = CString::new(root.to_string_lossy().as_bytes()).unwrap();
    let trace = root.join("trace.log");
    let doc_id = 55001;
    let text = CString::new("\u{FEFF}// note\r\n🦊target\r\n").unwrap();
    let uri = CString::new("file:///E:/workspace/main.rs").unwrap();
    let language = CString::new("rust").unwrap();

    assert_eq!(ffi::alula_abi_version(), 43);
    assert_eq!(
        take_json(unsafe { ffi::alula_doc_open(doc_id, text.as_ptr()) })["version"],
        1
    );
    let unavailable = json!({"ok": true, "supported": false});
    assert_eq!(
        take_json(ffi::alula_references_start(doc_id, 10, 1, 5000)),
        unavailable
    );
    assert_eq!(
        take_json(unsafe { ffi::alula_doc_set_uri(doc_id, uri.as_ptr()) })["known"],
        true
    );
    attach_server(doc_id, &root_arg, &trace, true);
    assert_eq!(
        take_json(unsafe { ffi::alula_lsp_did_open(doc_id, language.as_ptr()) })["ok"],
        true
    );

    // This raw buffer counts BOM and CRLF in the absolute offset. The LSP
    // column starts on line 1, where the preceding emoji occupies two units.
    let at_target = 12;
    let references = wait(start(doc_id, at_target, 0, 5000));
    assert_eq!(references["status"], "completed");
    assert_eq!(references["version"], 1);
    assert_eq!(
        references["references"],
        json!([
            {"uri": "file:///workspace/target.rs", "line": 1, "character": 2,
                "endLine": 1, "endCharacter": 8},
            {"uri": "file:///workspace/other.rs", "line": 3, "character": 5,
                "endLine": 3, "endCharacter": 11}
        ])
    );
    let all = wait(start(doc_id, at_target, 1, 5000));
    assert_eq!(all["references"].as_array().unwrap().len(), 3);
    assert_eq!(
        all["references"][2]["uri"],
        "file:///workspace/definition.rs"
    );
    let empty = wait(start(doc_id, 10, 1, 5000));
    assert_eq!(empty["status"], "completed");
    assert_eq!(empty["references"], json!([]));
    let oversized = wait(start(doc_id, 13, 1, 5000));
    assert_eq!(oversized["error"]["code"], "ReferencesFailed");
    let failed = wait(start(doc_id, 14, 1, 5000));
    assert_eq!(failed["error"]["code"], "ReferencesFailed", "{failed}");
    assert_eq!(
        failed["error"]["detail"],
        "fixture references provider failure"
    );
    assert_eq!(
        take_json(ffi::alula_references_start(doc_id, 999, 1, 5000))["error"]["code"],
        "InvalidUtf16Offset"
    );

    assert_eq!(
        take_json(ffi::alula_references_start(doc_id, at_target - 1, 1, 5000))["error"]["code"],
        "InvalidUtf16Offset"
    );

    assert_eq!(wait(start(doc_id, 15, 1, 5000))["status"], "stale");
    assert_eq!(wait(start(doc_id, 16, 1, 5000))["status"], "cancelled");
    assert_eq!(wait(start(doc_id, 17, 1, 5000))["status"], "cancelled");

    let cancelled = start(doc_id, at_target, 1, 5000);
    let next = start(doc_id, at_target, 0, 5000);
    assert_eq!(wait(cancelled)["status"], "cancelled");
    assert_eq!(take_json(ffi::alula_references_cancel(next))["ok"], true);
    assert_eq!(wait(next)["status"], "cancelled");
    assert_eq!(wait(start(doc_id, at_target, 1, 0))["status"], "timeout");

    let stale = start(doc_id, at_target, 1, 5000);
    let change =
        CString::new(json!([{"type":"insert","offset_utf16":0,"text":"x"}]).to_string()).unwrap();
    assert_eq!(
        take_json(unsafe { ffi::alula_doc_apply(doc_id, 1, change.as_ptr()) })["version"],
        2
    );
    assert_eq!(wait(stale)["status"], "stale");
    let current_target = at_target + 1;
    let before_close = start(doc_id, current_target, 1, 5000);
    assert_eq!(take_json(ffi::alula_lsp_did_close(doc_id))["closed"], true);
    assert_eq!(wait(before_close)["status"], "cancelled");
    assert_eq!(
        take_json(unsafe { ffi::alula_lsp_did_open(doc_id, language.as_ptr()) })["ok"],
        true
    );

    let before_shutdown = start(doc_id, current_target, 1, 5000);
    assert_eq!(
        take_json(unsafe { ffi::alula_lsp_shutdown_workspace(root_arg.as_ptr()) })["stopped"],
        true
    );
    assert_eq!(wait(before_shutdown)["status"], "cancelled");

    let no_provider_trace = root.join("no-provider.log");
    attach_server(doc_id, &root_arg, &no_provider_trace, false);
    assert_eq!(
        take_json(ffi::alula_references_start(doc_id, current_target, 1, 5000)),
        unavailable
    );
    assert_eq!(
        take_json(unsafe { ffi::alula_lsp_shutdown_workspace(root_arg.as_ptr()) })["stopped"],
        true
    );
    assert_eq!(take_json(ffi::alula_doc_close(doc_id))["removed"], true);

    let wire = std::fs::read_to_string(trace).unwrap();
    for include in [false, true] {
        let request = json!({
            "context": {"includeDeclaration": include},
            "position": {"line": 1, "character": 2},
            "textDocument": {"uri": "file:///e:/workspace/main.rs"},
        });
        assert!(wire.lines().any(|line| {
            line.strip_prefix("textDocument/references ")
                .and_then(|line| serde_json::from_str::<Value>(line).ok())
                .as_ref()
                == Some(&request)
        }));
    }
    assert!(wire.matches("$/cancelRequest").count() >= 6);
    assert!(wire.ends_with("textDocument/didClose\nshutdown\nexit\n"));
    assert!(!std::fs::read_to_string(no_provider_trace)
        .unwrap()
        .contains("textDocument/references"));
    std::fs::remove_dir_all(&root).unwrap();
}
