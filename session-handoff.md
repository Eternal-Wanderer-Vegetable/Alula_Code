# Session Handoff

> Last Updated: 2026-11-03. P04.80 / EDT-13a code commit `75c0690` and evidence/docs commit `9f84b9c` are pushed. PR CI `41567576972`, Platform Availability `41567572708`, and docs CI `41569488846` passed. A follow-up audit of recurring red platform checks is recorded here. PR #2 remains OPEN and draft.

## Current Objective

Continue the fixed Code-OSS 1.145.0 parity plan one slice at a time. Prioritize Linux and Windows usability and then hosted macOS packages. Architecture and features come before numeric memory optimization; the 500 MiB target remains deferred. Native macOS DnD/IME and P15 device checks remain pending because no native macOS host is available. Do not publish v0.1.0, mark PR #2 ready, or merge.

## P04.80 / EDT-13a State

- Whole-word find is implemented and complete: one filtered match list drives count, cycling navigation, editor/minimap highlights, current replacement and replace-all. Case-sensitive and whole-word modes are independent. Literal case-insensitive matches preserve original UTF-16 offsets across lowercase-expanding Unicode.
- Full local DoD passed: `bash init.sh` (Rust workspace, Clippy, core build, Flutter 721), `cargo fmt --all -- --check`, `app/` Flutter analyze (0 issues); 33 focused find/workbench cases passed. No Rust/ABI change. No local GUI or Narrator started.
- PR CI `41567576972` and Platform Availability `41567572708` all passed. Linux and Windows hosted usability checks passed; a macOS ARM64 hosted package was produced. macOS DnD was explicitly skipped because the runner could not route pointer input. Native macOS DnD/IME and P15 remain pending.
- Follow-up review of recurring red Platform Availability runs found Windows MSAA assertion failures with retained client artifacts showing graceful close/exit 0, a PowerShell parse error before launch, and macOS DnD assertion failures with active windows and delivered pointer events. No sampled red job contains the historical crash signature; fixing red probes may improve diagnostic signal but is not evidenced as a crash mitigation.
- Latest 100 branch records: CI 64 success / 0 failures; Platform Availability 26 success / 9 failures; separate exact historical Windows artifact replay 0 success / 1 failure. Historical Windows `0xC000041D` and macOS SIGSEGV remain unresolved; current green smoke runs are non-reproduction evidence only. The P04.80 Dart-only find change has no observed crash mitigation evidence.
- Evidence: `docs/diagnostics/2026-11-03-p04/p04.80-whole-word-find.md`, `docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md`.

## Blockers

- Native macOS DnD/IME and P15 still require a native device/host; hosted DnD explicitly skipped due unavailable input route.
- Historical Windows `0xC000041D` and macOS startup SIGSEGV source causes remain unresolved. Current CI/close/start checks did not reproduce them.

## Files

- P04.80 implementation is in `app/lib/editor/find_replace.dart` and `app/lib/workbench/workbench_page.dart`, with `find_replace_undo_test.dart` and `workbench_bounded_input_test.dart` coverage (commit `75c0690`).
- The documentation-stage commit updates `docs/03`, `progress.md`, `feature_list.json`, this handoff, and the P04.80/crash-correlation diagnostics, including the follow-up failure-versus-crash evidence.

## Next Session

1. Read `docs/03` and `docs/11`, choose the next dependency-ready EDT-13 slice (regex, selection scope, and multiline remain listed gaps), and run GitNexus impact before source edits; keep crash-root investigation separate unless new evidence links it to that slice.
2. Keep PR #2 OPEN and draft. Do not start the local desktop GUI or Narrator. Do not publish v0.1.0 or mark the PR ready.

## Constraints

- Work only in `/tmp/alula-p04.70-next`; never edit `/mnt/e/alula_code`.
- Pushes to `origin/codex/vscode-parity-p00` are authorized. Current checkout is detached; push with `git push origin HEAD:codex/vscode-parity-p00`.
- Avoid local GUI/accessibility tests that can trigger Narrator.
