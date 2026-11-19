# Session Handoff

Last Updated: 2026-11-19

## Current Objective

Continue P05 on PR #3 one feature at a time. Current slice is P05.98 / feat-150. `docs/03-里程碑计划与验收标准.md` and `feature_list.json` are authoritative. Keep PR #3 OPEN/DRAFT; do not merge.

## Current State

- Worktree: `/home/vegetable/.codex/worktrees/pr3-20261119`; original `/mnt/e/alula_code` checkout remains untouched.
- P05.97 / feat-149 is complete. Product commit `960da3163d068ff85255a066c7717d7346de632d` is pushed to PR head branch `codex/vscode-parity-p05`.
- Local validation: `bash init.sh` passed (Rust workspace, Clippy `-D warnings`, core build, Flutter 1,560 passed / 2 skipped); forced native ICU4X collation vectors 17/17; Linux release build passed. Controlled Linux three-document memory samples are recorded in `docs/diagnostics/2026-11-19-p05/p05.97-memory-comparison.md`.
- Exact-SHA PR CI `44501865076` passed all four jobs. Platform Availability `44501856661` passed Linux x64 and Windows x64, including native ICU4X collation, clipboard, DnD, package and launch checks. Artifact IDs and digests are in `docs/diagnostics/2026-11-19-p05/p05.97-hosted-verification.json`.
- At evidence capture, the macOS hosted job remained in Flutter analyze/tests and was not awaited. There is no macOS device; no macOS result is claimed.
- GitNexus product-diff scans reported 7 symbols / 15 changed files, while flow mapping varied between no mapped processes / LOW and an `InitState → Hunk` flow / MEDIUM. The latest docs-only staged scan reported 7 files / 1 section symbol / 1 MEDIUM flow by mapping the “Blockers / Limits” heading in this handoff to `InitState → Hunk`; that is a documentation mapping, not a runtime impact. `workbench_page.dart` exceeds the 512 KiB limit; process candidate ranking and FTS coverage are incomplete. Keep UNKNOWN and graph coverage limitations unresolved; do not call it clean. Details are in the P05.97 scope report.
- PR #3 is OPEN/DRAFT, head `eefe3a321f9be35a5b68ccb499193c010ea5cb4c`; do not merge.
- User-selected LAY-12b focus channel remains limited to active window/group identifiers. Do not sync document identity, contents, selection, dirty state, or session across auxiliary windows.
- P05 parent remains in progress. P05.97 closes only the alphabetical Open Editors sort slice.
- P05.98 / feat-150 is the only active slice. The worktree implementation turns the nonzero Open Editors dirty count into a labeled, keyboard-focusable action; it scans layout leaves and each group's document order, then reuses `_activateOpenEditorsRow`. Zero count stays hidden. Focused `open_editors_view_test.dart` passes 10/10, covering pointer, Enter/Space, semantics, collapsed state, ordering, and post-flush document/disk snapshots. Full local N.2 gates passed: `bash init.sh` Flutter 1,563 passed / 2 skipped, Rust workspace/Clippy/core passed, `cargo fmt --all -- --check` passed, and `flutter analyze --no-pub` reported 0 issues. Exact-SHA hosted Linux/Windows closeout remains pending. Acceptance and reference are in `docs/diagnostics/2026-11-19-p05/p05.98-open-editors-dirty-counter-scope.md`. GitNexus impacts for `_buildOpenEditorsSection`, `_activateOpenEditorsRow`, and `WorkbenchPage` were UNKNOWN/target-not-found because the >512 KiB Workbench file is omitted; retain this graph limitation.

## Blockers / Limits

- No macOS device is available; keep native macOS interaction and visual gaps unverified and continue with local plus hosted Linux/Windows gates.
- GitNexus FTS/flow coverage is incomplete; retain UNKNOWN and incomplete-index warnings.

## Next Session First Step

1. Review the fresh GitNexus all-scope and capped compare-main results in the P05.98 report, fetch the PR branch to catch concurrent updates, then commit/push the validated slice. Collect exact-SHA CI plus Linux/Windows Platform Availability, update evidence and keep PR #3 OPEN/DRAFT; preserve the macOS limitation.
