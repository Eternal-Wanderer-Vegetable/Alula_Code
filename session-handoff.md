# Session Handoff

> Last Updated: 2026-11-03. P04.98 / EDT-17f is complete. P01.5 is registered as an in-progress Windows CI fake-LSP shutdown-fixture follow-up after the first-attempt `p01_async_completion` failure on the same SHA later passed.

## Current Objective

Continue the fixed Code-OSS 1.145.0 parity plan one registered slice at a time. Current slice: stabilize the Windows CI fake-LSP cancellation/shutdown fixture and improve failure diagnostics, then return to EDT-17. Prioritize overall architecture and Linux/Windows usability, then provide hosted macOS packages. Numeric memory optimization remains deferred. Keep PR #2 OPEN/draft; do not publish v0.1.0 or merge.

## Latest Completed Slice: P04.98 / EDT-17f

- Added inline / side-by-side mode to Git Diff, preserving bounded patch source rows, paired word highlights, selectable text, line numbers, metadata/no-newline rows, and synchronized vertical alignment. Under 640 logical px the view remains inline; unsupported or over-budget patches retain the complete raw patch.
- Seven new tests; focused patch/side-by-side suite 22 passed. Full `bash init.sh` passed with Rust workspace, Clippy, `build_core`, and Flutter 836; cargo fmt, Flutter analyze (0 issues), and harness validator (100/100) passed. No local GUI/Narrator; no Rust/ABI change. Evidence: [`p04.98-git-diff-side-by-side.md`](docs/diagnostics/2026-11-03-p04/p04.98-git-diff-side-by-side.md).
- Headless Dart/Linux model probe at the 16,384-row cap recorded tail `total_private` 201.5 MiB baseline / 202.8 MiB candidate. This is a directional model sample, not product GUI evidence or a change to the deferred memory target.
- PR CI [`41659471482`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41659471482) final attempt 2 passed all four jobs with Flutter 836 tests. The first Windows Rust attempt failed an existing async LSP workspace-shutdown assertion; the same SHA rerun passed. The raw FFI error was not captured, so retain it as an unresolved intermittent shutdown assertion, not a proven false alarm or crash.
- Platform Availability [`41659454431`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41659454431) passed Linux x64, Windows x64, and macOS ARM64 package/startup jobs. Linux/Windows hosted DnD passed move/copy/external-text routes. Windows visible client/UIA and graceful close exit 0 passed. macOS DnD was skipped for unavailable hosted pointer routing.
- GitNexus warnings remain unresolved: exact workbench caller is omitted because `workbench_page.dart` exceeds 512 KiB; view impact is UNKNOWN, parser/word projection impacts and staged/all scans report unrelated CRITICAL flows. The evidence report records scope and counts.

## CI and Crash Finding

- Latest 100 branch regular CI runs have 100 successful final conclusions. The latest 100 Platform Availability runs have 54 successes / 46 historical failures; the newest failure remains `41458740387`, followed by 54 successful runs through `41659454431`.
- CI has captured real faults before: macOS FlutterView/Irondash startup SIGSEGV and the old Windows artifact `d5319369` close exit `0xC000041D`. Their source-level causes remain unresolved; current hosted close/startup passes are non-reproduction evidence only.
- P04.98's first-attempt Rust test failure was a missing `stopped` field in the FFI response with process exit 1, not an observed OS process crash. If it recurs, first print the full FFI response and collect child exit state before attributing it. See [`ci-failures-and-crash-correlation.md`](docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md).
- The focused follow-up is limited to the fake test server/test diagnostics. The recent platform probe failures and historical application crashes have different signatures; no causal relationship or crash mitigation is established.

## Current Workspace State

- Worktree: `/tmp/alula-p04.70-next`; P04.98 evidence is based on code SHA `6a247c7` and the accompanying docs commit.
- Push target: `origin/codex/vscode-parity-p00`. User authorized pushes to this branch.
- PR #2: [`OPEN/draft`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/pull/2).

## Blockers / Risks

- Historical Windows `0xC000041D` source cause; native Windows 11 acceptance.
- Native macOS DnD/IME, Linux DRM hardware, and P15 device gates. Hosted macOS DnD must remain marked skipped when pointer routing is unavailable.
- EDT-17 remains open: moved blocks, whitespace option, unchanged-region folding, diff navigation, and broader diff-editor integration.

## Files Involved

- Code: `app/lib/git/git_diff_side_by_side.dart`, `app/lib/git/git_diff_patch_view.dart`, `app/test/git_diff_side_by_side_test.dart`, `app/test/git_diff_patch_test.dart`.
- Evidence/state: `docs/03-里程碑计划与验收标准.md`, `docs/diagnostics/2026-11-03-p04/p04.98-git-diff-side-by-side.md`, `docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md`, `progress.md`, `feature_list.json`, and this handoff.

## Next Session Startup

1. Read `AGENTS.md`, `session-handoff.md`, and `progress.md`.
2. Confirm the worktree is clean and the evidence commit is pushed to `codex/vscode-parity-p00`.
3. Check PR #2 remains OPEN/draft and review the latest CI status.
4. Complete registered P01.5: make fake LSP cancellation interrupt delayed fixture work, report full shutdown JSON on assertion failure, and repeat the Windows focused test. Then return to the next EDT-17 gap.

## Recommended Next Step

Preserve all GitNexus UNKNOWN/CRITICAL warnings, keep PR #2 open/draft, and avoid local GUI/accessibility actions that can start Narrator.
