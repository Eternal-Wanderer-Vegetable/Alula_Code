# Session Handoff

## Last Updated

2026-11-06. User requested a new branch, an open PR, and completion of P05. Branch codex/vscode-parity-p05 is pushed; draft PR #3 targets main: https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/pull/3. P05.1–P05.14 / feat-053–066 are complete. P05.15 / feat-067 local implementation and full local DoD passed; final product commit and hosted PR/platform evidence are pending. P05 remains open until all LAY and CMD matrix DoDs pass.

## Current Objective

Continue the P05 architecture replication. P05.14 / feat-066 is complete. Current item P05.15 / feat-067 / LAY-03f has local implementation and full local DoD complete: root layout pin persistence, migration/normalization, Keep/Hide menus, active-unpinned visibility, last-pin guard, keyboard order, and remount tests. Registration commit b556ad3 is pushed; product changes are currently uncommitted. Scope and evidence are in docs/diagnostics/2026-11-06-p05/p05.15-activity-bar-pin-context-scope.md. Next: run final GitNexus change scans, commit the product phase, push, and collect final PR CI and Linux/Windows/macOS hosted validation. Keep PR #3 draft/open until P05 is complete.

## Current Branch State

- Worktree: /tmp/alula-p04.70-next. The original /mnt/e/alula_code worktree contains unrelated user changes; do not modify or clean it.
- Branch codex/vscode-parity-p05, product commit 7def397; current CI fix is uncommitted. P05.15 local full DoD and PR CI 42229440013 passed. Platform Availability 42229430615 Linux/Windows passed; macOS native Quit failed twice. P05.14 prior PR CI 42216043944 and Platform Availability 42216038049 passed.
- P05.14 local verification: ActivityBar widget 9/9, layout model 21/21, order integration 1/1; full init.sh passed Rust 71+54, Clippy, build_core and Flutter 1,076/1,076; cargo fmt, Flutter analyze (0 issues), diff check, and Harness 100/100 passed.
- Hosted evidence: Linux/Windows/macOS Intel x64 build/test/launch/package passed; Linux/Windows native move/copy/external-text DnD passed. macOS native clipboard and System Events Quit passed. Hosted macOS DnD artifact 13503490499 explicitly records that synthetic pointer events did not reach Flutter and is a skip. macOS app ZIP artifact 13503042243 has SHA-256 f1502651f4c1b17d482a9612b1f2bdb150359367bd4901390adab8479daa956d matching its sidecar digest; unzip integrity passed. Full report: docs/diagnostics/2026-11-06-p05/p05.14-activity-bar-reorder-scope.md.
- PR #3 remains draft/open; do not merge or mark P05 complete until all P05 matrix items pass.
- P05.15 pre-edit GitNexus: ActivityBar UNKNOWN/0 resolved callers, production caller text-confirmed at workbench_page.dart:16884 (large file skipped); WbSplit MEDIUM lower-bound, 14 total/11 direct with dynamic dispatch boundary. No HIGH/CRITICAL warning. Keep these limits in scope and commit records.
- Do not run local desktop GUI/Narrator tests. The 500 MiB optimization target remains deferred until architectural replication is complete.

## GitNexus Boundaries

GitNexus was refreshed after the P05.15 implementation against current source (HEAD b556ad3): 11,209 nodes / 31,449 edges / 341 clusters / 425 flows. It skips workbench_page.dart (>512 KiB), reports 799 cross-language property sites and flow-trace truncation (933 of 1,133 entry candidates dropped, 325 callees skipped, 14 budget-cut walks); missing callers/flows are not proof of no impact. P05.14 pre-edit ActivityBar impact was UNKNOWN because its production workbench assembly is in the skipped file; WbSplit was MEDIUM lower-bound. Product scans were MEDIUM for all-scope and CRITICAL compare-to-main due cumulative P05 history and existing unrelated flow mappings. Preserve these limits; no scan is described as clean. Before the next code edit, refresh status, run impact on its target, inspect relevant execution flows where available, and check for HIGH/CRITICAL/UNKNOWN.

## Blockers / Limits

- No local macOS hardware or native-device access. The hosted macOS lane is Intel x64; Apple Silicon and device behavior remain unverified.
- Hosted macOS synthetic pointer events did not reach Flutter, so the native DnD case is explicitly skipped. Linux and Windows native DnD passed.
- Do not launch local desktop GUI/Narrator tests. The 500 MiB optimization target remains deferred until architecture replication is complete.

## Files

- P05.14 implementation and tests: app/lib/workbench/activity_bar.dart, app/lib/workbench/activity_bar_order.dart, app/lib/workbench/layout_model.dart, app/lib/workbench/workbench_page.dart, app/test/activity_bar_test.dart, app/test/activity_bar_order_integration_test.dart, app/test/layout_model_test.dart.
- P05.14 evidence/state: docs/03-里程碑计划与验收标准.md, docs/diagnostics/2026-11-06-p05/p05.14-activity-bar-reorder-scope.md, docs/diagnostics/2026-11-06-p05/p05.14-local-validation.txt, feature_list.json, progress.md, session-handoff.md.
- P05.15 product: app/lib/workbench/activity_bar.dart, activity_bar_pins.dart, layout_model.dart, workbench_page.dart; app/test/activity_bar_test.dart, layout_model_test.dart, activity_bar_pin_integration_test.dart. CI fix: .github/workflows/platform-availability.yml and tools/vscode-parity/macos-native-dnd-input.swift. Scope/local/hosted evidence and trackers: docs/03-里程碑计划与验收标准.md, docs/diagnostics/2026-11-06-p05/p05.15-activity-bar-pin-context-scope.md, feature_list.json, progress.md, session-handoff.md.

## Next Step

First complete P05.15 final GitNexus all/compare scans, product commit and push; then verify final PR CI and Linux/Windows/macOS hosted build/test/launch/package (record any hosted macOS DnD pointer-route skip without claiming native P15 validation). After P05.15 evidence is complete, select/register exactly one next unfinished P05 child from docs/03 and continue sequentially. Do not run local desktop GUI/Narrator.
