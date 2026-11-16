# Session Handoff

Last Updated: 2026-11-17

## Current Objective

按 `docs/03-里程碑计划与验收标准.md` 的 N.2 DoD 逐 slice 推进 P05 / `feat-027`。PR #3（https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/pull/3，分支 `codex/vscode-parity-p05`）必须保持 OPEN/DRAFT，不合并。500 MiB 数值目标留到整体架构复刻完成后。

## Current State

- 工作树：`/home/vegetable/.codex/worktrees/pr3-continuation/alula_code`，PR 专用 detached checkout；原工作区 `/mnt/e/Alula_Code` 未改动。本 worktree 的 commit 推送到 `codex/vscode-parity-p05`。
- P05.1–P05.69 已完成各自本地 N.2 与 hosted closeout；P05.69 / feat-121 / LAY-12b4 主窗 tab 拖入既有辅助窗完成事务式单文档交换，目标原文档返回主窗。PR CI `43941953054` 四 job 通过，Platform Availability `43941942416` 三平台通过；Linux/Windows 通用 native DnD 通过，macOS 因 pointer route unavailable 明确 skip。fixture 未覆盖 Alula auxiliary 交换，P05.69 专属 OS DnD 仍未验证。P05.67 / feat-119 / LAY-12b2 按用户选择只同步活动 window/group 标识；其 focus channel 不含 document identity 或文档内容。P05.68 / feat-120 / LAY-12b3 Compact 的本地 N.2、PR CI `43900198139` 与 Platform Availability `43900182449` 三平台均通过；Linux/Windows DnD 通过，macOS synthetic pointer route 明确 skip；macOS ZIP sidecar 哈希匹配且 81 项完整，native Quit 成功。P05 / feat-027 继续 in-progress。
- P05.69 GitNexus：代码提交 all-scope 11 files/41 symbols/418 processes/CRITICAL（截断）；closeout docs all-scope 5 files/5–8 symbols/0 processes/LOW；compare-main 309 files/438–450 symbols/421 processes/CRITICAL（输出截断）。索引仍 skip `workbench_page.dart`，有跨语言属性、entry ranking 与 walk-budget 缺口。完整记录见 P05.69 scope report。
- P05.67 保留主窗 owner/MRU registry、活动 window/group + revision 快照、每窗口 sequence 去重、ready/mainWindowId handshake、focus/blur 元数据上报、最大 32 个辅助 owner 与 close cleanup/fallback。focus channel 不含 document identity、全文/selection/dirty/savepoint/session；既有文档移交/关闭恢复 payload 不变，命令路由仍保持 engine-local。
- bb0aa87 的 focused/full local gates、PR CI 与 Platform Availability 属于旧 document-identity 协议历史，不能作为新范围 closeout。当前 window/group-only 定向测试 27/27、完整 `bash init.sh`（Flutter 1347/1347）、`cargo fmt --check`、`flutter analyze`（0 issues）、diff check 与 JSON parse 全通过；日志：`p05.67-focused-tests.log`、`p05.67-init.log`、`p05.67-analyze.log`。
- GitNexus 当前 index 为 repeated incremental indexes: 12,735–12,738 nodes / 395 clusters / 434 flows（incremental edge count varied as diagnostics changed）。staged all-scope 多次扫描在 MEDIUM/CRITICAL 间波动（13 files/11–13 symbols/2–354 processes，最近 CRITICAL）；compare-main 累积 CRITICAL（303 files/538–574 symbols/377–381 processes），重复扫描显示 523–526 symbols 与 367–371 flows 未列出；本次 closeout compare-main 重复 max-limit 扫描为 303 files/538–574 symbols/377–381 processes（CRITICAL，输出仍截断），文档 staged all-scope 在 5 files/7–8 symbols/0 processes（LOW）与 5 files/1 symbol/336–352 processes（CRITICAL，最近 336）间波动；最近 changed symbol 是报告 section，flows 扩展到通用 Build/LSP traces，保留 CRITICAL 和截断，不判 clean。Snapshot/registry/app 精确 impact LOW；Event duplicate candidates UNKNOWN（max MEDIUM），workbench private initState 未找到且 >512 KiB file skipped。保留 UNKNOWN/CRITICAL 和列表/flow 截断，不称 graph clean；完整数字见 scope report。
- 原生 OS 双窗口 focus/blur 尚无实测证据；widget/channel mocks 不等于原生验证。此项必须在 scope report 中保留为未验证。always-on-top 原生层级也在 P05.66 报告中保留未验证。
- 超大 `app/lib/workbench/workbench_page.dart` 不要运行写入式 `dart format`，会造成大量无关重排；小文件已格式化，当前大文件仅局部代码 diff。

## Blockers / Limits

- P05.69 的本地 N.2、PR CI 与三平台 Platform Availability 已完成；generic native DnD fixture 未运行 Alula auxiliary swap，故该专属 OS 路径未验证，不能记为 pass。
- P05.67 的原生 OS 双窗口 focus/blur 未实测，按未验证限制保留；不作为 hosted closeout blocker。
- GitNexus 会跳过超大 workbench 文件，且 graph 有跨语言与 walk/entry truncation；UNKNOWN/截断不代表无影响，按报告保留。
- 现有 Platform Availability lane 未声明会自动化真实双窗口 focus/blur；若没有 OS 级证据，不得把该项写成已验证。

## Next Session First Step

1. 按 `docs/03` 的 P05 N.2 选择下一项独立 slice；保持一次只推进一项并先完成 Startup Workflow。
2. 原生 OS 双窗 focus/blur（P05.67）、Compact pixel/reference diff（P05.68）与 P05.69 auxiliary 跨窗交换仍未验证，继续按各自 scope report 标注；PR #3 保持 OPEN/DRAFT。

## Evidence and Files

- P05.67 scope、N.2、GitNexus 与本地门禁：`docs/diagnostics/2026-11-16-p05/p05.67-auxiliary-window-focus-context.md`。
- 产品协议：`app/lib/workbench/auxiliary_focus_context.dart`；辅助窗接线：`app/lib/workbench/auxiliary_window.dart`；主窗协调/接线：`app/lib/workbench/workbench_page.dart`。
- Tests: `app/test/auxiliary_focus_context_test.dart`, `app/test/auxiliary_window_test.dart`, `app/test/editor_tab_tear_out_test.dart`.
- P05.65 / P05.66 的实现、hosted artifact 与未验证行为证据分别见 `docs/diagnostics/2026-11-16-p05/p05.65-editor-tab-tear-out-scope.md` 和 `p05.66-auxiliary-window-always-on-top-scope.md`。

- P05.68 / feat-120 当前范围与 N.2：docs/diagnostics/2026-11-16-p05/p05.68-auxiliary-window-compact-mode.md。
- P05.68 hosted closeout：PR CI `43900198139`、Platform Availability `43900182449`；PR #3 仍为 OPEN/DRAFT。
- P05.69 / feat-121 实现、N.2、hosted closeout 与 GitNexus 限制：docs/diagnostics/2026-11-17-p05/p05.69-auxiliary-window-cross-window-drop.md；PR CI `43941953054`、Platform Availability `43941942416`。
