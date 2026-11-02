# Session Handoff

> Last Updated: 2026-11-03. P04.73 / EDT-12b9 implementation and hosted evidence are pushed. Current work is P04.74 / EDT-12c1 choice placeholder parser/session metadata; local DoD passed with Flutter 686, and hosted checks are pending.

## Current Objective

Complete the fixed Code-OSS 1.145.0 parity plan one milestone slice at a time. Current P04.74 supports choice parsing, first-option expansion, immutable options metadata, session range rebasing, and a Linux workbench save/readback fixture. The suggestion list and accepting a choice are intentionally separate open work. Memory-target optimization stays deferred. PR #2 (`codex/vscode-parity-p00`) remains OPEN draft; do not publish v0.1.0 or mark the PR ready before all plan and release gates.

## Current P04.74 Change

- `app/lib/editor/snippet_template.dart`: parse positive-index `${n|...|}` choices, decode `\,`, `\|`, `\\`, use the first option initially, keep malformed choices literal, and cap one choice at 256 options.
- `app/lib/editor/snippet_session.dart`: expose the active first-occurrence choice range and preserve its metadata as linked ranges shift.
- Tests cover parser escapes/fallback/bounds, UTF-16 emoji/CRLF coordinates, metadata rebasing, first-occurrence semantics, insertion, mirror editing, and save/readback. No Rust/ABI changes.
- Local: parser 44, session 7, widget choice fixture passed; `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0 with Flutter 686; cargo fmt and app Flutter analyze pass. No local GUI/Narrator.
- Pinned upstream: [`snippetParser.ts`](https://github.com/microsoft/vscode/blob/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/editor/contrib/snippet/browser/snippetParser.ts), [`snippetSession.ts`](https://github.com/microsoft/vscode/blob/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/editor/contrib/snippet/browser/snippetSession.ts).
- Report: `docs/diagnostics/2026-11-03-p04/p04.74-choice-snippet-parser.md`.

## GitNexus and CI/Crash Evidence

- Bound GitNexus repo: `/tmp/alula-p04.70-next`, indexed base `1ccd3f2`. Before editing, `SnippetExpansion`, `_SnippetTemplateParser`, `_parsePlaceholder`, and `SnippetSession` reported LOW; `SnippetPlaceholderRange` MEDIUM (11 impacted including `_buildEditor`). Residual cross-language property edges and budget-truncated flows are not an all-clear. The final staged/all scan is still required before commit.
- `docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md` distinguishes recent PowerShell/MSAA probe failures from historical Windows `0xC000041D` and macOS SIGSEGV. Current recent hosted close probes exit 0; this does not prove the historical binary crashes are permanently repaired.

## Blockers and Constraints

- No macOS native test host is available; native DnD/IME/P15 checks stay pending. Linux and Windows are first usability gates; a macOS package follows when those gates pass.
- Avoid local desktop GUI/Narrator; use Flutter test binding and hosted CI.
- Work only in `/tmp/alula-p04.70-next`; do not edit the unrelated root checkout `/mnt/e/alula_code`.
- Push to `origin/codex/vscode-parity-p00` is authorized. Preserve PR #2 as open draft.

## Next Steps

1. Finish report and tracking updates, run fresh GitNexus staged/all scans (rerun if partial/truncated), and commit/push the P04.74 implementation stage.
2. Collect PR CI and Platform Availability Linux/Windows/macOS jobs and artifacts; record Mac native-only tests as pending where the hosted runner cannot route input.
3. Make a separate hosted-evidence docs commit. Then continue with the next single EDT-12 slice: choice suggestion list and acceptance UI.
