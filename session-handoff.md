# session-handoff.md — 会话交接

> Last Updated：2026-10-27（第十一轮：P00.3 基线与风险夹具已验收）

## 项目一句话

Flutter桌面工作台 + Rust编辑核心，低内存与资源压力下稳定编辑/保存优先。
用户最新要求：执行docs/10中的全功能复刻计划并分阶段提交；P00.1、P00.2 已完成，P00 总包仍进行中。

## Current Objective

P00.1、P00.2、P00.3 已完成；当前下一项是 docs/03 的 P00.4 三项限时风险实验，P00 总包仍 in-progress。P00.3 的环境、页面/行为基线与四个夹具均已运行并登记。
当前任务与DoD唯一权威：docs/03当前主线；docs/10为范围/架构/方法，docs/11为需求矩阵。
旧Phase/W里程碑只作历史；原型done不继承为1:1完成。P00.4及P01–P15尚未开始。

## What Changed

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
- 本轮没有产品实现变更，不新增常驻结构；P00.3 只固定问题现状，不把它们误写成已修复。

## Blockers / 待核实前提

- P00.1：官方 `latest/insider` 当前指向 1.144.0 的其他 commit，固定 SHA 与 1.145.0 下载路径返回 404；Code-OSS client-only build/start 已完成。remote 子树依赖未安装，Copilot/remote lane 未构建；不能把此源码构建称作微软发行物。
- P00.2：client-only 运行时没有加载随附扩展 payload；静态 95 个 manifest 与运行时 0 个产品扩展的差异保留。6,828 条未决记录和候选映射必须在后续逐项复核，不计为已覆盖。
- P00需构建固定参考，若无相同SHA官方发行物，官方服务参考项标reference unavailable并建立明确差异。
- 真机IME/万行/多DPI/辅助技术未有完整证据；旧G1路线选择不等于这些硬门已通过。
- 官方OAuth/Sync/隧道/市场的注册与分发条件，Web引擎跨平台CDP/MHTML/DevTools与内存，在P00顺序做限时实验。
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
- docs/03：新P00–P15状态/依赖/DoD；docs/09与README标历史范围与新入口。
- feature_list.json、progress.md、本文件：可续作状态。
- app/lib/workbench/workbench_page.dart：本轮仅_findRenderEditableOf中递归调用一行；其余既存修改归用户。
- docs/diagnostics/2026-10-27-parity-plan/：验证日志。

## Next Session

1. 按 AGENTS 启动流程读取本文件/progress Current State，检查 GitNexus 状态并使用 Windows Git Bash 跑 `bash init.sh --fast`。
2. P00.3 已完成并按阶段提交；下一项只推进 P00.4：顺序完成编辑器 IME/增量输入/多光标视口、三平台 Web/CDP/MHTML/内存、官方服务/注册前提三个限时实验并记录 ADR；每次只推进一个实验。
3. P00.4 每项开工前做 GitNexus impact；阶段提交前完整 `detect-changes`，只提交本阶段明确归属文件，不打包用户既存改动。
4. 复用固定 SHA 工作树 `E:\_alula_vscode_ref_4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e` 与 P00.1/P00.2 证据。

## 已知风险（尚未因本轮计划而修复）

全局UndoStack跨文档风险；>2M字符未保存内容不入journal；同步FFI与800ms全量轮询；
Tree-sitter Rust-only/全文parse；lsp_stop仅detach；watcher全事件重读；快速打开/搜索硬上限。
详见docs/10 §2，不把静态风险冒充已运行复现。
