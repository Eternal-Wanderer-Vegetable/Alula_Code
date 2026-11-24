//! Exercise semantic location providers across the versioned ABI and LSP wire.

use alula_core::ffi;
use serde_json::{json, Value};
use std::{
    ffi::{c_char, CStr, CString},
    path::Path,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

fn take(ptr: *mut c_char) -> Value {
    unsafe {
        let result = serde_json::from_slice(CStr::from_ptr(ptr).to_bytes());
        ffi::alula_string_free(ptr);
        result.expect("FFI JSON response")
    }
}

fn attach(id: u64, root: &CString, trace: &Path, supported: bool) {
    let mut command = vec![
        env!("CARGO_BIN_EXE_async_completion_fake_lsp").to_string(),
        trace.to_string_lossy().into_owned(),
        "90".to_string(),
    ];
    if !supported {
        command.push("no-symbol-locations".into());
    }
    let command = CString::new(serde_json::to_string(&command).unwrap()).unwrap();
    let attached = take(unsafe { ffi::alula_lsp_start(id, root.as_ptr(), command.as_ptr()) });
    assert_eq!(attached["attached"], true, "{attached}");
    let language = CString::new("rust").unwrap();
    assert_eq!(
        take(unsafe { ffi::alula_lsp_did_open(id, language.as_ptr()) })["ok"],
        true
    );
}

fn start(id: u64, offset: u64, kind: u8, timeout: u64) -> u64 {
    let opened = take(ffi::alula_symbol_location_start(id, offset, kind, timeout));
    assert_eq!(opened["supported"], true, "{opened}");
    opened["requestId"].as_u64().unwrap()
}

fn finish(request: u64) -> Value {
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        let value = take(ffi::alula_definition_poll(request));
        if value["status"] != "pending" {
            return value;
        }
        assert!(Instant::now() < deadline, "request {request}: {value}");
        std::thread::sleep(Duration::from_millis(10));
    }
}

#[test]
fn symbol_location_queries_use_distinct_versioned_providers() {
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root = std::env::temp_dir().join(format!("alula-p05-locations-{suffix}"));
    std::fs::create_dir_all(&root).unwrap();
    let path = CString::new(root.to_string_lossy().as_bytes()).unwrap();
    let trace = root.join("wire.log");
    let doc = 55101;
    let text = CString::new("\u{FEFF}// note\r\n🦊target\r\n").unwrap();
    let uri = CString::new("file:///E:/workspace/main.rs").unwrap();
    assert_eq!(ffi::alula_abi_version(), ffi::ALULA_ABI_VERSION);
    assert_eq!(
        take(unsafe { ffi::alula_doc_open(doc, text.as_ptr()) })["version"],
        1
    );
    let offset = 12;
    let unsupported = json!({"ok":true,"supported":false});
    assert_eq!(
        take(ffi::alula_symbol_location_start(doc, offset, 1, 3000)),
        unsupported
    );
    assert_eq!(
        take(ffi::alula_symbol_location_start(doc, offset, 4, 3000))["error"]["code"],
        "InvalidArgument"
    );
    assert_eq!(
        take(unsafe { ffi::alula_doc_set_uri(doc, uri.as_ptr()) })["known"],
        true
    );
    attach(doc, &path, &trace, true);
    assert_eq!(
        take(ffi::alula_symbol_location_start(doc, offset - 1, 1, 3000))["error"]["code"],
        "InvalidUtf16Offset"
    );
    let expected = [
        (
            1,
            json!([
                {"uri":"file:///workspace/kind.rs","line":1,"character":7,"endLine":1,"endCharacter":10}
            ]),
        ),
        (
            2,
            json!([
                {"uri":"file:///workspace/imp.rs","line":2,"character":13,"endLine":2,"endCharacter":19},
                {"uri":"file:///workspace/other_imp.rs","line":6,"character":13,"endLine":6,"endCharacter":18}
            ]),
        ),
        (
            3,
            json!([
                {"uri":"file:///workspace/imp.rs","line":1,"character":11,"endLine":1,"endCharacter":17}
            ]),
        ),
    ];
    for (kind, targets) in expected {
        let response = finish(start(doc, offset, kind, 3000));
        assert_eq!(response["status"], "completed", "{response}");
        assert_eq!(response["version"], 1);
        assert_eq!(response["definitions"], targets);
    }
    let empty = finish(start(doc, offset - 2, 3, 3000));
    assert_eq!(empty["status"], "completed");
    assert_eq!(empty["definitions"], json!([]));

    let superseded = start(doc, offset, 1, 3000);
    let cancelled = start(doc, offset, 2, 3000);
    assert_eq!(finish(superseded)["status"], "cancelled");
    assert_eq!(take(ffi::alula_definition_cancel(cancelled))["ok"], true);
    assert_eq!(finish(cancelled)["status"], "cancelled");
    assert_eq!(finish(start(doc, offset, 3, 0))["status"], "timeout");
    let stale = start(doc, offset, 3, 3000);
    let change = CString::new(r#"[{"type":"insert","offset_utf16":0,"text":"x"}]"#).unwrap();
    assert_eq!(
        take(unsafe { ffi::alula_doc_apply(doc, 1, change.as_ptr()) })["version"],
        2
    );
    assert_eq!(finish(stale)["status"], "stale");

    let pending = start(doc, offset + 1, 2, 3000);
    assert_eq!(
        take(unsafe { ffi::alula_lsp_shutdown_workspace(path.as_ptr()) })["stopped"],
        true
    );
    assert_eq!(finish(pending)["status"], "cancelled");

    let no_provider = root.join("unsupported.log");
    attach(doc, &path, &no_provider, false);
    for kind in [1, 2, 3] {
        assert_eq!(
            take(ffi::alula_symbol_location_start(
                doc,
                offset + 1,
                kind,
                3000
            )),
            unsupported
        );
    }
    assert_eq!(
        take(unsafe { ffi::alula_lsp_shutdown_workspace(path.as_ptr()) })["stopped"],
        true
    );
    assert_eq!(take(ffi::alula_doc_close(doc))["removed"], true);

    let wire = std::fs::read_to_string(trace).unwrap();
    let rejected_wire = std::fs::read_to_string(no_provider).unwrap();
    let request = json!({
        "position":{"line":1,"character":2},
        "textDocument":{"uri":"file:///e:/workspace/main.rs"}
    });
    for kind in ["declaration", "implementation", "typeDefinition"] {
        assert!(wire.contains(&format!("{kind}.linkSupport")));
        let prefix = format!("textDocument/{kind} ");
        assert!(wire.lines().any(|line| {
            line.strip_prefix(&prefix)
                .and_then(|data| serde_json::from_str::<Value>(data).ok())
                .as_ref()
                == Some(&request)
        }));
        assert!(!rejected_wire.contains(&prefix));
    }
    assert!(!wire.lines().any(|line| line == "textDocument/definition"));
    assert!(wire.contains("$/cancelRequest"));
    std::fs::remove_dir_all(root).unwrap();
}
