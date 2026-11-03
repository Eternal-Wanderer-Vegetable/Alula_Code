# Session Handoff

> Last Updated: 2026-11-03. P04.95 / EDT-17c implementation, local DoD, and hosted CI/platform checks are complete. Code commit `e2e3aa3` is pushed; the final status/evidence update is still uncommitted.

## Current Objective

Continue the fixed Code-OSS 1.145.0 parity plan one registered slice at a time. Prioritize overall architecture and Linux/Windows usability, then provide hosted macOS packages. Numeric memory optimization remains deferred. Do not publish v0.1.0, mark PR #2 ready, or merge.

## Latest Completed Slice: P04.94 / EDT-17b

- Added bounded pure-Dart UTF-16 character/word ranges with Code-OSS ASCII word-boundary expansion, full local DoD, and hosted Linux/Windows/macOS validation. Evidence: [`p04.94-word-diff-model.md`](docs/diagnostics/2026-11-03-p04/p04.94-word-diff-model.md).
- Historical Windows ARM `0xC000041D` remains unresolved; P04.94 green CI is non-reproduction evidence only.

## Current Slice: P04.95 / EDT-17c

- Implemented `computeDiffViewModel` as a bounded pure-Dart projection from line hunks and UTF-16 word ranges into ordered unchanged/modified/inserted/deleted rows. Replacements pair by hunk order; both source sides map exactly once and in order. Combined input, row count, aggregate inline input, and work are capped; row fallbacks retain both full inputs, inline fallbacks retain whole changed rows with explicit reasons.
- 12 focused tests plus 200 seeded random pairs pass. `bash init.sh` passed with Flutter 814, Rust workspace, Clippy, and `build_core`; `cargo fmt --all -- --check`, Flutter analyze (0 issues), harness 100/100, JSON parse, and diff check passed. No GUI or Narrator was started.
- Scope excludes rendering, Rust/ABI, moved blocks, folding, navigation, and Git/SCM integration. Full evidence: [`p04.95-diff-view-row-model.md`](docs/diagnostics/2026-11-03-p04/p04.95-diff-view-row-model.md).
- PR CI [`41641937089`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41641937089) passed all four jobs with 814 Flutter tests. Platform Availability [`41641927566`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41641927566) passed Linux/Windows/macOS; macOS DnD was skipped because hosted pointer routing was unavailable.
- GitNexus 1.6.12 index was refreshed at `e2e3aa3`. New-model upstream impact reports CRITICAL and unrelated cross-flow callers; exact source search confirms no production caller. Staged/all/compare scans also reported CRITICAL/capped results and are recorded without downgrading the warnings.

## CI and Crash Finding

- Before the P04.95 push, the newest 100 regular CI runs all passed. The newest 100 Platform Availability runs contained 47 historical failures, followed by 53 consecutive successful runs through `41636589670`.
- CI has surfaced real crashes: the macOS FlutterView/Irondash startup SIGSEGV prompted a readiness handshake and nil guards; later smokes have not reproduced it. Exact old Windows artifact `d5319369` still reproduces `0xC000041D` during close; cause is unknown.
- Recent Windows ARM validator red runs lost automated input and exited without app fault events/dumps. Pacing fixed the validator route; this is not a fix for the old Windows close crash. Details: [`ci-failures-and-crash-correlation.md`](docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md).

## Current Workspace State

- Work in `/tmp/alula-p04.70-next`; checkout is detached at `e2e3aa3`. Pushes to `origin/codex/vscode-parity-p00` are authorized with `git push origin HEAD:codex/vscode-parity-p00`.
- P04.95 code commit `e2e3aa3` is pushed. Uncommitted status/evidence changes: `docs/03-里程碑计划与验收标准.md`, `docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md`, P04.94/P04.95 diagnostic reports, `feature_list.json`, `progress.md`, and this handoff.
- PR #2 remains OPEN/draft. Do not publish v0.1.0 or merge.
- CI, Linux, Windows, and macOS all passed. Linux/Windows DnD artifacts record 23/12 pointer events and move/copy/external-text routes; macOS startup log contains only the Impeller line, and native macOS DnD was skipped for `input-route-unavailable`.

## Open Validation Gaps

- Historical Windows 11 ARM `0xC000041D` source cause is unresolved; current x64-emulation replay is non-reproduction evidence only.
- Native macOS DnD/IME, Linux DRM hardware, and P15 device gates remain open. Hosted macOS DnD must be recorded as skipped when pointer routing is unavailable.
- EDT-17 visual diff features remain open; do not report the diff editor complete.

## Next Session First Step

Refresh GitNexus after the final doc edits, run staged/all/compare checks, commit the state/evidence separately, and push to `codex/vscode-parity-p00`. Keep PR #2 open/draft. Then register the next EDT-17 slice before coding. Preserve the unresolved crash evidence and avoid local GUI/accessibility actions that can start Narrator.
