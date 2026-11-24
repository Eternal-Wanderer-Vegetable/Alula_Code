//! Versioned hierarchy requests across the C ABI and LSP wire.

use alula_core::ffi;
use serde_json::{json, Value};
use std::{
    ffi::{c_char, CStr, CString},
    path::Path,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

fn take(ptr: *mut c_char) -> Value {
    unsafe {
        assert!(!ptr.is_null());
        let result = serde_json::from_slice(CStr::from_ptr(ptr).to_bytes());
        ffi::alula_string_free(ptr);
        result.expect("FFI JSON")
    }
}

fn attach(id: u64, root: &CString, trace: &Path, capability: &str) {
    let command = CString::new(
        json!([
            env!("CARGO_BIN_EXE_async_completion_fake_lsp"),
            trace.to_string_lossy(),
            "90",
            capability
        ])
        .to_string(),
    )
    .unwrap();
    assert_eq!(
        take(unsafe { ffi::alula_lsp_start(id, root.as_ptr(), command.as_ptr()) })["attached"],
        true
    );
    let rust = CString::new("rust").unwrap();
    assert_eq!(
        take(unsafe { ffi::alula_lsp_did_open(id, rust.as_ptr()) })["ok"],
        true
    );
}

fn request_id(opened: Value) -> u64 {
    assert_eq!(opened["supported"], true, "{opened}");
    opened["requestId"].as_u64().expect("request ID")
}

fn finish(request: u64) -> Value {
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        let reply = take(ffi::alula_hierarchy_poll(request));
        if reply["status"] != "pending" {
            return reply;
        }
        assert!(Instant::now() < deadline, "{reply}");
        std::thread::sleep(Duration::from_millis(10));
    }
}

fn expand(doc: u64, version: u64, direction: u8, item: &Value) -> Value {
    let item = CString::new(item.to_string()).unwrap();
    take(unsafe { ffi::alula_hierarchy_expand_start(doc, version, direction, item.as_ptr(), 3000) })
}

#[test]
fn hierarchy_routes_and_cancels_versioned_provider_operations() {
    assert_eq!(ffi::alula_abi_version(), 45);
    let suff = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let folder = std::env::temp_dir().join(format!("alula-p05-hierarchy-{suff}"));
    std::fs::create_dir_all(&folder).unwrap();
    let root = CString::new(folder.to_string_lossy().as_bytes()).unwrap();
    let trace = folder.join("hierarchy.log");
    let doc = 55166;
    let text = CString::new("\u{FEFF}// note\r\n🦊target\r\n").unwrap();
    let uri = CString::new("file:///E:/workspace/main.rs").unwrap();
    let unsupported = json!({"ok":true,"supported":false});
    assert_eq!(
        take(unsafe { ffi::alula_doc_open(doc, text.as_ptr()) })["version"],
        1
    );
    let offset = 12;
    let prepare = |offset, kind, timeout| {
        take(ffi::alula_hierarchy_prepare_start(
            doc, offset, kind, timeout,
        ))
    };
    assert_eq!(prepare(offset, 1, 3000), unsupported);
    assert_eq!(prepare(offset, 3, 3000)["error"]["code"], "InvalidArgument");
    assert_eq!(
        take(unsafe { ffi::alula_doc_set_uri(doc, uri.as_ptr()) })["known"],
        true
    );
    attach(doc, &root, &trace, "hierarchy");
    assert_eq!(
        prepare(offset - 1, 1, 3000)["error"]["code"],
        "InvalidUtf16Offset"
    );
    let call = request_id(prepare(offset, 1, 3000));
    let ty = request_id(prepare(offset, 2, 3000));
    let (call, ty) = (finish(call), finish(ty));
    assert_eq!(call["status"], "completed", "{call}");
    assert_eq!(ty["status"], "completed", "{ty}");
    assert_eq!(call["version"], 1);
    let call_item = &call["entries"][0]["item"];
    let type_item = &ty["entries"][0]["item"];
    assert_eq!(call_item["name"], "root");
    assert_eq!(type_item["name"], "Root");
    assert_eq!(call_item["uri"], "file:///E:/workspace/main.rs");
    assert_eq!(call_item["providerTag"], json!([true, null, "root"]));
    assert_eq!(call_item["data"]["id"], json!(["root", "🦊", 7]));

    let cases = [
        (1, call_item, "caller", vec![15, 30]),
        (2, call_item, "leaf", vec![12]),
        (3, type_item, "Base", vec![]),
        (4, type_item, "Derived", vec![]),
    ];
    let requests: Vec<_> = cases
        .iter()
        .map(|(direction, item, _, _)| request_id(expand(doc, 1, *direction, item)))
        .collect();
    for (request, (_, _, name, columns)) in requests.into_iter().zip(cases) {
        let result = finish(request);
        assert_eq!(result["status"], "completed", "{result}");
        let entry = &result["entries"][0];
        assert_eq!(entry["item"]["name"], name);
        let actual = entry["fromRanges"]
            .as_array()
            .unwrap()
            .iter()
            .map(|range| range["start"]["character"].as_u64().unwrap())
            .collect::<Vec<_>>();
        assert_eq!(actual, columns);
    }

    let empty = finish(request_id(prepare(offset - 2, 1, 3000)));
    assert_eq!(empty["status"], "completed");
    assert_eq!(empty["entries"], json!([]));
    assert_eq!(
        finish(request_id(prepare(offset + 2, 1, 3000)))["error"]["code"],
        "HierarchyFailed"
    );
    assert_eq!(
        finish(request_id(prepare(offset + 3, 1, 3000)))["status"],
        "stale"
    );
    assert_eq!(
        finish(request_id(prepare(offset + 4, 1, 3000)))["status"],
        "cancelled"
    );
    assert_eq!(
        expand(doc, 1, 5, call_item)["error"]["code"],
        "InvalidArgument"
    );
    assert_eq!(
        expand(doc, 1, 1, &Value::Null)["error"]["code"],
        "HierarchyFailed"
    );
    assert_eq!(
        expand(doc, 1, 1, &json!({"data":"x".repeat(64*1024)}))["error"]["code"],
        "InvalidArgument"
    );

    let pending: Vec<_> = (0..16)
        .map(|_| request_id(prepare(offset, 1, 3000)))
        .collect();
    assert_eq!(prepare(offset, 1, 3000)["error"]["code"], "Backpressure");
    for id in pending {
        assert_eq!(take(ffi::alula_hierarchy_cancel(id))["ok"], true);
        assert_eq!(finish(id)["status"], "cancelled");
    }
    assert_eq!(
        finish(request_id(prepare(offset, 1, 0)))["status"],
        "timeout"
    );

    let change = CString::new(r#"[{"type":"insert","offset_utf16":0,"text":"x"}]"#).unwrap();
    let stale = request_id(prepare(offset, 2, 3000));
    assert_eq!(
        take(unsafe { ffi::alula_doc_apply(doc, 1, change.as_ptr()) })["version"],
        2
    );
    assert_eq!(finish(stale)["status"], "stale");
    assert_eq!(expand(doc, 1, 1, call_item)["status"], "stale");

    let pending = request_id(prepare(offset + 1, 1, 3000));
    assert_eq!(take(ffi::alula_lsp_did_close(doc))["closed"], true);
    assert_eq!(finish(pending)["status"], "cancelled");
    let pending = request_id(expand(doc, 2, 2, call_item));
    assert_eq!(
        take(unsafe { ffi::alula_lsp_shutdown_workspace(root.as_ptr()) })["stopped"],
        true
    );
    assert_eq!(finish(pending)["status"], "cancelled");

    let denied = folder.join("unsupported.log");
    attach(doc, &root, &denied, "no-hierarchy");
    assert_eq!(prepare(offset + 1, 1, 3000), unsupported);
    assert_eq!(prepare(offset + 1, 2, 3000), unsupported);
    assert_eq!(expand(doc, 2, 4, type_item), unsupported);
    assert_eq!(
        take(unsafe { ffi::alula_lsp_shutdown_workspace(root.as_ptr()) })["stopped"],
        true
    );
    assert_eq!(take(ffi::alula_doc_close(doc))["removed"], true);

    let wire = std::fs::read_to_string(trace).unwrap();
    let rejected = std::fs::read_to_string(denied).unwrap();
    let source = json!({
        "textDocument":{"uri":"file:///e:/workspace/main.rs"},
        "position":{"line":1,"character":2}
    });
    for kind in ["Call", "Type"] {
        let prefix = format!("textDocument/prepare{kind}Hierarchy ");
        assert!(
            wire.lines().any(|line| {
                line.strip_prefix(&prefix)
                    .and_then(|json| serde_json::from_str::<Value>(json).ok())
                    .as_ref()
                    == Some(&source)
            }),
            "{wire}"
        );
        assert!(!rejected.contains(&prefix));
    }
    for (method, item) in [
        ("callHierarchy/incomingCalls", call_item),
        ("callHierarchy/outgoingCalls", call_item),
        ("typeHierarchy/supertypes", type_item),
        ("typeHierarchy/subtypes", type_item),
    ] {
        let prefix = format!("{method} ");
        let observed: Vec<_> = wire
            .lines()
            .filter_map(|line| line.strip_prefix(&prefix))
            .map(|params| serde_json::from_str::<Value>(params).unwrap())
            .collect();
        assert!(!observed.is_empty(), "{wire}");
        assert!(observed.iter().all(|params| &params["item"] == item));
        assert!(!rejected.contains(&prefix));
    }
    assert_eq!(
        wire.lines()
            .filter(|line| line.starts_with("callHierarchy/incomingCalls "))
            .count(),
        1,
        "malformed, oversized, and version-stale items must not reach the server"
    );
    assert!(wire.contains("callHierarchy.static") && wire.contains("typeHierarchy.static"));
    assert!(wire.contains("$/cancelRequest") && wire.contains("shutdown"));
    std::fs::remove_dir_all(folder).unwrap();
}
