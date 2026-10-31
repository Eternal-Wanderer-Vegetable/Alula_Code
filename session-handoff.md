# session-handoff.md — 会话交接

> Last Updated：2026-10-31（P04.16 / EDT-03a 完成；P04.1–P04.16 已完成，P04 / feat-026 仍进行中。Ctrl/Command+K Ctrl/Command+D 移动最后 occurrence selection，Ctrl/Command+D 添加下一个匹配；支持 selection undo/redo。定向 22 项、完整 `bash init.sh` 与隔离暂存快照均 EXIT=0（Flutter 341）、cargo fmt 与 Flutter analyze 通过。证据：`docs/diagnostics/2026-10-31-p04/p04.16-move-last-occurrence-selection.md`。P15 原生平台门仍待验证，500 MiB 留 P14。）

## 项目目标

按 docs/10-VSCode无插件全功能复刻总计划.md，使用 Flutter + Rust 复刻固定版本 VS Code 默认非 AI 能力。docs/03 是状态、依赖与 DoD 的唯一权威；一次只推进一个 feature 切片。

## 当前状态
- 当前状态更新（2026-10-31）：P03 / feat-025 的实现出口已关闭，EV-P03-* 留待 P15。Windows 11 exact historical artifact run `41187736069` 仍记录关闭 `0xC000041D` 与 Narrator UIA 语义/焦点门失败；该结果不外推到新构建。P04.1–P04.16 已完成，feat-026 仍进行中；最新 EDT-03a 实现 Ctrl/Command+K Ctrl/Command+D 移动最后 occurrence selection，定向 22 项及当前/隔离暂存快照完整 `bash init.sh`（Flutter 341）通过。P15 原生 DRM Linux、Windows 11 视觉/读屏/IME/DPI 与 macOS 仍 pending。

- P04.16 涉及 `app/lib/workbench/keybindings.dart`、`app/lib/workbench/workbench_page.dart`、`app/test/keybindings_test.dart`、`app/test/workbench_multi_selection_test.dart` 与本片证据/状态文件。`workbench_page.dart` 与 `keybindings.dart` 含本片以外的既有工作树改动；提交时只暂存 P04.16 对应 hunks。
- Next Session 首步：阅读 `docs/03` 与 `docs/11`，继续拆 EDT-03 剩余多光标/box-selection 原子项并先做 GitNexus upstream impact。保持 P15 平台验收 pending，不推进 P14 数值化内存优化。

- 本会话重新执行 `bash init.sh --fast`，EXIT=0：Rust workspace tests、`build_core`、Flutter 256 项通过。当前 WSL 没有 `nvidia-smi` / Windows 命令互操作，无法刷新显存状态；Windows Release 白窗复测仍待用户释放 2–4 GiB 显存或指定 AMD GPU。
- P03.6 新增 WSLg 实窗折叠/滚动截图：折叠 `main` 后 minimap viewport marker 覆盖整个可见源范围，滚动时 sticky header 显示 `main` / `Function`。文件 `docs/diagnostics/2026-10-31-p03/linux-alula-fold-before-wslg.png`、`linux-alula-fold-after-wslg.png`、`linux-alula-sticky-scroll-wslg.png`；仅 WSLg 证据。
- P03.6 增加了 WSLg `GDK_SCALE=2` / `GDK_DPI_SCALE=1` Release 截图（物理窗口 1280×800）：`docs/diagnostics/2026-10-31-p03/linux-alula-gdk-scale-2x-wslg.png`。只证明 WSLg 整数缩放绘制，不代表 fractional DPI 或其他平台。
- P03.6 字体补充：临时 fontconfig 将 Cascadia Code/Consolas 解析到 Windows 字体目录；Alula Release 已用隔离 HOME 截图，证据 `docs/diagnostics/2026-10-31-p03/linux-alula-cascadia-wslg.png`。该结果仍是 WSLg-only，关闭时复现 `No path was found` 与 GTK/Flutter teardown 告警。
- P03.6 已完成固定 Code-OSS 1.145.0-dev（commit `4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e`、Electron 43.8.3）同一 WSLg 1280×720 工作台参考；截图 `docs/diagnostics/2026-10-31-p03/code-oss-1.145.0-linux-wslg.png`。菜单/活动栏/Explorer/gutter/breadcrumb/status bar 与 Alula 当前编辑视图有明显结构差距；因 Code-OSS 是扩展未完整构建的源码开发版，此截图只作 shell 参考，不作像素验收。临时进程、profile 和 worktree 已清理。
- P03.6 Rust scope folding 与折叠后的 minimap/sticky-scroll 行投影已实现：报告 `docs/diagnostics/2026-10-30-p03/p03.6-code-folding.md`、`docs/diagnostics/2026-10-30-p03/p03.6-folded-viewport-projection.md`；工作树 `init.sh` 通过（Flutter 256 项），cargo fmt 与 analyze 全绿；精确 HEAD+index 快照 Rust/Clippy/build_core 和 Flutter 256 项 `--no-pub`、analyze 也通过。跨 OS/DPI/主题像素对照仍未完成。Linux WSLg 当前树 Release smoke 与隔离 rust-mini 单次前台编辑/保存已通过，磁盘回读代码 SHA-256 `1573fc4d16e7d13ab400d8f58b8ddb89756d59b39fe7b000983d1d1807ecd159`，截图 `docs/diagnostics/2026-10-31-p03/linux-alula-release-edited.png`；但 EGL DRI3 unavailable，关闭时有 GTK/Flutter/Rust LSP 告警；不等同原生 DRM 或生命周期通过。Windows 11 125% DPI 的隔离 Release 自动采集与 `--lsp-auto` 都只得到白色客户区，Code-OSS 对照正常；此结果不区分产品缺陷与自动化启动限制。待用户释放显存或指定 AMD GPU 后复测 Alula 与 Flutter 默认样例，再完成 P03.6 的字体安装基线/折叠像素校准；调查见 `docs/diagnostics/2026-10-30-p03/p03.6-windows-rendering-capture.md`。P03.6 保持 in-progress。`bash init.sh --fast` 首次发现 FFI 测试 ID 92,814 与相邻窗口测试的 `92,813 + 1` 碰撞，已将 fixture 改为 92,850；修复后 Rust workspace、build_core、Flutter 256 项与 cargo fmt 全通过。
- 当前优先级：P00–P13 完成整体架构和默认功能复刻；P14 做全功能性能/内存优化；P15 做最终对照与发布验收。
- P00 阶段交付物已签收。P01 / feat-023 的 P01.1–P01.4 已完成并分阶段提交。P02 / feat-024 的 P02.1–P02.7 全部完成并分阶段提交。P03 / feat-025 已按 docs/03 拆为 P03.1–P03.7；P03.1 范围读取提交为 `2c21662`，P03.2 按行 UTF-16 地址查询提交为 `2c6f9ab`，P03.3 ABI v14 批量行窗口/所有权 ADR/有界只读视口提交为 `e32b5fd`。P03.4.1 有界输入会话合同已提交为 `5695184`，P03.4.2a Flutter EditableText 输入适配器已提交为 `c95e584`。P03.4.2b1 Rust savepoint 合同及 ABI v15、b2 工作台有界输入接线、b3 Rust dirty/undo/journal/命令接线均已完成。P03.4.2c 已得到 Windows Alula/固定 Code-OSS 与 WSLg Linux/Fcitx5 产品 IME 证据，但 macOS 与原生 DRM Linux 未验证，P03.4 保持 in-progress。P03.5 已接入多光标、列选、Rust 提交、clipboard、按行分配粘贴、cursor history、Alt+Click、Rust 全文 occurrence 与跨窗编辑，阶段已完成并提交 `3ee3c4b`；同文档多视图 selection 按 docs/03 留到 P03.7。P03.6 已进入 in-progress：行号 gutter、Rust `lineOffset` 绝对行映射、缩进 guides、空白显示及默认 no-wrap/显式 wordWrap 横向视口已接入有界输入控件；长多行文本保留 LF，LTR/RTL 主 caret 显露 fixture 通过。workspace search 选中结果也已接入版本化 UTF-16 decorations；LSP semantic full provider 已以 ABI v16 接入并通过 fake LSP、本机 rust-analyzer 及 Rust/Flutter 版本 fixture；minimap overview 已用 ABI v17 接入 512 × 48 UTF-16 有界抽样和 Rust 行跳转；LSP 诊断、选中 workspace-search 与当前文件 Find 的 overview markers 已按 document/version 门控，总量限制为 512，Find 命中均匀采样最多 256 个；syntax-colored minimap 已完成（ABI v18、512×48 有界样本、paint 段上限 8192）；Find 切片全工作树及 HEAD+index 快照完整 Flutter 244 项、cargo fmt 与 analyze 0 issues 通过；sticky scroll 已接入；fold 和像素对照仍待完成；字段级字体 fallback 链已接入；详见 `docs/diagnostics/2026-10-30-p03/p03.6-editor-rendering.md`。 wrap 子切片完整门禁：全工作树与 HEAD+index tree `914f6f1b45b34ea2ee2738bea93b9ca58d629ef3` 独立快照的 `RUST_TEST_THREADS=1 bash init.sh` 均通过（Flutter 223 项）；两边 cargo fmt 通过，Flutter analyze 0 issues。
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

- P03.6 范围装饰子切片现已通过完整工作树与 HEAD+index 快照门禁（Flutter 226 项），cargo fmt、Clippy、build_core、Flutter analyze 均通过；报告已更新。

- P03.6 字体 fallback 子切片已完成实现；9 项 renderer 测试、完整工作树和精确 HEAD+index snapshot `bash init.sh`（均为 Flutter 226 项）、cargo fmt 和 Flutter analyze 0 issues 通过。平台字体实际安装与像素基线仍保留为验收项。

- P03.6 Rust Tree-sitter 正文着色子切片已实现：按 syntax/document version 门控，二分定位后只绘制当前有界 UTF-16 输入窗，pending 本地文本退回 plain TextSpan，IME composing 下划线保留。定向 renderer 10 项、完整工作树与精确 staged snapshot `RUST_TEST_THREADS=1 bash init.sh`（均 Flutter 227 项）、cargo fmt 与 Flutter analyze 0 issues 通过；staged GitNexus 最新为 8 files/19 symbols/0 processes/LOW，全工作树含既存改动为 39 files/24–27 symbols/137–299 processes/CRITICAL；报告已登记，阶段快照可提交。

- P03.6 Find provider 已接入版本化 range painter：活动 doc/version 和 Rust/input-window 版本都需一致，pending/IME 输入时隐藏旧装饰；按 UTF-16 命中二分定位，仅构造当前输入窗 decoration。定向 Find/Workbench 25 项通过，工作树及精确 staged snapshot `ede714dc8ef6be1af009fa800856e9907d8a7c5d` 全量 init.sh 均通过（Flutter 229 项），cargo fmt/Flutter analyze 也通过；GitNexus staged 9 files/11 symbols、all 40 files/16 symbols 均为 CRITICAL；affected-process 观测范围 139–325，报告保留图谱截断与调用路径风险，子切片可提交。

- P03.6 semantic tokens 子切片：ABI v16 的可取消异步 full 请求、服务器 legend/delta 解码和绝对 UTF-16 转换已通过 Rust/fake-LSP fixture；本机 rust-analyzer 临时 workspace 返回 20 tokens。完整 init.sh（Flutter 239 项）、cargo fmt、Flutter analyze 全绿；`docs/diagnostics/2026-10-30-p03/p03.6-lsp-semantic-tokens.md` 记录 100,000 token/文档上限与尚未做的 delta、像素对照。

- P03.6 minimap overview 子切片：ABI v17 Rust Rope 全文件均匀采样最多 512 行 × 48 UTF-16 单元；工作台 viewport marker 跟随有界输入窗和纵向 scroll，点击/拖动按 Rust lineOffset 跳行，窄编辑区自动隐藏。Rust、Dart↔Rust、Flutter fixtures 与完整 init.sh（Flutter 242 项）通过，详见 docs/diagnostics/2026-10-30-p03/p03.6-minimap-overview.md。Find occurrence overview markers 已完成（最多 256 个均匀采样命中），语法色 minimap 已完成；sticky scroll、fold 和跨 OS/DPI/主题像素对照仍待完成。

## 下一步

1. 按 `docs/03` 和 `docs/11` 选择下一个尚未完成的 EDT 原子项；编辑前先做 GitNexus upstream impact，并保持一次只推进一项。
2. 修复并验证 Narrator/UIA 可访问语义与焦点路径；候选构建需独立进行 Windows 11 客户端验收。旧 artifact 的 `0xC000041D` 保留为历史失败，不回填新构建结果。
3. 维持 EV-P03-LINUX-DRM、EV-P03-WIN11-UI-A11Y-DPI、EV-P03-MACOS-NATIVE pending；Linux/Windows target usability 达标后再提供 macOS 测试包。P00–P13 完成前不做 500 MiB 数值优化；完成全计划后完善 CI Release 并准备 v0.1.0 测试 PR。

## P03.7 CI follow-up（2026-10-31）

- Commits `bfbdc2c`, `96872ca`, and `d531936` are pushed; `41108610038` exposed the partial-stage missing `_onEditorPointerDown` issue, then corrected run `41109679662` passed all three platform jobs and uploaded Linux, Windows, and macOS artifacts. The current branch is hosted-buildable. Windows Server 2025 visible client, Unicode MSAA, four required semantic strings, 14 interaction tests, simulated Flutter IME, and graceful close pass in runs `41153011276`/`41153994655`; Windows 11 client-specific Narrator/native IME/DPI-theme/package gates and Linux native DRM remain pending. Preserve unrelated unstaged harness/P04/P09 work.

## P03.7 exact older Windows artifact follow-up (2026-10-31)

- Exact artifact run `41161368714` captured a visible 1028×711 client at 96 DPI on Windows Server 2025, exposed 24 MSAA nodes, and passed all four semantic-string assertions. The close request returned `0xC000041D`; a second no-accessibility launch returned the same code, so the historical artifact close failure is independent of UIA/MSAA inspection. Source-SHA Debug interaction run `41160604795` passed 14 tests, including save/read-back and simulated Flutter IME. The rebuilt branch passed its hosted Windows close smoke in run `41160297066`; these results apply to different binaries. Full boundary/evidence: `docs/diagnostics/2026-10-31-p03/p03.7-exact-windows-artifact-41109679662.md`.
