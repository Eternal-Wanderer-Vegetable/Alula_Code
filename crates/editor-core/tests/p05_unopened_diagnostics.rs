use alula_core::ffi;
use serde_json::{json, Value};
use std::ffi::{CStr, CString};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const EARLIER: &str = "file:///e:/fixture/a_unopened.rs";
const OPEN: &str = "file:///E:/fixture/m_open.rs";
const LATER: &str = "file:///e:/fixture/z_unopened.rs";

fn take(ptr: *mut std::ffi::c_char) -> Value {
    let bytes = unsafe { CStr::from_ptr(ptr) }.to_bytes().to_vec();
    unsafe { ffi::alula_string_free(ptr) };
    serde_json::from_slice(&bytes).unwrap()
}

fn query(id: u64, cursor: Option<&str>, forward: bool, open: &[&str]) -> Value {
    let request = CString::new(
        json!({ "cursorUri": cursor, "forward": forward, "openUris": open }).to_string(),
    )
    .unwrap();
    take(unsafe { ffi::alula_lsp_next_unopened_diagnostic(id, request.as_ptr()) })
}

#[test]
fn unopened_diagnostics_are_directional_bounded_and_keep_the_published_range() {
    assert_eq!(ffi::alula_abi_version(), ffi::ALULA_ABI_VERSION);
    let id = 987638;
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let folder = std::env::temp_dir().join(format!("alula-unopened-diagnostics-{stamp}"));
    std::fs::create_dir_all(&folder).unwrap();
    let trace = folder.join("requests.log");
    let workspace = CString::new(folder.to_string_lossy().as_bytes()).unwrap();
    let command = CString::new(
        json!([
            env!("CARGO_BIN_EXE_async_completion_fake_lsp"),
            trace.to_string_lossy(),
            "0",
            "unopened-diagnostics"
        ])
        .to_string(),
    )
    .unwrap();
    let content = CString::new("\u{feff}😀\r\nsource").unwrap();
    let opened_uri = CString::new(OPEN).unwrap();
    let language = CString::new("rust").unwrap();
    assert_eq!(
        take(unsafe { ffi::alula_doc_open(id, content.as_ptr()) })["ok"],
        true
    );
    assert_eq!(
        take(unsafe { ffi::alula_doc_set_uri(id, opened_uri.as_ptr()) })["known"],
        true
    );
    assert_eq!(
        take(unsafe { ffi::alula_lsp_start(id, workspace.as_ptr(), command.as_ptr()) })["attached"],
        true
    );
    assert_eq!(
        take(unsafe { ffi::alula_lsp_did_open(id, language.as_ptr()) })["ok"],
        true
    );

    let deadline = Instant::now() + Duration::from_secs(3);
    let later = loop {
        let result = query(id, Some(OPEN), true, &[OPEN])["candidate"].clone();
        if !result.is_null() && result["uri"] == LATER {
            break result;
        }
        assert!(Instant::now() < deadline, "missing later file diagnostic");
        std::thread::sleep(Duration::from_millis(20));
    };
    assert_eq!(later["wrapped"], false);
    assert_eq!(later["unopenedTotal"], 3);
    assert_eq!(later["unopenedBeforeFile"], 1);
    assert_eq!(later["fileTotal"], 2);
    assert_eq!(later["diagnostic"]["message"], "😀 later marker");
    assert_eq!(later["diagnostic"]["line"], 1);
    assert_eq!(later["diagnostic"]["character"], 3);
    assert_eq!(later["diagnostic"]["endLine"], 1);
    assert_eq!(later["diagnostic"]["endCharacter"], 9);
    assert_eq!(later["diagnostic"]["code"], 30);
    assert!(later["diagnostic"].get("documentVersion").is_none());

    let earlier = &query(id, Some(OPEN), false, &[OPEN])["candidate"];
    assert_eq!(earlier["uri"], EARLIER);
    assert_eq!(earlier["wrapped"], false);
    assert_eq!(earlier["unopenedTotal"], 3);
    assert_eq!(earlier["unopenedBeforeFile"], 0);
    assert_eq!(earlier["fileTotal"], 1);
    assert_eq!(earlier["diagnostic"]["character"], 5);
    let wrapped = &query(id, Some(LATER), true, &[OPEN])["candidate"];
    assert_eq!(wrapped["uri"], EARLIER);
    assert_eq!(wrapped["wrapped"], true);
    let reverse_wrapped = &query(id, Some(EARLIER), false, &[OPEN])["candidate"];
    assert_eq!(reverse_wrapped["uri"], LATER);
    assert_eq!(reverse_wrapped["wrapped"], true);
    assert_eq!(reverse_wrapped["unopenedTotal"], 3);
    assert_eq!(reverse_wrapped["unopenedBeforeFile"], 1);
    assert_eq!(reverse_wrapped["fileTotal"], 2);
    assert_eq!(reverse_wrapped["diagnostic"]["severity"], 2);
    assert_eq!(query(id, None, true, &[OPEN])["candidate"]["uri"], EARLIER);
    let only_earlier = &query(id, Some(OPEN), true, &[OPEN, LATER])["candidate"];
    assert_eq!(only_earlier["uri"], EARLIER);
    assert_eq!(only_earlier["unopenedTotal"], 1);
    assert_eq!(only_earlier["unopenedBeforeFile"], 0);
    assert_eq!(only_earlier["fileTotal"], 1);
    assert!(query(id, None, true, &[EARLIER, OPEN, LATER])["candidate"].is_null());
    assert_eq!(
        take(ffi::alula_doc_resync(id))["content"],
        "\u{feff}😀\r\nsource"
    );

    assert_eq!(
        take(unsafe { ffi::alula_lsp_shutdown_workspace(workspace.as_ptr()) })["stopped"],
        true
    );
    assert_eq!(
        query(id, Some(OPEN), true, &[OPEN])["error"]["code"],
        "NoLsp"
    );
    assert_eq!(take(ffi::alula_doc_close(id))["removed"], true);
    let requests = std::fs::read_to_string(trace).unwrap();
    assert_eq!(
        requests
            .lines()
            .filter(|line| *line == "textDocument/didOpen")
            .count(),
        1
    );
    std::fs::remove_dir_all(folder).unwrap();
}
