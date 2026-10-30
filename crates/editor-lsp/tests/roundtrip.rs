//! 与 fake-lsp 的全链路集成测试：spawn → 握手 → didOpen 收诊断 → completion → shutdown。

use editor_lsp::{decode_semantic_tokens, LspServer, SemanticToken};

#[test]
fn full_roundtrip_against_fake_lsp() {
    let bin = env!("CARGO_BIN_EXE_fake-lsp");
    let server = LspServer::spawn(".", &[bin.to_string()]).expect("spawn fake-lsp");

    // didOpen → 服务器推送 publishDiagnostics
    server
        .did_open("file:///t/demo.rs", "rust", 7, "fn main() {}\n")
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
    assert_eq!(diags[0].character, 0);
    assert_eq!(diags[0].end_line, Some(0));
    assert_eq!(diags[0].end_character, Some(1));
    assert_eq!(diags[0].document_version, Some(7));
    let serialized = serde_json::to_value(&diags[0]).expect("serialize diagnostic");
    assert_eq!(serialized["endLine"], 0);
    assert_eq!(serialized["endCharacter"], 1);
    assert_eq!(serialized["documentVersion"], 7);

    // completion → 同步响应
    let items = server
        .completion("file:///t/demo.rs", 0, 3, 5000)
        .expect("completion");
    assert_eq!(items, vec!["fake_a()", "fake_completion_b"]);

    let legend = server
        .semantic_token_legend()
        .expect("semantic token legend");
    let mut request = server
        .semantic_tokens_async("file:///t/demo.rs")
        .expect("semantic request")
        .expect("fake server supports semantic tokens");
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    let response = loop {
        if let Some(response) = request.try_recv().expect("semantic response channel") {
            break response;
        }
        assert!(std::time::Instant::now() < deadline, "等待语义令牌超时");
        std::thread::sleep(std::time::Duration::from_millis(10));
    };
    assert_eq!(
        decode_semantic_tokens(&response, &legend).expect("decode semantic tokens"),
        vec![
            SemanticToken {
                line: 0,
                start_character: 3,
                length: 4,
                kind: "function.readonly".into(),
            },
            SemanticToken {
                line: 1,
                start_character: 0,
                length: 3,
                kind: "variable".into(),
            },
        ]
    );

    // 干净退出
    server.shutdown().expect("shutdown");
}
