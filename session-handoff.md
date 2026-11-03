# Session Handoff

> Last Updated: 2026-11-03. P04.90 / EDT-15e is complete. Code commit `c65f340` is pushed; PR CI `41611944873` and Platform Availability `41611937616` passed; PR #2 remains OPEN/draft.

## Current Objective

Continue the fixed Code-OSS 1.145.0 parity plan one slice at a time. Prioritize architecture and Linux/Windows usability, then provide hosted macOS packages. Numeric memory optimization remains deferred. Do not publish v0.1.0, mark PR #2 ready, or merge.

## Latest Completed Slice: P04.90 / EDT-15e

- Escape, Shift+Escape, and the Find close button hide Find/Replace, clear Find-in-Selection scope, preserve the query, and restore focus to the same active editor after the widget unmounts. If the active document/group changed during the close frame, focus is not stolen. Document/version, selection, dirty/savepoint, disk, and text undo remain unchanged.
- Dedicated close widget fixture and focused Find/Replace regressions passed (1 + 22). Full `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh`: Rust workspace, Clippy, `build_core`, Flutter 782 all passed. `cargo fmt --all -- --check`, Flutter analyze (0 issues), `git diff --check`, and harness validation (100/100) passed. No local GUI or Narrator was started.
- Code commit `c65f340` is pushed. PR CI [`41611944873`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41611944873) passed all four jobs. Platform Availability [`41611937616`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41611937616) passed Linux, Windows, and macOS jobs: Linux DnD artifact `13220110381` has 20 pointer events and all three drop routes; Windows DnD artifact `13219622795` has 13 events and all three routes, client artifact `13220455435` records visible 1028×711 / 96 DPI, UIA/MSAA and graceful close exit 0; macOS ARM64 package `13220810721` and startup probe `13221135196` generated, clipboard passed, native DnD artifact `13219549723` explicitly skipped for unavailable pointer routing.
- Full test, artifact, and GitNexus coverage notes: [`p04.90-find-close-focus.md`](docs/diagnostics/2026-11-03-p04/p04.90-find-close-focus.md). This change does not explain or fix the historical Windows `0xC000041D` crash.

## Previous Completed Slice: P04.89 / EDT-15d

- Ctrl+F / `editor.find` seeds Find from the default word at a collapsed caret. It uses the pinned Code-OSS word regex and a bounded 1,000 UTF-16-unit context from Rust-authoritative text; regex mode searches the word literally. Empty separators, stale/IME/read failures preserve the previous query. Non-empty selections still use P04.88 behavior. Document, version, dirty/savepoint, disk, cursor, and text undo remain unchanged.
- Focused tests: 17 passed. Full `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh`: Rust workspace, Clippy, `build_core`, Flutter 781 all passed. `cargo fmt --all -- --check`, Flutter analyze (0 issues), `git diff --check`, and harness validation (100/100) passed. No local GUI or Narrator was started.
- Code commit `879e3a6` is pushed. PR CI [`41605702841`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41605702841) and Platform Availability [`41605695280`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41605695280) passed. Linux/Windows Release and actual DnD routes passed. macOS ARM64 test package, clipboard, and startup probe passed; native DnD was skipped because the hosted runner did not route synthetic pointer input.
- The latest 100 branch Actions remain 65 CI success / 0 failure, 28 Platform Availability success / 6 failure, plus one old Windows artifact replay failure. The replay captured a genuine `0xC000041D` close crash in a historical artifact. The sampled Platform reds are separate signatures (PowerShell encoding, MSAA semantic text, clipboard format assertions); no causal link to that crash is established. Review [`ci-failures-and-crash-correlation.md`](docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md).

## Current Workspace State

- Work only in `/tmp/alula-p04.70-next`; the checkout is detached. Pushes to `origin/codex/vscode-parity-p00` are authorized with `git push origin HEAD:codex/vscode-parity-p00`.
- P04.89 behavior and evidence are recorded in `docs/03-里程碑计划与验收标准.md`, `feature_list.json`, `progress.md`, and `docs/diagnostics/2026-11-03-p04/p04.89-caret-word-find-seed.md`.
- P04.90 behavior/evidence are recorded in `docs/03-里程碑计划与验收标准.md`, `feature_list.json`, `progress.md`, and `docs/diagnostics/2026-11-03-p04/p04.90-find-close-focus.md`.
- PR #2 must remain OPEN/draft. Do not publish or merge.

## Blockers

- Native macOS DnD/IME, Linux DRM hardware validation, and Windows 11 client/P15 device gates have no evidence from this session. The hosted macOS pointer route was unavailable.
- The historical Windows `0xC000041D` source cause remains unknown. Do not claim that passing current close checks repaired it.

## Files

- P04.90 code/test: `app/lib/workbench/workbench_page.dart`, `app/test/workbench_find_close_test.dart` (commit `c65f340`).
- P04.89 code/tests: `app/lib/editor/find_replace.dart`, `app/lib/workbench/workbench_page.dart`, `app/test/find_selection_seed_test.dart`, `app/test/workbench_regex_replace_test.dart` (commit `879e3a6`).
- Evidence/state: `docs/03-里程碑计划与验收标准.md`, `docs/diagnostics/2026-11-03-p04/p04.89-caret-word-find-seed.md`, `docs/diagnostics/2026-11-03-p04/p04.90-find-close-focus.md`, `docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md`, `feature_list.json`, `progress.md`, `session-handoff.md`.

## Next Priority

Choose the next dependency-ready P04 row from `docs/03` and register a narrow slice before editing. Continue one feature at a time. The recurring CI failure/crash correlation check is complete; no causal link or crash fix has been established.

### Next Session First Step

Run GitNexus status and refresh the index if stale, then select the next dependency-ready item from `docs/03`. `workbench_page.dart` exceeds the current index limit; preserve its UNKNOWN impact warning and use source-level call-site review for future edits.

## Constraints

- Avoid local GUI/accessibility checks that can trigger Narrator. Hosted checks run remotely and are acceptable.
- Retain unresolved GitNexus CRITICAL/UNKNOWN warnings; do not call capped graph scans clean.
- No macOS native DnD/IME, Linux DRM, Windows 11 client, or P15 hardware evidence has been supplied by this turn. Keep those gates open.
