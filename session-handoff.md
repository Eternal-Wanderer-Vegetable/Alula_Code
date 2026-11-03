# Session Handoff

> Last Updated: 2026-11-04. P04.102 / EDT-17j model commit `0959e3c0a24ab5776a9575c3e709ad39d642da53` and its evidence/state record are pushed to `codex/vscode-parity-p00`. PR #2 remains OPEN/draft.

## Current Objective

Continue P04 / `feat-026` toward fixed-version VS Code editor and Git Diff parity. P04.102 delivered a bounded pure-Dart moved-block matcher for exact, unique, trim-equivalent deletion/insertion blocks across hunks in one file. It preserves old/new line numbers and patch-row ranges and returns no partial results after parser, mapping, input, row, or work limits. The matcher is not connected to the workbench; there are no move markers, connectors, or `showMoves` setting yet.

## Latest Slice: P04.102 / EDT-17j

- Pinned Code-OSS 1.145.0 has `experimental.showMoves: false`; the model covers a conservative subset of `DefaultLinesDiffComputer.computeMovedLines` (exact trim-equivalent blocks only, not approximate similarity or unchanged moves). Minimum 3 lines, 15 normalized UTF-16 units, 2 substantial lines. Full criteria are in `docs/03-里程碑计划与验收标准.md`.
- 13 focused Flutter tests pass. `cargo fmt --all -- --check` and full `bash init.sh` pass: Rust workspace, Clippy, `build_core`, Flutter analyze 0 issues, Flutter 865 tests.
- PR CI [`41695398743`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41695398743) passed all four jobs. Platform Availability [`41695384851`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41695384851) passed Linux x64 and Windows x64. Linux package/DnD artifacts: `13261255894` / `13261180829`; Windows package/DnD: `13262211045` / `13261241203`.
- macOS ARM64 job in run `41695384851` was still `queued` at handoff capture. Do not mark it passed or claim a package for this SHA. Prior P04.101 macOS package/startup evidence remains recorded separately; native macOS DnD stays P15 pending.
- `tools/mem-probe` headless Linux sample on an identical 1,965,278 UTF-16 / 16,382-row fixture measured final PSS 178.8 MiB parser-only and 181.2 MiB with matcher (+2.4 MiB). It is a single Dart process model sample, not desktop product memory. The 500 MiB optimization target remains deferred to P14.
- GitNexus staged/all scan reported 9 files, 29 symbols, 430 affected flows, CRITICAL. Re-running with `--limit 1000` still displayed only 10 flows. The index reports 438 flows but warns that 758/958 entry candidates were dropped and 365 callees skipped. Full-repository exact source search before the report was added found no product runtime callsite for the new matcher. Preserve this CRITICAL graph limitation; do not reinterpret it as low risk. Details: `docs/diagnostics/2026-11-04-p04/p04.102-moved-block-model.md`.

## CI and Crash Evidence

The current regular CI run is green, with no failure or crash signature. The user suspects repeated CI failures may be related to application crashes. For any recurrence, correlate the exact SHA and job with process exit code, crash signature/dump, and runner logs; distinguish process faults from test assertions, timeouts, or runner queue issues, and do not treat a successful rerun as a fix. This slice is not wired into the product and does not exercise startup, window teardown, plugin lifecycle, or the historical crash paths; it cannot establish a crash fix. Historical evidence and confidence limits remain in `docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md`. Avoid local GUI/accessibility actions that can launch Narrator. No desktop GUI or Narrator was started during P04.102.

## Workspace and PR

- Worktree: `/tmp/alula-p04.70-next`; latest code commit `0959e3c0a24ab5776a9575c3e709ad39d642da53` is pushed. P04.102 evidence/state is recorded in this handoff and the linked diagnostics.
- Push target: `origin/codex/vscode-parity-p00`; user authorized pushes to this branch.
- PR #2: [`OPEN/draft`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/pull/2). Do not merge or publish v0.1.0.

## Blockers / Risks

- Check whether the macOS job in Platform Availability run `41695384851` leaves the queue; if it does, record the actual result. Queued is not success.
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
3. Recheck macOS job status for run `41695384851`; record only verified evidence.
4. Choose one next P04 slice from `docs/03`, register it before code, and run GitNexus query/context/impact before edits.

## Recommended Next Step

After recording the macOS queue outcome, decompose P04.103 as the view integration for moved-block markers and navigation/source mapping, keeping `showMoves` off by default and preserving raw-patch fallback. Verify the precise Code-OSS interaction first; do not broaden into approximate matching, unchanged-region folding, or general compare-editor integration in the same slice. Keep PR #2 OPEN/draft and avoid local GUI/Narrator.
