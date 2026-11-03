# Session Handoff

> Last Updated: 2026-11-03. P04.80 / EDT-13a is hosted-validated. P04.81 / EDT-13b regex Find code commit `4aa5a62` and evidence commit `097d547` are pushed; PR CI `41572068725` and Platform Availability `41572064300` passed. PR #2 remains OPEN and draft.

## Current Objective

Continue the fixed Code-OSS 1.145.0 parity plan one slice at a time. Prioritize Linux and Windows usability and then hosted macOS packages. Architecture and features come before numeric memory optimization; the 500 MiB target remains deferred. Native macOS DnD/IME and P15 device checks remain pending because no native macOS host is available. Do not publish v0.1.0, mark PR #2 ready, or merge.

## P04.80 / EDT-13a State

- Whole-word find is implemented and complete: one filtered match list drives count, cycling navigation, editor/minimap highlights, current replacement and replace-all. Case-sensitive and whole-word modes are independent. Literal case-insensitive matches preserve original UTF-16 offsets across lowercase-expanding Unicode.
- Full local DoD passed: `bash init.sh` (Rust workspace, Clippy, core build, Flutter 721), `cargo fmt --all -- --check`, `app/` Flutter analyze (0 issues); 33 focused find/workbench cases passed. No Rust/ABI change. No local GUI or Narrator started.
- PR CI `41567576972` and Platform Availability `41567572708` all passed. Linux and Windows hosted usability checks passed; a macOS ARM64 hosted package was produced. macOS DnD was explicitly skipped because the runner could not route pointer input. Native macOS DnD/IME and P15 remain pending.
- Follow-up review of recurring red Platform Availability runs found Windows MSAA assertion failures with retained client artifacts showing graceful close/exit 0, a PowerShell parse error before launch, and macOS DnD assertion failures with active windows and delivered pointer events. No sampled red job contains the historical crash signature; fixing red probes may improve diagnostic signal but is not evidenced as a crash mitigation.
- Latest 100 branch records: CI 64 success / 0 failures; Platform Availability 26 success / 9 failures; separate exact historical Windows artifact replay 0 success / 1 failure. Historical Windows `0xC000041D` and macOS SIGSEGV remain unresolved; current green smoke runs are non-reproduction evidence only. The P04.80 Dart-only find change has no observed crash mitigation evidence.
- Evidence: `docs/diagnostics/2026-11-03-p04/p04.80-whole-word-find.md`, `docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md`.

## P04.81 / EDT-13b State

- Regex Find runs in a short-lived, cancellable 750 ms isolate; pattern and result limits are 1,000 and 19,999. Line anchors, explicit multiline matching, whole-word/case options, original UTF-16 ranges, zero-width navigation, invalid/timeout/truncation feedback, stale query and document guards are covered. Regex Replace/capture is deferred to EDT-14; selection scope and history remain later EDT-13 items.
- Full local DoD passed: `bash init.sh` (Rust workspace/Clippy/core build, Flutter 730), cargo fmt, Flutter analyze (0 issues); 42 focused find/workbench tests passed. No Rust/ABI change and no local GUI/Narrator.
- PR CI `41572068725` passed all four jobs with Flutter Analyze 0 issues and 730 tests. Platform Availability `41572064300` passed Linux/Windows/macOS jobs. Windows artifact `13201683521` plus DnD artifact `13201803465`: visible client 1028×681, devicePixelRatio 1.0, 13 pointer events, same-document move, cross-document copy, external text drop, accessibility and close smoke pass. macOS ARM64 package `13202790735`; startup artifact `13202780734` contains only Impeller initialization. DnD artifact `13202362754` records pointer route unavailable and all tests skipped; native macOS DnD/IME and P15 remain pending.
- Code commit `4aa5a62`, interim evidence commit `097d547`. Final hosted evidence and run URLs are in `docs/diagnostics/2026-11-03-p04/p04.81-regex-find.md`.
- GitNexus before-edit: `findMatches` exact/LOW with `replaceAllMatches` as one direct dependent. `_refreshMatches` is UNKNOWN because `workbench_page.dart` is skipped above 512 KiB; source call sites were inspected. Staged/all risk LOW; compare-main CRITICAL reflects accumulated branch divergence. The graph index also omits the large workbench file and has cross-language/flow-budget limits.
- Recurring CI red checks remain a hypothesis for the historical crashes, not an established cause. Existing audit found no shared crash signature in sampled probe/fixture failures. This regex worker reduces UI blocking risk for pathological patterns but does not fix the historical Windows `0xC000041D` or macOS SIGSEGV.

## Blockers

- Native macOS DnD/IME and P15 still require a native device/host; hosted DnD explicitly skipped due unavailable input route.
- Historical Windows `0xC000041D` and macOS startup SIGSEGV source causes remain unresolved. Current CI/close/start checks did not reproduce them.

## Files

- P04.80 implementation is in `app/lib/editor/find_replace.dart` and `app/lib/workbench/workbench_page.dart`, with `find_replace_undo_test.dart` and `workbench_bounded_input_test.dart` coverage (commit `75c0690`).
- P04.81 implementation and tests use the same editor/workbench paths and test files (code commit `4aa5a62`); its local diagnostic is `docs/diagnostics/2026-11-03-p04/p04.81-regex-find.md`.
- P04.80 documentation and the CI/crash audit remain in `docs/03`, `progress.md`, `feature_list.json`, and the P04.80/crash-correlation diagnostics.

## Next Session

1. Finish the evidence documentation commit for P04.81, then choose the next EDT-13 gap (selection scope, multiline behavior, or history) and run GitNexus impact before edits.
2. Keep PR #2 OPEN and draft. Do not start the local desktop GUI or Narrator. Do not publish v0.1.0 or mark the PR ready.

## Constraints

- Work only in `/tmp/alula-p04.70-next`; never edit `/mnt/e/alula_code`.
- Pushes to `origin/codex/vscode-parity-p00` are authorized. Current checkout is detached; push with `git push origin HEAD:codex/vscode-parity-p00`.
- Avoid local GUI/accessibility tests that can trigger Narrator.
