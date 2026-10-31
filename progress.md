# progress.md — 项目进度跟踪

> agent 会话状态文件：每完成一项工作就追加记录。任务权威分解在 `docs/03`，
> 功能状态机在 `feature_list.json`，本文件记录「何时、做了什么、证据是什么」。

## Current State（当前状态，2026-10-31 更新）

### 最新进展（2026-10-31，P04.6 / EDT-01c 完成）

- 固定 Code-OSS `1.145.0-dev` commit `4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e` 的 word-part 行为已接入：macOS Ctrl+Option+左右方向键与 Shift 选择；Windows/Linux 不注册该默认 chord。Rust Rope 按绝对 UTF-16 偏移计算 camelCase、缩写、下划线/连字符和普通分隔符边界，跨输入窗时重居中，Rust 文本和版本保持不变。
- 新增 ABI v21 `alula_doc_word_part_offset`；Rust 子词单测 4 项、editor-core FFI 对拍 1 项、键位与工作台 Flutter 定向测试 16 项通过。`bash init.sh` EXIT=0（Flutter 280 项、Rust workspace、Clippy、build_core）；`cargo fmt --all -- --check` 通过，`flutter analyze --no-pub` 0 issues。报告：`docs/diagnostics/2026-10-31-p04/p04.6-word-part-movement.md`。
- P04 / feat-026 仍是唯一活动 feature；P04.6 完成后，下一 EDT 子项需先按 `docs/03` 剩余要求拆解。Flutter targetPlatform 测试不等同真实 macOS 键盘、IME 或辅助功能验收；这些仍属 P15。历史 Windows Release artifact 的 close crash 和其他 EV-P03 pending 门保持原记录。

### 阶段进展（2026-10-31，P04.5 / EDT-01b 完成）

- 新增 `app/test/workbench_word_navigation_test.dart` 与平台键位 fixture：Windows/Linux Ctrl+方向键、macOS Option+方向键完成双向词移动和 Shift 选择；覆盖 CRLF 读入后的 LF 文本、第二行边界及长文档重居中后的有界窗边缘，Rust 全文与版本不变。
- 修正历史导航默认键位与编辑器词移动冲突：Windows Alt+方向键；Linux Ctrl+Alt+- / Ctrl+Shift+-；macOS Ctrl+- / Ctrl+Shift+-。macOS Option+Shift+方向键留给原生词/段落选择，不再被列选择处理器吞掉。定向 14 项通过，完整 `bash init.sh` 通过（Flutter 278 项），`cargo fmt --all -- --check` 通过，Flutter analyze 0 issues。报告：`docs/diagnostics/2026-10-31-p04/p04.5-word-cursor-movement.md`。
- P04 / feat-026 仍是唯一活动 feature；下一项 P04.6 / EDT-01c 为 camelCase/下划线子词移动与选择。P03 外部平台门继续 pending；旧 Windows Release artifact close crash 保留为该二进制的失败证据，不能用新构建覆盖。

### 最新进展（2026-10-31，P04.3 / EDT-16c 完成）

- ABI v20 已接入异步 LSP definition（Location/LocationLink）、16 项在途上限、版本门控和文档关闭/LSP 停止或解绑/URI 改变/工作区关闭/Critical 压力取消；Rust 提供 BOM、CRLF、行尾和 surrogate 边界安全的 UTF-16 行列/绝对位置换算。
- 工作台先走 LSP 跨文件定义，保持同文件 Tree-sitter 回退；跨文件目标在源编辑组打开，已打开文档复用共享文档视图。back/forward 和 last-edit 历史各限 128 项，命名文件关闭后可重开，最终关闭的未命名文档从历史移除。
- Rust workspace/FFI 与 fake LSP tests 通过；临时真实 rust-analyzer 1.99.1 smoke 返回跨文件 Location。冷启动首次查询会短暂无结果，后续重试返回目标；工作台对快速 null 响应增加了一次版本受控重试。
- `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh --fast` 通过（Flutter 271 项）；`cargo fmt --all -- --check`、`cargo clippy --workspace --all-targets -- -D warnings`、Flutter analyze（0 issues）及导航/history 定向测试通过。完整边界、GitNexus 告警与验证限制见 `docs/diagnostics/2026-10-31-p04/p04.3-cross-file-definition-navigation.md`。
- `docs/03` 登记 P04.3 done；P04 / feat-026 仍 in-progress。下一受控切片以 docs/03 的后续 EDT 子项为准。P03 的 Linux native DRM、Windows 11 客户端读屏/IME/DPI主题与 macOS 原生门仍 pending；先自动化复验精确 Windows artifact 交互，再开展下一 EDT 切片。

### 阶段记录（2026-10-31，P04.2 完成）

- 按用户当前目标，把代码/自动化完成状态与外部平台/人工设备验收分开：P03 / feat-025 实现出口关闭；Linux native DRM、Windows 11 Release/读屏/DPI主题和 macOS 原生环境以 EV-P03-* 明确 pending。它们不阻塞 P04–P13 的架构实现；P15/公开发行仍不得视作通过。
- `docs/03` 的 P04 / feat-026 仍是唯一活动 feature。P04.1 / EDT-16a 与 P04.2 / EDT-16b 已完成：F12/命令面板与 Ctrl/Command+Click 同文件 Rust 定义导航；覆盖 Unicode XID、单字母边界、BOM/emoji/CRLF UTF-16、修饰键、点击后 selection、非零有界输入窗映射。P04.2 证据：`docs/diagnostics/2026-10-31-p04/p04.2-same-file-ctrl-click-definition.md`。下一受控切片为 P04.3 / EDT-16c（跨文件 definition provider 与导航历史）。工作树含其他 P04/P09 代码，阶段提交只暂存本片 hunks。
- `flutter test --no-pub test/workbench_navigation_test.dart` 通过（3 项）；完整 Flutter 测试 263 项通过。`RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0（Rust workspace tests、Clippy、build_core、Flutter 263 项），`cargo fmt --all -- --check` 与 `flutter analyze --no-pub`（0 issues）通过。GitNexus staged detect 报 CRITICAL/139 flows；Dart 调用边误连跨语言探针，真实 Listener 入口与 staged hunks 已核对，残余图谱风险记在 P04.2 报告。500 MiB 目标留 P14。

### 最新进展（2026-10-31，P03.7 Windows hosted UI / MSAA）

- 修复 Windows PowerShell 5.1 采集 JSON 的默认 ANSI 编码，改为 UTF-8；提交 `1ea7037 ci(windows): preserve accessible names as UTF-8` 已推送到 `codex/vscode-parity-p00`。
- GitHub Actions runs `41153011276` 与 `41153994655` 的 Linux、Windows、macOS jobs 全部成功；后者加入 MSAA 必需字符串断言（打开文件夹、UTF-8、LF、欢迎编辑器文本）。Windows Release 可见窗口采集与 P03.7 自动交互套件通过；14 项覆盖共享文档双视图、恢复副本、50k 行尾编辑保存、多光标/剪贴板、窗口外搜索、emoji/CRLF、Flutter 模拟 IME 与 selection 隔离。WM_CLOSE 后 exit code 0。
- Windows runner 为 Windows Server 2025 Datacenter build 26100，不是 Windows 11 客户端；窗口 1028×711、96 DPI，主题注册表报告 light。MSAA child-window 树含中文菜单、工具栏、编辑器 welcome value、UTF-8/LF 与状态栏语义；截图与 UTF-8 JSON：`docs/diagnostics/2026-10-31-p03/p03.7-windows-hosted/`。仅为 hosted 可见 UI/MSAA 和自动化功能证据，不代表 Narrator 播报、系统 IME、Windows 11、多 DPI/主题矩阵、Linux native DRM 或 macOS 原生交互。
- P03.7 继续 in-progress。当前外部平台门：原生 DRM Linux；Windows 11 客户端的 Narrator/键盘遍历、native IME、DPI/主题和目标发行包；macOS 原生行为待验证。用户要求 Linux/Windows 可用后再提供 macOS 测试包；500 MiB 优化目标留待 P14。

### 最新进展（2026-10-31，P03.7 exact Windows artifact recheck）

- Validator fixes `2754b07`, `07b0542`, and `93092f0` are pushed. Exact artifact run `41161368714` passes visible-client, DPI/theme capture, UIA availability, MSAA traversal, and all four semantic-string assertions on Windows Server 2025 build 26100 (1028×711, 96 DPI, light system theme). Raw files are in `docs/diagnostics/2026-10-31-p03/p03.7-windows-artifact-41109679662/`.
- The historical Release binary fails `WM_CLOSE` with exit code `0xC000041D`; a second launch with no UIA/MSAA queries fails with the same code, showing that the capture procedure did not cause the close failure. Source-SHA run `41160604795` passed all 14 Windows interaction tests on a Debug runner, including save/read-back and Flutter-simulated IME; it does not prove those interactions on the downloaded Release binary. Rebuilt branch run `41160297066` passed its Windows visible capture, MSAA assertions, 14 desktop tests, and graceful close; its Linux hosted availability job passed. Neither is Windows 11 client or native DRM Linux evidence. Focused report: `docs/diagnostics/2026-10-31-p03/p03.7-exact-windows-artifact-41109679662.md`.
- Windows 11 Narrator/native IME/DPI-theme and Linux native DRM remain pending. Keep the historical artifact close failure visible; do not replace its result with a later build's result.

### 最新进展（2026-10-31，P03.6 Linux Release / WSLg）

- 当前工作树 `bash scripts/build_core.sh` 与 Flutter Linux Release build 均成功。以临时 HOME 和显式 Rustup/Cargo toolchain 启动 WSLg Release，窗口 1280×720，状态栏报告 rust-analyzer running、ABI v19；截图 `docs/diagnostics/2026-10-31-p03/linux-alula-release-wslg.png`。
- 运行时 EGL 报 DRI3 unavailable。窗口管理器关闭时进程 exit 0，但 GTK/GDK、FlutterEngineRemoveView 与 rust-analyzer improper shutdown 告警仍出现；仅视为 WSLg 启动证据，不代替原生 DRM 或 P03.7 生命周期验收。报告 `docs/diagnostics/2026-10-31-p03/p03.6-linux-wslg-release-smoke.md`。

### 最新进展（2026-10-31，P03.6 Windows 图形交叉检查）

- Windows 11 上 Alula Release 与 Debug 的捕获仍为白色客户区；Debug Dart 主 isolate/Workbench widget tree 正常、无 Dart 异常。
- 同机 Flutter 3.47.8 默认项目在 Impeller 与 Skia 下均白窗，Alula 关闭 Impeller/使用软件渲染仍白；Flutter 3.44.2 默认项目的旧版 Skia 路径也白窗。结果不支持“仅 3.47.8 回归”为唯一原因，但测试时 NVIDIA VRAM 为 14,739/16,303 MiB，资源因素尚未排除。
- Release 构建零警告/错误。测试截图和环境记录见 `docs/diagnostics/2026-10-30-p03/p03.6-windows-rendering-capture.md` 与 `docs/diagnostics/2026-10-31-p03/flutter-3.44.2-default-window.png`。P03.6 仍进行中；待释放显存或选择 AMD GPU 后复测，P03.7 未启动。用户豁免 v0.1.0 测试版 Apple Developer 证书/公证门槛。


### 最新进展（2026-10-30，P03.6 Windows rendering capture investigation）

- Windows Release 包旁 `alula_core.dll` 与 `app/native/alula_core.dll` 的 SHA-256 相同；Windows 11 125% DPI / 2560×1440 runner 上固定 Code-OSS 对照画面正常。
- 自动采集器已改用 Per-Monitor V2 DPI awareness 与 DWM 物理窗口边界。隔离启动 Alula Release 在初始、最大化和 `--lsp-auto` 场景均只得到白色客户区；该结果无法判定是产品绘制缺陷还是自动启动/采集环境问题，不登记为通过或失败。
- P03.6 跨 OS/DPI/主题像素对照待 Windows 桌面人工启动确认；详见 `docs/diagnostics/2026-10-30-p03/p03.6-windows-rendering-capture.md`。

### 最新进展（2026-10-30，P03.6 Rust 作用域折叠）

- Rust Tree-sitter scope folding 已接到 `.rs` 编辑器：gutter disclosure 支持嵌套折叠；隐藏行只压缩绘制高度，Rust 全文和 UTF-16 selection/IME 坐标不变；caret、selection 或 composition 进入范围即展开。
- 真实 Dart↔Rust 与 Flutter fixture 覆盖 emoji/CRLF、嵌套 scope、有界窗口中途切入、点击折叠、正文保持一致及 caret 进入首个隐藏行展开。全量 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` 通过（Rust tests、Clippy、build_core、Flutter 254 项）；`flutter analyze --no-pub` 0 issues。
- 证据：`docs/diagnostics/2026-10-30-p03/p03.6-code-folding.md`。P03.6 仍待 folded viewport 下 minimap/sticky-scroll 几何校准和跨 OS/DPI/主题像素对照；Windows 自动采集的白色画面等待人工确认；500 MiB 数值优化留待 P14。

### 最新进展（2026-10-30，P03.6 sticky scroll）

- Tree-sitter 符号增加 1-based inclusive `end_line`，Rust/Dart ABI 握手升至 v19。工作台浮层按当前文档版本和无 pending 输入门控，最多显示 5 层仍包住视口的 Rust scope；滚动只用已取回的符号数据，点击标题跳至定义。
- Rust 与 Dart↔Rust fixtures 覆盖 BOM、emoji、CRLF 行范围；Flutter fixtures 覆盖范围筛选、最多层数、实际滚动与跳转。完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` 通过（Flutter 250 项），`cargo fmt --all -- --check` 与 `flutter analyze --no-pub` 无问题。
- 证据：`docs/diagnostics/2026-10-30-p03/p03.6-sticky-scroll.md`。P03.6 仍待折叠及跨 OS/DPI/主题像素对照；500 MiB 数值优化留待 P14。

### 最新进展（2026-10-30，P03.6 syntax-colored minimap）

- ABI v18 的 Rust minimap sample 为每个代表逻辑行返回绝对 UTF-16 起点；Flutter 仅把当前文档版本中与 512×48 有界样本相交的 Tree-sitter/LSP token 绘成语法色段，并将输出段均匀采样限制在 8192。pending 输入和旧版本不绘制。
- Rust buffer/FFI 与 Dart↔Rust BOM、emoji、CRLF 起点对拍，Flutter UTF-16 裁剪、陈旧版本、全文件覆盖采样和 8192 上限 fixtures 通过。完整 `init.sh` 通过（Flutter 246 项），cargo fmt 与 Flutter analyze 0 issues。
- P03.6 尚余 sticky scroll、折叠和跨 OS/DPI/主题像素对照；500 MiB 数值优化留待 P14。

### 最新进展（2026-10-30，P03.6 minimap overview）

- Rust ABI v17 新增全文件有界 minimap sample：均匀采样最多 512 行，每行返回最多 48 UTF-16 单元的标量安全前缀，带完整行长度、文档长度、行数和版本；不物化 Rust 全文。
- Flutter minimap 在编辑区宽度至少 720 logical pixels 时显示中性线条概览，点击/拖动调用 Rust lineOffset 跳行；viewport marker 跟随当前有界输入窗和 ScrollController，版本变更后 120 ms 合并刷新。窄窗口隐藏地图保留正文点击空间。
- Rust editor-buffer/editor-core 51 项、Dart↔Rust 与 minimap widget fixture、responsive editor fixture 通过；完整门禁和最终测试数见报告 docs/diagnostics/2026-10-30-p03/p03.6-minimap-overview.md。
- minimap overview markers 已接入当前版本的 LSP severity 与选中 workspace-search 行；doc/version/pending 门控，总数上限 512。定向 minimap/diagnostic/search 9 项和完整 `bash init.sh`（Flutter 243 项）通过；报告 docs/diagnostics/2026-10-30-p03/p03.6-minimap-overview-markers.md。
- 本轮架构切片已完成；完整 `bash init.sh`（Rust tests、Clippy、build_core、Flutter 244 项）、cargo fmt 与 Flutter analyze 均通过，细节见 `feature_list.json` 的 feat-025。
- 后续条目按 docs/03 顺序继续；500 MiB 数值目标留待 P14。

### 最新进展（2026-10-30，P03.6 LSP semantic tokens）

- Rust LSP client 现在声明 semantic-token client capabilities，读取服务端 legend，并可取消地请求 `textDocument/semanticTokens/full`；Rust FFI ABI 升至 v16，按 Rust 文档版本将相对 UTF-16 token 转为绝对范围，关闭/编辑/URI 迁移/工作区关闭会取消旧请求。
- Workbench 仅在 Rust 文档、输入窗口版本相同且没有本地 pending 输入时选用 LSP token；unsupported、空结果或陈旧数据继续回退到 Tree-sitter（`.rs`）。请求最多 16 个挂起项，单文档最多 100,000 tokens。
- fake LSP roundtrip、Rust emoji+CRLF 绝对偏移、Flutter 当前版本选择与 stale/pending fallback fixture 通过；本机 rust-analyzer 临时 Rust workspace 返回并解码 20 个 semantic tokens。
- 完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` 通过：Rust workspace tests、Clippy、build_core、Flutter 239 项；`cargo fmt --all -- --check` 与 `flutter analyze --no-pub` 0 issues。报告：`docs/diagnostics/2026-10-30-p03/p03.6-lsp-semantic-tokens.md`。
- 精确 staged source tree `ea407c35cc614a77e6cb43939a9ac4701750f527` 也通过 Rust workspace tests/Clippy/fmt/build_core、Flutter no-pub 239 项与 analyze 0 issues；该归档无 pub.dev 凭据，故 Flutter 使用已解析依赖离线验证。

### 最新进展（2026-10-30，P03.6 workspace-search 装饰 provider）

- workspace search 选中结果现可在目标编辑器行绘制；ripgrep JSON 子命中 UTF-8 byte offsets 转为 UTF-16 ranges，git grep 后端没有子范围时回退标记整行。跳转使用 Rust `lineOffset`，仅在已载入行内容仍与命中快照相同、文档 id/version 匹配且没有 pending input 时显示；编辑后旧装饰自动消失。
- 定向 `search_service_test.dart` 与 `workspace_search_decorations_test.dart` 共 17 项通过；`flutter analyze --no-pub` 0 issues。完整 `FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter RUST_TEST_THREADS=1 bash init.sh` EXIT=0，Rust workspace tests、Clippy、build_core 和 Flutter 237 项通过；`cargo fmt --all -- --check` 与最终 `flutter analyze --no-pub`（0 issues）通过。精确 HEAD+index tree `bd0aa159c0d99bab86b5925233161c7d3e39dbe6` 独立快照通过 cargo fmt、Rust tests/Clippy/build_core、Flutter 237 项 `--no-pub` 与 analyze 0 issues。GitNexus repeated refresh checks: staged/all 10/41 files，symbol count 18–30、affected-process 129–195，均 CRITICAL；all 含既存用户修改。图谱截断与跨语言误关联见阶段报告。
- 报告：`docs/diagnostics/2026-10-30-p03/p03.6-workspace-search-decorations.md`。此切片只绘制当前选中的搜索结果；minimap/overview、sticky scroll、fold 与像素对照仍待完成。

### 最新进展（2026-10-30，P03.6 编辑器绘制系统进行中）

- P03.5 完成并按 `docs/03` 关闭：全文 occurrence 通过 Rust `readRange` 以 64 Ki UTF-16 页面扫描；Ctrl+D 可跨输入窗继续/环绕，Ctrl+Shift+L 上限 10,000 selection。窗口外多选编辑、ZWJ emoji 字素退格、保存、撤销/重做和代理对中间选区拒绝均有 fixture。
- 之前已完成的插入/替换/退格、列选、IME overlay、复制/剪切、按行分配粘贴、独立 cursor history、Alt+Click 坐标与主 caret 保留证据继续有效；同一 DocumentId 多视图、屏幕阅读器和像素验收移交 P03.7。
- 定向集合 `flutter test --no-pub test/occurrence_search_test.dart test/workbench_multi_selection_test.dart test/rust_text_input_window_test.dart test/rust_text_input_field_test.dart`（`app/`）31 项通过。完整 `bash init.sh`：Rust workspace tests、Clippy、build_core 和 Flutter 217 项通过；`cargo fmt --all -- --check` 通过；`flutter analyze --no-pub` 0 issues。
- 变更前后 GitNexus 图谱索引范围、staged/all CRITICAL 风险与截断限制记录在 `docs/diagnostics/2026-10-30-p03/p03.5-multi-cursor-column-selection.md`；精确阶段快照门禁与检测待最终提交复核。
- P03.6 已开始：Rust-backed 输入控件内新增固定左侧的绝对行号 gutter，以 Rust `lineOffset` 二分映射有界输入窗起点；新绘制层增加缩进 guides 与 none/trailing/all 空白标记。未读取文档全文，也未改变 Rust delta/IME/ABI 路径。
- P03.6 新增默认 no-wrap 与显式 `wordWrap` 模式：按 bounded input window 的 TextPainter 度量建立横向滚动视口，仍使用 multiline TextField 并保留 LF；selection/caret 移动会用 ScrollPosition 轴方向自动显露，测试覆盖 LTR 与 RTL。
- renderer fixture 覆盖 CRLF/UTF-16 偏移、空末行、tab stop、CJK、组合字符、ZWJ emoji、RTL/gutter 顺序与编辑值更新；P03.6 定向输入/工作台集合 21 项通过，专用 renderer 集合 3 项通过，Flutter analyze 0 issues，cargo fmt 与 Rust/Clippy/core build 门通过。基础层提交前，工作树和 `HEAD + index` 精确 staged snapshot 的 `RUST_TEST_THREADS=1 bash init.sh` 均通过（Flutter 220 项）；staged snapshot 的 cargo fmt 与 Flutter analyze 0 issues。证据见 `docs/diagnostics/2026-10-30-p03/p03.6-editor-rendering.md`。
- P03.6 已加入版本化范围 decorations：以文档绝对 UTF-16 坐标提交，按 `RustTextInputWindow.version` 过滤陈旧装饰并裁剪到当前窗口；支持文字底层背景、边框和下划线。renderer 9 项 fixture 覆盖范围窗口裁剪、版本过期、实际像素与控件接线。
- P03.6 字体回退子切片：`RustTextInputField.fontFamilyFallback` 可字段级覆盖，默认提供多个跨平台等宽字体候选；EditableText 与 gutter/所有 renderer painter 复用同一解析样式。默认链和显式覆盖 fixture 均通过，未声称字体安装/OS 字形对照已验收。完整工作树与精确 HEAD+index snapshot 的 `bash init.sh` 均通过（Flutter 226 项），cargo fmt 与 Flutter analyze 0 issues 通过。
- 该范围装饰切片全工作树 `RUST_TEST_THREADS=1 bash init.sh` 通过（Flutter 226 项），精确 HEAD+index 快照完整 `bash init.sh` 也通过（Flutter 226 项）；两边 `cargo fmt --all -- --check` 与 `flutter analyze --no-pub` 均通过。
- P03.6 默认 no-wrap/wordWrap 子切片定向 renderer 6 项通过，保留多行 LF；全工作树 `RUST_TEST_THREADS=1 bash init.sh` 退出 0（Flutter 223 项）、`cargo fmt --all -- --check` 通过、`flutter analyze --no-pub` 0 issues。HEAD+index tree `914f6f1b45b34ea2ee2738bea93b9ca58d629ef3` 的独立解包快照也通过 `RUST_TEST_THREADS=1 bash init.sh`（Flutter 223 项）、cargo fmt 与 flutter analyze 0 issues。
- P03.6 尚未完成：字体回退配置、minimap/overview、sticky scroll、折叠、行级 decorations/provider 接线和视觉对照仍待做。P03.4 macOS/原生 DRM Linux IME 与屏幕边缘候选窗继续保留平台门；同文档多视图 selection 与屏幕阅读器/关闭生命周期留 P03.7。500 MiB 数值优化留 P14。

### 最新进展（2026-10-30，P03.4.2c Windows/Linux IME 部分平台证据）

- Windows 11 Alula Release + Microsoft Pinyin 已验证预编辑和光标附近候选条、Space 提交、追加组合后 Esc 取消、点击 Explorer 失焦。ABI v15，Release DLL 哈希与 `app/native/alula_core.dll` 一致；退出后隔离 journal 记录 `你好bei'jing`，未转换拼音在失焦时保留。
- 固定 Code-OSS 1.145.0-dev（`4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e`，`scripts/code.bat`、隔离 user-data、禁用扩展）同样记录 `你好bei'jing`，候选、提交、取消和焦点离开行为与 Windows Alula 相符。微软拼音 Tab 是候选导航，不算离开编辑器的证据。
- WSLg Linux + Fcitx5 Pinyin 的 Alula Release 通过原生输入回放：候选条在插入光标附近，Space 写入 `你好`，追加 `zhongguo` 后 Esc 保留已提交文本，点击 Explorer 后文档 journal 为 `你好bei jing`。这是 WSLg/X11，不等于原生 DRM Linux。
- 证据与截图：`docs/diagnostics/2026-10-30-p03/p03.4.2c-native-ime-platform-evidence.md`、同目录下 `p03.4.2c-windows/` 与 `p03.4.2c-linux-wslg/`。`flutter build linux --release --no-pub` 通过；运行在隔离 profile，操作前逐次核验前台窗口，结束时进程退出且恢复 ChatGPT 前台。macOS runner 不可用；屏幕边缘候选窗夹取也未测。单独 Alt+F4 关闭 WSLg Release 实例退出码 0，但 Flutter 隐式 view 移除仍有 `kInvalidArguments` 与 GLib critical，留待 P03.7 生命周期门。
- P03.4.2c 记为 partial、P03.4 保持 in-progress；按“先整体架构”的优先级，下一片继续 P03.5 多光标/列选择，把 macOS IME 与原生 DRM Linux 留作 P03.7 平台签收门。500 MiB 数值目标仍留待 P14，本阶段不做内存优化。

### 最新进展（2026-10-30，P03.4.2b2/b3 工作台有界 Rust 输入）

- 完成 P03.4.2b2/b3：`OpenDoc` 移除全文 `TextEditingController`，工作台现在以 Rust 文档作为文本/dirty/savepoint 权威，`RustTextInputField` 只持有最多 16,384 UTF-16 单元的本地编辑窗口。绝对 selection、窗口重定位、切换/保存/关闭前 flush 与 IME composition 提交已接入。
- 输入增量携带前向/逆向 TextOps；UndoStack 对连续输入保留坐标有序的批次并把双向插入载荷计入共享预算。大粘贴被直接提交到 Rust 后重置到有界窗口；超大 journal 文本跨重启完整恢复。版本冲突仅在基窗及绝对坐标安全时可自动重试，否则草稿保留并可复制。
- Rust savepoint 驱动 dirty；journal、保存、查找/替换、大纲、外部文件状态和跨文档 WorkspaceEdit 已改为从 Rust 文档读取或写入。未脏时 journal 不持久化文本；需要查询、保存或记录脏 journal 时会按需临时读取全文。超预算程序化编辑沿用受共享历史预算限制的旧快照帧。
- 验证：`FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 全量 186 项）；`cargo fmt --all -- --check`、`flutter analyze --no-pub` 零问题。定向输入/恢复用例通过；2,000,001 UTF-16 journal fixture 确认重启后 Rust 文本完整，Flutter 窗口为 16,383 单元，并显式确认冲突后完整保存到磁盘。
- GitNexus 变更前 `RustTextInputFieldState` 为 CRITICAL（64 项/118 流程）；`enqueue` 为 UNKNOWN，源码检索确认字段 listener、FFI/widget tests 和工作台 flush 路径。提交前图谱为 6,015 节点/11,499 边/328 流程，但 422 个入口候选和 251 个 callee 被截断；重复 staged 检测为 14 文件/71 符号、受影响流程数 94–296；all 为 45 文件/76–78 符号、受影响流程数 273–294，均为 CRITICAL。一次 all 返回 PARTIAL 后重跑成功。all 包含既有用户工作树改动；计数存在波动，不能用空结果解释为无影响。
- P03.4.2b2/b3 已关闭；P03.4 仍进行中，P03.4.2c 的 Windows/macOS/Linux Alula 原生 IME 候选定位/提交/取消实测尚未完成。500 MiB 内存目标继续按用户要求排到 P14，本切片不做整机内存目标测量。
- 报告：`docs/diagnostics/2026-10-30-p03/p03.4.2b-workbench-bounded-rust-input.md`。

### 最新进展（2026-10-30，P03.4.2b1 Rust savepoint 合同）

- Rust `TextBuffer` 持有 Rope savepoint 快照；可在成功保存时将当前内容设为 savepoint，也能在 journal 恢复时单独指定磁盘基线。dirty 与外部磁盘文本比较逐字节精确，不从 Rust Rope 物化完整 String；savepoint 操作不改变文本版本。
- ABI 升至 v15，Rust FFI 与 Dart `AlulaDoc` 双侧新增 set/mark/isDirty/matches 接口；Dart↔Rust fixture 覆盖 CJK、emoji、BOM/CRLF、编辑回到 savepoint、恢复基线和版本稳定。
- 定向 Rust buffer/core/FFI 测试 48 项通过；新 Dart FFI 测试通过。完整 `bash init.sh` EXIT=0（Flutter 179 项；大文本 journal fixture 2,000,001 UTF-16 单元成功写入并恢复），`cargo fmt --all -- --check`、`flutter analyze --no-pub` 均通过。报告：`docs/diagnostics/2026-10-30-p03/p03.4.2b1-rust-savepoint-state.md`。
- GitNexus pre-edit：`TextBuffer` 与 `DocRegistry` impact 均为 CRITICAL，`AlulaDoc` MEDIUM；ABI 常量为 UNKNOWN，源码确认 Rust FFI 自测及 Dart 加载握手的消费点。最终 staged detect-change 为 11 files/48 symbols、CRITICAL；all 为 43 files/54 symbols、CRITICAL，含既存用户改动。索引 5,945 nodes/307 flows 仍丢弃 404 个入口候选、192 个 callees 并截断 5 个 walk；报告保留该限制。Rope savepoint 用共享 Rope 根保持回退快照；此切片不是整机内存测量或 P14 优化。
- 限制：本切片只建 Rust 文档状态合同，工作台依然有全文 `TextEditingController`；dirty/savepoint 目前尚未由工作台消费。P03.4.2b2 接入有界输入控件，b3 再处理 undo/journal/查找/大纲/跨文档与生命周期。

### 最新进展（2026-10-30，P03.4.2a Flutter 有界 EditableText 适配器）

- 新增 `RustTextInputField`，以 Flutter `EditableText` 作为有界 Rust input session 的系统文本输入客户端；窗口不超过 64 Ki UTF-16。超限平台更新恢复到最近接受值并通知宿主，版本/FFI错误留 pending 并显示错误状态。宿主可显式 flush、commit 或 cancel composition；替换/移除控件前需先 flush。
- Flutter TestTextInput channel fixture 验证 composing overlay 未提前进 Rust、候选提交最终增量、取消恢复、超限恢复/宿主通知，并记录到有尺寸和非零屏幕变换的 `setEditableSizeAndTransform` 调用。P03.4.1 + .2a 定向 10 项全过。
- `cargo fmt --all -- --check`、`flutter analyze --no-pub`、`bash init.sh` EXIT=0；Rust workspace、Clippy、native core build 及 Flutter 全量 178 项通过（含 2,000,001 UTF-16 journal 恢复夹具）。
- 新控件 class exact upstream impact 为 LOW（仅本切片测试 importer/caller）；其 State class 的 exact impact 报 CRITICAL，直接边仅 `createState` 与测试 import，但向上流程扩散到全仓同名 Flutter 方法。暂存检测 7 files/7 symbols/28 flows、CRITICAL；全工作树 39 files/87 flows、CRITICAL，后者含既有用户变更。未使用 shared-axis 降级；源码搜索确认 workbench 不导入该组件。图谱另报告 388 入口候选/186 callee 截断。报告：`docs/diagnostics/2026-10-30-p03/p03.4.2a-flutter-ime-field.md`。
- 未接入工作台；Transform 通道不证明原生候选窗实际位置或 Windows/macOS/Linux IME 行为。P03.4.2b 接线前，`workbench_page.dart` 和其他现存用户修改不得混入本阶段提交。

### 最新进展（2026-10-30，P03.4.1 有界输入会话合同）

- 新增 `RustTextInputWindow`：Rust 读取最多 64 Ki UTF-16 输入窗，Flutter 仅在窗口内计算 delta，并把局部 TextOp 偏移平移到文档绝对坐标；窗口总大小硬限，超限不写 Rust。
- IME composition 作为 Flutter 临时 overlay，不提前修改 Rust authoritative text；平台提交后一次性回写 TextOps，取消返回已提交值；composition selection/range 保持窗口坐标并携带对应 Rust 替换范围，已提交 selection 才映射到文档绝对 UTF-16。超限输入被拒绝，版本失配保留 pending 值。
- 待写回使用单槽最新快照，100 次输入事件仅写入最后的 TextOp；失败时 pending 不丢。合同可在保存或焦点转移前明确提交/取消组合态。
- 定向 Dart↔Rust FFI 测试 7/7、`flutter analyze --no-pub` 零问题、`cargo fmt --all -- --check` 通过；`bash init.sh` EXIT=0：Rust workspace、Clippy、native core 构建与 Flutter 全量 175 项通过；超大恢复夹具已运行完成。无 Rust/ABI 修改。
- GitNexus 刷新后暂存变更检测为 7 files / 12 symbols / 87 affected processes、CRITICAL；全工作树 39 files / 87 flows、CRITICAL，含既有用户改动。新类精确 upstream impact 为 LOW（仅测试 importer、0 流程）；图谱报告 379 个候选入口与 186 个 callee 截断，已如实登记，不以低风险结论覆盖全局 CRITICAL。
- 报告：`docs/diagnostics/2026-10-30-p03/p03.4.1-input-window-contract.md`。输入合同未接入工作台控件，也没有原生候选窗或 Windows/macOS/Linux 产品 IME 证据；P03.4.2 将继续完成控件接线与平台验收。旧 CodeForge Windows 探针不替代产品门。

### 最新进展（2026-10-30，P03.3 Rust 唯一文本所有权与有界视口原型）

- P03.3 已完成并通过完整门禁。ABI v14 `readLines` 一次最多 256 行且总响应最多 64 Ki UTF-16；视口原型按 32 行/页、2,048 UTF-16 单元/行、每视图最多缓存 3 页读取 Rust 文档。10k 行末页、50k 行真实 FFI 双视图滚动/选区/独立状态与 100k 单行从第 90k 列续读均有 fixture。
- ADR 选择 Rust 唯一完整文本 + Flutter 有界分页绘制/选择，CodeForge 完整 Rope 与当前 TextField 全文控制器不作为最终大文档文本所有者。该原型只读且未替换工作台控件；输入/IME、多光标、跨页选择、无障碍、三平台与帧时延留在 P03.4–P03.7。
- 验证：`cargo fmt --all -- --check`、`bash init.sh` EXIT=0（workspace tests、Clippy、build_core、Flutter 168 项）、`flutter analyze --no-pub` 零问题；真实 FFI 控件测试通过。报告：`docs/diagnostics/2026-10-30-p03/p03.3-bounded-viewport-adr.md`。
- 预编辑 GitNexus 将 `TextBuffer` 与 `DocRegistry` 标为 CRITICAL；提交前 staged/all 结果见 P03.3 诊断报告。P03.4 是下一唯一活动切片。500 MiB 数值目标仍留在 P14，本片不做内存调优或整机测量。

### 最新进展（2026-10-30，P02.6 崩溃 journal 与大文本恢复）

- P02.6 已完成：journal 使用版本、generation 与 checksum；流式写入同目录临时文件，保留有效备份，启动时可从已 flush 临时代或备份恢复。兼容 legacy journal；坏数据、未知版本和写入失败均有明确状态/提示。
- 移除了旧 2,000,000 UTF-16 单元 journal 阈值。端到端夹具接受 2,000,001 单元脏文本，journal 持久化后重启全文一致恢复，原磁盘文件保持不变。独立子进程在临时 journal flush 后被强杀，重启从该临时代恢复。
- 验证：journal 单测 12/12、journal 错误提示 widget 定向测试通过、大文本端到端 fixture 通过；`bash init.sh` 完整门禁退出 0，Flutter 156 项全通过。日志 `/tmp/alula-p02.6-init-20261030.log`，详见 `docs/diagnostics/2026-10-30-p02/p02.6-crash-journal-large-text.md`。
- GitNexus 暂存范围变更分析：11 files、59 symbols、4 affected flows、MEDIUM；全工作树：41 files、77 symbols、4 affected flows、MEDIUM（包含已有 README、keybindings 等变更）。无 HIGH/CRITICAL。下一唯一活动切片 P02.7 跨文档编辑事务。Rust + rust-analyzer 500 MiB 数值优化继续安排在 P14。

### 历史进展（2026-10-30，P02.5 外部变更/冲突/只读/孤儿文档）

- P02.5 已完成：ABI v10 显式返回只读目标错误；干净外部重载保留光标、选区与滚动位置；本地脏内容与磁盘更新、journal 恢复内容与当前磁盘均保留两侧并要求用户显式处理。删除/重命名后的旧文档保持可编辑，普通保存不会静默重建原路径，另存为可恢复内容。
- 六个 Flutter 行为用例覆盖视图保留、磁盘冲突取消/覆盖、journal 恢复冲突、删除后继续编辑/另存、重命名孤儿状态和只读保存原字节保护；Rust 测试覆盖只读目标在原子替换前拒绝。
- 验证：`cargo fmt --check`、`cargo test --workspace`、`cargo clippy --workspace --all-targets -- -D warnings`、`bash scripts/build_core.sh`、`flutter analyze` 与 `bash init.sh` 全部通过；完整 Flutter suite 为 147 项。完整行为、图谱影响与限制见 `docs/diagnostics/2026-10-30-p02/p02.5-external-changes-conflicts.md`。
- P02 / feat-024 继续 in-progress；下一唯一活动切片 P02.6 崩溃 journal 与大文本恢复。500 MiB 性能优化目标继续留到 P14。

### 最新进展（2026-10-30，P02.4 编码/BOM/EOL）

- P02.4 已完成并通过完整门禁：Rust/Dart FFI ABI 升至 v9，支持 UTF-8、UTF-16LE/BE、GBK 与 LF/CRLF；保存/重开保留编码、BOM、EOL，编辑缓冲区统一 LF；GBK 不可表示字符会在原子替换前报错。无 BOM UTF-16 可手动选择编码打开，并能在会话恢复、Revert、外部检查中继续按 UTF-16 解码。
- UI 增加状态栏编码/EOL 操作及文件菜单命令；EOL 元数据进入 dirty/savepoint 与有界 undo/redo。测试覆盖 BOM/CRLF FFI 往返、GBK 不可表示内容不覆盖目标、UTF-8 BOM 保存、CRLF 撤销重做与写盘、无 BOM UTF-16 打开/重启恢复、混合 EOL 归一和无末尾换行保留。
- `cargo fmt --check`、`cargo test --workspace`、`cargo clippy --workspace --all-targets -- -D warnings`、`build_core`、`flutter analyze`、完整 Flutter 141 项与 `FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` 全通过。详细行为、GitNexus 图谱范围与限制见 `docs/diagnostics/2026-10-30-p02/p02.4-encoding-bom-eol.md`。
- P02 / feat-024 继续 in-progress；当前唯一活动切片转为 P02.5 外部变更、冲突、只读与孤儿文档。Rust + rust-analyzer 500 MiB 数值目标留在 P14 重定标，P02.4 未进行内存调优。

### 历史进展（2026-10-30，P02.1 每文档撤销/重做）

- 已完成 P02.1：撤销/重做状态、输入合并时间和程序化写回闸门改为按文档保存；命令上下文读取当前激活文档的历史。所有打开文档共享 100 条/2,000,000 UTF-16 code unit 历史预算，redo 帧也计入；关闭文档或工作台时释放对应历史。
- 验证通过：`cargo fmt --all -- --check`、`FLUTTER_BIN=/tmp/alula-flutter-serial bash init.sh`（Rust workspace tests、Clippy、build_core、Flutter 132/132）和 `flutter analyze --no-pub`；undo 栈与跨文档 widget 定向测试 20/20 通过。
- `P00.3 REF-07-UNDO-01` 夹具改为验证期望行为：两个文件交错编辑后，各自 undo 恢复本文件文本，redo 恢复本文件编辑。旧 P00 现状记录仅保留为历史证据。完整 impact、GitNexus 和验收边界见 `docs/diagnostics/2026-10-30-p02/p02.1-per-document-undo.md`。
- P02/feat-024 继续 in-progress；下一切片为 P02.2 savepoint、dirty 与 save/revert/save-as 生命周期。500 MiB 指标仍暂停，当前切片只保留历史容量和关闭释放约束。

### 最新进展（2026-10-30，P01.4 事件驱动工作区生命周期）

- P01.4 已完成：workspace watcher 增加 generation 防止旧根回调，attach/detach 串行切换并取消 pending debounce；语法只对打开/编辑/attach 的单文档防抖刷新，不再每 800ms 遍历所有 LSP 文档计算语法；关闭文档、工作区切换和退出时清理对应 timer/语法状态。
- 诊断快照保留轻量 800ms 轮询，但只在至少一个已 attach 的非 untitled LSP 文档时运行；没有此类文档就停止。该轮询只取诊断快照，不解析文档文本。
- `FLUTTER_BIN=/tmp/alula-flutter-serial bash init.sh` 最终退出 0：Rust workspace tests、Clippy、build_core、Flutter 130/130；`flutter analyze --no-pub`、`cargo fmt --check`、watcher/widget 聚焦测试也通过。首次完整运行中的 P00.3 双文档撤销夹具出现一次文档激活时序失败；夹具单项及第二轮完整串行门禁通过。
- GitNexus 与变更范围、未解析跨语言边、测试限制详见 `docs/diagnostics/2026-10-30-p01/p01.4-event-driven-workspace-lifecycle.md`。P01.1–P01.4 全部交付并阶段提交；下一项 P02 / feat-024。

### 最新进展（2026-10-30，P01.3 进程监督与资源状态）

- P01.3 已完成：新增 `editor-process` 统一监督 Rust LSP 与 Dart Git/搜索子进程，提供按需进程树快照、资源压力状态与临界态搜索回收；ABI 两侧同步到 v7，工作台只在工作区打开时每 30 秒采样并显示压力状态。
- 资源回收边界：Critical 转换取消待处理补全并结束 Search 进程树；Git 修改命令不会因压力被打断，编辑/保存路径不依赖压力状态。没有以 500 MiB 占用目标验收或做数值调优，完整压力注入 UI 验收留在 P14 场景矩阵。
- `FLUTTER_BIN=/tmp/alula-flutter-serial bash init.sh` 全部通过：Rust workspace tests、Clippy、`build_core`、Flutter 128/128。格式门、Flutter analyze、桥接/Git/搜索定向测试和进程树/临界回收测试也通过。
- 详细实现、验证与 GitNexus 限制记录：`docs/diagnostics/2026-10-30-p01/p01.3-process-resource-supervision.md`。P01.3 已阶段提交；当前唯一活动切片转为 P01.4 事件驱动工作区生命周期。

### 最新进展（2026-10-29，P01.2 命令与上下文引擎）

- SRV-06 已完成：`CommandService` 统一命令 ID/参数/条件/启用状态/执行结果；菜单、命令面板、键位、编辑器工具栏、面板标签与编辑器焦点链共用分发。Context expression 更新会立刻刷新 UI；`keybindings.json` 支持 `args` / `when`。
- `flutter analyze --no-pub` 零问题；全量 Flutter 测试串行 125/125 通过，widget 用例 15/15 通过。`cargo fmt --all -- --check` 与 `FLUTTER_BIN=/tmp/alula-flutter-serial bash init.sh` 均退出 0，后者完成 Rust tests、Clippy、build_core、Flutter 125/125。一次默认并行全量运行在既有 P00 双文档撤销 fixture 的断言失败，单项与串行复跑通过；详情见 `docs/diagnostics/2026-10-29-p01/p01.2-command-context-engine.md`。
- P01.2 已阶段完成，当前唯一活动切片转为 P01.3 进程监督与资源状态；500 MiB 数值验收继续暂停，架构阶段仍要求资源有界、关闭清理、压力下可编辑/保存。

### 最新进展（2026-10-29，用户调整复刻/优化顺序）

- 调度顺序改为先完成 P00–P13 的 VS Code 整体架构与默认功能复刻，再在 P14 做全功能性能/内存优化，P15 完成最终对照。Rust + rust-analyzer ≤500 MiB 暂停作为验收门；已有占用数据保留作基线，后续重新定标。
- P00 / feat-022 按阶段交付物签收：参考来源/构建差异、贡献项导出、golden/风险夹具和三项风险实验 ADR/证据已登记。真实 DRM/WPE GBM、Microsoft 官方服务身份/许可是 P12/P13/P14 后续风险，不再阻塞 P01。
- P01 / feat-023 继续进行：P01.1 异步请求/取消/版本契约与 P01.2 命令/上下文引擎已完成，当前唯一活动切片为 P01.3 进程监督与资源状态。架构阶段仍要求资源有界、服务按需启停、关闭后回收，并保证压力下可编辑/保存及无数据丢失；不提前做以数值占用达标为目的的优化。
- 启动基线首跑中，P00.3 `REF-07-UNDO-01` 曾因打开第二文件时的编辑时间戳落入 400ms undo coalescing 窗口而失败。测试在第二文件打开后增加 450ms 实时等待以隔离两次编辑；复跑 `bash init.sh --fast` 全通过（Rust workspace tests、build_core、Flutter 122/122），观测仍为双文档撤销串写这一既有夹具结果。
- 提交前 GitNexus `detect-changes --scope all` 覆盖工作树 38 个文件/11 个 symbols，报告 0 个受影响流程、low risk；staged 检查覆盖本次 7 个文件/1 个 AGENTS 文档 symbol、0 个受影响流程、low risk。索引报告既有流程图截断（417 个候选入口中 217 个未排名、130 个 callee 跳过、2 次 walk 达预算），因此 0 流程仅用于本次文档变更风险评估，不代表代码图完整。
- 本次变更文件：`AGENTS.md`、docs/03、docs/04、docs/10、`feature_list.json`、本文件与 `session-handoff.md`。

### 最新进展（2026-10-29，P01.1 异步请求/取消/版本契约）

- 按用户调整的顺序先做整体架构复刻；500 MiB 数值门槛暂时停用，资源有界、版本正确、关闭清理与压力下可编辑/保存仍是硬要求。P01 拆为四个有序切片；P01.1 已完成，当前唯一活动切片为 P01.2 命令与上下文引擎（权威状态见 docs/03 N.1）。
- editor-lsp 增加可轮询/取消的 JSON-RPC 请求句柄。editor-core 增加 async completion start/poll/cancel、32 项全局上限、版本校验；编辑、关闭文档、解除 LSP 挂接和工作区关闭会取消关联请求。ABI 两侧升为 v6；workbench 使用 Future 请求，版本变更或切换文档后的旧结果不更新面板。旧同步 ABI 与 API 保留兼容。
- 新增延迟 fake LSP 集成 fixture `crates/editor-core/tests/p01_async_completion.rs`，覆盖 start 非阻塞、编辑后取消、版本 2 返回、32 项上限及第 33 项背压、取消通知与工作区关闭；既有慢补全 fixture 继续验证同步兼容。
- 门禁全绿：`cargo fmt --all -- --check`、`cargo test --workspace`、`cargo clippy --workspace --all-targets -- -D warnings`、`bash scripts/build_core.sh`、app 下 `flutter analyze --no-pub`、`flutter test --no-pub`（122/122）及 `bash init.sh`。
- 契约与边界记录在 `docs/diagnostics/2026-10-29-p01/p01.1-async-completion-contract.md`。GitNexus staged 检查报 CRITICAL、35 条受影响流程；已展开 workspace shutdown/pending、同步 shutdown、文档 close 与 completion 等主路径，以逐符号 impact、源码调用点及全套 fixture/gates 核验，不用 riskSharedAxes 抵消。完整图谱仍截断（231 个候选入口未排名、135 个 callee 跳过、2 次 walk 达预算），因此保留风险记录而不宣称图谱完整。P01.1 已独立阶段提交；下一项为 P01.2 命令/context 影响分析。

### 最新进展（2026-10-29，第七十八轮，固定版 Code-OSS 30 分钟脚本编辑对照）

- 固定 Code-OSS 1.145.0-dev commit 4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e + rust-analyzer 0.3.3089/server 1.97.1，在隔离 profile/扩展/shared-data 与 rust-mini 副本上完成 1800.556 秒脚本编辑对照。临时 helper extension 用 VS Code TextEditor API 每 12 秒追加并保存一个 Rust 注释：150/150 次保存均读盘验证，最终标记齐全，源 fixture SHA-256 未变；RA 可见。
- 采集 1484 个进程树样本、首末跨度 1798.990 秒、中位间隔 1.197 秒。Private Bytes 峰值/尾段最后 40% 上中位/末值为 2223.14/1774.34/1788.38 MiB，末 Working Set 1853.30 MiB。尾段进程组中位 Private Bytes：Code-OSS 1327.12 MiB，rust-analyzer 431.38 MiB；统计包含临时 helper extension 开销。一次启动焦点恢复后无重复，关闭+30 秒所有观察 PID 退出，临时目录清理。
- 30 秒预检完成 6/6 次保存。首次纯窗口 API 恢复前台受 Windows 限制、未开始采样；改用短暂 Alt 授权恢复后预检和正式运行通过。该脚本编辑不是键盘延迟或 Alula 编辑体验验收；仍高于 500 MiB 产品目标，真实 DRM/WPE GBM、官方服务身份/许可与完整 docs/04 矩阵未完成。P00.4 仍 blocked/in-progress，P01 不启动。
- 证据：docs/diagnostics/2026-10-28-p00/p00.4-windows-code-oss-rust-lsp-edit-30m-20261029-181513092.json/.md、p00.4-windows-code-oss-rust-lsp-edit-30m.ps1；预检报告 p00.4-windows-code-oss-rust-lsp-edit-preflight-20261029-181116397.json/.md。
- bash init.sh、cargo fmt --check、flutter analyze 全部退出 0；Rust tests、Clippy、build_core、Flutter 122 项测试通过。GitNexus analyze/status 刷新完成；detect-changes --scope all 覆盖当前 43 个变更文件、20 个 symbols、0 个受影响流程、low 风险；范围包含工作树既有改动，本轮只提交限定证据文件和状态记录。

### 最新进展（2026-10-29，第七十七轮，Windows VS Code 同服务 idle 复跑 3）

- WSL 到 Windows PowerShell 的互操作已恢复。按用户授权，用新隔离 profile、rust-analyzer 0.3.3089 扩展副本、同服务 server 1.97.1 与 rust-mini fixture 完成 Microsoft VS Code 1.142.0 Stable idle 复跑：600 点、实际 858 秒、采样跨度 856.532 秒、中位间隔 1.422 秒；Private Bytes 峰值/尾段稳定/末值 1728.71/1431.09/1423.68 MiB，末 Working Set 1648.97 MiB。
- RA 在进程树可见。启动时焦点恢复一次；关闭+30 秒所有记录 PID 退出，profile、扩展副本和 shared-data 已清理。该样本只补充 idle 对照，不能替代固定 Code-OSS 1.145.0-dev、30 分钟编辑或 docs/04 全矩阵。
- 五轮 VS Code 同服务 idle 稳定值为 1267.18/1324.33/1298.38/1351.11/1431.09 MiB，中位数 1324.33 MiB；单轮间有明显差异。P00.4 保持 blocked/in-progress，P01 不启动。报告：`docs/diagnostics/2026-10-28-p00/p00.4-windows-vscode-rust-lsp-idle-rerun3-20261029-172235485.{json,md}`；日志与 runner 同目录。
- 第七十八轮继续完成了这组提交前门禁与 GitNexus 变更分析，结果见上文；其余既有未提交改动不纳入该轮提交。

### 最新进展（2026-10-29，第七十六轮，固定版 Code-OSS Rust+RA idle 对照完成）

- 复现并定位 Code-OSS 无 renderer 的根因：旧生成的 NLS-indexed `out/mainImpl.js` 与开发启动器 `VSCODE_DEV=1` 不兼容，主进程抛出 `NLS MISSING: 140`。Windows Node 24.22.1 重跑标准 dev transpile 后，30 秒隔离 smoke 在 6 秒内看到 renderer。
- 用户授权的固定 Code-OSS 1.145.0-dev / Electron 43.8.3 + rust-analyzer extension 0.3.3089 / server 1.97.1 idle 对照完成：600 个样本，实际跨度 888.565 秒（中位间隔 1.472 秒）；Private Bytes 峰值/尾段稳定/末值 2346.86/1702.66/1705.49 MiB，末 Working Set 1899.62 MiB。RA 在进程树中，焦点未变，关闭+30秒 PID 全退，隔离目录已清理。
- 报告和原始数据：`docs/diagnostics/2026-10-28-p00/p00.4-windows-code-oss-rust-lsp-idle-20261029-160631502.{json,md,log}`；旧失败诊断已补根因和修复记录。
- 此为 idle 参考，不能替代 Alula 的 30 分钟编辑或 docs/04 完整矩阵。Alula run3 稳态仍超 500 MiB；真实 DRM/WPE GBM 与 Microsoft 官方服务身份/许可未解决，故 P00.4/feat-022 保持 blocked/in-progress，P01 不启动。
- 提交前验证：`bash init.sh` 通过 Rust workspace tests、Clippy、`build_core` 和 Flutter 122 项测试；`cargo fmt --check` 与 `flutter analyze` 也通过（No issues found）。
- 阶段证据提交 `b6dd5f4` 已推送到 `origin/codex/vscode-parity-p00`。


### 最新进展（2026-10-29，第七十四轮，Windows LRU 内存筛选）

- 为评估 RA 缓存上限，完成 capacity 128/32/16 的三个 120 秒隔离筛选，并对 capacity 16 完成 1800 秒、150/150 次保存长测。配置均被 RA 读取且无校验错误；四轮采样关闭+30秒进程全退，长测前台恢复成功。
- capacity 16 短筛选稳定 593.06 MiB；长测峰值/稳定/末值为 858.18/659.96/236.84 MiB，stable 比既有默认配置 30 分钟 run3 的 657.93 MiB 高 2.03 MiB，仍超 500 MiB 目标 159.96 MiB。短时降幅未在长负载复现，不调整产品默认值。
- 详情与四轮原始文件：`docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-rust-lsp-lru-capacity-screen-20261029.md`。P00.4 继续 blocked/in-progress；P01 不启动。


指标口径修正（2026-10-29）：同服务 VS Code idle 的稳定值按 `tools/mem-probe::summarize` 算法：取时间顺序最后 240 个样本，对这些值排序并取上中位数。四轮稳定值为 1267.18、1324.33、1298.38、1351.11 MiB，中位数 1311.36 MiB；新增第四轮尾段起始 t=436.187 s。原始采样均保留。

用户目标变更为：按现有 **Flutter + Rust** 栈，对固定版本VSCode默认无需用户安装扩展的
全部非外接AI功能与界面做1:1复刻。计划已完成，P00.1已完成，P00总包继续执行，**产品完整复刻未实施**。
当前唯一状态/DoD见docs/03新主线；计划在docs/10、逐项功能族在docs/11。
旧原型可复用，但done不继承为新等价验收；未完成旧项保留证据并退回not-started/legacy。
P00.1 固定 SHA 源码/发行物与构建路径、P00.2 原子贡献/运行时注册项导出器、P00.3 Golden 基线与现状故障夹具均已完成；2026-10-28 Windows Git Bash 复跑的四项 P00.3 命令与完整门禁全部通过。P00.4 三项实验均有 ADR 与证据：编辑器 Windows 探针完成；Web 有 Windows Flutter/WebView2（stable 6.1.5 原始结果与 beta 6.2.0 兼容性复跑）、Linux WebKitGTK 原生 GTK，以及 Flutter/WPE 2.52.6 源码构建后的 Xvfb MHTML/截图/销毁回放；基线回放依赖隔离容器关闭 WebKit sandbox 与 GBM；后续在 Docker `SYS_ADMIN` + `seccomp=unconfined`、UID 1000 下运行，sandbox-disable 变量保持 unset，采样含 bwrap/WPEWebProcess，原始无等待首帧 PNG 为全透明缓冲；插件截图 API 只复制当前像素缓冲、不等 WPE 帧回调。隔离探针现于 DOM 查询前轮询页面标题蓝色像素，三次默认 sandbox 冷启动均取得初始页与 MHTML 截图，最终版本一次重试后通过。此为探针级时序处理，不提供产品层帧同步保证；本地回放关闭 GBM，后续 CI 虽将 GBM-disable 变量 unset 但使用 Xvfb/software GL，硬件 GBM 仍未验证。Debian sid WPE 2.54.2 设置 API 不兼容和 Trixie 2.48.3 FDO WebKit API 缺失仍是发行包阻塞；Linux CDP 不支持；WPE 2.52.6 Remote Web Inspector HTTP target discovery/Main.html (HTTP 200) 与 WPE Inspector protocol command session 已验证；经 Target.sendMessageToTarget 调用 Runtime.enable/Runtime.evaluate 并返回页面 title/marker，Linux CDP 仍不支持；WSLg 宿主在 `GALLIUM_DRIVER=d3d12` 下成功创建 D3D12 EGL/GLES context；临时 Debian GBM probe 因缺 DRI driver 返回 null，不能推断 WPE GBM。随后 WPE 2.52.6 快照容器映射 WSLg 设备、GBM enabled 且 software GL unset 时，Flutter EGL context 失败、WPEWebProcess crash、90 秒内未到 initial-loaded；WSLg X11 :0 与 Wayland socket 的容器 EGL 检查都返回 EGL_NOT_INITIALIZED；Wayland socket 可连接但无 GLES2 config；直接 WPE 镜像 GBM probe 打开 render node 后 `gbm_create_device` 返回 null。记录在 `p00.4-linux-wpe-wslg-d3d12-run/` 与 `p00.4-wslg-egl-evidence.json`；这属于当前环境集成失败，WPE GBM 仍未验证。macOS WKWebView Web Archive 已由 macOS 15 runner 验证保存与同一视图重载（693 bytes，title/marker 正确，archiveParsed=true）；run 40647161201 又通过 Safari Web Inspector 页面级附着，截图可见目标 DOM。docs/04 产品内存仍未验收。官方服务实验发现 Marketplace 与 Code-OSS fork 的明确政策阻塞。P00.4 标记 blocked；feat-022/P00 仍 in-progress。2026-10-28 三轮 WPE 自动生命周期采样与三轮无截图 F5 复跑显示销毁+30s仍有残留，中位数见第三十一轮；这些探针样本不满足 docs/04 DoD。Heaptrack 单轮插桩峰值路径见第三十二轮。第三十三轮以 UID 1000 未插桩 smaps 复测得到 +40.9 MiB private/+43.2 MiB PSS；父进程 `[heap]`、WPE WebKit 文件映射与匿名映射驻留增加，但仍无法判断 live object、分配器保留或具体 owner，不能据此判定泄漏。P00.4 继续 blocked；同一 WPE 探针10轮创建/销毁后，第10轮 destroy+30s 比初始高81.2 MiB private/83.6 MiB PSS，匿名映射持续增加且有回落，不能证明泄漏或 owner；P01仍受P00依赖约束。Windows Rust+RA 三轮 10 分钟 idle 尾部稳定态为 589.09/589.27/589.09 MiB，中位数 589.09 MiB，较 500 MiB 目标高 89.09 MiB；未观察到 idle 增长或预算恢复。三轮关闭+30秒均未见残留 PID。用户确认暂无真实 DRM Linux 主机或获授权的 Microsoft 官方客户端身份；Windows Alula Rust+RA 30分钟编辑脚本的30秒预检保存6次编辑，稳定 Private Bytes 为645.64 MiB；当时关闭+30秒 PID 已退出，但 stderr 报 `client exited without proper shutdown sequence`；第五十九轮已修复 Windows 原生 close 路径，真实 rust-analyzer 30 秒冒烟与完整 30 分钟复测 stderr 均不再出现该错误。此前三次启动编辑因前台切换中断（约291秒、171秒、732.329秒），未形成完整样本。之后 Windows Rust+RA 的 run1/2/3 三轮30分钟脚本化编辑均完成，每轮150次保存、1,800秒、1,808个一秒内存样本；稳定 Private Bytes 为676.20/672.36/660.81 MiB，中位数672.36 MiB，超过500 MiB预算172.36 MiB。三轮关闭+30秒后记录进程均退出，但 rust-analyzer 均报告非优雅关闭。run3正式完成前另两次重试分别在1654.929秒/137次和250.845秒/20次保存校验失败，均不计样本。P00.4 仍 blocked。同服务 VS Code 1.142.0 Stable + 相同 rust-analyzer 1.97.1 的隔离 idle 对照已完成四轮：稳定 Private Bytes 为 1267.18/1324.33/1298.38/1351.11 MiB，中位数 1311.36 MiB；最近两轮关闭+30秒进程全退，均发生一次启动焦点恢复后继续采样。版本不匹配固定 Code-OSS 1.145.0-dev，只作补充证据。VS Code 1.142.0 的隔离 profile/扩展副本经 PowerShell 最小化和 WSH `SW_SHOWMINNOACTIVE` 两种方式启动时都切换了前台；两次守卫均恢复原窗口并终止隔离实例，未采集内存数据；临时数据已清除。

### 最新进展（2026-10-29，第七十三轮，恢复 WSL 并完成 VS Code idle 对照）

- WSL interop 与路由检查已恢复；GitNexus 索引重建并显示 up-to-date。索引有 entry-point/callee/walk budget 截断，不能把空调用集合当成全量无影响结论。本轮 `bash init.sh --fast` 通过 Rust workspace tests、`build_core` 与 Flutter 122 项测试。
- 完成用户授权的隔离 Windows VS Code 同服务 idle 复跑：Microsoft VS Code 1.142.0 Stable + rust-analyzer extension 0.3.3089/server 1.97.1；独立 user-data、扩展和 shared-data，telemetry/自动更新关闭、未登录或 Sync。600 点覆盖 729.671 秒；Private Bytes 峰值/尾段稳定/末值 1630.83/1351.11/1343.63 MiB，末 Working Set 1556.62 MiB。RA 在树中；一次启动焦点恢复成功；13 个记录 PID 在关闭+30 秒全部退出，隔离目录已清理。
- 四轮 VS Code idle 稳定值为 1267.18/1324.33/1298.38/1351.11 MiB，中位数 1311.36 MiB。VS Code 版本不匹配固定 Code-OSS 1.145.0-dev，本轮也不是编辑场景。Windows Alula Rust+RA 30 分钟稳定态仍高于 500 MiB；真实 DRM/WPE GBM、Microsoft 官方服务身份/许可与完整 docs/04 产品/平台矩阵仍未完成。P00.4 继续 blocked、feat-022 保持 in-progress，P01 不启动。
- 报告：`docs/diagnostics/2026-10-28-p00/p00.4-windows-vscode-rust-lsp-idle-repeat2-20261029-024524.{json,md}`；运行日志：`p00.4-windows-vscode-rust-lsp-idle-20261029-134127345.log`；复跑脚本：`p00.4-vscode-rust-lsp-idle-repeat2-20261029-024524.ps1`。

### 最新进展（2026-10-29，第七十二轮，恢复后第二次复核）

- 再次确认 WSL interop 未恢复，旧 GitNexus 与 route-netlink D 状态进程仍在；直接启动 `cmd.exe /c echo WSL_TO_WINDOWS_OK` 仍返回 `UtilAcceptVsock:281: accept4 failed 110`。不启动新的 VS Code 或 GitNexus 进程。
- 已复核隔离脚本、`Code.exe`、user-data、扩展副本与 shared-data 目录均还在，无本轮采样输出；WSL 重启后可直接续跑。记录追加在 `docs/diagnostics/2026-10-29-p00/p00.4-windows-vscode-rust-lsp-idle-rerun-blocked-20261029.md`。P00.4 仍 blocked/in-progress，未提交。

### 最新进展（2026-10-29，第七十一轮，恢复后复核）

- 当前 goal 恢复后重新核对，WSL 未重启：interop/distro 环境变量仍为空；之前 GitNexus 和 route-netlink 进程保持 D 状态。一次安全的 `ip route show` 重试仍挂起，随后只终止 timeout 包装进程，D 状态的内核等待进程仍在。
- 从独立 Node REPL 尝试启动 Windows PowerShell，也返回 `UtilAcceptVsock:281: accept4 failed 110`。没有 Code.exe、焦点变化或内存样本；不继续制造 route-netlink/GitNexus 等待进程。证据补入 `docs/diagnostics/2026-10-29-p00/p00.4-windows-vscode-rust-lsp-idle-rerun-blocked-20261029.md`。
- 需要先在 Windows 宿主终止并重启当前 WSL 发行版；恢复后检查 route/GitNexus，继续已授权的隔离采样。P00.4 保持 blocked，feat-022 in-progress，P01 不启动；不提交，因为 GitNexus pre-commit 检查仍不可用。

### 最新进展（2026-10-29，第七十轮）

- 用户授权重跑隔离 VS Code + 相同 rust-analyzer 1.97.1 的 10 分钟 idle 对照。执行前确认 Linux 基线：`init.sh --fast` 中 Rust workspace tests、`build_core` 与 Flutter 122 项全部通过。
- Windows PowerShell 从 WSL 启动失败：`UtilAcceptVsock:281: accept4 failed 110`；显式设置两个现有 WSL interop socket 也失败。本轮没有启动 Code.exe、没有窗口焦点变化、没有内存样本。隔离 profile/扩展/shared-data 和 timestamped runner 已准备，详见 `docs/diagnostics/2026-10-29-p00/p00.4-windows-vscode-rust-lsp-idle-rerun-blocked-20261029.md`。
- WSL `ip route show` 与 GitNexus `status/analyze` 均进入内核 D 状态（route-netlink dump），无法由信号结束。`dmesg` 显示 `kworker/0:1` 在 `hv_pri_chan vmbus_add_channel_work` 阻塞超 483 秒，多个请求等待其 mutex；需宿主侧终止/重启当前 WSL 发行版。GitNexus 新鲜度无法确认，本轮不提交。恢复 WSL 后先检查 `ip route show` 和 GitNexus，再运行隔离 runner。P00/feat-022 继续 in-progress，P00.4 blocked，P01 不开始。

### 最新进展（2026-10-29，第六十八轮）

- 按用户授权，再次运行隔离 Windows VS Code 1.142.0 + rust-analyzer extension 0.3.3089 / server 1.97.1 idle 对照。独立 profile、扩展副本、shared-data 目录；未登录账号，遥测/自动更新关闭。600 个进程树样本覆盖 762.063 秒，Private Bytes 峰值/时间尾段40%上中位/末值为 1689.98/1298.38/1306.09 MiB，末 Working Set 1545.98 MiB；尾段起点 t=451.293 秒。RA 进程可见，启动焦点恢复一次，13 个记录 PID 关闭+30秒全退。三轮稳定值 1267.18/1324.33/1298.38 MiB，中位数 1298.38 MiB。固定参考仍是 Code-OSS 1.145.0-dev，此 1.142.0 Stable idle 样本只作补充对照。
- 做了隔离的 rust-analyzer `cachePriming.enable=false` 120 秒烟测；RA 日志确认项目配置已处理且无配置错误。对齐前 120 个活动样本后，稳定值 634.10 MiB 对 638.12 MiB，峰值 747.17 MiB 对 642.84 MiB；稳定差异约 4 MiB，启动阶段峰值更高约 104 MiB，证据不足以采用或推广此配置。没有改产品代码。报告：`docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-rust-lsp-cachepriming-off-20261029-091012539.md`。
- P00.4/feat-022 仍 blocked/in-progress：Windows Alula Rust+RA 稳态仍超 500 MiB，且真实 DRM/WPE GBM、官方服务身份/许可和完整跨平台内存矩阵未完成。新对照不覆盖编辑负载或固定 Code-OSS 版本，P01 不启动。数据与脚本：`docs/diagnostics/2026-10-28-p00/p00.4-windows-vscode-rust-lsp-idle-repeat-20261029-011501.{json,md,ps1}`。

### 最新进展（2026-10-29，第六十六轮）

- 按启动守则复跑 `PATH=/home/vegetable/.cargo/bin:/home/vegetable/develop/flutter/bin:$PATH PUB_CACHE=/mnt/c/Users/Vegetable/AppData/Local/Pub/Cache bash init.sh --fast`：Rust workspace tests、`build_core` 和 Flutter 122 项全部通过。原临时 WSL Pub Cache 已不存在；使用已有 Windows Pub Cache 的包离线运行 `flutter pub get --offline --enforce-lockfile` 成功，tracked pubspec/lock 未因恢复而改动。
- 从 Windows Alula Rust+RA 第六十五轮的既有 activity JSON 计算进程明细：尾部13个完整快照的主 rust-analyzer 中位数425.05 MiB、Alula 226.11 MiB、launcher 3.21 MiB、proc-macro 2.86 MiB；同时间戳树合计中位数657.38 MiB，和逐秒稳定值657.93 MiB相符。500 MiB门仍未通过；若服务器不变，Alula只剩约68.88 MiB预算。该推导不作为无法优化的结论，也不改变预算或关闭语言服务。报告：`docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-rust-lsp-edit-30m-run3-20261029-065714888-process-breakdown.md`。
- 下一步在保持 rust-analyzer 能力、编辑/保存可靠性与固定功能范围的前提下查找可测的内存优化点；真实 DRM/WPE GBM、官方服务身份/许可及完整 docs/04 跨平台矩阵仍未完成。P00.4 blocked，feat-022 in-progress，P01 不启动。

### 最新进展（2026-10-29，第六十五轮）

用户要求完整重试前台流程后，Windows Alula Rust+RA 编辑样本完成 1800.015 秒、150/150 次保存、1815 个采样；Private Bytes 峰值/稳定/最终 841.89/657.93/233.85 MiB，marker/hash 通过，关闭+30秒 6 个 PID 全退，隔离目录清理且原前台恢复。按授权完成的同服务 VS Code 1.142.0 idle 对照和 WSLg/Xvfb 主应用 Rust+RA 10 分钟 idle 单轮也已登记；VS Code 稳定 Private Bytes 1267.18 MiB，WSL memory.current/PSS 峰值 803.91/889.30 MiB、OOM=0。Windows 稳态超预算，VS Code 版本不匹配 pinned Code-OSS，WSL 仅软件渲染单轮；真实 DRM/WPE GBM、官方服务身份/许可及完整 docs/04 矩阵仍阻塞。P00.4 blocked，feat-022 in-progress，P01 不开始。证据索引见 docs/03 与下方第六十五轮。

2026-10-28 WSLg GBM follow-up：`libgbm-dev` 已安装，普通 uid 1000 可在 WSLg faux DRM 的 `card0` 分配/导出 GBM dma-buf；GBM EGL 无 GLES2 pbuffer config，surfaceless context 使用 llvmpipe 软件渲染。未运行 WPE，不满足硬件 GBM 验收；完整数据在 `docs/diagnostics/2026-10-28-p00/wslg-gbm-egl-evidence.json`。WSL Rust fmt/tests/clippy/release build 复验全通过；现已在 WSL ext4 安装 Flutter stable 3.47.8/Dart 3.13.7，离线 pub 依赖解析成功，WSL 的 cargo fmt、完整 bash init.sh、flutter analyze 与 flutter test 均通过。另已安装 clang、CMake、Ninja、pkg-config、GTK、libstdc++-12-dev、Epoxy、libsecret、GBM 开发依赖，`flutter doctor -v` 确认 Linux desktop toolchain 可用；Flutter bin 已加入 Bash PATH。原生 runner 证据见 `docs/diagnostics/2026-10-28-p00/wsl-flutter-validation.md`。

## 今日会话（2026-10-29 第六十三轮）：恢复前台验收并完成 WSL cgroup 探索

- 用户报告前台进程误关闭后，已重新完整执行 Windows 隔离 HOME/`rust-mini`/Release Rust+RA 编辑流程：1800.011 秒、150/150 次保存、1817 个一秒样本；Private Bytes 峰值/稳定/最终值 846.68/661.44/233.00 MiB。稳定值仍高于 500 MiB 目标 161.44 MiB；4 个观察 PID 关闭+30 秒后均退出，临时数据清除、原前台恢复。报告：`docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-rust-lsp-edit-30m-run3-20261029-043806492.{json,md}`、`-activity.json`、`-probe.stderr.log`。
- 从 WSL 中断点恢复，`bash init.sh --fast` 退出 0（Rust tests、core build、Flutter 122 项）。安装 Xvfb/xdotool/netpbm 并在隔离 fixture 下完成 Linux 主应用 cgroup 交互探索：512 MiB 无 LSP 单轮保存通过；512 MiB 含真实 Rust Analyzer 被 OOM killer 终止；1 GiB 含 Rust Analyzer 单轮保存通过，采样峰值 903,749,632 bytes，OOM=0。
- 1 GiB 与 512 MiB 无 LSP 成功关闭返回 0，但仍有 Flutter `FlutterEngineRemoveView returned kInvalidArguments` warning。各场景仅单轮，不满足 docs/04 的完整多档重复及长时进程树矩阵；真实 DRM/WPE GBM 与官方服务授权仍阻塞。P00.4 保持 blocked，P01 不启动。完整限制与原始证据见 `docs/diagnostics/2026-10-29-p00/p00.4-wsl-linux-cgroup-interaction.md`。
- 随后完成 cgroup v2 重复矩阵：Xvfb、Linux Release 主应用和子服务同处 scope，swap=0；64/128/256/512/1024 MiB、no-RA/RA 每档 3 次，no-RA 256 MiB 因 1 次 marker 校验失败追加第 4 次，保留原始失败。31 次中 no-RA 256/512/1024 MiB 保存并关闭为 3/4、3/3、3/3；RA 1 GiB 3/3 成功，RA 64–512 MiB 均 3/3 OOM。旧单轮的 Xvfb 实际在 scope 外，已更正交互报告。该短时 WSLg/Xvfb 软件渲染矩阵仍不等于 docs/04 长时产品验收，P00.4 blocked、P01 不启动。证据：`docs/diagnostics/2026-10-29-p00/p00.4-wsl-main-app-cgroup-matrix.md` 与同名 JSON。
- 追加 1 GiB RA cgroup 长时编辑：1800.000 秒、150/150 次磁盘保存、1 秒采样 1838 个；峰值 `memory.current` 837.59 MiB，scope PSS 924.75 MiB，OOM=0。产品进程树尾部 10 分钟 PSS 中位数 870.53 MiB，比 500 MiB 目标高 370.53 MiB；前后 10 分钟中位数上升约 13 MiB。关闭+30.002 秒 Alula 退出码 0、无 RA/proc-macro；仍有 watcher 与 FlutterEngineRemoveView 告警。该 WSLg/Xvfb/software-GL 单轮不覆盖 10 分钟 idle、模型负载或 VS Code 对照。证据：`docs/diagnostics/2026-10-29-p00/p00.4-wsl-rust-ra-30m-cgroup-1024-20261028-223917.md` 与同名 JSON。
- 提交 `e0256b2` 已按既有授权推送，GitHub CI run `40772304233` 全绿：Harness、Ubuntu/Windows Rust fmt/Clippy/tests，Flutter analyze 与 122 项测试通过。
- 按会话收尾要求再次运行本机完整 `PATH=/home/vegetable/.cargo/bin:/home/vegetable/develop/flutter/bin:$PATH PUB_CACHE=/tmp/alula-pub-cache bash init.sh`，退出 0：workspace tests、Clippy、build_core 和 Flutter 122 项通过；超大 recovery fixture 2:36。

## 今日会话（2026-10-29 第六十二轮）：Windows 前台 Rust+RA 编辑验收复跑

- WSL `PATH=/home/vegetable/.cargo/bin:/home/vegetable/develop/flutter/bin:$PATH PUB_CACHE=/tmp/alula-pub-cache bash init.sh --fast` 从中断点恢复并退出 0：Rust workspace tests、`build_core` 与 Flutter 122 项测试均通过。
- 按用户要求从隔离 HOME/`rust-mini` fixture 到退出清理重跑 Windows Release 前台编辑流程。1800.011 秒、150/150 次保存、1817 个一秒 mem-probe 样本；Private Bytes 峰值/稳定/最终值 846.68/661.44/233.00 MiB。稳定值比 500 MiB 目标高 161.44 MiB，不能据此关闭内存门。
- Marker/hash 校验通过；关闭+30 秒后 4 个观察 PID 均退出，临时 HOME/fixture 删除且原前台恢复。stderr 有两条 watcher-path 告警，没有 `client exited without proper shutdown sequence`。这是额外 follow-up，不并入原三轮中位数。
- P00.4 仍 blocked，P01 不启动；主应用 UI/cgroup 限额交互、完整 docs/04 矩阵、真实 DRM/WPE GBM、官方服务身份/许可和 VS Code 对照仍缺证据。报告：`docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-rust-lsp-edit-30m-run3-20261029-043806492.{json,md}`、`-activity.json`、`-probe.stderr.log`。

## 今日会话（2026-10-29 第六十一轮）：WSL 主应用 Linux runner

- 为 P00.4 主应用验证新增并纳入源码控制 `app/linux/` Flutter runner；Linux release bundle 将 `libalula_core.so` 放到可执行文件旁。修正 `build_core.sh` 根据 Rust host triple 选择库，避免共享 WSL/Windows 工作树时把旧 DLL 复制给 Linux；WSL 与 Windows Git Bash 两端复制验证通过。
- `flutter pub get --offline --enforce-lockfile`、`flutter build linux --release --no-pub` 成功；bundle 含正确 ELF Rust 核心。`flutter test --no-pub test/core_sync_test.dart` 的 6 项真实 FFI 测试通过。`cargo fmt --check`、workspace Clippy、`flutter analyze --no-pub` 与修正后的 `bash init.sh --fast` 均通过，Flutter 122 项全绿。
- 主应用 Linux 目前只验证了 Release build 与 FFI；隔离桌面 UI smoke、docs/04 产品内存矩阵/cgroup 限额交互尚未通过。WSLg 软件渲染不能替代 DRM/WPE GBM/DMABUF。P00.4 保持 blocked，P01 不启动。证据：`docs/diagnostics/2026-10-29-p00/p00.4-wsl-linux-main-runner.md`。

## 今日会话（2026-10-29 第六十轮）：WSL 快速门禁与跨平台 CI 复验

- 当前分支 `5e6e0ce` 已按既有授权推送。远端 CI run `40758401730` 全绿：Windows/Ubuntu Rust fmt、Clippy、workspace tests，Flutter analyze/122 项 tests 与 harness 校验通过；Flutter job 用时 6m12s。macOS Web Engine Probe `40758401692` 与 Linux WPE Web Engine Probe `40758401773` 的 analyze/test/build/replay jobs 也全绿。
- WSL 重跑 `PATH=/home/vegetable/.cargo/bin:/home/vegetable/develop/flutter/bin:$PATH PUB_CACHE=/tmp/alula-pub-cache bash init.sh --fast` 退出 0，包含 Rust workspace tests、build_core 与 Flutter 122 项默认并行测试。此前并行 Undo fixture 单次失败后，本次并行全套、隔离 fixture 与此前串行全套均通过；根因未定位。fixture 输出仍刻画预期的当前 Undo/recovery 行为，不代表这些已知产品缺口已修复。
- CI 只验证本次已提交的关闭路径代码与独立 Web Engine probes。macOS/Linux probe 不是主应用跨平台 build；Linux runner 使用 Xvfb/software GL，不验证真实 DRM GBM/DMABUF。P00.4 的内存、服务身份/许可与对照门未解除，P01 不启动。证据：`docs/diagnostics/2026-10-29-p00/p00.4-cross-platform-validation-followup-20261029.md`。

## 今日会话（2026-10-29 第五十九轮）：Windows 原生关闭路径与真实 LSP 重跑

- 前一轮 post-fix 30 秒/30 分钟 Rust+RA 运行仍有 `client exited without proper shutdown sequence`。源码追踪确认 `window_manager` 0.5.2 的 Windows `WM_CLOSE` 在默认 `preventClose=false` 时不会等待 Flutter `dispose()`；fake-server 测试没有覆盖原生窗口关闭边界。
- 主入口现启用 `setPreventClose(true)`；标题栏实现 `onWindowClose`，在销毁窗口前调用 `_shutdownLspWorkspace`。Flutter `dispose()` 仍调用同一 helper 作为回退路径。
- Windows `flutter analyze --no-pub`、`flutter test --no-pub`（122 项）及 `flutter build windows --release --no-pub` 均通过。30 秒真实 rust-analyzer 冒烟的 stderr 不再包含非优雅 shutdown 错误；两条 watcher-path 警告仍出现。
- WSL 用显式 Cargo/Flutter PATH 与 `PUB_CACHE=/tmp/alula-pub-cache` 恢复本地 package config；Rust workspace tests 和 `build_core` 通过。`bash init.sh --fast` 的并行 Flutter suite 有一次 `REF-07-UNDO-01` 文本落错文件；该 fixture 单独复跑和整套 `flutter test --concurrency=1`（122 项）均通过。并行失败根因未定位，未修改该未暂存编辑器功能。
- 新的完整 1800.011 秒运行保存 150/150 次编辑，采集 1815 个一秒样本，峰值/稳定/最终 Private Bytes 798.17/657.82/232.52 MiB；稳定值仍比 500 MiB 目标高 157.82 MiB。6 个观察 PID 关闭+30秒退出，marker/hash 通过，临时 HOME/fixture 清除，前台恢复。详细原始证据见 `docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-rust-lsp-edit-30m-run3-20261029-030127104.*` 和 `...030253128.*`。
- P00.4 仍 blocked；缺口包括完整产品内存门、真实 DRM/WPE GBM、Microsoft 官方身份/许可和同服务 VS Code 对照。未启动 P01。GitNexus impact 显示 `WorkbenchPage` 与 `AlulaTitleBar` 均为 LOW，dispose 为 UNKNOWN（5 个接收者类型调用未解析）；已将原生事件边界列为图谱限制。

## 今日会话（2026-10-29 第五十八轮）：LSP 工作区优雅关闭与门禁复验

- 新增 ABI v5 工作区 LSP shutdown FFI/Dart 包装；tab close 发 didClose 但保留共享服务，workbench dispose 通知全部附着文档、等待 shutdown response 后发送 exit 并有界回收进程。Fake LSP trace 验证完整消息顺序与进程退出。
- `cargo fmt --check`、`cargo test --workspace`、Clippy、`build_core`、`flutter analyze --no-pub` 与完整 `bash init.sh` 全通过；Flutter 122 项全绿。
- 跟进发现工作区原有未提交 Ctrl+Click 监听会在 pointer-down 时同步 rebuild 并夺走 P00.3 Undo fixture 焦点；验证时改为帧后处理后 fixture 与完整门禁复绿。该 workbench hunk 与用户的其他既存修改保持未暂存，不纳入本次提交。
- 当前 fake-server 通过尚不等于真实 Windows rust-analyzer 复验；既有 Rust+RA 稳态内存 661.77 MiB，仍高于 500 MiB。真实 DRM WPE GBM、官方服务身份/许可、同服务 VS Code 与完整产品跨平台门仍阻塞，P00.4 继续 blocked、P01 不启动。
- GitNexus staged detect-changes 为 HIGH、9 条受影响流程；fresh graph 仍有 201/401 entry candidates 未排名、123 个 callees 跳过、2 次 walk 到预算。已在证据文件列出具体 flow 与文本搜索补核，不能把图谱当作完整影响证明。
- 详细记录：`docs/diagnostics/2026-10-29-p00/p00.4-lsp-graceful-shutdown.md`。

## 今日会话（2026-10-29 第五十七轮）：前台意外关闭后的完整重跑

- 按用户要求从隔离 HOME/fixture 启动到关闭清理，再完整重跑 Windows Release Rust+RA 编辑态流程；编辑 1800.015 秒，150/150 次保存成功，mem-probe 记录 1808 个一秒样本。Private Bytes 峰值/稳定/最终值为 683.19/661.77/665.47 MiB，稳定值仍超 500 MiB 目标 161.77 MiB。
- 32 个进程树快照、128 条 PID 记录；最后 40% 的主 rust-analyzer、Alula、launcher、proc-macro server Private Bytes 中位数为 429.00/226.94/3.05/2.88 MiB。marker 与 SHA-256 校验通过；关闭+30 秒 4 个观察 PID 均退出，临时 HOME/fixture 已清理，前台已恢复。两条 watcher-path 告警与非优雅 LSP shutdown 警告仍存在。
- 前一轮 VS Code 版本预检中，`Code.exe --version` 意外启动默认 profile 并初始化应用共享存储；已停止观察到的进程树，没有采样，也未检查或回滚共享存储。后续对照仍需独立前台授权，隔离启动参数正在加强。
- P00.4 仍 blocked；同服务 VS Code 对照、真实 DRM/WPE GBM、Microsoft 官方身份/许可和完整产品跨平台内存门未完成；P01 不启动。无 app/ 或 crates/ 产品代码改动。
- 证据：`docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-rust-lsp-edit-30m-run2-20261029-011542390.json`、`-activity.json`、`.md`、`-probe.stderr.log`、`p00.4-windows-alula-rust-lsp-summary.md`。

## 今日会话（2026-10-29 第五十六轮）：重跑 Rust+RA 编辑态完整验收

- 按用户要求从隔离 HOME/fixture 启动到关闭清理完整重跑 Windows Release Rust+RA 编辑态流程；1800.011 秒内 150/150 次保存，mem-probe 记录 1808 个一秒样本。Private Bytes 峰值/稳定/最终值 679.95/657.55/661.45 MiB，稳定值仍超 500 MiB 目标 157.55 MiB。
- 额外 32 个进程树快照、128 条 PID 级数据；编辑末 40% 的 13 组快照中位数为主 rust-analyzer 427.02 MiB、Alula 223.49 MiB、launcher 3.05 MiB、proc-macro server 2.86 MiB；匹配快照 Private Bytes 和的中位数 656.36 MiB。最终 marker 与 SHA-256 校验通过，关闭+30 秒 4 个观察 PID 均退出，临时 HOME/fixture 清除，前台恢复。两条 watcher-path 与非优雅 LSP shutdown 警告仍存在。
- PowerShell 5.1 解析通过；`cargo fmt --check`、完整 `PATH=/home/vegetable/.cargo/bin:/home/vegetable/develop/flutter/bin:$PATH bash init.sh`（Rust tests、Clippy、build_core、Flutter 122 项）与 `flutter analyze` 均通过。没有修改 app/ 或 crates/ 产品源代码。P00.4 仍 blocked；VS Code 对照、真实 DRM/WPE GBM、Microsoft 官方身份/许可和完整产品跨平台内存门未完成，P01 不启动。
- 证据：`docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-rust-lsp-edit-30m-run1-20261029-002641395.json`、`-activity.json`、`.md`、`p00.4-windows-alula-rust-lsp-summary.md`、`p00.4-windows-alula-rust-lsp-edit-interrupted-attempts.md`。

## 今日会话（2026-10-29 第五十五轮）：Rust+RA 编辑态进程内存归因

- 在此前三轮 30 分钟编辑验收样本外，额外完成一轮 1800 秒 Windows Release/隔离 HOME/rust-mini 编辑；150/150 次保存通过，mem-probe 1809 个一秒样本，Private Bytes 峰值/稳定/最终值为 853.50/660.29/664.63 MiB。稳定值仍超 500 MiB 预算 160.29 MiB。
- 诊断脚本现在在编辑起点、每 5 次保存及编辑结束时采集进程树明细，共 32 个快照/128 行。尾部 40% 的逐进程 Private Bytes 中位数：主 rust-analyzer 428.68 MiB、Alula 227.75 MiB、RA launcher 3.14 MiB、proc-macro server 2.88 MiB；这是单轮归因数据，不替代原三轮汇总。所有观察 PID 在关闭+30 秒后退出；两条 watcher-path 告警与非优雅 LSP shutdown 警告仍存在。
- Windows PowerShell 5.1 解析检查和实际脚本执行均通过。没有修改 app/ 或 crates/ 产品源代码。PATH=/home/vegetable/.cargo/bin:/home/vegetable/develop/flutter/bin:$PATH bash init.sh --fast 通过；默认 shell 的 PATH 不含 WSL 工具链，未带 PATH 的初次启动失败不作为产品失败。
- P00.4 仍 blocked；同服务 VS Code 前台对照的授权请求待回复，真实 DRM/WPE GBM 与 Microsoft 官方身份/许可也仍未解决。P01 不启动。原始证据见 docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-rust-lsp-edit-30m-run1-20261028-235126746-activity.json、同名 .json 与 .md。

## 今日会话（2026-10-28 第五十四轮）：Windows Rust+RA 三轮 30 分钟编辑采样

- 按 `docs/03` 的三次重复要求，在隔离 HOME 与 `rust-mini` fixture 上完成 Windows Release `--lsp-auto` 三轮 1,800 秒编辑，每轮150/150次保存，mem-probe 各记录1,808个一秒样本。峰值/稳定/末样本中位数为858.16/672.36/674.20 MiB；稳定态分别676.20/672.36/660.81 MiB，均超过500 MiB目标。每轮关闭+30秒后所有记录 PID 均退出。
- 两次 run3 重试分别在1654.929秒/137次编辑、250.845秒/20次编辑时保存校验失败，前台变为浏览器 HWND 267254；均无完整内存报告。失败截图显示 File 菜单仍打开，随后将正式保存路径改为 Ctrl+S，并在磁盘标记等待期间检查焦点；最终 run3 完成。两次失败证据与全部原始成功数据登记在 `p00.4-windows-alula-rust-lsp-edit-interrupted-attempts.md` 和 `p00.4-windows-alula-rust-lsp-summary.md`。
- 三轮都出现两条 rust-analyzer watcher-path 警告及 `client exited without proper shutdown sequence`。所有 PID 退出不证明 LSP 优雅关闭；稳定内存中位数仍比预算高172.36 MiB，P00.4 保持 blocked。真实 DRM/WPE GBM、官方服务身份/许可、VS Code 同服务对照及完整产品跨平台门仍未解决。没有修改产品源代码。
- WSL shell 本轮未自动继承 Rust/Flutter PATH，且 Windows Pub 生成态 package config 覆盖了 WSL 配置；设置 WSL 原生工具 PATH、使用 `/tmp/alula-pub-cache` 离线恢复后，`bash init.sh --fast` 与完整 `bash init.sh` 均通过；完整门禁包含 Rust workspace tests、Clippy、`build_core` 与 Flutter 122 项测试。GitNexus 在最终状态更新后重新建索引；detect-changes all/staged 均为 risk=low（0 条受影响流程）；all 范围也包含工作区未暂存的 app/、README 等修改。阶段提交只包含 P00.4 证据/状态与测试脚本，没有产品源码。process graph 仍截断：202 flows，396个入口候选有196个未排名、123个callee跳过、2次walk达预算；缺失流程不能视为无影响证明。

## 今日会话（2026-10-28 第五十三轮）：Windows Alula Rust+RA 第三次脚本编辑被抢焦点中断

- 使用已修正的前台守卫脚本重跑 run 1；约 732.329 秒、保存 61 次编辑后，前台从 Alula 切到 Windows Sandbox（HWND 12781196，`WindowsSandboxRemoteSession.exe`，PID 46760）。守卫立即停止继续输入。
- 脚本成功生成 abort JSON，记录每次已保存编辑、观察到的进程 PID、焦点句柄及中止原因。mem-probe 未留下完整内存报告；Alula/RA/mem-probe 进程树及临时 HOME/fixture 已由脚本清理。本轮不计入 docs/04 验收。
- 证据见 `docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-rust-lsp-edit-30m-run1-20261028-204339106-abort.json`、对应 `-probe.stderr.log` 与 `p00.4-windows-alula-rust-lsp-edit-interrupted-attempts.md`。P00.4 仍 blocked；下次需在 Windows 前台可持续留给 Alula 30 分钟的时段重跑。真实 DRM/WPE GBM 与官方服务身份/许可仍阻塞，不启动 P01。

## 今日会话（2026-10-28 第五十二轮）：Windows Alula Rust+RA 脚本编辑预检与中断记录

- 安装/验证所需 WSL 依赖已在此前完成；本轮没有修改产品源代码。Windows Release 在隔离 HOME 与临时 `rust-mini` 副本上通过 30 秒前台预检，6 次编辑保存；40 个一秒样本的 Private Bytes 峰值/稳定/结束为 653.84/645.64/608.53 MiB，稳定值超 500 MiB 目标。
- 两次正式编辑尝试约在 291 秒与 171 秒时切到 Windows File Explorer（HWND 201794，PID 8696）。焦点守卫停止输入并终止隔离进程树；两轮都没有完整 mem-probe 报告，故不作为验收轮次或产品失败证据。预检、运行脚本与中断详情见 `docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-rust-lsp-edit-preflight.md`、`p00.4-windows-alula-rust-lsp-edit-interrupted-attempts.md` 和 `p00.4-windows-alula-rust-lsp-edit-30m.ps1`。
- 脚本已修正编辑计时边界，并在中断时输出单独 abort JSON。需在 Windows 桌面可连续保持 Alula 前台 30 分钟的时段重跑；既有 Alula 前台测试授权有效。真实 DRM/WPE GBM、官方服务身份/许可、完整产品内存门仍阻塞；不启动 P01。

## 今日会话（2026-10-28 第五十一轮）：WSL依赖复验与 Rust LSP watcher 告警归因

- 在 WSL 复跑 `bash init.sh --fast`，Rust workspace tests、`build_core` 与 Flutter 122 项测试通过。完整门禁证据仍见 `docs/diagnostics/2026-10-28-p00/wsl-flutter-validation.md`。
- 独立 rust-analyzer 1.97.1 LSP 初始化复现两条 watcher path 告警；确认它们来自 rust-analyzer stderr。上游 notify-rs 错误条件指向缺失或非文件/目录的请求路径，但具体失败路径未知；经 WSL Windows-interop pipe 的 `RA_LOG=trace` 补充尝试未完成握手，已停止本次隔离进程。没有改产品代码。
- 详细记录：`docs/diagnostics/2026-10-28-p00/p00.4-windows-ra-notify-warning.md`。P00.4 仍 blocked/in-progress；真实 DRM WPE GBM、官方服务身份/许可、完整产品内存门和获批的前台编辑对照仍未解决，不启动 P01。

## 今日会话（2026-10-28 第四十一轮）：WSL 原生 Flutter 与全门禁复验

- 在 WSL ext4 安装 Flutter stable 3.47.8/Dart 3.13.7，并复用现有 pub mirror 缓存离线按锁文件解析依赖；未修改 pubspec 或 lockfile 内容。安装 clang、CMake、Ninja、pkg-config、GTK、libstdc++-12-dev、Epoxy、libsecret 与 GBM 桌面开发依赖；`flutter doctor -v` 的 Linux desktop toolchain 检查通过，Flutter bin 已加入 `.profile` 和 `.bashrc` PATH。
- `cargo fmt --check`、`cargo clippy --workspace --all-targets -- -D warnings`、app `flutter analyze --no-pub`、`flutter test --no-pub --concurrency=1` 与完整 `bash init.sh` 全部 EXIT=0；Rust tests、Clippy、build_core、Flutter 122 项和静态分析全绿。2,000,001 UTF-16 单元恢复夹具按预期记录旧行为。
- 初始并行 Flutter 单次出现 P00.3 Undo fixture 失败；该测试单独、完整串行和随后完整默认并行 `init.sh` 复跑均通过，根因未确认，未改产品代码或测试。验收记录：`docs/diagnostics/2026-10-28-p00/wsl-flutter-validation.md`。
- P00.4 仍 blocked/in-progress，真实 DRM WPE GBM、官方服务身份/许可和 docs/04 完整产品内存门未解决；P01 不启动。WSL Linux 桌面开发依赖已从临时 Ubuntu Aliyun apt 源安装；临时 apt 源配置文件已移除。

## 今日会话（2026-10-28 第四十二轮）：WSL Linux 桌面目标构建检查

- 在登录 shell 中运行 `bash scripts/build_core.sh` 成功；随后主应用 `app/` 的 `flutter build linux --release --no-pub` 在编译前返回 `No Linux desktop project configured`。Flutter host toolchain 已就绪，但主应用没有 Linux runner scaffold。
- `tools/web-engine-probe/` 自带 Linux runner，P00.4 WPE CI 已有独立 Linux 构建与回放证据；不把该探针证据当作主应用 Linux 构建通过。本轮不新增 `app/linux` 文件。
- 将主应用 Linux runner 缺失登记为后续跨平台阶段事项；P00.4 的真实 DRM WPE GBM、官方服务身份/许可、docs/04 产品内存门仍阻塞，P01 不启动。诊断见 `docs/diagnostics/2026-10-28-p00/wsl-flutter-validation.md`。

## 今日会话（2026-10-28 第四十三轮）：Windows 主应用 Release 构建验证

- Windows Git Bash 下 `bash scripts/build_core.sh` 成功；首次 `flutter build windows --release --no-pub` 因生成插件链接目录缺失而未生成 CMake 项目。
- 在 `app/` 执行 `flutter pub get --enforce-lockfile` 后，Windows Release build 通过，产物为 `app/build/windows/x64/runner/Release/alula_app.exe`。lockfile 相对 HEAD 仅有行尾差异、无语义内容变化。
- P00.4 的真实 DRM WPE GBM、官方服务身份/许可和 docs/04 完整产品内存门仍未解决；主应用 Linux runner 亦未配置，记录为后续跨平台阶段事项。没有修改产品源文件。

## 今日会话（2026-10-28 第五十轮）：VS Code 同服务对照前台安全预检

- 本机安装 VS Code 1.142.0 Stable，rust-analyzer 扩展 0.3.3089；隔离 profile 与扩展副本配置为使用和 Alula 相同的 rust-analyzer 1.97.1 二进制。PowerShell 采样脚本通过解析检查。
- PowerShell `WindowStyle Minimized` 和 WSH `SW_SHOWMINNOACTIVE` 两种最小化启动均触发前台守卫；每次都恢复之前的前台并终止隔离实例。进程查询确认没有使用临时 profile 的进程；临时 profile 和扩展副本已删除。没有开始内存采样，也没有访问登录、Sync 或 Marketplace 服务。该 VS Code 版本不是锁定的 Code-OSS 1.145.0-dev。
- 预检证据和脚本见 `docs/diagnostics/2026-10-28-p00/p00.4-vscode-rust-lsp-preflight.json`、`p00.4-vscode-rust-lsp-idle.ps1`。同服务 VS Code 采样与 30 分钟编辑仍需前台窗口；Alula 测试的用户授权请求尚待回复，VS Code 对照另需用户许可。P00.4 保持 blocked/in-progress。

## 今日会话（2026-10-28 第四十九轮）：Windows Rust + rust-analyzer 第三轮 10 分钟 idle 采样

- Windows Release/`rust-mini` fixture 与全新隔离 HOME 采样 600 秒，共 600 个一秒样本：Private Bytes 峰值/尾部稳定态/结束值为 608.72/589.09/591.70 MiB。三轮 idle 稳态中位数 589.09 MiB，仍比 500 MiB 目标高 89.09 MiB；未观察到显著 idle 增长或预算恢复。
- 启动重现两条 watcher path 告警。关闭+30秒后 Alula、两个 rust-analyzer 和 proc-macro server 四个 PID 均退出，隔离 HOME 已删除。用户确认暂无真实 DRM Linux 主机或获授权的 Microsoft 官方客户端身份；30 分钟编辑、同服务 VS Code 对照和完整产品服务场景仍未完成。
- 原始证据：`docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-rust-lsp-idle-run3.json`、`.md` 与 `p00.4-windows-alula-rust-lsp-summary.md`。P00.4 保持 blocked/in-progress，P01 不启动。

## 今日会话（2026-10-28 第四十八轮）：Windows Rust + rust-analyzer 第二轮 10 分钟 idle 采样

- Windows Release/`rust-mini` fixture 与全新隔离 HOME 采样 600 秒，共 600 个一秒样本：Private Bytes 峰值/尾部稳定态/结束值 603.16/589.27/590.77 MiB。稳定态比首轮 idle 高 0.18 MiB，仍超 500 MiB 目标 89.27 MiB；未观察到显著 idle 增长。启动仍有两条 watcher path 告警。
- 关闭+30秒后 Alula、两个 rust-analyzer 和 proc-macro server 的四个 PID 均退出，隔离 HOME 已删除。用户确认暂无真实 DRM Linux 主机或获授权的 Microsoft 官方客户端身份；此两项仍阻塞 P00.4。第三轮 idle 样本正在进行，30 分钟编辑和同服务 VS Code 对照未完成。
- 原始数据和范围限制见 `docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-rust-lsp-idle-run2.json`、`.md` 与 `p00.4-windows-alula-rust-lsp-summary.md`。P00.4 保持 blocked/in-progress，P01 不启动。

## 今日会话（2026-10-28 第四十七轮）：Windows Rust + rust-analyzer 10 分钟 idle 采样

- 同一 Windows Release/`rust-mini` fixture 使用隔离 HOME 做一轮 600 秒/1 秒间隔 idle 采样，共 600 个样本；Private Bytes 峰值 600.08 MiB、尾部 40% 中位数 589.09 MiB、结束 588.11 MiB。相较此前三轮 1 分钟样本稳定值中位数低 0.75 MiB，但仍比 500 MiB 预算高 89.09 MiB；未见明显空闲增长。
- 启动时重现两条 `notify error: Input watch path is neither a file nor a directory.` 告警。结束+30 秒后本轮四个记录 PID 均不存在，临时 HOME 已删除。无脚本化编辑；这是单轮 idle 子场景，不关闭 docs/04 完整内存门。
- 数据与限制见 `docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-rust-lsp-idle-10min.json`、同名 Markdown 和 `p00.4-windows-alula-rust-lsp-summary.md`。P00.4 仍 blocked/in-progress；真实 DRM WPE GBM、官方服务身份/许可、30 分钟编辑与完整对照仍未完成。

## 今日会话（2026-10-28 第四十六轮）：Windows Rust + rust-analyzer 内存三轮采样

- GitNexus CLI status 发现 analyzer runtime fingerprint 变化后，使用缓存 CLI 执行 `analyze --index-only`，索引刷新到当前 `c5f89a5`。过程图提取仍有候选入口与调用裁剪；本次用 `context` 和源码确认了 session restore 早于 autoFolder 的启动顺序。
- 前一轮 `--lsp-auto` 只有主进程的原因已确认：Windows profile session 有 workspace 字段且目录存在，恢复逻辑使自动 fixture 打开分支跳过。未输出原路径或文档内容；profile session LastWrite 早于探针。以隔离临时 HOME 重跑，rust-analyzer 和 proc-macro server 均稳定出现。
- 三轮 Windows Release 1 分钟采样的稳定 Private Bytes 为 589.84/593.10/588.58 MiB，中位数 589.84 MiB；峰值中位数 598.40 MiB。稳定态超过 docs/03 的 500 MiB Rust+RA 目标约 89.84 MiB。每轮有两条 watcher path 告警；末轮关闭+30 秒后 Alula/RA/proc-macro 进程均为 0。汇总及 raw reports：`docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-rust-lsp-summary.md` 与同目录 JSON/Markdown。
- WSL 跨 OS `.dart_tool` 修复后 `bash init.sh --fast` 通过 Rust tests、build_core、Flutter 122 项测试（跳过 Clippy），日志见 `p00.4-wsl-init-fast-recovery-2026-10-28.log`。P00.4 仍缺长时编辑/idle/对照、真实 DRM 和服务身份/许可证据；feat-022 仍 in-progress，P01 不启动。

## 今日会话（2026-10-28 第四十五轮）：WSL 门禁复跑与 Windows LSP 自动启动采样

- Windows `pub get` 曾将共享忽略文件 `app/.dart_tool/package_config.json` 写成 Windows Pub Cache URI，WSL 因此无法解析 `package:ffi`。用现有 WSL 离线缓存重建生成文件后，`bash init.sh --fast` 通过 Rust workspace tests、`build_core` 与 Flutter 122 项测试；该快速门跳过 Clippy，完整 Clippy/格式/analyze 证据仍见 `wsl-flutter-validation.md`；本次完整复跑输出保存于 `docs/diagnostics/2026-10-28-p00/p00.4-wsl-init-fast-recovery-2026-10-28.log`。
- Windows Release app 从 `app/` 工作目录以 `--lsp-auto` 启动并采样 45 秒。45/45 个进程树读数只有 `alula_app.exe`，未观察到 rust-analyzer 子进程；峰值/稳定态 Private Bytes 为 202.3/190.3 MiB。此为启动尝试，不是 Rust+LSP 样本，原因未确认。原始报告：`docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-lsp-autostart-attempt.json` 及同名 Markdown。
- P00.4 仍缺真实 DRM WPE GBM/DMABUF 主机证据、官方服务身份/许可和完整产品 1/10/30 分钟内存验收；feat-022 保持 in-progress，P01 不启动。

## 今日会话（2026-10-28 第四十四轮）：Windows 空工作台三轮内存样本

- Windows Release app（HEAD `2235402` 加预先存在的 unstaged app 修改）用 Windows `mem-probe` 连续冷启动采样三次，每次 45 秒、间隔 1 秒，每份报告 45 个样本，进程树只有 `alula_app.exe`。
- Peak Private Bytes：202.60/201.72/200.63 MiB；稳态/结束 Private Bytes：188.38/187.46/186.38 MiB；中位数分别为 201.72/187.46 MiB。第三轮结束后等待 30 秒，`Get-Process alula_app` 返回 0。与旧空窗口样本相近，不作版本回归结论。
- 该采样没有 workspace、LSP、terminal、WebView 或编辑负载，不覆盖 docs/04 的长时多场景完整产品门。原始报告和限制见 `docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-current-empty-summary.md`。P00.4 仍 blocked/in-progress，P01 不启动。

## 今日会话（2026-10-28 第四十轮）：Safari Web Inspector 页面附着验证

- macOS 15 Actions run 40647161201 在 HEAD `5da053b` 通过 probe analyze/test、Release build、Web Archive 保存/重载和 Safari Web Inspector 页面级附着。日志显示 Web Inspector 窗口标题匹配 `webarchive.invalid — p00.4-web-probe.webarchive`；附着截图可见 `html > body data-ready="true"`。
- 693-byte Web Archive SHA-256 为 `f99cd79f8edec867378f55eeceb2182627ca14904e60099119feaf094afc9a0d`。该 probe 的单轮 footprint 不等于 docs/04 完整产品进程树、多场景和 1/10/30 分钟验收；Web Archive/Inspector 也不证明 CDP/MHTML 兼容。
- WSL 已安装 libgbm 并完成 WSLg faux DRM 探针：card0 GBM dma-buf 导出成功，render node 分配失败；EGL/GLES renderer 为 llvmpipe。WPE 硬件 GBM 仍未验证。Rust 格式、workspace tests、clippy 与 editor-core release build 已通过。
- 更新 docs/03、P00.4 ADR、探针 README、feature_list.json、本进度和 session handoff；P00.4 仍 blocked/in-progress，P01 不启动。原始 runner 文件与汇总在 `docs/diagnostics/2026-10-28-p00/p00.4-web-macos-run-40647161201/`。

## 今日会话（2026-10-28 第三十九轮）：WSL GBM/EGL 依赖与能力复测

- WSL 安装 `libgbm-dev=25.2.8-0ubuntu0.24.04.4`，将当前账号加入 `video` 与 `render`；以刷新后的 uid 1000 进程复测，card0 dumb buffer/dma-buf 成功，render node dumb-buffer ioctl 仍失败。
- 在 GBM EGL display 上创建 surfaceless GLES2 context 后，renderer 报告 `llvmpipe (LLVM 20.1.2, 256 bits)`；无 GLES2 pbuffer config，确认该 WSLg 路径是软件渲染，不能替代真实 DRM 主机的 WPE GBM/DMABUF 验收。未运行 WPE，也未改 feature 状态。
- WSL Rust fmt、workspace tests、clippy 与 `editor-core` release build 再次全部通过。完整版 Flutter Linux SDK 下载约 1.58 GB，当前镜像连接慢且被 Ubuntu X11 header 下载阻塞，因此没有安装；Flutter 完整门禁继续使用已通过的 Windows Git Bash runner。
- 证据：`docs/diagnostics/2026-10-28-p00/wslg-gbm-egl-evidence.json`、`docs/diagnostics/2026-10-28-p00/wsl-rust-validation.md`。P00.4 仍 blocked，feat-022/P00 仍 in-progress，P01 不启动。

## 今日会话（2026-10-28 第三十八轮）：WSL Rust 工具链与跨 runner 门禁复验

- WSL 安装 rustup stable 1.99.1、rustfmt 与 clippy；rustup-init SHA-256 对照官方 checksum 文件通过。WSL `cargo fmt --check`、`cargo test --workspace --locked`、`cargo clippy --workspace --all-targets --locked -- -D warnings`、`cargo build -p editor-core --release --locked` 全部 EXIT=0。
- Windows Git Bash 使用现成 Flutter 3.47.8 复验 `cargo fmt --check && bash init.sh` 与 `(cd app && flutter analyze)`，全部 EXIT=0；Rust tests、clippy、build_core、Flutter 122 项和 analyze 全绿。P00.3 超 2M UTF-16 恢复夹具再次观测到旧磁盘内容恢复，仍是 characterization，不是修复。
- WSL 已有 GCC/make/pkg-config；未安装 apt GUI 开发包，也未下载 1.58GB Linux Flutter SDK。Flutter gate继续走已授权的 Windows Git Bash runner。证据：`docs/diagnostics/2026-10-28-p00/wsl-rust-validation.md`。
- 没有改产品代码或 feature 状态；P00.4 仍 blocked，feat-022/P00 仍 in-progress，P01 不启动。剩余 gate 见本文件 Current State 与 `docs/03`。

## 今日会话（2026-10-28 第三十七轮）：macOS 与 Linux WPE CI 回放完成

- macOS 15 Actions run 40616364760 在 HEAD `51fe0cd` 通过探针 analyze/test、Release build 与 WKWebView Web Archive 保存/同一视图重载；693 bytes，title/marker 正确且 `archiveParsed=true`。Safari Web Inspector 人工附着与 docs/04 产品内存验收仍未完成。
- Linux Debian sid WPE run 40616364735 在同一 HEAD 通过依赖核验、analyze/test、Release build、memory sampler build 和默认 WebKit sandbox MHTML 回放。使用 WPE 2.52.6 + WPEBackend-FDO 1.16.1，sandbox-disable/GBM-disable 变量均 unset、观察到 bwrap；容器 security label 为 unconfined 且 capabilities 增强，故不代表产品安全 profile。页面 title/marker 正确；初始截图第4次/465ms、MHTML 第1次/50ms，archive 2,587 bytes。销毁+30s进程树 private 406.8 MiB（比创建 WebView 前高117.4 MiB），WebProcess 与 bwrap 退出但 NetworkProcess 留存。单轮探针样本不证明 leak，也不满足 docs/04。
- root CI run 40616364863 全绿。最新 run artifacts、流程、页面截图、归档和内存采样归档于 `p00.4-web-linux-run-40616364735/` 与 `p00.4-web-macos-run-40616364760/`；之前 Linux 包、namespace、network、mount sandbox 失败记录也保留。P00.4/feat-022 仍 blocked/in-progress：GBM、Safari Inspector、官方服务身份/许可、完整产品内存验收仍开放；P01–P15 不启动。
- 本环境启动门禁 `bash init.sh --fast` 因 WSL 无 Cargo 且挂载的 Windows Flutter shell 有 CRLF 失败；Windows Git Bash 2026-10-28 完整门禁 EXIT=0 的日志仍是跨平台门禁证据。本轮只更新诊断和状态文档，没有产品代码变更。

## 今日会话（2026-10-28 第三十六轮）：macOS Web Archive 与 Linux WPE CI

- macOS 15 Actions run 40614141265（commit d47543d）通过探针 analyze、tests、Release build 与 Web Archive replay。693-byte Web Archive 在同一 WKWebView 重载成功，title=`Alula Web Probe`、marker=true、`archiveParsed=true`，截图没有 bplist 原始内容；证据目录为 `docs/diagnostics/2026-10-27-p00/p00.4-web-macos-run-40614141265/`。这不证明 CDP/MHTML 等价，也未完成 Safari Web Inspector 手动附着或 docs/04 产品内存验收。
- Linux WPE run 40614141322 的包版本检查通过，但 Release configure 发现插件需要的 `wpebackend-fdo-1.0` pkg-config 模块未安装（既无 WPEPlatform 也无 FDO fallback），未进入编译。工作流现补 `libwpebackend-fdo-1.0-dev` 并把后端版本写入环境证据；`bash -n`、`git diff --check` 通过，提交/推送 `e853999`。重跑 40614659876 正在执行。
- CI run 40614141412 的 Linux/Windows Rust fmt、clippy、tests 与 Flutter analyze/test 均通过。P00.4 仍 blocked：Linux WPE 重跑、GBM/DMABUF、Safari Inspector、官方服务身份/许可和 docs/04 仍未关闭；P01 不启动。

## 今日会话（2026-10-28 第三十五轮）：复核官方服务策略

- 重新打开 Microsoft VS Code FAQ 与 Settings Sync 官方页面，确认 Code-OSS fork 无权访问 Visual Studio Marketplace；内置 Settings Sync 使用专用服务且不支持自定义后端。没有登录、调用 Marketplace 或写入远程服务。
- 将当前来源与结论登记到 `p00.4-services-evidence.json` 的 `currentPolicyCheck` 并更新 `p00.4-services-adr.md`。服务端许可/身份仍是 P00.4 外部阻塞；macOS workflow 的推送授权仍待用户答复，P01 不启动。

## 今日会话（2026-10-28 第三十四轮）：WPE 同进程十轮内存采样

- 通过 `/mnt/c/Program Files/Git/bin/bash.exe` 从 WSL 调用 Windows Git Bash 执行 `bash init.sh --fast`，EXIT=0：Rust workspace tests、`build_core` 与 Flutter 122 项测试通过；用户 Git Bash `.bashrc` 有 BOM 告警，不影响命令。当前 WSL 直接调用仍因缺 Cargo/Windows Flutter CRLF 失败。
- 在 UID 1000、WPE 2.52.6、Xvfb/software GL、sandbox/GBM disabled 的独立 Release 探针进程里，无截图/MHTML/Inspector 连续创建/销毁 10 次，每次销毁+30s采样。进程树基线 177.57/231.80 MiB private/PSS，第十轮 258.77/315.43 MiB（+81.20/+83.63）；增量在父进程，NetworkProcess PSS 基本稳定，WPEWebProcess 销毁后退出。
- 父进程 `[heap]`、匿名映射、WPE WebKit 文件映射 PSS 分别比基线高 35.17/32.48/14.66 MiB（文件页增量为 15,008 KiB）。周期内有回落，不能由映射数据证明 live leak 或具体 owner；单轮软件渲染探针不满足 docs/04。原始证据和限制见 `p00.4-linux-wpe-multi-cycle-evidence.json` 与 `p00.4-linux-wpe-multi-cycle-run1/`。P00.4 继续 blocked。

## 今日会话（2026-10-28 第三十三轮）：WPE 父进程 smaps 映射 follow-up

- 在 UID 1000 的 Debian 12/WPE 2.52.6/Xvfb 软件 GL 容器中，以无截图自动模式复跑一轮并保存 baseline、WebView open、destroy、destroy+30s 的进程 `smaps`/maps/status；无 MHTML、截图或 Inspector 操作。
- 本轮进程树 private/PSS 从 WebView 前 177.46/231.68 MiB 到销毁+30s 218.36/274.91 MiB，增量 40.90/43.23 MiB；WPEWebProcess 退出，WPENetworkProcess 留存。
- 父进程最大映射组增量为 `[heap]` +21.11 MiB PSS、WPE WebKit 文件映射 +14.62 MiB PSS（主要 private-clean）、匿名映射合计 +7.30 MiB PSS。映射数据不能区分 live object、malloc 保留页或具体库/图形 owner，不构成 leak 证明；sandbox 与 GBM 关闭，单轮探针，不满足 docs/04。
- 原始压缩快照、采集脚本和汇总见 `p00.4-linux-wpe-parent-smaps-run1/`、`p00.4-linux-wpe-parent-smaps-evidence.json` 与更新后的 `p00.4-web-adr.md`。P00.4 继续 blocked，P01 不启动。

## 今日会话（2026-10-28 第三十二轮）：WPE 父进程 heaptrack 探查

- 探针增加 `P00_4_WEB_NO_CAPTURE=1` 路径：复用 WebView 加载和 dispose，但跳过截图、MHTML 与 Inspector 操作。`flutter analyze --no-pub`、`flutter test --no-pub`、Linux Release build 均通过；普通 analyze 因容器 pub.dev 凭据拒绝而无法做联网解析。
- Heaptrack 1.4.0 插桩下一轮销毁+30s父进程比同轮基线多 98.2 MiB Private Bytes / 101.7 MiB PSS；插桩会改变内存行为，不能和此前未插桩的约 41 MiB直接对比。WPEWebProcess退出、NetworkProcess留存。
- 峰值栈有 51.25 MiB 经过 `InAppWebView::InitWpeBackend` 进入 software `swrast_dri.so`，另有 93.52 MiB 调用点未解析。峰值并非销毁后保留量；SIGTERM后的 154.50 MiB `leaked` 报告也不视作泄漏证据。仍未解释原始约40 MiB父进程残留，P00.4保持blocked。
- 证据：`p00.4-linux-wpe-parent-heaptrack-evidence.json`、`p00.4-linux-wpe-parent-heaptrack-run3/`、更新后的 `p00.4-web-adr.md`。

## 今日会话（2026-10-28 第三十一轮）：WPE 无截图生命周期三轮复验

- WPE 2.52.6 source-built Flutter Release 探针在 Debian 12/Xvfb/software GL 下，再以独立进程手动 F5 创建/销毁三次；没有调用截图、MHTML 或 Inspector，三份 TMPDIR 均为空。
- 三轮 WebView 前 Private Bytes/PSS 中位数为 177.1/231.5 MiB；打开时 287.9/390.1 MiB；销毁+30s为 217.3/274.0 MiB。相对基线的三轮增量中位数 40.2/42.5 MiB。
- 三轮销毁后 WPEWebProcess 均退出、WPENetworkProcess 均留存；父进程私有/PSS 内存增量中位数 41.2/42.3 MiB，来源仍未归因。容器元数据采集最初漏设 PKG_CONFIG_PATH，随后确认同一 /work/install 前缀为 WPE 2.52.6；初始 environment.txt 已补全。
- 这是探针级短时周期，不等同 docs/04 的 10min idle、30min edit、工作区关闭场景；P00.4 仍 blocked。汇总及原始文件见 p00.4-linux-wpe-memory-repeat-evidence.json 与 p00.4-linux-wpe-manual-f5-repeat-run1/ 至 run3/。

## 今日会话（2026-10-28 第三十轮）：Windows Git Bash 完整门禁复验

- WSL 启动门禁 bash init.sh --fast 因没有 cargo，且 /mnt/e/flutter/bin/internal/shared.sh 的 CRLF 行在 Bash 报错而失败；这是 runner 限制，不是产品代码失败。
- 按用户选定的 Windows Git Bash 执行 cargo fmt --check、bash init.sh 与 app 下单独 flutter analyze，全部退出 0。Rust workspace tests、Clippy -D warnings、build_core、Flutter 122 项测试全部通过；恢复 P00.3 2,000,001 UTF-16 fixture 耗时 2:11。
- 完整终端输出：docs/diagnostics/2026-10-27-p00/p00-full-validation-windows-gitbash-2026-10-28.log。Git Bash 的用户 .bashrc 有 UTF-16 编码告警，不影响命令结果。没有改产品代码。
- P00.4 外部阻塞未变化；macOS workflow 推送/运行授权问题已单独发给用户，未推送。

## 今日会话（2026-10-28 第二十九轮）：P00.3 fixture 复跑与 WPE 生命周期内存 follow-up

- 按用户选择使用 Windows Git Bash 重放 P00.3 build_core、Flutter risk fixtures 与两个 Rust integration tests，四项命令均通过；超大恢复 fixture 耗时 2 分 10 秒，所有结构化输出与已登记现状一致。完整日志：docs/diagnostics/2026-10-27-p00/p00.3-windows-gitbash-rerun-2026-10-28.log。
- WPE 2.52.6 source-built Flutter Release 探针在 Debian 12/Xvfb/software GL 下连续三轮自动执行页面/MHTML/销毁周期。销毁+30s Private Bytes/PSS 中位数 249.7/308.4 MiB，相对空 WebView 基线高 72.2/76.7 MiB。
- 为排除截图影响，另外手动 F5 创建/销毁一次，不执行 screenshot/MHTML，独立 TMPDIR 为空。WebProcess 退出、NetworkProcess 留存；销毁+30s进程树 218.7 MiB Private Bytes / 275.5 MiB PSS，比空载高 41.9/44.2 MiB，额外内存主要计在 Flutter 父进程，但未归因到具体分配者。
- 结果是探针级探索样本，不满足 docs/04 三轮长时/编辑/关闭要求，不能作为产品预算结论；P00.4 继续 blocked，P01 不启动。总结及原始记录见 p00.4-linux-wpe-memory-repeat-evidence.json 和三个自动/手动 run 目录；ADR 已更新。

## 今日会话（2026-10-28 第二十八轮）：WPE Inspector protocol command session

- WPE 2.52.6 Remote Inspector WebSocket endpoint 握手返回 101，收到 multiplexing page target，并通过 Target.sendMessageToTarget 成功执行 Runtime.enable 与只读 Runtime.evaluate；返回 title=Alula Web Probe、marker=true。
- 初次将 Page/Runtime 直接发送到外层 multiplexing endpoint 得到 domain-not-found；改用 WPE 的 Target.sendMessageToTarget 嵌套路由后命令成功。此为 Web Inspector Protocol，不是 CDP。
- 探针完成 initial-loaded、MHTML reload 与 WebView destroy。运行显式禁用了 sandbox 与 GBM，UID 1000、Xvfb、WPE 2.52.6 source build；不代表产品集成、默认安全配置、硬件渲染或 docs/04 内存 DoD。
- 证据：docs/diagnostics/2026-10-27-p00/p00.4-linux-wpe-inspector-protocol-evidence.json 与 p00.4-linux-wpe-2.52.6-inspector-protocol-run/。P00.4 继续 blocked，P01 not-started。

## 今日会话（2026-10-28 第二十七轮）：macOS workflow dispatch 预检

- 复核当前分支 codex/vscode-parity-p00（HEAD 3b3c7f0）在 origin 上没有对应 branch ref；GitHub workflow 列表仅返回 CI 与 Release；查询 p00-web-engine-macos.yml 明确返回默认分支 404。
- 没有推送，也没有尝试 dispatch；因此没有 macOS runner 或平台通过证据。待用户授权后才可发布当前分支以运行已准备的 macOS workflow。记录在 docs/diagnostics/2026-10-27-p00/p00.4-macos-dispatch-preflight.json。
- P00.4 继续 blocked，feat-022/P00 in-progress，P01 not-started；未改产品代码。

## 今日会话（2026-10-28 第二十六轮）：WSLg Wayland EGL follow-up

- 按启动门禁复核，`bash init.sh --fast` 在当前 WSL shell 因 Cargo 不存在、Windows Flutter 脚本 CRLF 而失败；不代表产品门禁结果。Windows Git Bash 的完整 DoD 与 P00.3 fixture 通过记录保持有效。
- WPE Debian 12 容器以 UID 1000、render supplementary group、`/dev/dxg` 和 `/dev/dri/renderD128` 访问 WSLg Wayland socket；`wl_display_connect` 成功，但 Mesa `eglInitialize` 返回 `EGL_NOT_INITIALIZED`，没有 GLES2 config，因此没有运行 WebView。
- 临时镜像已删除，原 WPE 容器仍运行；没有产品代码改动。WPE GBM 仍未验证，P00.4 blocked。证据：`p00.4-linux-wpe-wslg-d3d12-run/wayland-egl.log` 与 `p00.4-wslg-egl-evidence.json`。

## 今日会话（2026-10-28 第二十五轮）：WSLg D3D12 EGL 与 GBM capability check

- 用户选择 Windows Git Bash 作为 P00.3 runner；四个 fixture 的重放及门禁已记在第二十三轮，当前 WSL shell 没有 `cmd.exe`，本轮没有声称重新运行。
- WSLg EGL/GLES surfaceless probe 在 `GALLIUM_DRIVER=d3d12` 下报告 `D3D12 (AMD Radeon(TM) Graphics)`，context 创建成功。
- 临时 Debian Bookworm 容器可打开 `/dev/dri/renderD128`，但 `gbm_create_device` 返回 null；容器缺 Mesa DRI drivers，结果对 WPE GBM 不确定。
- WPE 2.52.6 容器快照映射 `/dev/dxg` 和 DRM nodes、启用 GBM 并关闭软件 GL 后，Flutter EGL context 失败、WPEWebProcess crash；Xvfb 与容器 X11 `:0` 都未能初始化 EGL。随后 Wayland socket 可连接，但容器 Mesa 的 `eglInitialize` 仍失败且无 GLES2 config。随后直接调用 WPE 镜像 `gbm_create_device` 也返回 null、没有分配 GBM buffer。未到 initial-loaded，也没有 GBM buffer/frame，不能作 WPE 支持结论。
- 未改产品代码或原 WPE 容器；临时镜像已删除，P00.4 仍 blocked。日志与环境见 `p00.4-linux-wpe-wslg-d3d12-run/`、`p00.4-wslg-egl-evidence.json`。

## 今日会话（2026-10-28 第二十四轮）：验证 WPE Remote Inspector HTTP endpoint

- WPE 2.52.6 source build 的 Flutter Linux/WPE Release 探针配置 loopback `WEBKIT_INSPECTOR_HTTP_SERVER=127.0.0.1:9231`；服务 target list 列出 `Alula Web Probe` 和 `/socket/1/1/WebPage`，`/Main.html` HTTP 200、2,680 bytes。同一回放 initial/MHTML 页面 marker、截图、销毁与 30 秒回收采样通过，退出码 0。
- 确认 pinned Linux 插件 capability JSON 仍报 `callDevToolsProtocolMethod=false`、`isInspectable=false`；但 Linux 原生插件源码默认 `enableDeveloperExtras=true` 并调用 WPE setting setter。因此把“Inspector 不支持”改为“WPE Remote Inspector endpoint/target/frontend bootstrap 已验证，命令会话未验证”；CDP 仍不支持。
- 此次 Inspector 回放显式禁用 WebKit sandbox 与 GBM，仍为 Xvfb/source-built WPE 诊断结果；没有 Inspector UI attach 或 protocol command response，不能推断安全发布或 CDP 等价。证据见 `p00.4-linux-wpe-inspector-evidence.json`、`p00.4-linux-wpe-2.52.6-inspector-http-run/` 和 ADR。
- 启动门禁 Windows Git Bash `bash init.sh --fast` EXIT=0；Flutter 122 项测试通过。未改产品 `app/` 或 `crates/`，P00.4 仍 blocked，feat-022 in-progress，P01 not-started。

## 今日会话（2026-10-28 第二十三轮）：重放 P00.3 并处理 WPE 首帧截图时序

- 按用户选择的 Windows Git Bash 与 Flutter wrapper，重跑 `build_core.sh`、P00.3 Flutter characterization test、workspace-close 与 slow-completion Rust tests；全部退出码 0，四个 JSON 观测与既有证据一致。2,000,001 UTF-16 单元恢复夹具约 2 分 03 秒完成。
- 提交前根目录门禁：Windows Git Bash `cargo fmt --check`、完整 `bash init.sh`、单独 `app/ flutter analyze` 全部退出码 0；Rust workspace tests、Clippy、core build 与 Flutter 122 项测试均通过。
- GitNexus 增量索引后 `detect-changes --scope all` risk=medium（91 files/14 symbols/1 flow，包含既有 workbench 改动），staged risk=medium（62 files/4 symbols/1 flow，唯一 flow 为 Build→`_hasProbeHeadingPixel` 探针截图路径）；无 HIGH/CRITICAL。流程索引警告 190 个候选入口未入选、123 个 callee 因预算跳过、2 次 walk 达预算，不能视为无影响证明。
- 解码旧默认-sandbox 首屏 PNG：1280×572 RGBA 的 732,160 像素全部为透明零值；DOM marker 虽存在，但没有页面像素。检查 pinned Linux plugin 发现 `takeScreenshot()` 只复制当前 buffer，不等待 WPE frame callback。
- 独立探针现在在 DOM 查询前轮询截图，最多 30 次、间隔 100ms，要求检测页面标题的蓝色像素。Flutter analyze、test 与 Linux Release build 通过。三次 UID 1000 默认-sandbox 新冷启动均生成可见初始页/MHTML 截图；两次预备 alpha-check 首试通过，最终 heading-check 版本第 2 次（199ms）通过。运行仍将 sandbox-disable 变量保持 unset、GBM disabled，并观察到 bwrap 与 WPEWebProcess。
- 新证据目录为 `p00.4-linux-wpe-2.52.6-frame-poll-run/`、`run2/`、`run3/`；判定为探针级捕获时序处理，不是产品帧同步修复。P00.4 仍因 macOS、官方服务身份/许可、GBM、发行包 API、Linux CDP/Inspector 等未决项 blocked；feat-022 继续 in-progress，P01 not-started。
- 未改 `app/`、`crates/` 或产品依赖；仅改独立 WPE 诊断探针及 P00.4 报告/状态文档。工作区原有的 harness、workbench、docs09 与 parity-plan 改动仍未暂存。

## 今日会话（2026-10-28 第二十二轮）：WPE 默认 sandbox 受限容器复核

- 按启动流程用 Windows Git Bash 重跑 `bash init.sh --fast`，退出码 0；Rust workspace 测试、核心库构建与 Flutter 122 项测试通过。GitNexus 在本次提交前状态 fresh。
- 标准临时容器的 seccomp profile 阻止 bwrap 创建 user namespace。为判断是否是 WPE 本身不支持 sandbox，使用本地一次性镜像启动验证容器，运行参数为 `--cap-add SYS_ADMIN --security-opt seccomp=unconfined`，探针进程仍为 UID/GID 1000；`unshare --user --map-root-user true` 退出 0。
- 在该容器中保持 `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS` unset、设置 `WEBKIT_DMABUF_RENDERER_DISABLE_GBM=1` 后，探针完整经过 initial-loaded、mhtml-loaded、webview-destroyed 与销毁后 30 秒采样，退出码 0。WebView 打开时进程树含两个 `bwrap`、`WPEWebProcess` 和 `WPENetworkProcess`；销毁后 WPEWebProcess 退出，NetworkProcess 留存。
- 首次页面 JSON marker 为 true，但 PNG 只有背景色；MHTML 重载页面的 JSON marker 与截图正常。500ms、2 秒等待都没能修好干净配置的首帧截图，因此撤回了探针中的临时延迟变更，产品/探针源码最终无改动。GBM 硬件渲染仍未验证。
- 默认 sandbox 运行证据在 `p00.4-linux-wpe-2.52.6-default-sandbox-run/`；单轮 Private/Working Set/PSS MiB：基线 227.0/341.9/281.5，view open 314.9/600.7/422.8，MHTML 332.8/622.2/441.4，destroy 255.3/382.5/315.5，destroy+30s 258.5/382.1/317.3。该轮不是 docs/04 三轮与长时产品验收。
- WPE 默认 sandbox launcher 已在具备额外 namespace 能力的隔离 Docker 环境运行；这不证明常规 Docker/GitHub runner/生产主机可用。首帧截图、GBM 硬件、macOS 与官方服务仍是 P00.4 阻塞；feat-022/P00 继续 in-progress，P01 继续 not-started。
- 本轮没有保留探针源代码改动；只更新 P00.4 ADR/证据、README、状态索引与会话交接。提交前需重新 analyze GitNexus、对暂存集跑 detect-changes，并验证 MHTML hash 与 JSON。

## 今日会话（2026-10-28 第二十一轮）：WPE 2.52.6 源码构建与回放

- 使用官方 WPE WebKit 2.52.6 release archive（SHA-256 `b2bafef2751625b7fdf530f230ff0f542ff0eeba3590c3a989d931b2a55c858e`）在临时 Debian Bookworm Docker 容器源码构建；WPEPlatform、Headless、MHTML 均开启，9,421 个 Ninja 步骤与 install 均成功。编译有 15 条 `-Wrestrict`、7 条 `-Wuse-after-free` 警告。构建参数、日志和源码限制见 `p00.4-linux-wpe-2.52.6-build.md`。
- Flutter 3.47.8 / Dart 3.13.7 的 probe `pub get`、`analyze`、1 项 test、Linux Release build 均通过；Rust 1.90.0 下 mem-probe release build 通过。Clang14 的 CMake 探测需设置自定义 WPE `LDFLAGS`；插件的 `-Wno-deprecated-literal-operator` 在本机 Clang14 未知，临时 `CXXFLAGS` 只屏蔽该选项诊断，没有改插件/产品源。
- 默认 WebKit sandbox 因容器禁止非特权 user namespace 无法启动；禁用 sandbox 后，GBM/DMA-BUF 路径不产出 CPU screenshot；设置 `WEBKIT_DMABUF_RENDERER_DISABLE_GBM=1` 后，初始页面、MHTML 重载、PNG、销毁和 30 秒内存采样全部通过。最终回放同时设 `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1`，只作为隔离软件渲染实验，不证明默认安全或硬件渲染。
- 单轮 Private/Working Set/PSS MiB：空 WebView 176.9/290.7/230.9；WebView open 282.5/553.9/384.8；MHTML reload 289.5/564.4/392.5；destroy 219.8/342.3/278.2；destroy+30s 219.3/341.8/277.7。WPEWebProcess 已退出但 NetworkProcess 留存；不满足 docs/04 多轮与长时协议。页面 JSON 仍记录 Linux CDP/Inspector 不支持。
- 更新 smoke runner，使 source-built WPE 不在 dpkg 中时仍可记录 pkg-config 版本，并将 WebKit 安全/GBM overrides 写入 environment.txt。GitNexus 对脚本文件的 impact 为 UNKNOWN；文本检索确认仅 README、Linux Actions workflow 和证据 JSON 引用该脚本。P00.4/feat-022 保持 blocked/in-progress，P01 仍 not-started。未修改 `app/`、`crates/` 或产品依赖。
- 本轮启动时 Windows Git Bash `bash init.sh --fast` 完整退出码 0；Rust/Dart 全门禁与 122 项 Flutter 测试通过。新增变更只涉及探针脚本和文档/实验数据；提交前仍需跑 Bash 语法、JSON/证据校验和 GitNexus graph change analysis。

## 今日会话（2026-10-28 第二十轮）：WPE API 兼容边界复核

- 官方 WPE 2.54 迁移说明确认 `WPE_SETTING_DISABLE_ANIMATIONS` 已替换为 `WPE_SETTING_REDUCED_MOTION`；pub.dev 当前只有 `flutter_inappwebview_linux 0.1.0-beta.1`，仍引用旧名。
- 测试 Debian Trixie `libwpewebkit-2.0-dev=2.48.3-1` 与插件声明的 WPEBackend-FDO legacy fallback。该包没有 WPEPlatform pkg-config/header；为继续检查 FDO 分支，在临时容器补空 include 目录后，干净 `flutter clean` + Release build 仍因 `webkit_web_view_get_theme_color` 未声明失败。容器为 Bookworm 衍生/混合 Debian，不是干净 Trixie；无 WPE runtime 证据。细节见 `p00.4-linux-wpe-trixie-compat.log`。
- 未加编译宏、未改插件源码、未把临时目录 workaround 写入仓库。WPE 2.53.92 是官方开发版，需单独评估是否值得从源码构建；P00.4 仍 blocked，P01 仍 not-started。
- GitNexus 在提交 `5d8b795` 后重建索引：201 flows；188 个入口候选未进入排名、123 个 callee 因分支预算跳过、2 次 walk 达预算；缺失 flow 不能视为无影响。
- 提交前 GitNexus `detect-changes --scope all` risk=low（37 files/33 symbols/0 processes），staged risk=low（8 files/17 symbols/0 processes）。

## 今日会话（2026-10-28 第十九轮）：Flutter Linux/WPE 构建尝试与阻塞

- 本地临时 Debian sid 包环境下，Flutter 3.47.8 / Dart 3.13.7 的 probe `flutter analyze` 与 `flutter test` 通过；Release 构建失败在 `flutter_inappwebview_linux 0.1.0-beta.1`，`in_app_webview_settings.cc:405` 引用了 WPE 2.54.2 头文件不存在的 `WPE_SETTING_DISABLE_ANIMATIONS`（头文件提供 `WPE_SETTING_REDUCED_MOTION`）。没有修改插件源码或加兼容宏。
- 首次 CMake 配置发现遗漏 `libsecret-1-dev`，已补到 `.github/workflows/p00-web-engine-linux.yml` 和 probe README。完整环境、命令结果与编译错误见 `p00.4-linux-wpe-build.log`；更新静态证据 JSON 与 Web ADR。Xvfb runtime replay 未运行，无 WPE MHTML、截图和内存样本。
- 本地容器从缓存的 Bookworm 衍生镜像升级 sid 包，`/etc/os-release` 报 `forky/sid`，不是干净的 `debian:sid` workflow 环境；包版本已在证据中记录。GitNexus 索引在 Flutter 生成文件后重建为 up-to-date；`WebEngineProbePage` impact 为 LOW，1 个直接调用、0 流程；CMake 文件 impact 为 UNKNOWN，文本确认本轮只补构建依赖。
- 提交前 GitNexus `detect-changes --scope all` 为 risk=low（38 files/34 symbols/0 affected processes），staged 为 risk=low（9 files/18 symbols/0 affected processes）。索引仍有流程截断：186 flows、208 个入口候选未纳入、98 个 callee 被跳过、2 次 walk 达预算；不把缺失 flow 当作无影响。
- P00.4 仍 blocked：Mac、Microsoft 官方服务身份/许可未解决，Linux WPE 在该插件/API 组合上无法构建；P01 仍 not-started。没有修改 `app/` 或 `crates/`。
- 收尾门禁：Windows Git Bash `bash init.sh --fast` 与完整 `bash init.sh` 均通过；`cargo fmt --check`、`flutter analyze` 也通过。完整脚本覆盖 Rust 测试、Clippy、核心 DLL 构建和 Flutter 122 项测试；2,000,001 UTF-16 单元恢复夹具约 2 分钟完成，结果符合现状预期。

## 今日会话（2026-10-28 第十八轮）：Linux WPE runner 与 beta 探针复验

- 为 Flutter Linux 加入生成的 Linux runner、Debian sid WPE 构建 workflow 和 Xvfb 生命周期采样脚本；锁定 `flutter_inappwebview 6.2.0-beta.3` / `flutter_inappwebview_linux 0.1.0-beta.1`，Linux WebKit 保存 MHTML 到 `.mht`，用插件 PNG API 截图并验证同 view 重载标记。Linux runner 尚未执行，不记为 runtime evidence。
- 所选插件的公开方法表将 `callDevToolsProtocolMethod` 限于 Windows WebView2；`isInspectable` 表未包含 Linux。静态契约与未运行边界见 `p00.4-linux-wpe-evidence.json`，P00.4 继续 blocked。
- Windows Git Bash Flutter 3.47.8：探针 `dart format`、`flutter analyze`、`flutter test` 通过；NuGet CLI 下载依赖后 Release build 退出码 0。beta.3 自动 WebView2 生命周期回放通过，1,438-byte MHTML 在同一 view 重载且两张截图均含页面标记；销毁后 30 秒单进程 203.2 MiB，探针退出。原始数据见 `p00.4-web-beta-run/` 与 `p00.4-web-beta-evidence.json`。
- Windows Git Bash `bash init.sh` 本轮退出码 0：Rust workspace tests、clippy、核心库构建与 Flutter 122 项测试通过；2,000,001 UTF-16 单元恢复夹具完成并保留预期现状。启动时 bashrc 有编码告警，不影响门禁结果。
- 新增 Linux Flutter/WPE workflow 仅在 PR/手动触发，未 push/dispatch；macOS workflow 也未运行。Marketplace/官方服务授权阻塞仍在，P01 不开工。没有修改 `app/` 或 `crates/`。

## 今日会话（2026-10-28 第十七轮）：补齐 macOS WebArchive 回放 runner

- Windows Git Bash 重验固定 SHA commit 下载 URL，HTTP 404；对官方 CLI 使用的语义版本解析端点发起 GET 也返回 404。微软维护的 `vscode-test` helper 与 VS Code CLI 更新服务源码都采用同一固定 commit URL。证据见 `reference-acquisition.md`；结论限于公开的官方路径，不推断所有内部/企业渠道。
- 给隔离 `tools/web-engine-probe/` 加入 Flutter macOS 工程骨架：macOS 使用 `WKWebView.createWebArchiveData()` 写出 `.webarchive`，在同一个 view 重新打开并验证页面标记。新增 Mac 重放脚本，采集 `footprint -targetChildren`、页面 JSON、Web Archive 和尽力截图；新增仅 `pull_request`/手动触发的 macOS 15 GitHub Actions 工作流。
- Windows Git Bash Flutter 3.47.8 下 `dart format`、探针 `flutter analyze`、`flutter test` 均通过；`cargo fmt --check && bash init.sh` 与单独 app `flutter analyze` 也通过。Mac 构建和运行尚未执行，Safari Web Inspector 附着仍需手动验证。Mac runner 是测试基础设施，不计平台 evidence，P00.4 仍 blocked。
- GitNexus staged 检查为 risk=medium，37 个文件/20 个符号/5 条受影响流程；五条均为隔离探针的 build、导出、重载、销毁与自动回放路径。all scope 还包含工作区用户既存改动。`_captureMhtml`、`_captureRenderedPage`、`_openMhtml`、`_runAutomaticReplay` 的 impact 为 LOW。`_toggleWebView` 显示 HIGH，因此撤回该方法内的状态文案改动并保持方法原样；`State.build` 图谱为 UNKNOWN，源码检索确认它是 Flutter 覆写且动态回调位于该方法内，调用边界已人工复核。流程索引自身存在截断，缺失流程不视作无影响。
- 未修改 `app/` 或 `crates/` 产品代码；P01 未开始。

## 今日会话（2026-10-28 第十六轮）：P00 完整门禁复验

- Windows Git Bash 执行 `cargo fmt --check && bash init.sh` EXIT=0；Rust workspace tests、core 构建、clippy 零警告、Flutter 122 项测试全绿。RECOVERY-01 实际接受 2,000,001 个 UTF-16 单元，重启恢复内容仍只有磁盘上的 5 个单元，夹具符合预期。
- 单独执行 Flutter `analyze` EXIT=0，`No issues found!`。本轮没有改动 `app/`、`crates/` 或产品依赖。
- GitNexus 状态在提交 `7a67d8f` 时 up-to-date；本次仅更新状态/交接文档。只提交本轮文档，不包含工作区已有的其它用户改动。
- P00.4 的 macOS、Linux Flutter/WPE/CDP 与 Microsoft 官方服务身份/许可阻塞仍未解除；feat-022/P00 保持 in-progress，P01 未开始。

## 今日会话（2026-10-28 第十五轮）：复核官方发行物与 Linux WPE runner 前提

- Windows Git Bash 重查 Code-OSS 固定 SHA 的微软发行地址：`latest/win32-x64-archive/insider` 当前回到 1.144.0 Insiders、revision token `abc2b20cb3e724689f78f5d2a3c231589b25483c`；固定 SHA 与 1.145.0 下载 URL 仍 404。P00.1 继续以已启动的 pinned Code-OSS 源码构建为参考，不替换版本，也不把其它版本当等价发行物。
- 重新核对微软 FAQ 与 Settings Sync 文档：Marketplace 限 Visual Studio 产品家族且不允许 Code-OSS fork；Settings Sync 不支持自定义后端。未登录、未请求 Marketplace 或写入服务，P00.4 服务身份/许可阻塞保持。
- 调查 Linux Flutter 路径：上游插件 v6.2.0-beta.3 才加入 Linux，依赖独立 WPE 实现；Ubuntu 24.04 WSL 当前没有 Linux Flutter/Dart SDK 或 WPE 开发包，主机只有 Windows Flutter SDK。Debian sid WPE 2.54.1 包是可选 runner 路线，但本轮未构建/运行 beta 插件；GTK 原生探针不替代该验收。
- GitNexus `detect_changes` all/staged 均 risk=low；staged scope 为 5 个文档文件、0 条受影响流程。返回对象未带 `partial`/`truncated` 字段；分析器流程索引仍有截断（187 flows、406 个入口候选中 206 个未入选、98 个 callee 被跳过、2 次 walk 达预算）。
- Windows Git Bash `bash init.sh --fast` EXIT=0，Flutter 122 项通过。无 app/、crates/ 或产品依赖改动。P00.4 仍 blocked，feat-022/P00=in-progress，P01 依赖未满足。

## 今日会话（2026-10-28 第十四轮）：补充 Linux WebKitGTK 原生引擎证据

- WSL2/WSLg 上运行 GTK 3.24.41 + WebKitGTK 2.52.6 原生探针；离线 HTML 渲染、页面快照、MHTML 保存及同一 view 重载均通过，Web Inspector 成功附着并留存截图。此结果不代表 Flutter Linux/WPE 集成，也不证明 Chrome CDP 兼容。
- 单次 Private_Clean + Private_Dirty 进程树样本：空壳 1 个进程 / 22.7 MiB，页面加载 3 个 / 170.0 MiB，MHTML 重载 3 个 / 199.2 MiB，Inspector 完成 5 个 / 449.8 MiB，销毁 30 秒后 2 个 / 69.6 MiB；NetworkProcess 仍在，且非 docs/04 的三轮及 1/10/30 分钟产品验收。WSLg 报告 DRI3 不可用。
- 新增可重放 runner `tools/web-engine-probe/linux/run-webkitgtk-probe.sh` 和探针 `webkitgtk_probe.py`；原始阶段 JSON、PNG、MHTML 与聚合摘要位于 `docs/diagnostics/2026-10-27-p00/p00.4-linux-webkitgtk-run/` 和 `p00.4-linux-webkitgtk-evidence.json`。不安装依赖包，runner 将所需 typelib/Cairo bridge 解到临时目录。
- Windows Git Bash `bash init.sh --fast` EXIT=0；`bash -n`、Python `py_compile` 与相对输出路径的 Linux runner 重放 EXIT=0，九个阶段均产出；MHTML 两次重放均有 MIME 头/页面标记，截图一致。MHTML MIME boundary 随次生成，哈希不同；归档摘要只记录提交的规范样本哈希。没有修改 app/ 或 crates/ 产品代码。
- GitNexus 本轮 `detect_changes` 的 all 与 staged scope 均为 risk=high；staged scope 覆盖 22 个文件与 8 条受影响流程，流程均落在独立 WebKitGTK GTK 探针的生命周期/采样路径。all scope 还包含未暂存的用户既存 README/app/workbench 修改。检测返回结构未带 `partial`/`truncated` 字段；索引构建报告 process graph 本身被截断（187 flows、406 个候选入口中 206 个未入选、98 个 callee 被跳过、2 次 walk 达预算），所以不把缺失流程视为无影响。
- P00.4 仍 blocked：Flutter Linux 插件/CDP、macOS 和 Marketplace/官方服务条件仍未解决；P01 依赖 P00，不开工。

## 今日会话（2026-10-27 第十三轮）：P00.4 Web 与官方服务风险实验

- Web 实验使用独立 `flutter_inappwebview 6.1.5` Windows Release 探针；按生命周期阶段标记采样，CDP `Page.captureSnapshot(format=mhtml)` 导出 1,438-byte MHTML，并在同一 WebView2 中重载；`Page.captureScreenshot` 导出的初始页与 MHTML 页均含 `WEB_ENGINE_PROBE_OK`。
- 单次进程树 Private Bytes：挂载前 1 进程 / 198.1 MiB，初始 WebView 7 进程 / 369.3 MiB，MHTML 阶段 7 进程 / 404.1 MiB，销毁后 1 进程 / 211.0 MiB，30 秒后 1 进程 / 203.9 MiB。探索样本不是 docs/04 三轮和 1/10/30 分钟验收。
- Windows `flutter analyze` 零问题、`flutter test` 1 项通过、Windows Release 构建通过；当前 MSVC 需 NuGet 和临时 coroutine 弃用宏。没有修改 app/ 或 crates/。
- macOS 无测试设备；WSL 没有 Linux GUI/Flutter Linux/WebKitGTK/WPE，跨平台 Web/CDP/MHTML 仍未验证。
- 固定 Code-OSS 1.145.0 `product.json` 缺少正式版 auth/Sync/gallery/tunnel 配置；本机另装 Microsoft VS Code 1.142.0 Stable 有独立产品身份字段，凭据值未复制。官方 FAQ 明确 Marketplace 不允许 Code-OSS fork 使用，Settings Sync 不支持自定义后端；无账号登录、OAuth 注册、Marketplace 请求或隧道创建。
- 阶段提交门禁：Windows Git Bash `cargo fmt --check`、`bash init.sh` 与单独的根目录 `flutter analyze` 均 EXIT=0；完整 Flutter 测试通过（122 项）。
- GitNexus 索引更新后，完整 `detect-changes --scope all` 无 `partial`/`truncated`：107 files / 271 symbols / 17 flows，risk=critical，包含工作区其它既存改动。仅 staged scope 也无 `partial`/`truncated`：78 files / 255 symbols / 17 flows，risk=critical；受影响项来自两个独立 Flutter 探针的通用 Win32Window 生命周期模板，以及 Web 探针自动回放路径，未涉及 app/ 或 crates/。Analyzer 本身仍报告 process graph 截断（187 flows；393 个候选入口中 193 个未入选、98 个 callee 被跳过、2 次 walk 达到预算），缺失 flow 不视为无影响。
- 证据：`p00.4-web-adr.md`、`p00.4-web-evidence.json`、MHTML/PNG/进程树 JSON、`tools/web-engine-probe/`；`p00.4-services-adr.md`、`p00.4-services-evidence.json`。
- P00.4 记为 blocked，feat-022/P00 保持 in-progress；P01 依赖 P00，当前不能签收或开工。

## 今日会话（2026-10-27 第十二轮）：P00.4 实验1编辑器风险探针

- 独立 Flutter Windows 探针运行 CodeForge 11.3.0；未改 Alula 产品工作台或 Rust 文档模型。
- Windows 11 Microsoft Pinyin 实测 composition/candidate commit/Escape cancel/Latin incremental input。Flutter widget characterization 验证 composing 文本未提前改权威文本、提交后单次撤销恢复；Delta 插入分发到主光标和三次光标并可一次撤销；10,000 行视口滚动。
- Windows Git Bash flutter analyze 与 flutter test 均 EXIT=0，4 项测试通过。Debug混合输入累计帧/按键采样仅作探索记录，不作为延迟或性能验收。
- 决策：CodeForge 11.3.0 保留为 P03 候选，不直接集成；Rust DocumentModel 仍须是唯一权威文本。三平台IME、Rust往返/背压、Release内存/时延、Emoji/ZWJ/组合字符/CRLF/BOM、多视图/无障碍等未验证。
- 证据：docs/diagnostics/2026-10-27-p00/p00.4-editor-adr.md、p00.4-editor-evidence.json、PNG 截图及 tools/editor-ime-probe/。
- P00.4 状态改为 in-progress；下一项顺序执行 Web/CDP/MHTML/按需内存实验，之后才做官方服务/注册前提实验。

## 今日会话（2026-10-27 第十一轮）：P00.3 现状风险夹具验收

- 新增 Flutter 双文件交替撤销、超 2M UTF-16 单元未保存恢复测试；新增 Rust 关闭工作区进程、1.2s 延迟补全测试及专用 fake LSP。
- Windows 11 Git Bash 运行四个现状夹具：撤销跨文件串写；超 2,000,000 UTF-16 单元正文未写入 journal，重启后读回磁盘 `seed\n`；关闭全部文档后 LSP 子进程仍存活；1.2s provider 令调用方等待 1.2s。固定 Code-OSS 1.145.0 的隔离运行再验证双文件分别撤销各自内容。
- 采集真实 Alula 空工作区页面图 `docs/diagnostics/2026-10-27-p00/alula-welcome.png`。与固定参考同为 1505×1005、1204×804 逻辑视口、DPI/DPR 1.25、深色主题；Alula 为 zh-CN、参考为 en-US，文字视觉配对留到 P05。
- DoD 全绿：`bash init.sh --fast`、`bash init.sh`、`cargo fmt --check`、`flutter analyze` 均 exit 0；Rust workspace tests/clippy/build_core 通过；Flutter 122 项通过。Windows 工具链/fixture 输出见 `p00.3-environment.json` 与 `p00.3-current-state.json`。
- `docs/03` 将 P00.3 标为 done，P00.4 仍 not-started。三项限时实验尚未开始；P00 整体仍 in-progress。

## 今日会话（2026-10-27 第十轮）：P00.2 原子贡献与运行时登记导出

- 固定源码 AST、95 个扩展 manifest、`product.json` 和隔离运行时 registry 导出为 12,958 条唯一登记记录；导出器验证 pinned commit/tree，保留运行时独有 ID、无稳定 ID、无目录路由和无 feature 路由等未决项。
- 运行时快照：2,684 条命令、5 种语言、1,289 个配置键；client-only 宿主未加载随附扩展 payload，静态 95 个 manifest 与运行时 0 个产品扩展的差异单独记录。运行时配置候选 1,289/1,289 可查。
- 检查发现并修正对账逻辑，防止把运行时独有项误计为源码项；注册记录 ID 现在唯一。当前尚有 6,828 条未决注册/路由，不计作覆盖率，留待后续逐项复核。
- 证据：`docs/diagnostics/2026-10-27-p00/atomic-contributions.md` 与 JSON ledger；可用 `node tools/vscode-parity/export-atomic-contributions.mjs --source=<pinned-checkout>` 重放。
- P00.2 导出器子项完成，P00 总包继续 in-progress；下一项为 P00.3 黄金基线/故障夹具。`bash init.sh`、`cargo fmt --check`、`flutter analyze` 均 EXIT=0，详见 `docs/diagnostics/2026-10-27-p00/p00.2-validation.log`。
- GitNexus `detect-changes --scope all` 报告 risk=critical（48 files/264 symbols/20 flows），包含此前已有的 README 和 app 修改；staged scope 为 19 files/248 symbols/17 flows，命中本阶段新导出器流程与文档，无 Alula 产品源码。记录于 `docs/diagnostics/2026-10-27-p00/atomic-contributions.md`。

## 今日会话（2026-10-27 第九轮）：P00.1 固定参考构建与启动

- 固定 SHA `4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e` Code-OSS client-only build 成功；Electron `43.8.3` 生成并成功启动 Workbench。构建输出 `client=full, extensions=skip, copilot=skip`，未编译外接 AI lane。
- 使用独立 user-data/extensions 目录启动，无账号登录；CDP 导出 viewport/DPI/locale/主题和 `product.json` 内置扩展清单，并保存 Workbench 欢迎页截图。
- 官方微软精确 SHA 发行物仍未找到；只把 Code-OSS 源码作为参考构建。remote 子树 postinstall 为非桌面 client 依赖，构建取证后停止；不将 remote 依赖视为已安装。
- 仓库 DoD：`bash init.sh` EXIT=0（Rust test、clippy、build_core、Flutter 120 tests）；另跑 `cargo fmt --check`、`flutter analyze` 均通过。Git Bash 启动有 `.bashrc` UTF-16 BOM 提示，但命令继续并全绿。
- 证据：`docs/diagnostics/2026-10-27-p00/reference-acquisition.md`、`capture-reference.mjs`、`runtime-evidence.json`、`reference-workbench.png`。P00.1 已验收，P00 总包仍 in-progress。

## 今日会话（2026-10-27 第八轮）：P00.1 固定参考获取（历史进度）

- 切到 `codex/vscode-parity-p00` 分支，保留工作区既存改动；没有整仓暂存或提交。
- GitHub 官方 commit API 核实 pinned SHA、tree、parent 与签名；`package.json` 为 1.145.0，`product.json` blob 已核验。
- 官方 Insider 最新归档落在 1.144.0 / 不同 commit；精确 SHA 与 1.145.0 的测试下载 URL 返回 404。本地 `code` 为 1.142.0，不能代替固定参考。
- Git smart-protocol 在 WSL 与 Windows Git Bash 均挂起；固定源码后续改用限制目标的 Git 协议 v2 relay 获取，commit/tree 已核验。该轮结束时构建和启动尚未完成。
- 基线：WSL `init.sh --fast` 因无 cargo 及 Flutter shell CRLF 失败；Windows Git Bash 的同命令退出 0，Rust 测试/build_core 与 Flutter 120 项通过。Node 24.22.1、npm 12.0.2、cargo 1.97.1；npm registry ping 17.7 秒成功。
- 证据：`docs/diagnostics/2026-10-27-p00/reference-acquisition.md`。本轮没有产品实现变更，不做内存或 UI 等价结论。

## 今日会话（2026-10-27 第七轮）：完整复刻计划

- 固定上游：vscode `4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e`（1.145.0开发快照）；
  docs `da213552439825628e0ab958dbde1e413dbc36bf`。通过官方GitHub connector实查目录、
  90个非AI产品manifest/74个language ID/89个grammar贡献及3个下载式预置调试扩展。
- 总计划16实施包P00–P15，含架构/依赖/风险/资源/跨平台界面及行为验收；矩阵342条功能族
  与14项边界决策。功能族仍须P00展开为原子注册项，不声称已完成100%语义覆盖。
- 范围包括内置扩展、终端、默认JS调试、Notebook宿主/输出、Markdown rich/math/Mermaid、
  集成浏览器、Profiles/Sync、Cloud Changes、公网Ports等非AI外部服务。外部服务互通前提单列，
  不能因联网删需求，也不冒称额外Python/Jupyter/Remote等provider已默认提供。
- 修正旧计划只要求结构等价、历史状态过期、空窗内存被当同功能−50%已通过的问题。
  现有全局UndoStack/大文档备份/同步FFI/800ms轮询/LSP回收等静态风险列入P00/P01/P02。
- 按Startup规则复验发现当前工作树Flutter编译失败：`_findRenderEditableOf`递归误调用
  接收BuildContext的方法；GitNexus impact LOW（2个上游方法、Ctrl+点击流程），仅一行改为
  正确RenderObject递归辅助方法。保留其余用户既存代码/skill改动。
- 验证：Windows Git Bash执行cargo fmt --check + bash init.sh + flutter analyze，EXIT=0；
  Rust workspace测试全绿、Flutter120测试通过，clippy零警告/analyze零问题。
  证据：docs/diagnostics/2026-10-27-parity-plan/full-validation.log；前后fast日志同目录。
- 当前WSL无cargo且Windows Flutter shell为CRLF，不能直接据WSL失败判业务错误；使用现有
  Windows工具链复验。原Windows GitNexus元数据在WSL无效，隔离索引在
  `/tmp/alula-plan-gitnexus`，不改原`.gitnexus`缓存；过程发现截断不可推断缺失调用不存在。
- 计划结构/链接/依赖自检通过，harness100/100；全工作树graph change analysis记录于同目录。
  最终证据见verification.md。feat-021计划完成；P00–P15未开始，未提交、未推送。

## 今日会话（2026-10-27 第六轮）：feat-outline 大纲视图（首个 Rust 侧功能）

- **全栈贯通**：editor-lang.symbols()（tree-sitter 遍历 10 类定义节点，impl 取
  「Trait for Type」，UTF-16 偏移/行号，嵌套+深度保险）→ editor-core.doc_symbols
  → FFI alula_symbols（**ABI 3→4** 双侧握手）→ Dart core.lsp.symbols →
  大纲侧栏视图（类别徽章/行号/点击跳定义）+ 编辑后防抖刷新（版本去重）。
- **顺修真实 UX bug**：外部刷新重建文件树丢展开状态（git status 写 .git 即
  触发监视刷新，用户展开被抹掉）→ _refreshTree 快照并恢复展开态。
- CI Format 门抓了新代码格式（cargo fmt 补齐）。
- 测试：3 Rust 单测 + 1 端到端 widget；全量 120 绿 + CI 全绿。

## 今日会话（2026-10-27 第五轮）：feat-filewatch 文件监视

- WorkspaceWatcher：Directory.watch(recursive)（Windows/Linux 原生递归，零新
  依赖），600ms 防抖收敛，错误静默降级；先探测本平台递归可用性再动工。
- 外部变更后：文件树刷新（根+已展开目录保留展开态）、Git 状态刷新、
  打开文档检测——干净文档自动重载、脏文档仅提示（不覆盖本地编辑）。
- analyzer info 清零（5 项字符串插值 lint）——init.sh 不含 analyze 的盲区
  被 CI 抓到一次，注意提交前跑 analyze。
- 测试：3 watcher 单测 + 1 端到端（外部写盘→自动重载）；全量 119 绿 + CI 全绿。

## 今日会话（2026-10-27 第四轮）：feat-search 搜索视图

- **SearchService**：后端探测 rg --json → git grep --untracked → 不可用提示；
  流式命中（StreamController + 取消订阅终止子进程）；上限 500。
- **三个实战坑**：① rg 在 stdout 管道化且无显式路径时等待 stdin（补 '.'）；
  ② git grep 默认不搜未跟踪文件（补 --untracked）；③ pattern 必须在
  '--' pathspec 之前。CI 又抓到一个：rg 探测要捕 ProcessException（可执行
  文件不存在直接抛异常，不只是非零退出码）。
- **UI**：活动栏搜索图标激活（侧栏第三视图）+ Ctrl+Shift+F 命令/键位 +
  搜索框（Enter/大小写切换）+ 命中列表；点击命中打开文件并跳转到对应行。
- 测试：10 服务测试 + 1 端到端 widget（runAsync）；全量 115 绿 + CI 全绿。

## 今日会话（2026-10-27 第三轮）：feat-git Git 面板

- **GitCli**（Dart CLI 封装）：status --porcelain -z 解析（rename/中文路径/
  未跟踪目录归一化）、add/reset/commit/diff/log；默认 runner 显式 UTF-8
  （Windows 码表乱码坑）；runner 可注入。6 假 runner 单测 + 4 真 git 集成测试
  （临时仓库全流程，局部 user 配置）。
- **UI**：活动栏双视图切换（资源管理器/源代码管理，重复点折叠）；Git 面板
  （分支/暂存区与工作区分组/单文件暂存取消/提交框/错误展示）；点击更改文件
  → 底部面板「Git Diff」标签看差异。
- **踩坑**：widget 测试假 async zone 里真实 git 子进程永不完成 → tester.runAsync
  包裹；ListTile 在彩色容器内触发框架断言 → 透明 Material 包裹。
- 测试：104 全绿 + init.sh + CI 全绿。

## 今日会话（2026-10-27 第二轮）：feat-010a 撤销/重做 + 查找替换

- **决策**：Flutter 内建 UndoHistory 探测死锁（测试环境）且绑死 TextField
  （组件选型会失效）→ **自研 UndoStack**（文本快照制：400ms 打字合并、
  100 帧/200 万字符双上限淘汰、新变更作废 redo）。撤销 = 快照写回 controller
  经 diff→FFI 同步，一致性天然成立。
- **关键机制**（两条都踩过）：① 每文档 FocusNode onKeyEvent 在事件分发第一站
  拦截 Ctrl+Z/Shift+Z/Y/F/H——原生 UndoHistory 在焦点链更下方注册同键；
  ② 撤销快照基线必须在 savedText 前移之前捕获（先写反过一次，端到端测试抓住）。
- **查找替换**：find_replace.dart 纯逻辑（非重叠匹配/大小写切换/从后向前
  全部替换，UTF-16+Emoji 用例）+ 编辑器右上角浮层（计数 x/y、上下导航、
  替换/全部替换）；标题栏新增「编辑」菜单。
- 测试：16 纯逻辑 + 1 端到端；全量 93 绿 + init.sh + CI 全绿。

## 今日会话（2026-10-27）：W3-2 键位注册表

- **KeybindingSet**：默认表 10 键位（逗号分隔多键位）、parseChord 解析、
  用户 keybindings.json 覆盖（追加 = 同命令重绑定、'-command' 移除、损坏逐条忽略）、
  KeybindingsStore 可注入。
- **页面接入**：全局 CallbackShortcuts 由注册表生成；编辑器级快捷键全部并入；
  F1-F3 命令化；菜单键位提示动态化（用户重绑定后菜单自动跟随）。
- **踩坑记录**：SingleActivator 没有重写 ==/hashCode（Shortcuts 走 accepts()
  分发），不能当查询键——值查询用 KeyChord。
- 用户交互复验通过（W2）；CI 两轮推送全绿。
- DoD：init.sh 全绿（Rust 41 + Flutter 76）。

## 今日会话（2026-10-26 第七轮续）：W3-1 命令面板 + CI 首跑修复

- **git push 首次执行**（8477ecc..ca26c07），CI 首跑**失败并抓到两个真问题**：
  ① mem-probe linux.rs 在返回 u64 的函数里用 `?`（Linux 路径首次被真实编译）；
  ② 5 个 widget 测试依赖 Windows 绝对路径 fixture。已修复：仓库相对 fixtureRoot
  + linux.rs and_then 归零 + 顺修侧栏标题混合分隔符切分 bug。
- **W3-1 命令面板**：CommandRegistry（11 条命令注册）+ fuzzyScore 模糊打分
  （子序列/连续/词首加权）+ QuickInput 浮层；Ctrl+Shift+P / Ctrl+P / Ctrl+B /
  Ctrl+J 全局键位（autofocus Focus 保证无焦点可达）；快速打开用有界文件索引
  （2000 上限，跳过 .git/target 等；同步 FFI 遍历大仓库会卡 UI，已知限制）。
- CI 复跑已触发（40355417691）。

## 今日会话（2026-10-26 第六轮）：W2-3 面包屑 + W2-4 会话 journal + 冒烟

- **W2-3 面包屑**：工作区相对路径段（根以下，对标 VS Code），点文件夹段唤起
  侧栏并沿祖先链展开文件树；多组各自有面包屑。
- **W2-4 会话 journal**：SessionStore（session.json 原子写盘，损坏回退）；启动恢复
  组/标签/焦点/文件树/未保存文本（journal 文本优先于磁盘；脏标记不跨重启保留，
  内容优先）；单文档文本上限 2M 字符。**顺手修正隐性 bug**：原 isDirty 是同步
  基线差值（每次 apply 后基线前移 → 脏点永不显示），新增 dirtyDisk 真磁盘脏标记。
- **实机冒烟**：W2 Release 稳态 189.9 MiB（+1.8% < 5% 护栏，≤200 线内），
  docs/baselines/2026-10-26/alula-w2-empty.md；启动级验证了两笔 Risk high 提交。
- ⚠️ 仍需人工交互复验：拆分/拖标签/强杀后 journal 恢复（真窗口操作）。
- DoD：init.sh 全绿（Rust 41 + Flutter 58）。

## 今日会话（2026-10-26 第五轮）：W2-2 编辑器组拆分

- **W2-2a 布局树分裂原语（commit 7a9d33a）**：splitLeaf（叶子→嵌套分割，权重交接，
  防重名）/removeLeaf（摘除 + 单子 split 自动折叠沿用权重；根直接子节点拒摘）+
  控制器转发 + 7 项模型测试。
- **W2-2b 编辑器组（commit 31b2ba6）**：EditorGroup（region+docs+activeDocId）替代
  全局文档列表；焦点组路由（拆分后新组获焦；点标签/编辑器切焦点；保存/补全/
  快捷键/新开文档进焦点组）；跨组跳转激活；空组自动摘除并组；「拆分编辑器」按钮。
- ⚠️ GitNexus 对 W2-2b 评 Risk high（2 文件 11 符号）——缓解：52 测试全绿含多组
  全链路 widget 测试；**待实机复验**。
- 清理：共享 _editorFocus 删除（多组下不成立）。
- DoD：init.sh 全绿（Rust 41 + Flutter 52）。

## 今日会话（2026-10-26 第四轮）：W1-3 补完 + 内存验收 + W2-1

- **W1-3 无边框窗口（完成，commit 007594a）**：开发者模式开启后接入 window_manager
  0.5.2；TitleBarStyle.hidden + DragToMoveArea + 双击最大化 + 窗口按钮；
  windowControls 开关隔离测试与插件通道。
- **W1 验收内存复测（通过，commit e633955）**：Release 实机 mem-probe 45s：
  **稳态 186.6 / 峰值 197.1 MiB**（≤200 线过；较 MVP +4.0% < 5% 护栏），
  docs/baselines/2026-10-26/alula-w1-empty.md。**feat-015 → done。**
- **W2-1 标签条交互（commit 后续）**：溢出横向滚动、中键关闭（kMiddleMouseButton）、
  Draggable/DragTarget 邻位拖动排序；widget 测试用鼠标指针拖 tab-3 到首位断言。
- **下轮首任务 W2-2 编辑器组拆分**：布局树 editor 叶子可分裂为组分割（复用
  WorkbenchGrid 引擎）；文档模型从全局 _openDocs 改为按组持有 + 焦点组路由快捷键；
  触点面大，需整轮专注做。

## 今日会话（2026-10-26 第三轮）：W1 布局骨架落地（docs/09 开始执行）

- **既有成果分 4 笔提交入库**（clippy/fmt 清理 → harness → CI → docs/09 计划）。
- **W1-1 布局树模型**：WbNode/WbSplit/WbLeaf 分割树（固定/弹性/折叠三形态）、
  moveDivider 拖拽数学（min 钳制 + 退化区间保护）、像素⇄权重双向换算无漂移、
  JSON 序列化 + defaultLayout。18 单测。commit `W1-1`。
- **W1-2 网格渲染 + 五大区**：WorkbenchGrid（分割条只在相邻弹性节点间、内置监听）、
  WorkbenchLayout 控制器（折叠记忆/唤起）；原 EditorPage 全逻辑迁 workbench_page.dart，
  旧工具栏动作拆入标题栏菜单/侧栏头部/编辑器动作区；诊断/补全/语法移入底部面板；
  main.dart 瘦身。38 测试。commit `W1-2`。
- **W1-4 布局持久化**：LayoutStore（原子写盘 + 损坏回退）、启动恢复、500ms 防抖落盘、
  dispose 冲写；layoutStore 注入点隔离测试与真实用户目录。42 测试。commit `W1-4`。
- **W1-3 无边框标题栏（已完成）**：用户开启开发者模式后接入 window_manager 0.5.2：
  TitleBarStyle.hidden + DragToMoveArea 拖拽移动 + 双击切换最大化 + -/□/× 窗口按钮
  （WindowListener 跟踪最大化态）；windowControls 显式开关隔离测试与插件通道。
- **W1 验收内存复测（已过）**：Release 实机 mem-probe 45s 采样，
  **稳态 186.6 MiB / 峰值 197.1 MiB**（≤200 验收线），较 MVP 基线 179.2 **+4.0%**
  （低于 5% 护栏，归属 = 工作台外壳），报告 docs/baselines/2026-10-26/alula-w1-empty.md。
- **feat-015 关闭（done）**：W1 全项完成。
- **决策微调**：Riverpod 推迟到 W3（命令/键位系统）引入；W1 用 ChangeNotifier +
  ListenableBuilder 已满足细粒度重建，少一个依赖。
- DoD：init.sh 全绿（Rust 41 + Flutter 43）。

## 上一会话（2026-10-26 第二轮）：工程化建设

| 项 | 结果 | 证据 |
|---|---|---|
| GitNexus 代码图谱 | ✅ 索引完成 | 796 符号 / 1681 关系 / 34 簇 / 66 执行流；`.gitnexus/run.cjs status` 报 up-to-date；CLAUDE.md / AGENTS.md 注入使用规则 |
| harness-creator 文档 | ✅ 五件套就位，validator 100/100 | AGENTS.md + CLAUDE.md（守则）、feature_list.json（14 项状态机）、progress.md（本文件）、init.sh（一键验证）、session-handoff.md |
| CI/CD | ✅ 工作流就位 | `.github/workflows/ci.yml`：Rust（fmt+clippy+test，Windows/Linux 矩阵）× Flutter（analyze+test，走真实 FFI）× harness 校验；`release.yml`：tag 触发 Windows/Linux 打包；YAML 语法已校验，**Actions 首跑待推送后确认** |
| VSCode 工作台复刻计划 | ✅ 计划成文 | `docs/09-VSCode工作台Flutter复刻计划.md`（W1–W6 里程碑 + 内存护栏） |
| 附带清理 | ✅ clippy/fmt 清零 | 修复 16 处 clippy 警告 + 全仓 cargo fmt；`build_core.sh` 补 Windows dll 支持；修复两处 init.sh 缺陷（flutter 路径解析、shell 语法） |
| 本机 DoD 复验 | ✅ init.sh 全绿 | EXIT=0：cargo test / clippy -D warnings / build_core / flutter analyze+test 全过 |

## 上一会话（2026-10-26 第一轮）：Phase 0 收尾 + Phase 1 增量 1

- 0-3 完成：rust-analyzer 全链路（诊断 7 条 / 补全 62 项 / 语法 40 token），
  截图 `docs/diagnostics/2026-10-26-lsp-demo/`。
- 0-4 完成并否决原型 A 路线（省 1.5% 内存，无竞争力），`docs/08`。
- 0-5 完成：mem-probe + bench + 首批基线 **alula 179.2 vs VS Code 959.5 MiB（−81.3%）**，
  `docs/baselines/2026-10-26/`。
- 0-7 完成：VS Code 卡死根因 = 系统提交内存耗尽，`docs/07`。
- 增量 1：文件夹→文件树→多标签→编辑→Ctrl+S 原子保存 + RA 多文件，
  截图 `docs/diagnostics/2026-10-26-phase1/`。

## 验证记录（本机，2026-10-26）

```
cargo test --workspace   → 10+12+3+2+3+1+3+4 全部 ok（41 passed, 0 failed）
flutter test (app/)      → 15 tests passed（含随机对拍 100 组与真实 FFI 闭环）
```

## Next（下一步，按 docs/03）

1. 继续关闭 P00.4 风险门：在真实 DRM 主机验证 WPE GBM/DMABUF，处理服务身份/许可边界，并完成 docs/04 三轮长时多场景采样。
2. 主产品 `app/` 缺 Linux desktop runner；Flutter host toolchain 已就绪，`flutter build linux` 仍因项目未配置而无法开始。将 scaffold 工作按 docs/03 依赖排到后续跨平台阶段；独立 WPE probe 已有 Linux runner。
3. P00/feat-022 完成前不启动依赖它的 P01；当前仍有 WPE 硬件、官方服务和产品内存验收阻塞。


## 今日会话（2026-10-29 第六十五轮）：完整复跑与同服务空闲对照

- 按用户要求重新完成 Windows Release Alula + Rust Analyzer 前台编辑验收。有效样本 1800.015 秒、150/150 次保存、1815 个一秒 mem-probe 样本；Private Bytes 峰值/稳定/最终 841.89/657.93/233.85 MiB，稳定值仍高于 500 MiB 目标 157.93 MiB。最终 marker/hash 通过，6 个观察 PID 在关闭+30 秒后全部退出，隔离 HOME/fixture 已删除、前台恢复。stderr 有两条 watcher-path 警告，没有非优雅 LSP shutdown 警告。原始报告：`docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-rust-lsp-edit-30m-run3-20261029-065714888.{json,md}`、`-activity.json`、`-probe.stderr.log`。
- 一次零输入的启动尝试因独立 PowerShell 状态查询抢焦点而在首个编辑前中止（0 保存、0 样本）；对应 abort JSON 保留在 `...run3-20261029-065645804-abort.json`，不计为有效样本。有效复跑期间没有另开窗口。
- 按用户授权完成隔离 Microsoft VS Code 1.142.0 Stable + rust-analyzer extension 0.3.3089 / server 1.97.1 idle 对照。600 个进程树 Private Bytes 样本覆盖 759.872 秒（首末样本跨度 759.341 秒，中位采样间隔 1.249 秒）；峰值/时间尾段40%上中位/最终为 1655.61/1267.18/1265.46 MiB，final Working Set 1541.28 MiB；RA 可见，关闭+30 秒所有记录 PID 退出。启动时发生一次窗口前台切换，脚本恢复原窗口并最小化 VS Code 后继续，采样期间未再恢复。该样本使用隔离 profile/extensions/shared-data、未登录/Sync；VS Code 版本不是 pinned Code-OSS 1.145.0-dev，仅为补充对照。证据：`docs/diagnostics/2026-10-28-p00/p00.4-windows-vscode-rust-lsp-idle.{json,md}`、同目录 timestamped `.log`。脚本的前台布尔字段已由事件列表校正，600个采样数据未改。
- WSLg/Xvfb 主应用 1 GiB cgroup / swap=0 的真实 Rust Analyzer 10 分钟 idle：600 秒无输入，memory.current 峰值 803.91 MiB、scope PSS 峰值 889.30 MiB、单核归一 CPU 8.036%，OOM/OOM-kill=0/0；关闭+30秒 RA/proc-macro 退出。该单轮软件渲染样本不代表 DRM 主机。证据：`docs/diagnostics/2026-10-29-p00/p00.4-wsl-rust-ra-10m-idle-cgroup-1024-20261029-065450.{json,md}`。
- P00.4 仍 blocked：Windows Rust+RA 稳态超过 500 MiB，真实 DRM/WPE GBM/DMABUF 和 Microsoft 官方服务身份/许可仍不可用，VS Code 对照有版本差异，完整 docs/04 产品跨平台矩阵未完成；feat-022/P00 继续 in-progress，P01 不开始。没有提交产品代码。
- P00.4 阶段证据提交 `c7f0d9b` 已推送到 PR #1。GitHub 检查全绿：CI run `40791174980`（Flutter analyze/test、Ubuntu/Windows Rust、Harness）、macOS WKWebView/Safari run `40791174984`、Linux WPE run `40791174974`。

## 最新进展（2026-10-29，第六十九轮）

- 按授权继续 P00.4 本地 WSL idle 观察：在既有 WSLg/Xvfb Rust+RA 10 分钟样本基础上新增两轮；每轮 1 GiB cgroup、swap=0、无输入 600 秒。峰值 `memory.current` 为 809.56/821.54 MiB，scope PSS 峰值 880.26/892.16 MiB，OOM=0，应用退出码 0，关闭+30秒 RA/proc-macro 均退出，隔离 HOME/fixture 清除。三次观察汇总见 `docs/diagnostics/2026-10-29-p00/p00.4-wsl-rust-ra-idle-3run-summary-20261029.md`。
- 修正采样器以焦点 XTest 键盘输入打开 `rust-mini/src/main.rs`，短截图预检已看到该文件（`docs/diagnostics/2026-10-29-p00/p00.4-wsl-rust-ra-idle-ui-check-src-main-20261029.png`）；修正按空闲边界前样本归因进程 CPU。两个新样本中 Alula 分别消耗约 154.79/146.97 CPU 秒，RA 低于 10 秒快照分辨率；旧样本单核归一 CPU 为 8.036%，和新样本差异明显。当前归因提示 WSLg/Xvfb software-GL 路径需要单独调查，不能外推真实桌面。另一次短截图检查的 UI 关闭未在限时内退出（SIGTERM，exit -15），已从有效内存样本中排除，失败预检见 `docs/diagnostics/2026-10-29-p00/p00.4-wsl-rust-ra-idle-ui-preflight-20261029.{json,md}`；三轮正式样本均为 exit 0。
- 这三次 WSLg 观察的 scope PSS 峰值中位数 889.30 MiB，高于 500 MiB Rust+RA 目标；它们不覆盖真实 DRM/WPE GBM/DMABUF、完整 docs/04 多场景压力矩阵或同版本编辑负载。P00.4/feat-022 仍 blocked/in-progress，P01 不启动。本轮未改产品源代码。
- 阶段提交 `07515f3` 已推送至 `codex/vscode-parity-p00`；GitHub CI `40806485257`、Linux WPE `40806485215`、macOS Web Engine `40806485341` 均成功。它们不替代原生 DRM/GBM 与完整 docs/04 产品矩阵。

## 今日会话（2026-10-29 第七十五轮）：固定版 Code-OSS 同服务 idle 启动诊断

- 用户授权的版本匹配对照尝试未进入 Workbench：固定 Code-OSS 1.145.0-dev / Electron 43.8.3，配置同一 rust-analyzer 1.97.1 与隔离 profile、扩展、shared-data、fixture；脚本先前的直接启动和随后上游 `scripts/code.bat` 启动均未观察到 renderer/RA，没有产生有效内存样本。最后一轮在30秒 renderer 快速门失败并清理；确认没有隔离进程或临时目录遗留，也没有 Marketplace/账户登录。
- 前面一次直接启动在4个 Code-OSS 进程下记录至240/600点后中止，另一次正确批处理入口等待180秒未见 RA；这些均无效，不与 Alula 内存比较。完整尝试、限制和日志索引见 `docs/diagnostics/2026-10-28-p00/p00.4-code-oss-rust-lsp-idle-startup-failure-20261029.{md,json}`，可重放的 fail-fast runner 为同目录 `p00.4-code-oss-rust-lsp-idle-10min.ps1`。
- 有效的 Microsoft VS Code 1.142.0 同服务 idle 对照仍是单独补充证据，版本与固定 Code-OSS 不匹配且不含编辑负载；Windows Alula 30分钟/150次保存编辑重跑已在既有进度中记录，稳定 Private Bytes 657.93 MiB，超过500 MiB目标。P00.4/feat-022 继续 blocked/in-progress，P01 不启动；没有产品代码改动。
- 提交前完整 `bash init.sh` EXIT=0：Rust workspace tests、Clippy、`build_core` 与 Flutter 122 项测试通过；PowerShell runner AST parse 和 evidence JSON 校验也通过。


## 本轮（2026-10-29）：固定版 rust-analyzer 配置审计

- 检查本机 0.3.3089/server commit `5ec20d044d`：扩展 schema 暴露 per-query LRU 设置，但固定源码中的应用函数为 Salsa 迁移留空；不运行该无效实验，也不削减语言能力。报告：`docs/diagnostics/2026-10-29-p00/p00.4-rust-analyzer-query-lru-config-audit.md`。
- P00.4/feat-022 保持 in-progress/blocked；P01 不启动。

## 今日会话（2026-10-30）：P02.2 dirty/savepoint

- 完成 P02.2：拆分磁盘 savepoint savedText 与 Rust diff 基线 syncText；undo/redo 跨已保存文本时 dirty 正确清除/恢复，Rust resync 不覆盖磁盘 savepoint。Widget fixture 覆盖 Ctrl+S、undo、redo、标签 dirty 点及磁盘内容。
- 完整门禁 FLUTTER_BIN=/tmp/alula-flutter-serial bash init.sh 通过：Rust workspace tests、Clippy、build_core、Flutter 133/133；另有 cargo fmt --all -- --check、Flutter analyze（0 issues）、定向 19 项测试通过。细节和风险边界：docs/diagnostics/2026-10-30-p02/p02.2-savepoint-dirty-undo.md。
- Rust + rust-analyzer ≤500 MiB 目标已按用户调整暂时移出当前目标，历史测量仅作基线，P14 重新定标；下一项 P02.3 Save As/Revert。现有工作树包含无关用户改动，阶段提交会按文件及内容精确选择。

## 今日会话（2026-10-30）：P02.3 Save As/Revert

- 完成 P02.3：新增 file.saveAs/file.revert、Save As 快捷键及 File 菜单；路径迁移更新 URI/名称/savepoint/journal，并检查重复打开路径和覆盖确认；Revert 读取当前路径磁盘内容、同步 Rust/controller、确认丢弃脏文本并清空撤销历史。
- 增加保留 Rust 缓冲区的 didClose FFI，Dart/Rust ABI v8 双侧握手；fake-LSP 集成测试覆盖旧 URI didClose、新 URI didOpen 与关闭次序。平台原生文件选择器未纳入本切片，使用路径输入对话框。
- 最终门禁：cargo fmt、Flutter analyze 0 issues、FLUTTER_BIN=/tmp/alula-flutter-serial bash init.sh EXIT=0；Rust workspace、Clippy、build_core、Flutter 135/135 全绿。详见 docs/diagnostics/2026-10-30-p02/p02.3-save-as-revert.md。
- 500 MiB 数值优化继续放在 P14；下一切片 P02.4 编码/BOM/EOL。工作树仍有其它用户未提交改动，按 staged snapshot 精确提交。

## 今日会话（2026-10-30）：P02.7 跨文档 WorkspaceEdit 事务

- 完成 P02.7 并关闭 P02/feat-024：ABI v11 增加 Rust 多文档事务 API，所有文档版本、编辑范围均验证成功后再替换 live buffers；任一文档版本/范围错误、重复 ID 或空事务均原子拒绝。
- Dart planner 将 LSP UTF-16 行列映射到原文偏移，处理 LF/CRLF、emoji 代理对、重叠与多位置编辑；工作台提交后同步 Rust 版本、controller、selection、dirty/journal 状态。各文件有独立撤销帧并关联 transaction ID。
- 证据：`docs/diagnostics/2026-10-30-p02/p02.7-workspace-edit-transaction.md`。`bash init.sh` EXIT=0，Rust workspace / Clippy / build_core / Flutter 163 项通过；`cargo fmt --check`、`flutter analyze --no-pub` 0 issues。服务端主动 `workspace/applyEdit` 接收留待 P12。
- 用户确认架构与默认功能优先，500 MiB 数值目标继续安排到 P14。下一阶段 P03 编辑器输入与绘制，开始前按 docs/03 拆分受控子项。提交只含 P02.7 快照，既有工作区改动保留。

## 今日会话（2026-10-30）：P03.1 Rust 有界范围读取

- P03 已按 docs/03 拆分 P03.1–P03.6；当前只完成 P03.1。CodeForge 11.3.0 本机候选控制器拥有完整 Rope 且 `text` getter 物化全文；P03.1 没有选择最终控件。Rust 文档模型继续为权威，组件选择和可视区原型留到 P03.2。
- Rust `TextBuffer` 新增 UTF-16 范围切片与版本/总长度/行数/起点元数据；请求上限 64 Ki units，校验代理对边界，保留 BOM/CRLF，能分页读取 100k 单行。ABI v12 双侧增加 `alula_doc_read_range` / `AlulaDoc.readRange`，没有改变现有写入/保存入口。
- 变更前 GitNexus 影响：TextBuffer CRITICAL（11 符号/8 流程）、DocRegistry CRITICAL（19/13）、AlulaFfi CRITICAL（44/18）。风险未按共享轴豁免；本片仅新增读 API，并由 FFI 对拍和完整门禁回归。
- 定向 Rust（buffer 13/core 19）与 Linux FFI 对拍（Flutter 13）通过；`cargo fmt --all -- --check`、workspace Clippy、build_core、flutter analyze 及 `bash init.sh` EXIT=0，完整 Flutter 165 项通过。详细边界见 `docs/diagnostics/2026-10-30-p03/p03.1-bounded-rust-range-read.md`。
- 工作树里的 workbench、harness、app 配置和其他文档改动未纳入 P03.1。下一切片 P03.2：控件/文本所有权 ADR 与 Rust 分页可视区原型；500 MiB 数值优化继续留 P14。

## 今日会话（2026-10-30）：P03.2 Rust 按行 UTF-16 地址

- 完成 ABI v13 `alula_doc_line_offset` / `AlulaDoc.lineOffset`；Rust Rope 直接将 0-based 行映射为绝对 UTF-16 起点，返回版本/全文长度/行数，Dart 无需扫描全文。BOM、emoji、CRLF、末尾空行和非法行均由 Rust 与 Linux Dart↔Rust 动态库对拍。
- 变更前 GitNexus：TextBuffer CRITICAL（14 符号/10 流程）、DocRegistry CRITICAL（19/13）、AlulaFfi CRITICAL（45/16）；AlulaDoc MEDIUM lower-bound（14 符号，callable value 检查 unavailable）。源码搜索未发现将 AlulaDoc 句柄保存为函数值；风险没有以 shared-axis 结果降低。
- Rust 定向 15 buffer/20 core tests 与 Flutter 14 项 FFI 测试通过；fmt、Clippy、build_core、Flutter analyze 与完整 `bash init.sh`（166 项）全绿。2,000,001 UTF-16 恢复 fixture 约运行 5 分 22 秒后通过。报告 `docs/diagnostics/2026-10-30-p03/p03.2-rust-line-offset-api.md`。
- 下一切片 P03.3：使用 Rust 行地址 + 有界范围读取做编辑控件/文本所有权 ADR 与可视区原型；工作台全文 TextField 仍在，三平台 IME、无障碍和多视图还未通过。P14 才重新制定和开展整机内存数值优化。


## 今日会话（2026-10-30）：P03.6 Rust Tree-sitter 正文着色

- Rust syntax provider 的版本化 UTF-16 tokens 已接到 `.rs` 正文：只在 syntax.version 与 Rust 有界输入窗版本一致、且 Flutter 当前输入文本等于已提交窗口文本时绘制；用二分定位后只建立当前窗口内的 TextSpan。旧版本或尚未 flush 的本地文本保持普通文本；IME composing 下划线与 selection/input controller 状态不改。该子片没有修改 Rust/FFI/ABI/delta 合同。
- 新增 renderer widget fixture 覆盖 token 着色、陈旧版本降级、待提交本地文本降级、composition 下划线。`flutter test --no-pub test/editor_rendering_test.dart` 10 项通过；`flutter analyze --no-pub` 0 issues；完整 `RUST_TEST_THREADS=1 bash init.sh` 退出 0，Rust tests/Clippy/build_core 与 Flutter 227 项通过。精确 staged snapshot `e9b481509a7cade3971e3bbc429dd1fe364ce9f2` 也通过相同全量门禁（Flutter 227 项）；GitNexus 刷新后 staged 为 8 files/18 symbols/0 processes/LOW，全工作树 39 files/24 symbols/299 processes/CRITICAL（含既存修改），图谱遗漏/截断与编辑前共享控件 CRITICAL 风险均已记入阶段报告。
- GitNexus 编辑前 `RustTextInputFieldState`、Workbench `_buildEditor`、`_scheduleSyntaxRefresh` 均为 CRITICAL；`_buildEditor` 影响结果 partial，真实 LSP syntax 方法名 UNKNOWN。源码调用链已核对为 `AlulaLsp.syntax` → Rust LSP/Tree-sitter → Workbench 版本化 cache → `.rs` bounded field；输入/IME/FFI 路径未改。图谱 CRITICAL/partial/UNKNOWN 不作为豁免。
- 本阶段只暂存 syntax feature 的控件、测试、报告与 Workbench 精确 hunk；保留 Workbench 既有用户改动和其它工作树改动。下一步继续 P03.6 绘制架构（minimap/overview 等）；500 MiB 指标按用户调整继续留 P14。


## 今日会话（2026-10-30）：P03.6 当前文档 Find 装饰 provider

- 将已有 Find 结果接入版本化 range painter。WorkBench 对活动 Rust 文档 id/version 记录结果；编辑器视图要求 Rust doc、input window 版本精确一致且无 pending/IME 文本，防止旧装饰误画。二分跳过窗口之前的 UTF-16 命中，只为当前有界窗口建立 decoration。
- Workbench fixture 验证 emoji 前缀后的 `[3,9)`、`[12,18)` 命中与版本门控，并确认切换到另一文档时不会显示原文档命中；lower-bound 纯逻辑用例通过。定向 Find + bounded Workbench 25 项通过；工作树与精确 staged tree `ede714dc8ef6be1af009fa800856e9907d8a7c5d` 的完整 `RUST_TEST_THREADS=1 bash init.sh` 均退出 0（Flutter 229 项），cargo fmt 与 Flutter analyze 0 issues。GitNexus staged 9 files/11 symbols、all 40 files/16 symbols，均为 CRITICAL；增量图谱 affected-process 计数观测范围为 139–325，all 包含既存改动，风险与截断已记录。
- 本次没有重写既有 `_refreshMatches` 全文 Find 算法；renderer 仅拿当前输入窗相交装饰。后续 slices 已分别接入 LSP diagnostic、semantic-token 与 workspace-search providers；Find match enumeration 仍待单独改为 Rust `readRange` 分页。


## 今日会话（2026-10-30）：P03.6 LSP 诊断范围 provider

- LSP publishDiagnostics 缓存保留可选 UTF-16 结束位置与 publication version；对 alula_diagnostics 的 C 签名和 ABI 版本没有改动。Workbench 将当前文档诊断位置映射为 Rust 绝对 UTF-16 ranges，要求 Rust/input/LSP 版本一致并排除 pending/IME 输入；按可见行过滤后复用已有 range painter 绘制 severity 下划线。
- fake-LSP roundtrip 验证新增 JSON 字段；Dart provider fixture 覆盖 emoji UTF-16、跨行范围、severity、stale/unversioned/empty/invalid 与窗口外过滤。定向 Flutter 13 项、`cargo test -p editor-lsp --test roundtrip`、cargo fmt、Flutter analyze 0 issues 通过；完整工作树 `RUST_TEST_THREADS=1 bash init.sh` 全绿（Flutter 232 项）。精确暂存 source tree `06a8c1645aa00eb6d401962830c59b0e0c214560` 的 Rust tests/Clippy/build_core 与离线 `flutter test --no-pub`（232 项）、Flutter analyze（0 issues）也通过。
- GitNexus 编辑前 Diagnostic exact CRITICAL（134 symbols/123 processes/20 modules），reader_loop exact CRITICAL（35/34 direct/7 processes/5 modules）；`_pollLanguageServices` 未入图，已用源码检索并逐段复核真实调用路径。保持 P03.6 in-progress；semantic 与 workspace-search providers 已在后续子切片接入，minimap、sticky scroll、folding 与像素基线仍待完成。报告 `docs/diagnostics/2026-10-30-p03/p03.6-lsp-diagnostic-decorations.md`。


### 最新进展（2026-10-30，P03.6 折叠后的 minimap/sticky viewport）

- 新增零基左闭右开绝对折叠行区间与统一投影，归并嵌套/重叠范围；RustTextInputField 版本化回报折叠范围，Workbench 将同一范围传给 minimap 和 sticky scroll。Minimap viewport marker 按折叠后的可见行比例定位，sticky scope 使用映射回的绝对源行；导航和 UTF-16 文本坐标不变。
- 定向 folding/minimap/sticky 测试 15 项通过；完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` 通过，Flutter 256 项；`flutter analyze --no-pub` 0 issues。`cargo fmt --all -- --check` 通过；精确 HEAD+index 快照 Rust tests/Clippy/build_core、Flutter 256 项 `--no-pub` 与 analyze 0 issues 均通过。
- P03.6 仍未完成：尚需跨平台、多 DPI、主题下的绘制像素对照。报告：`docs/diagnostics/2026-10-30-p03/p03.6-folded-viewport-projection.md`。

### 最新进展（2026-10-30，P03.6 Windows 启动调查与 WSL 基线复核）

- GitNexus 索引刷新后以 `Alula_Code` 为目标查询；Windows runner 的 `OnCreate` 可见，但 Dart `main` 的图谱 impact 为 `UNKNOWN`，已用源码与依赖包搜索核实启动路径。锁定的 `window_manager` 0.5.2 Windows handler 对 `waitUntilReadyToShow` 立即返回，不支持“等待首帧导致挂起”的解释；白屏原因仍未定位，也未改产品源码。
- WSL 下 `RUST_TEST_THREADS=1 PUB_CACHE=/mnt/c/Users/Vegetable/AppData/Local/Pub/Cache bash init.sh --fast` 全绿：Rust workspace tests、`build_core`、Flutter 256 项。起初 `.dart_tool/package_config.json` 指向 Windows SDK，离线 `pub get --enforce-lockfile` 重建后恢复；使用锁文件强制模式。并行 Rust FFI 测试单次失败，串行复跑全绿。
- P03.6 继续 in-progress。Windows Release 的白色客户区仍需桌面手动确认；跨 OS/DPI/主题像素对照未完成。调查报告：`docs/diagnostics/2026-10-30-p03/p03.6-windows-rendering-capture.md`。


## 最新进展（2026-10-31，P03.6 Linux 前台编辑保存复验）

- 在 WSLg Release Alula 中打开隔离 rust-mini 副本，前台将 `main.rs` 替换为 `fn main() { println!("linux-save-ok"); }`，Ctrl+S 后应用状态栏显示已保存；从临时 fixture 回读精确匹配该代码并带末尾换行，SHA-256 `1573fc4d16e7d13ab400d8f58b8ddb89756d59b39fe7b000983d1d1807ecd159`。仓库 fixture 未修改。截图 `docs/diagnostics/2026-10-31-p03/linux-alula-release-edited.png`，报告 `docs/diagnostics/2026-10-31-p03/p03.6-linux-wslg-release-smoke.md`。
- 该结果仅是 WSLg 单次编辑/保存 smoke，不代表原生 DRM、多 DPI/主题像素、IME 或关闭生命周期通过。窗口退出码 0，但 GTK/GDK、FlutterEngineRemoveView 与 rust-analyzer improper-shutdown 告警复现，进程树已退出。P03.6 继续 in-progress。Windows 白窗复测需等显存降低或指定 AMD GPU 后继续。


## 最新进展（2026-10-31，启动门禁修复与字体环境基线）

- 初次 `bash init.sh --fast` 在 `editor-core` 并行 FFI 测试中重现 savepoint 状态异常。GitNexus 刷新后目标测试函数未入图（impact 为 UNKNOWN）；源码检索确认 `rust_owned_savepoint_roundtrip_over_ffi_keeps_document_version` 使用 ID 92,814，而 `bounded_line_windows_over_ffi_share_a_rust_snapshot` 将 92,813 + 1 分配给长行文档，形成并行共享全局注册表碰撞。将 savepoint fixture ID 改为 92,850；未改产品逻辑。单测、串行 workspace tests 和修复后的并行 `bash init.sh --fast` 均通过；后者 Rust workspace tests、build_core、Flutter 256 项全部通过，`cargo fmt --check` 通过。
- WSLg 字体/显示基线登记于 `docs/diagnostics/2026-10-31-p03/p03.6-linux-wslg-release-smoke.md`：X11 2560×1440、96 DPI；monospace/Cascadia/Consolas fontconfig 映射、中文 glyph fallback 以及截图窗口尺寸已记录。仅为 WSLg 环境数据，不是原生 Linux 或跨平台像素对照。
- Windows 显存只读复查为 RTX 5080 14,668/16,303 MiB，空闲 1,310 MiB，未满足降低 2–4 GiB 的复测条件；没有更改 GPU 选择或关闭进程。Windows 渲染结果仍未定论，P03.6 保持 in-progress。

## 最新进展（2026-10-31，P03.6 固定 Code-OSS WSLg 参考）

- 从固定 Code-OSS commit `4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e`（1.145.0 / Electron 43.8.3）建立临时 detached worktree；同一 WSLg 2560×1440、96 DPI 下将窗口设为 1280×720，打开含 `fn main() { println!("linux-save-ok"); }` 的隔离 rust-mini 文件。参考截图为 `docs/diagnostics/2026-10-31-p03/code-oss-1.145.0-linux-wslg.png`，SHA-256 `cd1b0217b2f93003089364eb5dcb62db86efef97deab036c353acab564b9ef9a`。
- 与同尺寸 Alula WSLg 截图相比，Code-OSS 显示菜单/命令区、活动栏、Explorer、文件 breadcrumb、gutter 与状态栏；Alula 当前截图缺少这层 workbench chrome。这是明确的架构和绘制差距，不是像素验收通过。Code-OSS 为源码开发版且未完整构建内置扩展，扩展禁用、未登录；因此只登记为工作台 shell 参考。
- Code-OSS 窗口正常关闭，临时进程、user-data、扩展目录与 Git worktree 已清理。P03.6 保持 in-progress；Windows 渲染需待显存释放 2–4 GiB 或用户指定 AMD GPU 后复测，原生 DRM 和多 DPI/主题像素门仍未完成。

## 最新进展（2026-10-31，P03.6 WSLg Windows 字体解析）

- WSLg 默认 fontconfig 未检索 `/mnt/c/Windows/Fonts`。建立临时进程级配置后，`fc-match` 将 Cascadia Code 解析为 `CascadiaCode.ttf`、Consolas 解析为 `consola.ttf`；没有复制字体或修改系统配置。以该配置、隔离 HOME 启动当前 Linux Release 并打开原有 rust-mini fixture，磁盘内容 hash 未变；截图 `docs/diagnostics/2026-10-31-p03/linux-alula-cascadia-wslg.png`，SHA-256 `8a9239e55039a34781f0387f2686b86d8b827cbb3b4509988c5b97973558b57e`。
- 这只验证当前 WSLg 进程可以用到 Windows 字体，不是 DRM、多 DPI 或像素等价证据。关闭 exit code 0，但 `notify error: No path was found`、GLib/GDK critical 与 `FlutterEngineRemoveView` 告警再次出现；P03.6 保持 in-progress。

## 最新进展（2026-10-31，P03.6 WSLg 2× GTK 缩放）

- Linux Release 在独立 HOME 下用 `GDK_SCALE=2` / `GDK_DPI_SCALE=1` 启动，窗口 1280×800 物理像素，目标文件仍为 `fn main() { println!("linux-save-ok"); }` 且 SHA-256 不变。截图 `docs/diagnostics/2026-10-31-p03/linux-alula-gdk-scale-2x-wslg.png`（SHA-256 `9b73988e6fa04280a38d03e52038dc360437ba483cc344c348a0c4ca294c85a2`）。
- WSLg integer-scale 2× 视口绘制正常；不是 125% fractional DPI、Windows/macOS、native DRM 或跨平台像素验收。关闭仍有 `No path was found` 与 GTK/Flutter teardown 告警。报告已登记，P03.6 保持 in-progress。

## 最新进展（2026-10-31，P03.6 WSLg 折叠/viewport/sticky 实窗）

- 建立 48 行隔离 Rust fixture 并用 xwd 按 Alula window id 直接采集 1280×720 客户区。折叠 `main` 后正文只显示折叠头和尾部行 45–49，minimap viewport tint 由 y=104–436 扩展到 y=104–686；继续在函数内滚动后 sticky header 显示 `main` / `Function`。折叠前后 fixture hash 均为 `594da06828d91c2dd8deca8a5b6d8e30dae58326d08f06266e4435c920a11295`。PNG 与 hash 见 `docs/diagnostics/2026-10-31-p03/p03.6-linux-wslg-release-smoke.md`。
- 该实窗证据加强 WSLg 几何验证，但不能代替 Windows/macOS/native DRM、多 DPI/主题或无障碍验证。窗口关闭 exit 0，`No path was found` 及 GTK/Flutter teardown 告警仍在。P03.6 保持 in-progress。

## 会话基线复核（2026-10-31）

- 按启动守则重跑 `bash init.sh --fast`，EXIT=0：Rust workspace tests、`build_core`、Flutter 256 项通过。
- 当前 WSL 会话没有 `nvidia-smi`，且没有 `powershell.exe` / `pwsh.exe` / `cmd.exe` 互操作命令，因此无法刷新 Windows GPU 空闲量；未重跑 Windows 白窗诊断。P03.6 仍需在 Windows 释放 2–4 GiB 显存或指定 AMD GPU 后复测；该手动平台门未由旧显存样本替代。


## P03.6 implementation close / P03.7 start（2026-10-31）

- 本轮完整 RUST_TEST_THREADS=1 bash init.sh EXIT=0（Rust workspace tests、Clippy、build_core、Flutter 256 项）；cargo fmt --all -- --check 与 flutter analyze --no-pub 也通过。P03.6 的实现与本地自动化门关闭。

- 按用户要求，设备依赖验收作为待验证项继续登记，不记作通过：Windows Release 客户区（历史自动捕获白窗且同机 Flutter 默认窗口也白窗）、原生 DRM Linux、macOS 原生交互以及跨 OS/DPI/主题像素对照移交 P14/P15。

- P03.7 已启动，当前目标是同一 DocumentId 多视图的共享文本/savepoint 与独立 view state、无障碍语义，以及已有 10k/50k/长行与关闭释放的证据审计；需逐项按 docs/03 补实现和证据。

## P03.7 shared-document views and editor semantics（2026-10-31）

- Workbench uses one shared Rust document/savepoint/undo/LSP model for matching `DocumentId`s while each editor view owns its bounded input window, selection history, fold state, scroll controller, and group-specific focus node. All document mutation paths refresh sibling windows and map sibling UTF-16 selections through the edit operations.
- Session restore now rebuilds repeated matching IDs as shared views. Conflicting duplicate journal text/options are retained in a separate untitled recovery draft with a visible notice. Closing one view keeps the Rust document live; closing the last view sends `didClose` and releases the Rust document/undo state.
- Editor semantics now label a field with file and group; fold controls expose collapse/expand labels, state, line hints, and semantic tap actions. The existing gutter pointer path remains.
- `app/test/workbench_multi_view_test.dart` covers shared identity/content, per-view input/scroll/focus and selection, edit broadcast, save, single-view close, last-view close/reopen, same-ID session restore, conflicting journal recovery, and searching/editing/saving the tail of a 50,000-line fixture in two views. The provided `fn main() { println!("linux-save-ok"); }` is the first line of the large-file save fixture. The large-window rebase regression also catches and guards transient multiple scroll-position painting.
- `app/test/workbench_bounded_input_test.dart` now covers tail edit/save for a 50,000-UTF-16-unit single line in two views; `app/test/editor_folding_test.dart` covers semantic collapse/expand actions. Both large-file fixtures verify both views resolve to the same saved Rust text. Full `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` passed: Rust workspace tests, Clippy, build_core, Flutter 260 tests. `cargo fmt --all -- --check`, `flutter analyze --no-pub` (0 issues), and targeted `git diff --check` passed. Evidence: `docs/diagnostics/2026-10-31-p03/p03.7-multiview-accessibility.md`.
- P03.7 remains in progress. Windows Server 2025 hosted visible-client capture, Unicode MSAA, 14 desktop tests, simulated Flutter IME, and graceful close pass in run 41153011276; Windows 11 client-specific Narrator/native IME/DPI-theme/package gates and Linux native DRM remain pending. macOS native testing remains unavailable; first establish Linux/Windows usability, then prepare its test package without claiming native macOS verification. WSLg does not count as native DRM evidence.

## P03.7 CI stage-snapshot correction（2026-10-31）

- Commits `bfbdc2c` and `96872ca` were pushed to `codex/vscode-parity-p00`. GitHub Actions run `41108610038` failed on Linux, Windows, and macOS because the partial P03.7 snapshot retained a `Listener` call to `_onEditorPointerDown` while its definition remained in the unstaged P04 work. This is a phase-staging compile error, not evidence of an OS-specific failure.
- A follow-up correction removes that P04 pointer listener from the P03 snapshot; its staged diff is one `WorkbenchPage` symbol with low GitNexus impact. Local full `init.sh`, `cargo fmt --check`, and `flutter analyze` passed before the CI snapshot issue was found. The correction passed GitHub Actions run `41109679662`: Linux x64 and Windows x64 Release build/hosted launch smoke, plus macOS ARM64 analyze/tests/Release/ad-hoc sign/launch/zip. Artifacts: `alula-linux-x64-d5319369c5b5d569954e0d816daf325f3bc12a51`, `alula-windows-x64-d5319369c5b5d569954e0d816daf325f3bc12a51`, `alula-macos-ARM64-d5319369c5b5d569954e0d816daf325f3bc12a51`. Hosted smoke is not native Linux DRM or visible Windows UI validation; manual P03.7 device checks remain pending.
