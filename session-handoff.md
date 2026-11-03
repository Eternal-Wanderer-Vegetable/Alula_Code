# Session Handoff

> Last Updated: 2026-11-04. P04.103 / EDT-17k is complete and pushed; P04.104 / EDT-17l is registered and implementation is in progress. PR #2 remains OPEN/draft.

## Current Objective

Continue P04 / feat-026 toward fixed-version VS Code editor and Git Diff parity. Current slice P04.104 delivers conservative inline folding for unchanged Git diff context. P04.103's default-off moved-block presentation for side-by-side Git diffs is complete. The 500 MiB numeric memory target remains deferred to P14.

## Current Slice: P04.104 / EDT-17l

- Implement inline unchanged-region folding only, off by default, using pinned Code-OSS 1.145.0 defaults: preserve 3 context rows on either side, require at least 3 hidden rows, reveal at most 20 per action.
- Fold only within one hunk between changed runs; preserve leading/trailing context and all metadata, markers and changed rows. Strict source mapping failure disables folding. Navigation must target visible projected rows.
- Patch update clears reveal state. No Rust/ABI/parser/side-by-side/persistence/P14 changes.
- Registration and pinned reference: `docs/diagnostics/2026-11-04-p04/p04.104-inline-unchanged-regions.md`; `docs/03-里程碑计划与验收标准.md` is authoritative for DoD.
- GitNexus `GitDiffPatchView` impact remains UNKNOWN with zero resolved callers. Exact text search confirmed one workbench product instance; preserve the unresolved graph risk.

## Latest Slice: P04.103 / EDT-17k

- Strictly maps P04.102 moved-block source rows into projected side-by-side rows. Any missing, duplicate, out-of-range, mismatched, non-contiguous, or overlapping mapping suppresses every moved decoration.
- The per-view toolbar toggle defaults off. Side-by-side mode shows both outlines and a central connector; inline/raw fallback shows none. Patch updates clear old projected state. No Rust/ABI/parser/settings persistence changes.
- 25 focused tests pass. Full bash init.sh passed: Rust workspace, Clippy, core build, Flutter analyze (0 issues), Flutter 872; cargo fmt, diff check, and Harness 100/100 pass.
- PR CI [41700110715](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41700110715) passed all four jobs. Platform Availability [41700098639](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41700098639) passed Linux x64, Windows x64, and macOS ARM64. macOS package artifact [13265030361](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41700098639/artifacts/13265030361); Linux [13262593289](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41700098639/artifacts/13262593289); Windows [13262834152](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41700098639/artifacts/13262834152). macOS hosted DnD route was unavailable, so native macOS DnD/IME remain P15 device gates.
- GitNexus warnings remain unresolved: edited views had UNKNOWN impact before code; post-change detect reports CRITICAL and many unrelated name-linked processes. Exact source search shows one product caller for the new projector and tests. See docs/diagnostics/2026-11-04-p04/p04.103-moved-block-view.md.

## CI Failure and Crash Classification

The five 2026-11-03 Windows ARM artifact replay runs 41623366222, 41624838142, 41625760177, 41626282817, and 41626759894 failed the second-view text assertion. Run 41626759894 artifacts show all four MSAA editor nodes synchronized to the same text, but the Windows ARM SendKeys route dropped its first character; the light sample was missing “v” from “view-2”, while the dark sample saved/read back the exact string. Both closed gracefully with exit code 0 and no Application Fault event or crash dump. This is an input-harness race, not crash evidence for those runs. The current code SHA's Windows P03.7 suite and graceful close passed in Platform Availability 41700098639. Preserve this harness issue for a separate follow-up; do not weaken exact text/save assertions or record it as a crash fix. Historical Windows 0xC000041D and pre-9f2c70a macOS SIGSEGV evidence remain in docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md.

P04.102's earlier macOS job was canceled while queued with zero steps; that remains true for that SHA. P04.103's successor SHA now has successful macOS package/startup evidence. No local desktop GUI or Narrator was launched.

## Workspace and PR

- Worktree: /tmp/alula-p04.70-next. Code commit 56b343e is pushed; this commit records evidence and state.
- Push target: origin/codex/vscode-parity-p00; user authorized pushes to this branch.
- PR #2: [OPEN/draft](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/pull/2). Do not merge or publish v0.1.0 before the plan gates are complete.

## Blockers / Risks

- Native Linux DRM and native macOS DnD/IME/device acceptance remain P15 gates.
- macOS hosted DnD artifact records synthetic pointer routing unavailable; package/build/startup success is not native DnD evidence.
- Windows ARM artifact validator has a reproducible first-character SendKeys race on an older artifact; preserve it as a harness issue.
- GitNexus graph remains CRITICAL/UNKNOWN for this slice; do not downgrade from the raw impact count.
- Historical Windows 0xC000041D and pre-9f2c70a macOS SIGSEGV remain evidence-qualified mitigations, not controlled root-cause proof.

## Files Involved

- Product: app/lib/git/git_diff_patch_view.dart, app/lib/git/git_diff_moved_blocks_projection.dart
- Tests: app/test/git_diff_moved_blocks_projection_test.dart, app/test/git_diff_moved_blocks_view_test.dart
- State: docs/03-里程碑计划与验收标准.md, feature_list.json, progress.md, session-handoff.md
- Evidence: docs/diagnostics/2026-11-04-p04/p04.103-moved-block-view.md and docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md

## Next Session Startup

1. Read AGENTS.md, this handoff, and progress.md.
2. Check node .gitnexus/run.cjs status; refresh if stale. Run bash init.sh --fast.
3. Continue P04.104 only; do not open another feature until its evidence/state is committed. Before Dart edits, refresh/check GitNexus and run required impact/context/query and exact caller search; preserve UNKNOWN/CRITICAL warnings.
4. Keep PR #2 OPEN/draft. Avoid local GUI/accessibility actions that can launch Narrator.
