# Session Handoff

Last Updated: 2026-11-07

## Current Objective

Finish P05 / `feat-027` one registered LAY/CMD matrix slice at a time. Keep PR #3 draft/open; do not merge or mark P05 complete until the remaining matrix requirements pass. `docs/03-里程碑计划与验收标准.md` is the task-state/DoD authority, `docs/11-VSCode功能对照矩阵.md` is the requirement matrix, and `feature_list.json` is the feature state machine.

## Current State

- Worktree: `/tmp/alula-p04.70-next`; branch `codex/vscode-parity-p05`; PR #3: https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/pull/3 (draft, targets `main`). The original `/mnt/e/alula_code` worktree contains unrelated user changes; do not modify or clean it.
- P05.1–P05.27 are complete; P05 / feat-027 remains in progress for later LAY/CMD matrix items. Product commit `880ebecf455a7079677897be24bb9f5ead005fb4` is pushed to draft PR #3. Local focused tests 49/49 and full DoD (Flutter 1,150/1,150), fmt/analyze, Harness 100/100 passed. PR CI `42362871885` and Linux/Windows/macOS Intel x64 Platform Availability `42362866427` passed. Linux/Windows native DnD passed; macOS DnD explicitly skipped because hosted pointer routing was unavailable. Packages Linux/Windows/macOS `13571020067` / `13571275187` / `13570959133`; macOS ZIP SHA-256 `6d302c880d24a69b2842fa7a6b62e4764fd82449c16c224027a6e2d3c024e29c` matched sidecar and ZIP integrity passed. Scope and GitNexus coverage limitations: `docs/diagnostics/2026-11-07-p05/p05.27-sash-double-click-reset-scope.md`.
- P05.23 / feat-075 / LAY-05b is complete at product commit `b9a1b4b`. Focused tests 27/27 and full local DoD passed; PR CI `42340702008` and Linux/Windows/macOS Intel x64 Platform Availability `42340697752` passed. Linux/Windows native DnD passed; hosted macOS DnD explicitly skipped for unavailable pointer routing. Package artifacts: Linux `13561543111`, Windows `13561309118`, macOS `13562435512`; macOS ZIP SHA-256 `e73c36ff01ecae7f551866a5906c12fa0eca2423448a44222ab11a32e39422c1` matched its sidecar and ZIP integrity passed. Native Quit/startup artifact `13561608842`. Full evidence and graph limitations: `docs/diagnostics/2026-11-07-p05/p05.23-panel-position-left-right-scope.md`.
- P05.24 / feat-076 / LAY-05c is complete at product commit `66d2867`. Local full DoD passed: Rust 71+54, Clippy, build_core, Flutter 1,133, cargo fmt, Flutter analyze (0), Harness 100/100, JSON/diff. PR CI `42346270441` and Platform Availability `42346265567` passed; Linux/Windows/macOS Intel x64 lanes and all three packages succeeded. macOS ZIP SHA-256 `08d70b5f79b0ba19845180781c452ffface11f370a1a8b57ce25b5172f262c4b` matched sidecar and 76 entries passed integrity; macOS DnD remains explicitly skipped for unavailable hosted pointer routing. Full evidence and GitNexus limits are in `docs/diagnostics/2026-11-07-p05/p05.24-panel-alignment-scope.md`.
- P05.25 / feat-077 / LAY-05d Panel maximize/restore is complete at `c456374` plus format-noise cleanup `1188cdf`. Local full DoD, PR CI `42351275970`, and Linux/Windows/macOS Intel x64 Platform Availability `42351272135` passed. Full implementation and graph-coverage limitations are recorded in `docs/diagnostics/2026-11-07-p05/p05.25-panel-maximize-restore-scope.md`. `WorkbenchGrid`/`workbench_page.dart` remain UNKNOWN because of the file-size cap; `WbSplit` remains HIGH/lower-bound. Keep those risks active.
- P05.26 / feat-078 / LAY-05e is complete at product commit `71b2a03`. Focused tests 44/44 and full local DoD passed (Rust 71+54, Clippy, build_core, Flutter 1,145, cargo fmt, Flutter analyze 0, Harness 100/100, JSON/diff). PR CI `42356533251` and Platform Availability `42356528682` attempt 2 passed; Linux/Windows native DnD passed, hosted macOS DnD explicitly skipped for unavailable pointer routing. macOS artifact `13569481669`; ZIP SHA-256 `982a268a7f81c209686751b4829c76509d5d25670654763b7bcfbc62dc9cee12` matched sidecar and all 76 entries passed integrity. Full evidence and graph limitations: `docs/diagnostics/2026-11-07-p05/p05.26-panel-minimum-size-scope.md`. P05 remains in progress.
- P05.27 / LAY-06b is closed with local and hosted evidence. `WbSplit.resetDivider` preserves non-adjacent sibling extents and fixed/collapsed weights, meets recursive minima, and writes equalized proportions. `_Divider` uses raw pointer tap tracking around the existing drag recognizer to preserve drag behavior. Panel alignment projection and root JSON persistence are covered by tests.
- GitNexus was refreshed at P05.26 product head `71b2a03` (11,523 nodes, 28,160 edges, 347 clusters, 430 reported flows). P05.26 `WbSplit`/`WbLeaf` HIGH/lower-bound and helper/renderer UNKNOWN results remain active. The analyzer skips >512 KiB `workbench_page.dart`, reports 847 cross-language property sites and incomplete flow discovery; do not treat empty/UNKNOWN or missing flows as safe. P05.26 pre-commit all-scope mapping and compare-to-main CRITICAL results are documented in its scope report; all-scope hits are documentation mapping noise, not product source changes.
- Prior P05 platform evidence is for Linux/Windows/macOS Intel x64 hosted runners. Hosted macOS DnD pointer injection is unavailable and remains an explicit skip; Apple Silicon and physical-device checks are not implied.

## Blockers

- None currently require user action.

## Next Step

1. Verify final evidence file updates, run GitNexus all-scope and compare-to-main, then commit/push P05.27 evidence to PR #3.
2. Register the next remaining P05 LAY/CMD matrix slice before touching its product code; continue one item at a time.
3. Keep PR #3 draft/open and P05/feat-027 in-progress until all matrix DoDs pass. Do not merge.
