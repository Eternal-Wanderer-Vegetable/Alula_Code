# Session Handoff

Last Updated: 2026-11-15

## Current Objective

按 `docs/03-里程碑计划与验收标准.md` 的 N.2 DoD 逐 slice 完成 P05 / `feat-027`；PR #3
（<https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/pull/3>，分支
`codex/vscode-parity-p05`）保持 draft/open，不合并。500 MiB 数值目标继续留到架构复刻后。

## Current State

- 工作树：`E:/temp/alula-pr3-p05`（该分支专用 worktree），分支
  `codex/vscode-parity-p05`。`E:/Alula_Code` 是另一条 p00 线，未改动。
- P05.1–P05.56 已登记完成；**LAY-17 QuickInput 验收面（分组/多选/描述/detail/
  buttons/back/校验/历史/取消与焦点恢复）已全部交付**。
  - P05.54 / feat-106 / LAY-17a：步骤/返回、item 按钮、取消焦点恢复（`4c76f44`）。
  - P05.55 / feat-107 / LAY-17b：分组分隔符、多选、`description`/`detail`、校验消息
    （`eb2d8c0`）。
  - P05.56 / feat-108 / LAY-17c：命令面板 MRU 历史（有界持久化）与 item 按钮显隐/
    键盘可达（本地 DoD 完成；hosted 待补）。报告：
    `docs/diagnostics/2026-11-15-p05/p05.56-quick-input-history-item-buttons.md`。
- P05.54/P05.55 的 hosted 证据已登记（PR CI `43597695692` / `43602681711`，Platform
  Availability `43597691956` / `43602675844`，macOS ZIP SHA-256 与 sidecar 一致）。
- 门禁（Windows 原生执行；WSL `bash init.sh` 在本机不可用：脚本 CRLF + wrapper）：
  `cargo fmt --check`、`cargo test --workspace`、Clippy `-D warnings`、`flutter analyze`
  （0 issues）、focused tests 全绿。全量 `flutter test` 的 30 项失败是与切片无关的既有
  环境/时序基线，另有 `workbench_merge_editor_open_test.dart` 的轮换 flake（单跑稳定的
  是基线那两项）；P05.56 轮为 `+1242 -32`。

## Blockers

- 无用户手动操作需求。P05.56 的 hosted 证据（PR CI + Platform Availability）待采录。
- 工作树里 `app/{linux,macos,windows}/**/generated_plugin_registrant*` 等 7 个文件是
  P05.49 `desktop_multi_window` 依赖后本地构建生成的既有脏改动，不属任何切片，未提交、
  未回滚。
- Windows PowerShell 5.1 无法解析 `scripts/build_core.ps1`（UTF-8 无 BOM + 中文串）；
  WSL 侧 `scripts/*.sh` 因 CRLF 不可直接执行。按脚本内容逐条执行并记录。
- GitNexus 图覆盖：`workbench_page.dart` > 512 KiB 不入图（私有方法 UNKNOWN）、跨语言
  字段点与 flow 截断限制；不把 0 caller/0 flow 当作无影响。FTS 扩展在 Windows 上不可用。
- `dart format` 会用新版 formatter 重排 `workbench_page.dart`（1,100+ 行无关 diff）与
  `main.dart`；这些文件保持既有风格，只对新增/重写文件做格式门。

## Next Session First Step

1. `node .gitnexus/run.cjs status`：索引基于 P05.56 工作树改动重建，提交后需刷新；
   stale 则 `analyze --index-only`，必要时 `GITNEXUS_LBUG_MAX_DB_SIZE=34359738368`。
2. 若 P05.56 hosted 未登记：查看 PR #3 最新 PR CI 与 Platform Availability，把 run id、
   artifacts、macOS ZIP SHA-256、DnD/startup 结果补进 `docs/03`、`feature_list.json`、
   `progress.md`、报告与 PR body。
3. 登记并实现下一个切片：LAY-18 通知与进度（toast/center/banner、来源过滤、actions、
   取消/loading/error/可访问提示），建议按 a/b/c 拆分（基础设施+toast、进度与取消、
   产品接线）；随后 LAY-19、LAY-20、CMD-01–12。
4. 收尾：更新 `feature_list.json`（status + evidence）、`docs/03`、`progress.md`、本
   handoff；提交前完整 `detect-changes`，保留既有本地脏改动不混入。

## Evidence and Files

- P05.54：`docs/diagnostics/2026-11-14-p05/p05.54-quick-input-steps.md`
- P05.55：`docs/diagnostics/2026-11-14-p05/p05.55-quick-input-groups-multi-select.md`
- P05.56：`docs/diagnostics/2026-11-15-p05/p05.56-quick-input-history-item-buttons.md`，
  `p05.56-focused-red.log`、`p05.56-focused-green.log`、`p05.56-rust-gates.log`、
  `p05.56-full-flutter.log`
- 产品文件：`app/lib/workbench/quick_input.dart`、`command_history.dart`、
  `command_history_store.dart`、`app/lib/workbench/workbench_page.dart`、
  `app/lib/main.dart`、`app/test/command_history_test.dart`、
  `app/test/quick_input_history_test.dart`
