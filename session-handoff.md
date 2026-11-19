# Session Handoff

Last Updated: 2026-11-19

## Current Objective

Continue PR #3, one P05 feature at a time. P05.99 / feat-151 is complete; select the next dependency-satisfied P05 slice from `docs/03-里程碑计划与验收标准.md` and `feature_list.json`. Keep PR #3 OPEN/DRAFT; do not merge.

## Current State

- Dedicated worktree: `/home/vegetable/.codex/worktrees/pr3-20261119`, branch `codex/p05-95-breadcrumb-with-picker`. The fetched PR branch `origin/codex/vscode-parity-p05` matched HEAD `9426cca2eec9048ef29caec2a0501dbe74a2eaf` before the current P05.99 changes. Re-fetch and compare before pushing because other contributors may update the PR. Do not modify `/mnt/e/alula_code`, which has unrelated dirty/untracked work.
- User explicitly chose a window/group-only focus channel. Focus messages/snapshots must not include document identity, body, selection, dirty/savepoint, or session. Document move/restore payloads are outside P05.99.
- Root cause: `desktop_multi_window` 0.3.1 requires a child-window-created callback to register generated plugins in each engine. Linux native smoke first reproduced the missing `window_manager.ensureInitialized` implementation. Runner callbacks are now added for Linux, Windows and macOS.
- Linux native smoke passes with the real `WorkbenchPage` and `AuxiliaryEditorApp`: auxiliary → main → auxiliary → main, revisions 2–5; snapshot keys only `groupId`, `revision`, `windowId`; document sentinel absent. Evidence: `docs/diagnostics/2026-11-19-p05/p05.99-linux-native-focus/`.
- Full local N.2 passed after the implementation: `FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` (Rust workspace, Clippy `-D warnings`, core build, Flutter 1,563 passed / 2 skipped), `cargo fmt --all -- --check`, full `flutter analyze --no-pub`, and focused auxiliary focus/window tests 16/16.
- Exact-SHA PR CI `44524110062` passed all four jobs (Flutter 1,563 passed / 2 skipped, analyze clean). Platform Availability `44524100180` Linux/Windows jobs passed, including both native focus smokes; macOS Release build compiled the callback, but the overall macOS job failed in existing native DnD pointer-route and native Quit checks. Do not claim native macOS focus. Linux/Windows focus artifacts and macOS diagnostics/build artifact IDs/digests are in the P05.99 scope report.
- GitNexus product scan: 10 files / 7 symbols / 0 flows / LOW. Final docs-closeout scan maps 6 files / 1 section symbol / 1 MEDIUM `InitState → Hunk` documentation mapping, not runtime. Compare-main is cumulative PR scope (762 files / 79 flows / CRITICAL; repeated symbol counts 1,274–1,355; listing capped), not attributable to this slice. Latest index snapshot before handoff edits: 13,368 nodes / 31,094 edges / 435 clusters / 431 flows. `workbench_page.dart` (>512 KiB) omitted, FTS build failed, and cross-language/process-candidate coverage incomplete. Do not call the graph clean.
- P05.99 product commit `6b4e6dd7c934f1e5c7d35a05fbf8abda75d74554` is pushed. Docs-only hosted closeout remains to commit/push. PR #3 was verified OPEN/unmerged/draft and its description now includes P05.99 hosted status.

## Next Session First Step

1. Commit and push the current P05.99 hosted-evidence closeout after final diff/graph checks; re-fetch first to avoid overwriting contributor updates.
2. Review remaining P05 scope and select exactly one dependency-satisfied child feature. Keep the P05 parent in progress and PR #3 OPEN/DRAFT.
3. Do not modify the original `/mnt/e/alula_code` dirty checkout.
