# Session Handoff

> Last Updated: 2026-11-04. P04.108 / EDT-18d is complete and evidence is pushed. P04.109 / EDT-18e is registered as the only active slice; implementation has not started. PR #2 remains OPEN/draft.

## Current Objective

P04.109 / EDT-18e: implement only the pinned single-file diff `Revert Block`, `Revert Selection`, and `diffEditor.revert` action. Scope/DoD and pre-edit graph impact are registered in `docs/03-里程碑计划与验收标准.md` and `docs/diagnostics/2026-11-04-p04/p04.109-revert-diff-block-scope.md`. Implementation has not started. P04.108 evidence commit `1a5cd1b` is pushed; PR CI `41760872371` passed, and PR #2 remains OPEN/draft. Keep original snapshots immutable, route all changes through the versioned Rust-backed modified document, guard stale/approximate/IME cases, and retain the CRITICAL `computeDiffViewModel` impact by not changing it. No local GUI/Narrator. Prior P04.108 report: `docs/diagnostics/2026-11-04-p04/p04.108-explorer-compare.md`.

## Repository and PR

- Active worktree: `/tmp/alula-p04.70-next`; use it for follow-up work. `/mnt/e/alula_code` is an older worktree.
- Push branch: `codex/vscode-parity-p00`; push authorization for this branch persists.
- PR #2: https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/pull/2 — OPEN/draft. Do not merge or publish v0.1.0 before the plan gates finish.
- Product commit `945d9576b889cd312689b9462c1b5e0d9c110a80`; test commit `8c294309ee469463ac78f0830484fef6cbe42bc3`; P04.107 evidence/state commit `f44533e89bd05c7c9cb7fb3ec20ce998a1047c0b` is pushed. P04.108 product/test commits `d035275`, `15da959`, and `11a494e` are pushed; only evidence/state docs remain uncommitted. Push authorization for `codex/vscode-parity-p00` persists.

## P04.107 Evidence

- Product implementation: `app/lib/editor/snapshot_compare_preview.dart`, `app/lib/editor/clipboard_compare_preview.dart`, `app/lib/workbench/workbench_page.dart`.
- Tests: `app/test/workbench_saved_compare_test.dart`, `app/test/workbench_clipboard_compare_test.dart`.
- Local: `bash init.sh` and `bash init.sh --fast` passed; Rust workspace/Clippy/core build and Flutter 907 tests passed. Focused saved compare 14/14, compare suites 22; Flutter analyze 0 issues; cargo fmt and Harness 100/100 passed.
- Hosted PR CI: [41740385635](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41740385635) and [41741561799](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41741561799), all four jobs passed.
- Hosted platform runs: [41740379438](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41740379438) and [41741552975](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41741552975), Linux x64, Windows x64, and macOS ARM64 jobs passed. Latest package artifacts: Linux `13282810395`, Windows `13282375945`, macOS `13282177699`.
- CI failure recheck: run `41719529276` attempt 1 lost the hosted Windows runner connection without a crash signature; attempt 2 passed Windows format, Clippy, tests, and the 10-repeat LSP shutdown fixture. Historical Windows `0xC000041D` and pre-mitigation macOS SIGSEGV remain separate evidence-qualified crash reports.
- macOS hosted DnD could not route synthetic pointer events; native macOS DnD/IME and real-device acceptance stay P15 gates. No local GUI or Narrator was started.
- GitNexus impact risks include CRITICAL and UNKNOWN findings and all-scope overconnected flows; no clean-scan claim. See `docs/diagnostics/2026-11-04-p04/p04.107-editable-compare.md` and `docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md`.

## P04.108 Scope and Pre-edit Analysis

- Fixed Code-OSS 1.145.0 route: single Explorer file uses `selectForCompare` → `compareFiles` (`Select for Compare` → `Compare with Selected`); `compareSelected` handles multi-resource selection and is excluded. Sources: `fileConstants.ts` 13–17; `fileCommands.ts` 187–230; Explorer action/menu `fileActions.contribution.ts` 398–428 and 517–535; resource resolution `files.ts` 96–130.
- Scope: single Explorer file selection and frozen original snapshot; compare a second Explorer file as the editable Rust-backed modified `OpenDoc`. Do not implement Explorer multi-select, Open Editors/selected tabs, apply/revert, or three-way/Multi Diff.
- Impacts: `_WorkbenchPageState` CRITICAL 262/141/20; `TreeNode` CRITICAL 272/141/20; `SnapshotComparePreview` CRITICAL 191/141/20; `_readDiskDocument` HIGH 69/4/3; `_refreshTree` UNKNOWN across three candidates. `_registerCommands`, `_buildNode`, `_openTreeFile`, `_showEditableSnapshotCompare`, and `CommandService` were LOW. Do not edit `_readDiskDocument` or `_refreshTree` without new impact and exact source review.
- Exact search found no current compare-selection command or Explorer menu in `app/lib` / `app/test`; the existing tree opens files on single tap. The refreshed graph has 735 unresolved cross-language property sites, 772/972 unselected flow candidates, and 13 budget-cut walks; these remain limitations, not all-clear evidence. All-scope docs scans varied from LOW/zero processes with unresolved section names to CRITICAL/421–425 matches whose process labels pointed to unrelated build/LSP flows; neither output is a clean impact determination.
- Registration checks: `bash init.sh --fast` passed Rust workspace, Clippy, `build_core`, and Flutter 907; Harness scored 100/100. A non-failing `UnknownDoc` log appeared during the existing saved-compare close-race fixture; all tests passed, and the log does not establish a crash cause. No GUI or Narrator was started.

## P04.108 Implementation and Local Verification

- Explorer single-resource `selectForCompare` → `compareFiles` is implemented with frozen disk/open-document original snapshots, Rust-authoritative editable modified `OpenDoc`, canonical workspace/path and document-version guards, visible whole-operation rejection for unsupported/stale/over-budget cases, and the active save shortcut inside the preview. Multi-resource `compareSelected` and other compare surfaces remain out of scope; no Rust/FFI/ABI/save protocol changed.
- Dedicated widget tests passed 6/6, including whole comparison rejection when diff-row limits are exceeded. Full `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0 with Flutter 913 and Rust workspace/Clippy/build_core; cargo fmt, Flutter analyze (0 issues), Harness 100/100, and diff check pass. Existing headless saved-compare close-race fixture emitted one non-failing `UnknownDoc` message; no crash conclusion is drawn. No GUI/Narrator was started.
- Product/five-test snapshot CI runs `41755678771` and `41755709195` passed; six-test PR CI `41758044540` and Platform Availability `41758034721` passed all jobs. Latest Linux/Windows/macOS package artifacts are `13288599908`, `13289171782`, and `13289098296`; macOS startup diagnostics artifact is `13289078404`. Native macOS acceptance remains P15.
- CI interpretation: recent Windows ARM validator assertion failures were keyboard-input drops with exit 0 and no crash artifact; one platform failure was macOS queued cancellation before any step. These are separate from historical Windows close/macOS startup crashes and their qualified lifecycle mitigations. This Explorer change does not touch startup/close paths. See `docs/diagnostics/2026-11-04-p04/p04.108-explorer-compare.md` and the CI/crash report.

## P04.109 Scope and Pre-edit Analysis

- Pinned `diffEditor.revert` exposes Revert Block per hunk and Revert Selection per selected mapping, only when the modified side is writable. The F1 command reverts line mappings intersecting the modified cursor/selection; toolbar context carries exact inner changes. Both write original text into the modified side with undo stops. Sources and range semantics: `diffEditor.contribution.ts` lines 32–67, `commands.ts` 171–197, `diffEditorWidget.ts` 674–712 at commit `4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e`.
- GitNexus exact impacts: `SnapshotComparePreview` LOW 9; `_showEditableSnapshotCompare` LOW 5; `computeDiffViewModel` CRITICAL 74 across 6 workflows. Keep diff model untouched. Graph warnings: 421 unresolved cross-language property sites, 1,012/1,212 flow-entry candidates unranked, 545 callees skipped, 15 budget-cut walks.
- Implementation is not started. Next: inspect the preview/editor callback path, use only the Rust-authoritative versioned edit route, add focused tests, update evidence, run graph change analysis, and commit in stages.

## Next Session Startup

1. Read `AGENTS.md`, this handoff, and `progress.md`.
2. Run `node .gitnexus/run.cjs status`; refresh the index if stale.
3. Run `bash init.sh --fast`.
4. Continue only P04.109 / EDT-18e from its registered DoD; inspect Rust-backed editor mutation/selection APIs before editing.
5. Run focused and full DOD checks, preserve UTF-16/FFI invariants and CRITICAL/UNKNOWN graph caveats, commit product and evidence separately, and push the already-authorized branch. Leave PR #2 open/draft.
