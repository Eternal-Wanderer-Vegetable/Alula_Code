# Session Handoff

> Last Updated: 2026-11-03. P04.72 / EDT-12b8 `$WORKSPACE_NAME` / `$WORKSPACE_FOLDER` is implemented locally. Focused parser/workbench tests (50), full `bash init.sh` (Rust workspace, Clippy, build_core, Flutter 673), cargo fmt, and Flutter analyze pass. Hosted CI and Linux/Windows availability are pending. The P04.71 evidence-only CI run `41515815365` passed all jobs. Avoid local GUI/Narrator.

## Current Objective

Finish hosted verification and evidence recording for P04.72, then select the next single eligible P04 slice from `docs/03-里程碑计划与验收标准.md`. P04.71 is done; keep macOS native DnD/device checks pending. Memory-target optimization stays deferred until architecture parity is complete.

## Current Evidence and Files

- P04.72 implementation: `app/lib/editor/snippet_template.dart`, `app/lib/workbench/workbench_page.dart`, and the two snippet test files. It adds the single-folder `WORKSPACE_NAME` / `WORKSPACE_FOLDER` variables without Rust or ABI changes.
- P04.72 evidence: `docs/diagnostics/2026-11-03-p04/p04.72-workspace-snippet-variables.md`.
- P04.71 implementation: `app/lib/editor/snippet_template.dart`, `app/lib/workbench/workbench_page.dart`, and the two snippet test files.
- P04.71 evidence: `docs/diagnostics/2026-11-03-p04/p04.71-relative-filepath-snippet-variable.md`.
- Plan row: P04.72 is in progress pending hosted checks; P04.71 and P04.70 are done. `feat-026` remains in progress because P04 has open subtasks.
- Code-OSS 1.145.0 reference commit: `4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e`. P04.72 follows its single-folder workspace resolver: basename for name and absolute fsPath for folder. Current-word still uses the default word definition and bounded 1000 UTF-16 context.
- GitNexus P04.72 pre-edit impact: `expandSnippetTemplate`, `snippetTemplateUsesVariable`, and `_insertSnippetTemplate` report LOW on the fresh 1 MiB index. `_workspaceRoot` context identifies the property, but read/write edges are not fully linked; source usages were confirmed. Index cross-language gaps and process truncation remain documented.
- CI/crash report: `docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md`. Run `41458740387` failed a Windows MSAA welcome-text assertion after requesting focus. Run `41370553563` separately recorded a macOS DnD pointer-route timeout and a real launch SIGSEGV (exit 139). Run `41505691264` is a successful baseline PR CI run; none of these claims permanent crash resolution.

Root `/mnt/e/alula_code` contains extensive pre-existing unstaged user changes, including edits to `app/lib/workbench/workbench_page.dart`. Continue only in `/tmp/alula-p04.70-next` and preserve unrelated root changes. PR #2 stays draft; do not mark ready, merge, or publish v0.1.0 before full plan/release gates.

## Blockers and Constraints

- No macOS native test host is available; native DnD/IME/device validation remains pending.
- Avoid local GUI and Narrator because earlier GUI checks triggered Narrator repeatedly.
- 500 MiB process-memory target remains suspended until architecture parity is complete.
- GitNexus has unresolved cross-language references and truncated walks. UNKNOWN/HIGH/CRITICAL warnings remain explicit; missing callers or zero resolved flows are not proof of no impact.

## Next Steps

1. P04.71 evidence-only CI `41515815365` passed all jobs.
2. Run staged/all GitNexus scans for P04.72, review the exact diff, then commit and push the implementation plus local evidence.
3. Wait for PR CI and Linux/Windows platform checks, record hosted evidence in `docs/03`, `feature_list.json`, and `progress.md`, and keep macOS native DnD/device checks pending.
4. Keep release CI / v0.1.0 publication gated on the full plan.
