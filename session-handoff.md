# session-handoff.md — 会话交接

> Last Updated：2026-10-30（P03.1–P03.3 已完成；下一片 P03.4 Delta/IME）

## 项目目标

按 docs/10-VSCode无插件全功能复刻总计划.md，使用 Flutter + Rust 复刻固定版本 VS Code 默认非 AI 能力。docs/03 是状态、依赖与 DoD 的唯一权威；一次只推进一个 feature 切片。

## 当前状态

- 当前优先级：P00–P13 完成整体架构和默认功能复刻；P14 做全功能性能/内存优化；P15 做最终对照与发布验收。
- P00 阶段交付物已签收。P01 / feat-023 的 P01.1–P01.4 已完成并分阶段提交。P02 / feat-024 的 P02.1–P02.7 全部完成并分阶段提交。P03 / feat-025 已按 docs/03 拆为 P03.1–P03.7；P03.1 范围读取提交为 `2c21662`，P03.2 按行 UTF-16 地址查询提交为 `2c6f9ab`。P03.3 ABI v14 批量行窗口、Rust 唯一文本所有权 ADR 和 Flutter 有界只读视口原型已完成，完整 `bash init.sh` 通过（Flutter 168 项）。当前下一片 P03.4：Delta 输入窗口与三平台 IME 合同。
- Rust + rust-analyzer ≤500 MiB 目标暂时移出当前目标集合与验收门；历史与新增测量仅作基线，P14 完成整体架构后重新制定优化指标。P00–P13 仍须满足有界资源、关闭时回收、压力下可编辑/保存和无数据丢失要求。
- 真实 DRM/WPE GBM 与 Microsoft 官方服务身份/许可仍有外部阻塞，按 docs/03 对应 Web/联网阶段处理，不阻塞当前 P03 编辑器切片。
- P02.1：docs/diagnostics/2026-10-30-p02/p02.1-per-document-undo.md；P02.2：docs/diagnostics/2026-10-30-p02/p02.2-savepoint-dirty-undo.md；P02.3：docs/diagnostics/2026-10-30-p02/p02.3-save-as-revert.md。
- P02.4：docs/diagnostics/2026-10-30-p02/p02.4-encoding-bom-eol.md；P02.5：docs/diagnostics/2026-10-30-p02/p02.5-external-changes-conflicts.md。`workbench_page.dart` 含既存未提交编辑器/Git 变更，阶段提交只暂存本阶段 hunk；`keybindings.dart` 与 harness/agent/docs09 等工作区改动保持不纳入。
- P02.6：docs/diagnostics/2026-10-30-p02/p02.6-crash-journal-large-text.md。完整门禁 `bash init.sh` 已通过（Flutter 156 项）；Rust + rust-analyzer 500 MiB 目标按优先级安排到 P14。
- P02.7：docs/diagnostics/2026-10-30-p02/p02.7-workspace-edit-transaction.md。ABI v11 的多文档文本事务、UTF-16 范围/版本校验、全批原子提交与独立 undo 均通过；完整 `bash init.sh` 163 项、`cargo fmt --check` 和 Flutter analyze 均通过。LSP 服务端主动 `workspace/applyEdit` 接收留待 P12。
- P03.1：`docs/diagnostics/2026-10-30-p03/p03.1-bounded-rust-range-read.md`。ABI v12 新增 Rust Rope 有界读取与 Dart `AlulaDoc.readRange`；真实 Linux FFI fixture 对拍 BOM/CRLF/emoji、超长单行与偏移边界，完整 `bash init.sh` Flutter 165 项通过。当前工作台仍是全文 TextField，未测三平台 IME/无障碍。
- P03.2：`docs/diagnostics/2026-10-30-p03/p03.2-rust-line-offset-api.md`。ABI v13 新增行号到绝对 UTF-16 起点查询，直接使用 Rust Rope 行索引；BOM/emoji/CRLF/末尾空行与越界行由 Dart↔Rust 对拍，完整 `bash init.sh` Flutter 166 项通过。工作台全文 TextField 尚未替换，下一片 P03.3。
- P03.3：`docs/diagnostics/2026-10-30-p03/p03.3-bounded-viewport-adr.md`。ABI v14 批量按行读取受限 UTF-16 窗口；Flutter 只读原型每页 32 行、每行最多 2,048 单元、每视图最多缓存 3 页。Rust 10k 尾页、真实 FFI 50k 行双视图滚动/选区/隔离与 100k 长行水平窗口通过。完整 `bash init.sh` 168 项、`flutter analyze`、格式门通过。原工作台仍持有全文 TextField；Delta 输入/IME、多光标、无障碍和平台验收仍未过门。

## 工作树注意事项

仓库有既存未提交改动，包含 harness 技能迁移、agent/、README、app 中其他功能及格式、docs09、appendix、旧诊断证据等；不得重置或混入无关内容。app/lib/workbench/workbench_page.dart 与 app/lib/workbench/keybindings.dart 尤其包含既存用户修改，阶段提交必须创建只含当前阶段目标的 staged snapshot。

## 下一步

1. 开始 P03.4：实现短输入窗口与 Delta/IME 协议；验证组合区生命周期、候选窗定位、提交/取消、selection 映射、增量回写/背压，并按 docs/03 取得 Windows/macOS/Linux 真实平台证据。开始改函数/类前按 GitNexus impact 执行并处理 HIGH/CRITICAL 风险。
2. 按 docs/03 的依赖与切片顺序逐项推进；P00–P13 完成前不做 500 MiB 数值优化。
