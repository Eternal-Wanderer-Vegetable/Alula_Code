# Session Handoff

> Last Updated: 2026-11-04. P04.107 / EDT-18c is complete, including local DoD and hosted Linux, Windows, and macOS package/startup checks. PR #2 remains OPEN/draft.

## Current Objective

P04.107 made the modified pane in Compare with Clipboard and Compare with Saved edit the same Rust-authoritative active document. The original clipboard/disk snapshot stays read-only; diff recompute is bounded and has a complete fallback; same-document views, save, undo/redo, dirty/savepoint, IME commit, and preview lifecycle behavior are covered.

Next session: choose one dependency-ready item from `docs/03-里程碑计划与验收标准.md` and the plan, define/register its DoD before implementation, and work only that slice. P04/EDT-18 remains open; do not infer the next feature from this handoff.

## Repository and PR

- Active worktree: `/tmp/alula-p04.70-next`; use it for follow-up work. `/mnt/e/alula_code` is an older worktree.
- Push branch: `codex/vscode-parity-p00`; push authorization for this branch persists.
- PR #2: https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/pull/2 — OPEN/draft. Do not merge or publish v0.1.0 before the plan gates finish.
- Product commit `945d9576b889cd312689b9462c1b5e0d9c110a80`; test commit `8c294309ee469463ac78f0830484fef6cbe42bc3`; this handoff is included in the final P04.107 evidence/state commit.

## P04.107 Evidence

- Product implementation: `app/lib/editor/snapshot_compare_preview.dart`, `app/lib/editor/clipboard_compare_preview.dart`, `app/lib/workbench/workbench_page.dart`.
- Tests: `app/test/workbench_saved_compare_test.dart`, `app/test/workbench_clipboard_compare_test.dart`.
- Local: `bash init.sh` and `bash init.sh --fast` passed; Rust workspace/Clippy/core build and Flutter 907 tests passed. Focused saved compare 14/14, compare suites 22; Flutter analyze 0 issues; cargo fmt and Harness 100/100 passed.
- Hosted PR CI: [41740385635](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41740385635) and [41741561799](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41741561799), all four jobs passed.
- Hosted platform runs: [41740379438](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41740379438) and [41741552975](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41741552975), Linux x64, Windows x64, and macOS ARM64 jobs passed. Latest package artifacts: Linux `13282810395`, Windows `13282375945`, macOS `13282177699`.
- CI failure recheck: run `41719529276` attempt 1 lost the hosted Windows runner connection without a crash signature; attempt 2 passed Windows format, Clippy, tests, and the 10-repeat LSP shutdown fixture. Historical Windows `0xC000041D` and pre-mitigation macOS SIGSEGV remain separate evidence-qualified crash reports.
- macOS hosted DnD could not route synthetic pointer events; native macOS DnD/IME and real-device acceptance stay P15 gates. No local GUI or Narrator was started.
- GitNexus impact risks include CRITICAL and UNKNOWN findings and all-scope overconnected flows; no clean-scan claim. See `docs/diagnostics/2026-11-04-p04/p04.107-editable-compare.md` and `docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md`.

## Next Session Startup

1. Read `AGENTS.md`, this handoff, and `progress.md`.
2. Run `node .gitnexus/run.cjs status`; refresh the index if stale.
3. Run `bash init.sh --fast`.
4. Select a dependency-ready item from `docs/03` and `feature_list.json`; read the registered DoD and run GitNexus impact before editing.
5. Keep one feature in progress, preserve UTF-16/FFI invariants, and run all-scope GitNexus change analysis before committing.
