# Session Handoff

Last Updated: 2026-11-16

## Current Objective

按 `docs/03-里程碑计划与验收标准.md` 的 N.2 DoD 逐 slice 推进 P05 / `feat-027`。PR #3（https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/pull/3，分支 `codex/vscode-parity-p05`）必须保持 OPEN/DRAFT，不合并。500 MiB 数值目标留到整体架构复刻完成后。

## Current State

- 工作树：`/home/vegetable/.codex/worktrees/pr3-continuation/alula_code`，PR 专用 detached checkout；原工作区 `/mnt/e/Alula_Code` 未改动。本 worktree 的 commit 推送到 `codex/vscode-parity-p05`。
- P05.1–P05.66 已完成各自 N.2 与 hosted closeout；P05.67 / feat-119 / LAY-12b2 的产品实现和本地 N.2 已完成，hosted closeout 待提交推送后验证。P05 / feat-027 保持 in-progress。
- P05.67 完成主窗 owner/MRU registry、活动 window/group/document identity 与 revision 快照、每窗口 sequence 去重、ready/mainWindowId handshake、focus/blur 元数据上报、最大 32 个辅助 owner 与 close cleanup/fallback。焦点 metadata 不含全文/selection/dirty/savepoint/session，当前命令路由保持 engine-local。
- 本地证据：focus context + auxiliary window + tear-out focused tests 27/27；`cargo fmt --check`；`bash init.sh` exit 0（Rust workspace tests、Clippy `-D warnings`、core build、Flutter 1347/1347）；`flutter analyze` 0 issues；`git diff --check` 与 `feature_list.json` JSON parse 通过。持久日志：`docs/diagnostics/2026-11-16-p05/p05.67-init.log` 与 `p05.67-focused-tests.log`。
- GitNexus 当前 index 为 12,735 nodes / 32,757 edges / 395 clusters / 434 flows。重复 exact impact 不稳定：registry/app 查询在 LOW/UNKNOWN/CRITICAL 间变化；event/payload LOW。staged all-scope MEDIUM（13 files、32–37 symbols、4 processes），此前未暂存输出 CRITICAL；compare-main 是 PR 累积 CRITICAL（302 files、672–678 symbols、399 processes）。返回列表被截断，`workbench_page.dart` >512 KiB 被跳过，private state/initState UNKNOWN。保留 1,038 跨语言属性点、1,031 未排名入口、14 budget cuts、1 depth cap、289 callees dropped 的截断限制；详见 scope report。
- 原生 OS 双窗口 focus/blur 尚无实测证据；widget/channel mocks 不等于原生验证。此项必须在 scope report 中保留为未验证。always-on-top 原生层级也在 P05.66 报告中保留未验证。
- 超大 `app/lib/workbench/workbench_page.dart` 不要运行写入式 `dart format`，会造成大量无关重排；小文件已格式化，当前大文件仅局部代码 diff。

## Blockers / Limits

- P05.67 PR CI 和 Platform Availability hosted workflow 尚未针对最终产品提交验证。
- GitNexus 会跳过超大 workbench 文件，且 graph 有跨语言与 walk/entry truncation；UNKNOWN/截断不代表无影响，按报告保留。
- 现有 Platform Availability lane 未声明会自动化真实双窗口 focus/blur；若没有 OS 级证据，不得把该项写成已验证。

## Next Session First Step

1. 查看 PR #3 当前 head 的 CI；触发并查看 Platform Availability，保持 PR OPEN/DRAFT，不合并。
2. hosted 通过后，在 `docs/diagnostics/2026-11-16-p05/p05.67-auxiliary-window-focus-context.md`、docs/03、`feature_list.json`、`progress.md` 与本文件登记 hosted run/artifacts 和 OS focus limitation；完成 GitNexus 检查后提交/push 文档 closeout。
3. 查 docs/03 选择下一个 P05 slice；当前同一时间只推进一个 feature。

## Evidence and Files

- P05.67 scope、N.2、GitNexus 与本地门禁：`docs/diagnostics/2026-11-16-p05/p05.67-auxiliary-window-focus-context.md`。
- 产品协议：`app/lib/workbench/auxiliary_focus_context.dart`；辅助窗接线：`app/lib/workbench/auxiliary_window.dart`；主窗协调/接线：`app/lib/workbench/workbench_page.dart`。
- Tests: `app/test/auxiliary_focus_context_test.dart`, `app/test/auxiliary_window_test.dart`, `app/test/editor_tab_tear_out_test.dart`.
- P05.65 / P05.66 的实现、hosted artifact 与未验证行为证据分别见 `docs/diagnostics/2026-11-16-p05/p05.65-editor-tab-tear-out-scope.md` 和 `p05.66-auxiliary-window-always-on-top-scope.md`。
