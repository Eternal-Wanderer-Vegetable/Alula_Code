# Session Handoff

> Last Updated: 2026-11-04. P04.101 / EDT-17i implementation e39a648 is pushed; local DoD, PR CI 41687279291, and Linux/Windows/macOS Platform Availability 41687266257 all passed. P04.101 evidence update is pending commit/push; PR #2 remains OPEN/draft.

## Current Objective

P04.101 / EDT-17i is complete as registered. Local full DoD passed; PR CI 41687279291 passed all four jobs with Flutter 852; Platform Availability 41687266257 passed Linux x64, Windows x64, and macOS ARM64 build/package/startup. Linux artifacts: 13255511248/13256755398. Windows artifacts: 13255204860/13255244745; visible client area 1028×681, UIA/MSAA and graceful WM_CLOSE exit 0 passed. macOS package/startup artifacts: 13256467168/13256402126. macOS native DnD was skipped because CGEventPostToPid pointer route=false and no Flutter pointer events; artifact 13255502756. Its 12-second startup smoke was intentionally stopped with SIGTERM; no .ips/.crash was found. The headless model probe adds about 4.1 MiB and is not product GUI evidence. Historical crash evidence links four pre-9f2c70a macOS SIGSEGV starts to the engine-context registry readiness race; 49 later hosted runs did not recur, which supports targeted mitigation but is not controlled proof. Keep native macOS device input under P15. Numeric memory optimization remains deferred. Keep PR #2 OPEN/draft; do not merge or publish v0.1.0. Avoid local GUI/accessibility actions that could trigger Narrator.

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
- CI has captured real faults before. For the old Windows `d5319369` artifact, source comparison found that `CoUninitialize()` ran before `FlutterWindow` destruction; commit `c2b787f` moved controller destruction before COM teardown. The newer `1129d607` artifact passed a Windows 11 ARM light/dark replay, so the old close crash is likely mitigated, although the exception lacks a confirmed stack and this is not a single-variable proof. Four pre-`9f2c70a` macOS startup failures ended in SIGSEGV/exit 139. Two retained `.ips` files show `objc_loadWeakRetained` → `IrondashEngineContextPlugin getFlutterView` → Rust engine-context lookup → `super_native_extensions::drag_manager`, dereferencing an unpublished FlutterView registry entry. Commit `9f2c70a` adds an engine-context readiness handshake and nil guard; 49 later successful Platform Availability runs have not reproduced the launch crash. This is a strong targeted mitigation signal, not a controlled proof. The 25 recurring macOS DnD route failures are input-routing skips/failures, separate from the crash.
- P04.98's first-attempt Rust test failure was a missing `stopped` field in the FFI response with process exit 1, not an observed OS process crash. If it recurs, first print the full FFI response and collect child exit state before attributing it. See [`ci-failures-and-crash-correlation.md`](docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md).
- Recent platform red runs primarily concern input routing, accessibility assertions, or validation probes; they are not all crashes. The P01.5 fake-LSP fixture follow-up improves test determinism only and does not explain either historical application fault. See `docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md`.
- P01.5 outcome: the fake server now interrupts canceled delayed completion workers. Linux and Windows focused repetitions passed 10/10, and PR CI run [`41666117480`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41666117480) passed all four jobs. This makes the shutdown regression fixture more deterministic; the original failure's FFI error was not captured, and the old application crash remains unresolved.

## Current Workspace State

- Worktree: /tmp/alula-p04.70-next; code commit e39a648ad7af538d45eeb5ac0a0d32515cae67fc is pushed. Pending evidence/state files are under docs/diagnostics/2026-11-04-p04/, plus docs/03, progress.md, feature_list.json, and this handoff.
- Push target: `origin/codex/vscode-parity-p00`. User authorized pushes to this branch.
- PR #2: [`OPEN/draft`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/pull/2).

## Active Slice / Risks

- P04.99 is complete as registered: F7 / Shift+F7, wraparound navigation, toolbar controls, current-row highlight, live accessibility status, inline/side-by-side reveal. Local DoD, PR CI 41670555528, and Platform Availability 41670544291 passed; macOS native DnD was explicitly skipped for unavailable pointer routing.
- The P04.99 implementation staged/all scan remains CRITICAL and capped (385 flows); examples are unrelated build/LSP flows. The later docs-only evidence/state scan was 7 files / 16 symbols / 0 affected flows / LOW, not partial/truncated. Preserve both scopes in the P04.99 report.
- P04.100 / EDT-17h is complete: Command Palette exposes editor.action.accessibleDiffViewer.next/prev only in an active, navigable Git Diff tab. Three new widget tests and full local DoD pass. PR CI `41678408601` passed (847 Flutter tests); Platform Availability `41678397272` passed Linux/Windows/macOS build/package/startup. macOS DnD was explicitly skipped for unavailable pointer routing. Windows graceful close exit 0; no current app-crash signal. See `docs/diagnostics/2026-11-04-p04/p04.100-diff-palette-actions.md`.
- P04.101 / EDT-17i is implemented and pushed. New projection keeps whitespace-equivalent rows neutral, retains both sides/line numbers and markers, and falls back to the full raw patch on budget or mapping uncertainty. P04.101 local DoD, PR CI and Linux/Windows/macOS hosted build/package/startup gates passed. macOS DnD was explicitly skipped for unavailable synthetic pointer routing; physical macOS interaction remains a P15 gate. Code impact had CRITICAL/UNKNOWN warnings, including the unindexed >512 KiB workbench_page.dart; keep these visible. See docs/diagnostics/2026-11-04-p04/p04.101-git-diff-trim-whitespace.md.


- P04.99 / EDT-17g is registered in docs/03: implement wraparound next/previous diff navigation with F7/Shift+F7 in inline and side-by-side Git diff views. See docs/diagnostics/2026-11-03-p04/p04.99-diff-navigation.md.
- GitNexus GitDiffPatchView impact was UNKNOWN because the >512 KiB workbench caller is omitted. Exact source search found workbench_page.dart:16121; keep the graph limitation visible. Re-index and rerun impact immediately before code edits.

## Blockers / Risks

- Historical Windows `0xC000041D` is likely mitigated by `c2b787f`, but the exact fault is unproven; native Windows 11 device acceptance remains open.
- Native macOS DnD/IME, Linux DRM hardware, and P15 device gates. Hosted macOS DnD must remain marked skipped when pointer routing is unavailable.
- EDT-17 remains open: moved blocks, whitespace option, unchanged-region folding, generic compare-editor integration, and other registered diff gaps.

## Files Involved

- Code: app/lib/git/git_diff_whitespace_projection.dart, app/lib/git/git_diff_patch_view.dart, app/test/git_diff_whitespace_projection_test.dart, and app/test/git_diff_patch_test.dart. The caller in app/lib/workbench/workbench_page.dart remains outside the GitNexus index due its size.
- Evidence/state: docs/03-里程碑计划与验收标准.md, docs/diagnostics/2026-11-04-p04/p04.101-git-diff-trim-whitespace.md and evidence/, docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md, progress.md, feature_list.json, and this handoff.

## Next Session Startup

1. Read `AGENTS.md`, `session-handoff.md`, and `progress.md`.
2. Finish and push the P04.101 evidence/state commit after running GitNexus detect-changes and validating harness/docs.
3. Confirm PR #2 remains OPEN/draft and both run 41687279291 and run 41687266257 remain successful.
4. Pick the next dependency-ready P04 gap from docs/03 and docs/11, registering one bounded slice before making changes.

## Recommended Next Step

Complete hosted verification for P04.101, determine whether any current CI failures show a new crash signature, and commit the resulting evidence/state update. Keep macOS DnD input-route skips explicit; preserve GitNexus UNKNOWN/CRITICAL warnings, keep PR #2 open/draft, and avoid local GUI/accessibility actions that can start Narrator.
