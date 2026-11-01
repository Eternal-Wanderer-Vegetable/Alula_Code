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

## Post-fix CI and platform result

Commit `fd546639` cleared the repeated lint. CI run [41267836439](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41267836439) completed successfully: Windows Rust (including Clippy and tests), Ubuntu Rust, Flutter analyze/tests, and harness validation all passed. The Windows `windows-latest` job compiled the `#[cfg(windows)]` helper with the CI stable toolchain.

Platform Availability run [41267833196](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41267833196) also completed successfully for Linux x64, Windows x64, and macOS ARM64. Its current-source Windows Release build passed the P03.7 desktop interaction checks, including a graceful `WM_CLOSE` exit. That workflow did not start Narrator. These hosted-runner results establish that the current branch builds and closes cleanly in CI; they do not erase the separate native Windows 11 failure of the older exact artifact from run 41109679662. The fix itself is test-only and cannot directly alter the shipped Flutter binary, so the old-artifact crash was not caused by this Clippy issue.
