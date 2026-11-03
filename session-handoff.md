# Session Handoff

> Last Updated: 2026-11-03. P04.94 / EDT-17b bounded character/word diff model and local DoD are complete. Code commit `39a5592` is local; evidence/state changes are being committed separately before push. PR #2 remains OPEN/draft.

## Current Objective

Continue the fixed Code-OSS 1.145.0 parity plan one registered slice at a time. Prioritize overall architecture and Linux/Windows usability, then provide hosted macOS packages. Numeric memory optimization remains deferred. Do not publish v0.1.0, mark PR #2 ready, or merge.

## Latest Completed Slice: P04.94 / EDT-17b

- Added a bounded pure Dart UTF-16 character Myers model with Code-OSS ASCII word-boundary expansion at the pinned two-thirds threshold. It returns zero-based, end-exclusive paired text ranges, preserves surrogate pairs, and validates that unchanged gaps match before returning.
- Nine focused cases plus 200 seeded random pairs pass; they cover local and whole-word edits, punctuation, repeats, BOM/Emoji/CRLF, limits, equal gaps and surrogate safety. `bash init.sh` passed Rust workspace, Clippy, `build_core`, and Flutter 802; `cargo fmt --all -- --check`, `flutter analyze --no-pub` (0 issues), harness 100/100, and `git diff --check` passed. Code commit: `39a5592`; P04.94 evidence/state commit is pending.
- EDT-17a line alignment and EDT-17b word ranges are separate models; no diff UI is connected. Inline/side-by-side, line-hunk integration, moved blocks, unchanged folding, accessible navigation, and Git/SCM entry points remain open. Details and graph warnings: [`p04.94-word-diff-model.md`](docs/diagnostics/2026-11-03-p04/p04.94-word-diff-model.md).

## Latest Hosted Platform Evidence: P04.93 head `ca2600e`

- PR CI [`41631078928`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41631078928) passed all four jobs: Linux/Windows Rust, Flutter analyze + tests, and harness structure.
- Platform Availability [`41631071185`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41631071185) passed Linux x64, Windows x64, and macOS ARM64 package/startup/interaction smoke. Artifacts: Linux [`13227783918`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41631071185/artifacts/13227783918), Windows [`13228249270`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41631071185/artifacts/13228249270), macOS ARM64 [`13229646087`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41631071185/artifacts/13229646087). P04.94 hosted CI is pending until its commits are pushed.

## Crash and CI Finding: P04.92 / CI-Crash-01

- Current x64 Release artifact `1129d607` passed Windows 11 ARM light/dark edit, four-view sync, save/readback, and graceful close (exit 0); no Application Error events or dumps. Narrator was not started. Replay [`41627307864`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41627307864); PR CI [`41627306984`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41627306984).
- Earlier ARM validation assertion failures came from intermittent keyboard/clipboard character loss; each inspected failure still closed with exit 0 and no crash record. The validator now settles after Enter and paces typing. This improves CI reliability, not application crash behavior.
- Historical artifact `d5319369` still has a confirmed Windows 11 ARM `0xC000041D` close crash in `flutter_windows.dll`; source cause is unknown. Current clean replay does not prove a fix. Evidence: [`p04.92-win11-arm-current-artifact.md`](docs/diagnostics/2026-11-03-p04/p04.92-win11-arm-current-artifact.md), [`ci-failures-and-crash-correlation.md`](docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md).

## Current Workspace State

- Work in `/tmp/alula-p04.70-next`; checkout is detached. Pushes to `origin/codex/vscode-parity-p00` are authorized with `git push origin HEAD:codex/vscode-parity-p00`.
- P04.92 and P04.93 code/evidence commits are pushed. P04.94 code commit `39a5592` is local; docs/03, diagnostics, feature_list, progress, and handoff are unstaged for a separate evidence commit.
- PR #2 must remain OPEN/draft. Do not publish v0.1.0 or merge.

## Open Validation Gaps

- Historical Windows 11 ARM crash source cause is unresolved; current x64 emulation replay is non-reproduction evidence only.
- Native macOS DnD/IME, Linux DRM hardware, and P15 device gates remain open. Hosted macOS DnD must be recorded as skipped when pointer routing is unavailable.
- EDT-17 visual diff features remain open; do not report the diff editor complete.

## Next Session First Step

Finish the P04.94 evidence commit after staged/all/compare GitNexus scans; push the code and evidence commits to `codex/vscode-parity-p00`, then verify PR and Platform Availability checks for the new head. Keep PR #2 open/draft. After hosted checks finish, register one next EDT-17 slice from `docs/11` in `docs/03` before editing. Preserve the unresolved historical crash evidence and avoid local GUI/accessibility actions that can start Narrator.
