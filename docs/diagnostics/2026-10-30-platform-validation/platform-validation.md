# Platform availability validation

**Status: pending.** The first verification wave targets Linux and Windows. macOS packaging is gated on both passing their current revision build and availability checks; a package will not be presented as native validation evidence.

## Linux — partial pass

- Target: `9645ffdf24234daebab30ebae22c7860b524d026` (`codex/vscode-parity-p00`), checked from a clean detached worktree at `/tmp/alula-verify-9645ffd`.
- Environment: WSLg/X11 (`DISPLAY=:10.0`, `WAYLAND_DISPLAY=wayland-0`), Flutter 3.47.8, Linux x64.
- `scripts/build_core.sh`: passed; produced `app/native/libalula_core.so`.
- `flutter pub get`: passed for the clean worktree; restored generated plugin links.
- `flutter build linux --release --no-pub`: passed.
- `ldd app/build/linux/x64/release/bundle/alula_app`: no unresolved libraries.
- Launch smoke: the release executable remained alive for 10 seconds and created a visible `Alula Code` 1280×720 X11 window. It used the software-rendering fallback because WSLg did not provide DRI3. The process was then stopped by the smoke script.
- Scope limit: no edit/save interaction was performed in this run. Existing WSLg editing and cgroup evidence is recorded under `docs/diagnostics/2026-10-29-p00/`; it predates this renderer commit and does not replace a current-revision edit/save check or native DRM Linux validation.

## Windows — pending

- There is no Windows command runner in the local WSL environment.
- First native workflow run: `41060624442`. Linux passed; Windows failed at `flutter build windows --release` with “No Windows desktop project configured.” The clean checkout confirmed `app/windows/` was absent because the root `.gitignore` excluded it. The Windows runner existed only as ignored local files, so earlier local Windows build evidence did not prove a clean clone could build.
- Remediation in progress: remove the blanket Windows-runner ignore and commit the Flutter-generated Windows runner sources. Then the branch workflow rebuilds the Windows x64 Release bundle, places `alula_core.dll` beside the executable, checks that the process survives startup, and uploads the bundle. Windows remains pending until a follow-up run passes.
- Existing Windows editing evidence is recorded in `docs/diagnostics/2026-10-28-p00/`; it predates this current folded-viewport commit and is not a current-revision availability check.

## macOS — gated and unverified

- This machine has no macOS host, and the product currently has no `app/macos/` Flutter runner.
- Do not create or distribute a macOS package until Linux and Windows first-wave checks pass. After that gate, add the macOS runner/package path and build it on a macOS GitHub Actions host. Keep native startup, IME, accessibility, and visual checks marked pending until a macOS host can run them.

## Shared baseline

- `FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter RUST_TEST_THREADS=1 bash init.sh --fast`: passed on 2026-10-30 (Rust tests, core build, Flutter 256 tests). This baseline ran in the primary working tree, which contains existing uncommitted changes; the Linux Release build above is the clean-commit evidence.
- Current priority remains architecture and default feature parity first; the 500 MiB optimization target stays deferred to P14.
