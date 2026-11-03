# Session Handoff

> Last Updated: 2026-11-03. P04.97 / EDT-17e code commit 0eaacac and evidence commit b2b370d are pushed. P04.98 / EDT-17f side-by-side Git diff is registered as the next slice.

## Current Objective

Continue the fixed Code-OSS 1.145.0 parity plan one registered slice at a time. Prioritize overall architecture and Linux/Windows usability, then provide hosted macOS packages. Numeric memory optimization remains deferred. Do not publish v0.1.0, mark PR #2 ready, or merge.

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

## Latest Completed Slice: P04.97 / EDT-17e

- Paired removed/added rows only inside contiguous blocks per unified hunk; word ranges use the existing UTF-16 word diff and render as selectable rich text. Context and unmatched rows stay unpaired. Aggregate caps: 8,192 pairs, 262,144 UTF-16 input units, 2,000,000 work reservation, 1,000,000 trace cells per pair. Fallback paints full paired lines with a reason; full raw-patch fallback remains.
- Local DoD passed: 15 focused tests, full init.sh (Rust workspace/Clippy/build_core, Flutter 829), cargo fmt, Flutter analyze 0 issues, harness 100/100, JSON and diff check. No local GUI/Narrator; no Rust/ABI or numerical memory changes. Evidence: docs/diagnostics/2026-11-03-p04/p04.97-git-diff-word-highlight.md.
- Code commit 0eaacac is pushed. PR CI 41653070567 passed all four jobs. Platform Availability 41653061611 passed Linux x64, Windows x64, and macOS ARM64 build/package smoke. Linux/Windows DnD artifacts record 22/13 pointer events and move/copy/external-text routes; Windows client 1028×681 at DPR 1.0. macOS package/startup passed, while native DnD artifact 13238189464 is explicitly skipped due unavailable input route.
- GitNexus impact remains CRITICAL for computeGitDiffPatchWordChanges (76/31) and UNKNOWN for GitDiffPatchView. Staged detection: 3 files / 14 symbols / 376 flows / CRITICAL with capped/unmatched paths. workbench_page.dart exceeded the index's 512 KiB cap. Do not call the graph clean. Current green smoke does not resolve historical Windows 0xC000041D.

## CI and Crash Finding

- Before the P04.95 push, the newest 100 regular CI runs all passed. The newest 100 Platform Availability runs contained 47 historical failures, followed by 53 consecutive successful runs through `41636589670`.
- CI has surfaced real crashes: the macOS FlutterView/Irondash startup SIGSEGV prompted a readiness handshake and nil guards; later smokes have not reproduced it. Exact old Windows artifact `d5319369` still reproduces `0xC000041D` during close; cause is unknown.
- Recent Windows ARM validator red runs lost automated input and exited without app fault events/dumps. Pacing fixed the validator route; this is not a fix for the old Windows close crash. Details: [`ci-failures-and-crash-correlation.md`](docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md).

## Current Workspace State

- Work in `/tmp/alula-p04.70-next`; checkout is detached and pushes to `origin/codex/vscode-parity-p00` are authorized with `git push origin HEAD:codex/vscode-parity-p00`.
- P04.97 code commit `0eaacac` and evidence/state commit `b2b370d` are pushed. P04.98 EDT-17f is registered in docs/03 and is waiting for impact review before implementation.
- PR #2 remains OPEN/draft. Do not publish v0.1.0 or merge.
- P04.97 PR CI and Platform Availability passed. Linux/Windows DnD artifacts record 22/13 pointer events and move/copy/external-text routes; macOS startup log contains only the Impeller line, and native macOS DnD was skipped for `input-route-unavailable`.

## Open Validation Gaps

- Historical Windows 11 ARM `0xC000041D` source cause is unresolved; current x64-emulation replay is non-reproduction evidence only.
- Native macOS DnD/IME, Linux DRM hardware, and P15 device gates remain open. Hosted macOS DnD must be recorded as skipped when pointer routing is unavailable.
- EDT-17 remains open after inline Git patch rendering and word highlights; side-by-side, moved blocks, whitespace options, unchanged folding, navigation, and full diff-editor integration remain.

## Next Step

After the P04.97 evidence commit, register the next EDT-17 slice in `docs/03-里程碑计划与验收标准.md` before coding. Continue the user-facing diff editor parity gaps from the fixed Code-OSS matrix, retain explicit work budgets and complete-text fallback, refresh GitNexus before edits, and preserve every CRITICAL/UNKNOWN warning. Keep PR #2 open/draft. Preserve the unresolved crash evidence and avoid local GUI/accessibility actions that can start Narrator.
