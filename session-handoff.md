# Session Handoff

Last Updated: 2026-11-16

## Current Objective

按 `docs/03-里程碑计划与验收标准.md` 的 N.2 DoD 逐 slice 完成 P05 / `feat-027`；PR #3
（<https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/pull/3>，分支
`codex/vscode-parity-p05`）保持 draft/open，不合并。500 MiB 数值目标继续留到架构复刻后。

## Current State

- 工作树：`/home/vegetable/.codex/worktrees/pr3-continuation/alula_code`，PR #3 专用 detached
  checkout（远端分支 `codex/vscode-parity-p05`）。`/mnt/e/Alula_Code` 是原 p00 工作区，未动本轮
  更改；从此 managed worktree 将提交推送到 PR 远端分支。
- P05.1–P05.60 已登记完成，P05.60 本地与 hosted 证据均已补齐；P05.61 实现与本地 DoD 已通过，hosted 证据待本次提交后补齐。
  - P05.54 / LAY-17a：步骤/返回、item 按钮、取消焦点恢复（`4c76f44`）。
  - P05.55 / LAY-17b：分组分隔符、多选、`description`/`detail`、校验消息（`eb2d8c0`）。
  - P05.56 / LAY-17c：命令面板 MRU 历史与 item 按钮显隐/键盘可达（`f9172da`；
    hosted 已登记：PR CI `43710612479`、Platform Availability `43710607607` 三平台首跑
    全绿，macOS ZIP SHA-256 `1ebf5954…5263` 与 sidecar 一致）。
  - P05.57 / LAY-18a：通知中心与 toast 基础设施（DND、来源过滤、可访问提示）
    （`72edbe0`；hosted 已登记：PR CI `43713492886`、Platform Availability `43713488195`
    三平台首跑全绿，macOS ZIP SHA-256 `de166272…51f0` 与 sidecar 一致）。报告：
    `docs/diagnostics/2026-11-15-p05/p05.57-notification-center.md`。
  - P05.58 / LAY-18b：进度通知（loading/percentage/cancel）与 banner 层（`9f184ca`；
    hosted 已登记：PR CI `43717289132`、Platform Availability `43717284222` 三平台首跑
    全绿，macOS ZIP SHA-256 `1423aafa…b345` 与 sidecar 一致）。报告：
    `docs/diagnostics/2026-11-15-p05/p05.58-notification-progress-banner.md`。
  - P05.59 / LAY-18c：通知产品接线（journal 写入失败、文档保存失败）（`1c780d8`；
    hosted 已登记：PR CI `43717815102`、Platform Availability `43717810444` Linux/Windows
    首跑通过 + macOS attempt 1 Quit 探针 flake、attempt 2 全绿，macOS ZIP SHA-256
    `52d83c06…5d2c` 与 sidecar 一致）。报告：
    `docs/diagnostics/2026-11-15-p05/p05.59-notification-product-wiring.md`。
  - P05.60 / LAY-19a：Welcome 页与空编辑器组 watermark —— 本地 DoD 通过；PR CI `43726743775` 四项全绿；Platform Availability `43726740538` attempt 2 三平台通过。attempt 1 普通 macOS Release smoke 的 SIGTERM 收尾失败未复现；native-titlebar Quit、bundle 与 ZIP 校验通过。
    报告：`docs/diagnostics/2026-11-15-p05/p05.60-welcome-and-watermark.md`。
  - P05.61 / LAY-19b：最近项目 MRU —— `RecentHistoryStore`、Welcome「最近」、File >「打开最近」和失效项通知已实现；`cargo fmt --check`、`bash init.sh`（Flutter 全集 1311 项）与 `flutter analyze` 通过；待 PR hosted closeout。报告：`docs/diagnostics/2026-11-16-p05/p05.61-recent-history.md`。
- LAY-17 与 LAY-18 验收面均已全部交付；LAY-19 已交付 a（Welcome/watermark），
  b（最近项目）与 c（Walkthrough）开放；下一步 LAY-19b。
- 当前 managed worktree 已能直接执行 `bash init.sh`：Rust tests、Clippy `-D warnings`、
  core build、完整 Flutter 全集均通过；P05.61 全集 1311/1311。`flutter analyze` 0 issues。
- Flutter `dart format` 会用新版 formatter 重排超大 `workbench_page.dart`；保持既有风格，
  本 slice 手工保留 191 行局部 diff，仅格式化其他新增/小型改动文件。

## Blockers

- 无用户手动操作需求。P05.56–P05.60 hosted 证据均已登记。macOS DnD 当前 runner 仍报告 `CGEventPostToPid pointer route: false`，workflow 明确跳过该探针；Linux/Windows DnD 通过。
- `bash init.sh --fast` 生成的 Linux/macOS/Windows plugin registrant 修改已恢复；PR 专用工作树当前干净。
- Windows PowerShell 5.1 无法解析 `scripts/build_core.ps1`（UTF-8 无 BOM + 中文串）；
  WSL 侧 `scripts/*.sh` 因 CRLF 不可直接执行。按脚本内容逐条执行并记录。
- GitNexus 图覆盖：`workbench_page.dart` > 512 KiB 不入图（私有方法 UNKNOWN）、跨语言
  字段点与 flow 截断限制；不把 0 caller/0 flow 当作无影响。FTS 扩展在 Windows 上不可用。
- `dart format` 会用新版 formatter 重排 `workbench_page.dart`/`status_bar.dart`/`main.dart`
  （1,000+ 行无关 diff）；这些文件保持既有风格，只对新增/重写文件做格式门。

## Next Session First Step

1. `git status --short` 与 `node .gitnexus/run.cjs status`；stale 时先 `analyze --index-only`。
   GitNexus 警告仍存在：`workbench_page.dart` (>512 KiB) 未入图、981 个跨语言属性点未链接、
   flow tracing 有 truncation；UNKNOWN 仍须源码确认。
2. P05.60 hosted closeout 已登记：PR CI `43726743775`；Platform Availability
   `43726740538` attempt 2 全绿。详情在 `docs/diagnostics/2026-11-15-p05/p05.60-welcome-and-watermark.md`。
3. 完成 P05.61 hosted closeout，更新 `docs/03`、`feature_list.json`、`progress.md` 与 PR 证据；随后登记并实现 P05.62 / LAY-19c Walkthrough。
4. 每 slice 做完即更新 evidence/状态；提交前完整 `detect-changes --scope all`。PR #3
   保持 draft/open，不合并。

## Evidence and Files

- P05.54：`docs/diagnostics/2026-11-14-p05/p05.54-quick-input-steps.md`
- P05.55：`docs/diagnostics/2026-11-14-p05/p05.55-quick-input-groups-multi-select.md`
- P05.56：`docs/diagnostics/2026-11-15-p05/p05.56-quick-input-history-item-buttons.md`
- P05.57：`docs/diagnostics/2026-11-15-p05/p05.57-notification-center.md`，
  `p05.57-focused-red.log`、`p05.57-focused-green.log`、`p05.57-rust-gates.log`、
  `p05.57-full-flutter.log`
- P05.58：`docs/diagnostics/2026-11-15-p05/p05.58-notification-progress-banner.md`，
  `p05.58-focused-red.log`、`p05.58-focused-green.log`、`p05.58-rust-gates.log`、
  `p05.58-full-flutter.log`
- P05.59：`docs/diagnostics/2026-11-15-p05/p05.59-notification-product-wiring.md`，
  `p05.59-focused-red.log`、`p05.59-focused-green.log`、`p05.59-rust-gates.log`、
  `p05.59-full-flutter.log`
- P05.60：`docs/diagnostics/2026-11-15-p05/p05.60-welcome-and-watermark.md`，
  `p05.60-focused-red.log`、`p05.60-focused-green.log`、`p05.60-rust-gates.log`、
  `p05.60-full-flutter.log`
- 产品文件：`app/lib/workbench/notifications.dart`、`notification_widgets.dart`、
  `status_bar.dart`、`workbench_page.dart`、`app/lib/main.dart`、
  `app/test/notification_center_test.dart`、`app/test/notification_ui_test.dart`
