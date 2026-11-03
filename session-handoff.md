# Session Handoff

> Last Updated: 2026-11-04. P04.102 / EDT-17j model commit `0959e3c0a24ab5776a9575c3e709ad39d642da53` and its evidence/state record are pushed to `codex/vscode-parity-p00`. PR #2 remains OPEN/draft.

## Current Objective

Continue P04 / `feat-026` toward fixed-version VS Code editor and Git Diff parity. P04.102 delivered and verified the bounded pure-Dart moved-block model. P04.103 / EDT-17k is now registered to map those source patch rows into side-by-side projection rows and render opt-in default-off moved block outlines/connectors. No implementation has started yet; see the P04.103 report for scope and GitNexus warnings.

## Current Slice: P04.103 / EDT-17k

- Registered in `docs/03-里程碑计划与验收标准.md`; implementation has not started. Code-OSS 1.145.0 defaults `diffEditor.experimental.showMoves` to false and enables it only for side-by-side view. Alula will provide a per-view opt-in toggle for this slice because it has no global settings UI.
- Work first on strict source-patch-row to projected-row mapping, then old/new outlines and connector drawing. Any mapping failure must suppress all moved marks; inline and raw fallback do not display them. Keep approximate/unchanged move detection and preference persistence out of scope.
- GitNexus impact for `GitDiffPatchView`, its State, and `_GitDiffPatchRow` is `UNKNOWN`; exact source search confirmed one product instantiation in `workbench_page.dart` and several tests. Preserve the graph uncertainty. Details and fixed sources: `docs/diagnostics/2026-11-04-p04/p04.103-moved-block-view.md`.

## Latest Slice: P04.102 / EDT-17j

- Pinned Code-OSS 1.145.0 has `experimental.showMoves: false`; the model covers a conservative subset of `DefaultLinesDiffComputer.computeMovedLines` (exact trim-equivalent blocks only, not approximate similarity or unchanged moves). Minimum 3 lines, 15 normalized UTF-16 units, 2 substantial lines. Full criteria are in `docs/03-里程碑计划与验收标准.md`.
- 13 focused Flutter tests pass. `cargo fmt --all -- --check` and full `bash init.sh` pass: Rust workspace, Clippy, `build_core`, Flutter analyze 0 issues, Flutter 865 tests.
- PR CI [`41695398743`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41695398743) passed all four jobs. Platform Availability [`41695384851`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41695384851) passed Linux x64 and Windows x64. Linux package/DnD artifacts: `13261255894` / `13261180829`; Windows package/DnD: `13262211045` / `13261241203`.
- The macOS ARM64 job in run `41695384851` was canceled while queued, with zero steps; the overall Platform Availability workflow therefore concluded failure, but there was no app build/launch/crash on macOS. Do not claim a package for this SHA. Prior P04.101 macOS package/startup evidence remains recorded separately; native macOS DnD stays P15 pending.
- `tools/mem-probe` headless Linux sample on an identical 1,965,278 UTF-16 / 16,382-row fixture measured final PSS 178.8 MiB parser-only and 181.2 MiB with matcher (+2.4 MiB). It is a single Dart process model sample, not desktop product memory. The 500 MiB optimization target remains deferred to P14.
- GitNexus staged/all scan reported 9 files, 29 symbols, 430 affected flows, CRITICAL. Re-running with `--limit 1000` still displayed only 10 flows. The index reports 438 flows but warns that 758/958 entry candidates were dropped and 365 callees skipped. Full-repository exact source search before the report was added found no product runtime callsite for the new matcher. Preserve this CRITICAL graph limitation; do not reinterpret it as low risk. Details: `docs/diagnostics/2026-11-04-p04/p04.102-moved-block-model.md`.

## CI and Crash Evidence

The regular PR CI run is green, with no failure or crash signature. Platform Availability concluded failure only because the macOS job was canceled while queued before any step; no app process ran there. The user suspects repeated CI failures may be related to application crashes. For any recurrence, correlate the exact SHA and job with process exit code, crash signature/dump, and runner logs; distinguish process faults from test assertions, timeouts, or runner queue issues, and do not treat a successful rerun as a fix. This slice is not wired into the product and does not exercise startup, window teardown, plugin lifecycle, or the historical crash paths; it cannot establish a crash fix. Historical evidence and confidence limits remain in `docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md`. Avoid local GUI/accessibility actions that can launch Narrator. No desktop GUI or Narrator was started during P04.102.

## Workspace and PR

- Worktree: `/tmp/alula-p04.70-next`; latest code commit `0959e3c0a24ab5776a9575c3e709ad39d642da53` is pushed. P04.102 evidence/state is recorded in this handoff and the linked diagnostics.
- Push target: `origin/codex/vscode-parity-p00`; user authorized pushes to this branch.
- PR #2: [`OPEN/draft`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/pull/2). Do not merge or publish v0.1.0.

## Blockers / Risks

- Retry or obtain a macOS runner result for Platform Availability run `41695384851` or its successor; the current job was canceled before any step and provides no macOS build/package evidence.
- Native macOS DnD/IME and device acceptance remain P15 gates; Linux DRM hardware remains unavailable.
- Historical Windows `0xC000041D` and pre-`9f2c70a` macOS SIGSEGV remain evidence-qualified mitigations, not controlled root-cause proof.
- GitNexus graph output is truncated/noisy and retains CRITICAL risk for this slice.

## Files Involved

- Model: `app/lib/git/git_diff_moved_blocks.dart`
- Tests: `app/test/git_diff_moved_blocks_test.dart`
- Plan/state: `docs/03-里程碑计划与验收标准.md`, `feature_list.json`, `progress.md`, `session-handoff.md`
- Evidence: `docs/diagnostics/2026-11-04-p04/p04.102-moved-block-model.md`, `docs/diagnostics/2026-11-04-p04/p04.102-moved-blocks-probe.dart`, `docs/diagnostics/2026-11-04-p04/evidence/p04.102-*`

## Next Session Startup

1. Read `AGENTS.md`, this file, and `progress.md`.
2. Check `node .gitnexus/run.cjs status`; refresh if stale. Run `bash init.sh --fast`.
3. Recheck whether a macOS runner becomes available for run `41695384851` or a successor; record only executed job evidence.
4. Choose one next P04 slice from `docs/03`, register it before code, and run GitNexus query/context/impact before edits.

## Recommended Next Step

Implement registered P04.103 with strict row mapping, default-off side-by-side moved marks/connectors, and all-or-nothing fallback. Track the canceled macOS job as an external runner validation gap without blocking architecture work. Do not broaden into approximate matching, unchanged-region folding, settings persistence, or general compare-editor integration in the same slice. Keep PR #2 OPEN/draft and avoid local GUI/Narrator.
