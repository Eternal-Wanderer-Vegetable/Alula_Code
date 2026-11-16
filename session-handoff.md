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
- P05.1–P05.65 已完成各自 N.2 与 hosted closeout；当前下一项待按 docs/03 独立拆分 LAY-12b（组/焦点同步、compact/pin-top、移回主窗、跨窗口拖拽）。P05.65 产品提交 `f4f95d799a13f991da46bb8620c267103d6d87f4` 与测试选择器修复 `831c5c54933f15817917e5806b05725954a5277c` 已推送；PR CI `43814360627` 四项全绿。Platform Availability `43814354795` attempt 2 三平台 build/test/launch/package 全绿；attempt 1 的 macOS ordinary launch-stop 与 native Quit smoke 失败，attempt 2 均通过。macOS ZIP artifact `14205627497` 的 SHA-256 `cfd8fc3976f8aacea8435a4c76658ee49f5191929a78c243470c09d7d5733f3e` 与 sidecar 一致，81 项完整；native DnD artifact `14205611876` 明确记录 pointer route unavailable/skip。完整范围：`docs/diagnostics/2026-11-16-p05/p05.65-editor-tab-tear-out-scope.md`。P05 / feat-027 仍 in-progress，PR #3 保持 OPEN/DRAFT，不合并。
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
  - P05.61 / LAY-19b：最近项目 MRU —— `RecentHistoryStore`、Welcome「最近」、File >「打开最近」和失效项通知已实现；本地 DoD、PR CI `43737761143` 与 Platform Availability `43737756490` 三平台全绿；Linux/Windows DnD 通过，macOS DnD 明确因 pointer route unavailable 跳过；macOS ZIP SHA-256 `f16a0f38…09112d4` 与 sidecar 一致。报告：`docs/diagnostics/2026-11-16-p05/p05.61-recent-history.md`。
- P05.62 / LAY-19c：内置向导、步骤 checkbox、独立进度 journal、Welcome/QuickInput/Help/命令路由已完成；focused tests 4/4。本地 `bash init.sh`、`cargo fmt --check`、`flutter analyze` 全绿（Flutter 1315/1315）。PR CI `43745604458` 四项全绿；Platform Availability `43745600249` attempt 2 三平台全绿。attempt 1 macOS Quit 探针因 hosted Accessibility 错误失败，attempt 2 通过；macOS DnD 因 pointer route unavailable 明确跳过。macOS ZIP SHA-256 `f77f8da1…92f50` 与 sidecar 一致、`unzip -tq` 81 项。报告：`docs/diagnostics/2026-11-16-p05/p05.62-walkthrough.md`。
- P05.63 / LAY-20a：组区、正文中心/四方向拆分、标签目标 hover overlay 与有效复制提示已实现；modifier 键变化即时刷新，拖动结束/取消/销毁清理。新增 4 个 widget tests，拆分与组区 focused 合计 13/13。`cargo fmt --check && bash init.sh` 全绿，Flutter 1319/1319、analyze 0 issues；Harness 100/100。PR CI `43782830766` 全绿；Platform Availability `43782824700` 三平台全绿，Linux/Windows native DnD 通过，macOS 因 pointer route unavailable 明确 skip。app artifacts Linux `14189760470`、Windows `14188839971`、macOS `14190945481`；macOS ZIP SHA `65dad7f75346230423d3f6702f19f7fe456a50ecb48fdb598cebac86b7251b7d` 与 sidecar 匹配且 `unzip -tq` 81 项。报告：`docs/diagnostics/2026-11-16-p05/p05.63-drop-target-feedback.md`。
- P05.64 / LAY-10g：组内 MRU overflow 列表完成；3 policy + 2 widget 新测通过，受影响定向回归 57/57；`bash init.sh`、`cargo fmt --check`、`flutter analyze` 0 issues、Harness 100/100 通过。PR CI `43794320814` 四项全绿；Platform Availability `43794316315` 三平台全绿。包 artifacts Linux/Windows/macOS `14193972371` / `14193678983` / `14194524746`；Linux/Windows DnD 通过，macOS DnD 因 pointer route false 明确 skip；macOS ZIP SHA `8ae0e37c…f0a4ff` 与 sidecar 一致、81 项完整。GitNexus class/all-scope CRITICAL 与 compare-main 累积风险按报告保留。范围：`docs/diagnostics/2026-11-16-p05/p05.64-group-editor-overflow-mru.md`。
- LAY-17 与 LAY-18 验收面均已全部交付；LAY-19 的 Welcome/watermark、最近项目与 Walkthrough（a/b/c）均已完成。
- 当前 managed worktree 上 P05.65 的 `cargo fmt --check`、`bash init.sh`、`flutter analyze` 均已通过：Rust workspace tests、Clippy `-D warnings`、core build、Flutter 1336/1336，analyze 0 issues；focused tear-out 12/12。
- Flutter `dart format` 会用新版 formatter 重排超大 `workbench_page.dart`；保持既有风格，
  P05.65 的 `workbench_page.dart` 仅 43 行局部 diff，只对新增/小型文件运行写入式 formatter。

## Blockers

- P05.65 已完成且无已知产品阻塞：本地 DoD、PR CI `43814360627` 与 Platform Availability `43814354795` attempt 2 全绿。Hosted macOS text DnD 探针因 runner 不路由合成指针而 skip；标签拖出手势由 policy/Workbench widget tests 验证，未声称原生手势 hosted 通过。Linux Wayland 无全局坐标时禁用自动 tear-out，手动 Move to New Window 可用。
- Historical, non-blocking CI anomaly: P05.64 docs closeout commit `f65043e2ebed82224159bc8b4351f2b78ecaae74` 的 PR CI run `43798796857` 已结束为 failure。Rust Windows job failure，但 `Tests` step 状态仍是 `in_progress` 且没有结论；日志读取返回 404。不得将它写成测试断言失败或成功。同 SHA 的 Harness、Flutter、Rust Ubuntu 成功；前一产品 commit 的 Windows CI 和 Platform Availability 三平台均通过。
- GitNexus 图覆盖：`workbench_page.dart` 私有方法/跨语言字段与 flows 有 UNKNOWN、截断限制；不把 0 caller/0 flow 当作无影响。P05.65 helper exact impact LOW/3；all-scope 多次结果跨 12 files/5–19 symbols/0–146 processes，在 LOW 与 CRITICAL 间波动；compare-main 291 files/CRITICAL、符号和 process 计数有波动、listing capped；Section 03 impact UNKNOWN；旧 class-level CRITICAL 保留。完整输出与影响范围见 P05.65 报告。
- Platform Availability 验证插件注册、三平台 build/package/启动/关闭，但其 DnD probe 不驱动标签 tear-out；报告中不可写成真实原生标签拖出已通过。该功能行为由 policy/Workbench widget tests 验证。
- `dart format` 会用新版 formatter 重排超大 `workbench_page.dart`（1,000+ 行无关 diff）；保持局部代码风格，只格式化新增/小文件。

## Next Session First Step

1. 按 docs/03 将 LAY-12b 拆分为单一、可验收的 P05 slice；完成上游核对、编辑前 GitNexus impact 与 scope/N.2 DoD 登记后再改实现。
2. 保持 one-feature-at-a-time；完成该 slice 后运行其完整 N.2 本地与 hosted 门禁，更新 feature_list/progress/session-handoff 并在 commit 前执行 GitNexus detect-changes。
3. P05 / feat-027 继续 in-progress；PR #3 保持 OPEN/DRAFT，不合并。

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
- P05.63：`docs/diagnostics/2026-11-16-p05/p05.63-drop-target-feedback.md`（本地与 hosted closeout 完成）
- P05.64：`docs/diagnostics/2026-11-16-p05/p05.64-group-editor-overflow-mru.md`（本地与 hosted closeout 完成）
- P05.65（done）：`docs/diagnostics/2026-11-16-p05/p05.65-editor-tab-tear-out-scope.md`；本地 focused 12/12、完整 init.sh Flutter 1336/1336、Rust/Clippy/core、fmt/analyze/Harness 通过。PR CI `43814360627` 四项全绿；Platform Availability `43814354795` attempt 2 三平台通过。Artifacts Linux/Windows/macOS `14202041981` / `14202401615` / `14205627497`；macOS ZIP SHA `cfd8fc3976f8aacea8435a4c76658ee49f5191929a78c243470c09d7d5733f3e`，sidecar 一致、81 项完整。macOS native DnD artifact `14205611876` 明确 skip；不计为手势验收。
- 产品文件：`app/lib/workbench/notifications.dart`、`notification_widgets.dart`、
  `status_bar.dart`、`workbench_page.dart`、`app/lib/main.dart`、
  `app/test/notification_center_test.dart`、`app/test/notification_ui_test.dart`
