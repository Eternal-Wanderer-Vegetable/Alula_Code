# Repeated Windows Clippy failure

Date: 2026-11-01. Repository: `Alula_Code`, branch `codex/vscode-parity-p00`. GitNexus was refreshed at `fe879c2` before tracing this failure.

## Failure pattern

The Windows Rust job failed at `Clippy (-D warnings)` on six consecutive PR CI runs: [41267446041](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41267446041), [41267027526](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41267027526), [41266093481](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41266093481), [41264593223](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41264593223), [41264327454](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41264327454), and [41262203418](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41262203418). The latest pre-fix run passed Linux Rust, Flutter analyze/tests, and harness validation; only Windows Clippy failed.

Clippy 1.99 reported `clippy::permissions_set_readonly_false` at `crates/editor-doc/src/lib.rs:547`, inside the test `read_only_target_is_rejected_before_replacement`. That Windows-only cleanup clears the temporary target's read-only file attribute so `TempDir` can delete it. The lint warns about Unix world-writable semantics even though this call is compiled only on Windows.

## Change

Moved the Windows cleanup call into a small `#[cfg(windows)]` test helper with a local allow for that lint and a comment describing why the Windows attribute must be cleared. The Unix permission restore remains unchanged. No production save implementation or release binary code changed.

The repeated Clippy failure itself does not explain the historical Flutter shutdown crash: it is raised while compiling test code, not while running the app. Clearing CI restores the Windows gate and makes fresh Windows artifacts available for a separate no-Narrator close test.

## Local verification

- `cargo clippy --workspace --all-targets -- -D warnings` — passed.
- `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` — passed: Rust workspace, Clippy, `build_core`, and all 548 Flutter tests.
- `cargo fmt --all -- --check` — passed.
- `flutter analyze --no-pub` — passed with no issues.

The current Linux run does not compile the `#[cfg(windows)]` helper. The post-fix Windows CI result is the platform confirmation and will be added after that run completes.
