//! 与 fake-lsp 的全链路集成测试：spawn → 握手 → didOpen 收诊断 → completion → shutdown。

use editor_lsp::LspServer;

#[test]
fn full_roundtrip_against_fake_lsp() {
    let bin = env!("CARGO_BIN_EXE_fake-lsp");
    let server = LspServer::spawn(".", &[bin.to_string()]).expect("spawn fake-lsp");

    // didOpen → 服务器推送 publishDiagnostics
    server
        .did_open("file:///t/demo.rs", "rust", 1, "fn main() {}\n")
        .expect("didOpen");

    // 诊断是异步推送的：轮询等待
    let mut diags = Vec::new();
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    while diags.is_empty() {
        assert!(std::time::Instant::now() < deadline, "等待诊断超时");
        std::thread::sleep(std::time::Duration::from_millis(50));
        diags = server.diagnostics("file:///t/demo.rs");
    }
    assert_eq!(diags.len(), 1);
    assert_eq!(diags[0].severity, 1);
    assert_eq!(diags[0].message, "fake error from fake-lsp");
    assert_eq!(diags[0].line, 0);

    // completion → 同步响应
    let items = server
        .completion("file:///t/demo.rs", 0, 3, 5000)
        .expect("completion");
    assert_eq!(items, vec!["fake_a()", "fake_completion_b"]);

    // 干净退出
    server.shutdown().expect("shutdown");
}
