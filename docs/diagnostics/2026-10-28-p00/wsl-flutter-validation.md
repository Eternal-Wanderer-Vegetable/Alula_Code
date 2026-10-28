# WSL Flutter runner validation (2026-10-28)

## Environment

- Native WSL SDK: Flutter stable 3.47.8, Dart 3.13.7, installed at `/home/vegetable/develop/flutter` on the WSL filesystem. The official Flutter archive checksum matched its release manifest.
- Rust toolchain: rustc/cargo 1.99.1. Existing WSL `libgbm-dev` and `video`/`render` groups are documented in `wslg-gbm-egl-evidence.json`.
- Dart packages were resolved with `flutter pub get --offline --enforce-lockfile`. A temporary `/tmp/alula-pub-cache` exposed the existing `pub.flutter-io.cn` cache under the lockfile's `pub.dev` host name. `app/pubspec.yaml` and `app/pubspec.lock` had no content diff after ignoring their existing line-ending differences.

The WSL Linux desktop toolchain dependencies are now installed: clang 18.1.3, CMake 3.28.3, Ninja 1.11.1, pkg-config 1.8.1, GTK 3.24.41, libstdc++-12-dev 12.4.0, Epoxy 1.5.10, libsecret 0.21.4, and GBM 25.2.8. Flutter is on PATH for login and interactive Bash via `.profile` and `.bashrc`. `flutter doctor -v` marks the Linux desktop toolchain ready. It reports no Android SDK and cannot query EGL driver details because `eglinfo` is absent; neither prevents the Linux desktop build path. Packages were installed from a temporary Ubuntu 24.04 Aliyun source configuration under `/tmp`, which was removed after installation.

## Verification

| Command | Result |
|---|---|
| `cargo fmt --check` | Exit 0 |
| `cargo clippy --workspace --all-targets -- -D warnings` | Exit 0 |
| `flutter analyze --no-pub` in `app/` | Exit 0; no issues found |
| `flutter test --no-pub --concurrency=1` in `app/` | Exit 0; 122 tests passed |
| `bash init.sh` with the WSL Cargo/Flutter paths and offline Pub cache | Exit 0; Rust workspace tests, Clippy, `build_core`, and all 122 Flutter tests passed |

The `P00.3 REF-07-RECOVERY-01` fixture accepted 2,000,001 UTF-16 units; the session journal omitted the oversized text and restart recovered the 5-unit on-disk `seed\n` content, matching the recorded current-state behavior. The UTF-16 diff random replay also passed.

One earlier parallel `flutter test --no-pub` run exited 1 on `P00.3 REF-07-UNDO-01`. That test passed in isolation, passed in the complete serial run, and passed again in the later default-concurrency `bash init.sh` run. The cause of the one-off failure was not established; no product code or test was changed.

## Scope and remaining gates

This only establishes that the current Flutter/Rust workspace gates can run natively in WSL. It does not establish WPE hardware GBM/DMABUF, Microsoft official-service identity/licensing, or the docs/04 full-product memory acceptance. P00.4 remains blocked and P01 remains unstarted. The WSLg renderer evidence remains software `llvmpipe`; it is not real DRM hardware evidence.
