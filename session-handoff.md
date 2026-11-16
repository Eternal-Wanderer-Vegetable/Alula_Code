# Session Handoff

Last Updated: 2026-11-16

## Current Objective

按 `docs/03-里程碑计划与验收标准.md` 的 N.2 DoD 逐 slice 推进 P05 / `feat-027`。PR #3（https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/pull/3，分支 `codex/vscode-parity-p05`）必须保持 OPEN/DRAFT，不合并。500 MiB 数值目标留到整体架构复刻完成后。

## Current State

- 工作树：`/home/vegetable/.codex/worktrees/pr3-continuation/alula_code`，PR 专用 detached checkout；原工作区 `/mnt/e/Alula_Code` 未改动。本 worktree 的 commit 推送到 `codex/vscode-parity-p05`。
- P05.1–P05.66 已完成各自 N.2 与 hosted closeout；P05.67 / feat-119 / LAY-12b2 已按用户选择收窄为只同步活动 window/group 标识，并通过本地 N.2 与 GitNexus 检查；新提交 hosted closeout 待完成。P05 / feat-027 保持 in-progress。
- P05.67 保留主窗 owner/MRU registry、活动 window/group + revision 快照、每窗口 sequence 去重、ready/mainWindowId handshake、focus/blur 元数据上报、最大 32 个辅助 owner 与 close cleanup/fallback。focus channel 不含 document identity、全文/selection/dirty/savepoint/session；既有文档移交/关闭恢复 payload 不变，命令路由仍保持 engine-local。
- bb0aa87 的 focused/full local gates、PR CI 与 Platform Availability 属于旧 document-identity 协议历史，不能作为新范围 closeout。当前 window/group-only 定向测试 27/27、完整 `bash init.sh`（Flutter 1347/1347）、`cargo fmt --check`、`flutter analyze`（0 issues）、diff check 与 JSON parse 全通过；日志：`p05.67-focused-tests.log`、`p05.67-init.log`、`p05.67-analyze.log`。
- GitNexus 当前 index 为 repeated incremental indexes: 12,735–12,738 nodes / 395 clusters / 434 flows（incremental edge count varied as diagnostics changed）。staged all-scope 多次扫描在 MEDIUM/CRITICAL 间波动（13 files/11–13 symbols/2–354 processes，最近 CRITICAL）；compare-main 累积 CRITICAL（303 files/538–541 symbols/377–381 processes），重复扫描显示 523–526 symbols 与 367–371 flows 未列出。Snapshot/registry/app 精确 impact LOW；Event duplicate candidates UNKNOWN（max MEDIUM），workbench private initState 未找到且 >512 KiB file skipped。保留 UNKNOWN/CRITICAL 和列表/flow 截断，不称 graph clean；完整数字见 scope report。
- 原生 OS 双窗口 focus/blur 尚无实测证据；widget/channel mocks 不等于原生验证。此项必须在 scope report 中保留为未验证。always-on-top 原生层级也在 P05.66 报告中保留未验证。
- 超大 `app/lib/workbench/workbench_page.dart` 不要运行写入式 `dart format`，会造成大量无关重排；小文件已格式化，当前大文件仅局部代码 diff。

## Blockers / Limits

- P05.67 新 window/group-only 协议的 GitNexus analysis 已记录；PR CI/Platform Availability hosted verification 尚未完成。
- GitNexus 会跳过超大 workbench 文件，且 graph 有跨语言与 walk/entry truncation；UNKNOWN/截断不代表无影响，按报告保留。
- 现有 Platform Availability lane 未声明会自动化真实双窗口 focus/blur；若没有 OS 级证据，不得把该项写成已验证。

## Next Session First Step

1. 提交并 push 当前本地验证完成的 slice，保持 PR #3 OPEN/DRAFT；检查新 HEAD 的 PR CI 与 Platform Availability。
2. hosted 完成后更新 `docs/03`、`feature_list.json`、`progress.md` 与本文件，注明原生 OS focus/blur 未实测；再按 docs/03 选择下一个 P05 slice。

## Evidence and Files

- P05.67 scope、N.2、GitNexus 与本地门禁：`docs/diagnostics/2026-11-16-p05/p05.67-auxiliary-window-focus-context.md`。
- 产品协议：`app/lib/workbench/auxiliary_focus_context.dart`；辅助窗接线：`app/lib/workbench/auxiliary_window.dart`；主窗协调/接线：`app/lib/workbench/workbench_page.dart`。
- Tests: `app/test/auxiliary_focus_context_test.dart`, `app/test/auxiliary_window_test.dart`, `app/test/editor_tab_tear_out_test.dart`.
- P05.65 / P05.66 的实现、hosted artifact 与未验证行为证据分别见 `docs/diagnostics/2026-11-16-p05/p05.65-editor-tab-tear-out-scope.md` 和 `p05.66-auxiliary-window-always-on-top-scope.md`。
