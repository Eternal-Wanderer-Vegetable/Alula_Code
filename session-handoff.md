# session-handoff.md — 会话交接

> Last Updated：2026-10-30（P03.5 多光标/列选与 Alt+Click 坐标 fixture 已实现；阶段仍进行中，500 MiB 留待 P14）

## 项目目标

按 docs/10-VSCode无插件全功能复刻总计划.md，使用 Flutter + Rust 复刻固定版本 VS Code 默认非 AI 能力。docs/03 是状态、依赖与 DoD 的唯一权威；一次只推进一个 feature 切片。

## 当前状态

- 当前优先级：P00–P13 完成整体架构和默认功能复刻；P14 做全功能性能/内存优化；P15 做最终对照与发布验收。
- P00 阶段交付物已签收。P01 / feat-023 的 P01.1–P01.4 已完成并分阶段提交。P02 / feat-024 的 P02.1–P02.7 全部完成并分阶段提交。P03 / feat-025 已按 docs/03 拆为 P03.1–P03.7；P03.1 范围读取提交为 `2c21662`，P03.2 按行 UTF-16 地址查询提交为 `2c6f9ab`，P03.3 ABI v14 批量行窗口/所有权 ADR/有界只读视口提交为 `e32b5fd`。P03.4.1 有界输入会话合同已提交为 `5695184`，P03.4.2a Flutter EditableText 输入适配器已提交为 `c95e584`。P03.4.2b1 Rust savepoint 合同及 ABI v15、b2 工作台有界输入接线、b3 Rust dirty/undo/journal/命令接线均已完成。P03.4.2c 已得到 Windows Alula/固定 Code-OSS 与 WSLg Linux/Fcitx5 产品 IME 证据，但 macOS 与原生 DRM Linux 未验证，P03.4 保持 in-progress。P03.5 已接入多光标、列选、Rust 提交、clipboard、按行分配粘贴、cursor history 与 Alt+Click；Alt+Click pointer-coordinate fixture 验证 offset 6 次级 caret 且保留主 caret。当前与精确 staged snapshot 的 bash init.sh（Flutter 211 项）、cargo fmt 与 Flutter analyze 均通过；GitNexus staged/all 变更检查为 CRITICAL，风险与范围见阶段报告。窗口外 occurrence 搜索仍缺；同文档多视图 selection 按 docs/03 留到 P03.7。
- Rust + rust-analyzer ≤500 MiB 目标暂时移出当前目标集合与验收门；历史与新增测量仅作基线，P14 完成整体架构后重新制定优化指标。P00–P13 仍须满足有界资源、关闭时回收、压力下可编辑/保存和无数据丢失要求。
- 真实 DRM/WPE GBM 与 Microsoft 官方服务身份/许可仍有外部阻塞，按 docs/03 对应 Web/联网阶段处理，不阻塞当前 P03 编辑器切片。
- P02.1：docs/diagnostics/2026-10-30-p02/p02.1-per-document-undo.md；P02.2：docs/diagnostics/2026-10-30-p02/p02.2-savepoint-dirty-undo.md；P02.3：docs/diagnostics/2026-10-30-p02/p02.3-save-as-revert.md。
- P02.4：docs/diagnostics/2026-10-30-p02/p02.4-encoding-bom-eol.md；P02.5：docs/diagnostics/2026-10-30-p02/p02.5-external-changes-conflicts.md。`workbench_page.dart` 含既存未提交编辑器/Git 变更，阶段提交只暂存本阶段 hunk；`keybindings.dart` 与 harness/agent/docs09 等工作区改动保持不纳入。
- P02.6：docs/diagnostics/2026-10-30-p02/p02.6-crash-journal-large-text.md。完整门禁 `bash init.sh` 已通过（Flutter 156 项）；Rust + rust-analyzer 500 MiB 目标按优先级安排到 P14。
- P02.7：docs/diagnostics/2026-10-30-p02/p02.7-workspace-edit-transaction.md。ABI v11 的多文档文本事务、UTF-16 范围/版本校验、全批原子提交与独立 undo 均通过；完整 `bash init.sh` 163 项、`cargo fmt --check` 和 Flutter analyze 均通过。LSP 服务端主动 `workspace/applyEdit` 接收留待 P12。
- P03.1：`docs/diagnostics/2026-10-30-p03/p03.1-bounded-rust-range-read.md`。ABI v12 新增 Rust Rope 有界读取与 Dart `AlulaDoc.readRange`；真实 Linux FFI fixture 对拍 BOM/CRLF/emoji、超长单行与偏移边界，完整 `bash init.sh` Flutter 165 项通过。当前工作台仍是全文 TextField，未测三平台 IME/无障碍。
- P03.2：`docs/diagnostics/2026-10-30-p03/p03.2-rust-line-offset-api.md`。ABI v13 新增行号到绝对 UTF-16 起点查询，直接使用 Rust Rope 行索引；BOM/emoji/CRLF/末尾空行与越界行由 Dart↔Rust 对拍，完整 `bash init.sh` Flutter 166 项通过。工作台全文 TextField 尚未替换，下一片 P03.3。
- P03.3：`docs/diagnostics/2026-10-30-p03/p03.3-bounded-viewport-adr.md`。ABI v14 批量按行读取受限 UTF-16 窗口；Flutter 只读原型每页 32 行、每行最多 2,048 单元、每视图最多缓存 3 页。Rust 10k 尾页、真实 FFI 50k 行双视图滚动/选区/隔离与 100k 长行水平窗口通过。完整 `bash init.sh` 168 项、`flutter analyze`、格式门通过。原工作台仍持有全文 TextField；Delta 输入/IME、多光标、无障碍和平台验收仍未过门。
- P03.4.1：`docs/diagnostics/2026-10-30-p03/p03.4.1-input-window-contract.md`。Rust 为唯一提交文本；Flutter 输入窗最多 64 Ki UTF-16、局部偏移映射为绝对 TextOps；IME 预编辑只作为 overlay，提交/取消/selection/composition/超限/版本失配与单槽背压由 7 项真实 FFI fixture 验证。`bash init.sh`（Flutter 175 项）和 Flutter analyze 通过。未接入工作台 TextField、未验证原生候选位置及三平台 Alula IME。
- P03.4.2a：`docs/diagnostics/2026-10-30-p03/p03.4.2a-flutter-ime-field.md`。`RustTextInputField` 以 Flutter EditableText 平台输入客户端承载有界 session；测试 TextInput 通道上报的编辑框尺寸/非零屏幕变换、IME overlay/提交/取消和超限恢复。P03.4.1 + .2a 定向 10 项通过，`flutter analyze` 零问题。独立控件尚未接入工作台；native IME 与 candidate window 未实测。
- P03.4.2b1：`docs/diagnostics/2026-10-30-p03/p03.4.2b1-rust-savepoint-state.md`。ABI v15 将 Rope savepoint 快照、精确 dirty 与外部基线比较暴露给 Dart `AlulaDoc`；dirty/回到 savepoint/恢复基线及 ABI 版本不变由 Rust 和真实 Dart↔Rust FFI 验证。`bash init.sh`（Flutter 179 项）、cargo fmt、flutter analyze 全绿。该合同尚未由工作台消费；不等同移除了全文控制器。
- P03.4.2b2/b3：`docs/diagnostics/2026-10-30-p03/p03.4.2b-workbench-bounded-rust-input.md`。`OpenDoc` 不再保存全文控制器；工作台输入窗、窗口移动/selection、保存切换 flush、大粘贴和版本冲突恢复已接线。dirty/savepoint、操作型 undo、journal、查找/大纲、外部状态、WorkspaceEdit 与关闭流程使用 Rust 权威文档。完整 `bash init.sh` Flutter 186 项、Rust workspace、Clippy、build_core、cargo fmt 与 Flutter analyze 均通过。2,000,001 UTF-16 单元文本重启后保留并可从 Rust 保存；控件窗口保持有界。P03.4.2c 的 Windows 与 WSLg Linux 样本已取得；macOS 和原生 DRM Linux 仍未验证，详见下一条。
- P03.4.2c：`docs/diagnostics/2026-10-30-p03/p03.4.2c-native-ime-platform-evidence.md`。Windows 11 Alula + Microsoft Pinyin 与固定 Code-OSS 1.145.0-dev 对拍通过 composition/候选/提交/取消/失焦；WSLg Linux Alula Release + Fcitx5 Pinyin 验证同类路径，journal 留存 `你好bei jing`。Linux Release build 通过；Alt+F4 关闭退出码 0，日志仍有 GLib critical 与 `FlutterEngineRemoveView kInvalidArguments`。WSLg 不替代原生 DRM Linux，macOS 和候选屏幕边缘夹取未验证；P03.4.2c partial，平台/关闭硬门留待 P03.7。

## 工作树注意事项

仓库有既存未提交改动，包含 harness 技能迁移、agent/、README、app 中其他功能及格式、docs09、appendix、旧诊断证据等；不得重置或混入无关内容。app/lib/workbench/workbench_page.dart 与 app/lib/workbench/keybindings.dart 尤其包含既存用户修改，阶段提交必须创建只含当前阶段目标的 staged snapshot。

## 下一步

1. 继续 P03.5：补齐输入窗外 occurrence 查询，完成该切片证据与验收后再开 P03.6。同一 DocumentId 多视图 selection 与无障碍/原生平台门按 P03.7 所有权验收。P03.4 macOS 原生 IME、原生 DRM Linux 与屏幕边缘候选夹取仍留平台签收门，不以 WSLg 或固定 Code-OSS 替代。改既有符号前先按 GitNexus impact；图谱 unknown/critical 均须结合源码调用路径 review。
2. 按 docs/03 的依赖与切片顺序逐项推进；P00–P13 完成前不做 500 MiB 数值优化。
