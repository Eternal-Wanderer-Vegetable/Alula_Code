# Session Handoff

> Last Updated: 2026-11-03. P04.79 / EDT-12e and its documentation evidence are committed and pushed (`511ec3c`, `da382b5`). PR #2 remains OPEN and draft. P04.80 / EDT-13a whole-word find is now in progress.

## Current Objective

Continue the fixed Code-OSS 1.145.0 parity plan one slice at a time. Prioritize Linux and Windows usability and then hosted macOS packages. Architecture and features come before numeric memory optimization; the 500 MiB target remains deferred. Native macOS DnD/IME and P15 device checks remain pending because no native macOS host is available. Do not publish v0.1.0, mark PR #2 ready, or merge.

## P04.80 / EDT-13a Current State

- Add a find-bar whole-word toggle using the workbench's existing default word-separator set plus whitespace. One filtered match list must drive counts, previous/next navigation, editor decorations, minimap markers, current replacement, and replace-all.
- Case-sensitive and whole-word modes remain independent. Case-insensitive matching must report positions in the original UTF-16 string even where Unicode lowercase mapping changes length.
- Logic and workbench integration cases cover punctuation/underscore boundaries, emoji, CRLF, BOM, case mapping, current replacement and replace-all. The focused find/workbench suite passed (33); full `bash init.sh` passed (Rust workspace, Clippy, core build, Flutter 721). `cargo fmt --all -- --check`, `app/` Flutter analyze (0 issues), and `git diff --check` passed.
- GitNexus impact: `findMatches` exact/LOW; `replaceAllMatches` UNKNOWN, confirmed used by source search. `workbench_page.dart` exceeds the GitNexus source-file indexing threshold; its relevant handlers are treated as UNKNOWN and were confirmed by text search. No Rust/ABI change is planned.
- The latest P04.79 host runs passed. Historical Windows `0xC000041D` and macOS startup SIGSEGV remain unresolved and have not been correlated to recent CI probe/fixture failures; current green close/start smoke is non-reproduction evidence only.

## Next Steps

1. Finish GitNexus change analysis; preserve UNKNOWN/truncation caveats and review the final diff.
2. Commit the P04.80 implementation, push the authorized branch, and wait for PR CI plus Platform Availability Linux/Windows evidence and hosted macOS package evidence.
3. Record run/artifact evidence in `docs/03`, `progress.md`, `session-handoff.md`, and a P04.80 diagnostic report; make a separate documentation-stage commit.
4. Keep the PR OPEN and draft. Do not run the local desktop GUI or Narrator. Native macOS DnD/IME and P15 remain pending.

## Constraints

- Work only in `/tmp/alula-p04.70-next`; never edit `/mnt/e/alula_code`.
- Pushes to `origin/codex/vscode-parity-p00` are authorized. Current checkout is detached; use `git push origin HEAD:codex/vscode-parity-p00`.
- Avoid local GUI/accessibility tests that can trigger Narrator.
