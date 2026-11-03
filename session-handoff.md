# Session Handoff

> Last Updated: 2026-11-04. P04.105 / EDT-18a code and evidence are ready for the separate evidence/state commit: local DoD, PR CI 41713133917, and Linux/Windows/macOS Platform Availability 41713121910 passed. PR #2 remains OPEN/draft.

## Current Objective

Continue P04 / feat-026 toward fixed-version VS Code editor, Git Diff, and compare-operation parity. P04.105 active-file versus clipboard snapshot compare preview is complete. After its evidence/state commit, read docs/03 and docs/11 to select and register the next single EDT-18 operation before implementation. The 500 MiB numeric memory target remains deferred to P14.

## Completed Slice: P04.105 / EDT-18a

- Register `workbench.files.action.compareWithClipboard`, F1/File command and Ctrl/Cmd+K, C. Compare a Rust-authoritative active document snapshot with one clipboard snapshot in a bounded side-by-side, read-only preview.
- Validate active document identity/version after asynchronous clipboard read. Cancel stale requests visibly. Keep temporary clipboard model in memory and dispose it when preview closes; do not write clipboard text to disk/session/history.
- Do not claim editable right pane, selected-file compare, saved-version compare, apply/revert or three-way merge in this slice.
- Local gates passed on final implementation: `bash init.sh` (Rust workspace, Clippy, core build, Flutter 891), `cargo fmt --all -- --check`, `flutter analyze --no-pub` (0 issues), focused keybinding/preview/workbench suites. New tests cover close/switch/edit races, empty/no-text clipboard, line budget, BOM/emoji/CRLF, and document/selection/dirty/undo/disk invariants.
- Close-race test logs a caught pre-existing minimap overview `UnknownDoc` after document close; track as an adjacent diagnostic only. It is not an unhandled exception or crash signal.
- Fixed source, DoD, GitNexus boundary notes: `docs/diagnostics/2026-11-04-p04/p04.105-clipboard-compare-preview.md`; `docs/03-里程碑计划与验收标准.md` is authoritative.
- Code commit `f1d204a5c3a0414ce4fb7edd6063efaeeb3ef290` pushed. PR CI `41713133917` passed all four jobs (Flutter 891); Platform Availability `41713121910` passed Linux x64, Windows x64, and macOS ARM64 build/test/startup/package. Artifacts: Linux `13268317746`, Windows `13269382552`, macOS `13269977828`; artifact details and process-exit/crash classification are in the P04.105 report.
- macOS hosted native DnD pointer routing was unavailable and remains a P15 device gate. The macOS build warns that `com.alula.alula_app` has an invalid underscore in its bundle identifier; track the identifier fix in release packaging. No local GUI or Narrator was started.
- P04.104 evidence commit `26cdf35` pushed; its PR CI `41709174313` passed all four jobs. P04.104 code SHA `43e35cd` local, PR CI and Linux/Windows/macOS Platform Availability all passed; macOS device DnD remains a P15 gate.
- Before any Dart code edit, refresh GitNexus and run impact/context for the concrete command registration, diff view model and workbench entry. Existing `computeDiffViewModel` context is lower-bound; `CommandService` impact UNKNOWN/zero callers; `workbench_page.dart` is >512 KiB/skipped. Retain UNKNOWN/CRITICAL and verify exact callsites by search.

## Previous Slice: P04.104 / EDT-17l

- Implement inline unchanged-region folding only, off by default, using pinned Code-OSS 1.145.0 defaults: preserve 3 context rows on either side, require at least 3 hidden rows, reveal at most 20 per action.
- Fold only within one hunk between changed runs; preserve leading/trailing context and all metadata, markers and changed rows. Strict source mapping failure disables folding. Navigation must target visible projected rows.
- Patch update clears reveal state. No Rust/ABI/parser/side-by-side/persistence/P14 changes.
- Registration and pinned reference: `docs/diagnostics/2026-11-04-p04/p04.104-inline-unchanged-regions.md`; `docs/03-里程碑计划与验收标准.md` is authoritative for DoD.
- GitNexus `GitDiffPatchView` impact remains UNKNOWN with zero resolved callers. Exact text search confirmed one workbench product instance; preserve the unresolved graph risk.
- Code SHA `43e35cd2124b8a936c64876f9592e5f7674835ee` is pushed. Local focused tests 9, related tests 46, full init.sh Flutter 881; analyze 0, cargo fmt, Harness 100/100 pass.
- PR CI `41706323129` passed all four jobs; Platform Availability `41706312269` passed Linux x64, Windows x64, and macOS ARM64. Linux and Windows native DnD and Windows UIA/MSAA/graceful close passed; macOS package/startup passed but hosted pointer route is unavailable, so native macOS DnD remains a P15 device gate. Artifact IDs and crash classification are recorded in the P04.104 evidence page.
- This slice produced no crash signal/dump or nonzero app exit in hosted checks. It does not change startup/close paths and is not a crash fix.
- Post-change GitNexus all-scope risk remains CRITICAL (4 files, 7 symbols, 434 affected flows); new projector impact 44/43 direct/CRITICAL and context is lower-bound. Preserve risk and exact search evidence in the report.

## Previous Slice: P04.103 / EDT-17k

- Strictly maps P04.102 moved-block source rows into projected side-by-side rows. Any missing, duplicate, out-of-range, mismatched, non-contiguous, or overlapping mapping suppresses every moved decoration.
- The per-view toolbar toggle defaults off. Side-by-side mode shows both outlines and a central connector; inline/raw fallback shows none. Patch updates clear old projected state. No Rust/ABI/parser/settings persistence changes.
- 25 focused tests pass. Full bash init.sh passed: Rust workspace, Clippy, core build, Flutter analyze (0 issues), Flutter 872; cargo fmt, diff check, and Harness 100/100 pass.
- PR CI [41700110715](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41700110715) passed all four jobs. Platform Availability [41700098639](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41700098639) passed Linux x64, Windows x64, and macOS ARM64. macOS package artifact [13265030361](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41700098639/artifacts/13265030361); Linux [13262593289](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41700098639/artifacts/13262593289); Windows [13262834152](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41700098639/artifacts/13262834152). macOS hosted DnD route was unavailable, so native macOS DnD/IME remain P15 device gates.
- GitNexus warnings remain unresolved: edited views had UNKNOWN impact before code; post-change detect reports CRITICAL and many unrelated name-linked processes. Exact source search shows one product caller for the new projector and tests. See docs/diagnostics/2026-11-04-p04/p04.103-moved-block-view.md.

## CI Failure and Crash Classification

The five 2026-11-03 Windows ARM artifact replay runs 41623366222, 41624838142, 41625760177, 41626282817, and 41626759894 failed the second-view text assertion because SendKeys dropped its first post-newline character (`v` in `view-2`). Those processes closed with exit code 0 and no Application Fault event or crash dump. Validator commit `34f1511` added a post-Enter wait and per-character pacing; same-artifact light/dark replay 41627307864 then passed exact edit/save/read-back. Keep this classified as hosted input stabilization, not a crash fix. Historical Windows 0xC000041D and pre-9f2c70a macOS SIGSEGV and mitigations remain in docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md.

P04.102's earlier macOS job was canceled while queued with zero steps; that remains true for that SHA. P04.103's successor SHA now has successful macOS package/startup evidence. No local desktop GUI or Narrator was launched.

## Workspace and PR

- Worktree: /tmp/alula-p04.70-next. P04.105 code commit `f1d204a` is pushed; docs/evidence/state changes are pending the separate commit.
- Push target: origin/codex/vscode-parity-p00; user authorized pushes to this branch.
- PR #2: [OPEN/draft](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/pull/2). Do not merge or publish v0.1.0 before the plan gates are complete.

## Blockers / Risks

- Native Linux DRM and native macOS DnD/IME/device acceptance remain P15 gates.
- macOS hosted DnD artifact records synthetic pointer routing unavailable; package/build/startup success is not native DnD evidence.
- The Windows ARM artifact validator input race is stabilized and passed light/dark replay; do not attribute those old assertion failures to application crashes.
- The macOS target emits an invalid bundle identifier warning for `com.alula.alula_app`; normalize it in the planned release packaging work.
- GitNexus graph remains CRITICAL/UNKNOWN for this slice; do not downgrade from the raw impact count.
- Historical Windows 0xC000041D and pre-9f2c70a macOS SIGSEGV remain evidence-qualified mitigations, not controlled root-cause proof.

## Files Involved

- Product: app/lib/editor/clipboard_compare_preview.dart, Workbench command/keybinding registration
- Tests: app/test/clipboard_compare_preview_test.dart, app/test/workbench_clipboard_compare_test.dart, app/test/keybindings_test.dart
- State: docs/03-里程碑计划与验收标准.md, feature_list.json, progress.md, session-handoff.md
- Evidence: docs/diagnostics/2026-11-04-p04/p04.105-clipboard-compare-preview.md, docs/diagnostics/2026-11-04-p04/p04.103-moved-block-view.md, and docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md

## Next Session Startup

1. Read AGENTS.md, this handoff, and progress.md.
2. Check node .gitnexus/run.cjs status; refresh if stale. Run bash init.sh --fast.
3. Refresh GitNexus and run all-scope detect-changes for pending documentation; commit/push P04.105 evidence/state separately. Verify its PR CI, then select and register one next EDT-18 operation from docs/03 and docs/11 before coding.
4. Keep PR #2 OPEN/draft. Avoid local GUI/accessibility actions that can launch Narrator.
