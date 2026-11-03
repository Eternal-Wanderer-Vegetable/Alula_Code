# Session Handoff

> Last Updated: 2026-11-03. P04.92 / CI-Crash-01 is complete for the selected current Release artifact replay. Code commit `34f1511` and the separately staged evidence/state update are on `codex/vscode-parity-p00`. PR #2 remains OPEN/draft.

## Current Objective

Continue the fixed Code-OSS 1.145.0 parity plan one registered slice at a time. Prioritize overall architecture and Linux/Windows usability, then provide hosted macOS packages. Numeric memory optimization remains deferred. Do not publish v0.1.0, mark PR #2 ready, or merge.

## Latest Completed Follow-up: P04.92 / CI-Crash-01

- The Windows ARM artifact workflow accepts a run ID, exact artifact name, and source commit. Narrator/UIA focus checks and the legacy source interaction job are opt-in and default off.
- Current x64 Release artifact `1129d607e10e28ed9ada90b185c59f8757a26686` was replayed on Windows 11 Enterprise ARM64 with x64 emulation, in light and dark themes at 96 DPI. Both themes synchronized the exact second-view edit across four accessible editor nodes, saved/read back the edit, and closed gracefully (`exitCode=0`). No Application Error events or crash dumps. Narrator was not started. Evidence: replay [`41627307864`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41627307864), artifacts `13225549631` (light) and `13226642379` (dark); PR CI [`41627306984`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41627306984) passed all four jobs.
- Several earlier exact-edit assertions failed because hosted ARM keyboard/clipboard injection intermittently dropped characters. Failing theme varied; each available close record was exit 0 with no app fault/dump. The validator now waits 350 ms after Enter and paces each ASCII key at 100 ms; final exact light/dark assertions pass. This is a harness input fix, not a product crash fix.
- Historical artifact `d5319369` still has confirmed Windows 11 ARM `0xC000041D` during close (`flutter_windows.dll`, offset `0x1e220`). Its source cause remains unknown and the current artifact's clean replay does not prove it fixed. Full evidence and GitNexus caveats: [`p04.92-win11-arm-current-artifact.md`](docs/diagnostics/2026-11-03-p04/p04.92-win11-arm-current-artifact.md) and [`ci-failures-and-crash-correlation.md`](docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md).

## Previous Completed Slice: P04.91 / EDT-15f

- Find/Replace starts at 419 logical pixels. The left sash expands the bar within editor/minimap bounds; double-click toggles default/maximum width; fields stay synchronized; width/query survive close/reopen. Narrow layouts reflow actions. Resize fixture, 50,000-line two-view regression, local `init.sh`, cargo fmt, Flutter analyze, harness, PR CI, and hosted Linux/Windows/macOS package checks passed. macOS native DnD remains explicitly skipped where hosted pointer injection is unavailable. Details: [`p04.91-find-resize.md`](docs/diagnostics/2026-11-03-p04/p04.91-find-resize.md).

## Current Workspace State

- Work in `/tmp/alula-p04.70-next`; checkout is detached. Pushes to `origin/codex/vscode-parity-p00` are authorized with `git push origin HEAD:codex/vscode-parity-p00`.
- Code commit `34f1511` is pushed. P04.92 evidence and project state are kept in a separate documentation commit.
- PR #2 must remain OPEN/draft. Do not publish v0.1.0 or merge.

## Open Validation Gaps

- Historical Windows 11 ARM crash source cause is unresolved; this current-build x64 emulation replay is non-reproduction evidence only.
- Native macOS DnD/IME, Linux DRM hardware, and P15 device gates remain open. Hosted macOS DnD must be recorded as skipped when pointer routing is unavailable.
- These gaps do not block the next architecture slice, but must not be reported as passed.

## Next Session First Step

Read `session-handoff.md` and `progress.md`; check `node .gitnexus/run.cjs status`, refresh the graph if stale, and run `bash init.sh --fast` before selecting one dependency-ready `in-progress`/`not-started` feature from `feature_list.json`. Preserve the unresolved historical crash evidence and avoid local GUI/accessibility actions that can start Narrator.
