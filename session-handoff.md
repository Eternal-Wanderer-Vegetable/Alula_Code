# Session Handoff

> Last Updated: 2026-11-03. P04.91 / EDT-15f is complete locally and on hosted CI. Code commit `1129d60` is pushed to `codex/vscode-parity-p00`; evidence/state updates are in the current worktree. PR #2 remains OPEN/draft.

## Current Objective

Continue the fixed Code-OSS 1.145.0 parity plan one registered slice at a time. Prioritize overall architecture and Linux/Windows usability, then provide hosted macOS packages. Numeric memory optimization remains deferred. Do not publish v0.1.0, mark PR #2 ready, or merge.

## Latest Completed Slice: P04.91 / EDT-15f

- Find/Replace starts at 419 logical pixels. The left sash expands the bar while respecting editor and minimap bounds; double-click toggles default/maximum width; Find and Replace input widths stay synchronized; width and query survive close/reopen. Narrow layouts reflow actions instead of overflowing.
- The dedicated resize fixture covers bounds, drag direction, double-click, narrow-window reflow, reopen persistence, and unchanged query/document/selection/disk state. The 50,000-line two-view regression passes.
- Full `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh`: Rust workspace, Clippy, `build_core`, Flutter 783 all passed. `cargo fmt --all -- --check`, Flutter analyze (0 issues), `git diff --check`, harness validation (100/100) passed. No local desktop GUI or Narrator was started.
- PR CI [`41618241197`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41618241197) passed all jobs, including 783 Flutter tests. Platform Availability [`41618233435`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41618233435) passed Linux, Windows, and macOS jobs. Linux artifacts `13223165628`/`13223115653` show 23 pointer events and three drop routes. Windows artifacts `13222791693`/`13222457221` show 13 pointer events and three routes; the visible client was 1028×711 at 96 DPI and `WM_CLOSE` exited gracefully with code 0. macOS ARM64 package artifact `13222524463`, startup `13223810498`, and clipboard passed; native DnD artifact `13223407455` explicitly skipped because hosted pointer routing was unavailable.
- The historical Windows 11 ARM replay of old artifact `d5319369` directly reproduced `0xC000041D`. The current Windows x64 close smoke exited 0, which does not establish a fix. Keep current-build ARM replay open. Sampled MSAA/probe assertion failures are distinct signals and should be classified by failed step, process exit code, and crash report. See [`ci-failures-and-crash-correlation.md`](docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md) and [`p04.91-find-resize.md`](docs/diagnostics/2026-11-03-p04/p04.91-find-resize.md).
- GitNexus all-scope results varied: earlier scans reported LOW (4 files / 5–6 symbols / 0 processes), while the latest says 4 touched files have no indexed-symbol overlap and warns “not a clean tree.” Compare-main remains CRITICAL with capped results (1,583 files / 1,127–1,377 symbols / 366–389 flows). Preserve both warnings; the >512 KiB workbench file remains outside the index and its impact was UNKNOWN.

## Current Workspace State

- Work in `/tmp/alula-p04.70-next`; checkout is detached. Pushes to `origin/codex/vscode-parity-p00` are authorized with `git push origin HEAD:codex/vscode-parity-p00`.
- P04.91 code is committed as `1129d60`. The report, `docs/03`, `feature_list.json`, `progress.md`, and this handoff contain the completion evidence.
- PR #2 must remain OPEN/draft. Do not publish v0.1.0 or merge.

## Open Validation Gaps

- Current-build Windows 11 ARM crash replay has not been run. The historical artifact crash source cause remains unknown.
- Native macOS DnD/IME, Linux DRM hardware, and P15 device gates remain open. Hosted macOS DnD is skipped when pointer injection is unavailable.
- These gaps do not block the next architecture slice, but must not be reported as passed.

## Next Session First Step

Read `session-handoff.md` and `progress.md`, run `node .gitnexus/run.cjs status` and refresh the index if stale, then run `bash init.sh --fast`. Select the next dependency-ready item from `docs/03-里程碑计划与验收标准.md` / `feature_list.json`, run GitNexus impact before editing, and continue one feature at a time. Preserve the unresolved Windows ARM `0xC000041D` evidence and avoid local GUI/accessibility actions that can start Narrator.
