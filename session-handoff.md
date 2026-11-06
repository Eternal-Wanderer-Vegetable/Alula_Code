# Session Handoff

## Last Updated

2026-11-07. User requested a new branch, open PR, and completion of P05. Branch `codex/vscode-parity-p05` is pushed; draft PR #3 targets `main`: https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/pull/3. P05.1–P05.15 / feat-053–067 are complete; P05.16 / feat-068 is registered and in progress. P05 and the full LAY/CMD matrix remain open.

## Current Objective

Complete P05 one registered feature at a time. `docs/03-里程碑计划与验收标准.md` is the state/DoD authority; `docs/11-VSCode功能对照矩阵.md` is the requirement matrix. Current item P05.16 / LAY-03g implements Activity Bar badges and per-view badge visibility. After it is complete, register Accounts/Manage as a separate child; do not skip to LAY-04 until the LAY-03 matrix row is covered. Keep PR #3 draft/open and do not mark P05 done until all LAY/CMD requirements pass.

## Worktree and Branch

- Worktree: `/tmp/alula-p04.70-next`; branch: `codex/vscode-parity-p05`; current committed head: `813c2f8`.
- The original `/mnt/e/alula_code` worktree contains unrelated user changes; do not modify or clean it.
- P05.15 product/evidence commits and macOS LaunchServices/bundle fixes are pushed. The P05.16 registration changes are staged in `docs/03-里程碑计划与验收标准.md`, `docs/diagnostics/2026-11-07-p05/p05.16-activity-bar-badge-scope.md`, `feature_list.json`, `progress.md`, and this file. JSON/diff checks passed. Repeated docs-only all-scope results varied between 5 files without symbol overlap (not clean) and 5 files / 1 symbol / 410 processes CRITICAL; compare-to-main varied across 92 files / 39–42 symbols / 410–417 processes CRITICAL. The all-scope graph maps progress text to unrelated code flows. Details are in the scope report. Commit and push this registration, then await its PR CI.
- Latest docs-head PR CI `42253151367` passed all four jobs. Code-head PR CI `42247690393` and Platform Availability `42247679502` passed. Linux/Windows DnD passed; macOS hosted DnD explicitly skipped because pointer events were not routed to Flutter. macOS hosted package SHA/integrity and native Quit evidence are in the P05.15 scope report.
- PR #3 is OPEN/draft. User authorized pushing this branch; do not merge it.

## P05.16 Scope

- Fixed source: Code-OSS 1.145.0 commit `4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e`.
- Add number/icon/progress badge presentation and accessible descriptions, Show/Hide Badge on each view's right-click menu, and root layout JSON persistence. No provider means no fabricated badge data. Accounts/Manage belong to the separate Global Composite Bar and are excluded from this feature.
- Full source, scope, acceptance, and graph results are recorded in `docs/diagnostics/2026-11-07-p05/p05.16-activity-bar-badge-scope.md`.

## Validation and Constraints

- P05.15 local full `init.sh` passed Rust 71+54, Clippy, `build_core`, Flutter 1,083/1,083; cargo fmt, Flutter analyze (0 issues), focused ActivityBar tests, Harness 100/100, JSON and diff checks passed.
- Do not run local desktop GUI/Narrator tests. The user warned that this can trigger Narrator. Use tests and hosted lanes.
- User deferred the 500 MiB target until architecture replication is complete. The user also said no local macOS device is available; hosted macOS Intel x64 package/build is evidence only, with device/Apple Silicon checks retained for P15.

## GitNexus

- Repository binding: `Alula_Code` at `/tmp/alula-p04.70-next`; index/HEAD `813c2f8` before these docs changes.
- `impact ActivityBar` and `_ActivityBarState` report UNKNOWN/0 because production assembly lives in `workbench_page.dart` (>512 KiB, skipped by the graph). Text search confirms the production constructor call; do not treat UNKNOWN as unused.
- `_viewItem` reports CRITICAL (57–88 edges, 3 processes) with unrelated bulk-edit/`_tokenize` mappings and a callable-value lower-bound. Keep this alert unresolved; scope report records exact commands and text corroboration. Do not use `riskSharedAxes` to waive it.
- Registration scan: repeated all-scope results vary between no symbol overlap (not clean) and a `progress.md` section mapping to 410 unrelated processes; compare-to-main varies across 39–42 symbols and 410–417 processes over 92 cumulative files (CRITICAL). The scope report preserves this variability.
- The index skips large/cross-language regions and process candidates. Before code edits, rerun exact impact/context and inspect text callers; before commits run `detect-changes --scope all` and `--scope compare --base-ref main`, preserving broad risks and scan flags rather than calling them clean.

## Next Steps

1. Run the final pre-commit scans and commit/push the P05.16 registration docs/tracker update.
2. Re-run GitNexus impact on the exact Activity Bar/layout model symbols before code edits; record UNKNOWN/CRITICAL and confine changes to this slice.
3. Implement badge presentation, per-view Hide/Show behavior, and persistence with focused tests; then run full local DoD and hosted PR/platform lanes.
4. Record completion evidence in `docs/03`, `feature_list.json`, `progress.md`, scope report, and this handoff; commit and push. Only then register the next P05 child.
