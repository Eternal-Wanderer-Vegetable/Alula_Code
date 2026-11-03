# Session Handoff

> Last Updated: 2026-11-03. P04.96 / EDT-17d evidence commit 735a465 is pushed; final PR CI run 41650426521 passed all four jobs. P04.97 / EDT-17e is registered in docs/03 and is now the active implementation slice.

## Current Objective

Continue the fixed Code-OSS 1.145.0 parity plan one registered slice at a time. Prioritize overall architecture and Linux/Windows usability, then provide hosted macOS packages. Numeric memory optimization remains deferred. Do not publish v0.1.0, mark PR #2 ready, or merge.

## Latest Completed Slice: P04.94 / EDT-17b

- Added bounded pure-Dart UTF-16 character/word ranges with Code-OSS ASCII word-boundary expansion, full local DoD, and hosted Linux/Windows/macOS validation. Evidence: [`p04.94-word-diff-model.md`](docs/diagnostics/2026-11-03-p04/p04.94-word-diff-model.md).
- Historical Windows ARM `0xC000041D` remains unresolved; P04.94 green CI is non-reproduction evidence only.

## Completed Slice: P04.95 / EDT-17c

- Implemented `computeDiffViewModel` as a bounded pure-Dart projection from line hunks and UTF-16 word ranges into ordered unchanged/modified/inserted/deleted rows. Replacements pair by hunk order; both source sides map exactly once and in order. Combined input, row count, aggregate inline input, and work are capped; row fallbacks retain both full inputs, inline fallbacks retain whole changed rows with explicit reasons.
- 12 focused tests plus 200 seeded random pairs pass. `bash init.sh` passed with Flutter 814, Rust workspace, Clippy, and `build_core`; `cargo fmt --all -- --check`, Flutter analyze (0 issues), harness 100/100, JSON parse, and diff check passed. No GUI or Narrator was started.
- Scope excludes rendering, Rust/ABI, moved blocks, folding, navigation, and Git/SCM integration. Full evidence: [`p04.95-diff-view-row-model.md`](docs/diagnostics/2026-11-03-p04/p04.95-diff-view-row-model.md).
- PR CI [`41641937089`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41641937089) passed all four jobs with 814 Flutter tests. Platform Availability [`41641927566`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41641927566) passed Linux/Windows/macOS; macOS DnD was skipped because hosted pointer routing was unavailable.
- GitNexus 1.6.12 index was refreshed at `e2e3aa3`. New-model upstream impact reports CRITICAL and unrelated cross-flow callers; exact source search confirms no production caller. Staged/all/compare scans also reported CRITICAL/capped results and are recorded without downgrading the warnings.

## Latest Completed Slice: P04.96 / EDT-17d

- Replaced the existing Git Diff panel's plain unified-patch text with a bounded, lazy inline list showing file/hunk metadata, old/new line numbers, and context/add/remove colors; preserves line-level selection and falls back to the complete raw patch for unsupported or over-budget input.
- Scope and DoD are registered in `docs/03-里程碑计划与验收标准.md`. Limits: 2,000,000 UTF-16 units and 16,384 display rows; no partial parse. Side-by-side, generic full-text comparison, word highlighting, moved blocks, folding, and navigation remain later slices.
- GitNexus index was refreshed after implementation and covers 1,263 files. `workbench_page.dart` is omitted due to the analyzer's file-size limit; impacts for `_buildGitDiffPanel` and `_showGitDiff` are UNKNOWN/not found. Parser impact is CRITICAL (98 symbols/31 flows); repeated staged/all scans are 341–377 flows/CRITICAL, compare-main is 399 flows/CRITICAL and capped. Source search confirms parser/view/tests and one workbench panel call; all graph warnings remain unresolved.
- Local DoD passed: focused parser/widget suite (7), full `bash init.sh` (Rust workspace/Clippy/build_core, Flutter 821), `cargo fmt --all -- --check`, Flutter analyze (0 issues), harness validator 100/100, JSON and diff checks. No local GUI/Narrator.
- PR CI [`41647025365`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41647025365) passed all four jobs, including 821 Flutter tests. Platform Availability [`41647018011`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41647018011) passed Linux x64, Windows x64, and macOS ARM64. Linux/Windows DnD artifacts record 19/13 pointer events and move/copy/external-text routes. macOS DnD was skipped for unavailable hosted pointer routing. Full evidence: [`p04.96-git-diff-patch-renderer.md`](docs/diagnostics/2026-11-03-p04/p04.96-git-diff-patch-renderer.md).

## Active Slice: P04.97 / EDT-17e

- Implement bounded UTF-16 word highlights for ordinally paired removed/added rows in one contiguous Git unified-diff change block. Keep unpaired lines, context and hunk boundaries distinct; rich selectable text retains the existing full raw-patch fallback.
- Budgets registered in docs/03: 8,192 pairs, 262,144 aggregate UTF-16 input units, 2,000,000 aggregate work, and 1,000,000 trace cells per pair. Any exhausted budget or word-model fallback paints the whole paired lines and records why. No Rust/ABI or numeric memory changes.
- Before code edits, GitNexus index was refreshed and bound to /tmp/alula-p04.70-next at 735a465. computeWordDiff impact is CRITICAL (75 nodes/31 flows) with clearly unrelated graph mappings; GitDiffPatchView is UNKNOWN because workbench_page.dart exceeds index size cap. Source search confirms existing word-diff use in diff_view_model.dart and a single production GitDiffPatchView construction in the large Workbench file. All-scope doc scans varied between 0 affected processes/LOW and 84–377/CRITICAL; high-risk flow lists were capped and unrelated, so the 0 result is not an all-clear. Keep warnings unresolved and recheck before commit.
- Last completed P04.96 evidence run 41650426521 passed Rust Linux/Windows, harness, and Flutter (821); local init.sh --fast passed. Historic Windows close crash remains unresolved. No local desktop or accessibility interaction.

## CI and Crash Finding

- Before the P04.95 push, the newest 100 regular CI runs all passed. The newest 100 Platform Availability runs contained 47 historical failures, followed by 53 consecutive successful runs through `41636589670`.
- CI has surfaced real crashes: the macOS FlutterView/Irondash startup SIGSEGV prompted a readiness handshake and nil guards; later smokes have not reproduced it. Exact old Windows artifact `d5319369` still reproduces `0xC000041D` during close; cause is unknown.
- Recent Windows ARM validator red runs lost automated input and exited without app fault events/dumps. Pacing fixed the validator route; this is not a fix for the old Windows close crash. Details: [`ci-failures-and-crash-correlation.md`](docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md).

## Current Workspace State

- Work in `/tmp/alula-p04.70-next`; checkout is detached and pushes to `origin/codex/vscode-parity-p00` are authorized with `git push origin HEAD:codex/vscode-parity-p00`.
- P04.96 code commit `44807f2` is pushed; this commit contains its final evidence and state update.
- PR #2 remains OPEN/draft. Do not publish v0.1.0 or merge.
- CI, Linux, Windows, and macOS all passed. Linux/Windows DnD artifacts record 23/12 pointer events and move/copy/external-text routes; macOS startup log contains only the Impeller line, and native macOS DnD was skipped for `input-route-unavailable`.

## Open Validation Gaps

- Historical Windows 11 ARM `0xC000041D` source cause is unresolved; current x64-emulation replay is non-reproduction evidence only.
- Native macOS DnD/IME, Linux DRM hardware, and P15 device gates remain open. Hosted macOS DnD must be recorded as skipped when pointer routing is unavailable.
- EDT-17 visual diff features remain open; do not report the diff editor complete.

## Next Session First Step

Register the next EDT-17 slice in `docs/03-里程碑计划与验收标准.md` before coding; prioritize connecting word-level ranges to rendered changed lines while retaining explicit work budgets and complete-text fallback. Refresh GitNexus, preserve every CRITICAL/UNKNOWN warning, and continue with local/hosted checks in staged commits. Keep PR #2 open/draft. Preserve the unresolved crash evidence and avoid local GUI/accessibility actions that can start Narrator.
