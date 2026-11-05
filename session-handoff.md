# Session Handoff

## Last Updated

2026-11-05. User asked to create a branch, open a PR, and complete P05. Branch `codex/vscode-parity-p05` is pushed; draft PR #3 targets `main`: https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/pull/3.

## Current Objective

Complete P05 / feat-027 in sequential, scoped child tasks. P05.1 / feat-053 / LAY-01a is complete and its hosted evidence is committed at `9573290`; P05 and LAY-01 remain open. P05.2 / feat-054 / LAY-01b implementation and local DoD are complete; the product/evidence commit still needs PR CI and Linux/Windows/macOS Intel x64 hosted validation. Continue one child at a time until all 20 LAY and 12 CMD rows have evidence.

Use clean worktree `/tmp/alula-p04.70-next`. The original `/mnt/e/alula_code` worktree contains unrelated user changes; do not modify or clean it.

## P05.1 Evidence

- Local full `init.sh` passed: Rust workspace 71+54, Clippy, `build_core`, Flutter 1,030; `cargo fmt --check`; Flutter analyze (0 issues); focused titlebar/config tests 9/9; Harness 100/100; diff check.
- PR CI [42032128727](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/42032128727) on the P05.1 product commit passed all four jobs. Evidence commit `9573290` triggered CI run `42038213800`; recheck before closing the child.
- Platform Availability [42032120138](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/42032120138) passed Linux x64 (5m46s), Windows x64 (11m48s), and macOS Intel x64 (28m58s). Package artifacts: Linux 13415944530, Windows 13417376645, macOS Intel x64 13417219623.
- Linux and Windows DnD/titlebar smoke passed. Windows also passed visible client capture, P03.7 interaction, clipboard, accessibility, and graceful close. macOS Release build, clipboard, bundle/sign, regular and native-titlebar launch, and packaging passed. macOS DnD artifact 13418970398 records `CGEventPostToPid pointer route: false` and `All tests skipped`; do not count DnD as passed. Startup diagnostics: 13417639020. macOS ZIP SHA-256 `bb12d417b2bfdd2239cbba57c02467beb1bd137bedc84b01525b88cb5d50ad5e`; sidecar matched and `unzip -t` passed.
- Hosted macOS is Intel x64 only; Apple Silicon and native-device behavior remain P15. Linux custom mode draws window controls due GTK hidden decorations; Windows custom-control parity and explicit control-style setting remain open. Menu hierarchy, mnemonics, and macOS system menu remain separate work.
- Full scope and details: `docs/diagnostics/2026-11-05-p05/p05.1-titlebar-mode-scope.md`.

## P05.2 Implementation and Pending Hosted Evidence

- Scope/pre-edit review: `docs/diagnostics/2026-11-05-p05/p05.2-menu-hierarchy-scope.md`.
- Expected files: `app/lib/workbench/title_bar.dart`, `app/lib/workbench/workbench_page.dart` around the `AlulaTitleBar` assembly at line 16656, `app/test/title_bar_test.dart`, plus tracking/evidence files.
- GitNexus impact for exact `TitleMenuItem` and `AlulaTitleBar` UIDs returned `UNKNOWN` and 0 resolved callers. `context(WorkbenchPage)` failed because the >512 KiB workbench page is not indexed. Text search confirms the only production menu assembly at line 16656 and `TitleMenuItem` construction beginning at line 16661; inspect and test those callers directly.
- Recursive command/submenu/separator model, `View > Appearance`, action visibility/enabled/arguments, and mouse/keyboard submenu interaction are implemented and tested. Mnemonics, full default menu population, and macOS native menu remain separate.
- Local gates passed: `FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` (Rust, Clippy, core build, Flutter 1,032), `cargo fmt --check`, Flutter analyze (0 issues), titlebar suite 8/8, workbench menu integration 1/1, Harness 100/100, feature JSON and diff check. The previously failing menu-driven save case passes after preserving the File menu tooltip.
- Refresh GitNexus before committing current tracker/evidence changes. Latest product scan: 10,841 nodes / 27,278 edges / 328 clusters / 418 flows; all-scope 4 files / 8 symbols / 4 processes / MEDIUM; compare-to-main 15 files / 80 symbols / 10 processes / HIGH. Analyzer skips 5 large files including workbench_page.dart, leaves 779 cross-language property references unresolved, and truncates process discovery (902 candidates, 321 callees, 13 walks). Several mapped processes are false-positive/unrelated; retain HIGH and UNKNOWN without calling the graph clean.

## Blockers

- No local GUI/Narrator tests; rely on hosted evidence and record unsupported input routes honestly.
- macOS Apple Silicon and native-device checks remain P15. macOS hosted DnD is skipped when synthetic pointer routing is unavailable.
- The 500 MiB goal remains deferred until after architectural replication.

## Files

- P05 reports: `docs/diagnostics/2026-11-05-p05/p05.1-titlebar-mode-scope.md`, `docs/diagnostics/2026-11-05-p05/p05.2-menu-hierarchy-scope.md`
- P05 state: `docs/03-里程碑计划与验收标准.md`, `feature_list.json`, `progress.md`, `session-handoff.md`
- P05 titlebar implementation: `app/lib/main.dart`, `app/lib/workbench/title_bar.dart`, `app/lib/workbench/window_chrome_configuration.dart`, `app/lib/workbench/window_chrome_driver.dart`, and focused tests.

## GitNexus and Worktree Rules

- GitNexus index refreshed against commit `9573290`: 10,829 nodes / 27,140 edges / 328 clusters / 418 flows. P05.2 scope scans: all-scope 5 files / 8 symbols / 0 processes / LOW; compare-to-main 14 files / 60 symbols / 6 flows / HIGH. Analyzer skips 5 large files including `workbench_page.dart`, leaves 779 cross-language property sites unresolved, and truncates process discovery (899 candidates, 321 callees, 13 trace walks); do not read missing graph edges as unaffected.
- P05.1 evidence scans varied: all-scope 5 files / 1–16 symbols / 0–1 flows / LOW–MEDIUM; compare-to-main 13 files / 50–70 symbols / 5–6 flows / MEDIUM–HIGH. One docs section mapped to unrelated `InitState → Hunk`. Keep these as unresolved graph limitations.
- P05.2 exact pre-edit impact for `TitleMenuItem` and `AlulaTitleBar` is `UNKNOWN`; literal search confirms production assembly in skipped `workbench_page.dart`. Empty caller sets are not an all-clear.
- Do not start local GUI/Narrator tests. Use hosted evidence and record unavailable synthetic input honestly. The 500 MiB goal remains deferred until after architectural replication.

## Recommended Next Step

Commit and push P05.2 implementation plus evidence, wait for PR CI and Platform Availability, record platform artifacts/explicit skips, then start exactly one next P05 child.

## Next Session

1. Check PR CI run `42038213800` for the P05.1 evidence commit if still needed.
2. Finish updating P05.2 evidence, refresh GitNexus and run all/compare change detection for the final staged changes.
3. Commit/push the P05.2 product and evidence; wait for PR CI and Platform Availability.
4. Record hosted results (including explicit macOS input skips and Intel-only coverage), mark P05.2 done only when gates pass, then register the next single P05 child.

## Baseline

P04 merged to `main` by PR #2 at `46084e95ea0bfd72cf86873339db9670d0ba0b67`. P05 product implementation commit is `d6e297d8bed8e11b36978e5a0ffb0e8fe2384676`.
