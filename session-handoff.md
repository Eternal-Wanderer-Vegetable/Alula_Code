# Session Handoff

> Last Updated: 2026-11-04. P04.107 / EDT-18c is complete; P04.108 / EDT-18d is registered and is the only active slice. PR #2 remains OPEN/draft.

## Current Objective

P04.108 / EDT-18d: implement only the Explorer single-resource `Select for Compare` → `Compare with Selected` workflow. The DoD is registered in `docs/03-里程碑计划与验收标准.md`; upstream and pre-edit graph evidence are in `docs/diagnostics/2026-11-04-p04/p04.108-explorer-compare-scope.md`. Implementation has not started.

## Repository and PR

- Active worktree: `/tmp/alula-p04.70-next`; use it for follow-up work. `/mnt/e/alula_code` is an older worktree.
- Push branch: `codex/vscode-parity-p00`; push authorization for this branch persists.
- PR #2: https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/pull/2 — OPEN/draft. Do not merge or publish v0.1.0 before the plan gates finish.
- Product commit `945d9576b889cd312689b9462c1b5e0d9c110a80`; test commit `8c294309ee469463ac78f0830484fef6cbe42bc3`; P04.107 evidence/state commit `f44533e89bd05c7c9cb7fb3ec20ce998a1047c0b` is pushed. P04.108 scope registration is currently an uncommitted docs/state working-tree change.

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

## Next Session Startup

1. Read `AGENTS.md`, this handoff, and `progress.md`.
2. Run `node .gitnexus/run.cjs status`; refresh the index if stale.
3. Run `bash init.sh --fast`.
4. Continue P04.108 only from its registered DoD; first re-check GitNexus status/impact freshness, then implement the Explorer two-step workflow.
5. Keep one feature in progress, preserve UTF-16/FFI invariants, and run all-scope GitNexus change analysis before committing.
