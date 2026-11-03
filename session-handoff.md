> Last Updated: 2026-11-04. P04.106 / EDT-18b is complete and pushed at fe6c13fe76a891eaceffa95025e2f073cffdadfa. PR CI 41727303547 and Linux/Windows/macOS Platform Availability 41727292646 all passed; macOS hosted native DnD input remains unavailable and is still a P15 device gate. PR #2 stays OPEN/draft.

## Current Objective

P04.106 / EDT-18b is complete: workbench.files.action.compareWithSaved compares the active Rust-authoritative document with a bounded, decoded disk snapshot in a read-only side-by-side preview. Product commit 8f1ba78 and hosted evidence/state commits 50bd30a plus fe6c13f are pushed to origin/codex/vscode-parity-p00. Local DoD passed with Flutter 901 tests, Rust workspace, Clippy, core build, cargo fmt, and Flutter analyze. PR CI 41727303547 and Linux/Windows/macOS Platform Availability 41727292646 passed. P04/EDT-18 remains in progress; decompose the next separate EDT-18 item into docs/03 before implementation. Keep PR #2 OPEN/draft and avoid local GUI/Narrator checks.

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

P04.106 Platform Availability 41727292646 passed Linux x64, Windows x64, and macOS ARM64 build/test/startup/package. Linux and Windows native DnD checks passed; macOS DnD was skipped because the hosted runner could not route synthetic pointer input (CGEventPostToPid pointer route: false) and remains a P15 device gate. macOS stayed alive through the 12-second startup smoke; the harness then sent SIGTERM, and diagnostics contain no crash report. No local desktop GUI or Narrator was launched.

## Workspace and PR

- Worktree: /tmp/alula-p04.70-next (detached); remote origin/codex/vscode-parity-p00 contains the P04.106 product SHA fe6c13fe76a891eaceffa95025e2f073cffdadfa and its hosted validation evidence.
- Push target: origin/codex/vscode-parity-p00; authorization to push this branch persists.
- PR #2 is OPEN/draft: https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/pull/2. Do not merge or publish v0.1.0 before plan gates are complete.

## Blockers / Risks

- Native Linux DRM and native macOS DnD/IME/device acceptance remain P15 gates.
- macOS hosted DnD artifact records synthetic pointer routing unavailable; package/build/startup success is not native DnD evidence.
- The Windows ARM artifact validator input race is stabilized and passed light/dark replay; do not attribute those old assertion failures to application crashes.
- The macOS target emits an invalid bundle identifier warning for `com.alula.alula_app`; normalize it in the planned release packaging work.
- GitNexus graph remains CRITICAL/UNKNOWN for this slice; do not downgrade from the raw impact count.
- Historical Windows 0xC000041D and pre-9f2c70a macOS SIGSEGV remain evidence-qualified mitigations, not controlled root-cause proof.

## Files Involved

- Product: app/lib/workbench/workbench_page.dart, app/lib/editor/snapshot_compare_preview.dart, app/lib/editor/clipboard_compare_preview.dart, app/lib/main.dart, app/lib/workbench/keybindings.dart
- Tests: app/test/workbench_saved_compare_test.dart and app/test/keybindings_test.dart; full local suite passed with 901 tests
- State/evidence: docs/03-里程碑计划与验收标准.md, feature_list.json, progress.md, session-handoff.md, docs/diagnostics/2026-11-04-p04/p04.106-compare-with-saved.md, docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md

## Next Session Startup

1. Read AGENTS.md, this handoff, and progress.md.
2. Review the remaining EDT-18 scope in docs/10 and select the next concrete operation after compare-with-saved.
3. Register its independent scope, pinned VS Code behavior, dependencies, and DoD in docs/03 before editing source.
4. Run GitNexus impact before code changes; keep the one-feature-at-a-time rule. Keep PR #2 OPEN/draft and do not launch local GUI/Narrator.
