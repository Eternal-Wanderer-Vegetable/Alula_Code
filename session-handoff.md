# Session Handoff

> Last Updated: 2026-11-03. P04.78 / EDT-12d2 code is committed as `08e0bcf` and pushed. PR CI `41558120044` and Linux/Windows/macOS hosted build/package run `41558114011` passed. The hosted evidence and status follow-up is included in the docs-stage commit; PR #2 remains OPEN draft.

## Current Objective

Continue fixed Code-OSS 1.145.0 parity one slice at a time. User priority is Linux/Windows usability, followed by a hosted macOS package. Native macOS DnD/IME and P15 device checks remain pending without a native host. Memory optimization is deferred. Do not publish v0.1.0, mark PR #2 ready, or merge before all release gates.

## P04.78 / EDT-12d2 Current State

- Placeholder transforms `${n/regex/format/options}` run before navigation leaves the current tabstop; independent occurrences use their own current text. No-match without a nonempty else/default retains original text. Tab, Shift+Tab, and choice acceptance share the transform path.
- The async path revalidates document/session/controller, Rust version, bounded input window, selection, and editing value after worker completion. Replacements use one Rust transaction and are undoable; stale worker results are discarded. Multiline output keeps insertion-line indentation and CRLF save/readback. No Rust/ABI changes.
- Focused parser/session/workbench tests passed (94); `bash init.sh` passed with 713 Flutter tests plus Rust workspace, Clippy, and `build_core`; cargo fmt and Flutter analyze (0 issues) passed.
- Hosted CI run `41558120044` passed all four jobs. Platform run `41558114011` passed Linux, Windows, and macOS jobs. Linux/Windows DnD recorded pointer events and move/copy/external text; Windows client metadata records 1028×711 at 96 DPI, UI Automation available, and graceful close/exit 0; macOS ARM64 package was produced. macOS DnD skipped because the hosted runner did not route synthetic pointer input into Flutter.
- GitNexus exact-slice scans report CRITICAL with capped affected-process lists; compare to `main` spans the entire historical parity branch and is also capped. The refreshed index is up to date at `08e0bcf`; source file size and cross-language mappings still limit graph coverage. Preserve these warnings rather than treating them as an all-clear.
- Current hosted runs did not reproduce the historical Windows `0xC000041D` or macOS SIGSEGV. The transform lifecycle race found in this slice is guarded and covered by a concurrent-edit test; it does not identify the old native crash root cause.

## Next Steps

1. Verify the docs evidence commit CI passes; keep PR #2 open as a draft.
2. Read `docs/03-里程碑计划与验收标准.md` and take the next dependency-ready P04 item as one slice. Keep crash correlation based on exact failing steps, process exit codes, and crash artifacts.
3. Keep native macOS DnD/IME and P15 device verification marked pending until a native host is available. Do not publish v0.1.0 or mark the PR ready.

## Constraints

- Work only in `/tmp/alula-p04.70-next`; do not edit `/mnt/e/alula_code`.
- Push to `origin/codex/vscode-parity-p00` is authorized. Keep PR #2 OPEN draft.
- Do not start the local desktop GUI or Narrator for automated verification.
