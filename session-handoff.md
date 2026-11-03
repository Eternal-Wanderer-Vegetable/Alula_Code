# Session Handoff

> Last Updated: 2026-11-03. P04.77 / EDT-12d1 is committed as `400a2e0`, pushed, and passed PR CI plus Linux/Windows/macOS hosted build/package lanes. The hosted evidence/status follow-up is staged in `/tmp/alula-p04.70-next`; PR #2 remains OPEN draft.

## Current Objective

Continue fixed Code-OSS 1.145.0 parity one slice at a time. User priority is Linux/Windows usability, followed by a hosted macOS package. Native macOS DnD/IME and P15 device checks remain pending without a native host. Keep memory optimization deferred. Do not publish v0.1.0, mark PR #2 ready, or merge before all release gates.

## P04.77 / EDT-12d1 Current State

- Variable transforms `${VAR/regex/format/options}` are implemented with captures, conditional/default formats, case formats, flags, and bounded short-lived isolates. Placeholder transforms remain open. The parser/workbench edit uses no Rust or ABI changes.
- Workbench post-await snapshot validation rejects stale edits and controller disposal. Targeted snippet parser/session/workbench tests passed; full `bash init.sh` passed with 708 Flutter tests; `cargo fmt --all -- --check` and `flutter analyze --no-pub` passed. PR CI `41553470823` passed all four jobs with 708 Flutter tests. Platform Availability `41553465771` passed Linux, Windows, and macOS jobs; Linux/Windows hosted DnD passed, Windows close exit code was 0, and a macOS ARM64 package was produced. macOS native DnD skipped because the pointer input route was unavailable; native DnD/IME and P15 device checks remain pending.
- Local mem-probe harness measured 100×128 Ki UTF-16 expansions with and without transforms. The comparison and limitations are in `docs/diagnostics/2026-11-03-p04/p04.77-snippet-variable-transforms.md`; it is not an Alula GUI or cross-platform baseline.
- GitNexus reports `_SnippetTemplateParser` LOW, `expandSnippetTemplate` and `snippetTemplateUsesVariable` UNKNOWN, and `SnippetExpansion`/`SnippetPlaceholderRange` CRITICAL. UNKNOWN callers were text-searched; `workbench_page.dart` is above the index's 512 KiB file cap. Preserve unresolved graph warnings and include staged/all scans before commit.
- The regression test found an async worker/controller-lifetime hazard in this new snippet path; it is fixed and covered for concurrent editing and closing. Current hosted CI passed those cases. It does not identify the old Windows `0xC000041D` or macOS SIGSEGV root cause; P04.77 adds only non-reproduction evidence.

## Next Steps

1. The staged P04.77 hosted-evidence update has a docs-only GitNexus staged/all scan; both report CRITICAL with broad flow mappings retained. Commit/push this evidence stage and verify its CI.
2. Keep PR #2 open as draft and continue with the next explicit `docs/03` item after the docs commit CI clears. Keep crash triage based on exit codes, process logs, and crash artifacts; do not infer a source crash from probe or fixture routing failures.

## Constraints

- Work only in `/tmp/alula-p04.70-next`; do not edit `/mnt/e/alula_code`.
- Push to `origin/codex/vscode-parity-p00` is authorized. Keep PR #2 OPEN draft.
- No local GUI/Narrator. Keep macOS native DnD/IME and P15 pending until a native host is available.
