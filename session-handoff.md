# Session Handoff

> Last Updated: 2026-11-04. P04.100 / EDT-17h is complete for its registered scope; code is pushed and hosted evidence/state updates are prepared in the worktree. P04 and the overall parity plan remain in progress.

## Current Objective

Continue the fixed Code-OSS 1.145.0 parity plan one registered slice at a time. P04.100 adds pinned accessible-diff actions through the existing Command Palette. Its local DoD, PR CI, Linux/Windows hosted usability, and macOS ARM64 build/package/startup gates passed. Hosted macOS native DnD was skipped because the runner could not route synthetic pointer events; physical macOS interaction remains pending under P15. Fresh GitNexus impact and its CRITICAL/UNKNOWN warnings are recorded. Prioritize overall architecture and Linux/Windows usability, then provide hosted macOS packages. Numeric memory optimization remains deferred. Keep PR #2 OPEN/draft; do not publish v0.1.0 or merge.

## Latest Completed Follow-up: P01.5 Windows LSP shutdown fixture

- Fake server cancellation now wakes and exits delayed completion workers. Linux and Windows focus runs passed 10/10; PR CI 41666117480 passed all four jobs. The original failed FFI error was not captured. Production LSP/ABI and window code were unchanged; historical application crash root cause remains unresolved.

## Previous Architecture Slice: P04.98 / EDT-17f

- Added inline / side-by-side mode to Git Diff, preserving bounded patch source rows, paired word highlights, selectable text, line numbers, metadata/no-newline rows, and synchronized vertical alignment. Under 640 logical px the view remains inline; unsupported or over-budget patches retain the complete raw patch.
- Seven new tests; focused patch/side-by-side suite 22 passed. Full `bash init.sh` passed with Rust workspace, Clippy, `build_core`, and Flutter 836; cargo fmt, Flutter analyze (0 issues), and harness validator (100/100) passed. No local GUI/Narrator; no Rust/ABI change. Evidence: [`p04.98-git-diff-side-by-side.md`](docs/diagnostics/2026-11-03-p04/p04.98-git-diff-side-by-side.md).
- Headless Dart/Linux model probe at the 16,384-row cap recorded tail `total_private` 201.5 MiB baseline / 202.8 MiB candidate. This is a directional model sample, not product GUI evidence or a change to the deferred memory target.
- PR CI [`41659471482`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41659471482) final attempt 2 passed all four jobs with Flutter 836 tests. The first Windows Rust attempt failed an existing async LSP workspace-shutdown assertion; the same SHA rerun passed. The raw FFI error was not captured, so retain it as an unresolved intermittent shutdown assertion, not a proven false alarm or crash.
- Platform Availability [`41659454431`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41659454431) passed Linux x64, Windows x64, and macOS ARM64 package/startup jobs. Linux/Windows hosted DnD passed move/copy/external-text routes. Windows visible client/UIA and graceful close exit 0 passed. macOS DnD was skipped for unavailable hosted pointer routing.
- GitNexus warnings remain unresolved: exact workbench caller is omitted because `workbench_page.dart` exceeds 512 KiB; view impact is UNKNOWN, parser/word projection impacts and staged/all scans report unrelated CRITICAL flows. The evidence report records scope and counts.

## CI and Crash Finding

- Latest 100 branch regular CI runs have 100 successful final conclusions. The latest 100 Platform Availability runs have 54 successes / 46 historical failures; the newest failure remains `41458740387`, followed by 54 successful runs through `41670544291`.
- CI has captured real faults before. For the old Windows `d5319369` artifact, source comparison found that `CoUninitialize()` ran before `FlutterWindow` destruction; commit `c2b787f` moved controller destruction before COM teardown. The newer `1129d607` artifact passed a Windows 11 ARM light/dark replay, so the old close crash is likely mitigated, although the exception lacks a confirmed stack and this is not a single-variable proof. macOS FlutterView/Irondash startup SIGSEGV had a separate readiness/nil-guard change in `9f2c70a`; later startup smokes did not produce a crash report.
- P04.98's first-attempt Rust test failure was a missing `stopped` field in the FFI response with process exit 1, not an observed OS process crash. If it recurs, first print the full FFI response and collect child exit state before attributing it. See [`ci-failures-and-crash-correlation.md`](docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md).
- Recent platform red runs primarily concern input routing, accessibility assertions, or validation probes; they are not all crashes. The P01.5 fake-LSP fixture follow-up improves test determinism only and does not explain either historical application fault. See `docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md`.
- P01.5 outcome: the fake server now interrupts canceled delayed completion workers. Linux and Windows focused repetitions passed 10/10, and PR CI run [`41666117480`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41666117480) passed all four jobs. This makes the shutdown regression fixture more deterministic; the original failure's FFI error was not captured, and the old application crash remains unresolved.

## Current Workspace State

- Worktree: `/tmp/alula-p04.70-next`; code commit `0b792fd` and P04.100 local implementation are pushed. Current worktree contains hosted-evidence/status documentation changes for a separate evidence commit.
- Push target: `origin/codex/vscode-parity-p00`. User authorized pushes to this branch.
- PR #2: [`OPEN/draft`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/pull/2).

## Active Slice / Risks

- P04.99 is complete as registered: F7 / Shift+F7, wraparound navigation, toolbar controls, current-row highlight, live accessibility status, inline/side-by-side reveal. Local DoD, PR CI 41670555528, and Platform Availability 41670544291 passed; macOS native DnD was explicitly skipped for unavailable pointer routing.
- The P04.99 implementation staged/all scan remains CRITICAL and capped (385 flows); examples are unrelated build/LSP flows. The later docs-only evidence/state scan was 7 files / 16 symbols / 0 affected flows / LOW, not partial/truncated. Preserve both scopes in the P04.99 report.
- P04.100 / EDT-17h is complete: Command Palette exposes editor.action.accessibleDiffViewer.next/prev only in an active, navigable Git Diff tab. Three new widget tests and full local DoD pass. PR CI `41678408601` passed (847 Flutter tests); Platform Availability `41678397272` passed Linux/Windows/macOS build/package/startup. macOS DnD was explicitly skipped for unavailable pointer routing. Windows graceful close exit 0; no current app-crash signal. See `docs/diagnostics/2026-11-04-p04/p04.100-diff-palette-actions.md`.


- P04.99 / EDT-17g is registered in docs/03: implement wraparound next/previous diff navigation with F7/Shift+F7 in inline and side-by-side Git diff views. See docs/diagnostics/2026-11-03-p04/p04.99-diff-navigation.md.
- GitNexus GitDiffPatchView impact was UNKNOWN because the >512 KiB workbench caller is omitted. Exact source search found workbench_page.dart:16121; keep the graph limitation visible. Re-index and rerun impact immediately before code edits.

## Blockers / Risks

- Historical Windows `0xC000041D` is likely mitigated by `c2b787f`, but the exact fault is unproven; native Windows 11 device acceptance remains open.
- Native macOS DnD/IME, Linux DRM hardware, and P15 device gates. Hosted macOS DnD must remain marked skipped when pointer routing is unavailable.
- EDT-17 remains open: moved blocks, whitespace option, unchanged-region folding, generic compare-editor integration, and other registered diff gaps.

## Files Involved

- Code: `app/lib/git/git_diff_commands.dart`, `app/lib/git/git_diff_navigation.dart`, `app/lib/git/git_diff_patch_view.dart`, `app/lib/workbench/workbench_page.dart`, `app/test/git_diff_command_test.dart`, and the existing navigation tests.
- Evidence/state: `docs/03-里程碑计划与验收标准.md`, `docs/diagnostics/2026-11-04-p04/p04.100-diff-palette-actions.md`, `docs/diagnostics/2026-11-03-p04/p04.99-diff-navigation.md`, `docs/diagnostics/2026-11-03-p04/p04.92-win11-arm-current-artifact.md`, `docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md`, `progress.md`, `feature_list.json`, and this handoff.

## Next Session Startup

1. Read `AGENTS.md`, `session-handoff.md`, and `progress.md`.
2. Confirm the worktree is clean and the evidence commit is pushed to `codex/vscode-parity-p00`.
3. Check PR #2 remains OPEN/draft and review the latest CI status.
4. Commit/push the P04.100 evidence-only state update, confirm PR #2 remains OPEN/draft, then select the next dependency-ready item from `docs/03`.

## Recommended Next Step

Select the next P04 item from `docs/03` after the P04.100 evidence commit. Keep the macOS DnD route skip and historical Windows crash cause explicit; preserve GitNexus UNKNOWN/CRITICAL warnings, keep PR #2 open/draft, and avoid local GUI/accessibility actions that can start Narrator.
