# Session Handoff

## Last Updated

2026-11-06. User asked to create a branch, open a PR, and complete P05. Branch `codex/vscode-parity-p05` is pushed; draft PR #3 targets `main`: https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/pull/3.

## Current Objective

Complete P05 / feat-027 in sequential, scoped child tasks. P05.1 / feat-053 / LAY-01a through P05.4 / feat-056 / LAY-01d are complete with local and hosted evidence. Continue by registering one next LAY/CMD matrix child at a time; LAY-01 default File menu coverage and macOS native-menu parity still need follow-up. P05 remains open.

Use clean worktree `/tmp/alula-p04.70-next`. The original `/mnt/e/alula_code` worktree contains unrelated user changes; do not modify or clean it. P05.4 product commit `a5c2600` is pushed to draft PR #3. Its full local DoD, PR CI `42079988344`, and Linux/Windows/macOS Intel x64 Platform Availability `42079981274` passed. The macOS test package is artifact `13442660378`; macOS native DnD was explicitly skipped because the hosted runner did not route synthetic pointer events. P05.4 evidence is recorded in `docs/diagnostics/2026-11-06-p05/p05.4-file-menu-catalog-scope.md`; follow-up CI for the evidence commit remains to be checked.

## P05.1 Evidence

- Local full `init.sh` passed: Rust workspace 71+54, Clippy, `build_core`, Flutter 1,030; `cargo fmt --check`; Flutter analyze (0 issues); focused titlebar/config tests 9/9; Harness 100/100; diff check.
- PR CI [42032128727](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/42032128727) on the P05.1 product commit passed all four jobs. Evidence commit `9573290` triggered CI run `42038213800`; recheck before closing the child.
- Platform Availability [42032120138](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/42032120138) passed Linux x64 (5m46s), Windows x64 (11m48s), and macOS Intel x64 (28m58s). Package artifacts: Linux 13415944530, Windows 13417376645, macOS Intel x64 13417219623.
- Linux and Windows DnD/titlebar smoke passed. Windows also passed visible client capture, P03.7 interaction, clipboard, accessibility, and graceful close. macOS Release build, clipboard, bundle/sign, regular and native-titlebar launch, and packaging passed. macOS DnD artifact 13418970398 records `CGEventPostToPid pointer route: false` and `All tests skipped`; do not count DnD as passed. Startup diagnostics: 13417639020. macOS ZIP SHA-256 `bb12d417b2bfdd2239cbba57c02467beb1bd137bedc84b01525b88cb5d50ad5e`; sidecar matched and `unzip -t` passed.
- Hosted macOS is Intel x64 only; Apple Silicon and native-device behavior remain P15. Linux custom mode draws window controls due GTK hidden decorations; Windows custom-control parity and explicit control-style setting remain open. Menu hierarchy, mnemonics, and macOS system menu remain separate work.
- Full scope and details: `docs/diagnostics/2026-11-05-p05/p05.1-titlebar-mode-scope.md`.

## P05.2 Completed

- Scope/pre-edit review: `docs/diagnostics/2026-11-05-p05/p05.2-menu-hierarchy-scope.md`.
- Expected files: `app/lib/workbench/title_bar.dart`, `app/lib/workbench/workbench_page.dart` around the `AlulaTitleBar` assembly at line 16656, `app/test/title_bar_test.dart`, plus tracking/evidence files.
- GitNexus impact for exact `TitleMenuItem` and `AlulaTitleBar` UIDs returned `UNKNOWN` and 0 resolved callers. `context(WorkbenchPage)` failed because the >512 KiB workbench page is not indexed. Text search confirms the only production menu assembly at line 16656 and `TitleMenuItem` construction beginning at line 16661; inspect and test those callers directly.
- Recursive command/submenu/separator model, `View > Appearance`, action visibility/enabled/arguments, and mouse/keyboard submenu interaction are implemented and tested. Mnemonics, full default menu population, and macOS native menu remain separate.
- Local gates passed: `FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` (Rust, Clippy, core build, Flutter 1,032), `cargo fmt --check`, Flutter analyze (0 issues), titlebar suite 8/8, workbench menu integration 1/1, Harness 100/100, feature JSON and diff check. The previously failing menu-driven save case passes after preserving the File menu tooltip.
- PR CI [42044717588](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/42044717588) passed all four jobs, including Flutter analyze and 1,032 tests. Platform Availability [42044705607](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/42044705607) attempt 2 passed Linux x64 (4m30s), Windows x64 (8m56s), and macOS Intel x64 (35m11s). Attempt 1 failed two existing macOS fixed-delay widget assertions, then the exact SHA passed 1,032/1,032 on rerun; no app crash was reported or inferred from those test timing failures.
- Package artifacts Linux/Windows/macOS Intel x64: `13425020073` / `13423773712` / `13427823993`; Linux/Windows DnD passed, macOS DnD artifact `13427973390` explicitly skips because synthetic pointer delivery to Flutter is unavailable. macOS startup diagnostics `13427414246`. macOS ZIP SHA-256 `5a2d3d9916ec45425d04ebb82d41b16733f8eaef07d1eb721c4d67f7056c64af` matches sidecar; unzip integrity passed. Apple Silicon/native-device verification remains P15.
- Latest GitNexus precommit scans varied: all-scope 9 files / 8–13 symbols / 4 processes / MEDIUM; compare-to-main 15 files / 56–67 symbols / 9 processes / HIGH. Menu helper flows were falsely mapped to unrelated Build functions; compare also covers existing titlebar-window paths. Five >512 KiB files including workbench_page.dart are skipped, 779 cross-language property sites are unresolved, and process tracing truncates (902 candidates, 321 callees, 13 walks). Retain HIGH/UNKNOWN; do not call the graph clean.
- Final hosted-evidence docs scan: all-scope touched 5 documentation files with no indexed-symbol overlap (GitNexus explicitly says this is not a clean tree); compare-to-main 15 files / 60 symbols / 9 processes / HIGH. The index was 10,853 nodes / 28,175 edges / 328 clusters / 418 flows; coverage warnings remain.

## Blockers

- No local GUI/Narrator tests; rely on hosted evidence and record unsupported input routes honestly.
- macOS Apple Silicon and native-device checks remain P15. macOS hosted DnD is skipped when synthetic pointer routing is unavailable.
- The 500 MiB goal remains deferred until after architectural replication.

## Files

- P05 reports: `docs/diagnostics/2026-11-05-p05/p05.1-titlebar-mode-scope.md`, `docs/diagnostics/2026-11-05-p05/p05.2-menu-hierarchy-scope.md`
- P05 state: `docs/03-里程碑计划与验收标准.md`, `feature_list.json`, `progress.md`, `session-handoff.md`
- P05 titlebar implementation: `app/lib/main.dart`, `app/lib/workbench/title_bar.dart`, `app/lib/workbench/window_chrome_configuration.dart`, `app/lib/workbench/window_chrome_driver.dart`, and focused tests.

## GitNexus and Worktree Rules

- Current P05.3 GitNexus index is about 11.16k nodes / 31k edges / 332 clusters / 419 flows. All-scope scans vary 8–9 files / 28–44 symbols / 5–11 processes (MEDIUM–HIGH); compare-to-main varies 15 files / 74–96 symbols / 10–11 processes (HIGH). Some menu helpers map to unrelated Build flows and a doc section maps to `InitState → Hunk`; `AlulaTitleBar` callers remain UNKNOWN. Analyzer skips 5 large files including `workbench_page.dart`, leaves 779 cross-language property sites unresolved, and truncates process discovery (911 candidates, 322 callees, 13 trace walks); do not read missing graph edges as unaffected.
- P05.1 evidence scans varied: all-scope 5 files / 1–16 symbols / 0–1 flows / LOW–MEDIUM; compare-to-main 13 files / 50–70 symbols / 5–6 flows / MEDIUM–HIGH. One docs section mapped to unrelated `InitState → Hunk`. Keep these as unresolved graph limitations.
- P05.2 exact pre-edit impact for `TitleMenuItem` and `AlulaTitleBar` is `UNKNOWN`; literal search confirms production assembly in skipped `workbench_page.dart`. Empty caller sets are not an all-clear.
- Do not start local GUI/Narrator tests. Use hosted evidence and record unavailable synthetic input honestly. The 500 MiB goal remains deferred until after architectural replication.

## Recommended Next Step

Register the next single LAY/CMD child from docs/03 and docs/11, run GitNexus impact before code edits, and write its scope/evidence file before implementation. Keep macOS native-menu parity as an explicit LAY-01 follow-up. P05.4 macOS package SHA-256 `5be93632fdc224b98a60dbbc477dcd80e9bbe25c648f5f08c67476b6a924e873` matched its sidecar and `unzip -t` passed. Keep P05 open until every matrix DoD is complete.

## Next Session

1. Commit/push the P05.4 hosted evidence update and check the follow-up PR CI.
2. Select and register the next single LAY/CMD child from docs/03 and docs/11, with pre-edit GitNexus impact analysis.
3. Continue one child at a time; keep native macOS menu parity explicit and do not close P05 until all matrix DoDs pass.

## Baseline

P04 merged to `main` by PR #2 at `46084e95ea0bfd72cf86873339db9670d0ba0b67`. P05.1 product commit `d6e297d8bed8e11b36978e5a0ffb0e8fe2384676`; P05.2 product commit `dd8ae8a`.
