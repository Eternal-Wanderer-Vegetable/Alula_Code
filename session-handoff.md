# Session Handoff

> Last Updated: 2026-11-03. P04.94 / EDT-17b bounded character/word diff model, local DoD, and hosted verification are complete. Code/evidence commits `39a5592` and `57cbb40` are pushed; hosted evidence registration is the current docs-only commit stage. PR #2 remains OPEN/draft.

## Current Objective

Continue the fixed Code-OSS 1.145.0 parity plan one registered slice at a time. Prioritize overall architecture and Linux/Windows usability, then provide hosted macOS packages. Numeric memory optimization remains deferred. Do not publish v0.1.0, mark PR #2 ready, or merge.

## Latest Completed Slice: P04.94 / EDT-17b

- Added a bounded pure Dart UTF-16 character Myers model with Code-OSS ASCII word-boundary expansion at the pinned two-thirds threshold. It returns zero-based, end-exclusive paired text ranges, preserves surrogate pairs, and validates that unchanged gaps match before returning.
- Nine focused cases plus 200 seeded random pairs pass; they cover local and whole-word edits, punctuation, repeats, BOM/Emoji/CRLF, limits, equal gaps and surrogate safety. `bash init.sh` passed Rust workspace, Clippy, `build_core`, and Flutter 802; `cargo fmt --all -- --check`, `flutter analyze --no-pub` (0 issues), harness 100/100, and `git diff --check` passed. Code commit: `39a5592`; local milestone/state evidence commit: `57cbb40`; hosted validation is recorded in the current staged evidence update.
- EDT-17a line alignment and EDT-17b word ranges are separate models; no diff UI is connected. Inline/side-by-side, line-hunk integration, moved blocks, unchanged folding, accessible navigation, and Git/SCM entry points remain open. Details and graph warnings: [`p04.94-word-diff-model.md`](docs/diagnostics/2026-11-03-p04/p04.94-word-diff-model.md).

## Latest Hosted Platform Evidence: P04.94 head `57cbb40`

- PR CI [`41636601665`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41636601665) passed all four jobs: Flutter analyze/tests, Linux/Windows Rust, and harness structure.
- Platform Availability [`41636589670`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41636589670) passed Linux x64, Windows x64, and macOS ARM64 package/startup smokes. Release artifacts: Linux [`13230189175`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41636589670/artifacts/13230189175), Windows [`13230509184`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41636589670/artifacts/13230509184), macOS ARM64 [`13232455491`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41636589670/artifacts/13232455491). Linux/Windows DnD recorded 21/13 pointer events and three drop outcomes. macOS DnD [`13232251198`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41636589670/artifacts/13232251198) was skipped because hosted pointer routing was unavailable; startup diagnostics [`13232590066`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41636589670/artifacts/13232590066) contain only the Impeller initialization line.

## Crash and CI Finding: P04.92 / CI-Crash-01

- Current x64 Release artifact `1129d607` passed Windows 11 ARM light/dark edit, four-view sync, save/readback, and graceful close (exit 0); no Application Error events or dumps. Narrator was not started. Replay [`41627307864`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41627307864); PR CI [`41627306984`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41627306984).
- Earlier ARM validation assertion failures came from intermittent keyboard/clipboard character loss; each inspected failure still closed with exit 0 and no crash record. The validator now settles after Enter and paces typing. This improves CI reliability, not application crash behavior.
- Historical artifact `d5319369` still has a confirmed Windows 11 ARM `0xC000041D` close crash in `flutter_windows.dll`; source cause is unknown. Current clean replay does not prove a fix. Evidence: [`p04.92-win11-arm-current-artifact.md`](docs/diagnostics/2026-11-03-p04/p04.92-win11-arm-current-artifact.md), [`ci-failures-and-crash-correlation.md`](docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md).

## Current Workspace State

- Work in `/tmp/alula-p04.70-next`; checkout is detached. Pushes to `origin/codex/vscode-parity-p00` are authorized with `git push origin HEAD:codex/vscode-parity-p00`.
- P04.92, P04.93, and P04.94 code/local-evidence commits are pushed. P04.94 hosted validation updates to docs/03, diagnostics, feature_list, progress, and handoff are staged for a separate evidence commit.
- PR #2 must remain OPEN/draft. Do not publish v0.1.0 or merge.

## Open Validation Gaps

- Historical Windows 11 ARM crash source cause is unresolved; current x64 emulation replay is non-reproduction evidence only.
- Native macOS DnD/IME, Linux DRM hardware, and P15 device gates remain open. Hosted macOS DnD must be recorded as skipped when pointer routing is unavailable.
- EDT-17 visual diff features remain open; do not report the diff editor complete.

## Next Session First Step

Finish the P04.94 hosted-evidence commit after staged/all/compare GitNexus scans and push it to `codex/vscode-parity-p00`. P04.94 is then complete; register one next EDT-17 slice from `docs/11` in `docs/03` and `feature_list.json` before editing. Keep PR #2 open/draft. Preserve the unresolved historical crash evidence and avoid local GUI/accessibility actions that can start Narrator.
