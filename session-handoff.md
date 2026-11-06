# Session Handoff

## Last Updated

2026-11-07. User requested a new branch, an open PR, and completion of P05. Branch `codex/vscode-parity-p05` is pushed; draft PR #3 targets `main`: https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/pull/3. P05.1–P05.14 / feat-053–066 are complete. P05.15 / feat-067 / LAY-03f is implemented and passed local DoD, but the latest macOS hosted lane exposed two launch-path issues. P05 and all LAY/CMD matrix requirements remain open.

## Current Objective

Finish P05 sequentially, following `docs/03-里程碑计划与验收标准.md` as the sole status/DoD authority. Current item is P05.15 Activity Bar Keep/Hide and pin persistence. After its hosted evidence is complete, select exactly one next unfinished P05 matrix item and continue. Keep PR #3 draft/open until all P05 LAY/CMD requirements pass. Do not merge or declare P05 complete early.

## Worktree and Branch

- Worktree: `/tmp/alula-p04.70-next`; branch: `codex/vscode-parity-p05`.
- The original `/mnt/e/alula_code` worktree contains unrelated user changes; do not modify or clean it.
- Product commit `7def397` implements P05.15 and is pushed. CI fix commit `dcf69e0` is pushed. Current uncommitted change is a follow-up macOS validation fix: use an absolute app-bundle path for native Quit and change the invalid macOS bundle ID from `com.alula.alula_app` to `com.alula.alula-app`; related scope/DoD/progress evidence has been updated.
- PR CI `42239892251` passed. Platform Availability `42239881628`: Linux and Windows x64 passed; macOS analyze/tests, Release build, clipboard, and regular launch passed. The macOS DnD integration test stopped at Flutter `open returned 1` before pointer-route diagnostics. The native Quit step failed because LaunchServices received a relative app bundle path. Scope report has exact evidence and distinguishes unverified paths.

## Local Validation and Constraints

- `bash init.sh --fast` passed at current P05.15 source: Rust 71+54, Clippy, `build_core`, and Flutter 1,083/1,083.
- Earlier full P05.15 validation also passed `cargo fmt`, Flutter analyze (0 issues), focused ActivityBar tests, Harness (100/100), JSON and diff checks.
- Do not run local desktop GUI/Narrator tests. No local macOS/Xcode/Swift environment is available; use hosted runners.
- User deferred the numeric 500 MiB target until architecture replication is complete.
- User authorized pushing this branch. Keep the PR draft/open.

## GitNexus

Current index was refreshed at commit `dcf69e0`: 11,252 nodes / 32,506 edges / 341 clusters / 425 flows. Pre-edit impact for `quitThroughNativeMenu` is CRITICAL (58 upstream, 57 direct, 3 processes, 6 modules) with a callable-value boundary; graph entries include unrelated Dart flows. Exact text search confirmed the workflow is the real CLI entry. `PRODUCT_BUNDLE_IDENTIFIER` is not indexed (UNKNOWN); text search confirms `AppInfo.xcconfig` supplies the value referenced by Runner `Info.plist`. Preserve CRITICAL/UNKNOWN and analyzer coverage limits. Before committing, refresh and run GitNexus `detect-changes --scope all` plus `--scope compare --base-ref main`; do not claim a clean graph if it reports broad risks.

## Next Steps

1. Finish the P05.15 scope report, `docs/03`, `progress.md`, and this handoff for the path/Bundle ID fix.
2. Validate YAML, bundle-ID character constraints, and `git diff --check`; refresh GitNexus and record all/compare scans.
3. Commit and push the follow-up fix; wait for PR CI and Platform Availability. Confirm the macOS DnD test either reaches its explicit hosted pointer-route skip or passes, then verify native Quit, package ZIP/hash, and artifact evidence.
4. Only when P05.15 DoD is met, mark its trackers complete and select the next unfinished LAY/CMD item from `docs/03`. Continue one scoped item at a time.
