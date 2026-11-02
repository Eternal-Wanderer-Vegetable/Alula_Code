# Session Handoff

> Last Updated: 2026-11-03. P04.74 / EDT-12c1 (`816ac70`, `08723ef`) and P04.75 / EDT-12c2 implementation (`58fdd31`) are pushed. P04.75 local DoD and hosted CI / Linux / Windows / macOS build-package checks passed; the separate hosted-evidence documentation commit is being prepared. PR #2 remains OPEN draft.

## Current Objective

Complete the fixed Code-OSS 1.145.0 parity plan one milestone slice at a time. P04.75 adds the active-choice list, arrow preview, click/Enter/Tab accept, Shift+Tab navigation, and Escape dismissal while preserving the session; local and hosted checks pass. Linux/Windows availability and macOS ARM64 packaging passed. Memory-target optimization stays deferred. PR #2 (`codex/vscode-parity-p00`) remains OPEN draft; do not publish v0.1.0 or mark the PR ready before all plan and release gates.

## Previous P04.74 Change

- `app/lib/editor/snippet_template.dart`: parse positive-index `${n|...|}` choices, decode `\,`, `\|`, `\\`, use the first option initially, keep malformed choices literal, and cap one choice at 256 options.
- `app/lib/editor/snippet_session.dart`: expose the active first-occurrence choice range and preserve its metadata as linked ranges shift.
- Tests cover parser escapes/fallback/bounds, UTF-16 emoji/CRLF coordinates, metadata rebasing, first-occurrence semantics, insertion, mirror editing, and save/readback. No Rust/ABI changes.
- Local: parser 44, session 7, widget choice fixture passed; `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0 with Flutter 686; cargo fmt and app Flutter analyze pass. No local GUI/Narrator.
- Pinned upstream: [`snippetParser.ts`](https://github.com/microsoft/vscode/blob/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/editor/contrib/snippet/browser/snippetParser.ts), [`snippetSession.ts`](https://github.com/microsoft/vscode/blob/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/editor/contrib/snippet/browser/snippetSession.ts).
- Report: `docs/diagnostics/2026-11-03-p04/p04.74-choice-snippet-parser.md`.


## Current P04.75 Change

- Added the bounded, caret-anchored choice list with Up/Down preview, click/Enter/Tab acceptance, Shift+Tab navigation, and two-stage Escape behavior.
- Choice acceptance selects the complete active and linked ranges, applies through the existing multi-selection formatter/Rust input path, and moves to the next tabstop. No Rust/ABI change; `_onInputDelta` and `_setDocSelections` implementations remain untouched.
- Local validation passed: full `init.sh` with 688 Flutter tests, `cargo fmt --all -- --check`, and Flutter analyze. No local GUI/Narrator.
- Final staged/all graph scans report 8 changed files at CRITICAL, with 52–180 affected-process entries across refreshed snapshots; exact caret-scroll helper risk is MEDIUM and class-level `RustTextInputFieldState` remains CRITICAL (380 impacted); review and limitations are recorded in `docs/diagnostics/2026-11-03-p04/p04.75-choice-snippet-ui.md`.
- Hosted PR CI `41537293168` passed all jobs; Platform Availability `41537286459` passed Linux, Windows, and macOS. Linux/Windows package and native interaction evidence passed; Windows close metadata has exit code 0. macOS package/startup passed, while native DnD is skipped because `CGEventPostToPid pointer route=false`. Artifacts and limitations are in the P04.75 report.
- Latest 100 Actions records: CI 61/61 success; Platform Availability 23 success / 15 failure. Recent red platform checks are probes/fixtures; one Windows launch run (`41454766999`) failed parsing PowerShell before launching Alula. Keep this distinct from the confirmed historical Windows `0xC000041D` and macOS SIGSEGV, whose source-level roots remain unresolved. See `ci-failures-and-crash-correlation.md`.
- Keep macOS native DnD/IME/P15 and historical crash root-cause status pending.

## GitNexus and CI/Crash Evidence

- Bound GitNexus repo: `/tmp/alula-p04.70-next`, refreshed at `58fdd31`. Before editing, `SnippetExpansion`, `_SnippetTemplateParser`, `_parsePlaceholder`, and `SnippetSession` reported LOW; `SnippetPlaceholderRange` MEDIUM (11 impacted including `_buildEditor`). After an intermediate no-symbol-overlap result was repeated, final staged/all/compare scans mapped only documentation sections across 6 docs/status files, 0 affected processes, LOW, with no partial/truncated output. Residual cross-language edges and budget-truncated flows remain.
- `docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md` distinguishes recent PowerShell/MSAA probe failures from historical Windows `0xC000041D` and macOS SIGSEGV. Current hosted close probes exit 0, including P04.74 Windows metadata; the latest macOS startup artifact contains no crash report. These are non-reproduction results, not proof that historical crash causes are permanently repaired.

## Blockers and Constraints

- No macOS native test host is available; native DnD/IME/P15 checks stay pending. Linux and Windows are first usability gates; a macOS package follows when those gates pass.
- Avoid local desktop GUI/Narrator; use Flutter test binding and hosted CI.
- Work only in `/tmp/alula-p04.70-next`; do not edit the unrelated root checkout `/mnt/e/alula_code`.
- Push to `origin/codex/vscode-parity-p00` is authorized. Preserve PR #2 as open draft.

## Next Steps

1. Finish the P04.75 hosted-evidence documentation stage: reindex GitNexus, scan staged/all changes, then commit and push docs03, progress, handoff, feature evidence, and diagnostic reports.
2. Confirm the documentation commit's PR CI; keep PR #2 open as draft and do not publish v0.1.0 or mark the PR ready.
3. Choose and decompose the next unfinished EDT item from `docs/03` and `docs/11`; retain macOS native DnD/IME/P15 and historical crash root-cause checks as pending.
