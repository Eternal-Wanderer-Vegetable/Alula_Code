# Session Handoff

Last Updated: 2026-11-07

## Current Objective

Finish P05 / `feat-027` one registered LAY/CMD matrix slice at a time. Keep PR #3 draft/open; do not merge or mark P05 complete until the remaining matrix requirements pass. `docs/03-里程碑计划与验收标准.md` is the task-state/DoD authority, `docs/11-VSCode功能对照矩阵.md` is the requirement matrix, and `feature_list.json` is the feature state machine.

## Current State

- Worktree: `/tmp/alula-p04.70-next`; branch `codex/vscode-parity-p05`; PR #3: https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/pull/3 (draft, targets `main`). The original `/mnt/e/alula_code` worktree contains unrelated user changes; do not modify or clean it.
- P05.1–P05.24 are complete. P05.22 / feat-074 product commit `78ebda0` is pushed; local full DoD, PR CI `42336252273`, and Linux/Windows/macOS Intel x64 Platform Availability `42336247962` passed. Full package, hash, DnD-skip, and native Quit evidence is in `docs/diagnostics/2026-11-07-p05/p05.22-panel-position-top-bottom-scope.md`.
- P05.23 / feat-075 / LAY-05b is complete at product commit `b9a1b4b`. Focused tests 27/27 and full local DoD passed; PR CI `42340702008` and Linux/Windows/macOS Intel x64 Platform Availability `42340697752` passed. Linux/Windows native DnD passed; hosted macOS DnD explicitly skipped for unavailable pointer routing. Package artifacts: Linux `13561543111`, Windows `13561309118`, macOS `13562435512`; macOS ZIP SHA-256 `e73c36ff01ecae7f551866a5906c12fa0eca2423448a44222ab11a32e39422c1` matched its sidecar and ZIP integrity passed. Native Quit/startup artifact `13561608842`. Full evidence and graph limitations: `docs/diagnostics/2026-11-07-p05/p05.23-panel-position-left-right-scope.md`.
- P05.24 / feat-076 / LAY-05c is complete at product commit `66d2867`. Local full DoD passed: Rust 71+54, Clippy, build_core, Flutter 1,133, cargo fmt, Flutter analyze (0), Harness 100/100, JSON/diff. PR CI `42346270441` and Platform Availability `42346265567` passed; Linux/Windows/macOS Intel x64 lanes and all three packages succeeded. macOS ZIP SHA-256 `08d70b5f79b0ba19845180781c452ffface11f370a1a8b57ce25b5172f262c4b` matched sidecar and 76 entries passed integrity; macOS DnD remains explicitly skipped for unavailable hosted pointer routing. Full evidence and GitNexus limits are in `docs/diagnostics/2026-11-07-p05/p05.24-panel-alignment-scope.md`.
- GitNexus was refreshed at product head `78ebda0` before P05.23 edits. `WbSplit` is HIGH/lower-bound and `WbNode` HIGH; `WorkbenchLayout` MEDIUM. UNKNOWN helper/menu calls were checked with exact `rg` searches. The analyzer skips >512 KiB `workbench_page.dart`, reports cross-language property gaps and incomplete flow coverage. Do not treat empty/UNKNOWN or missing flows as safe.
- Prior P05 platform evidence is for Linux/Windows/macOS Intel x64 hosted runners. Hosted macOS DnD pointer injection is unavailable and remains an explicit skip; Apple Silicon and physical-device checks are not implied.

## Blockers

- None currently require user action.

## Next Step

1. Select the next incomplete P05 LAY/CMD requirement from `docs/11-VSCode功能对照矩阵.md`, register one bounded slice in `docs/03` and `feature_list.json`, and complete GitNexus impact before editing.
2. Keep PR #3 draft/open and P05/feat-027 in-progress; finish each slice with local DoD, hosted Linux/Windows/macOS evidence, graph change analysis, and its own evidence commit before starting another. Do not merge.
