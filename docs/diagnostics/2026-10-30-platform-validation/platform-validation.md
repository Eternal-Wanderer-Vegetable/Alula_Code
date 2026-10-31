# Platform availability validation

**Project status: pending verification.** Linux and Windows first-wave build/start checks passed, followed by a macOS package build and hosted startup smoke. These runs do not close end-to-end edit/save, IME, accessibility, native DRM, or visual-parity checks. A CI artifact is recorded as a package, not as native-user acceptance.

## Linux — partial pass

- Target: `9645ffdf24234daebab30ebae22c7860b524d026` (`codex/vscode-parity-p00`), checked from a clean detached worktree at `/tmp/alula-verify-9645ffd`.
- Environment: WSLg/X11 (`DISPLAY=:10.0`, `WAYLAND_DISPLAY=wayland-0`), Flutter 3.47.8, Linux x64.
- `scripts/build_core.sh`: passed; produced `app/native/libalula_core.so`.
- `flutter pub get`: passed for the clean worktree; restored generated plugin links.
- `flutter build linux --release --no-pub`: passed.
- `ldd app/build/linux/x64/release/bundle/alula_app`: no unresolved libraries.
- Launch smoke: the release executable remained alive for 10 seconds and created a visible `Alula Code` 1280×720 X11 window. It used the software-rendering fallback because WSLg did not provide DRI3. The process was then stopped by the smoke script.
- Scope limit: no edit/save interaction was performed in this run. Existing WSLg editing and cgroup evidence is recorded under `docs/diagnostics/2026-10-29-p00/`; it predates this renderer commit and does not replace a current-revision edit/save check or native DRM Linux validation.
- The clean-commit Linux bundle was also uploaded by Actions run `41062967568` as artifact `alula-linux-x64-c52758e1f06262a3f862a822a1c3fed6aaa7b0bf`.

## First-wave build and startup gate — passed

- GitHub Actions run [41062967568](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41062967568) passed both Linux and Windows jobs from commit `c52758e`.
- Linux artifact: `alula-linux-x64-c52758e1f06262a3f862a822a1c3fed6aaa7b0bf`.
- Windows artifact: `alula-windows-x64-c52758e1f06262a3f862a822a1c3fed6aaa7b0bf`.
- This gate establishes clean-checkout Release build, Rust library deployment, and app startup. It does not close project verification: current-revision edit/save, native DRM, IME, accessibility, and visual parity remain open.

## Windows — build/start pass; functional checks pending

- There is no Windows command runner in the local WSL environment.
- First native workflow run: `41060624442`. Linux passed; Windows failed at `flutter build windows --release` with “No Windows desktop project configured.” The clean checkout confirmed `app/windows/` was absent because the root `.gitignore` excluded it. The Windows runner existed only as ignored local files, so earlier local Windows build evidence did not prove a clean clone could build.
- Remediation: removed the blanket Windows-runner ignore and committed the Flutter-generated Windows runner sources. The branch workflow builds the Windows x64 Release bundle, places `alula_core.dll` beside the executable, checks that the process survives startup, and uploads the bundle.
- Existing Windows editing evidence is recorded in `docs/diagnostics/2026-10-28-p00/`; it predates this current folded-viewport commit and is not a current-revision availability check.
- Follow-up Actions run `41061997778` built the Windows Release bundle and confirmed 10-second process survival, but its cleanup step raced after terminating the already-exited process, so no artifact was uploaded.
- Final first-wave run `41062967568`: Linux and Windows jobs both succeeded. Windows Release build, `alula_core.dll` deployment, 10-second startup survival, process cleanup, and artifact upload passed. Artifact: `alula-windows-x64-c52758e1f06262a3f862a822a1c3fed6aaa7b0bf`. This confirms Windows x64 build/start availability on the current source; it is not an editing, IME, accessibility, or visual-parity signoff.

## macOS — package and hosted startup smoke passed; local native acceptance pending

- Linux and Windows first-wave build/start checks passed in run `41062967568`; the gate to prepare a macOS package is satisfied.
- The Flutter macOS runner is source-controlled in `app/macos/`. GitHub Actions run [41065014669](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41065014669) completed successfully on `macos-15`: Flutter analyze/tests, Release build, Rust dylib copied beside the executable, ad-hoc signature verification, 12-second launch smoke, and package upload all passed.
- Artifact: `alula-macos-ARM64-374fdc97c0b1a1fe65dc59817fbf6c620dfef26c`; it contains `alula-code-macos-ARM64-374fdc97c0b1a1fe65dc59817fbf6c620dfef26c.zip` and its `.sha256` file. This is a downloadable Actions artifact, not a GitHub Release asset.
- The local machine has no macOS host. No Apple Developer signing/notarization secrets are configured, so the package is ad-hoc signed and unnotarized; Gatekeeper may require the user to approve opening it. Native macOS interaction, IME, accessibility, and visual checks remain pending.
- The staged GitNexus graph reports `RegisterGeneratedPlugins` as CRITICAL (40 downstream symbols / 27 flows). It is ambiguous in the index; path-qualified impact still reports unrelated editor/Rust flows. Source review confirms the generated function has one caller (`MainFlutterWindow.awakeFromNib`) and registers only `screen_retriever_macos` and `window_manager`; no Dart FFI or Rust ABI code changed. Keep the graph warning recorded and rely on macOS compile/test/launch evidence to validate this generated runner path.

## Shared baseline

- `FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter RUST_TEST_THREADS=1 bash init.sh --fast`: passed on 2026-10-30 (Rust tests, core build, Flutter 256 tests). This baseline ran in the primary working tree, which contains existing uncommitted changes; the Linux Release build above is the clean-commit evidence.
- Current priority remains architecture and default feature parity first; the 500 MiB optimization target stays deferred to P14.
