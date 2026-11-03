# Session Handoff

> Last Updated: 2026-11-03. P04.85 / EDT-14b Preserve Case is complete for local DoD and the prioritized hosted gates. Code commit `3949d8d` and evidence/status updates are pushed. PR #2 remains OPEN and draft.

## Current Objective

Continue the fixed Code-OSS 1.145.0 parity plan one slice at a time. Prioritize Linux and Windows usability, then hosted macOS packages. Architecture and feature parity come before numeric memory optimization; the 500 MiB target remains deferred. Native macOS DnD/IME, Linux DRM, Windows 11 multi-configuration acceptance, and P15 device checks remain pending. Do not publish v0.1.0, mark PR #2 ready, or merge.

## Latest Completed Slice: P04.85 / EDT-14b

- Added a default-off, accessible Preserve Case toggle for literal and regex current/all replacement. Static patterns cover all-uppercase, all-lowercase, initial casing, and matching kebab/snake segments; Unicode 16 full casing includes multi-codepoint uppercase, dotted I, and contextual final sigma. Empty matches return the replacement unchanged; capture and case-operation templates keep their own semantics.
- Targeted tests passed (61). Full `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` passed (Rust workspace, Clippy, core build, Flutter 765). `cargo fmt --all -- --check`, Flutter analyze (0 issues), Dart formatting, and `git diff --check` passed. No local GUI or Narrator was started.
- Code commit `3949d8d` is pushed. PR CI [`41588501685`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41588501685) passed all four jobs. Platform Availability [`41588495748`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41588495748) passed Linux, Windows, and macOS jobs. Linux artifact [`13209266941`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41588495748/artifacts/13209266941) records 22 pointer events and all three DnD routes. Windows artifact [`13208928420`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41588495748/artifacts/13208928420) records 13 events, a visible 1028×681 client area at DPR 1.0, and all three routes; accessibility and graceful close passed. macOS ARM64 package [`13210135594`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41588495748/artifacts/13210135594) was produced; startup artifact [`13209333872`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41588495748/artifacts/13209333872) contains only Metal/Impeller initialization. macOS DnD artifact [`13209009030`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41588495748/artifacts/13209009030) says pointer routing was unavailable and all DnD tests skipped.
- The latest-100 branch sample has 65 regular CI successes/0 failures, 28 Platform Availability successes/6 failures, plus one historical Windows artifact replay failure. Sampled platform reds are MSAA/clipboard assertions or PowerShell probe encoding/parse errors. The separate old artifact replay recorded a real `0xC000041D` close crash; current hosted passes are non-reproduction evidence only. See `docs/diagnostics/2026-11-03-p04/p04.85-preserve-case.md` and `ci-failures-and-crash-correlation.md`.
- GitNexus all-scope: 6 files / 12 symbols / 0 resolved processes / LOW. The helper impact is 2 direct / 0 processes / LOW. `workbench_page.dart` exceeds the 512 KiB index limit. The fresh compare-main scan is 1,574 files / 2,770 symbols / 384 flows / CRITICAL with a capped changed-symbol listing; retain this cumulative branch-risk note.

## Next Session

1. Confirm the P04.85 status/evidence commit is pushed and PR #2 CI is green.
2. Select the next dependency-ready item in `docs/03`; register its acceptance row first if needed.
3. Run GitNexus impact before source edits, complete one feature slice and its DoD, then record evidence before starting another.
4. Keep PR #2 OPEN and draft. Avoid local GUI/accessibility checks that can trigger Narrator. Do not publish v0.1.0 or mark the PR ready.

## Constraints

- Work only in `/tmp/alula-p04.70-next`; never edit `/mnt/e/alula_code`.
- Pushes to `origin/codex/vscode-parity-p00` are authorized. This checkout is detached; push with `git push origin HEAD:codex/vscode-parity-p00`.
- Avoid local GUI/accessibility checks that can trigger Narrator.
