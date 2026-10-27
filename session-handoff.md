# session-handoff.md — 会话交接

> Last Updated：2026-10-28（第十七轮：补齐 macOS Web Archive 回放 runner；Mac 实测与 P00.4 阻塞仍未解除）

## 项目一句话

Flutter桌面工作台 + Rust编辑核心，低内存与资源压力下稳定编辑/保存优先。
用户最新要求：执行docs/10中的全功能复刻计划并分阶段提交；P00.1、P00.2 已完成，P00 总包仍进行中。

## Current Objective

P00.1、P00.2、P00.3 已完成；P00.4 三项限时风险实验均有部分证据。Web 实验包括 Windows Flutter/WebView2 与 Linux WebKitGTK 原生引擎层结果；本轮为 macOS WKWebView 新增了 Web Archive 回放 runner，但尚无 Mac 构建/运行结果。Linux Flutter/WPE/CDP、macOS 实测及 Microsoft 官方服务互通仍有阻塞。P00.4=blocked，feat-022/P00=in-progress；P01–P15 尚未开始。
当前任务与DoD唯一权威：docs/03当前主线；docs/10为范围/架构/方法，docs/11为需求矩阵。
旧Phase/W里程碑只作历史；原型done不继承为1:1完成。P00.4不能签收done。

## What Changed

- P00.4 实验1：独立 Flutter Windows CodeForge 11.3.0 探针通过真实 Microsoft Pinyin composition/commit/cancel/Latin 输入；4 个 widget tests 覆盖 composition undo、Delta 多光标插入/撤销与 10k 行视口。见 p00.4-editor-adr.md 与 p00.4-editor-evidence.json。CodeForge 仅保留为 P03 候选。
- P00.4 实验2：独立 Flutter Windows WebView2 探针以 `flutter_inappwebview 6.1.5` 验证按需创建/销毁、CDP MHTML 导出与同一 WebView 重载；另在 WSLg 上以 GTK 原生探针验证 WebKitGTK 页面快照、MHTML 保存/重载、Web Inspector 和短时进程生命周期。Linux 结果不代表 Flutter/WPE 集成或 Chrome CDP；macOS 未验证。证据见 p00.4-web-adr.md、p00.4-web-evidence.json、p00.4-linux-webkitgtk-evidence.json 及 p00.4-linux-webkitgtk-run/。
- P00.4 实验3：固定 Code-OSS 产品配置与本机 Microsoft VS Code 1.142.0 Stable 产品配置对照；官方文档确认 Settings Sync 不支持自定义后端，Marketplace 不允许 Code-OSS fork。未登录、未注册 OAuth 应用、未调用 Marketplace API、未创建隧道。见 p00.4-services-adr.md、p00.4-services-evidence.json。
- 第十五轮复核：固定 SHA 与 1.145.0 官方 Insiders URL 仍 404，latest 返回 1.144.0 不同 revision；Marketplace fork 禁止与 Sync 无自定义后端政策保持。Linux 插件路线为 v6.2 beta + 独立 WPE 包；当前 Ubuntu WSL 无 Linux Flutter/Dart 与 WPE dev SDK。证据补充在 reference-acquisition.md、p00.4-web-adr.md、p00.4-services-adr.md。
- 第十七轮：重验 pinned commit 下载 URL 与官方 CLI 的 1.145.0 版本解析 GET 均为 404；微软维护的 `vscode-test` helper 与 VS Code CLI 更新实现使用同一 commit URL，公开官方路径没有发现可替代的固定版本端点。该结果不覆盖所有内部/企业发行渠道，记录在 `reference-acquisition.md`。
- 第十七轮：新增隔离 macOS Flutter 工程、WKWebView Web Archive 保存/同 view 重载验证、页面标记输出、`footprint -targetChildren` 采样脚本及 macOS 15 GitHub Actions runner。它们尚未在 Mac 执行，不是平台通过证据；Safari Web Inspector 附着仍是独立手动步骤。细节见 `p00.4-web-adr.md`、`tools/web-engine-probe/README.md` 与 `.github/workflows/p00-web-engine-macos.yml`。
- GitNexus staged `detect-changes` 为 risk=medium（37 files/20 symbols/5 flows），五条受影响流程均在隔离 Web Probe 的 build、导出、重载、销毁与自动回放；all scope 还包含工作区用户既存改动。`_toggleWebView` impact 为 HIGH，该方法的状态文案改动已撤回；`State.build` impact 为 UNKNOWN，确认是 Flutter 覆写后按动态回调路径人工审阅。其余探针回放方法 impact 为 LOW。分析器报告的 process graph truncation 仍存在。
- 第十六轮完成 Windows Git Bash `cargo fmt --check && bash init.sh`，退出码 0；单独 Flutter `analyze` 也为 0（No issues found）。完整门禁覆盖 Rust workspace tests、core 构建、clippy 零警告和 Flutter 122 项测试；RECOVERY-01 接受 2,000,001 UTF-16 单元后仍只从磁盘恢复 5 单元，现状故障夹具保持预期。
- 第十六轮仅更新进度/交接文档，没有修改 `app/`、`crates/` 或产品依赖。用户工作区中原有的未提交修改继续保持未暂存、未纳入提交。
- 本轮 GitNexus `detect_changes` all/staged 均 risk=low；staged 为 5 个文档文件、0 条受影响流程。结果对象无 `partial`/`truncated` 字段；索引流程图本身仍截断（187 flows，406 个入口候选丢弃 206 个、98 个 callee 跳过、2 次 walk 达预算）。
- P00.4 标记 blocked；feat-022/P00 保持 in-progress。没有改动 app/ 或 crates/ 产品代码。

- 固定vscode SHA 4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e（1.145.0开发版，非Stable）；
  vscode-docs SHA da213552439825628e0ab958dbde1e413dbc36bf。
- 总计划16实施包，342条功能族验收/14边界决策；另有源目录/全部90个非AI产品manifest及下载预置调试器清单。
- P00.2 exporter从固定 SHA 的 14,811 个 tracked TS/JS 文件中解析 1,490 个候选源文件，导出 AST、95 个扩展 manifest、`product.json` 和隔离运行时 registry，共 12,958 条唯一记录；2,140 条为运行时独有登记。
- 当前保留 6,828 条未决登记/路由，不能计作覆盖率。运行时探针观测 2,684 个命令、1,289 个配置键、5 种语言；client-only lane 未加载默认扩展 payload，运行时产品扩展数为 0。
- 默认随附扩展全部纳入；终端/JS调试/Markdown rich-Mermaid/Notebook宿主/集成浏览器/Sync/Cloud Changes/Ports不漏。
  外接AI排除；需用户另装的Python/Jupyter/Remote等业务provider不冒充默认能力。
- 官方服务互通是条件验收，不能因联网删需求；自建替代不等于官方1:1完成。
- 旧未完成feature保留evidence并退回not-started/legacy；新执行轨为vscode-builtin-parity，单feature推进。
- Startup发现原工作树Flutter编译错误，按规则仅一行修复_findRenderEditableOf递归误调；impact LOW。

## Verification Evidence

- P00.3：Windows Git Bash `bash init.sh --fast` EXIT=0、`bash init.sh` EXIT=0、`cargo fmt --check` EXIT=0、`flutter analyze` EXIT=0。完整门禁包含 Rust workspace tests、clippy 零警告、build_core 与 Flutter 122 项测试全绿。
- 四个夹具均实际运行：UNDO-01 两份 Alula 文档各自撤销时互相串写；RECOVERY-01 接受 2,000,001 UTF-16 单元但恢复为磁盘 5 单元；CLOSE-01 文档关闭后 workspace LSP 仍活着；SLOW-01 provider 延迟与调用方等待均为 1,200ms。
- 固定 Code-OSS 1.145.0 / Electron 43.8.3 的隔离实例验证双文件 undo 每个文档恢复自己的原始文本。参考行为输出与 Alula 观测见 `p00.3-current-state.json`。
- 页面证据：`reference-workbench.png` 与真实 Alula `alula-welcome.png`。窗口均 1505×1005、DPR 1.25、深色；Alula 画面为中文，固定参考为英文，未声称文字级视觉一致。
- GitNexus `detect-changes --scope all`：43 files/40 symbols/3 flows，risk=medium，来自其它既存工作区改动；staged scope：14 files/24 symbols/0 flows，risk=low，仅有 characterization fixtures、fake LSP、证据与状态文档。隔离索引报告 process graph 截断，缺失 flow 不作无影响证明；详见 `p00.3-replay.md`。
- 更早的 WSL 直接运行失败是 runner 不兼容，不是产品测试失败；最终 Windows Git Bash 的全量 DoD 已通过。早期输出保留在 `p00.3-validation.log`（ignored，本轮退出码以以上可重放命令为准）。
- P00.4 探针：Windows Git Bash `flutter analyze` EXIT=0、`flutter test` EXIT=0（1 项）、Windows Release build EXIT=0；详见 web evidence。根目录 `cargo fmt --check`、`bash init.sh`、单独的 `flutter analyze` 均 EXIT=0，完整 Flutter 测试通过（122 项）。
- GitNexus 索引更新后执行完整 `detect-changes --scope all`，结构化结果无 `partial`/`truncated`：107 files / 271 symbols / 17 flows，risk=critical；staged scope 为 78 files / 255 symbols / 17 flows，risk=critical。staged 受影响流程都落在独立探针的 Flutter Win32Window 生命周期模板或 Web 自动回放，没有 app/ 或 crates/ 产品代码；全量 scope 还包含用户既存工作区改动，未纳入阶段提交。Analyzer 的 process graph 仍有截断（187 flows；393 个候选入口中 193 个未入选、98 个 callee 被跳过、2 次 walk 达到预算）；缺失 flow 不视作无影响。
- 本轮 `bash init.sh --fast` EXIT=0；新增 GTK runner `bash -n`、Python `py_compile` 和完整相对路径重放均 EXIT=0，九阶段证据齐全。MHTML 每次生成边界不同，页面截图字节一致，MHTML MIME 头与页面标记重放一致。
- 第十六轮 `cargo fmt --check && bash init.sh` EXIT=0，单独 Flutter `analyze` EXIT=0；完整门禁包含 Rust 测试、clippy、core 构建与 Flutter 122 项测试。
- 第十七轮根目录 Windows Git Bash `cargo fmt --check && bash init.sh` EXIT=0；单独主应用 Flutter `analyze` EXIT=0（No issues found）。探针 `dart format`、Flutter `analyze`、`flutter test` 均 EXIT=0；Mac 编译/执行未运行。Mac runner Bash 脚本 `bash -n` 与 workflow YAML 解析通过。
- 本轮 GitNexus `detect_changes` 的 all 与 staged scope 均为 risk=high；staged scope 覆盖 22 个文件与 8 条受影响流程，八条均为 GTK 探针生命周期/采样路径。结果对象没有 `partial`/`truncated` 字段；索引构建日志报告 process graph 被截断：187 flows，406 个入口候选丢弃 206 个，98 个 callee 跳过，2 次 walk 达预算。all scope 同时涵盖未暂存用户改动。
- 本轮没有 app/ 或 crates/ 产品实现变更；Linux WebKitGTK 证据作为 P00.4 scoped follow-up 提交，不把 GTK/WebView 证明写成产品能力；其它既存工作区改动不纳入提交。

## Blockers / 待核实前提

- P00.1：2026-10-28 重验官方 `latest/insider` 指向 1.144.0 的其他 revision token `abc2b20cb3e724689f78f5d2a3c231589b25483c`；固定 SHA 与 1.145.0 下载路径仍 404。Code-OSS client-only build/start 已完成；remote 子树依赖未安装，Copilot/remote lane 未构建；不能把此源码构建称作微软发行物。
- P00.2：client-only 运行时没有加载随附扩展 payload；静态 95 个 manifest 与运行时 0 个产品扩展的差异保留。6,828 条未决记录和候选映射必须在后续逐项复核，不计为已覆盖。
- P00 需固定参考的 Microsoft 同 SHA 发行物尚不可得；Code-OSS 与微软发行配置差异不能抹平。
- P00.4 实验1只在 Windows 验证；macOS/Linux IME、Rust 往返/背压、Release 内存、完整 Unicode/EOL 与无障碍仍未验证。
- P00.4 实验2：Linux 原生 WebKitGTK 的 MHTML/快照/Inspector/单轮内存已有 WSLg 证据；Flutter Linux/WPE 集成（上游当前需 v6.2 beta + WPE 2.0）、Chrome CDP 互操作、硬件加速及 docs/04 长时多轮产品内存协议仍未实测；macOS WKWebView/Web Archive/Safari Inspector 和内存仍未实测。
- P00.4 实验3：官方 FAQ 明确 Marketplace 不允许 Code-OSS fork 访问，Microsoft 扩展许可限定 VS family；Settings Sync 不支持自定义后端。本地正式版 1.142.0 产品身份字段不属于固定 1.145.0 Code-OSS 参考。需解决许可/产品身份边界才可声称官方服务 1:1。
- 原Windows .gitnexus元数据在WSL路径无效。本轮隔离索引位于/tmp/alula-plan-gitnexus，不修改原缓存；
  使用 GITNEXUS_STORAGE_ROOT=/tmp/alula-plan-gitnexus node .gitnexus/run.cjs ... 。缓存临时丢失可重建。
  代码图谱process发现可能截断，缺失flow不等于无调用；UNKNOWN先做文本确认。

## Files

- docs/10-VSCode无插件全功能复刻总计划.md、docs/11-VSCode功能对照矩阵.md、docs/plans/：新计划及官方源证据。
- docs/diagnostics/2026-10-27-p00/reference-acquisition.md：P00.1固定参考获取与下载探测记录。
- docs/diagnostics/2026-10-27-p00/atomic-contributions.md：P00.2统计、运行时差异和未决项；`atomic-contributions.json` 是逐项 ledger。
- docs/diagnostics/2026-10-27-p00/p00.3-replay.md、`p00.3-environment.json`、`p00.3-current-state.json`、`alula-welcome.png`：P00.3门禁、环境、现状夹具输出与页面基线。
- app/test/p00_risk_fixtures_test.dart、crates/editor-core/tests/p00_workspace_close.rs、crates/editor-lsp/tests/p00_slow_completion.rs：四个现状风险复放测试及专用 fake LSP。
- tools/vscode-parity/export-atomic-contributions.mjs、runtime-probe/：P00.2可重放导出器和临时探针。
- docs/diagnostics/2026-10-27-p00/p00.4-editor-adr.md、p00.4-editor-evidence.json 与 tools/editor-ime-probe/：P00.4实验1决策、数据、重放探针及真机截图。
- docs/diagnostics/2026-10-27-p00/p00.4-web-adr.md、p00.4-web-evidence.json、MHTML/PNG/进程树采样与 tools/web-engine-probe/：P00.4实验2 Windows 子实验。
- docs/diagnostics/2026-10-27-p00/p00.4-linux-webkitgtk-evidence.json、p00.4-linux-webkitgtk-run/ 与 tools/web-engine-probe/linux/：P00.4 Linux WebKitGTK 原生引擎补充及可重放 GTK 探针。
- docs/diagnostics/2026-10-27-p00/p00.4-services-adr.md、p00.4-services-evidence.json：P00.4实验3端点、正式版配置差异、Marketplace/Sync 阻塞。
- docs/03：新P00–P15状态/依赖/DoD；docs/09与README标历史范围与新入口。
- feature_list.json、progress.md、本文件：可续作状态。
- app/lib/workbench/workbench_page.dart：本轮仅_findRenderEditableOf中递归调用一行；其余既存修改归用户。
- docs/diagnostics/2026-10-27-parity-plan/：验证日志。

## Next Session

1. 按 AGENTS 启动流程读取本文件/progress Current State，检查 GitNexus 状态并使用 Windows Git Bash 跑 `bash init.sh --fast`。
2. P00.4 当前 blocked；不要开 P01（docs/03 依赖 P00）。先在 Mac runner 上执行 `.github/workflows/p00-web-engine-macos.yml` 并检查 artifact；需手动确认 Safari Web Inspector attach。Linux Flutter/WPE/CDP 仍需单独 runner。
3. Microsoft 官方身份/许可路径仍没有授权结论。用户尚未回复“保持严格 1:1 / 批准不等价替代 / 提供授权或 runner 访问信息”的问题；按严格标准保留阻塞，直到明确决策。
4. 工作流必须推到 GitHub PR/分支后才会获得 Mac 运行结果；当前本地提交分支尚未推送。不要将未运行的 workflow 写成 Mac 证据，也不要用 Linux GTK 结果代替 Flutter/WPE。
4. 复用固定 SHA 工作树 `E:\_alula_vscode_ref_4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e` 与 P00.1/P00.2 证据。

## 已知风险（尚未因本轮计划而修复）

全局UndoStack跨文档风险；>2M字符未保存内容不入journal；同步FFI与800ms全量轮询；
Tree-sitter Rust-only/全文parse；lsp_stop仅detach；watcher全事件重读；快速打开/搜索硬上限。
详见docs/10 §2，不把静态风险冒充已运行复现。
