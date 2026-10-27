# session-handoff.md — 会话交接

> Last Updated：2026-10-28（第二十三轮：P00.3 夹具复放与 WPE 首帧轮询）

## 项目一句话

Flutter桌面工作台 + Rust编辑核心，低内存与资源压力下稳定编辑/保存优先。
用户最新要求：执行docs/10中的全功能复刻计划并分阶段提交；P00.1、P00.2 已完成，P00 总包仍进行中。

## Current Objective
P00.1、P00.2、P00.3 已完成；P00.4 三项实验的 ADR/证据齐备但仍 blocked。Web 实验含 Windows Flutter/WebView2、Linux WebKitGTK，以及 WPE 2.52.6 源码构建。无等待旧首帧 PNG 是全透明缓冲；检查确认 pinned Linux 插件只复制当前像素缓冲、不等待 WPE 帧回调。独立探针已在 DOM 查询前轮询页面标题蓝色像素；三次默认 sandbox 冷启动均取得初始/MHTML 页面截图，最终版本一次重试后成功。GBM 继续关闭，探针结果不证明产品帧同步。WPE 2.54.2/2.48.3 发行包构建失败，Linux CDP/Inspector 不支持，macOS 与 Microsoft 官方服务身份/许可仍未解决。feat-022/P00=in-progress，P01–P15 未开始。
当前任务与DoD唯一权威：docs/03当前主线；docs/10为范围/架构/方法，docs/11为需求矩阵。
旧Phase/W里程碑只作历史；原型done不继承为1:1完成。P00.4不能签收done。

## What Changed

- 第二十三轮：按用户选择的 Windows Git Bash 重跑 P00.3 `build_core`、Flutter fixture 与两个 Rust fixture 命令；四项夹具全部通过，输出与既有记录一致，超大文档用例约 2 分 03 秒。WPE 旧首屏的 732,160 个 RGBA 像素均透明；插件只复制当前缓冲。独立探针改为 DOM 查询前检查标题蓝色像素并有界重试。analyze/test/Linux Release build 通过，三次新的默认 sandbox 冷启动均取得 initial/MHTML 截图，最终版本的一次回放第 2 次截图才得到目标帧。P00.4 仍 blocked，未动产品代码。证据见 `p00.4-linux-wpe-evidence.json` 与三个 `p00.4-linux-wpe-2.52.6-frame-poll-run*/`。
  提交前 Windows Git Bash `cargo fmt --check`、完整 `bash init.sh`、单独 `app/ flutter analyze` 均 EXIT=0；完整脚本覆盖 Rust workspace tests、Clippy、build_core 和 Flutter 122 项测试。
  GitNexus `detect-changes` all risk=medium（91 files/14 symbols/1 flow，含既有 workbench 变更），staged risk=medium（62 files/4 symbols/1 flow，Build→`_hasProbeHeadingPixel`）；无 HIGH/CRITICAL。流程图截断提示 190 个入口候选未入选、123 个 callee 因预算跳过、2 次 walk 达预算，不能把缺失 flow 作为无影响证据。
- 第二十二轮：以 `--cap-add SYS_ADMIN --security-opt seccomp=unconfined` 本地容器复测默认 WebKit sandbox；探针用户 UID 1000、sandbox-disable 环境变量 unset、GBM disabled。`unshare` 成功，bwrap/WebProcess 进程可见，MHTML 重载截图通过；初始 DOM marker 虽通过，首帧 PNG 背景空白。延迟 500ms/2s 未修复，探针源码保持原状。证据见 `p00.4-linux-wpe-2.52.6-default-sandbox-run/`。

- P00.4 实验1：独立 Flutter Windows CodeForge 11.3.0 探针通过真实 Microsoft Pinyin composition/commit/cancel/Latin 输入；4 个 widget tests 覆盖 composition undo、Delta 多光标插入/撤销与 10k 行视口。见 p00.4-editor-adr.md 与 p00.4-editor-evidence.json。CodeForge 仅保留为 P03 候选。
- P00.4 实验2：独立 Flutter Windows WebView2 探针以 `flutter_inappwebview 6.1.5` 验证按需创建/销毁、CDP MHTML 导出与同一 WebView 重载；另在 WSLg 上以 GTK 原生探针验证 WebKitGTK 页面快照、MHTML 保存/重载、Web Inspector 和短时进程生命周期。Linux 结果不代表 Flutter/WPE 集成或 Chrome CDP；macOS 未验证。证据见 p00.4-web-adr.md、p00.4-web-evidence.json、p00.4-linux-webkitgtk-evidence.json 及 p00.4-linux-webkitgtk-run/。
- P00.4 实验3：固定 Code-OSS 产品配置与本机 Microsoft VS Code 1.142.0 Stable 产品配置对照；官方文档确认 Settings Sync 不支持自定义后端，Marketplace 不允许 Code-OSS fork。未登录、未注册 OAuth 应用、未调用 Marketplace API、未创建隧道。见 p00.4-services-adr.md、p00.4-services-evidence.json。
- 第十五轮复核：固定 SHA 与 1.145.0 官方 Insiders URL 仍 404，latest 返回 1.144.0 不同 revision；Marketplace fork 禁止与 Sync 无自定义后端政策保持。Linux 插件路线为 v6.2 beta + 独立 WPE 包；当前 Ubuntu WSL 无 Linux Flutter/Dart 与 WPE dev SDK。证据补充在 reference-acquisition.md、p00.4-web-adr.md、p00.4-services-adr.md。
- 第十七轮：重验 pinned commit 下载 URL 与官方 CLI 的 1.145.0 版本解析 GET 均为 404；微软维护的 `vscode-test` helper 与 VS Code CLI 更新实现使用同一 commit URL，公开官方路径没有发现可替代的固定版本端点。该结果不覆盖所有内部/企业发行渠道，记录在 `reference-acquisition.md`。
- 第十七轮：新增隔离 macOS Flutter 工程、WKWebView Web Archive 保存/同 view 重载验证、页面标记输出、`footprint -targetChildren` 采样脚本及 macOS 15 GitHub Actions runner。它们尚未在 Mac 执行，不是平台通过证据；Safari Web Inspector 附着仍是独立手动步骤。细节见 `p00.4-web-adr.md`、`tools/web-engine-probe/README.md` 与 `.github/workflows/p00-web-engine-macos.yml`。
- 第十八轮：新增 Flutter Linux runner、Debian sid WPE 构建 workflow、Xvfb replay 与 `mem-probe` 采样；锁定插件 beta 6.2.0。Windows Git Bash analyze/test/Release build 与 WebView2 CDP/MHTML 自动回放通过；新增 1,438-byte MHTML、截图与五阶段内存 JSON。Linux workflow 尚未运行，静态契约显示其 WPE 插件没有 CDP handler，Inspector 标志不支持 Linux。详见 `p00.4-linux-wpe-evidence.json`、`p00.4-web-beta-evidence.json` 与 `p00.4-web-adr.md`。
- 第十八轮收尾：Windows Git Bash `bash init.sh` EXIT=0，Rust workspace tests、clippy、build_core 与 Flutter 122 项测试通过；恢复夹具的 2,000,001 UTF-16 输入在约 2 分钟后完成，输出仍为预期的磁盘 5 单元恢复结果。Git Bash 启动时 `.bashrc` 编码告警但不影响命令成功。
- 第十八轮 GitNexus `detect-changes --scope all` 为 risk=low（61 files/58 symbols/0 flows），staged scope 为 risk=low（32 files/42 symbols/0 flows）；all 包含用户原有工作区改动。两个结果均未报告 partial/truncated，但索引过程图本身有截断：186 flows、208 个入口候选未纳入、98 个 callee 被跳过、2 次 walk 达预算；缺失流程不视为无影响。
- 第十九轮：在本地临时 sid 包环境跑 Flutter 3.47.8 / Dart 3.13.7 的 `flutter analyze` 与 `flutter test`，均通过。Release 构建在 `flutter_inappwebview_linux 0.1.0-beta.1` 的 `WPE_SETTING_DISABLE_ANIMATIONS` 未定义错误处失败；WPE 2.54.2 头文件提供 `WPE_SETTING_REDUCED_MOTION`。未修改插件源码或增加编译兼容宏，无 Xvfb runtime replay。证据见 `p00.4-linux-wpe-build.log` 与 `p00.4-linux-wpe-evidence.json`。
- 第二十轮：WPE 官方 2.54 migration notes 确认旧动画 setting 已替换；pub.dev 当前只发布 Linux beta.1。Debian Trixie 2.48.3 的 FDO fallback 在混合容器中仍因 `webkit_web_view_get_theme_color` 未声明而构建失败。没有宏或插件源码补丁，无 runtime；证据见 `p00.4-linux-wpe-trixie-compat.log` 与更新后的 Web ADR。
- 第二十一轮：官方 WPE 2.52.6 release 源码在 Bookworm 临时容器以 WPEPlatform/Headless/MHTML 配置构建成功，Flutter probe Release build 与 Xvfb MHTML/PNG/destroy replay 通过。容器不允许 bwrap namespace，因此关闭 sandbox；GBM/DMA-BUF 路径不提供截图像素，设置 `WEBKIT_DMABUF_RENDERER_DISABLE_GBM=1` 后软件缓冲回放通过。完整构建参数、警告、内存数据和边界见 `p00.4-linux-wpe-2.52.6-build.md` 与 `p00.4-linux-wpe-2.52.6-run/`。
- 本轮 `mem-probe` Linux Release build 成功；探针 `flutter pub get/analyze/test/build linux --release` 均退出码 0。脚本现在兼容 source-installed WPE pkg-config 记录，并把 sandbox/GBM overrides 写入环境证据。
- P00.4 仍 blocked：macOS、官方服务身份/许可、Linux 默认 sandbox/硬件渲染/CDP/Inspector 未解决；P01 仍 not-started。无 `app/`、`crates/` 或产品依赖改动。
- 本轮 GitNexus reindex：201 flows；188 个入口候选未进入排名、123 个 callee 因分支预算跳过、2 次 walk 达预算；缺失 flow 不视为无影响。提交前 detect-changes all risk=low（37 files/33 symbols/0 processes），staged risk=low（8 files/17 symbols/0 processes）。
- 首次 Linux CMake 配置还发现缺少 `libsecret-1-dev`，已加入 Linux workflow 和 README 依赖清单。临时容器以 Bookworm 衍生镜像为基础安装 sid 包，OS 文件报告 `forky/sid`，不等同于干净的 `debian:sid`。
- GitNexus 在 Flutter 生成文件出现后重建为 up-to-date。`WebEngineProbePage` impact 为 LOW（1 个直接调用、0 流程）；CMake 文件目标为 UNKNOWN，文本确认本轮只补构建依赖。提交前 `detect-changes --scope all` risk=low（38 files/34 symbols/0 processes），staged risk=low（9 files/18 symbols/0 processes）。索引仍有流程截断：186 flows、208 个入口候选未纳入、98 个 callee 被跳过、2 次 walk 达预算，缺失 flow 不视为无影响。
- 收尾 Windows Git Bash `bash init.sh --fast` 与完整 `bash init.sh` 均 EXIT=0；另行执行 `cargo fmt --check` 和 Flutter `analyze` 也通过。完整脚本覆盖 Rust tests、Clippy、core DLL 构建与 Flutter 122 项测试；2,000,001 UTF-16 单元恢复夹具约 2 分钟完成。
第十七轮 GitNexus staged `detect-changes` 为 risk=medium（37 files/20 symbols/5 flows），五条受影响流程均在隔离 Web Probe 的 build、导出、重载、销毁与自动回放；all scope 还包含工作区用户既存改动。`_toggleWebView` impact 为 HIGH，该方法的状态文案改动已撤回；`State.build` impact 为 UNKNOWN，确认是 Flutter 覆写后按动态回调路径人工审阅。其余探针回放方法 impact 为 LOW。分析器报告的 process graph truncation 仍存在。
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
- P00.4 实验2：Linux 原生 WebKitGTK 的 MHTML/快照/Inspector/单轮内存已有 WSLg 证据；WPE 2.52.6 source build/Xvfb MHTML replay 通过。默认 sandbox 后续在 Docker `SYS_ADMIN` + `seccomp=unconfined` 配置、UID 1000 下运行，sandbox-disable 变量 unset，进程树观察到 bwrap/WPEWebProcess；旧的无等待首帧 PNG 全透明，MHTML 重载截图通过；后续探针在 DOM 查询前轮询页面标题蓝色像素，三次默认 sandbox 回放都呈现初始页与 MHTML 页面，最终版有一次重试。GBM 硬件仍关闭；WPE 2.54.2 Release 与 Trixie 2.48.3 FDO 构建仍失败；所选 beta 插件静态声明 CDP 与 Inspector 不支持 Linux。docs/04 长时多轮内存协议仍未实测；macOS WKWebView/Web Archive/Safari Inspector 和内存仍未实测。
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
- docs/diagnostics/2026-10-27-p00/p00.4-web-beta-evidence.json、p00.4-web-beta-run/、p00.4-linux-wpe-evidence.json、p00.4-linux-wpe-build.log 与 p00.4-linux-wpe-trixie-compat.log：当前 beta Windows 兼容性复跑及两种 Linux WPE API 组合的构建阻塞证据。
- docs/diagnostics/2026-10-27-p00/p00.4-linux-wpe-2.52.6-build.md、p00.4-linux-wpe-2.52.6-run/、p00.4-linux-wpe-2.52.6-default-sandbox-run/ 与三个 p00.4-linux-wpe-2.52.6-frame-poll-run*/：WPE 2.52.6 源码构建、Flutter Release/Xvfb replay、首帧有界轮询、MHTML/PNG、sandbox 进程及单轮内存证据；明确记录临时 sandbox/GBM overrides。
- .github/workflows/p00-web-engine-linux.yml、tools/web-engine-probe/linux/ 与 scripts/run-web-smoke-linux.sh：Linux WPE 构建和可重放 Xvfb 生命周期采样；本地构建未通过，CI workflow 未运行。
- docs/diagnostics/2026-10-27-p00/p00.4-linux-webkitgtk-evidence.json、p00.4-linux-webkitgtk-run/ 与 tools/web-engine-probe/linux/：P00.4 Linux WebKitGTK 原生引擎补充及可重放 GTK 探针。
- docs/diagnostics/2026-10-27-p00/p00.4-services-adr.md、p00.4-services-evidence.json：P00.4实验3端点、正式版配置差异、Marketplace/Sync 阻塞。
- docs/03：新P00–P15状态/依赖/DoD；docs/09与README标历史范围与新入口。
- feature_list.json、progress.md、本文件：可续作状态。
- app/lib/workbench/workbench_page.dart：本轮仅_findRenderEditableOf中递归调用一行；其余既存修改归用户。
- docs/diagnostics/2026-10-27-parity-plan/：验证日志。

## Next Session

1. 按 AGENTS 启动流程读取本文件/progress Current State，检查 GitNexus 状态并使用 Windows Git Bash 跑 `bash init.sh --fast`。
2. WPE 2.52.6 在 `SYS_ADMIN` + `seccomp=unconfined`、UID 1000 下 sandbox-disable 变量 unset 的三次新回放均生成首屏/MHTML截图；最终探针一次重试后捕获标题蓝色像素。该探针轮询只解决诊断截图时序，不是产品帧同步保证；GBM 硬件未测。P00/P00.4 仍 blocked，不要开 P01。下一步在授权可用的 Mac runner 上验证 WKWebView/Web Archive/Safari Inspector，继续厘清 Microsoft 官方服务身份/许可边界；Linux GitHub workflow 仍未运行（固定 Debian sid WPE 2.54.2），不要从本地结果推断该 CI 通过。
3. P00.4 当前 blocked；不要开 P01（docs/03 依赖 P00）。Linux CDP/Inspector 在当前插件支持表中不支持，需记录为架构决策而非当作兼容。
4. Microsoft 官方身份/许可路径仍没有授权结论；按严格标准保留阻塞。工作流推到 GitHub PR/分支后才能取得 Mac 运行结果，当前不要把未运行 workflow 写成平台证据，也不要用 Linux GTK 结果代替 Flutter/WPE。
5. 复用固定 SHA 工作树 `E:\_alula_vscode_ref_4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e` 与 P00.1/P00.2 证据。

## 已知风险（尚未因本轮计划而修复）

全局UndoStack跨文档风险；>2M字符未保存内容不入journal；同步FFI与800ms全量轮询；
Tree-sitter Rust-only/全文parse；lsp_stop仅detach；watcher全事件重读；快速打开/搜索硬上限。
详见docs/10 §2，不把静态风险冒充已运行复现。
