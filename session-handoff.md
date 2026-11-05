# Session Handoff

## Last Updated

2026-11-05. User asked to create a branch, open a PR, and complete P05. Branch `codex/vscode-parity-p05` is pushed; draft PR #3 targets `main`: https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/pull/3.

## Current Objective

Complete P05 / feat-027 in sequential, scoped child tasks. P05.1 / feat-053 / LAY-01a is complete; P05 and LAY-01 remain open. The current evidence update is not yet committed. After its push and PR CI, register exactly one next P05 child from the LAY/CMD matrix, then continue until all 20 LAY and 12 CMD rows have evidence.

Use clean worktree `/tmp/alula-p04.70-next`. The original `/mnt/e/alula_code` worktree contains unrelated user changes; do not modify or clean it.

## P05.1 Evidence

- Local full `init.sh` passed: Rust workspace 71+54, Clippy, `build_core`, Flutter 1,030; `cargo fmt --check`; Flutter analyze (0 issues); focused titlebar/config tests 9/9; Harness 100/100; diff check.
- PR CI [42032128727](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/42032128727) passed all four jobs.
- Platform Availability [42032120138](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/42032120138) passed Linux x64 (5m46s), Windows x64 (11m48s), and macOS Intel x64 (28m58s). Package artifacts: Linux 13415944530, Windows 13417376645, macOS Intel x64 13417219623.
- Linux and Windows DnD/titlebar smoke passed. Windows also passed visible client capture, P03.7 interaction, clipboard, accessibility, and graceful close. macOS Release build, clipboard, bundle/sign, regular and native-titlebar launch, and packaging passed. macOS DnD artifact 13418970398 records `CGEventPostToPid pointer route: false` and `All tests skipped`; do not count DnD as passed. Startup diagnostics: 13417639020. macOS ZIP SHA-256 `bb12d417b2bfdd2239cbba57c02467beb1bd137bedc84b01525b88cb5d50ad5e`; sidecar matched and `unzip -t` passed.
- Hosted macOS is Intel x64 only; Apple Silicon and native-device behavior remain P15. Linux custom mode draws window controls due GTK hidden decorations; Windows custom-control parity and explicit control-style setting remain open. Menu hierarchy, mnemonics, and macOS system menu remain separate work.
- Full scope and details: `docs/diagnostics/2026-11-05-p05/p05.1-titlebar-mode-scope.md`.

## Blockers

- No local GUI/Narrator tests; rely on hosted evidence and record unsupported input routes honestly.
- macOS Apple Silicon and native-device checks remain P15. macOS hosted DnD is skipped when synthetic pointer routing is unavailable.
- The 500 MiB goal remains deferred until after architectural replication.

## Files

- P05.1 report: `docs/diagnostics/2026-11-05-p05/p05.1-titlebar-mode-scope.md`
- P05 state: `docs/03-里程碑计划与验收标准.md`, `feature_list.json`, `progress.md`, `session-handoff.md`
- P05 titlebar implementation: `app/lib/main.dart`, `app/lib/workbench/title_bar.dart`, `app/lib/workbench/window_chrome_configuration.dart`, `app/lib/workbench/window_chrome_driver.dart`, and focused tests.

## GitNexus and Worktree Rules

- GitNexus index was refreshed against product head `d6e297d`: 10,821 nodes / 26,755 edges / 328 clusters / 418 flows. Repeated evidence scans varied: all-scope 5 files / 1–16 symbols / 0–1 flows / LOW–MEDIUM (recently 5 / 16 / 0 / LOW); compare-to-main 13 files / 50–70 symbols / 5–6 flows / MEDIUM–HIGH (recently 13 / 70 / 5 / MEDIUM). One doc-section mapped to unrelated `InitState → Hunk`; no partial/truncated marker appeared, but the graph is not clean. Retain the analyzer coverage caveats below.
- Pre-edit `AlulaTitleBar` impact was `UNKNOWN`; literal search confirmed production assembly in `app/lib/workbench/workbench_page.dart`, a >512 KiB file skipped by the index. Empty callers are not an all-clear. Prior post-edit scans varied; graph is not clean.
- Do not start local GUI/Narrator tests. Use hosted evidence and record unavailable synthetic input honestly. The 500 MiB goal remains deferred until after architectural replication.

## Recommended Next Step

Commit and push the validated P05.1 hosted-evidence update, confirm the PR CI rerun, then register one next P05 child and perform its pre-edit impact analysis.

## Next Session

1. Validate the evidence edits (`feature_list.json`, docs/03, progress, handoff, P05.1 report), refresh GitNexus, and run all/compare change detection.
2. Commit and push the evidence update to PR #3; confirm its PR CI rerun.
3. Inspect P05 matrix and code, register exactly one next P05 child, perform its pre-edit impact analysis, then implement and validate it.

## Baseline

P04 merged to `main` by PR #2 at `46084e95ea0bfd72cf86873339db9670d0ba0b67`. P05 product implementation commit is `d6e297d8bed8e11b36978e5a0ffb0e8fe2384676`.
