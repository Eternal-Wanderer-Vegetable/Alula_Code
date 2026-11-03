# Session Handoff

> Last Updated: 2026-11-03. P04.84 / EDT-14a regex capture replacement is complete for local DoD and the prioritized hosted gates. Code commit `8eb2d34` is pushed. PR #2 remains OPEN and draft.

## Current Objective

Continue the fixed Code-OSS 1.145.0 parity plan one slice at a time. Prioritize Linux and Windows usability, then hosted macOS packages. Architecture and feature parity come before numeric memory optimization; the 500 MiB target remains deferred. Native macOS DnD/IME and P15 device checks remain pending because no native macOS host is available. Do not publish v0.1.0, mark PR #2 ready, or merge.

## Latest Completed Slice: P04.84 / EDT-14a

- Regex replacement follows pinned Code-OSS `replacePattern.ts`: `$&`, `$0`–`$99`, `$$`, `\n`, `\t`, `\\`, and `\u`/`\U`/`\l`/`\L` capture case operations. Current/all replacement run in a bounded cancellable isolate; results are guarded by query, document, version, generation, and replacement input. Timeout, cancel, invalid/truncated output, and stale results do not write partial text. Selection scope, zero-width progress, output/match caps, and one Rust undo frame are preserved. Preserve-case is deferred to a later EDT-14 slice.
- Eleven added replacement cases. Full `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` passed (Rust workspace, Clippy, core build, 758 Flutter tests); cargo fmt, Flutter analyze (0 issues), new/changed Dart formatter check, and `git diff --check` passed. No local GUI or Narrator was started.
- Code commit `8eb2d34` is pushed to `origin/codex/vscode-parity-p00`. PR CI [`41584189165`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41584189165) passed all four jobs, including 758 Flutter tests. Platform Availability [`41584184923`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41584184923) passed all three platform jobs. Linux package/DnD artifacts `13207296631` / `13207371568` record an Xvfb launch, 22 pointer events, and same-document move, cross-document copy, and external text drop. Windows artifacts `13207317283` / `13207886549` record a visible 1028×711 client area at 96 DPI, UI Automation/MSAA availability, graceful close with exit code 0, 13 pointer events, and all three drop routes. macOS ARM64 package `13208125947` was produced; DnD artifact `13206989416` reports the pointer route unavailable and skipped interaction; startup artifact `13207084453` contains only Impeller initialization and no crash report.
- The latest 100 branch Actions sample remains 65 successful/0 failed CI, 28 successful/6 failed Platform Availability, and one separate historical Windows artifact replay failure. The sampled reds stop at accessibility/MSAA, clipboard, DnD, or launch-probe assertions/parsing. They have no shared known signature with the historical Windows `0xC000041D` or macOS startup SIGSEGV. Current green runs are non-reproduction evidence only; no causal link or crash mitigation is claimed. See [`p04.84-regex-capture-replacement.md`](docs/diagnostics/2026-11-03-p04/p04.84-regex-capture-replacement.md) and [`ci-failures-and-crash-correlation.md`](docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md).

## GitNexus

Before editing, `replaceAllMatches` returned UNKNOWN because the workbench caller is not resolved; `workbench_page.dart` exceeds the indexer's 512 KiB limit. Source references were checked. Post-code all-scope detected 4 indexed files, 13 symbols, 0 resolved processes, LOW risk. After evidence/status edits, current tracked all-scope detected 5 files, 9 symbols, 0 resolved processes, LOW risk; the new untracked report is not indexed. Neither process count proves complete coverage because the workbench file is omitted. Two refreshed compare-main scans reported 1,572 files, 2,902–2,903 symbols, 384 flows, CRITICAL, with a capped listing; this reflects cumulative branch divergence and is not clean.

## Blockers

- Native macOS DnD was skipped because the hosted runner could not route pointer events. Native macOS IME and P15 device validation still require a native device.
- Hosted Windows is not the Windows 11 client acceptance gate; the local GUI/Narrator route remains intentionally unused.
- Historical Windows `0xC000041D` and macOS startup SIGSEGV source causes remain unresolved. No causal link to sampled CI assertion/probe failures has been established.

## Files

- P04.84 implementation/tests: `app/lib/editor/find_replace.dart`, `app/lib/workbench/workbench_page.dart`, `app/test/find_replace_undo_test.dart`, `app/test/workbench_regex_replace_test.dart`.
- Plan/status/evidence: `docs/03-里程碑计划与验收标准.md`, `feature_list.json`, `progress.md`, `session-handoff.md`, `docs/diagnostics/2026-11-03-p04/p04.84-regex-capture-replacement.md`, and `ci-failures-and-crash-correlation.md`.

## Next Session

1. Confirm the P04.84 evidence/status commit is pushed and PR #2 CI is green.
2. Select the next dependency-ready item already listed in `docs/03` / `docs/11`. Preserve-case is a later EDT-14 slice; register its acceptance row before implementation if it is not already listed.
3. Run GitNexus impact before source edits and complete one feature slice with its local DoD before committing.
4. Keep PR #2 OPEN and draft. Do not start the local desktop GUI or Narrator. Do not publish v0.1.0 or mark the PR ready.

## Constraints

- Work only in `/tmp/alula-p04.70-next`; never edit `/mnt/e/alula_code`.
- Pushes to `origin/codex/vscode-parity-p00` are authorized. This checkout is detached; push with `git push origin HEAD:codex/vscode-parity-p00`.
- Avoid local GUI/accessibility checks that can trigger Narrator.
