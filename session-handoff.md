# Session Handoff

> Last Updated: 2026-11-03. P04.88 / EDT-15c is complete. Code commit `fd53c85` and its separate evidence/docs commit are pushed. PR CI and Linux/Windows/macOS hosted availability passed for the code commit; verify the documentation commit checks before the next slice. PR #2 remains OPEN/draft.

## Current Objective

Continue fixed Code-OSS 1.145.0 parity one slice at a time. Prioritize Linux and Windows usability, then provide hosted macOS packages. Architecture and feature parity come before numeric memory optimization; 500 MiB remains deferred. Linux DRM, native macOS DnD/IME, Windows 11 multi-configuration, and P15 device gates remain open. Do not publish v0.1.0, mark PR #2 ready, or merge.

## Latest Completed Slice: P04.88 / EDT-15c

- Ctrl+F / `editor.find` seeds Find from a non-empty single-line selection shorter than 524,288 UTF-16 units, read from Rust authority; regex metacharacters are escaped. Empty, multiline, over-limit, stale, pending/IME, and read-failure cases preserve the old query. Ctrl+H Replace and cursor-at-word seeding are separate work.
- Focused tests: 12 passed. Full `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh`: Rust workspace, Clippy, `build_core`, Flutter 776 all passed. `cargo fmt --all -- --check`, Flutter analyze (0 issues), and harness validation (100/100) passed. Query, hit result, emoji UTF-16 offsets, selection, Rust version, dirty state, disk bytes, and Ctrl+Z were checked. No local GUI or Narrator was started.
- Code commit `fd53c85` is pushed. PR CI [`41600604418`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41600604418) passed all four jobs; Platform Availability [`41600596922`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41600596922) passed Linux, Windows, and macOS jobs. Linux and Windows DnD artifacts recorded actual pointer events and all three drop routes. macOS ARM64 package produced; startup log had only one Metal/Impeller line and no crash report. macOS DnD was skipped because hosted pointer input was unavailable.
- Latest 100 branch Actions at `fd53c85`: regular CI 65/0, Platform Availability 28/6, plus one historical Windows artifact replay crash. The six recurring probe failures have no shared crash signature; the old binary replay alone confirms `0xC000041D`. Current green close/startup checks are non-reproduction evidence, not a crash fix. Details: `docs/diagnostics/2026-11-03-p04/p04.88-selection-seeded-find.md` and `ci-failures-and-crash-correlation.md`.
- GitNexus code-only all-scope: 5 files / 5 symbols / 0 processes / LOW. Refreshed docs-only scans vary between 5–12 Section symbols and 16–37 affected flows, all CRITICAL; text search found none of the generated RunBuildCommand/Cargokit names in those docs, so retain this unresolved graph warning. Docs compare-main varies between 2,731–2,955 symbols (1,579 files / 400 flows), CRITICAL with a capped listing and analyzer truncation; do not report it as clean.

## Current Workspace State

- Work only in `/tmp/alula-p04.70-next`; the checkout is detached. The current P04.88 evidence commit is pushed to `codex/vscode-parity-p00`.
- PR #2 is OPEN/draft. Verify CI for the latest docs commit and confirm PR state before starting the next slice.
- P04.88 acceptance and evidence are recorded in `docs/03-里程碑计划与验收标准.md`, `feature_list.json`, `progress.md`, and the diagnostic report above.

## Next Session

1. Check the latest docs-commit PR CI and Platform Availability results; confirm PR #2 remains OPEN/draft.
2. Select one dependency-ready follow-up from `docs/03`; P04.89 cursor-at-word Find seeding is the planned next Find slice. Register its acceptance row before source edits.
3. Run GitNexus impact before editing; retain CRITICAL/UNKNOWN warnings. Run full local DoD, update evidence, run all-scope and compare-main checks, then commit and push in stages.

## Constraints

- Never edit `/mnt/e/alula_code`; only use `/tmp/alula-p04.70-next`.
- Pushes to `origin/codex/vscode-parity-p00` are authorized; this checkout is detached, so push with `git push origin HEAD:codex/vscode-parity-p00`.
- Avoid local GUI/accessibility checks that can trigger Narrator. Hosted checks do not run on the user's machine.
