# Session Handoff

## Last Updated

2026-11-07. User requested a new branch, open PR, and completion of P05. Branch `codex/vscode-parity-p05` is pushed; draft PR #3 targets `main`: https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/pull/3. P05.1–P05.15 / feat-053–067 are complete. P05.16 / feat-068 is locally implemented and passed local DoD; product commit/push and hosted CI/platform evidence remain. P05 and the full LAY/CMD matrix remain open.

## Current Objective

Complete P05 one registered feature at a time. `docs/03-里程碑计划与验收标准.md` is the state/DoD authority; `docs/11-VSCode功能对照矩阵.md` is the requirement matrix. Current item P05.16 / LAY-03g implements Activity Bar badges and per-view badge visibility. Product implementation and local DoD are complete; push it, wait for PR CI and hosted Linux/Windows/macOS Intel x64 validation, then record evidence and close feat-068. After that register Accounts/Manage as a separate child and continue through every remaining P05 LAY/CMD row. Keep PR #3 draft/open and do not mark P05 done until all LAY/CMD requirements pass.

## Worktree and Branch

- Worktree: `/tmp/alula-p04.70-next`; branch: `codex/vscode-parity-p05`; current committed head before this pending product change: `ec77f5e`.
- The original `/mnt/e/alula_code` worktree contains unrelated user changes; do not modify or clean it.
- P05.15 product/evidence commits and macOS LaunchServices/bundle fixes are pushed. P05.16 registration commit `ec77f5e` is pushed. Its PR CI run `42256920980` passed all four jobs. Product changes are currently uncommitted in ActivityBar/layout code and tests, with local evidence added to the P05.16 scope report and trackers.
- P05.15 code-head PR CI `42247690393` and Platform Availability `42247679502` passed. Linux/Windows DnD passed; macOS hosted DnD explicitly skipped because pointer events were not routed to Flutter. macOS hosted package SHA/integrity and native Quit evidence are in the P05.15 scope report.
- PR #3 is OPEN/draft. User authorized pushing this branch; do not merge it.

## P05.16 Scope

- Fixed source: Code-OSS 1.145.0 commit `4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e`.
- Add number/icon/progress badge presentation and accessible descriptions, Show/Hide Badge on each view's right-click menu, and root layout JSON persistence. No provider means no fabricated badge data. Accounts/Manage belong to the separate Global Composite Bar and are excluded from this feature.
- Full source, scope, acceptance, and graph results are recorded in `docs/diagnostics/2026-11-07-p05/p05.16-activity-bar-badge-scope.md`.

## Validation and Constraints

- P05.16 local focused ActivityBar/layout/persistence suites passed 43/43. Full `bash init.sh` passed Rust workspace tests, Clippy, `build_core`, and Flutter 1,089/1,089; `flutter analyze` reported no issues. Final P05.16 GitNexus workspace scan was all-scope 10 files / 13 symbols / 417 processes CRITICAL; compare-to-main was 92 / 48 / 417 CRITICAL. Name-mapping noise and graph limits remain in the scope report. Run cargo fmt and JSON checks before product commit.
- Do not run local desktop GUI/Narrator tests. The user warned that this can trigger Narrator. Use tests and hosted lanes.
- User deferred the 500 MiB target until architecture replication is complete. The user also said no local macOS device is available; hosted macOS Intel x64 package/build is evidence only, with device/Apple Silicon checks retained for P15.

## GitNexus

- Repository binding: `Alula_Code` at `/tmp/alula-p04.70-next`; fresh index content based on `ec77f5e` plus current ActivityBar/layout source edits, 11,575 nodes / 34,407 edges / 340 clusters / 425 flows.
- `impact ActivityBar` and `_ActivityBarState` report UNKNOWN/0 because production assembly lives in `workbench_page.dart` (>512 KiB, skipped by the graph). Text search confirms the production constructor call; do not treat UNKNOWN as unused.
- `_viewItem` reports CRITICAL (57–88 edges, 3 processes) with unrelated bulk-edit/`_tokenize` mappings and a callable-value lower-bound. Keep this alert unresolved; scope report records exact commands and text corroboration. Do not use `riskSharedAxes` to waive it.
- Final P05.16 `detect-changes` reported all-scope 10 files / 13 symbols / 417 processes CRITICAL; compare-to-main 92 files / 48 symbols / 417 processes CRITICAL. Flow listings map badge names to unrelated `_match`, `_parseUnary`, `_tokenize`, LSP and editor flows. Report preserves counts and noise. Graph skips `workbench_page.dart` (>512 KiB), 800 cross-language property sites, and many process candidates. Pre-edit `_viewItem` CRITICAL and ActivityBar UNKNOWN remain unresolved.
- Before each later feature edit, rerun impact/context and inspect text callers; before each commit run all-scope and compare-to-main scans, preserving broad risks and scan flags rather than calling them clean.

## Next Steps

1. Run `cargo fmt --all -- --check`, JSON/diff checks, then commit and push P05.16 product/tests/local evidence.
2. Wait for PR CI and Platform Availability on the pushed product SHA; resolve any failures and record actual Linux/Windows/macOS Intel x64 package/launch evidence. Do not run local GUI/Narrator tests.
3. Update `docs/03`, `feature_list.json`, `progress.md`, scope report, and handoff with hosted results; commit and push the evidence update.
4. Register Accounts/Manage as the next P05 feature, then continue single-feature slices through all remaining LAY/CMD requirements. Do not merge PR #3 or mark P05 done early.
