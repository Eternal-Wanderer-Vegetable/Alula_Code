# Session Handoff

Last Updated: 2026-11-07

## Current Objective

Finish P05 / `feat-027` one registered feature at a time. The user asked for a new branch, an open PR, and completion of P05. Keep PR #3 draft/open; do not merge or mark P05 complete until the remaining LAY/CMD requirements pass. `docs/03-里程碑计划与验收标准.md` is the task-state/DoD authority, `docs/11-VSCode功能对照矩阵.md` is the requirement matrix, and `feature_list.json` is the feature state machine.

## Current State

- Worktree: `/tmp/alula-p04.70-next`; branch: `codex/vscode-parity-p05`; PR #3: https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/pull/3 (draft, targets `main`). PR head `f876a5d` has product CI green.
- P05.1–P05.18 are complete; P05.19 / feat-071 / LAY-04b is registered, with no product edits yet. P05 and remaining LAY/CMD requirements remain open.
- P05.18 product commit `b3d2a78` and evidence commit `f876a5d` are on the branch. Product CI `42281213183`, docs-head CI `42285762655`, and Platform Availability `42281207384` all passed. Package IDs and caveats are in `docs/diagnostics/2026-11-07-p05/p05.18-secondary-sidebar-scope.md`.
- P05.19 scope: add primary side bar left/right toggle and persisted position; keep Activity Bar at the outer edge of the primary side and secondary side bar opposite. Fixed upstream is Code-OSS 1.145.0 commit `4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e`. Scope report: `docs/diagnostics/2026-11-07-p05/p05.19-sidebar-position-scope.md`.
- Pre-edit GitNexus ran on repository `Alula_Code` at `/tmp/alula-p04.70-next`, worktree branch `codex/vscode-parity-p05`, index `f876a5d`. `WbSplit` is CRITICAL/lower-bound; `defaultLayout` and `setActivityBarLocation` are CRITICAL; `ActivityBarLocation`, `WorkbenchLayout`, and `LayoutStore` are UNKNOWN. `workbench_page.dart` is over the graph's 512 KiB limit; source search confirmed its layout construction/loading and sidebar region consumers. Do not treat missing graph edges as clean.
- The original `/mnt/e/alula_code` worktree contains unrelated user changes; do not modify or clean it.

## Next Step

1. Finish the P05.19 scope-only registration commit: refresh GitNexus on the staged docs tree, run all and compare-to-main change scans, commit, push, and verify docs-head CI.
2. Implement only registered LAY-04b; test tree ordering/weights, Activity Bar modes, visibility/collapse, legacy JSON migration, persistence, command and Appearance-menu direction labels. Then run local DoD, commit/push, and wait for PR CI and Linux/Windows/macOS hosted evidence.
3. After P05.19 is evidenced, register the next single P05 requirement; keep PR #3 open/draft and do not merge.

No manual operation is currently required from the user.
