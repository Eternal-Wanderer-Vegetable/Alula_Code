# session-handoff.md — 会话交接

> Last Updated：2026-10-27（第十轮：P00.2 原子贡献/运行时登记导出完成）

## 项目一句话

Flutter桌面工作台 + Rust编辑核心，低内存与资源压力下稳定编辑/保存优先。
用户最新要求：执行docs/10中的全功能复刻计划并分阶段提交；P00.1、P00.2 已完成，P00 总包仍进行中。

## Current Objective

当前仅推进docs/03的P00.3：Golden 基线与现状故障夹具。P00.1 已通过固定 SHA 的 Code-OSS client-only build 与 Workbench 启动完成验收；P00.2 已完成源码/manifest/product/runtime 交叉导出，保留所有未决路由。
当前任务与DoD唯一权威：docs/03当前主线；docs/10为范围/架构/方法，docs/11为需求矩阵。
旧Phase/W里程碑只作历史；原型done不继承为1:1完成。P00.3进行中；P00.4及P01–P15尚未开始。

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

- cargo fmt --check、bash init.sh（Rust test/clippy/build_core/Flutter120测试）、flutter analyze：EXIT=0。
- 本轮 `bash init.sh`、`cargo fmt --check`、`flutter analyze` 均 EXIT=0；日志：`docs/diagnostics/2026-10-27-p00/p00.2-validation.log`。P00.2 导出器 `node --check` 与结构核验通过；12,958 条均具来源路径/可达状态，注册记录 ID 全唯一，四类静态/运行时对账计数自洽。
- GitNexus `detect-changes --scope all` risk=critical（48 files/264 symbols/20 flows），包含工作树中既有 README/app 修改；staged scope risk=critical（19 files/248 symbols/17 flows），命中本阶段导出器流程与文档，本阶段未暂存产品源码。详情见 `atomic-contributions.md`。
- 本轮阶段门复核：Windows Git Bash `bash init.sh` 全绿、`cargo fmt --check` 通过、`E:\flutter\bin\flutter.bat analyze` 无问题；Git Bash 打印 `.bashrc` UTF-16 BOM 提示但未影响退出状态。
- 实际命令/日志与文档结构/graph/harness结果：docs/diagnostics/2026-10-27-parity-plan/verification.md。
- 当前工具链是Windows：从WSL调用Git Bash执行；WSL本身无cargo，Windows Flutter shell有CRLF，勿把环境报错当业务回归。
- 本轮未做新UI/内存基准；只有一行类型修复，没有新增常驻结构。完整1:1/IME/性能均未声称通过。
- 未commit、未push；工作树有大量用户既存skill/app/pubspec改动，勿覆盖、归属本轮或整仓打包提交。

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
- tools/vscode-parity/export-atomic-contributions.mjs、runtime-probe/：P00.2可重放导出器和临时探针。
- docs/03：新P00–P15状态/依赖/DoD；docs/09与README标历史范围与新入口。
- feature_list.json、progress.md、本文件：可续作状态。
- app/lib/workbench/workbench_page.dart：本轮仅_findRenderEditableOf中递归调用一行；其余既存修改归用户。
- docs/diagnostics/2026-10-27-parity-plan/：验证日志。

## Next Session

1. 按AGENTS启动流程读本文件/progress Current State、检查图谱、跑init --fast（Windows工具链）。
2. P00.3 先固定同环境 Workbench 页面/行为 golden，再准备双文件交替撤销、超大未保存文件、关闭工作区进程、长延迟补全四个可重放夹具。
3. 复用固定 SHA 工作树 `E:\_alula_vscode_ref_4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e` 与 P00.1/P00.2 证据；当前 Alula 工作树有大量既存用户改动。
4. 阶段验收与 GitNexus detect_changes 完成后，只提交本阶段明确归属的文件；不要整仓打包用户既存改动。
5. 任何业务代码变更前impact；提交前完整detect_changes；状态只以docs/03为准并同步执行镜像/evidence。

## 已知风险（尚未因本轮计划而修复）

全局UndoStack跨文档风险；>2M字符未保存内容不入journal；同步FFI与800ms全量轮询；
Tree-sitter Rust-only/全文parse；lsp_stop仅detach；watcher全事件重读；快速打开/搜索硬上限。
详见docs/10 §2，不把静态风险冒充已运行复现。
