# Session Handoff

Last Updated: 2026-11-19

## Current Objective

Continue PR #3, one P05 feature at a time. Current slice: P05.99 / feat-151, auxiliary-window native focus handoff smoke. `docs/03-里程碑计划与验收标准.md` and `feature_list.json` are authoritative. Keep PR #3 OPEN/DRAFT; do not merge.

## Current State

- Dedicated worktree: `/home/vegetable/.codex/worktrees/pr3-20261119`, branch `codex/p05-95-breadcrumb-with-picker`. The fetched PR branch `origin/codex/vscode-parity-p05` matched HEAD `9426cca2eec9048ef29caec2a0501dbe74a2eaf` before the current P05.99 changes. Re-fetch and compare before pushing because other contributors may update the PR. Do not modify `/mnt/e/alula_code`, which has unrelated dirty/untracked work.
- User explicitly chose a window/group-only focus channel. Focus messages/snapshots must not include document identity, body, selection, dirty/savepoint, or session. Document move/restore payloads are outside P05.99.
- Root cause: `desktop_multi_window` 0.3.1 requires a child-window-created callback to register generated plugins in each engine. Linux native smoke first reproduced the missing `window_manager.ensureInitialized` implementation. Runner callbacks are now added for Linux, Windows and macOS.
- Linux native smoke passes with the real `WorkbenchPage` and `AuxiliaryEditorApp`: auxiliary → main → auxiliary → main, revisions 2–5; snapshot keys only `groupId`, `revision`, `windowId`; document sentinel absent. Evidence: `docs/diagnostics/2026-11-19-p05/p05.99-linux-native-focus/`.
- Full local N.2 passed after the implementation: `FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` (Rust workspace, Clippy `-D warnings`, core build, Flutter 1,563 passed / 2 skipped), `cargo fmt --all -- --check`, full `flutter analyze --no-pub`, and focused auxiliary focus/window tests 16/16.
- Windows hosted native smoke and exact-SHA PR/Platform Availability workflows have not run yet. Do not mark feat-151 done until Windows smoke and required hosted gates pass. macOS native focus behavior remains unverified; no device is available.
- GitNexus index refreshed after source and documentation changes: 13,367 nodes / 30,800 edges / 435 clusters / 431 flows. `workbench_page.dart` (>512 KiB) is omitted, FTS build failed, and cross-language/process-candidate coverage is incomplete. Preserve UNKNOWN/coverage limits; do not call scans clean. Scope and pre-edit review are in `docs/diagnostics/2026-11-19-p05/p05.99-auxiliary-focus-native-smoke-scope.md`.
- Current uncommitted work includes native runners, the focused smoke fixture/driver and CI job, plus P05.99 scope/state docs and local Linux evidence. PR metadata was verified OPEN, unmerged and draft.

## Next Session First Step

1. Read this handoff and `progress.md`, check `git status`, fetch the PR branch, and confirm it still equals the expected base before staging. Refresh GitNexus status, then complete required all-scope change detection (and compare-main scan), retaining partial/truncated/UNKNOWN warnings.
2. Review the complete diff and local evidence. Commit and push only if the remote PR head is unchanged; otherwise reconcile the newer contributor work without overwriting it.
3. Follow the exact pushed SHA's PR CI and Platform Availability Linux/Windows runs, inspect uploaded diagnostics, fix any failures, and record run/artifact IDs and digests. Keep feat-151 in progress until those gates pass; do not claim macOS native focus.
4. Keep PR #3 OPEN/DRAFT and do not merge. Update `docs/03`, `feature_list.json`, `progress.md`, this handoff and the scope report with verified hosted results.
