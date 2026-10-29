//! P00.3 REF-07 slow completion baseline; the synchronous caller waits for the provider.

use editor_lsp::LspServer;
use std::time::{Duration, Instant};

#[test]
fn delayed_completion_blocks_until_response() {
    let delay_ms = 1_200;
    let server = LspServer::spawn(
        ".",
        &[
            env!("CARGO_BIN_EXE_slow_fake_lsp").to_string(),
            delay_ms.to_string(),
        ],
    )
    .expect("spawn slow fake LSP");
    let uri = "file:///p00/slow.rs";
    server
        .did_open(uri, "rust", 1, "fn main() {}\n")
        .expect("didOpen");

    let started = Instant::now();
    let items = server
        .completion(uri, 0, 3, 5_000)
        .expect("completion response");
    let elapsed = started.elapsed();
    println!(
        "P00.3_FIXTURE={{\"fixture\":\"parity-ref-07-slow-completion-01\",\"configuredDelayMs\":{delay_ms},\"callerWaitMs\":{},\"items\":{}}}",
        elapsed.as_millis(),
        serde_json::to_string(&items).unwrap()
    );

    assert_eq!(items, vec!["delayed_completion"]);
    assert!(elapsed >= Duration::from_millis(1_000));
    server.shutdown().expect("shutdown fake LSP");
}
