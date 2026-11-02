# CI failures and runtime crash correlation

Date: 2026-11-03. Repository: `Eternal-Wanderer-Vegetable/Alula_Code`; branch: `codex/vscode-parity-p00`; audited HEAD: `ddacdbd`.

## Recent Actions sample

The latest 100 GitHub Actions runs on this branch contained:

| Workflow | Successful | Failed | What the failures show |
|---|---:|---:|---|
| CI | 56 | 1 | The lone failure (`41372387516`) was Flutter Analyze scanning Cargokit's standalone vendored build tool. It did not launch Alula; `1fbda68` corrected the analyzer scope. |
| Platform Availability | 14 | 28 | This history includes hosted input routing, UIA/MSAA assertions, script encoding, native clipboard fixtures, and teardown failures. The latest relevant Windows failures (`41456756543`, `41458740387`) stop on semantic-text assertions. They do not establish a runtime crash. |
| Validate Windows artifact 41109679662 | 0 | 1 | This separate replay does contain a genuine close crash in the exact historical Release artifact, described below. |

The counts reflect a development history of repeated probe and fixture changes, not a current failure rate. Latest PR CI run [`41487367300`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41487367300) passed.

## Confirmed historical Windows crash

Windows artifact validation run [`41454766973`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41454766973) replayed the exact x64 Release artifact from run [`41109679662`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41109679662), built from commit `d5319369`. Both light and dark validation sessions posted `WM_CLOSE`, did not time out, and observed exit code `-1073740771` (`0xC000041D`). UIA/Narrator assertions also failed later in those sessions, but they are a separate failure signal.

This is a real crash in the old application binary, not a CI assertion misreport: earlier exact-artifact replays captured the same exit code even when the validator made no UIA/MSAA queries. Windows Application Error events identify an access violation in `flutter_windows.dll` at offset `0x000000000001e220`. The exact-artifact report and raw diagnostics are recorded in [`p03.7-exact-windows-artifact-41109679662.md`](../2026-10-31-p03/p03.7-exact-windows-artifact-41109679662.md). This remains a historical-binary failure and does not identify the source-level cause.

## Current-build comparison

Platform Availability run [`41482157012`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41482157012) tested the rebuilt branch at commit `189e920`. Its Windows `Verify Windows accessibility tree and smoke lifecycle` step passed. That step rejects a nonzero `WM_CLOSE` exit code, so this run's current-build close smoke passed. It is hosted Windows Server evidence; it does not replace the pending Windows 11 client, DPI, theme, Narrator, and IME gates.

The macOS startup SIGSEGV in run [`41370553563`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41370553563) remains a distinct historical issue. The readiness handshake/nil guards in `9f2c70a` were followed by successful startup smokes without a new `.ips` or `.crash`; that is non-reproduction evidence, not proof of permanent elimination.

## Finding

Hosted CI runs Alula in isolated runners, so a failing job does not itself cause a crash on the user's computer. CI does provide useful crash evidence: the old Windows artifact's close check exposed a real product failure, while many other red runs were test or runner failures. Fixing those test paths improves signal quality; fixing the application's close path is the work that addresses the recorded crash. Current rebuilt-branch hosted close and launch checks pass, while native Windows 11 acceptance remains pending.

No local desktop GUI or Narrator was started during this audit.

## Graph review

An isolated clean snapshot at `ddacdbd` was indexed before scanning this exact documentation change. GitNexus `detect-changes --scope all` reported 6 files, 17 symbols, 0 affected processes, risk LOW. The underlying index still reports 498 unresolved cross-language property accesses, 851 entry-point candidates not ranked, 447 callees skipped by the branching cap, and 13 budget-truncated walks; absent flows are not treated as proof that no path exists. No application code changed in this evidence update.
