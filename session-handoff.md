# Session Handoff

## Last Updated

2026-11-06. User requested a new branch, an open PR, and completion of P05. Branch codex/vscode-parity-p05 is pushed; draft PR #3 targets main: https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/pull/3. P05.1–P05.14 / feat-053–066 are complete; P05.15 / feat-067 is registered and in progress. P05 remains open until all LAY and CMD matrix DoDs pass.

## Current Objective

Continue the P05 architecture replication. P05.14 / feat-066 / LAY-03e is complete. Current item: P05.15 / feat-067 / LAY-03f, Activity Bar view pin/unpin with Keep/Hide context menu and root layout JSON persistence. Scope and fixed source are in docs/diagnostics/2026-11-06-p05/p05.15-activity-bar-pin-context-scope.md. Product code has not been edited for P05.15 yet; next run the startup workflow and inspect current ActivityBar/layout APIs before implementation. Keep PR #3 draft/open until P05 is complete.

## Current Branch State

- Worktree: /tmp/alula-p04.70-next. The original /mnt/e/alula_code worktree contains unrelated user changes; do not modify or clean it.
- Branch codex/vscode-parity-p05, product head 7dc0326. PR CI 42216043944 and Platform Availability 42216038049 passed.
- P05.14 local verification: ActivityBar widget 9/9, layout model 21/21, order integration 1/1; full init.sh passed Rust 71+54, Clippy, build_core and Flutter 1,076/1,076; cargo fmt, Flutter analyze (0 issues), diff check, and Harness 100/100 passed.
- Hosted evidence: Linux/Windows/macOS Intel x64 build/test/launch/package passed; Linux/Windows native move/copy/external-text DnD passed. macOS native clipboard and System Events Quit passed. Hosted macOS DnD artifact 13503490499 explicitly records that synthetic pointer events did not reach Flutter and is a skip. macOS app ZIP artifact 13503042243 has SHA-256 f1502651f4c1b17d482a9612b1f2bdb150359367bd4901390adab8479daa956d matching its sidecar digest; unzip integrity passed. Full report: docs/diagnostics/2026-11-06-p05/p05.14-activity-bar-reorder-scope.md.
- PR #3 remains draft/open; do not merge or mark P05 complete until all P05 matrix items pass.
- P05.15 pre-edit GitNexus: ActivityBar UNKNOWN/0 resolved callers, production caller text-confirmed at workbench_page.dart:16884 (large file skipped); WbSplit MEDIUM lower-bound, 14 total/11 direct with dynamic dispatch boundary. No HIGH/CRITICAL warning. Keep these limits in scope and commit records.
- Do not run local desktop GUI/Narrator tests. The 500 MiB optimization target remains deferred until architectural replication is complete.

## GitNexus Boundaries

The current GitNexus index was refreshed at product head 7dc0326. It skips workbench_page.dart (>512 KiB), reports 795 cross-language property sites and flow-trace truncation; missing callers/flows are not proof of no impact. P05.14 pre-edit ActivityBar impact was UNKNOWN because its production workbench assembly is in the skipped file; WbSplit was MEDIUM lower-bound. Product scans were MEDIUM for all-scope and CRITICAL compare-to-main due cumulative P05 history and existing unrelated flow mappings. Preserve these limits; no scan is described as clean. Before the next code edit, refresh status, run impact on its target, inspect relevant execution flows where available, and check for HIGH/CRITICAL/UNKNOWN.

## Blockers / Limits

- No local macOS hardware or native-device access. The hosted macOS lane is Intel x64; Apple Silicon and device behavior remain unverified.
- Hosted macOS synthetic pointer events did not reach Flutter, so the native DnD case is explicitly skipped. Linux and Windows native DnD passed.
- Do not launch local desktop GUI/Narrator tests. The 500 MiB optimization target remains deferred until architecture replication is complete.

## Files

- P05.14 implementation and tests: app/lib/workbench/activity_bar.dart, app/lib/workbench/activity_bar_order.dart, app/lib/workbench/layout_model.dart, app/lib/workbench/workbench_page.dart, app/test/activity_bar_test.dart, app/test/activity_bar_order_integration_test.dart, app/test/layout_model_test.dart.
- P05.14 evidence/state: docs/03-里程碑计划与验收标准.md, docs/diagnostics/2026-11-06-p05/p05.14-activity-bar-reorder-scope.md, docs/diagnostics/2026-11-06-p05/p05.14-local-validation.txt, feature_list.json, progress.md, session-handoff.md.
- P05.15 registration: docs/03-里程碑计划与验收标准.md, docs/diagnostics/2026-11-06-p05/p05.15-activity-bar-pin-context-scope.md, p05.15-pre-edit-*.txt, feature_list.json, progress.md, session-handoff.md. Final registration all-scope LOW (4 files/4 symbols/0 processes); compare-to-main CRITICAL is cumulative P05 (83/160/18), no partial/truncated status reported.

## Next Step

Run the startup workflow in AGENTS.md, select and register one unfinished P05 child using docs/03 as the status authority, then continue without starting a second feature in parallel.
