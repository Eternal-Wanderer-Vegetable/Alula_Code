# Session Handoff

Last Updated: 2026-11-14

## Current Objective

按 `docs/03-里程碑计划与验收标准.md` 的 N.2 DoD 逐 slice 完成 P05 / `feat-027`；PR #3
（<https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/pull/3>，分支
`codex/vscode-parity-p05`）保持 draft/open，不合并。500 MiB 数值目标继续留到架构复刻后。

## Current State

- 工作树：`E:/temp/alula-pr3-p05`（该分支专用 worktree），分支
  `codex/vscode-parity-p05`。`E:/Alula_Code` 是另一条 p00 线，未改动。
- P05.1–P05.55 已登记完成。最新完成：
  - P05.54 / feat-106 / LAY-17a QuickInput 步骤/返回、item 按钮与焦点恢复（产品提交
    `4c76f44`；本地 + hosted 全绿；报告 `docs/diagnostics/2026-11-14-p05/p05.54-quick-input-steps.md`）。
  - P05.55 / feat-107 / LAY-17b QuickInput 分组分隔符、多选与描述/校验消息（产品提交
    `eb2d8c0`；本地 DoD 全绿、6 个 focused tests 先红后绿、全量 `+1233 -30` 与基线逐条
    一致；hosted 见下；报告
    `docs/diagnostics/2026-11-14-p05/p05.55-quick-input-groups-multi-select.md`）。
- P05.54 hosted：PR CI `43597695692`（Rust windows 首跑 `p01_async_completion` LSP exit
  1s 超时 flake，`--failed` 重跑通过）；Platform Availability `43597691956` 三平台首跑
  全绿；包 artifacts Linux `14114643330` / Windows `14115124198` / macOS `14115743698`，
  macOS ZIP SHA-256 `b4843258…a007a6` 与 sidecar 一致。
- P05.55 hosted：PR CI `43602681711` 四项首跑全绿；Platform Availability `43602675844`
  Linux/Windows 首跑通过，macOS attempt 1 仅 native-titlebar Quit 探针失败（有 Accessibility
  菜单无 Quit 项的日志），`--failed` 重跑 attempt 2 全绿；包 artifacts `14117216955` /
  `14116799270` / `14119581440`，macOS ZIP SHA-256
  `df061a6d348b4cecc461dcd1bc69626c99b397c44a547155e904ec4d538127ac` 与 sidecar 一致、
  `tar -tf` 81 项。
- 门禁（Windows 原生执行；WSL `bash init.sh` 在本机不可用：脚本 CRLF + wrapper）：
  `cargo fmt --check`、`cargo test --workspace`、Clippy `-D warnings`、build_core 等价
  步骤、`flutter analyze`（0 issues）、focused tests 全绿。全量 `flutter test` 的 30 项
  失败是与切片无关的既有环境/时序基线；P05.55 轮的失败集合与基线逐条一致。

## Blockers

- 无用户手动操作需求。
- 工作树里 `app/{linux,macos,windows}/**/generated_plugin_registrant*` 等 7 个文件是
  P05.49 `desktop_multi_window` 依赖后本地构建生成的既有脏改动，不属任何切片，未提交、
  未回滚。
- Windows PowerShell 5.1 无法解析 `scripts/build_core.ps1`（UTF-8 无 BOM + 中文串）；
  WSL 侧 `scripts/*.sh` 因 CRLF 不可直接执行。按脚本内容逐条执行并记录。
- GitNexus 图覆盖：`workbench_page.dart` > 512 KiB 不入图（私有方法 UNKNOWN）、跨语言
  字段点与 flow 截断限制；不把 0 caller/0 flow 当作无影响。FTS 扩展在 Windows 上不可用。

## Next Session First Step

1. `node .gitnexus/run.cjs status`：本轮索引基于 `3ad2834` + P05.55 工作树改动重建，
   提交后已与 HEAD（`eb2d8c0`/后续 docs 提交）不同，开工前先刷新；stale 则
   `analyze --index-only`，必要时 `GITNEXUS_LBUG_MAX_DB_SIZE=34359738368`。
2. 登记并实现 LAY-17c：item 按钮 hover/focus 显示与键盘可达、输入历史回填、多选产品
   接线（找到与上游 `canPickMany` 对应的命令后再接）；随后 LAY-18–20、CMD-01–12。
3. 收尾：更新 `feature_list.json`（status + evidence）、`docs/03`、`progress.md`、本
   handoff；提交前完整 `detect-changes`，保留既有本地脏改动不混入。

## Evidence and Files

- P05.54：`docs/diagnostics/2026-11-14-p05/p05.54-quick-input-steps.md`，红/绿 focused、
  rust gates、build-core、两轮全量日志同前缀。
- P05.55：`docs/diagnostics/2026-11-14-p05/p05.55-quick-input-groups-multi-select.md`，
  `p05.55-focused-red.log`、`p05.55-focused-green.log`、`p05.55-rust-gates.log`、
  `p05.55-full-flutter.log`。
- 产品文件：`app/lib/workbench/quick_input.dart`（两轮重写）、
  `app/lib/workbench/workbench_page.dart`（调用点迁移与移动视图分组）、
  `app/test/quick_input_steps_test.dart`、`app/test/quick_input_groups_test.dart`。
