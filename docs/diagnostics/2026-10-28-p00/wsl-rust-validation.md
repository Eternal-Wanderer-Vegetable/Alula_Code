# WSL Rust toolchain and parity baseline

Date: 2026-10-28
Repository: `/mnt/e/alula_code`, branch `codex/vscode-parity-p00`, HEAD `6e4e77e`.

## WSL toolchain

- Installed the official `rustup-init` for `x86_64-unknown-linux-gnu` from the USTC Rust mirror over verified TLS. Its SHA-256 matched the official Rust checksum file: `5be191e8c70a5007074254cb74d78dbfdd25cd5a61c27de7b8e5410122ec24f4`.
- Stable toolchain installed: `rustc 1.99.1 (58cf8f9c3 2026-10-13)`, `cargo 1.99.1`, `rustfmt 1.10.0-stable`, `clippy 0.1.99`.
- WSL already had GCC, make, and pkg-config. No apt packages were installed. Flutter checks use the existing Windows Flutter 3.47.8 SDK through Git Bash; the WSL-visible `/mnt/e/flutter` is a Windows SDK whose shell wrapper has CRLF line endings, so it is not used as a Linux Flutter SDK.

## WSL Rust checks

All commands exited 0:

```text
cargo fmt --check
CARGO_HTTP_MULTIPLEXING=false cargo test --workspace --locked
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo build -p editor-core --release --locked
```

The workspace test run compiled Linux dependencies from `Cargo.lock`, ran all unit, integration, process-lifecycle, and doc tests, and passed. The release build produced the Linux `editor-core` library under ignored `target/`; it did not copy a Linux library over the Windows app artifact.

## Windows Git Bash validation

Using the authorized Windows runner and Flutter 3.47.8, these commands exited 0:

```text
cargo fmt --check && bash init.sh
(cd app && flutter analyze)
```

`init.sh` passed Rust workspace tests, clippy, `build_core`, and all 122 Flutter tests. `flutter analyze` reported no issues. The P00.3 recovery fixture again observed 2,000,001 accepted UTF-16 units with no journal text and recovered the five-unit disk seed; this is the known failure behavior under characterization, not a fix.

## Scope and remaining gate

No application code or `feature_list.json` status changed. `feat-022` / P00 remains `in-progress`, with P00.4 blocked by the existing external/product gates: Safari Web Inspector manual attach, WPE GBM/DMABUF on a real DRM host, Microsoft service identity/licensing, and the full docs/04 multi-run product memory protocol. WSL Rust installation removes the missing-Cargo environment blocker but does not satisfy those gates.
