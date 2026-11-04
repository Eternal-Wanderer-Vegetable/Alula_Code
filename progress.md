# progress.md — 项目进度跟踪

> agent 会话状态文件：每完成一项工作就追加记录。任务权威分解在 `docs/03`，
> 功能状态机在 `feature_list.json`，本文件记录「何时、做了什么、证据是什么」。

## Current State（当前状态，2026-11-04 更新）

### P04.112 / EDT-19b：三方合并投影 FFI 契约（已完成；EDT-19 继续）

- 范围：新增无状态 JSON C ABI `alula_merge_project_json` 与 typed Dart bridge，输入 base/input1/input2、accept-all 和逐冲突选择，输出完整 result/conflicts/unresolved count；Rust/Dart 握手统一升到 ABI v38。不改 `DocRegistry`/`AlulaDoc` 编辑保存语义，不做工作台 UI、Git 冲突发现、导航/combine/Multi Diff。详见 `docs/diagnostics/2026-11-04-p04/p04.112-merge-ffi-contract-scope.md`。
- 已新增无状态 `alula_merge_project_json`，Rust/Dart ABI 同步为 v38；冲突候选、确定性 id、0-based/end-exclusive base 行范围、未解决计数、accept-all 与逐冲突覆盖均由真实 C ABI 往返。请求 16 MiB、响应 32 MiB、逐冲突请求 1,024 项上限；JSON/模型/重复或未知 id 错误不返回部分结果，Dart 按 Rust 所有权合同释放输出。没有修改 `DocRegistry` 或 `AlulaDoc` 行为。
- 验证：Rust FFI 三用例 3/3；真实共享库 Dart→Rust 用例 4/4；完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` 通过（Rust workspace、Clippy、build_core、Flutter 929）；`flutter analyze --no-pub` 零问题；`cargo fmt --all -- --check`、`git diff --check`、`feature_list.json` JSON 校验通过。PR CI `41794075155` 四 job 全绿；Platform Availability `41794067407` 的 Linux x64、Windows x64、macOS ARM64 build/test/launch/package 全通过。包 artifacts：Linux `13303914267`、Windows `13304932299`、macOS `13304649644`。Windows 交互、剪贴板、可访问性和关闭检查通过；macOS 原生 DnD 因 hosted pointer route unavailable skip（artifact `13305996091`，保留 P15）；macOS startup diagnostics `13304833892` 无 crash report。Evidence commit 前 GitNexus 在 product HEAD `e08bfe9` 刷新为 9,959 nodes/302 clusters/379 flows（增量刷新间 edge count 不稳定，未作为证据）；文档-only all-scope 输出在刷新间不一致：一轮六个文档无索引符号重叠且标记 not clean，另一轮识别出 `session-handoff.md` 的 3 个章节符号、0 processes、LOW。保留图映射为未解析；产品代码 all-scope 扫描仍为 CRITICAL。覆盖警告：跳过 5 个 >512 KiB 文件、760 个跨语言 property unresolved、815 个未排名 entry candidates、369 个 skipped callees、13 个 budget-cut walks。
- CI 崩溃线索复核：之前 Platform Availability `41695384851` 的 macOS job 在分配 runner 前零步骤取消；Windows ARM run `41626759894` 的红灯是第二视图编辑/保存断言失败，进程正常退出且无崩溃签名；paced 重放 `41627307864` 通过。本次 `41794075155` 与 `41794067407` 均全绿（macOS DnD 的明确 skip 除外），无新 crash signal。此前红灯可降低 CI 稳定性，但没有证据表明它们导致或复现历史 Windows `0xC000041D`、macOS 启动 SIGSEGV；绿色 smoke 也不构成历史崩溃修复结论。详见 `docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md`。
- 阶段提交：产品 `e08bfe9` 与证据 `577a7ac` 已推送；PR CI `41794075155` 和证据提交 CI `41797888015` 均四项全绿。PR #2 仍 OPEN/draft。下一项为 EDT-19 剩余 Merge Editor 工作台/结果文档生命周期范围登记。
- GitNexus 预编辑（UID-bound）：`ALULA_ABI_VERSION` 为 UNKNOWN；`alula_abi_version` 的 name-based impact 错配到 Cargokit `BuildCMakeCommand`，path-specific context 因 callable-value probe 未运行而 lower-bound，刷新间也出现空结果/异常 UID，故 export impact 保持 UNKNOWN；文本搜索确认真实 Rust/Dart 握手。`AlulaFfi` CRITICAL（2 direct、135–141 flows/20 modules）；`AlulaCore` HIGH–CRITICAL（17 direct、0–139 flows/20 modules）；`AlulaDoc` HIGH–CRITICAL（17–19 direct、0–141 flows/20 modules）；`DocRegistry` CRITICAL（1 direct、135 flows/20 modules）。跨刷新结果不稳定时保留最坏风险；summary-only/capped 输出省略 flow 轴时不能当作 all-clear。workbench 超大文件跳过和跨语言/flow coverage 限制保留。

### P04.111 / EDT-19a：Rust 三方合并投影模型（已完成；EDT-19 继续）

- 新增依赖零、无 GUI 的 `crates/editor-merge` workspace crate。以 base/input1/input2 计算有界 Myers 行投影：单侧与相同 overlap 自动应用；仅真正重叠的差异形成冲突，初始 result 使用 base；支持逐冲突与 accept-all 选择 input1/input2，并可读 unresolved count。范围上限：三输入合计 8 MiB UTF-8、每侧 8,192 行、每次 diff 2,000,000 个活动 trace cell、两侧合计 4,000,000 work step、1,024 conflicts、16 MiB 保留 projection。
- 插入/替换边界可自动组合；邻接但独立的改动保持在冲突区域外。输出保留 BOM、emoji、CRLF、CR 与 final newline。所有限额失败/未知 conflict id 原子报错，不返回部分 projection。暂不接 FFI/ABI、工作台路由/界面、Rust OpenDoc 保存、组合/导航或 Git；因此 EDT-19、`feat-026` 仍未完成。
- `cargo test -p editor-merge` 14/14 通过；完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` 通过（Rust workspace、Clippy、build_core、Flutter 925）；`cargo fmt --all -- --check`、`git diff --check`、`app/` `flutter analyze --no-pub`（0 issues）通过。
- 产品 commit `0c261b2` 已推送。PR CI [41782417039](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41782417039) 四个 job 全绿（Rust Ubuntu/Windows、Flutter analyze/test、Harness）。Platform Availability [41782412210](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41782412210) attempt 2 的 Linux/Windows/macOS ARM64 均通过 build/test/launch/package；包 artifacts：Linux `13300425218`、Windows `13300471052`、macOS `13301288193`。Attempt 1 仅 macOS 的 GitHub ArtifactService `CreateArtifact` 五次超时；只重跑失败 job 后成功，记录为瞬时 artifact 服务故障，不是应用崩溃。CI 证据和详细诊断见 `docs/diagnostics/2026-11-04-p04/p04.111-three-way-merge-core-scope.md`。
- GitNexus 刷新索引：9,941 nodes / 20,756 edges / 299 clusters / 446 flows；仍跳过 >512 KiB 的 workbench 文件，保留 743 个跨语言 property unresolved、800 个未排名 entry candidates、367 个 skipped callees、13 条 budget-cut walks。产品提交前 all-scope 扫描汇总 9 files / 31 symbols / 387 flows / CRITICAL；workspace/build/init 传播较广，未更改既有编辑符号或 build script。索引覆盖局限和完整风险见阶段诊断。
- 该切片仅实现 core projection，不含工作台/保存。EDT-19 与 `feat-026` 仍 in-progress；下一项应为 Merge Editor 工作台/结果文档生命周期注册独立范围，依照 docs/03 单项推进。历史 Windows `0xC000041D` 与 macOS SIGSEGV 仍独立未定位；绿色 CI/重跑不等于 crash 修复。未启动本机 GUI/讲述人。

### P04.110 / EDT-18f：Explorer 多选 Compare Selected（已完成）

- 已实现固定 Code-OSS compareSelected 的 Explorer 双选入口：Windows/Linux Ctrl-click、macOS Cmd-click 切换文件，Shift-click 选择展开树中的可见文件区间；plain click 保留打开文件行为。恰好两项不同普通文件时，点击已选行的菜单才出现 Compare Selected；选择次序决定 original / modified。比较复用冻结原文快照与 Rust 可编辑 modified OpenDoc 路径，保存回读正确。产品 commit efd1ce1 与范围登记 commit 9c4c3fe 已推送。
- 新增两项跨平台目标 Widget 测试覆盖顺序、dirty original、编辑/保存 BOM+CRLF+emoji、macOS Cmd/Shift 和单项/三项菜单 gating。完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` 通过（Flutter 925、Rust workspace、Clippy、build_core）；cargo fmt、Flutter analyze（0 issues）、Harness 100/100、diff check、Explorer 专项 13/13 通过。
- PR CI [41774434607](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41774434607) 全四 job 通过，含 Flutter 925。Platform Availability [41774429349](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41774429349) 的 Linux x64、Windows x64、macOS ARM64 build/test/launch/package 全通过；Linux/Windows DnD、Windows P03.7/UIA/MSAA/graceful close 通过。包 artifacts：Linux `13296362503`、Windows `13296383113`、macOS ARM64 `13296269888`；DnD artifacts：Linux `13296357485`、Windows `13296637171`、macOS `13297250622`。macOS DnD因 synthetic pointer route unavailable 而 skip，保留 P15；启动 artifact `13296199926` 只有 Impeller 初始化行，无 crash report。绿色 smoke 是不复现证据，不是历史崩溃修复结论。PR #2 保持 OPEN/draft；不启动桌面 GUI 或讲述人。
- CI/崩溃线索：旧 Windows 发行包关闭时 `0xC000041D` 与 macOS 启动 SIGSEGV 是真实历史崩溃；近期多数红灯为 runner/排队/输入丢字符/断言，不含崩溃信号。CI 稳定性可改善回归信号，但不得将绿色重跑记成 crash fix。见 `docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md` 与本阶段报告。
- 最终 GitNexus all-scope scan：2 files / 4 symbols / 17 affected processes / CRITICAL；路径标签仍有过连线。预编辑 `_openTreeFile` CRITICAL，若干目标 UNKNOWN；具体影响和索引覆盖限制保留在 `docs/diagnostics/2026-11-04-p04/p04.110-explorer-compare-selected.md`，未将图上的空结果视为无影响。

### P04.109 / EDT-18e：比较编辑器块与选区回退（已完成；P04 继续）

- 已实现固定 Code-OSS diffEditor.revert：diff hunk 的 Revert Block、modified-side selection 的 Revert Selection，以及通过命令面板触发的焦点 Revert。工具栏行与精确 diff hunk 映射，命令按当前 caret/selection 与 modified-side 行范围定位；macOS 命令面板使用 Cmd+Shift+P，Windows/Linux 使用 Ctrl+Shift+P。
- 操作只把冻结 original snapshot 写入 modified Rust OpenDoc。修改通过版本检查的 Rust 文本事务原子提交，形成一个 undo grouping，支持撤销/重做、兄弟视图同步、保存与磁盘回读。stale/approximate/budget fallback、活跃 IME、文档关闭和 identity/version 变化均在修改前拒绝。未修改 diff model、Rust/FFI/ABI 或保存协议。
- 五项范围映射单测与五项工作台 widget 测试覆盖 UTF-16/CRLF、空行插删、selection/hunk 映射、命令面板、undo/redo、兄弟视图、BOM/non-BMP 保存回读及 IME blur 时拒绝旧 diff。完整 init.sh 通过：Rust workspace、Clippy、build_core、Flutter 923；cargo fmt、Flutter analyze（0 issues）、diff check 通过。未启动桌面 GUI 或讲述人。
- GitNexus 最终代码扫描：5 files / 18 symbols / 3 flows / MEDIUM；预编辑 computeDiffViewModel CRITICAL 与图覆盖限制保留。产品/测试提交 2b671e5 已推送；PR CI 41767192131 四 job 全绿（Flutter 923）。Platform Availability 41767186847 的 Linux x64、Windows x64、macOS ARM64 build/test/launch/package jobs 全绿；Linux/Windows DnD 通过，Windows UIA/MSAA 与 graceful close 通过。macOS DnD artifact 13294480227 记录 hosted pointer route unavailable、交互被 skip，原生 macOS DnD 留 P15；macOS startup artifact 13294295957 只有 Impeller 初始化行。包 artifacts：Linux 13292689699、Windows 13294185107、macOS ARM64 13293522849。当前绿色与无 crash report 只是不复现证据，不声称修复历史崩溃。未启动本机 GUI 或讲述人。
- 固定上游、实现、本地/hosted 证据与崩溃归因见 `docs/diagnostics/2026-11-04-p04/p04.110-explorer-compare-selected.md`、`p04.110-explorer-compare-selected-scope.md` 与 `docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md`。P04.110 完成；进入下一 slice 前仍须按 docs/03/docs/11 单项分解和登记。PR #2 保持 OPEN/draft。

### P04.108 / EDT-18d：Explorer 单资源两步比较（已完成；P04 继续）

- 已实现固定 Code-OSS 1.145.0 Explorer 单资源 `selectForCompare` → `compareFiles`：原始快照在选择时冻结，已打开原文件取 Rust 权威当前文本，否则经 Rust workspace decoder；第二个 Explorer 文件绑定 Rust 权威 `OpenDoc`，复用 P04.107 可编辑预览。目录不显示动作，当前已选资源不显示第二步动作；工作区根、canonical path、文档身份/version、IME、文件字节、全文 UTF-16 与差异预算均受校验，过期或超限整次拒绝并给出状态。比较预览内也接入当前 `file.save` 快捷键。未改 Rust/FFI/ABI/保存协议；多资源 `compareSelected`、Open Editors/tabs、apply/revert 和三方/Multi Diff 仍排除。
- 六项新增 widget tests 通过，覆盖 BOM+emoji+CRLF 磁盘解码与冻结、dirty original、读取期间源文档变更、目录/二进制/删除/切换工作区、2,000,000 UTF-16 上限、行预算超限整次拒绝，及 Rust 编辑/预览内 Ctrl+S 保存回读。完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 913）；`cargo fmt --all -- --check`、`flutter analyze --no-pub`（0 issues）、Harness（100/100）和 diff check 通过。headless suite 在已有 saved-compare close-race fixture 输出一条非失败 `UnknownDoc`，不构成崩溃证据。未启动桌面窗口或讲述人。
- 第六测试提交 `11a494e` 的 PR CI [41758044540](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41758044540) 四个 job 全绿。Platform Availability [41758034721](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41758034721) 的 Linux x64、Windows x64、macOS ARM64 job 全绿：Linux 发布/剪贴板/拖放/Xvfb 启动通过；Windows 发布/可见客户区/P03.7 交互/拖放/剪贴板/UIA-MSAA/graceful close 通过；macOS analyze/tests、ARM64 Release、剪贴板、启动和打包通过。包 artifact：Linux `13288599908`、Windows `13289171782`、macOS ARM64 `13289098296`；macOS startup diagnostics `13289078404`，原生 DnD diagnostics Linux/Windows/macOS `13289286604`/`13289496676`/`13288899954`。macOS 包是 hosted 构建证据；本机无 macOS，原生设备交互仍留 P15。
- CI/crash 复核：旧 Windows ARM 重放红灯来自合成键盘丢字符，退出码 0、无应用故障/转储；一次 Platform 红灯在 macOS runner 启动前零步骤取消。历史 Windows `0xC000041D` 与修复前 macOS SIGSEGV 为独立真实崩溃证据。P04.108 不改启动/窗口关闭路径；当前全绿只说明覆盖路径回归通过，不作为崩溃修复证据。GitNexus 实现前 CRITICAL/HIGH/UNKNOWN 与索引覆盖限制保留，提交前需刷新并执行 all-scope change analysis。
- 设计、固定上游、图谱范围与完整证据见 `docs/diagnostics/2026-11-04-p04/p04.108-explorer-compare-scope.md`、`p04.108-explorer-compare.md` 与 `docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md`。本子项完成，P04 / EDT-18 后续能力仍开放。

### P04.107 / EDT-18c：活动文件比较的修改侧可编辑（已完成；P04/EDT-18 继续）

- Compare with Clipboard / Compare with Saved 的 modified pane 现在编辑同一 Rust 权威活动文档；original clipboard/disk snapshot 只读，动态 diff、同文档双视图、selection/undo/redo/dirty/savepoint、保存回读与生命周期 race 维持一致。动态 diff 受 UTF-16、2,000,000 units 与现有行/row/work 预算约束，超限时保留 Rust 编辑并显示完整 fallback；没有改 Rust/ABI/保存协议。固定上游 CompareWithClipboardAction 将活动文件作为 modified resource 打开：https://github.com/microsoft/vscode/blob/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/files/browser/fileActions.ts#L820-L868。
- 产品 commit `945d9576b889cd312689b9462c1b5e0d9c110a80` 已推送；独立测试 commit `8c294309ee469463ac78f0830484fef6cbe42bc3` 补充插入/删除/替换与 IME preedit/commit 用例并已推送。Saved compare focused 14/14、compare suites 22 项、全 Flutter 907 项与本地 `bash init.sh`、当前 `bash init.sh --fast` 均通过；Flutter analyze 0 issues，cargo fmt、Clippy、build_core 与 Harness 100/100 通过。
- PR CI `41740385635`（产品）及 `41741561799`（含补充用例）四 job 全绿。Platform Availability 产品 run `41740379438` 与 follow-up run `41741552975` 的 Linux x64、Windows x64、macOS ARM64 build/launch/package 均通过。最新包 artifacts：Linux `13282810395`、Windows `13282375945`、macOS `13282177699`；Linux/Windows 原生 DnD通过，Windows 可见客户区、P03.7 交互、UIA 与 graceful close 通过。macOS 原生 DnD hosted pointer route unavailable，设备 gate 保留 P15。runner 断连红灯 `41719529276` 同 SHA attempt 2 的 Windows Format/Clippy/tests/10× LSP fixture 全通过；原始失败没有应用 crash signature。完整测试、GitNexus 风险与崩溃关联见 `docs/diagnostics/2026-11-04-p04/p04.107-editable-compare.md` 及 `docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md`。
- 开工前 GitNexus impact 的 `SnapshotComparePreview` 为 LOW；`computeDiffViewModel`、`RustTextInputField`、`_refreshSiblingViews`、`_SnapshotCompareBinding` 为 CRITICAL；`CommandService` 与 compare handlers 为 UNKNOWN。all-scope product scan 5 files/28 symbols/442 process-flow matches/CRITICAL；测试文件无索引 symbol overlap 不能当 clean。433 跨语言 property sites、1,006/1,206 flow candidates 未解析及 15 budget-cut walks 保留未解决，报告详载。
- P04.106 / EDT-18b 已完成，详见下方记录；代码 SHA fe6c13fe76a891eaceffa95025e2f073cffdadfa 的 PR CI 41727303547 与三平台 Platform Availability 41727292646 通过；docs evidence SHA e4974a08a3b40ec07b0248025d95c803393dd01a 的 PR CI 41731775379 也通过。macOS 包 artifact 已生成，hosted 原生 DnD 因指针路由不可用仍待 P15 设备验证。

### P04.106 / EDT-18b：活动文件与磁盘已保存版本比较（此前完成）

- 固定 Code-OSS workbench.files.action.compareWithSaved 已接入 File/命令面板及 Ctrl+K、D；macOS 为 Cmd+K、D。磁盘快照为 original，Rust 权威活动文本为 modified，打开只读 side-by-side 预览；stat 先行限制 6,000,016 bytes，合并输入不超过 2,000,000 UTF-16，并复用差异模型预算。文档切换、编辑、关闭，缺失/二进制/超限磁盘文件均取消整次预览，不写回文档或磁盘。
- 保存比较 widget 9/9；完整 bash init.sh 全绿：Rust workspace、Clippy、core build、Flutter 901；cargo fmt --all -- --check 与 flutter analyze --no-pub 通过（0 issues）。本次启动守则 bash init.sh --fast 也全绿。没有启动本机 GUI/Narrator。
- PR CI [41727303547](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41727303547) 在 SHA fe6c13fe76a891eaceffa95025e2f073cffdadfa 四 job 全通过。Platform Availability [41727292646](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41727292646) 的 Linux x64、Windows x64、macOS ARM64 build/test/startup/package job 全通过；包 artifacts：Linux 13274942383、Windows 13275866747、macOS 13274164639。
- Linux/Windows hosted native move/copy/external-text DnD 都成功，diagnostics 分别为 13273658708 和 13274418074。macOS 包与启动 smoke 成功，但 DnD artifact 13275379020 显示 hosted CGEventPostToPid pointer route: false、交互跳过，macOS 原生 DnD 仍留 P15。macOS startup artifact 13275923616 只有 Metal/Impeller 初始化行，无 crash report；12 秒存活后由 harness SIGTERM 清理。Bundle ID com.alula.alula_app 的无效下划线 warning 留给 release packaging 修正。
- 最近 100 条 branch Actions 记录：regular CI 69/70 成功（唯一 runner communication failure 为 41719529276；稍后的 41727303547 在另一提交上通过，不是同 SHA 重跑）；Platform Availability 23/24 成功（唯一失败 41695384851 是 macOS runner 分配前零步骤取消）；Windows artifact validator 1/6 成功，5 个旧断言失败都因 SendKeys 丢首字符，进程 exit 0 且无 crash dump。不同红灯按 runner、排队或测试输入问题分类；历史 Windows/macOS 真崩溃及证据限定见 docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md。
- GitNexus 风险边界保持不变：大文件跳过、跨语言 property/flow 预算告警未解除；全量 changes 仍为 CRITICAL/UNKNOWN 风险证据，不声称 clean scan。P04.106 不修改启动/关闭路径，也不声称修复 crash。
- P04.106 本地与 hosted DoD 已完成，证据页：docs/diagnostics/2026-11-04-p04/p04.106-compare-with-saved.md。P04 / EDT-18 仍在进行；下一项先从总计划中分解为独立 DoD 并登记到 docs/03，再开始实现。

### P04.105 / EDT-18a：活动文件与剪贴板文本比较预览（此前完成）

- 完成 P04.104 / EDT-17l：inline unchanged-region folding 默认关闭，严格 source row 映射，3 行上下文/20 行逐次展开。代码 `43e35cd`，本地 full init.sh (Flutter 881)、analyze 0、focused 9/相关回归 46、GitNexus all-scope detect 保留 CRITICAL。PR CI `41706323129` 与 Linux/Windows/macOS Platform Availability `41706312269` 通过；P04.104 证据提交 `26cdf35` 的 PR CI `41709174313` 四 job 也全部通过（Harness、Linux/Windows Rust、Flutter analyze、881 tests）。平台包 artifact：Linux `13266685006`、Windows `13267056042`、macOS `13267221143`。Linux/Windows native DnD 与 Windows UIA/MSAA/graceful close 通过；macOS hosted DnD pointer route unavailable，device gate 保持 P15。
- 当前 SHA 无 crash signal/dump 或非零应用退出；P04.104 不涉及启动/关闭路径，不能作为 crash fix。历史真实 Windows/macOS 崩溃与 ARM SendKeys assertion race 分开记录，详见 `docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md`。
- P04.105 / EDT-18a 完成：活动文件与剪贴板只读 side-by-side 比较；F1/File 与 Ctrl/Cmd+K,C；异步 clipboard 后复核 view/id/resource/version，关闭、切换、编辑均取消；2M UTF-16 与 DiffViewModel 行/row/work 预算超限整体拒绝。完整 `bash init.sh`（Rust workspace、Clippy、build_core、Flutter 891）、`cargo fmt --all -- --check`、`flutter analyze --no-pub`（0 issues）与 focused suites 通过。代码 commit `f1d204a5c3a0414ce4fb7edd6063efaeeb3ef290` 已推送；PR CI [41713133917](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41713133917) 四 job 全绿（Flutter 891）；Platform Availability [41713121910](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41713121910) Linux x64、Windows x64、macOS ARM64 build/test/startup/package 全成功。Artifacts: Linux `13268317746`, Windows `13269382552`, macOS `13269977828`; Linux/Windows DnD 23/13 events 与三种 drop 结果均通过，Windows 1028×711、96 DPI、WM_CLOSE exit 0。Linux smoke 的 124 与 macOS smoke 的 SIGTERM 15 均由 watchdog 在进程存活 12 秒后按设计发出，macOS startup artifact `13270312636` 只有 Impeller 初始化行、无 crash report。macOS hosted DnD pointer route unavailable 保留 P15；构建出现 `com.alula.alula_app` 无效 Bundle ID warning，后续 release packaging 修正。完整证据与 crash 边界见 `docs/diagnostics/2026-11-04-p04/p04.105-clipboard-compare-preview.md`。
- 关闭竞态测试捕获到已有 minimap 后台 overview 请求在文档关闭后收到 `UnknownDoc`，现有 catch/log 处理，测试通过，无未捕获异常或进程崩溃证据。记为下一步 minimap async-close 诊断；不扩大 P04.105 代码范围。

### P04.104 / EDT-17l：Git Diff inline 未变区域折叠（已完成）

- 固定 Code-OSS 1.145.0 默认 hideUnchangedRegions=false、上下文 3 行、最少隐藏 3 行、reveal 20 行；inline 每视图 toggle 默认关闭。只折叠同 hunk 内 changed runs 之间不少于 9 行的 context，边缘各保留 3 行；导航按 source row 映射到折叠后的可见行，映射不一致时整体回退。
- 独立 Dart projection + Git Diff inline view 已实现：不跨 hunk/file，不折叠 changed/metadata/marker/leading/trailing context；patch 更新清理开关和 reveal 状态；不改 parser/Rust/ABI/side-by-side/持久化/P14。代码 commit `43e35cd2124b8a936c64876f9592e5f7674835ee` 已推送。
- Focused 投影/widget 9/9；相关 Git Diff patch/whitespace/navigation/moved-block 回归 46/46；`bash init.sh` Rust workspace 71+46、Clippy、build_core、Flutter 881 全通过；Flutter analyze 0、cargo fmt、git diff check、Harness 100/100、JSON 校验通过。
- PR CI `41706323129` 四 job 全通过；Platform Availability `41706312269` 的 Linux x64、Windows x64、macOS ARM64 job 全通过。Linux/Windows Release、clipboard、DnD、启动，Windows UIA/MSAA 和 graceful close 均成功；macOS ARM64 Release/package/startup 成功。Packages: Linux `13266685006`, Windows `13267056042`, macOS `13267221143`; Linux DnD `13265773731` (23 events), Windows DnD `13267245821` (14 events), macOS DnD `13267476544` 明确记录 hosted pointer route 不可用，因此 macOS device DnD 仍未验收。当前 SHA 无 crash/非零退出证据；此 UI slice 也未触及启动/关闭路径。详见 docs/diagnostics/2026-11-04-p04/p04.104-inline-unchanged-regions.md 和 docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md。
- 编辑前 GitNexus GitDiffPatchView/State impact UNKNOWN、共享 projection CRITICAL；实现后 detect-changes 仍为 CRITICAL（4 files、7 symbols、434 flows），新 projector impact 44 nodes/43 direct/CRITICAL。保留图谱风险；精确 rg 确认单一 workbench 产品入口与测试调用点。

### P04.103 / EDT-17k：Git diff moved-block side-by-side 视图（已完成）

- 完成严格的 patch source row → projection side-by-side row 映射；映射不一致时所有 moved marks 整体 fallback。每视图 toggle 默认关闭；side-by-side 开启后绘制原/修改边框和中心连接线，inline/raw fallback 不显示，patch 更新会清掉旧投影。Alula 每视图入口与 Code-OSS 全局 diffEditor.experimental.showMoves 设置位置不同，持久化未纳入本切片。
- 25 个 focused projection/view/patch 测试通过。完整 bash init.sh 通过：Rust workspace、Clippy、build_core、Flutter analyze 0 issues、Flutter 872 tests；cargo fmt、git diff check、Harness 100/100 和 feature_list.json 校验通过。代码 commit 56b343e3b19a9e4adc360e24f7107beeae9d9756 已推送。
- PR CI run 41700110715 四 job 全绿。Platform Availability run 41700098639 的 Linux x64、Windows x64 与 macOS ARM64 jobs 全绿；Windows P03.7 交互、DnD、clipboard/accessibility/graceful close exit 0 均通过。macOS package/startup 成功；hosted synthetic pointer route 不可用，因此 macOS 原生 DnD 仍是 P15 device gate。
- 包 artifacts：Linux 13262593289、Windows 13262834152、macOS ARM64 13265030361。macOS startup diagnostics 13263044741。报告：docs/diagnostics/2026-11-04-p04/p04.103-moved-block-view.md。
- GitNexus 保留 UNKNOWN/CRITICAL：代码 all-scope 4 files / 10 symbols / 432 flows / CRITICAL，仅显示前 10；新增 projection function impact 报 41 上游节点并包含与产品函数无文本引用的异名类型。精确 rg 确认产品入口只在 git_diff_patch_view.dart，其他引用均为测试；不降级告警。

### Windows ARM artifact validator 输入首键问题（已通过同工件复验）

- 用户指出 CI 反复失败可能与崩溃有关。2026-11-03 的五个 Windows 11 ARM workflow_dispatch artifact replay runs 41623366222、41624838142、41625760177、41626282817、41626759894 都因第二视图编辑/保存断言失败；不是常规 PR CI。
- run 41626759894 的浅色工件 13226531608 记录输入后四个 MSAA editor values 均为换行后 `iew-2`，自动输入漏掉首字符 `v`，保存前精确文本断言失败；同 run 深色工件 13227025780 的 `view-2` 保存回读成功。失败 session 正常关闭、exitCode=0，Application Fault 和 crash dump 为空，因此这五次重验失败不是应用崩溃证据。
- validator commit `34f1511` 在 Enter 后等待 350 ms，并把 SendKeys 文本改为逐字符 100 ms 间隔；同一旧 Release artifact 的复验 run [41627307864](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41627307864) 浅色/深色两 job 均通过，四个视图同步并保存回读精确 `view-2`，gracefulClose=true、exitCode=0，crash diagnostics 为空。保持精确文本断言；这是 hosted ARM 验收输入稳定化，不是应用 crash 修复。详见 docs/diagnostics/2026-11-04-p04/p04.103-moved-block-view.md、docs/diagnostics/2026-11-03-p04/p04.92-win11-arm-current-artifact.md 与 docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md。

### P04.102 / EDT-17j：Git diff moved-block 配对模型（模型切片完成）

- 新增纯 Dart 有界模型，从同文件、不同 hunk 中唯一配对首尾空白等价的删除/新增块；默认长度门槛 3 行/15 UTF-16 units，重复候选、近似编辑、同 hunk 和跨文件不标记。保留原/修改行号与 patch-row 映射；超过 2,000,000 输入 units、16,384 rows 或 4,000,000 candidate text work 时完整 fallback。尚未接入产品 view/config，因此 UI 没有显示 moved-block 装饰。
- 代码与模型证据 commit `0959e3c0a24ab5776a9575c3e709ad39d642da53` 已推送至 `codex/vscode-parity-p00`。13 个定向 Flutter 测试通过；`cargo fmt --check` 与完整 `bash init.sh` 通过（Rust workspace/Clippy/build_core、Flutter analyze 0 issues、Flutter 865 tests）。
- PR CI [`41695398743`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41695398743) 四 job 全绿。Platform Availability [`41695384851`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41695384851) Linux x64、Windows x64 jobs 全绿；Linux package/DnD artifacts `13261255894`/`13261180829`，Windows `13262211045`/`13261241203`。macOS ARM64 job 后在 queued 阶段被取消且零步骤执行，故该 workflow 整体为 failure；未运行应用，不能归因于应用崩溃，也不计为 macOS 通过。物理 macOS DnD 仍属 P15。
- 相同 1,965,278 UTF-16 / 16,382 row headless fixture 经 tools/mem-probe：parser-only 末次 PSS 178.8 MiB、模型 181.2 MiB（+2.4 MiB）；不是产品进程占用，不调整 P14 数值目标。GitNexus all-scope 9 files / 29 symbols / 430 affected flows / CRITICAL，输出仍只列前 10；全仓精确搜索未发现产品运行时 callsite。保留图谱风险，不将其解释为低风险。诊断：[`p04.102-moved-block-model.md`](docs/diagnostics/2026-11-04-p04/p04.102-moved-block-model.md)。
- 本轮 PR CI 无失败或崩溃信号；Platform Availability 的失败仅来自 macOS runner 在 queued 阶段被取消（零步骤），没有应用进程可产生崩溃信号。模型未接入 workbench，不触及启动/窗口关闭/插件生命周期，不能证明修复历史崩溃。PR #2 保持 OPEN/draft；未启动本机 GUI/Narrator。
- 用户补充怀疑反复 CI 失败可能与应用崩溃相关。后续遇到失败时，应按同一 SHA 对照进程退出码、crash signature/dump 与 runner 日志，区分真实进程崩溃、断言失败、超时及 runner 排队；重跑通过不作为修复证据。历史记录见 `docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md`。

### P04.101 / EDT-17i（已完成注册范围）

- 固定 Code-OSS 1.145.0 的 diffEditor.ignoreTrimWhitespace=true 已接入 Git unified diff：逐 hunk 投影首尾空白等价行，side-by-side 保留双方原文与行号；内部空白继续着色，超限/映射不一致时完整 raw patch fallback。实现与 DoD 见 docs/03-里程碑计划与验收标准.md。
- 实现 commit e39a648ad7af538d45eeb5ac0a0d32515cae67fc 已推送。本地完整 DoD 通过，Flutter 852 项全绿；focused projection/patch suite 22 项，Flutter analyze 0 issues。证据/state commit 2f390e0 已推送，其 PR CI run 41690547161 四 job 全绿。报告：docs/diagnostics/2026-11-04-p04/p04.101-git-diff-trim-whitespace.md。
- PR CI run 41687279291 四 job 全绿：Harness、Ubuntu/Windows Rust、Flutter analyze 与 852 tests。Platform Availability run 41687266257 三平台 job 全 success。Linux x64 Release/clipboard/DnD（22 pointer events）/Xvfb launch 通过，artifacts 13255511248/13256755398；Windows x64 Release/launch、P03.7 interaction、clipboard、DnD（11 events）、UIA/MSAA 和 graceful close exit 0 通过，artifacts 13255204860/13255244745；macOS ARM64 Flutter 852、Release/clipboard/core signing/package 与 12 秒启动 smoke 通过，package/startup artifacts 13256467168/13256402126。macOS DnD 因 CGEventPostToPid pointer route=false 明确 skip，artifact 13255502756；设备级验收仍属 P15。此轮没有新的 crash 信号；smoke 结束处 SIGTERM 由脚本主动发送，不是崩溃。
- 单次受限 headless Dart 模型样本的尾段 private 为 baseline 183.1 MiB、candidate 187.2 MiB（约 +4.1 MiB）；不是桌面应用或真实项目测量，仅登记给 P14。500 MiB 数值目标仍暂停。
- CI 崩溃相关性按证据区分：4 个修复前 macOS SIGSEGV/exit 139 的 .ips 栈指向 engine-context registry readiness race；9f2c70a 后 49 次 hosted 平台成功运行无复现，支持针对性缓解但不是受控证明。平台输入路由与普通断言红灯不能归类为崩溃。报告：docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md。本地未启动桌面 GUI 或讲述人。

### P04.100 / EDT-17h：F1 差异导航命令（已完成注册范围）

- 固定 Code-OSS 1.145.0 F1 action ID 已校正为 editor.action.accessibleDiffViewer.next/prev；新增本地化命令并接入现有 CommandService/QuickInput。命令只在 Git Diff 面板 tab 活动且解析出可导航差异时出现；点击复用 GitDiffPatchView 当前 index、环绕、滚动揭示和播报路径，每次执行一个方向。
- 新的 GitDiffPatchNavigationController 仅持有一个当前 view 的有界回调；状态销毁时按 owner detach。命令上下文随 TabController 变化和 patch parser availability 更新。没有 Rust/ABI、文本、diff parser/模型或内存预算改动。
- 新增 3 个 palette widget 用例，连同导航套件 11/11 通过；覆盖 next/previous exactly-once、环绕、side-by-side、fallback/no-change 与 inactive context。
- 本地完整 DoD 通过：bash init.sh（Rust 71+46、Clippy、build_core、Flutter 847）；cargo fmt --all -- --check；flutter analyze --no-pub（0 issues）；Harness 100/100；JSON/diff check 通过。本机 GUI/Narrator 未启动。
- P04.100 的 GitNexus impact 保留 CommandService class CRITICAL 172 / 140 processes / 20 modules、GitDiffPatchView class CRITICAL 196 / 140 / 20，以及 workbench_page.dart 超 512 KiB 未入索引造成的 UNKNOWN；_navigateToChange 方法影响 LOW（2 callers）。见 docs/diagnostics/2026-11-04-p04/p04.100-diff-palette-actions.md。
- 代码 commit `0b792fd` 已推送。PR CI [`41678408601`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41678408601) 全绿：Linux/Windows Rust、Flutter analyze、847 Flutter tests、Windows LSP shutdown fixture 连续 10 次和 Harness 均通过。
- Platform Availability [`41678397272`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41678397272) Linux x64、Windows x64、macOS ARM64 三个 job 全绿。Linux build/clipboard/DnD/Xvfb 启动通过；Windows 可见客户区、P03.7 interaction、DnD/clipboard/accessibility 与 graceful close exit 0 通过；macOS Release build、clipboard、DnD probe、core signing、startup 和 ARM64 package 通过。macOS DnD 交互明确因 hosted pointer route unavailable 而 skip，设备级交互仍留在 P15。
- 工件：Linux 包 `13252056391`；Windows 包/client metadata `13251498940`，DnD `13250764038`；macOS ARM64 包 `13254280175`，startup `13253715682`，DnD probe `13252374590`。Windows 元数据记录 1028×711、96 DPI、UIA/MSAA 可用、`wmClosePosted=true`、`gracefulClose=true`、exit 0。macOS startup log 只有 Metal/Impeller 初始化行。
- CI 与崩溃的关系见 `docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md` 和 P04.100 报告：本次 CI/平台 job 没有崩溃签名。补查最新 100 个 Platform Availability 失败记录发现，修复前 4 个 macOS 启动失败实际以 SIGSEGV/exit 139 退出；两份 `.ips` 栈落在 `IrondashEngineContextPlugin getFlutterView`，对应 `9f2c70a` 的 engine-context readiness handshake/nil guard。其后 49 次平台成功运行未再复现，支持该修复是有效缓解，但没有回滚对照，仍不是永久修复证明。25 个 macOS DnD 红灯则是 synthetic input route 不可用，当前 workflow 已显式 skip。P04.100 Windows DnD fixture 的非致命 Cargokit PowerShell `Get-Item` 告警与 macOS pointer skip 均不是崩溃；Windows 历史 `0xC000041D` 根因仍未确认。



### P04.99 / EDT-17g：Git unified diff 差异导航（已完成）

- 按固定 Code-OSS 1.145.0 实现 F7 / Shift+F7 上一处/下一处差异导航，跨末/首处循环；连续删除/新增块视为一处，no-newline marker 不拆块。inline 与 side-by-side 都居中揭示并高亮目标，工具栏按钮与 live region 播报序号/总数/行号；patch 更新重置索引，无差异/raw fallback 禁用导航。实现入口为纯模型 `GitDiffPatchView`，无 Rust/ABI 或文本修改。
- 本地验证通过：定向导航/patch widget 25/25；完整 `init.sh`（Rust 71+46、Clippy、build_core、Flutter 844）、cargo fmt、Flutter analyze 0 issues、Harness 100/100、JSON 和 diff check 全绿。本次重新跑的 `init.sh --fast` 也全绿。本机 GUI/Narrator 未启动。
- Code SHA `ce78c3f` 已推送。PR CI [`41670555528`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41670555528) 四 job 全绿、Flutter 844 tests；Platform Availability [`41670544291`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41670544291) Linux x64、Windows x64、macOS ARM64 jobs 全成功。Windows P03.7、DnD、clipboard、accessibility tree 和 graceful close 通过；macOS ARM64 包已产出，启动诊断无 crash report。macOS DnD artifact 记录 `CGEventPostToPid pointer route: false`，明确 skip，原生 DnD/IME 仍待 P15 设备验证。证据见 `docs/diagnostics/2026-11-03-p04/p04.99-diff-navigation.md`。
- 最新样本：regular CI 最近 100 次为 100 成功/0 失败；Platform Availability 最近 100 次为 54 成功/46 历史失败，最新失败仍是 `41458740387`，之后 54 次成功。红灯主要来自输入路由、可访问性断言与探针/验证器；没有把 assertion failure 当作进程崩溃。
- CI 源码复核发现旧 Windows artifact `d5319369` 在 `CoUninitialize()` 后才析构 `FlutterWindow`；`c2b787f` 将 controller 析构移到 COM teardown 前。旧 artifact 在包含 UIA proxy cleanup 的脚本下仍 crash；后续含该修正的 Windows 11 ARM artifact 两主题都保存读回并 exit 0。判定为高度可能缓解历史关闭崩溃，但旧报告无确认调用栈，仍不是单变量根因证明。详见 `p04.92-win11-arm-current-artifact.md` 与 `ci-failures-and-crash-correlation.md`。
- GitNexus implementation staged/all scan preserves CRITICAL 385 flows / capped and class impact with-tests CRITICAL 173/140/20, without-tests UNKNOWN; the >512 KiB workbench caller is skipped, so the code scan is not clean. The fresh docs-only evidence/state staged/all scan covered 7 files / 16 section symbols / 0 flows / LOW and was neither partial nor truncated. Fixed actions' F1 Command Palette exposure remains a separate EDT-17 follow-up.


### P01.5 Windows CI 异步 LSP 关闭 fixture 稳定性（已完成）

- P04.98 的 PR CI 首次 attempt 在 `p01_async_completion` 的 workspace shutdown FFI 断言处失败，返回错误 JSON（`stopped` 为缺失字段）；测试进程以断言退出码 1，没有 Rust panic、Windows 应用故障记录或 crash dump。同 SHA 重跑通过。失败日志没有打印原始错误 JSON，因此错误原因仍未直接观测。
- fake LSP 原先只记录 `$/cancelRequest`，已取消的延迟 completion worker 仍休眠到期；现在用活动 request 集合与 Condvar 让取消立即唤醒 worker。测试失败时打印完整 shutdown FFI JSON。Linux 焦点用例连续 10/10 通过；Windows hosted CI 焦点用例 10/10 通过。原失败的完整 FFI error 没有留存，因此这解释仍是最可能的 fixture 竞争，不能声称根因已被直接捕获。
- `bash init.sh` 全绿：Rust workspace（71+46）、Clippy、`build_core`、Flutter 836；另有 cargo fmt、Flutter analyze 0 issues、Harness 100/100。PR CI [`41666117480`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41666117480) 四 job 全通过。生产 `LspServer.shutdown`、超时与 ABI 未改；这项 CI 修正不证明缓解历史 `0xC000041D`。
- GitNexus 对生产 `lsp_shutdown_for_workspace` 的 impact 报 `CRITICAL`（126 impacted）；本切片不修改该生产函数。fixture `main` 的索引 impact 为 `UNKNOWN`，精确源码搜索确认仅由 `p01_async_completion` 通过 Cargo 测试二进制调用。

### P04.92 / CI-Crash-01：当前 Release artifact 的 Windows 11 ARM 关闭复放（已完成）

- `windows-artifact-validation.yml` 现可选 run/artifact/source SHA，Narrator 与旧源码交互 job 默认关闭。Windows ARM 的多视图编辑回放先后暴露 clipboard 粘贴与 SendKeys 注入丢字符；在回车后等待 350 ms、逐字符间隔 100 ms 后，保留严格同步/保存回读断言的最终 light/dark 两组均通过。当前 run `41627307864` 使用 Platform Availability `41618233435` 的 x64 Release artifact（source `1129d607`，Windows 11 Enterprise ARM64 x64 仿真，96 DPI）；两组四视图同步、保存回读 `view-2` 一致，WM_CLOSE exit 0，无 Application Error 或 crash dump。讲述人未启动。证据 artifacts [`13225549631`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41627307864/artifacts/13225549631)（light）和 [`13226642379`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41627307864/artifacts/13226642379)（dark）。
- 验证器修正 commit `34f1511` 已推送。PR CI [`41627306984`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41627306984) 四个 job 全绿。先前 ARM 红灯是测试输入注入丢字符，相关 session 正常关闭且无崩溃诊断；这是 harness 输入问题。另经源码复核，旧 artifact 的 `CoUninitialize()` 先于 `FlutterWindow` 销毁，`c2b787f` 调整为先销毁 controller；后续新 artifact ARM light/dark 关闭通过，故旧 crash 高度可能已缓解，确切根因仍未被调用栈证实。详见 [`p04.92-win11-arm-current-artifact.md`](docs/diagnostics/2026-11-03-p04/p04.92-win11-arm-current-artifact.md) 与 [`ci-failures-and-crash-correlation.md`](docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md)。

### P04.93 / EDT-17a：有界逐行差异模型（已完成）

- 按固定 Code-OSS `4bda7217` `DefaultLinesDiffComputer` 新增纯 Dart Myers 行对齐模型；返回 1-based、end-exclusive hunk，支持插入/删除/替换和分离变化，默认忽略首尾空白。UTF-16 输入、每侧行数、frontier 历史槽和比较操作均有上限；到限后返回明确标记的粗粒度全文 hunk。
- 新增 10 个定向用例，含 300 组 seeded 随机行输入；覆盖重复行稳定性、行范围映射、首尾空白、BOM/Emoji/CRLF、空文本/末尾换行和资源上限。
- 完整 `bash init.sh` 通过：Rust workspace、Clippy、build_core、Flutter **793**；`cargo fmt --all -- --check`、`cd app && flutter analyze --no-pub`（0 issues）、harness 100/100 与 `git diff --check` 通过。报告：[`p04.93-line-diff-model.md`](docs/diagnostics/2026-11-03-p04/p04.93-line-diff-model.md)。
- 此切片只交付 line-diff model，未接入 UI；inline/side-by-side、word diff、moved blocks、unchanged folding 与导航仍属于 EDT-17 后续任务。GitNexus 的 diff 概念检索无相关调用流，超大 `workbench_page.dart` 不在索引中；保留 UNKNOWN 与 compare-main CRITICAL/capped 图谱限制。

### P04.94 / EDT-17b：有界字符差异与整词范围扩展模型（已完成）

- 新增纯 Dart `computeWordDiff`：按 UTF-16 code unit 做 Myers 字符对齐，以 Code-OSS `LinesSliceCharSequence` ASCII `[A-Za-z0-9]` word 边界和 `3 * equal < oldWordLength + newWordLength` 扩展低相似度变更。双方范围 0-based、end-exclusive；边界外扩以免切开代理对。合计输入最多 262,144 code units，trace 最多 1,000,000 cells，搜索与扩展最多 2,000,000 work；超限回退完整文本 hunk。最终门逐字检查每个 unchanged gap，必要时合并到无不等 gap，否则显式 alignment-invariant 回退。
- 9 个定向测试全过，另有 200 组 seeded 随机字符串对拍验证范围单调、未变区一致和代理对边界安全。完整 `bash init.sh` EXIT=0：Rust workspace、Clippy、build_core、Flutter **802**；`cargo fmt --all -- --check`、Flutter analyze（0 issues）、harness validator（100/100）和 `git diff --check` 全过。报告：[`p04.94-word-diff-model.md`](docs/diagnostics/2026-11-03-p04/p04.94-word-diff-model.md)。
- 该模型尚未接入 P04.93 行 hunk 或 Workbench。inline/side-by-side、moved blocks、unchanged folding、差异导航及 SCM 入口继续属于 EDT-17 后续项。开工时 GitNexus 刷新至 `ca2600e`，提示跨语言属性未连边与流程候选截断；diff 查询没有命中真实 diff flow，`workbench_page.dart` 超过索引大小上限。新增模块生产调用为零；保留此边界，接线时重新做 impact。

- Hosted acceptance after push: PR CI [`41636601665`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41636601665) passed all four jobs; Platform Availability [`41636589670`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41636589670) passed Linux x64, Windows x64, and macOS ARM64. Linux/Windows DnD recorded 21/13 Flutter pointer events and move/cross-document copy/external-text outcomes. macOS ARM64 package and launch passed; DnD was skipped due unavailable hosted pointer routing. Artifacts are linked from the P04.94 diagnostic report. These green checks do not resolve the historical Windows ARM `0xC000041D`.

### P04.95 / EDT-17c：有界行/词差异视图行模型（已完成）

- 新增纯 Dart `computeDiffViewModel` 组合行 hunk 与 UTF-16 word ranges，按顺序配对替换行，保留额外插入/删除行；验证两侧源行精确一次且顺序不变。支持空尾行、CRLF/BOM/Emoji、首尾空白策略、分离 hunk 和 1:N/N:1；最大合并输入 2,000,000 UTF-16 units、16,384 行、聚合 word 输入 262,144 units、聚合 word work 2,000,000 steps。行模型超限不返回部分 rows 并保留全文；inline 超限保留整行且报告 fallback reason。
- 12 个定向用例和 200 组 seeded 随机文本对拍通过。完整 `bash init.sh` 通过（Rust workspace、Clippy、build_core、Flutter **814**）；`cargo fmt --all -- --check`、Flutter analyze（0 issues）、harness 100/100、JSON 与 `git diff --check` 通过。无 GUI/Narrator。
- GitNexus 对新 `computeDiffViewModel` 的 impact 报 CRITICAL（65 symbols/29 processes）；context/flows 指向无关工作台路径。精确源码搜索确认无生产调用者，只有新模型内部和新测试引用；图谱风险作为未解决分析器误连保留，不降级。报告与当前 CI/崩溃关系复核：[`p04.95-diff-view-row-model.md`](docs/diagnostics/2026-11-03-p04/p04.95-diff-view-row-model.md)、[`ci-failures-and-crash-correlation.md`](docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md)。
- 当前分支最近 100 次常规 CI 全绿；Platform Availability 最近 100 次有 47 次历史失败，但最新 53 次连续通过。早期 macOS 启动 SIGSEGV 曾触发生命周期路径修复；历史 Windows 旧 artifact 的 `0xC000041D` 仍未定位。近期 Windows ARM 自动输入丢字红灯已通过节奏修复稳定复验，失败 session 无 crash 证据。具体样本和边界见 CI 关联报告。
- Hosted checks for code commit `e2e3aa3` passed: PR CI [`41641937089`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41641937089) (814 Flutter tests, Rust Windows/Linux, harness) and Platform Availability [`41641927566`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41641927566) (Linux/Windows/macOS). Linux/Windows DnD artifacts recorded 23/12 pointer events and move/copy/external-text routes; macOS ARM64 package/startup passed while native DnD was skipped for unavailable pointer routing. P04.95 report contains artifact links and the distinction from the unresolved historical crash.

### P04.96 / EDT-17d：Git unified diff 行内渲染（已完成）

- 将现有 Git Diff 面板从纯 unified patch 文本升级为带行号、hunk、上下文/新增/删除着色的惰性行列表；保留逐行选择。解析上限 2,000,000 UTF-16 units / 16,384 行，畸形、二进制、元数据-only 与超限输入回退完整原文，不返回部分解析结果。
- GitNexus 1.6.12 索引在 `c4e3f9d` 新鲜。`workbench_page.dart` 超过分析器大小上限，`_buildGitDiffPanel`/`_showGitDiff` 未解析；源码搜索核实单一面板构建点、单一 `_showGitDiff` 调用点和 `GitCli.diff` 的生产/测试引用。GitCli `diff` 的 impact 为 UNKNOWN（无解析边），不是 unused 结论。
- 实现和本地 DoD 已完成，hosted 验证待推送：新增有界 unified patch parser/lazy row renderer 并接入 Git Diff panel；7 个 parser/widget 测试通过；完整 `bash init.sh` 通过（Rust workspace、Clippy、build_core、Flutter **821**），`cargo fmt --all -- --check`、Flutter analyze（0 issues）、harness validator（100/100）、JSON 与 diff check 通过。本机未启动 GUI/Narrator。
- 新索引覆盖 1,263 个文件；`parseGitDiffPatch` impact 返回 CRITICAL（98 symbols/31 flows），context 列出无关 test `main`、编辑组合/LSP/paint 流程；`GitDiffPatchView` 返回 UNKNOWN。精确源码搜索只找到新 parser/renderer、面板接线和本次测试引用。保留 CRITICAL/UNKNOWN 警告，不宣称图谱 clean。完整 staged/all-scope 为 8 files/15 symbols/341–377 processes/CRITICAL；compare-main 为 1,597 files/1,397–1,462 symbols/399 processes/CRITICAL 且清单 capped。流程关联未能由源码调用核实，仍按未解决风险登记。
- Code commit `44807f2` 已推送。PR CI [`41647025365`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41647025365) 四个 job 全绿，Flutter 0 issues / 821 tests；Platform Availability [`41647018011`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41647018011) Linux/Windows/macOS ARM64 jobs 全成功。Linux/Windows DnD artifacts [`13236070883`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41647018011/artifacts/13236070883) / [`13236870442`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41647018011/artifacts/13236870442) 分别记录 19/13 Flutter pointer events 和同文档 move、跨文档 copy、外部文本 drop；Windows 可见客户区 1028×681、DPR 1.0，P03.7/剪贴板/MSAA/graceful close 通过。macOS ARM64 包 [`13236208246`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41647018011/artifacts/13236208246) 和 startup [`13236058618`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41647018011/artifacts/13236058618) 通过，DnD [`13235843924`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41647018011/artifacts/13235843924) 因 `input-route-unavailable` 跳过。报告：[`p04.96-git-diff-patch-renderer.md`](docs/diagnostics/2026-11-03-p04/p04.96-git-diff-patch-renderer.md)。CI 未复现但未修复历史 Windows `0xC000041D`；样本复核见 [`ci-failures-and-crash-correlation.md`](docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md)。

### P04.97 / EDT-17e：Git unified diff 配对改动的词级高亮（已完成）

- 同一 unified hunk 的连续改动块按序配对 deleted/added rows，复用 UTF-16 computeWordDiff 范围着色为可选择的 rich text；context、hunk 边界和未配对行不会跨界。无末尾换行 marker 保留在当前块。超限或模型 fallback 将整对退回整行范围并附原因；完整 raw-patch fallback 保留。
- 定向 parser/model/widget suite 15 项通过；完整 init.sh 通过（Rust workspace、Clippy、build_core、Flutter 829）；cargo fmt、Flutter analyze（0 issues）、harness 100/100、JSON 与 diff check 全过。无 Rust/ABI 或 memory target 改动，本机无 GUI/Narrator。
- PR CI [41653070567](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41653070567) 四 job 全绿；Platform Availability [41653061611](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41653061611) Linux x64、Windows x64、macOS ARM64 全成功。Linux/Windows DnD artifacts [13238248664](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41653061611/artifacts/13238248664) / [13239400814](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41653061611/artifacts/13239400814) 记录 22/13 events 和 move/copy/external text；Windows 客户区 1028×681、DPR 1.0。macOS package [13238993226](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41653061611/artifacts/13238993226) 与 startup [13240410321](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41653061611/artifacts/13240410321) 通过；native DnD artifact [13238189464](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41653061611/artifacts/13238189464) 因 input-route-unavailable 明确 skip，不冒充 macOS DnD pass。
- GitNexus new function impact CRITICAL（76/31），view UNKNOWN；staged scan 3 files/14 symbols/376 flows/CRITICAL，流程明细 capped 且不匹配准确源码调用。workbench_page.dart 大于 512 KiB，caller 未入图；保留所有图谱风险。源码和 CI/crash 边界见 docs/diagnostics/2026-11-03-p04/p04.97-git-diff-word-highlight.md、ci-failures-and-crash-correlation.md。
- 代码 commit 0eaacac 已推送。当前 green CI 只是 non-reproduction evidence；历史 Windows 11 ARM 关闭时 0xC000041D 仍未定位。

### P04.98 / EDT-17f：Git unified diff 并排视图（已完成首批 hosted gate）

- Git Diff 增加 inline / side-by-side 切换；复用有界 patch/word diff 源行，左右分别编号并保持 selectable 高亮，同一行序列同步垂直滚动。上下文、hunk metadata 和 no-newline marker 跨栏；连续删除/新增按序配对，超限仍完整回退原 patch，宽度小于 640 logical px 时只提供 inline。新增纯投影 5 项与 widget 2 项测试；定向 suite 22 项、完整 `bash init.sh`（Rust workspace/Clippy/build_core、Flutter 836）、cargo fmt、Flutter analyze（0 issues）、Harness 100/100 均通过。无 Rust/ABI 改动，无本机 GUI/Narrator。
- Headless Linux/WSL Dart 模型 probe 对 16,384 行/8,191 词对做 10 秒对照，`total_private` 尾部值基线 201.5 MiB、并排 202.8 MiB（方向性 +1.3 MiB）；峰值 204.2/202.9 MiB。该样本不是 Alula 桌面进程或 Windows 产品基线；原始 JSON 与脚本在 `docs/diagnostics/2026-11-03-p04/evidence/p04.98/`，不改变数值内存优化延期决定。
- GitNexus fresh index 覆盖 1,272 个文件，仍跳过 >512 KiB 的 `workbench_page.dart`。本次 docs/evidence staged/all 扫描报 9 文件/1 symbol/385 flows/CRITICAL；唯一识别符号是文档 section，流程却映射到无关 build/LSP 代码。完整记录误连与截断，不把扫描当作 clean。
- 代码 commit `6a247c7` 已推送。PR CI [`41659471482`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41659471482) 最终 attempt 2 四 job 全绿（Flutter 836 tests）；首次 Windows Rust attempt 的既有 `p01_async_completion` 测试在 workspace shutdown 断言遇到缺失 `stopped` 字段、exit 1，未见 crash signature。耗时 3.03 秒；前一次与同 SHA rerun 均 1.80 秒通过。原始 FFI error 未输出，根因保留未定，后续复现时先增加诊断并采集子进程退出状态，不把重跑当成修复。
- Platform Availability [`41659454431`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41659454431) Linux x64、Windows x64、macOS ARM64 jobs 全通过。Linux/Windows DnD artifacts [`13240454720`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41659454431/artifacts/13240454720) / [`13241223425`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41659454431/artifacts/13241223425) 记录 23/13 events 与 move/copy/external-text；Windows 可见客户区 1028×711、96 DPI、UIA available、WM_CLOSE exit 0。macOS ARM64 package [`13242307358`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41659454431/artifacts/13242307358) 与 startup [`13242572135`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41659454431/artifacts/13242572135) 通过；macOS DnD [`13243135661`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41659454431/artifacts/13243135661) 因 hosted pointer route unavailable skip。
- 最新 100 条 branch 常规 CI 最终结论 100 成功；Platform Availability 54 成功/46 历史失败，最近 54 条连续成功。旧 Windows artifact `0xC000041D` 和 macOS 启动 SIGSEGV 仍未定位；当前 smoke 是 non-reproduction evidence。完整报告：[`p04.98-git-diff-side-by-side.md`](docs/diagnostics/2026-11-03-p04/p04.98-git-diff-side-by-side.md)、[`ci-failures-and-crash-correlation.md`](docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md)。

### P04.91 / EDT-15f：Find/Replace 查找栏水平调整（已完成）

- 按固定 Code-OSS 1.145.0 实现 419 logical px 默认宽度、左侧 sash 拖动扩宽/编辑区与 Minimap 上限、双击默认/最大宽度切换、Find/Replace 输入同步及关闭重开宽度保留；窄窗口改为换行显示操作区，避免水平溢出。专用 fixture 覆盖宽度边界、双击、窄窗口、重开状态与文档/选区/磁盘不变；50,000 行双视图回归通过。
- 完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` 通过（Rust workspace、Clippy、`build_core`、Flutter **783**）；`cargo fmt --all -- --check`、Flutter analyze（0 issues）、`git diff --check` 与 harness validation（100/100）通过。本机未启动桌面 GUI 或 Narrator。
- 代码 commit `1129d60` 已推送。PR CI [`41618241197`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41618241197) 全绿（Flutter 783）。Platform Availability [`41618233435`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41618233435) 的 Linux/Windows/macOS jobs 全部通过：Linux package/DnD `13223165628`/`13223115653`（23 pointer events、move/cross-document copy/external text）；Windows package/DnD `13222791693`/`13222457221`（可见客户区 1028×711、96 DPI、13 events 与三类 drop、WM_CLOSE graceful/exit 0）；macOS ARM64 包 `13222524463` 与 startup `13223810498` 通过，DnD `13223407455` 因 hosted pointer route unavailable 明确 skip。报告：`docs/diagnostics/2026-11-03-p04/p04.91-find-resize.md`。
- CI/崩溃关系：历史 Windows 11 ARM 对 `d5319369` 旧 artifact 重放直接复现 `0xC000041D`；当前 Windows x64 close smoke 正常退出，但不能证明该历史根因已修复。MSAA/探针类红灯需与崩溃分别诊断；current-build Windows 11 ARM 复测仍开放。

### P04.90 / EDT-15e：关闭 Find/Replace 后恢复编辑器焦点（已完成）

- Escape、Shift+Escape 与关闭按钮关闭 Find/Replace 后恢复同一活动编辑器焦点并清除 Find-in-Selection scope；保留 query，文档、选区、dirty/savepoint 与文本 undo 不变。定向查找/替换回归 22 项、关闭行为 fixture 1 项、完整 `init.sh`（Rust workspace/Clippy/build_core、Flutter **782**）、cargo fmt、Flutter analyze（0 issues）、diff check 与 harness 100/100 全通过。本机全程 headless，未启动桌面 GUI/Narrator。
- 代码 commit `c65f340` 已推送。PR CI [`41611944873`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41611944873) 四 job 全绿、Flutter 782 tests。Platform Availability [`41611937616`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41611937616) Linux/Windows/macOS jobs 全成功：Linux DnD artifact `13220110381` 记录 20 pointer events 与 move/copy/external-text 三路；Windows artifact `13219622795` 记录 13 events 与三路，client artifact `13220455435` 记录可见客户区、UIA/MSAA 与 `WM_CLOSE` exit 0；macOS ARM64 包 artifact `13220810721` 与 startup `13221135196` 生成，clipboard 通过，DnD artifact `13219549723` 因 hosted pointer route unavailable 明确 skip。
- GitNexus `impact` 对 `_toggleFind` 与 `_clearFindSelectionScope` 均为 `UNKNOWN`（超大工作台文件未被索引）；源码搜索核实调用点。重复 all-scope 对 5 changed files 均报 CRITICAL，计数随文档映射波动且流程名与 Find 无关；compare-main 为 1,582 files、超过 1,100 symbols/389 flows，CRITICAL 且列表 capped。保留这些风险，不按 clean 处理。历史 Windows `0xC000041D` 仍未定位，本切片和绿灯 CI 不代表 crash 已修复。详见 `docs/diagnostics/2026-11-03-p04/p04.90-find-close-focus.md`。

### P04.89 / EDT-15d：Find 从光标处单词初始化 query（已完成）

- `editor.find` / Ctrl+F 从关闭状态打开 Find 且主选区为空时，使用固定 Code-OSS 1.145.0 默认 word definition 从光标处读取单词；regex 模式按字面搜索。沿 Rust 权威范围读取最多 1,000 UTF-16 单元，处理长行窗口边界与 surrogate pair；无词、stale、IME 或读取失败时保留旧 query。选区非空仍走 P04.88。光标、文本/版本、dirty/savepoint、磁盘与 undo 不变。
- 定向 17 项、完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh`（Rust workspace/Clippy/build_core/Flutter **781**）、`cargo fmt --all -- --check`、Flutter analyze（0 issues）、`git diff --check` 与 harness validation（100/100）均通过。本机未启动 GUI/Narrator。
- 代码 commit `879e3a6` 已推送，验收证据 commit `5402d71` 与关闭 metadata 补充审计 commit `2ddd70e` 已分开推送。PR CI [`41605702841`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41605702841) 与最新 docs CI [`41608891135`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41608891135) 均通过。Platform Availability [`41605695280`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41605695280) Linux/Windows/macOS jobs 全部通过：Linux/Windows DnD artifact `13216652312` / `13216103431` 记录三类真实 drop route；Windows P03.7、clipboard、UIA/MSAA 与 graceful close 通过；macOS ARM64 包 `13217547195` 生成、clipboard 通过、启动日志仅一条 Metal/Impeller 初始化行。macOS DnD artifact `13216579019` 标记 input route unavailable，故 skip，不计通过。
- 最新 100 条 Actions 仍为常规 CI 65/0、Platform Availability 28/6，另有 1 条旧 Windows artifact replay。抽查到的红灯包括 MSAA 语义文本、PowerShell 编码解析和 clipboard format 断言。下载 5 个红灯 Windows package artifacts 后，其中 `wmClosePosted=true`、`closeTimedOut=false`、`exitCode=0`、`gracefulClose=true`；另 1 个 PowerShell 解析错误发生在生成关闭 metadata 前，结果未知。旧包 `0xC000041D` 是独立应用崩溃；当前证据没有显示修复 probe 红灯会缓解该崩溃。详见 `docs/diagnostics/2026-11-03-p04/p04.89-caret-word-find-seed.md` 与 `ci-failures-and-crash-correlation.md`。

### P04.88 / EDT-15c：Find 从单行文本选区初始化 query（已完成）

- `editor.find` / Ctrl+F 从关闭状态打开 Find 时，按固定 Code-OSS 1.145.0 默认行为，从 Rust 权威文档读取非空单行主选区（长度严格小于 524,288 UTF-16 code units）；regex 模式按字面转义。多行、空、超长、stale、存在未提交输入/IME 或读取失败时保留旧 query。Ctrl+H Replace 与光标处单词种子不在本片；后者列为 P04.89。
- 定向 12 项、完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh`（Rust workspace/Clippy/build_core/Flutter **776**）、`cargo fmt --all -- --check`、Flutter analyze（0 issues）、`git diff --check` 均通过；检查 query/regex 命中、emoji UTF-16、selection、Rust 文档版本、dirty、磁盘字节与 Ctrl+Z。未在本机启动 GUI/Narrator。
- 代码 commit `fd53c85` 已推送。PR CI [`41600604418`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41600604418) 四 job 全绿。Platform Availability [`41600596922`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41600596922) Linux/Windows/macOS jobs 全绿：Linux DnD artifact `13214372411` 记录 22 pointer events 与三种 drop route；Windows 包 `13215235646`、DnD artifact `13215390378` 记录可见客户区、13 pointer events、三种 route 和 graceful-close/accessibility 检查；macOS ARM64 包 `13215810663`、启动诊断 `13215860416` 生成，DnD artifact `13215191894` 标记 input route unavailable、native DnD skip。
- 最近 100 条 branch Actions：常规 CI 65 成功/0 失败、Platform Availability 28 成功/6 失败，另有一条旧 Windows artifact replay 崩溃。平台 probe 红灯仍与旧包 `0xC000041D` 无共同故障签名；本次绿色 close/startup 只是非复现证据，不声称修复崩溃。GitNexus 代码 all-scope 5 files/5 symbols/0 processes/LOW；文档 staging 刷新后多次扫描为 CRITICAL，Section symbols 5–12、flows 16–37，文本搜索未在六个文档 diff 中找到 RunBuildCommand/Cargokit 名称，保留 cross-document mapping 警告；docs compare-main 1,579 files/2,731–2,955 symbols/400 flows/CRITICAL、列表 capped。详见 `docs/diagnostics/2026-11-03-p04/p04.88-selection-seeded-find.md` 和 `ci-failures-and-crash-correlation.md`。


### P04.87 / EDT-15b：查找栏 Shift+Enter 导航上一个命中（已完成）

- Find 输入框聚焦时，裸 Shift+Enter / Shift+NumpadEnter 导航上一个命中，普通 Enter 继续下一个；Replace 输入框不触发 Find。命中循环按绝对 UTF-16 偏移，更新选区但不改文本、文档版本、dirty/savepoint 或文本 undo。定向 workbench 测试 9 项通过；完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` 通过（Rust workspace、Clippy、build_core、Flutter **773**），cargo fmt 与 Flutter analyze（0 issues）通过。本机未启动 GUI/Narrator。
- 代码 commit `7523df2` 已推送。PR CI [`41596896260`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41596896260) 四 job 全绿。Platform Availability [`41596889965`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41596889965) Linux/Windows/macOS jobs 全绿：Linux DnD artifact `13212783060` 记录 21 个 pointer events 及同文档 move、跨文档 copy、外部文本 drop；Windows DnD artifact `13212788474` 记录三种 drop 结果，Windows clipboard、UIA/MSAA 与 graceful close 检查通过；macOS ARM64 包 `13213275616`、startup diagnostics `13213196011` 已生成，DnD artifact `13213825783` 标注 input route unavailable、native DnD skip。
- 最新 100 条 branch Actions：常规 CI 66 成功/0 失败，Platform Availability 27 成功/6 失败，另有一条历史 Windows artifact replay failure。新 run 全绿但仅是当前构建的非复现证据，不能据此宣称旧包关闭崩溃已缓解；反复平台 probe 红灯与历史 `0xC000041D` 仍无共同故障签名。GitNexus impact 因 Workbench 跨语言/宽类误连报 CRITICAL，实际 Find/Replace Focus 两调用点已源码核对；代码 all-scope 3 files/2 symbols/0 processes/LOW，staged evidence gate 6 files/2 symbols/0 processes/LOW；compare-main 重复为 1,577 files/2,501–2,536 symbols/402–404 flows/CRITICAL 且 capped、计数波动，不记为 clean。详见 `docs/diagnostics/2026-11-03-p04/p04.87-shift-enter-previous-find-match.md` 和 `ci-failures-and-crash-correlation.md`。

### P04.86 / EDT-15a：查找栏 Alt+Enter 选择全部命中（已完成）

- Find 与 Replace 输入框接入 Code-OSS 默认 Alt+Enter，按 literal/regex、大小写、全字和 Find-in-Selection 选中命中；丢弃过期、非法正则结果，保留当前精确命中为 primary，最多 10,000 个 UTF-16 选区并显示截断状态。单次选择历史更新，不修改文本/dirty/savepoint。定向 Flutter 68 项、完整 `init.sh`（Rust tests、Clippy、build_core、Flutter **772**）、`cargo fmt --check`、`flutter analyze`（0 issues）通过。本机未启动桌面 GUI/Narrator。
- 代码 commit `f24e605` 已推送到 PR #2。PR CI [`41593516002`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41593516002) 四 job 全绿，Flutter analyze 0 issues/772 tests。Platform Availability [`41593509709`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41593509709) Linux/Windows/macOS job 全绿：Linux DnD artifact `13211282750` 记录 22 pointer events 与三种 drop route；Windows artifact `13210964226` 记录可见 1028×711 客户区、96 DPI、UIA/MSAA 与 graceful `WM_CLOSE` exit 0，DnD artifact `13211671290` 记录 13 events 与三种 route；macOS ARM64 app `13212575071` 已生成，startup artifact `13212535093` 只有 Metal/Impeller 行，DnD artifact `13211931578` 明确 input route unavailable、native DnD skip。
- CI 复核：提交前最新 100 次 branch Actions 为常规 CI 65 成功/0 失败、Platform Availability 28 成功/6 失败、旧 Windows artifact replay 1 失败；红灯是 MSAA/clipboard/probe 断言，只有旧包 replay 有 `0xC000041D` 关闭崩溃证据。Windows 关闭校验使用 `if: always()`，故平台断言失败不会跳过关闭检测；暂未发现重复平台红灯与崩溃之间的因果证据。新提交的 Linux/Windows/macOS checks 均通过，详见 `docs/diagnostics/2026-11-03-p04/p04.86-alt-enter-select-all-find-matches.md` 和 `ci-failures-and-crash-correlation.md`。
- GitNexus 对本次工作台入口报 critical，直接函数路径为 `_handleFindInputKey → _selectAllFindMatches → _setDocSelections`；流程列表含大量不相干跨语言命名匹配。已手动检查其单一 Find/Replace 事件入口和共享 selection helper，完成 invalid/stale/limit/widget 测试；compare-main 因整分支差异仍截断，保留该限制，不声明图谱检查 clean。

### P04.85 / EDT-14b：替换保留大小写（本地 DoD 与首批 hosted gates 通过）

- 默认关闭的 Preserve Case 控件支持普通文本/正则当前与全部替换；覆盖全大写、全小写、首字符及 kebab/snake 分段，Unicode 16 多码点大写、点号 I、词尾 sigma；动态捕获/大小写模板不重复转换。正则 worker 的取消/上限/stale guard、selection scope、UTF-16/CRLF/emoji/零宽、单步 undo 与保存读回保持。
- 定向测试 61 项通过；完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` 通过（Rust workspace、Clippy、build_core、Flutter **765**）；cargo fmt、Flutter analyze（0 issues）、Dart 格式及 diff check 通过。本机未启动 GUI/Narrator。
- 代码 commit `3949d8d` 已推送。PR CI [`41588501685`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41588501685) 四 job 全绿。Platform Availability [`41588495748`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41588495748) Linux/Windows/macOS job 全绿：Linux DnD artifact `13209266941` 记录 22 pointer events 和 move/copy/external-text；Windows artifact `13208928420` 记录 13 events、1028×681 客户区、DPR 1.0 与三类 drop，release/accessibility/graceful-close 通过；macOS ARM64 包 `13210135594` 生成，startup artifact `13209333872` 只有 Metal/Impeller 行；macOS DnD artifact `13209009030` 明确 route unavailable、零 pointer event、all tests skipped。
- 当前分支最新 100 条 Actions：常规 CI 65 成功/0 失败，Platform Availability 28 成功/6 失败，另有一条旧 Windows artifact replay failure。红灯抽查是 MSAA/clipboard 断言或 PowerShell 中文乱码导致的 probe parse failure；单独的旧 artifact replay 确为旧二进制关闭 `0xC000041D`。稳定 CI probe 有助于诊断，但这批探针红灯本身不证明引起/缓解本机 crash。当前 green runs 仅 non-reproduction evidence。详见 `docs/diagnostics/2026-11-03-p04/p04.85-preserve-case.md` 和 `ci-failures-and-crash-correlation.md`。
- GitNexus 代码变更 all-scope 6 files/12 symbols/0 resolved processes/LOW；helper impact 2 direct/0 processes/LOW。fresh re-index 后，本次文档状态更新 all-scope 为 5 files/1 symbol/0 processes/LOW；compare-main 为 1,574 files/2,770 symbols/384 flows/CRITICAL、列表 capped，风险保留。`workbench_page.dart` 超过 512 KiB 索引上限。


### P04.84 / EDT-14a：正则替换捕获组与替换串语法（已完成本地 DoD 与优先 hosted gates）

- 依 Code-OSS 1.145.0 实现 `$&`、`$0`–`$99`、`$$`、换行/制表/字面反斜线与捕获组大小写变换操作；支持正则当前替换与全部替换。沿用可取消 750 ms isolate、19,999 命中/有界输出、selection scope、零宽推进与 Rust 单 undo transaction；超时、取消、截断与 stale-result 均不写入。Preserve-case 留待 EDT-14 后续切片。
- 新增 11 项替换测试。完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter **758**）；cargo fmt、Flutter analyze（0 issues）、新/改 Dart 文件格式检查与 `git diff --check` 通过。本机未启动桌面 GUI/Narrator。
- 代码 commit `8eb2d34` 已推送。PR CI [`41584189165`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41584189165) 四个 job 全绿（Flutter 758）。Platform Availability [`41584184923`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41584184923) Linux/Windows/macOS job 全绿。Linux artifacts `13207296631`/`13207371568` 记录 Xvfb launch、22 pointer events 与同文档 move/跨文档 copy/外部文本 drop；Windows artifacts `13207317283`/`13207886549` 记录 1028×711 可见客户区、96 DPI、UI Automation/MSAA、graceful close exit 0、13 pointer events 与三类 drop。macOS ARM64 package `13208125947`；DnD artifact `13206989416` 显示 pointer route unavailable、交互跳过；startup diagnostics `13207084453` 只有 Impeller 初始化行、无 crash report。
- latest 100 branch Actions 仍为 CI 65 成功/0 失败、Platform Availability 28 成功/6 失败、另有一条历史 Windows artifact replay failure。重复平台红灯是无障碍/MSAA、clipboard、DnD 或 launch-probe 断言/解析失败；当前 green runs 仅是 non-reproduction evidence，未建立与 Windows `0xC000041D` / macOS SIGSEGV 的因果联系，也不声称缓解崩溃。详见 `docs/diagnostics/2026-11-03-p04/p04.84-regex-capture-replacement.md` 与 `ci-failures-and-crash-correlation.md`。
- GitNexus re-index at `8eb2d34` succeeded. Post-code all-scope was 4 files/13 symbols/0 resolved processes/LOW; after status/evidence edits all-scope was 5 tracked files/9 symbols/0 resolved processes/LOW (new untracked report omitted). `workbench_page.dart` remains over the 512 KiB index limit, so zero process count is not complete coverage. Two refreshed compare-main scans reported 1,572 files/2,902–2,903 symbols/384 flows/CRITICAL with capped listing, reflecting cumulative branch divergence.

### P04.83 / EDT-13d：查找与替换历史（本地 DoD 与优先 hosted gates 通过）

- 查找和替换历史默认按工作区保存，也支持 `editor.find.history` / `editor.find.replaceHistory = never` 仅内存保留；每栏最多 100 项，Up/Down 浏览 MRU 并恢复编辑草稿，重复值提升到最新。记录采用 500 ms debounce；每条最多 524,288 UTF-16 单元、最多保留 16 个工作区记录，损坏或超大 journal 回退为空；无 Rust/ABI 改动。
- 聚焦历史测试 11 项通过；完整 `FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter RUST_TEST_THREADS=1 bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter **747**）；cargo fmt、Flutter analyze（0 issues）、新增 Dart 文件格式检查与 `git diff --check` 通过。本机未启动 GUI/Narrator。
- 代码 commit `1c9fa40` 已推送。PR CI [`41580497304`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41580497304) 四 job 全绿（Flutter analyze 0 issues、747 tests、Rust Linux/Windows、Harness）。Platform Availability [`41580492090`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41580492090) 三平台 job 全通过：Linux artifacts `13205786160` / `13206030917` 记录 23 pointer events 与 move/copy/external-text；Windows artifacts `13205298478` / `13205333334` 记录 1028×681、DPR 1.0、P03.7 25 tests、12 pointer events、clipboard/MSAA/graceful close 通过；macOS ARM64 package `13206037907` 已生成，DnD artifact `13206461728` 因 pointer route unavailable 跳过，startup diagnostics `13206326998` 已保留。原生 macOS DnD/IME 与 P15 仍待设备。
- GitNexus all-scope 为 11 files / 46–47 symbols / 1 process / MEDIUM（`Save → _stableHash`），但 `workbench_page.dart` 超过 512 KiB 索引限制；compare-main 为 1,571 files / 384 flows / CRITICAL、清单 capped，重复刷新后的符号总数不稳定。最新 100 条 branch Actions：CI 65/65 成功、Platform Availability 28 成功/6 失败、另有 1 条历史 Windows artifact replay failure。失败样本没有与 Windows `0xC000041D` 或 macOS SIGSEGV 相同的已知签名；本轮绿灯是 non-reproduction evidence，不代表崩溃已缓解。证据：`docs/diagnostics/2026-11-03-p04/p04.83-find-replace-history.md` 与 `ci-failures-and-crash-correlation.md`。

### P04.82 / EDT-13c：选区内查找（本地 DoD 与 hosted gates 通过）

- 查找栏新增“在选区中查找”切换；普通/正则结果共用原文 UTF-16 选区范围，驱动计数、导航、高亮、当前替换与全部替换。多选区范围有序、重叠合并、相邻范围保持隔离；捕获末尾 CR/LF/CRLF 时去除行尾换行。范围绑定文档 id/version，过期后清除并退出选区模式；无 Rust/ABI 改动。
- 定向 find/workbench 48 项通过；完整 `FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter **736**）；`cargo fmt --all -- --check`、Flutter analyze（0 issues）、Dart format check 与 `git diff --check` 通过。本机 GUI/Narrator 未启动。代码 commit `60fd9ef`、导航回归测试 commit `d713321` 已推送。
- GitNexus 编辑前 `findMatches` exact/LOW，直接 dependent `replaceAllMatches`；regex/replace callsites 为 UNKNOWN 后用源码搜索确认。staged/all scan 5 files/12 symbols/0 resolved processes/LOW；compare-main 1564 files/2804 symbols/383 flows/CRITICAL，清单 capped，按累计分支差异保留。详见诊断报告。
- 最新 100 条 Actions：CI 65/65 通过，Platform Availability 27 成功/7 失败；7 个平台红灯定位为 MSAA 文本断言、PowerShell launch-probe 解析、clipboard 与 DnD 输入检查。独立历史 Windows artifact replay 仍报告 `0xC000041D`；这些平台红灯日志未见该退出码或 macOS SIGSEGV，不据此声称缓解崩溃。P04.82 PR CI `41575408281` 与 Platform Availability `41575402869` 均通过；四个 CI job 通过（Flutter 736），Linux/Windows/macOS hosted jobs 成功。Linux、Windows 可用性证据及 macOS ARM64 包详见阶段报告；macOS DnD 因 hosted pointer route 不可用而跳过。证据：`docs/diagnostics/2026-11-03-p04/p04.82-selection-scoped-find.md` 与 `ci-failures-and-crash-correlation.md`。

### P04.81 / EDT-13b：安全正则查找（本地与 hosted gates 通过；原生 macOS DnD 待设备验证）

- 查找栏新增正则开关，与大小写/全字选项组合；普通表达式逐行匹配，显式跨行表达式规范化 CRLF 并映射回原 UTF-16 范围。短生命周期 isolate 限时 750 ms、支持 supersede cancellation、表达式 1,000 UTF-16 与结果 19,999 上限；错误、超时和截断有可见反馈。请求 generation、文档 id/version 与查询选项均校验后才可写 UI。零宽匹配可连续导航；正则替换在 EDT-14 前禁用。不改 Rust/ABI。
- 定向 find/workbench 42 项通过；完整 `FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter **730**），`cargo fmt --all -- --check`、Flutter analyze（0 issues）与 `git diff --check` 通过。本机 GUI/Narrator 未启动。代码 commit `4aa5a62`。
- PR CI [`41572068725`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41572068725) 四个 job 全绿：Flutter Analyze 0 issues / 730 tests，Linux/Windows Rust format、Clippy、workspace tests 和 harness 通过。Platform Availability [`41572064300`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41572064300) Linux、Windows、macOS jobs 全 success。Linux package/DnD artifacts `13201737448` / `13202171502`；Windows app/DnD `13201683521` / `13201803465`，可见客户区 1028×681、devicePixelRatio 1.0、13 pointer events，记录同文档 move、跨文档 copy、外部文本 drop，accessibility/关闭 smoke 通过；macOS ARM64 包 artifact `13202790735`。
- 编辑前 GitNexus `findMatches` impact 为 exact/LOW（直接调用者 `replaceAllMatches`）；`_refreshMatches` 为 UNKNOWN，因为 >512 KiB 的工作台文件被跳过，源码核对确认其调用点并保留限制。代码 staged/all 检查 5 files / 13 symbols / 0 processes / LOW；compare-main 为 CRITICAL（1563 files / 2769 symbols / 383 flows），反映累计分支差异。最终 hosted-evidence 文档 staged/all scan 为 LOW、0 affected processes；compare-main 仍因累计分支差异为 CRITICAL。诊断：`docs/diagnostics/2026-11-03-p04/p04.81-regex-find.md`。
- macOS startup artifact `13202780734` 只有 Impeller 初始化行、无 crash report；DnD artifact `13202362754` 记录 `CGEventPostToPid pointer route: false` 且所有 DnD 测试 skipped，因此原生 macOS DnD 仍待设备。此次 hosted run 未复现历史 Windows `0xC000041D` 或 macOS SIGSEGV；worker timeout/cancellation 是正则路径的保护，不声称修复历史 crash。重复 CI 红灯与已知 crash 签名关联仍无证据，详见 `ci-failures-and-crash-correlation.md` 与 `p04.81-regex-find.md`。

### 最新进展（2026-11-03，P04.80 / EDT-13a 全字匹配，hosted gates 通过）

- 查找栏新增全字匹配开关，按工作台默认分隔符、空白与 BOM 计算边界。大小写/全字选项可独立组合；相同命中列表驱动计数、前后循环、编辑器和 minimap 高亮、当前替换/全部替换。大小写不敏感命中基于原文返回 UTF-16 偏移，修正 U+0130 等 lower-case 长度扩展造成的范围错位；无 Rust/ABI 改动。
- 定向 `find_replace_undo_test.dart` + `workbench_bounded_input_test.dart` 33 项通过，覆盖 Emoji、CRLF、BOM、默认分隔符、underscore 边界、Unicode offset、whole-word replace-all 与工作台当前替换。完整 `FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter **721**）；`cargo fmt --all -- --check`、`app/` Flutter analyze（0 issues）、`git diff --check` 通过。本机 GUI/Narrator 未启动。
- 实现提交 `75c0690` 已推送。PR CI [`41567576972`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41567576972) 四个 job 全绿；Platform Availability [`41567572708`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41567572708) 三个平台 job 全绿。Linux Release/Xvfb 和原生 DnD artifact `13199094910` / `13200150196` 通过；Windows 可见 1028×711、96 DPI、UIA/MSAA 与 graceful close、DnD move/copy/external-text artifacts `13200580572` / `13200650257` 通过；macOS ARM64 hosted package `13199499668` 生成，startup artifact `13199609840` 只有 Impeller 行、无 crash report。macOS DnD artifact `13199239830` 因 input route unavailable 跳过，原生 macOS DnD/IME 仍待设备。
- 最新 100 条 branch Actions：CI 64 success/0 failure，Platform Availability 26 success/9 failure，另有 1 条 exact historical Windows artifact replay failure。P04.80 两个新 run 均成功；近期 probe/fixture 红灯与旧二进制的历史 crash 不共享已知 crash signature。Windows `0xC000041D` 和 macOS SIGSEGV 根因未明，当前通过仅是 non-reproduction 证据。见 `docs/diagnostics/2026-11-03-p04/p04.80-whole-word-find.md` 与 `ci-failures-and-crash-correlation.md`。

### 最新进展（2026-11-03，P04.79 / EDT-12e 多光标片段插入，首批 hosted 门禁通过）

- 多光标 snippet 按各自选区解析 selected text、行号、当前行与当前词，共用文件/工作区/剪贴板变量。最多 64 个同一有界输入窗内的普通选区；占位符总数最多 4096、每个 tabstop transforms 最多 64。所有展开经过快照校验后，以一个 Rust transaction 和一个 undo 帧写入；tabstop/镜像/choice/transform 同步导航，多行 transform 保留每个插入点缩进。IME、列选、跨窗、交叠/无效选区、超限、超时和 stale state 在事务前拒绝。无 Rust/ABI 改动。
- 新增测试覆盖各选区变量、Emoji/UTF-16、不同缩进、多行 transform、镜像编辑、Tab/Shift+Tab、CRLF 保存回读、undo/redo，以及 65 选区拒绝且文本/磁盘不变。定向 parser/session/workbench 41 项通过；完整 `bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter **716**），cargo fmt 与 Flutter analyze（0 issues）通过。本机 GUI/Narrator 未启动。
- 代码 commit `511ec3c` 已推送。PR CI [`41563561890`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41563561890) 四个 job 全绿，Flutter 716 tests。Platform Availability [`41563556374`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41563556374) Linux、Windows、macOS 全通过：Linux DnD artifact `13198557247` 记录 23 events 和 move/copy/external text；Windows client artifact `13197713446` 记录可见 1028×711 客户区、96 DPI、UI Automation/MSAA 与 graceful WM_CLOSE/exit 0，DnD artifact `13197498664` 记录 11 events 和三类 drop。macOS ARM64 包 artifact `13198960553` 已生成，startup artifact `13198499420` 只有 Impeller 行、无 crash report。
- macOS DnD artifact `13199565067` 明确显示 synthetic pointer route unavailable，所有 DnD 测试 skip；不算 macOS 原生 DnD 通过。原生 DnD/IME 和 P15 设备检查仍待原生主机。
- 最新 100 次 branch Actions 计数：CI 63 成功/0 失败，Platform Availability 25 成功/11 失败，另有 1 条历史 Windows artifact 验收失败。当前 P04.79 两个 run 均通过；此前红灯主要是 accessibility、clipboard、DnD、交互夹具与启动脚本探针。历史精确 Windows `0xC000041D` 和 macOS SIGSEGV 仍无源码根因；本轮退出/启动正常只属未复现证据。修复探针可减少误报、提升诊断质量，但不等于修复崩溃。分类见 `docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md`。
- GitNexus staged 扫描覆盖 5 files/18 symbols/0 resolved flows、LOW；all-scope 覆盖 6 files/22 symbols、LOW。工作台文件超过索引源文件限制，关键 handler 图仍 UNKNOWN；compare-main 的 CRITICAL 结果覆盖该分支累计历史变更，不能当作本切片风险结论。具体边界和 hosted artifact 见 `docs/diagnostics/2026-11-03-p04/p04.79-multicursor-snippets.md`。

### 最新进展（2026-11-03，P04.77 / EDT-12d1 片段变量转换，首批 hosted 门禁通过）

- 支持 `${VAR/regex/format/options}` 变量转换，捕获组、TextMate conditional/default/case formats 与 `gimsu` flags；未知变量以空字符串进入 transform，转换结果纯文本。64 transforms、regex/format 512 UTF-16、总输入/输出各 256 Ki UTF-16、worker 750 ms 上限，超限/错误在 Rust 事务前 fail closed；placeholder transform 仍开放，无 Rust/ABI 改动。
- 异步 worker 完成后校验活动文档、Rust 版本、输入窗、选区和字段实例；新增工作台用例覆盖当前行转换的 emoji/CRLF 保存回读、worker 运行中编辑、关闭工作台。局部工作台集成首次暴露了新异步路径可能在 controller dispose 后继续回写的竞态；快照保护和两条回归用例通过。它是本切片找到的新生命周期风险，不解释历史 Windows `0xC000041D` 或 macOS SIGSEGV。
- 最新完整 `bash init.sh` EXIT=0（Rust workspace、Clippy、core build、Flutter **708**）；`cargo fmt --all -- --check`、`flutter analyze --no-pub`（0 issues）、`git diff --check` 均通过。针对 snippet parser/session/workbench 文件的完整用例通过。本机 GUI/Narrator 未启动。
- 受控 Linux/WSL Dart harness mem-probe 79 samples/8 s：100×128 Ki UTF-16 plain variable 的峰值/稳态为 211.8/180.3 MiB；variable transform 为 216.8/175.8 MiB。只说明这两次短 harness 观察到峰值约 +5 MiB、无稳态上升；不等同于 Alula GUI，也不可与 Windows 2026-10-26 工作台基线作跨系统预算比较。证据及限制见 `docs/diagnostics/2026-11-03-p04/p04.77-snippet-variable-transforms.md`。
- PR CI [`41553470823`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41553470823) 四个 job 全绿，Flutter analyze 0 issues、全量 708 tests passed，包含 worker 等待期间编辑/关闭编辑器的生命周期回归。Platform Availability [`41553465771`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41553465771) 的 Linux/Windows/macOS jobs 全成功；Linux DnD 23 pointer events、Windows DnD 12，均验证 move/copy/external text，Windows close metadata 为 gracefulClose=true/exitCode=0，macOS ARM64 包已构建。macOS DnD因 input route unavailable 跳过；startup artifact 仅 Impeller 行、无 `.ips`/`.crash`。这些是当前构建未复现证据，不说明历史 Windows `0xC000041D` 或 macOS SIGSEGV 已根治。P04.77 完成首批 hosted gate；macOS 原生 DnD/IME、P15 设备门仍开放。详见 `p04.77-snippet-variable-transforms.md` 与 `ci-failures-and-crash-correlation.md`。
- GitNexus 最终 staged/all 两项均覆盖 13 files 并报告 CRITICAL；CLI 只列前 10 个流程名，余下结果被省略。长篇状态文档重新索引后扫描计数有波动，因此只记录稳定的 CRITICAL 与覆盖边界，不固化流程计数。常见 `parse`/跨语言映射保留为未解决风险，不作为实际可达流程或安全豁免。工作台 `workbench_page.dart` 超过 512 KiB 未入索引；源码核对和 impact 结果见报告。

### 最新进展（2026-11-03，P04.61 / EDT-11c 跨文档文本拖放复制，首批平台验收完成）

- PR CI [`41548372182`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41548372182) 全部 job 通过，覆盖 Flutter 全量测试/analyze、Rust Linux/Windows 与 harness；工作台 handler 测试验证源文档不变、目标 undo/redo 和保存读回。
- Platform Availability [`41543813557`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41543813557) hosted build/package lanes 通过。Linux DnD artifact `13188595395` 记录 20 个 Flutter pointer events，Windows artifact `13187717018` 记录 13 个；两端均记录显式 Ctrl 跨文档 Copy、同文档 move 和外部文本 drop。native adapter probe 与工作台 widget lifecycle 是分开的验收证据。
- P04.61 对首批 Linux/Windows hosted gate 标为 done。macOS artifact `13189006426` 因 `CGEventPostToPid` pointer route unavailable 明确跳过，macOS 原生 DnD 与任意第三方 drag source 互操作仍待验证。
- 全绿 CI 不构成崩溃修复结论：历史 Windows `0xC000041D` 与 macOS SIGSEGV 仍未解决；没有把 DnD fixture/probe 结果归因成崩溃证据。详见 `docs/diagnostics/2026-11-02-p04/p04.61-cross-document-text-copy.md` 与 `docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md`。

### 最新进展（2026-11-03，P04.60 / EDT-11b 外部纯文本拖入，首批平台验收完成）

- 本地验收合同覆盖 `text/plain` receiver、UTF-16 hit-test、65,536-unit 上限、stale/非法/只读/IME/pending 操作拒绝、CRLF 归一、单步 undo/dirty/保存路径；full Flutter tests 和完整 `init.sh` 既有证据均通过。
- 当前 PR CI [`41543818701`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41543818701) 与 Platform Availability [`41543813557`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41543813557) 通过。Linux DnD artifact `13188595395` 记录 20 个 Flutter pointer events，Windows artifact `13187717018` 记录 13 个；两者均完成 external-text drop，另有同文档 move 与跨文档 copy。doc-only CI [`41546512782`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41546512782) 全绿。
- 本切片标为 done 的范围是 Linux/Windows hosted receiver gate；source 是 Flutter fixture，第三方应用间 source interoperability 未测。macOS ARM64 package `13187783861` 已生成，但 DnD artifact `13189006426` 因 pointer route=false 跳过，原生 macOS DnD/IME 仍待设备。本机 GUI/Narrator 未启动。
- 本轮没有 CI crash artifact；旧 Windows `0xC000041D` 和 macOS SIGSEGV 继续未结。当前红灯分类依据退出码、crash artifact 和失败步骤，不把 probe/fixture 路由问题归为产品崩溃或宣称根因已修复。详见 `docs/diagnostics/2026-11-02-p04/p04.60-external-plain-text-drop.md` 与 `docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md`。

### 最新进展（2026-11-03，P04.59 / EDT-11a 同文档文本拖放，首批平台验收完成）

- 复用最新 PR CI `41543818701` 与 Platform Availability `41543813557` 作为当前代码快照的回归证据：Linux/Windows hosted DnD 均有实际 Flutter pointer events，并记录同文档 move、跨文档 copy、外部文本 drop；Flutter 全量测试覆盖同文档 copy/undo、边界与 UTF-16/CRLF。证据与 artifact 号见 `docs/diagnostics/2026-11-01-p04/p04.59-same-document-text-drag.md`。
- Windows hosted 客户区、UI Automation 与 WM_CLOSE exit 0 通过；macOS ARM64 hosted package 已生成，但其 DnD probe 因 `CGEventPostToPid pointer route=false` 明确跳过。按平台优先级，P04.59 对 Linux/Windows 首批验收标为 done；原生 macOS DnD 继续待验证。无本机 GUI/Narrator。
- CI run `41546512782`（证据文档提交）全绿。成功 run 不能消除历史 Windows `0xC000041D` 或 macOS SIGSEGV；近期 probe/fixture/DnD route/accessibility 红灯需按退出码与 crash artifact 分类，不能一概归为崩溃或声称已修复。

### 最新进展（2026-11-03，P04.76 / EDT-12c3 嵌套片段占位符，托管验收完成）

- 固定 Code-OSS 1.145.0 的嵌套默认值与镜像 tabstop 已实现；session 同步跟踪父子范围，支持 UTF-16/emoji，嵌套深度上限 32，transforms 继续 fail closed；无 Rust/ABI 改动。实现提交 `a5a137888eb2d48aedbf0c3077025d043042ee7a` 已推送。
- parser/session/workbench 定向 80 项通过；完整 `init.sh` EXIT=0（Rust workspace、Clippy、core build、Flutter 697），cargo fmt 与 Flutter analyze 0 issues。PR CI [`41543818701`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41543818701) 四项全绿；Platform Availability [`41543813557`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41543813557) 的 Linux/Windows/macOS jobs 通过。
- Linux DnD artifact `13188595395` 记录 20 个 Flutter pointer events 与 move/copy/external-text drop。Windows artifact `13188850992` 记录可见客户区、UI Automation 与 WM_CLOSE exit 0；DnD artifact `13187717018` 记录 13 个 pointer events 与三种 drop。macOS ARM64 包 `13187783861` 已生成，startup `13188093501` 仅 Impeller 初始化；DnD artifact `13189006426` 因 pointer route=false 跳过，不能算原生 DnD 通过。详见 `docs/diagnostics/2026-11-03-p04/p04.76-nested-snippet-placeholders.md`。
- 用户补充的崩溃假设已对照 CI 失败证据复核：历史 Windows `0xC000041D` 是实际异常关闭，修复同类进程崩溃可能消除此类失败；但近期重复红灯主要是 PowerShell/probe/fixture、不可用的 DnD 注入路由和可访问性断言，不都伴随应用崩溃证据。CI 中出现同类红灯时应先核对进程退出码、崩溃报告和失败步骤，再判断是否由应用崩溃导致。历史 Windows 与 macOS SIGSEGV 根因仍未结案，当前绿灯只是非复现；见 `docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md`。
- GitNexus staged/all 扫描覆盖 11 files / 21 symbols，均报 CRITICAL；affected-process 计数随文案变化为 86–163。保留 CRITICAL、UNKNOWN 及索引跨层映射限制，不作为低风险。PR #2 仍为 OPEN draft。本机 GUI/Narrator 未启动；原生 macOS DnD/IME 与 P15 设备验收仍待 macOS 主机。

### 最新进展（2026-11-03，P04.75 / EDT-12c2 选择占位符建议与接受，托管验收完成）

- P04.74 实现与托管证据阶段已完成：`816ac70` / `08723ef` 已推送；PR CI `41530306532`、文档提交 CI `41533891548` 与 Platform Availability `41530299036` 均通过。历史 CI 红灯分类及“绿灯不等于历史崩溃根因已修复”已记录于 `docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md`。
- EDT-12c2 实现 commit `58fdd31540c8a3e1054e11dcb9000de2e282d1e1` 已推送；caret 附近有界 choice 列表支持上下键预览、点击/Enter/Tab 接受、Shift+Tab 前跳、Escape 先关闭列表；通过既有多选区 formatter 与 Rust delta 替换 linked ranges 并推进 tabstop。定向 snippet widget 19 项通过；完整 `init.sh` EXIT=0（Rust workspace、Clippy、core build、Flutter 688），cargo fmt、Flutter analyze 通过。
- 最终 GitNexus staged/all-scope 均报 8 files/CRITICAL；重复刷新时 affected-process 数在重复扫描间为 52–180；caret scroll helper 为 MEDIUM 13 impacted，`RustTextInputFieldState` 类级风险为 CRITICAL 380。`_focusNodeFor` 预编辑为 HIGH；`_onInputDelta` / `_setDocSelections` 为 CRITICAL 且实现未改。完整风险与索引遗漏见 `docs/diagnostics/2026-11-03-p04/p04.75-choice-snippet-ui.md`。
- PR CI run `41537293168` 全绿；Platform Availability run `41537286459` 的 Linux/Windows/macOS jobs 全绿。Linux Xvfb launch 与真实 DnD 通过；Windows P03.7、clipboard、MSAA、可见客户区与 WM_CLOSE exit 0 通过，close artifact 无 crash；macOS ARM64 package/clipboard/startup 通过，DnD 因 `CGEventPostToPid pointer route=false` 跳过。CI/崩溃复核的最新 100 条记录为 CI 61/61 成功、Platform Availability 23 成功/15 失败；红灯主要为验证探针/fixture，其中 `41454766999` 是 PowerShell 解析错误，未启动 Alula。旧 Windows `0xC000041D` 与历史 macOS SIGSEGV 仍是独立、未定位根因的崩溃证据，当前成功运行不声称修复它们。报告：`docs/diagnostics/2026-11-03-p04/p04.75-choice-snippet-ui.md`、`docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md`。无本机 GUI/Narrator。
- 实现阶段已提交并推送；当前仅待把托管证据和状态更新作为独立文档阶段提交。Linux/Windows 首批可用性通过；macOS 包已在托管 runner 生成，原生 DnD/IME/P15 仍待设备。

### 最新进展（2026-11-03，P04.74 / EDT-12c1 选择占位符解析与 session 元数据，本地门禁通过）

- 对齐固定 Code-OSS 1.145.0 的正整数 choice tabstop；首项展开、逗号/竖线/反斜杠转义、畸形或空 choice 文本回退；选择元数据关联精确范围并随 session 镜像编辑保留。每个 choice 限 256 个选项，UTF-16 范围与既有片段上限不变，无 Rust/ABI 修改。建议列表和选项接受另行拆分，当前不宣称完整交互。
- parser 44 项、session 7 项和 workbench 插入/镜像编辑/保存读回 fixture 通过。完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 686）；`cargo fmt --all -- --check` 与 `flutter analyze --no-pub` 通过。本机未启动 GUI/Narrator。
- 编辑前 GitNexus：`SnippetExpansion`、`_SnippetTemplateParser`、`_parsePlaceholder`、`SnippetSession` impact LOW；`SnippetPlaceholderRange` MEDIUM、11 impacted，含 `_buildEditor` flow。已核对 parser/session/workbench 调用链和文本引用；残余跨语言属性边、未排名入口及截断 walks 记于 `docs/diagnostics/2026-11-03-p04/p04.74-choice-snippet-parser.md`。实现 commit `816ac70` 已 push。PR CI `41530306532` 全绿；Platform Availability `41530299036` 的 Linux、Windows、macOS jobs 全绿。Linux/Windows x64 package artifacts `13180814450` / `13181283379`；Linux DnD artifact `13180684685` 记录真实 pointer events 与 move/copy/external-text，Windows artifact `13181473634` 记录三种 drop outcome，client metadata 显示 MSAA focus 与 WM_CLOSE exit 0。macOS ARM64 包 artifact `13181539579` 已产出；startup `13181299922` 只有 Impeller 初始化且无 crash report；DnD `13183156152` 因 hosted pointer route=false skip。历史 Windows `0xC000041D` 与 macOS SIGSEGV 的 source-level 根因仍未结案；本次绿色 CI 不能证明它们已修复。本机未启动 GUI/Narrator。

### 最新进展（2026-11-03，P04.73 / EDT-12b9 `$CLIPBOARD` 片段变量，PR CI 与 Linux/Windows hosted 通过）

- 按固定 Code-OSS 1.145.0 `ClipboardBasedVariableResolver` 接入纯文本 clipboard 变量；空剪贴板走 `${CLIPBOARD:default}` fallback。异步读取后验证文档版本、活动文档、选区、输入值、输入窗和字段实例，变化/异常/超时拒绝插入；限制为 256 Ki UTF-16，无 Rust/ABI 改动。
- 定向 parser/workbench 55 项通过；完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 678），cargo fmt 与 app/ Flutter analyze 通过。编辑前默认阈值 impact 为 UNKNOWN，源码搜索确认调用；随后使用 1 MiB threshold 纳入 527,241-byte 工作台文件，关键 upstream impact 均 LOW，staged/all 为 9 files/23 symbols/0 resolved processes。流程 walk 截断与跨语言 property 漏链保留在 `docs/diagnostics/2026-11-03-p04/p04.73-clipboard-snippet-variable.md`。
- 实现 commit `6acf224` 已 push。PR CI `41522434210` 全绿；Platform Availability `41522426147` 的 Linux/Windows jobs 全绿。Linux Release/clipboard/Xvfb launch 与原生 move、cross-document copy、external text drop 通过；Windows Release、P03.7 interaction、DnD、clipboard、MSAA 与 `WM_CLOSE` exit code 0 通过。Windows artifact `13178576904`、Linux DnD artifact `13177508754`。
- macOS Platform Availability 首次 attempt 因 runner 未分配而取消；只重跑该 job 的 attempt 2 成功，产出 ARM64 package artifact `13180740858`。启动 artifact `13179618766` 只有 Impeller 行，无 crash report；DnD artifact `13179558811` 因 pointer route=false 全部 skip，不视为原生通过。近期 3 个 Windows hosted 红灯已分类为一个 PowerShell probe parse error（应用未启动）和两个 MSAA 文本断言（诊断 JSON 都显示 graceful close / exit 0），不是 crash；旧 Windows binary `0xC000041D` 与历史 macOS SIGSEGV 的 source-level 根因仍未结案。证据：`docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md`。本机未启动 GUI/Narrator。

### 最新进展（2026-11-03，P04.72 / EDT-12b8 `$WORKSPACE_NAME` / `$WORKSPACE_FOLDER`，已推送并通过 hosted CI 与 Linux/Windows 验证）

- 按固定 Code-OSS 1.145.0 单文件夹 resolver 增加工作区名称与路径变量。名称使用根目录 basename，路径是规范化绝对路径并小写 Windows drive letter；路径不缩写 home。只有模板引用变量时才解析，无工作区时显式空值。无 Rust/ABI 改动。
- 定向 parser/workbench 50 项通过；完整 `bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 673），`cargo fmt --all -- --check` 与 `flutter analyze --no-pub` 均通过。编辑前 GitNexus 三个代码入口 impact 均 LOW；属性调用图和索引遗漏按文本核对并保留边界。报告：`docs/diagnostics/2026-11-03-p04/p04.72-workspace-snippet-variables.md`。commit `f2905ff` 已 push；PR CI `41516872987` 与 Platform Availability `41516863565` 三平台全绿。Linux/Windows DnD artifact 分别记录 move、cross-document copy、external text；Windows visible client、UIA/MSAA 与 WM_CLOSE exit 0 通过。macOS ARM64 package artifact `13176282782` 产出，clipboard/startup/package 通过；DnD artifact `13175683851` 因 pointer route=false 明确 SKIP，startup artifact `13176972237` 只有 Impeller 行。历史崩溃仍不宣称永久修复。本机 GUI/Narrator 未启动。

### 最新进展（2026-11-03，P04.71 / EDT-12b7 `$RELATIVE_FILEPATH`，已提交并通过 hosted CI / Linux、Windows 可用性）

- 对齐 Code-OSS 1.145.0：当前 workspace root 内返回不带根名的相对路径，使用宿主分隔符；路径等于 root 和 untitled 文档为空；无 root 或文档位于 root 外时回退到规范化绝对路径标签。仅在模板引用时计算，复用现有 Rust snippet 输入、撤销与保存路径，无 ABI 改动。
- 定向 parser/workbench 46 项通过；`bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 669），cargo fmt 与 `flutter analyze --no-pub` 均通过。GitNexus 1 MiB index 后的三个代码入口 impact 为 LOW；`_workspaceRoot` property 仍 UNKNOWN，文本核对确认真实读写点。commit `dac83fa` 已推送；PR CI `41513096273` 与 Platform Availability `41513086988` 的三平台 jobs 全绿。Linux/Windows 原生 DnD、clipboard、launch smoke 通过，Windows 可见客户区、P03.7、MSAA 与正常关闭通过。macOS ARM64 包 artifact `13174218690` 产出，DnD artifact `13173379014` 因 pointer route=false 明确 SKIP；startup artifact `13173619065` 只有 Impeller 行，无 crash report。详细证据见 `docs/diagnostics/2026-11-03-p04/p04.71-relative-filepath-snippet-variable.md`。

### 最新进展（2026-11-03，P04.70 / EDT-12b6 当前单词片段变量，已提交并通过 PR CI 与 Linux/Windows hosted 可用性）

- 按固定 Code-OSS 1.145.0 增加 `$TM_CURRENT_WORD`：从活动光标 extent 解析当前 word；Alula 尚无每语言 `wordPattern` 配置，本项采用 Code-OSS 默认 word definition。只在模板真正引用变量时读取，通过 Rust 行边界、合法 UTF-16 起点与同版本 `readRange` 读取最多 1000 单元上下文；无 Rust/ABI 改动，未命中保持未知变量原式。
- 定向 parser/workbench 41 项全绿，覆盖分隔符/word 边界、十进制数、Emoji 与 UTF-16、CRLF 保存回读、未知变量、长行 1000 单元窗口。最终完整 `bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 664），`cargo fmt --all -- --check` 通过，`flutter analyze --no-pub` 为 0 issues。GitNexus staged/all 均为 9 files/19 symbols/0 resolved flows、LOW；compare-main 为 CRITICAL，因 parity 分支与 main 相差 2345 commits/1550 files，已在证据报告保留该宽范围告警。代码与本地证据待提交、推送；hosted CI 待补。
- Linux/Windows Release、clipboard、启动与实际 native DnD 路由通过；Windows 可见客户区、P03.7、MSAA 与 WM_CLOSE exit 0 通过。macOS ARM64 包 artifact `13171663410` 已产出，build/clipboard/startup/package 通过；DnD artifact `13173027491` 显示 pointer route=false 且所有 DnD 测试 skip，仍待原生主机；startup artifact `13171469477` 只有 Impeller 初始化行、无 crash report。
- CI 复查：run `41458740387` 的 Windows 红灯是 MSAA 快照缺少欢迎语的语义文本断言；run `41370553563` 有真实 macOS launch SIGSEGV/exit 139，另有无 pointer events 的 DnD 探针超时。P04.70 新 run 未报告崩溃，但不能据此宣称历史崩溃永久修复。CI 错误分类与证据见 `docs/diagnostics/2026-11-03-p04/p04.70-current-word-snippet-variable.md`。

### 最新进展（2026-11-03，P04.69 / EDT-12b5 当前行片段变量，已提交并通过 hosted CI）

- 按固定 Code-OSS 1.145.0 增加 `$TM_CURRENT_LINE`，按插入前光标所在逻辑行展开，去掉 CR/LF 行终止符并保留行内容原样；只有模板确实包含可解析变量时才读取 Rust 行范围。超出 16,384 UTF-16 输入窗上限、版本不一致或读取不完整时不做部分编辑。无 Rust/ABI 改动。
- 新增纯 helper 与 parser/widget 回归，覆盖普通/花括号/default 变量、转义与后缀、嵌套默认文本、emoji、CRLF 保存、当前行超长拒绝、普通片段在长行仍能保存。定向 35 项、完整 `init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 658）、cargo fmt 与 Flutter analyze 0 issues；GitNexus staged/all 均为 9 files/24 symbols/0 resolved processes/LOW，但保留 518 跨语言漏链与流程预算截断警告。commit `ed56d58` 已 push。PR CI `41502782763` 全绿；Platform Availability `41502776628` 全 jobs success。Linux/Windows DnD 实测成功；Windows close/accessibility smoke 通过。macOS `.app` ARM64 zip artifact `13170707375` 已产出；原生 DnD artifact `13169863681` 因 pointer route=false SKIP，startup artifact `13170916969` 仅 Impeller 日志。历史 Windows crash 与 macOS SIGSEGV 未宣称永久修复。本机 GUI/Narrator 未启动。证据：`docs/diagnostics/2026-11-03-p04/p04.69-current-line-snippet-variable.md`。

### 最新进展（2026-11-03，P04.68 / EDT-12b4 行号片段变量，已提交并通过 hosted CI）

- 按固定 Code-OSS 1.145.0 增加 `$TM_LINE_INDEX`（0-based）和 `$TM_LINE_NUMBER`（1-based），均根据插入前活动选区 extent 所在行计算。工作台 flush 并校验输入后读取 Rust 权威位置，再经纯 helper 展开；无 Rust/ABI 改动。
- 定向 parser/workbench 28 项通过；完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 651）；cargo fmt、Flutter analyze 0 issues。commit `6d29a77` 已 push。PR CI `41497584820` 全绿；Platform Availability `41497575540` 全部 job success。Linux/Windows Release、启动与交互 lanes 通过；macOS Release、clipboard、startup/package 通过并产出 ARM64 验证包 `13167398677`。macOS 原生 DnD artifact `13168442013` 因 `CGEventPostToPid pointer route: false` 明确跳过，不能算原生 DnD 通过；startup artifact `13168835425` 只有 Impeller 日志，无 `.ips`/`.crash`。本机未启动 GUI/Narrator。证据：`docs/diagnostics/2026-11-03-p04/p04.68-line-number-snippet-variables.md`。

### 阶段进展（2026-11-03，P04.67 / EDT-12b3 文件路径片段变量，已提交并完成 hosted smoke）

- 对齐固定 Code-OSS 1.145.0 的 `$TM_DIRECTORY`、`$TM_DIRECTORY_BASE`、`$TM_FILEPATH`：命名文档按主机路径风格规范化，POSIX/macOS home 下缩写为 `~`，Windows 盘符小写，根目录 basename 为空；untitled 三变量为空。沿现有 Rust 输入、撤销与保存路径，无 ABI 改动。
- 定向 25 项与完整 `bash init.sh`（Rust workspace、Clippy、build_core、Flutter 648）、cargo fmt、Flutter analyze 0 issues 全绿；commit `6606b77` 已 push。PR CI `41492442098` 全绿；Platform Availability `41492433894` 的 Linux、Windows、macOS jobs 全部 success。Linux/Windows Release、launch、native interaction smoke 通过；macOS Release、clipboard、startup/package 通过并产出 ARM64 验证包 `13167546753`。macOS DnD artifact `13166693448` 明确 SKIP（hosted pointer route=false），startup artifact `13166678983` 只有 Impeller 日志，无 crash report；macOS 原生行为仍需真实设备验证。未启动本机 GUI/Narrator。证据：`docs/diagnostics/2026-11-03-p04/p04.67-file-path-snippet-variables.md`。

### 阶段进展（2026-11-03，P04.66 / EDT-12b2 文件名片段变量，已完成）

- 片段变量新增 `$TM_FILENAME` 与 `$TM_FILENAME_BASE`，flush 后从活动命名文档 basename 解析；base 只去掉最后扩展名，dotfile 保留。未命名文档当前解析为空字符串。无 Rust/ABI 改动。
- 定向 parser/session/workbench 24 项通过；完整 bash init.sh EXIT=0（Rust workspace、Clippy、build_core、Flutter 642），cargo fmt 与 Flutter analyze 0 issues。实现参考固定 Code-OSS 1.145.0；提交 189e920 已 push。PR CI 41482164944、Platform Availability 41482157012 三平台 Release/启动与打包 smoke 全绿；macOS DnD 因 hosted pointer route=false skipped，startup artifact 13161417248 只有 Impeller 日志、无 .ips/.crash。未启动本机 GUI/Narrator。
- 编辑前隔离索引 impact：_insertSnippetTemplate LOW（2 上游入口）、expandSnippetTemplate LOW（3 符号）；OpenDoc.uri 与测试 main 的 UNKNOWN 已文本核实。提交前最终 staged scan 为 9 files/18 symbols/0 flows、LOW。提交后刷新根仓索引时，expandSnippetTemplate impact 报 CRITICAL（76 symbols/142 processes），与隔离快照结果不同；本次证据登记不改代码，未来改该符号前必须复核这项风险与跨语言漏链。

### CI 稳定性跟进（2026-11-03）

- 用户提醒反复 CI 失败可能与崩溃有关；复核 recent 100 runs 后更正分类：PR CI 有 56 success / 1 failure，唯一失败是未启动 Alula 的 vendored Cargokit analyzer；Platform Availability 为 14 success / 28 failure，多数是输入路由、UIA/MSAA、脚本或 fixture 失败；另一个独立 Windows artifact validation failure 确实捕获旧 Release binary `d5319369` 在 `WM_CLOSE` 后以 `0xC000041D` 退出。该旧 binary 的无 UIA/MSAA 对照也崩溃，Windows 事件指向 `flutter_windows.dll` access violation。重建分支 `189e920` 在 run `41482157012` 的 Windows close lifecycle smoke 通过（该步骤断言 exit code 为 0）；当前 PR CI `41487367300` 也通过。详细证据与因果边界见 `docs/diagnostics/2026-11-03-p04/ci-failures-and-crash-correlation.md`。CI 的旧 artifact 回放确实暴露过真实产品崩溃；多数其他红灯仍是探针/runner 假红。Hosted 失败本身不会让本机进程崩溃，修正测试信号不能替代修复运行时关闭路径。旧 artifact 与 P15 Windows 11 验收继续 pending；不在本机启动 GUI/Narrator。
- 后续 P04.67/P04.68/P04.69 的 PR CI 与 Platform Availability 均全绿，三平台 Release/launch/package smoke 无新 crash；P04.69 Linux/Windows DnD pointer/drop 路由真实通过，macOS DnD artifact `13169863681` 仍因 hosted pointer route=false SKIP。P04.69 Windows close/accessibility smoke 通过，旧 Release artifact 的 `0xC000041D` 仍是历史真实崩溃；当前绿灯只说明新构建本次未复现，不证明永久修复。macOS startup artifact `13170916969` 只有 Impeller 日志，无 crash report；历史 SIGSEGV `41370553563` 仍未证明永久消除。
- P04.70/P04.71/P04.72 的 PR CI 与 Platform Availability 均全绿；P04.70 hosted evidence CI `41511068018`、P04.71 证据文档提交 CI `41515815365` 也通过。P04.72 run `41516863565` 的 Windows 新构建在 WM_CLOSE 后 exit 0，macOS startup artifact `13176972237` 仅有 Impeller 行且无 crash report；这不证明旧 Windows `0xC000041D` 或 macOS SIGSEGV 已永久消失。Actions 仍提示 checkout/upload-artifact 的 Node 20 deprecation 与 ubuntu-latest runner migration；均为非致失败告警，后续随 CI/release 整理。P04.71 Windows hosted accessibility 和正常关闭检查通过，Linux/Windows 拖放实际通过。macOS DnD 仍因 runner 的 pointer route unavailable 明确跳过；P04.71 startup artifact `13173619065` 仅有 Impeller 行。历史 Windows close 崩溃 `0xC000041D` 与 macOS SIGSEGV `41370553563` 继续作为未证明永久修复的历史缺陷跟踪。

### 阶段进展（2026-11-03，P04.65 / EDT-12b1 选中文本片段变量）

- 新增 `$TM_SELECTED_TEXT` 与花括号形式；输入 flush 后捕获输入窗内单选区原文，按纯文本展开，不增 tabstop；空选区值为空，unknown variables 保留，变量 transform fail closed。没有 Rust/ABI 变化。
- 定向 parser/session/workbench 20 项通过，含 emoji 代理对与保存回读；完整 `bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 638），cargo fmt 通过，Flutter analyze 0 issues。精确 staged detached snapshot 也通过完整门禁。GitNexus staged scan LOW；私有 parser 方法 UNKNOWN 与索引截断限制已登记。没有本机 GUI。
- commit `a46d63f` 已 push；本项 PR CI 41476559731 与 Platform Availability 41476548776 三平台 lane 全绿。Windows Release/启动、交互、拖放、剪贴板和关闭检查通过；Linux/macOS Release smoke 与 macOS package 通过。macOS startup artifact 13158197946 只有 Impeller 日志，无 `.ips`/`.crash`。历史 CI 红灯已归类为 Windows MSAA/UIA 语义断言、Windows PowerShell 中文脚本编码错误及单 URI clipboard fixture 断言，均无应用崩溃栈；不在本机启动 GUI/Narrator。唯一确认 SIGSEGV 41370553563 单独追踪，不因 CI 绿灯宣称永久消除。证据：`docs/diagnostics/2026-11-02-p04/p04.65-selected-text-snippet-variable.md`。

### 阶段进展（2026-11-02，P04.64 / EDT-12a 基础片段会话）

- 基础 TextMate 子集支持编号占位符/默认值镜像、Tab/Shift+Tab、最终光标、Esc 取消及模板命令；镜像编辑沿用 Rust 输入与撤销路径。多选区、composition 和窗外插入拒绝；choice/transform/nested/其他变量仍开放。
- 解析器/session/工作台定向 17 项通过；完整 `bash init.sh` EXIT=0（Flutter 635），cargo fmt 与 Flutter analyze 0 issues。报告 `docs/diagnostics/2026-11-02-p04/p04.64-snippet-session.md`。P04.64 hosted PR CI 与三平台 Release/launch lanes 随后通过，原生设备/IME 仍 pending。

### 最新进展（2026-11-02，P03.7 hosted MSAA 编辑器文本）

- 修复 Windows hosted CI 的 focused editor `Value` 为空：`RustTextInputField` 的语义节点现在发布当前有界输入窗文本；新增无 GUI widget 回归，证明中文 welcome 文本及 label 都可从 Semantics 读取。修复前测试复现空 value，修复后 `rust_text_input_field_test.dart` 8 项通过。
- `bash init.sh` EXIT=0（Rust workspace tests、Clippy、build_core、Flutter 618 项）；commit `40b8444` 已 push。PR CI `41461810249` 与 Platform Availability `41461800457` 全绿；Windows 当前 Release 的 accessibility 与正常关闭检查通过，Linux lane 通过。macOS build/launch/package lane 通过，但不替代原生 Mac 设备验收。
- 失败分类：前置 run `41458740387` 的 MSAA `State & 4` 已确认焦点真实到位，`Value` 为空；其截图仍可见 welcome 文本。关闭元数据显示 WM_CLOSE 正常、未超时、exit 0。该红灯是语义暴露缺陷，不是崩溃。当前修复提升 CI 检测信号，不据此声称消除了运行时崩溃。
- 历史 Windows 固定旧 artifact 的 `0xC000041D` 和 macOS startup SIGSEGV `41370553563` 均与本次语义问题分开；现有 macOS readiness handshake 后 smoke 未复现 SIGSEGV。Windows 11 Narrator/DPI/主题、Linux native DRM 与 macOS native device 门仍 pending。完整证据：`docs/diagnostics/2026-11-02-p03/p03.7-msaa-editor-value.md`。

### 最新进展（2026-11-02，P04.63 / EDT-11e Paste As 核心实现）

- `EditorClipboard` 现在读取有界 plain/HTML/URI 多 MIME snapshot，并支持 Linux、Windows、macOS URI-list 及平台 file/regular URI formats。新增 Paste As provider/config pipeline：plain text、显式 HTML、绝对 URI/path、工作区 relative path；注册 `editor.action.pasteAs`、`editor.action.pasteAsText`、`editor.changePasteType`、`editor.hidePasteWidget`，默认 Ctrl/Cmd+Shift+V。普通 paste 保持纯文本优先，功能关闭时普通 Ctrl/Cmd+V 仍可用；粘贴后选项为不抢编辑焦点的浮层。
- provider edits 校验 activity/doc version/focus/selections，通过一次 Rust `applyWith` 和单帧 undo；替换 provider 先撤销前一 provider 再应用新值。测试覆盖多格式、URI workspace containment、provider switching、一次 undo/redo、保存回读与设置关闭回退。无 Rust/ABI 改动。
- 定向 Paste As/clipboard/widget tests 全过；`RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 617），`cargo fmt --all -- --check` 通过，`flutter analyze --no-pub` 0 issues；从 HEAD 05afc0d 应用精确 14-file staged patch 的 detached worktree 再跑 init/fmt/analyze 也全部通过；task-scope diff check 通过。真实桌面 clipboard round trip 已加到 Platform Availability integration，不在本机启动 GUI，以免触发 Narrator。
- P04.63 / EDT-11e 已完成并登记。PR CI `41447739900` 全绿；Platform `41447732320` 的 Linux/Windows/macOS native clipboard round-trip 均通过。Linux lane 全绿，macOS clipboard/DnD/startup/package 全绿；Windows app launch、P03.7 interaction 与 clipboard 通过，但 Windows DnD probe 与独立 accessibility label 仍失败，分别记录为后续项。三个 launch smoke 均通过，无新 crash stack。
- 首次 P04.63 push 的 PR CI 41441416426 通过，Platform 41441408464 暴露三类原生 URI 格式差异；修复后 PR CI 41444169065 全绿（Flutter 617、Analyze、Rust Linux/Windows、harness）。Platform 41444162648 最终失败仅在 Windows native clipboard fixture 和独立 accessibility semantic label 断言；Linux clipboard/DnD/Xvfb launch 全绿，macOS clipboard/DnD/startup/package 全绿，Windows app launch/P03.7 interaction suite 通过。新 fixture 已改为 Windows/Linux 单对象多行 URI-list，等待 hosted 重跑。日志无 Alula crash stack；三平台 launch smoke 均成功，所以当前红灯不支持“CI 失败导致产品崩溃”的推断。accessibility 文案问题记录为 P03.7 后续项。
- Hosted completion evidence for P04.63: `8c4ca9c` fixes the platform-native URI-list clipboard fixture. PR CI `41447739900` passed; Platform `41447732320` Linux/Windows/macOS clipboard steps passed. Windows DnD artifact `alula-windows-native-dnd-41447732320-1` has down/move/cancel and times out waiting for drop.json; accessibility smoke still lacks “打开一个文件夹开始工作”. Both are outside P04.63 clipboard DoD and neither emitted a crash stack. macOS DnD and package passed; three OS launch smokes passed.

- 跟进 GitNexus：staged 6 files / 5 symbols / 0 flows / LOW；_decodeUriList 为 UNKNOWN（属性 dispatch 未建边，文本检索已核实 codec registrations 和 unit test）；scope all 重复结果 45 files / 17–18 symbols / LOW；compare-main 1,565 files / 1,566–1,604 symbols / 430 flows / CRITICAL 且列表 capped，代表整条分支，不作为本次 follow-up 风险评级。索引的 567 跨语言属性漏链与流程截断见 P04.63 报告。
- GitNexus staged 两次结果不一致：一次为 4 files / 1 section / 182 flows / CRITICAL；重索引后的复查为“no indexed symbols overlap”且明确不是 clean tree。最后 scope all 43 files / 13 symbols / 0 flows / LOW（含既有工作区修改）；compare-main 1,565 files / 1,355 symbols / 430 flows / CRITICAL 且 capped。P04.63 文档节 impact 曾报 CRITICAL；fixture `main` impact UNKNOWN，已用 workflow 文本确认三平台直接启动此测试文件。告警未消解，未当作 clean，见报告。

### 最新进展（2026-11-02，P04.62 / EDT-11d 跨文档 Move 与联动撤销）

- 跨文档 builder 现在支持默认 Move 与显式 Copy。Move 在 Rust workspace 原子事务内删除源范围并插入目标；两侧用同一 linked transaction id 记录历史。Ctrl+Z/Y 从任一参与文档发起会验证两侧栈顶后原子撤销/重做；栈顶失配拒绝且内容不变。关闭/clear、redo 分叉及本地或共享历史预算淘汰均成对移除帧。拒绝的内部 Move 不会落入 dragCompleted 的源删除回退。
- planner 和工作台用例覆盖 UTF-16 emoji、stale payload/目标版本、move/drop route、两文档 dirty/savepoint/保存回读、双文档 undo/redo、后续单文档编辑导致的 fail-closed、被拒 drop 不误删源；UndoStack 用例覆盖 close、redo branch 与共享预算淘汰。未改 Rust 或 ABI。
- `bash init.sh` EXIT=0：Rust workspace、Clippy、build_core、Flutter 605 tests 全过；`cargo fmt --check` 通过，`flutter analyze` 0 issues。最后追加栈顶失配 widget assertions 后，完整目标工作台 2 tests 再通过。P04.62 报告：`docs/diagnostics/2026-11-02-p04/p04.62-cross-document-text-move.md`。
- 精确 staged snapshot 临时 worktree 的完整 `bash init.sh`、`cargo fmt --all -- --check`、`flutter analyze --no-pub` 全通过。提交 `4a15ac3` 已 push；PR CI `41430406198`（Flutter 605、Analyze、Linux/Windows Rust、harness）及 Platform `41430397498` 三平台 lanes 全绿。Linux/Windows hosted artifacts `13133749226` / `13133069363` 证明 native same-document move、explicit cross-document Copy fixture 和 external drop；跨文档 Move 实际 handler/linked undo 由 PR 工作台 widget tests 覆盖。macOS DnD artifact `13135045729` 明确 route-unavailable / all skipped；startup artifact `13135370216` 只有 Impeller 日志、无 `.ips` / `.crash`。CI 日志的 Windows symlink resolver `Get-Item` 和 Node 20 / `ubuntu-latest` 提示均为非致命 warning。P04.61/P04.62 报告区分 runner/test 假红与真实 SIGSEGV；本次没有新 crash 证据。
- GitNexus 编辑前 `_buildEditorTextDropRequest` impact 为 UNKNOWN/no callers，经文本搜索确认其由 `EditorNativeTextDragDrop.buildDropRequest` 调用；`EditorNativeTextDragDrop` 类 impact CRITICAL（363 symbols / 142 processes / 20 modules），该类未改。Rust workspace transaction 入口已有 CRITICAL 影响提示，保持复用、不修改函数或 ABI。
- CI 红灯审计（`gh run list --branch codex/vscode-parity-p00 --limit 100`）：主 CI 54 success / 1 failure；Platform Availability 11 success / 34 failure。主 CI 唯一失败是已由 `1fbda68` 修复的 vendored Cargokit analyzer 误扫；抽查的 Platform 红灯为 macOS 合成 pointer route、Windows pointer-cancel 断言、Windows 临时目录 teardown 与一次 Swift adapter 编译问题。`5c1c501`、显式 `input-route-unavailable` SKIP 路径和后续 Swift 修正后，最新 PR CI `41433034281` 与 Platform `41430397498` 都通过。该统计反映开发迭代中的历史尝试，不应当作当前故障率；macOS DnD 仍未验收。
- CI 假红没有启动 Alula或可提供崩溃栈。唯一确认产品 crash 为 `41370553563` macOS startup SIGSEGV；`9f2c70a` readiness handshake/nil guards 后的 launch smoke 未复现。CI 稳定有助于发现回归，但当前证据不支持把 runner/test 红灯当作该 crash 的原因。详见 `docs/diagnostics/2026-11-02-p04/p04.62-cross-document-text-move.md`。
- P04.62 已完成并有 Linux/Windows CI 证据；macOS 原生 DnD 仍单独 pending，500 MiB 优化留在 P14。P04.63 当前实现完成并等待 hosted native MIME 验收；Settings UI/持久化留 P07，Markdown URL/文件/图片 providers 留 P08/P12。

### 最新进展（2026-11-02，P04.61 / EDT-11c 跨文档文本拖放复制）

- 跨文档 local text payload 现在支持显式 Copy：目标控件按不同 Rust 文档分支处理，默认 Move 被拒；源文档在 drop 时重读选区并核验 id/version/UTF-16 内容，目标文档版本、输入窗、IME 与 pending 状态也要匹配。目标使用 Rust 单次 insert，进入目标 undo/dirty/Find/保存和分屏同步；源文本保持不变。没有 Rust/ABI 变更。跨文档 Move 留待原子事务与跨文档撤销实现。
- 新增 planner 边界、Rust FFI 与 `DropRegion`/`RustTextInputField` widget 回归；另加真实工作台 handler 测试，覆盖目标单次插入、源内容/磁盘不变、目标 undo/redo/dirty 与 Ctrl+S 读回。`FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 598）；`cargo fmt --all -- --check` 通过，`flutter analyze --no-pub` 0 issues。
- 新 widget test 直接构造 Flutter `DropSession` 事件；handler 测试调用真实工作台 callback。PR CI [`41420735903`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41420735903) 全绿：Flutter Analyze 0 issues、598 tests passed，Rust Linux/Windows 与 harness job 通过。Platform [`41420726253`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41420726253) Linux/Windows/macOS build/package lanes 均成功。Linux artifact `13129633026`、Windows artifact `13130780116` 均完成同文档 move、Ctrl cross-document Copy（fixture target 7002/v4/offset 6）及 external text drop。Mac DnD artifact `13130327858` 为 `input-route-unavailable` / `All tests skipped`，job success 不算原生通过。
- CI 线索复核：PR run `41372387516` 的 Flutter Analyze 误扫 vendored Cargokit `build_tool` 且缺其独立 pub 依赖，已由 `1fbda68` 排除；Windows run `41398574665` 的 pointer cancel 断言假红和 `41386803238` 的大文件 teardown 锁文件已由 `5c1c501` 修复；macOS `41390211533` 是 hosted AppKit 输入无法 foreground/route，现作为 `input-route-unavailable` pending，不计通过。唯一确认的启动 SIGSEGV 是 `41370553563`，`9f2c70a` readiness handshake/nil guard 后多个 Release smoke 未复现；不得将测试假红等同 crash，也不把 smoke 当绝对无崩溃证明。
- Linux Xvfb 和 hosted Linux/Windows 原生 Ctrl+拖放均通过：adapter fixture 的 drop-over 报 copy，callback 收到目标 doc 7002/v4、UTF-16 offset 6；同文档 move 与外部 text 路径仍过。OS 输入 probe 不直接调用工作台 handler，真实 handler 由独立 widget test 经 PR CI 复核。Linux 本地证据 `docs/diagnostics/2026-11-02-p04/p04.61-cross-document-text-copy-linux-xvfb/`；hosted artifacts `13129633026` / `13130780116`。完整 `init.sh` 再次 EXIT=0（Flutter 598、Rust workspace、Clippy、build_core）；Flutter analyze 与 cargo fmt 通过。
- GitNexus 原预编辑索引报告 CRITICAL；重新索引至 `0eccaf3` 后 `_onCrossDocumentTextCopyDrop` 与 `RustTextInputFieldState` 当前 impact 为 LOW/exact，但 `_buildEditorTextDropRequest` 为 UNKNOWN/no callers，文本搜索确认它作为 `DropRegion.buildDropRequest` callback 使用。图谱仍提示 557 个跨语言属性访问未链接，风险和索引变化见 `docs/diagnostics/2026-11-02-p04/p04.61-cross-document-text-copy.md`，不把低风险或 UNKNOWN 当作路径完整证明。
- 下一步：P04.62 / EDT-11d 已在 docs/03 定义：复用 P02.7 Rust workspace 原子事务，新增跨文档 Move 的 linked undo/redo；先实现 pair history 的清除、关闭、预算淘汰语义，再接入拖放。Linux/Windows Ctrl Copy 已有 hosted evidence；macOS DnD 仍 pending（artifact `13130327858` 明确 route unavailable），500 MiB 目标仍留 P14。

### 前次进展（2026-11-02，P04.60 / EDT-11b 外部纯文本拖入）

- 新增单项 `text/plain` 外部拖入：`DataReader` 异步读取（10 秒超时并取消）、65,536 UTF-16 上限、stale/IME/pending/只读状态保护、CRLF/CR 到 LF 归一、Rust 单次插入与单步 undo；串接光标、分屏、dirty、Find、语法和保存路径。localData 类型可识别但损坏时不会退化为外部复制；未改 ABI/Rust GUI 依赖。
- `text_drag_drop_test.dart` 与 adapter widget 定向 12 项通过；Linux X11 本地原生 probe 在 Xvfb 中分别完成内部 move 与外部 plain-text copy，external callback 收到 `external text`、document 7002/v4/offset 6。最终复跑证据：`docs/diagnostics/2026-11-02-p04/p04.60-external-plain-text-drop-linux-xvfb-final2/`。`cargo fmt --all -- --check`、`flutter analyze`（0 issues）及完整 `FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 593）通过。
- Linux 本地/hosted 与 Windows hosted 的内部 move、外部纯文本 copy 双路径均通过。Platform Availability [`41406646083`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41406646083)、PR CI [`41406657349`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41406657349) 全绿；Windows artifact `13123619387` 回报 `external text` / 7002/v4/offset 6 及 `alpha` / move / offset 11，pointer cancel 伴随成功 drop。新 Platform run [`41411218584`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41411218584) 的 Linux/Windows artifacts 再次通过相同两条路径；macOS Release/launch/package 通过，但 DnD artifact 明确记为 route unavailable / all tests skipped，不能算原生 DnD 通过。startup artifact 只有 Impeller 日志、无 crash report；ARM64 validation 包不是 v0.1.0 发行件。真实 macOS native DnD 仍 pending，P04.59 同文档 DnD 也保持 pending。
- CI 线索复核：近期红灯主要来自 `Platform Availability` 的输入/teardown 测试路径；常规 CI run `41406657349` 全绿。修复后本次 Linux/Windows lanes 全过；历史真实 SIGSEGV `41370553563` 与 runner 假红分开，`9f2c70a` readiness handshake 后近期启动 smoke 未复现。GitNexus staged/all 变更审计仍报 CRITICAL 并将新私有拖放方法映射到无源码引用的 Build/ApplyWorkspaceEdit 流程；证据与未解决风险见 P04.60 报告，不宣称图谱审计 clean。
- 报告：`docs/diagnostics/2026-11-02-p04/p04.60-external-plain-text-drop.md`。下一步：按 docs/03 选择 EDT-11 的一个后续架构切片；macOS DnD 保持待验。

### CI 修复记录（2026-11-02，P04.59 / EDT-11a）

- commit `5c1c501` 修复 Windows 两类 CI 假红：50,000 行测试 teardown 先卸载并排空 100ms，再以最多 5 秒重试删除；原生拖放探针接受插件接管时的 pointer cancel。定向 `flutter test --no-pub --reporter expanded test/workbench_multi_view_test.dart` 5 项通过，Dart format 与 Python AST 检查通过。Platform `41400262650` 和 PR CI `41400267570` 全绿，Windows P03.7、clipboard、accessibility、close smoke 均通过；DnD artifact `13121491263` 为 alpha/move/UTF-16 offset 11。Linux X11 artifact `13120289367` 通过。macOS hosted DnD artifact `13121237662` 明确因输入路由不可用而 SKIP；startup artifact `13121502027` 无 `.ips`/`.crash`，ARM64 验证包 `13121626550` 不是 v0.1.0 发行包。P04.59 仍待真实 macOS 原生拖放验收。详见 `docs/diagnostics/2026-11-01-p04/p04.59-same-document-text-drag.md`。

- 本轮提交 `0157e7f` 已 push；PR CI [`41395923079`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41395923079) 与 Platform Availability [`41395917970`](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41395917970) 全绿。Linux hosted X11 native DnD 通过，artifact `13118594194` 收到 down/move/up 并完成 alpha/move/UTF-16 offset 11；Windows Release/交互/剪贴板/UIA/关闭 smoke 通过；macOS Release/clipboard/launch/package 通过。macOS route-check artifact `13119946021` 明确 route false 并 `All tests skipped`，所以仍不是 macOS 原生拖放验收。macOS startup artifact `13119378925` 仅有 Impeller 与窗口/AX 诊断，无 `.ips` / `.crash`；验证包 artifacts `13118923216`/`13119138490`/`13119677748` 不是 v0.1.0 发行包。
- 失败计数复核：最近 50 条 Actions run 中 18 条失败；14 条含 macOS 合成 DnD 输入无法路由的红灯，两条 Windows P03.7 失败均为 50,000 行用例 teardown 时目录被占用（runs `41372382625`、`41386803238`），另有零星 macOS clipboard/Swift helper/Flutter analyze 错误。修复后 `41400262650` 与 `41400267570` 全绿。历史真实 SIGSEGV 仍只指向 `41370553563`，修复 commit `9f2c70a` 后 launch smoke 未重现；测试失败不能等同应用崩溃。

- CI 证据区分了真实崩溃与测试假红：`41370553563` 的 macOS `.ips` 为真实启动 SIGSEGV，栈顶 `objc_loadWeakRetained` → `IrondashEngineContextPlugin getFlutterView:`。commit `9f2c70a` 增加 `irondash_engine_context 0.5.5` 的 FlutterView readiness handshake 和 nil guard，`EditorNativeTextDragDrop` 等 handshake 成功后才创建原生区域。修复后的多次独立 Release launch smoke 未复现崩溃，最新 startup artifact `13113715849` 只有 Impeller 初始化日志；继续保留 crash-report 观察。
- 已修复根 analyzer 扫描 Cargokit 独立 build tool 的失败（`1fbda68`）。PR CI `41380284226` 的 Flutter analyze/tests、Rust Ubuntu/Windows 和文档门全绿；Platform Availability `41380278756` 的 Linux、Windows 全 lane 通过，macOS analyze/tests、Release、clipboard、launch smoke 与 package 通过。
- macOS DnD 注入仍不能进入 Flutter：helper 的 `CGEventPostToPid pointer route` 为 false，Flutter pointer log 为空。workflow 现在将该 hosted-input 限制明确标为 SKIP；artifact `13113691238` 显示 `All tests skipped` 且无 teardown 异常。此前 `41375984424` 的 40 秒超时被 `dadfcdd` 改为显式 skip；`41377581941` 暴露进程过早结束的 temporary listener 清理错误，`64216dd` 改为 marker 协作退出，`41379092637` 又暴露 SemanticsHandle 清理问题，已由 `fd136b1` 修复并经最新 CI 验证。历史 `.ips` 启动崩溃与这些 runner/test 清理问题是不同故障。
- AppKit 路由尝试 run `41390211533` 的 DnD-only timeout 已复核为 runner 输入路径不通，而非应用崩溃；恢复路径已提交为 `04e5055`。PR CI `41392102903` 与 Platform Availability `41392097712` 全绿：Linux、Windows lane 全过；macOS analyze/tests/Release/clipboard/route-check/launch/package 通过。DnD artifact `13118336741` 报 `CGEventPostToPid pointer route: false`、无 Flutter pointer events、`All tests skipped` 且无 teardown error；startup artifact `13118386486` 只有 Impeller 初始化日志，无 crash report。Linux/Windows/macOS 包 artifacts `13117898191`/`13118500343`/`13117399408` 是验证产物。真实 macOS 原生 DnD 仍 pending。
- 2026-11-02 新增 Linux X11 原生输入证据：用普通 `flutter run -d linux` fixture（不使用会拦截 PointerDown 的 `LiveTestWidgetsFlutterBinding`）配合独立 Xvfb/XTEST/xdotool 完成 24 点拖动，Flutter 观察到 down/move/up，拖动源、目标 hover、drop 与完成回调均触发；`alpha` 以 move 操作落在 UTF-16 offset 11。证据在 `docs/diagnostics/2026-11-02-p04/p04.59-linux-native-dnd-xvfb/`。Platform Availability 新增同款 Linux probe 和 artifact 上传，hosted CI 结果待提交后确认。
- P04.59 仍 in-progress：macOS hosted runner 不能把合成指针路由到 Flutter，Linux 证据不替代 macOS；下一步先做本切片全量 DoD、GitNexus 变更审计、精确提交并 push，查看 Linux probe、PR CI 与 macOS route-check 结果。继续避免本机 GUI 操作；真实 macOS 原生 DnD 验收前不推进 EDT-11 后续切片，500 MiB 优化仍留 P14。报告：`docs/diagnostics/2026-11-01-p04/p04.59-same-document-text-drag.md`。

### 前次记录（2026-11-01，P04.59 / EDT-11a 进行中）

- 接入有界同文档原生文本拖放：同视图/分屏视图 move/copy、绝对 UTF-16 payload、Rust 版本与源范围复核、单帧 undo/redo、stale/IME/pending 输入保护；拖出提供 `text/plain`，系统确认 move 后只在源版本仍有效时删除源文本。外部拖入、多文档 provider 与 Paste As 留后续切片。
- run `41288093654` 的 `.ips` 报告（artifact `13076640390`）显示 macOS faulting thread 为 `objc_loadWeakRetained` → `IrondashEngineContextPlugin getFlutterView:`，registry context 为空，后续栈位于 `super_native_extensions`。插件在 main queue 异步发布 FlutterView，首帧 DropRegion/Draggable 会请求它；高置信假设是启动时序重叠。commit `2cca8e6` 将 macOS 原生拖放壳推迟到首帧后，Linux/Windows 不延迟，并新增首帧 widget 回归。其 PR CI `41290051650` 与 Platform Availability `41290048090` 的 attempt 1、2 均全绿；两次 macOS Release launch smoke 均未复现 SIGSEGV，也未产生 crash report。此前重复 CI 红灯中，Clippy lint、断言、剪贴板解码及 fixture teardown 竞态均发生在测试/构建路径，不能单独解释应用崩溃；历史 Windows `0xC000041D` 仍由 P15 独立验证。
- 修复本地及 hosted 回归：新增首帧 widget test 通过；完整 `flutter test` 590 项通过；`flutter analyze` 0 issues；`cargo fmt --check` 通过；`bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 590）。PR CI 与 Platform Availability 的 Linux/Windows/macOS 测试、构建和启动 smoke 均通过。macOS ARM64 验证 artifact `13077042325` / `13077766892` 已生成；它们不是 v0.1.0 公开发行包。`flutter test -d linux` 合成手势未启动原生 drag provider；Xvfb 打开隔离工作区通过，真实原生 DnD 交互仍 pending。
- GitNexus 本阶段 pre-edit `EditorNativeTextDragDrop` upstream impact 为 CRITICAL（79 symbols、145 processes、20 modules）；`RustTextInputFieldState` 也为 CRITICAL（48/114/20）。提交前全树 detect 为 CRITICAL（46 files、18 symbols），重复扫描流程计数观测范围 171–388；staged detect 为 CRITICAL（7 files、7 symbols），也观察到 171–388 条流程，含测试入口 `main` 与文档 section，流程只展示前 10 条。保留风险，不把全树/通用名称匹配计数归属本切片或降级。

### 最新进展（2026-11-01，P04.58 / EDT-10f 完成）

- 富文本桌面剪贴板已接入 plain text、Code-OSS v1 `vscode-editor-data` 和有界 HTML token 输出；剪切、单选/空选区/多光标复制及粘贴读取复用统一适配。Linux 原生回读曾把自定义 target 返回为 UTF-8 bytes；解码器现在接受 `String`/`Uint8List` 并设置 1 MiB 上限。
- Linux Xvfb 原生剪贴板集成测试通过，覆盖 plain text、HTML 和 metadata 往返；定向套件原为 25 项；CI 修正后 27 项通过。完整 `bash init.sh` 通过（Rust workspace、Clippy、build_core、Flutter 579），`cargo fmt --all -- --check` 通过，Flutter analyze 0 issues，Linux Release bundle 构建通过。报告：`docs/diagnostics/2026-11-01-p04/p04.58-rich-text-clipboard.md`。
- 结合用户提供的线索复核 CI：历史重复 Windows CI 红灯集中在 Clippy 测试 fixture lint，修复后后续 runs 连续绿；一次 50k 行临时目录 teardown 占用是测试清理竞态。P04.58 首轮 `41278747568` 暴露 Windows widget mock/native channel 冲突与 macOS custom type 映射；follow-up `41279726799` 通过 Linux/macOS、Windows P03.7，但发现 Windows metadata UTF-16LE/NUL 解码问题。commit `200d6de` 将 Windows MIME 改为 raw UTF-8 并兼容 UTF-16LE/BE/NUL；本地目标回归 27 项、Flutter analyze 0 issues。最终 CI `41280923105` 与 Platform Availability `41280920056` 均全绿，三平台 clipboard、Release/launch 与 Windows accessibility/close smoke 通过。各失败 run 仅报告测试或 metadata 问题，没有应用崩溃/`0xC000041D`；不解释旧 artifact crash，P15 旧精确 artifact 复核仍 pending。
- GitNexus `EditorClipboard` upstream impact 为 CRITICAL（171 impacted nodes、72 reported flows、20 modules、2 direct callers），结果有截断和跨语言边界，保留最高风险。 提交前 all-scope `detect-changes --limit 1000` 为 CRITICAL（54 files、10 symbols、339 processes；流程清单仍截断），含未归属当前切片的既有用户改动，保留最高风险。CI 与三平台原生剪贴板 smoke 已通过；P04.58 已完成，P15 原生剪贴板验收 pending。
- CI 修正后、提交前再次执行全树 GitNexus detect：CRITICAL，48 files、13 symbols、169–293 processes（重复扫描间波动），流程清单仍截断；工作树还含其他既有改动，风险不按总数归属或降级。分析已刷新，Flutter analyze 无问题。
- Windows native MIME 修正后的 precommit detect 同样为 CRITICAL：47 files、14 symbols，重复扫描 175–394 processes、165–384 条未展开；检测含有既有工作树改动，保留风险且不把数字当作本切片影响数量。

### 最新进展（2026-11-01，P04.57 / EDT-10e 完成）

- 完成多光标 clipboard metadata：用有界单条纯文本 sidecar 精确匹配最近一次复制，恢复包含内嵌换行的 `multiCursorText`；目标光标按文档顺序映射，CRLF/CR 片段归一为文档 LF。普通/覆写多光标粘贴接入；外部剪贴板、文本变化、数量不符与超限退回普通纯文本路径。记录上限 64 Ki UTF-16 文本、64 Ki 分段总量和 10,000 项；不改 ABI。
- 新增元数据 exact-match、不可变快照、失效、界限、混合行尾、分发回退/文档顺序与 Windows/Linux 工作台测试，定向组合 45 项通过。完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 573）；`cargo fmt --all -- --check` 通过，Flutter analyze 0 issues。报告：`docs/diagnostics/2026-11-01-p04/p04.57-clipboard-metadata.md`。
- CI 失败复核：重复 Windows Clippy 失败是测试 fixture 对 `set_readonly(false)` 的 lint，未启动 Alula，已由 `fd54663` 修复；一次 Windows integration 失败来自 50k 行 fixture 临时目录删除 race，应用启动/关闭与后续可访问性步骤成功。P04.57 commit `1f37b41` 的 CI `41275162368` 与 Platform Availability `41275159178`（Linux Xvfb、Windows 可见窗口/交互/辅助功能/WM_CLOSE、macOS Release 打包与启动）全绿。上述失败不解释历史 `0xC000041D`；该 artifact 仍需 P15 原生复核。
- 提交前 GitNexus `detect-changes --scope all` 报告 51 files、32 symbols、151 affected processes，risk=CRITICAL。全量工作树含大量既有改动，命令返回的符号/流程列表有省略，按最高风险记录，不以计数或截断降级；详见 P04.57 报告。
- 下一步：按固定 Code-OSS 对照拆解 `text/html` 与 `vscode-editor-data` 富文本剪贴板；P15 的 Linux DRM、Windows UIA/IME/关闭/主题/DPI 与 macOS 原生验收仍 pending。

### 上一片（2026-11-01，P04.56 / EDT-10d 完成）

- 多光标 `Ctrl/Cmd+X` 已覆盖混合非空选区与空光标：非空范围剪切选中文字，空光标复制并删除 Rust 权威整行；处理中间/末行 EOL，读取输入窗外绝对 UTF-16 范围，版本与选择快照校验后一次 Rust 事务接通 undo/redo、dirty、双视图、Find 和显式保存。无 ABI 变化。
- 新增 Windows/Linux/macOS `TargetPlatform` fixture 及 3×12,000 UTF-16 单元长行窗口外光标 fixture；与复制、单光标空行剪切和多选回归合计 29 项通过。完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 563）；`cargo fmt --all -- --check` 通过，`flutter analyze --no-pub` 0 issues。报告：`docs/diagnostics/2026-11-01-p04/p04.56-empty-selection-multicursor-cut.md`。
- CI 故障复核扩大到 6 个连续 Windows CI 失败 run（41260806566、41262203418、41264327454、41264593223、41266093481、41267027526），均只在 Windows Clippy 因 `permissions_set_readonly_false` fixture 清理 lint 失败；这些 job 没构建/启动 Alula，修复已在 `fd54663`。P04.56 commit `fc032cf` 的 CI `41273058892` 全绿；Platform Availability `41273053709` 的 Linux/Windows/macOS lane 全通过，包含 Windows 交互/辅助功能/WM_CLOSE 与 macOS 构建打包。另一个 41264323909 integration 失败发生于 fixture 目录删除 race，应用关闭结果仍为 `gracefulClose=true` / exit 0。该失败簇不能解释旧 artifact 的 `0xC000041D`；当前 Windows hosted close smoke 通过，但旧 crash 是否对所有原生用户会话修复仍由 P15 验证。
- GitNexus 复核：staged 与 all-scope detect 跨重复扫描都在 HIGH/CRITICAL 间波动，按最高风险保留 CRITICAL；compare-main 多次为 CRITICAL 且列表 capped。当前分析仍漏 817 entry points、399 callees、10 truncated walks。shared `_copyableDocumentSelectionTexts` upstream CRITICAL 保持不降级；报告保留源码复核与测试证据。
- 下一步：按固定 Code-OSS 对照推进 rich-text clipboard slice。P15 的 Linux DRM、Windows UIA/IME/关闭/主题/DPI 与 macOS 原生验收仍 pending。

### 最新进展（2026-11-01，P04.55 / EDT-10c 完成）

- 完成多光标空选区复制：Ctrl/Cmd+C 按文档顺序处理 Rust 绝对 UTF-16 选区；空光标复制当前逻辑行和 EOL，同一行重复空光标去重，非空选区复制所选文本，各段按文档 EOL 拼接。Windows 强制 CRLF，Linux/macOS 使用文件 EOL 元数据；读取可越过有界输入窗，并校验版本与 selection 快照，不改变 buffer、dirty 或磁盘。多选剪切路径未改，无 ABI 变化。
- 新增 4 项测试：Windows/Linux/macOS TargetPlatform EOL fixture，以及 12,000 UTF-16 单元行的输入窗外光标 fixture。与既有多光标测试组合共 21 项通过。完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 559）；`cargo fmt --all -- --check` 与 `flutter analyze --no-pub`（0 issues）通过。报告：`docs/diagnostics/2026-11-01-p04/p04.55-empty-selection-multicursor-copy.md`。
- CI 复核：run `41267446041` 只在 Windows Clippy 的只读 fixture 清理 lint 失败，已由 `fd54663` 修复；CI run `41270079204` 全绿。Platform Availability run `41270075211`（代码仍是 P04.55 前的 `a75359e`）通过 Linux/Windows 构建启动、Windows 桌面交互/辅助功能与 macOS 打包启动。此前 Clippy 失败未启动应用，因此没有证据说明它导致关闭崩溃；P15 运行时复验仍单独 pending。
- 下一步拆 EDT-10 剩余多光标空选区剪切、clipboard metadata / rich text；平台 TargetPlatform fixture 不代替原生 P15 验收。

### 上一片进展（2026-11-01，P04.54 / EDT-10b 完成）

- 完成空选区剪切当前行：Ctrl+X/Cmd+X 先复制 Rust 当前逻辑行并附加平台/文件 EOL，再通过已有 Rust 权威删除行事务删除该行。中间行删除后续分隔符，末行删除前置分隔符，单行文档变为空文档；剪贴板写入后重新核对版本、焦点、光标与可写状态。
- 新增 4 项 Windows/Linux/macOS `TargetPlatform` fixture，覆盖 Windows 强制 CRLF、emoji 中间行、单行文档、Linux 无末尾换行末行、macOS CRLF 文件空行；验证 clipboard、Rust 全文、dirty、undo/redo 和显式保存前磁盘不变。定向 4 项通过。
- 完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0：Rust workspace、Clippy、build_core、Flutter 555；`cargo fmt --all -- --check` 与 `flutter analyze --no-pub`（0 issues）通过。报告：`docs/diagnostics/2026-11-01-p04/p04.54-empty-selection-cut-line.md`。
- EDT-10 剩余多光标空选区与 clipboard metadata / rich text 仍待拆分；P15 原生设备与辅助功能验收保持 pending。

### 上一片进展（2026-11-01，P04.53 / EDT-10a 完成）

- 完成空选区复制当前行：单光标空选区按 Ctrl+C/Cmd+C 复制 Rust 文档当前逻辑行并附加 EOL；Windows clipboard 强制 CRLF，Linux/macOS 遵循文档行尾元数据。读取通过 Rust `lineBoundary` 与版本校验的有界范围读取；复制不改文档、selection、dirty 或磁盘。
- 新增 Windows/Linux/macOS `TargetPlatform` 集成 fixture，覆盖无末尾换行的末行、Windows CRLF、Linux LF、macOS CRLF，并确认文本/磁盘字节不变；定向 3 项通过。
- 完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0：Rust workspace、Clippy、build_core、Flutter 551；`cargo fmt --all -- --check` 与 `flutter analyze --no-pub`（0 issues）通过。报告：`docs/diagnostics/2026-11-01-p04/p04.53-empty-selection-copy-line.md`。
- EDT-10 后续剪切、多光标空选区、clipboard metadata 与富文本仍待拆分；P15 原生设备与辅助功能验收保持 pending。

### 上一片进展（2026-11-01，P04.52 / EDT-09e 完成）

- 对照固定 Code-OSS `editor.action.insertFinalNewLine` 注册无默认快捷键的命令面板项。每次在全文 EOF 插入一个当前 EOL；已有末尾换行时仍会追加另一个。由于 Alula 文档缓冲统一为 LF，通过 Rust 权威 TextOps 插入 LF，保存时沿用文档 EOL 元数据。
- 命令检查只读与 IME 状态，按独立撤销帧提交；插入前后版本校验、映射 selection（EOF 光标右移，前置选区不变）、刷新输入窗口与分屏，接通 dirty、Find、undo/redo 和保存回读。ABI 未改。
- 新增 4 个 Flutter 用例：Windows/Linux/macOS `TargetPlatform` 下覆盖 UTF-8 BOM、CRLF、emoji、中间/EOF 选区、分屏、保存、撤销/重做、重复执行；空文件也能执行。定向测试全过。最终完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 548）；`cargo fmt --all -- --check` 通过，`flutter analyze --no-pub` 0 issues。报告：`docs/diagnostics/2026-11-01-p04/p04.52-insert-final-newline.md`。
- Code-OSS 保存设置 `files.insertFinalNewline` 与 `files.trimFinalNewlines` 尚未实现；本次只交付显式命令。P15 原生 Windows UIA/关闭/主题/DPI、Linux DRM 与 macOS 验收保持 pending。

### 最新进展（2026-11-01，P04.51 / EDT-09d 完成）

- 新增 `editor.action.indentationToSpaces` 与 `editor.action.indentationToTabs` 命令面板项。Rust Rope 规划器只转换全文每行的前导空格/tab，绝对偏移使用 UTF-16；转 tab 保留不足 tabSize 的余数，保留 BOM、行尾与 CR/LF/CRLF。Rust/Dart FFI 升至 ABI v37，界限为 32 Mi UTF-16 扫描、10,000 行编辑、2,000,000 UTF-16 undo payload、5 MiB 响应和 tabSize 1–32。
- 工作台校验 Rust 版本与每段原文后一次性 TextOps 提交，接通选区映射、undo/redo、dirty、Find、分屏与 BOM+CRLF 保存回读。同文档分屏共享 transient `insertSpaces`；后续 Tab、行缩进/反缩进及括号内自动缩进使用该模式。当前 tabSize 固定为 4，设置持久化/UI 留 P07，状态栏缩进选择器尚未接入。
- Rust 定向 buffer 2 项、FFI 1 项与 Flutter 三平台 `TargetPlatform` fixture 3 项通过。完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 544），`cargo fmt --all -- --check` 通过，`flutter analyze --no-pub` 0 issues。报告：`docs/diagnostics/2026-11-01-p04/p04.51-indentation-conversion.md`。
- Windows 11 exact artifact run `41109679662` 的自动原生回放记录在 P03.7 报告：客户区和双视图编辑同步、保存回读、Microsoft Pinyin 通过；关闭时 Flutter 崩溃，UIA/Narrator 标签与布局未通过。该证据仍只覆盖暗色 125% DPI；主题切换、100%/150%、原生 DRM Linux 和 macOS 保持 P15 pending。

### 最新进展（2026-11-01，P04.50 / EDT-09c 完成）

- P04.50 完成固定 Code-OSS `editor.action.trimTrailingWhitespace`：Windows/Linux `Ctrl+K Ctrl+X`，macOS `Cmd+K Cmd+X`。Rust Rope 版本化 UTF-16 planner 只删除行尾 ASCII 空格/tab，保留 CR/LF/CRLF 与 NBSP；扫描、edit 数、删除/undo payload 和 FFI JSON 响应均设上限。ABI 双侧升至 v36，工作台校验删除全文与版本，批量接入 selection 映射、undo/redo、dirty、Find、双视图及 BOM+CRLF 保存回读；双段键位解析也接入当前注册的多键序列。
- Rust buffer/core/FFI、Dart bridge、KeybindingSet 与三平台 TargetPlatform fixture 通过；定向 Flutter 27 项通过。完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 541）；`cargo fmt --all -- --check` 与 `flutter analyze --no-pub` 均通过（0 issues）。
- 本片只实现显式命令；Code-OSS 保存设置 `files.trimTrailingWhitespace`（默认关闭）和 auto-save 光标行跳过尚未接入。32 Mi UTF-16 扫描/2,000,000 UTF-16 删除上限会安全拒绝超限文档；极大文档与原生平台行为尚未对照。报告与 GitNexus 结果：`docs/diagnostics/2026-11-01-p04/p04.50-trim-trailing-whitespace.md`。P15 原生 Windows/Linux/macOS 验收仍 pending。

### 上一片进展（2026-11-01，P04.49 / EDT-09b 完成）

- P04.49 完成固定 Code-OSS Toggle Block Comment：Rust UTF-16 planner、NUL-safe FFI ABI v35，Windows/macOS Alt+Shift+A、Linux Ctrl+Shift+A。Rust/JS/TS 配置 `/*` 与 `*/`，接入空 caret pair、选区包围/取消、Code-OSS selection mapping、版本/全文一致性校验、undo budget、undo/redo、dirty、Find、分屏与 BOM+CRLF 保存回读。planner 限制 10,000 选区、endpoint line 64 Ki UTF-16、总扫描 2,000,000 UTF-16、token 16 visible ASCII；超限与重叠选择原子拒绝。Rust 66、FFI/core 44，Flutter 定向 25 与全量 535 通过；cargo fmt 和 Flutter analyze 0 issues。Python/plaintext 及其他语言的 block token 暂未接入，P15 原生 Windows/Linux/macOS 验收仍 pending。证据：`docs/diagnostics/2026-11-01-p04/p04.49-toggle-block-comment.md`。

### 上一片进展（2026-11-01，P04.48 / EDT-09a 完成）

- P04.48 完成固定 Code-OSS Toggle Line Comment：Rust UTF-16 planner、NUL-safe FFI ABI v34、Windows/Linux Ctrl+/ 与 macOS Cmd+/，接通 Rust/Python/TypeScript/JavaScript token、版本/全文一致性校验、撤销预算、selection、undo/redo、dirty、Find、双视图与 BOM+CRLF 保存回读。Rust 和 FFI 用例覆盖空白行、行尾 column-1、emoji/CRLF 与边界；三平台 workbench 测试覆盖快捷键、分屏、保存、撤销重做、Python 与 plaintext。完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` 通过（Rust workspace、Clippy、build_core、Flutter 530），cargo fmt 与 Flutter analyze 0 issues。重叠多选区采取保守整批拒绝；未知语言安全 no-op；块注释与 EDT-09 其余清理项仍待后续切片。证据：`docs/diagnostics/2026-11-01-p04/p04.48-toggle-line-comment.md`。P15 原生 Windows/Linux/macOS 验收仍 pending。

### 上一片进展（2026-11-01，P04.47 / EDT-08g 完成）

- P04.47 完成固定 Code-OSS Emmet 六项数值变换：Rust UTF-16 bounded planner 与 NUL-safe FFI ABI v33，工作台按版本校验并单批提交，接通 selection、undo/redo、dirty、Find、分屏与 BOM+CRLF 保存回读。Rust/FFI/bridge/工作台覆盖六种步长、舍入/格式边界、多光标和无数字 no-op。完整 `init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 525），cargo fmt 和 Flutter analyze 0 issues；详细差异与 GitNexus 限制见 `docs/diagnostics/2026-11-01-p04/p04.47-emmet-numeric-transform.md`。超长 token 窗口边界与重叠多光标差异已登记；P15 原生验收仍 pending。

### 上一片进展（2026-11-01，P04.46 / EDT-08f 完成）

- 新增固定 Code-OSS `editor.action.transposeLetters` 命令，macOS Ctrl+T、Windows/Linux 无默认键位；Rust UTF-16 计划支持 LF、CRLF、CR、Unicode scalar 与 NUL-safe FFI ABI v32。工作台复用有版本门控的单批 TextOps，接入独立多光标、selection 跳过、重叠范围原子取消、undo/redo、dirty、Find、分屏和保存。
- Rust buffer/FFI 转置定向 5 项与 Flutter bridge/工作台定向 34 项通过；最终完整 `init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 520），`cargo fmt --all -- --check` 和 `flutter analyze --no-pub` 通过（0 issues）。报告：`docs/diagnostics/2026-11-01-p04/p04.46-transpose-letters.md`。
- 交叠多光标编辑范围采用全批次取消；固定版 Code-OSS 在该冲突场景尚无原生自动化对照。P15 原生 Windows/Linux/macOS 验收仍 pending。

### P15 Windows 11 自动回放（2026-11-01 归档）

- 自动运行 GitHub Actions [41221325692](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/41221325692)，下载并运行指定 artifact run 41109679662。Windows 11 Enterprise build 26200 ARM64/x64 emulation 在 96 DPI 下完成可见客户区、MSAA、双视图和保存回读；独立源码交互 job 的 14 项 Flutter Windows 桌面测试全部通过。
- Release artifact 仍未过验收：light registry 设置下渲染仍为暗色；runner 没有 IMM context，不能验证真实 Pinyin；Narrator UIA 只有窗口/FlutterView，没有四项必需语义节点；`WM_CLOSE` 与无无障碍查询对照都以 `0xC000041D` 退出。截图、metadata、Narrator/关闭诊断与 source log：`docs/diagnostics/2026-11-01-p03/p03.7-windows11-hosted-artifact-41221325692.md`。
- P03.7 / EV-P03-WIN11-UI-A11Y-DPI 与 P15 保持 pending。真实 x64 Windows 11 的 125%/Pinyin 结果仍以既有 exact-artifact 报告为准；本次 96 DPI ARM64 emulation 不替代原生 x64、语音采集或 DPI 矩阵。


### 最新进展（2026-11-01，P04.44 / EDT-08d 完成）

- 新增固定 Code-OSS `editor.action.transformToSnakecase` 命令，无默认快捷键；Rust 实现 Unicode lower→upper/acronym 边界和完整 lowercase，并经 ABI v30 NUL-safe JSON FFI 调用。沿用既有 UTF-16 选区/caret 事务、撤销/重做、多视图同步和保存路径。
- Rust buffer/FFI、Dart ABI 握手、三平台 TargetPlatform 工作台测试通过；工作台 fixture 保留用户给出的 `fn main() { println!("linux-save-ok"); }`，并覆盖 selection、caret、双视图、undo/redo、BOM+CRLF 保存回读。完整 `init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 510），cargo fmt 通过，Flutter analyze 0 issues。报告：`docs/diagnostics/2026-11-01-p04/p04.44-snake-case.md`。
- JS `toLocaleLowerCase` 的 locale-sensitive 行为和运行时 Unicode 数据版本仍有差异；TargetPlatform fixture 不替代 P15 原生验收。P04.43 已推送；GitNexus staged/all/compare 检查均为 CRITICAL，索引全局截断保留且未作无影响解释。

### 最新进展（2026-11-01，P04.43 / EDT-08c 完成）

- 新增固定 Code-OSS `editor.action.transformToCamelcase` 命令，无默认快捷键。Rust 按固定规则分别处理单行与多行分隔符、Unicode 首词大小写边界、ECMAScript whitespace，以及后续片段首 UTF-16 code unit；通过 ABI v29 的 NUL-safe JSON FFI 调用。编辑事务沿用 P04.41/42 的 Rust 权威范围、selection/caret 映射、版本/预算检查、undo/redo、dirty、Find、双视图与保存。
- 三平台 TargetPlatform 用例以 `fn main() { println!("linux-save-ok"); }` 为夹具，覆盖选词与 caret 下划线转换、分屏、undo/redo、BOM+CRLF 保存回读；Rust/FFI 覆盖 acronym、emoji、Deseret 字母、CRLF、NUL、NEL/BOM/Unicode line separator。完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 506）；cargo fmt check 与 app Flutter analyze 0 issues。报告：`docs/diagnostics/2026-11-01-p04/p04.43-camel-case.md`。
- 保留与 JS `toLocale*` 的系统 locale 和 Unicode 数据版本差异；TargetPlatform fixture 不代表 P15 原生平台验收。下一项按 EDT-08 拆解 Snake Case，仍一次只处理一个功能。

### 最新进展（2026-11-01，P04.42 / EDT-08b 完成）

- 新增固定 Code-OSS `editor.action.transformToTitlecase` 命令，无默认快捷键；先 Rust full lowercase，再按上游 Unicode letter/number/apostrophe 边界把首字母 full uppercase。沿用 P04.41 的 Rust UTF-16 范围事务、selection 扩展映射、undo/redo、dirty、Find、分屏与保存路径，Rust JSON FFI ABI 升至 v28。
- 三平台 TargetPlatform 测试验证选区/caret、`ß→SS` 长度变化、ASCII/curly apostrophe、Unicode letter/number、组合符、双视图、BOM+CRLF 保存回读及 undo/redo。完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 502）；cargo fmt check 通过，app Flutter analyze 0 issues。报告：`docs/diagnostics/2026-11-01-p04/p04.42-title-case.md`。
- 已登记 JS locale-sensitive case 与 Rust locale-independent mapping 的差异、Unicode 数据版本边界；Windows 11 UIA/Narrator、DPI/主题和原生 IME 仍在 P15。P04.41 commit `12987d0` 已推送。

### 最新进展（2026-11-01，P04.41 / EDT-08a 完成）

- 新增 Uppercase/Lowercase 固定命令，无默认快捷键。选区原样转换；caret 使用 VS Code 默认词分隔符和小数 token 定位，空白/空行不变；多光标范围去重后一次 Rust TextOps 事务提交。Rust 负责 Unicode full case mapping，通过 ABI v27 暴露 NUL-safe JSON 转换；选区长度随 `ß→SS` 扩展，undo/redo、dirty、保存和兄弟视图同步均覆盖。
- 三平台工作台测试覆盖 UTF-16 emoji 偏移、Turkish-like 字母、sharp-s expansion、Alt+Click 多光标、selection/caret、空白 no-op、BOM+CRLF 保存回读、撤销/重做与分屏。Rust buffer/FFI 转换用例和核心 ABI 握手通过。完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 498）；`cargo fmt --all -- --check` 通过；`app/ flutter analyze --no-pub` 0 issues。
- 已登记差异：未接入语言专属 wordPattern；Rust full Unicode 映射不模拟 VS Code `toLocaleUpperCase/LowerCase` 的系统 locale 特例。title/camel/snake/transpose/numeric transforms 继续分 slice。证据：`docs/diagnostics/2026-11-01-p04/p04.41-case-conversion.md`。GitNexus 调用图风险与索引截断保留；P15 原生平台验收 pending。

### 最新进展（2026-11-01，P04.40 / EDT-07g 完成）

- P04.39 `c62917d` 已推送并核对 `origin/codex/vscode-parity-p00`。随后完成 Code-OSS `editor.action.removeDuplicateLines`：单 caret/单行 selection 作用于全文，多选范围分别去重、末行含列 1 端点，精确行文本去重并保留首次出现；走 Rust UTF-16 有界读取、预算/版本/重叠门控和一个 TextOps 事务，涵盖 undo/redo、dirty、Find、分屏与保存。无 ABI 变化。
- 新增 6 项 Windows/Linux/macOS TargetPlatform 工作台测试，覆盖大小写/空白/空行、BOM+CRLF、选区边界、保留行 caret、undo/redo、分屏及保存回读。基于 `HEAD c62917d` 的隔离 stage 完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` 通过（Rust workspace、Clippy、build_core、Flutter 494），cargo fmt 与 app Flutter analyze 0 issues。证据：`docs/diagnostics/2026-11-01-p04/p04.40-delete-duplicate-lines.md`。
- 固定 Code-OSS 对单 caret 全文去重使用 `executeEdits` 内部 tracked-selection 映射；Alula 显式映射到首次保留行，重复行内部 caret 的原生 marker-collapse 仍待比较。GitNexus WorkbenchPage upstream impact CRITICAL，刷新图谱有未排名入口和 walk 截断，保持风险不降级。P15 原生平台/读屏/IME/DPI/主题/发行门继续 pending；500 MiB 留 P14。

### 最新进展（2026-11-01，P04.39 / EDT-07f 完成）

- 完成升序/降序 Sort Lines 命令，按固定 Code-OSS 行为处理单行选区全文排序、列 1 排除末行、全选区原子 no-op、降序反转、多选计划、版本/重叠/撤销预算与 100,000 行上限；Rust TextOps 单批提交并同步 selection、undo/redo、dirty、Find、输入窗和兄弟视图。无 ABI 改动。区域排序仍有已登记差异：Dart code-unit comparison 不能匹配上游 runtime `Intl.Collator` 的语言/大小写/重音结果。
- 三平台 TargetPlatform 工作台测试 6 项通过，覆盖升降序、全文 caret、列 1 端点、分屏、undo/redo、BOM+CRLF 保存回读与多光标原子取消。精确 detached `HEAD bd24edf` 快照的 `bash init.sh` 通过：Rust workspace、Clippy、build_core、Flutter 488；cargo fmt 检查通过；`app/` Flutter analyze 0 issues。报告：`docs/diagnostics/2026-11-01-p04/p04.39-sort-lines.md`。
- GitNexus 编辑前 WorkbenchPage impact 为 CRITICAL，命令注册与 KeybindingSet 为 LOW；fresh index 为 8,715 nodes / 27,433 edges / 389 reported flows，但 713/913 入口未排名、341 callees 跳过、9 walks 达预算。检测结果保留 CRITICAL/截断，不降级。

### 最新进展（2026-11-01，P04.38 / EDT-07e 完成）

- 完成固定 Code-OSS Join Lines 命令。macOS 用 Ctrl+J，面板切换改 Cmd+J；Windows/Linux 继续用 Ctrl+J 切面板，合并行从命令面板调用。Rust UTF-16 行范围和撤销预算内文本读取，经版本校验后一次 TextOps 批量应用，保持 undo/redo、dirty、Find、分屏同步和保存路径，无 ABI 变化。
- 三平台 targetPlatform fixture 覆盖单光标、选区、多 occurrence 光标、空行、EOF、undo/redo、双视图及 BOM+CRLF 保存回读；定向 22 项通过。detached `HEAD ad7063a` 精确功能快照 `bash init.sh` 通过，Flutter 482、Rust workspace、Clippy、build_core；cargo fmt 检查通过，Flutter analyze 0 issues。报告：`docs/diagnostics/2026-11-01-p04/p04.38-join-lines.md`。本地 Windows 11 精确旧 artifact 自动回放结果已记录在 `docs/diagnostics/2026-10-31-p03/p03.7-exact-windows-artifact-41109679662.md`；编辑/IME 一组通过，主题/布局/读屏焦点/关闭门失败，保持 P15 pending。
- GitNexus 编辑前 `_registerCommands` / `WorkbenchPage` CRITICAL、`KeybindingSet` LOW；提交前 staged（9 files）、all（46 files）和 compare `main`（1350 files）均 CRITICAL。重复检查的符号/流程计数有波动，不作为风险边界；fresh index 有 712/912 入口候选未排名、340 callees 跳过和 9 次 walk 达预算，风险不降级。只包含 P04.38 的提交推送待完成。P04 其它 EDT-07 操作、P15 原生平台验收继续开放。

### 最新进展（2026-11-01，P04.37 / EDT-07d 完成）

- 固定 Code-OSS 默认 Move Line Up/Down 命令与三平台 Alt+↑/↓。Rust UTF-16 行地址解析；端点跟踪覆盖下一行第 1 列、反向选择、多光标相邻行和空行；首尾行为按源码 no-op。单次预算内 TextOps 事务接入撤销/重做、dirty、split view 与保存回读。
- 新增 7 项定向用例：三平台移动、空行和多 occurrence-selection；组合 keybinding + 行移动套件 27 项通过。全量 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 478）；`cargo fmt --all -- --check` 通过，`flutter analyze --no-pub` 0 issues。证据：`docs/diagnostics/2026-11-01-p04/p04.37-move-lines.md`。
- 差异保留：Code-OSS 根据语言 `indentRules` / `onEnter` 对移动行进行 autoIndent；Alula 目前保留原缩进，完整语言配置缩进行为仍待办。GitNexus 编辑前 `WorkbenchPage` 与 `_registerCommands` 为 CRITICAL（分别 67/111 flows/20 modules 与 48 项/44 direct/2 flows/6 modules），`KeybindingSet` LOW；风险不降级。detached `HEAD ca9f7b5` 精确暂存 9 文件补丁的完整 init.sh、cargo fmt 与 Flutter analyze 均通过。GitNexus staged（9 files）、all（45 files，含既有改动）和 compare `main`（1348 files）均 CRITICAL；重复检查 observed affected-process 范围分别为 169–389、173–389、388–389。图谱报告 710/910 入口候选未排名、340 callees 跳过、9 次 walk 到预算。文档映射噪声不用于降级。分阶段提交待执行。

### 最新进展（2026-11-01，P04.36 / EDT-07c 完成）

- 新增 Code-OSS `editor.action.copyLinesUpAction` / `editor.action.copyLinesDownAction`，Windows/macOS Alt+Shift+方向键、Linux Ctrl+Alt+Shift+方向键；保留 Linux Alt+Shift 列选并将 Windows 列选移至 Ctrl+Alt+Shift，macOS 不注册列选快捷键。Rust UTF-16 行范围、预算与版本校验后由 TextOps 单批提交，更新选择/撤销/重做/分屏同步。
- 三平台 fixture 覆盖向上/向下复制、emoji、结束于下一行第 1 列的选区、两个 occurrence caret、双视图、undo/redo 和 BOM+CRLF 保存回读。完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0（Flutter 468、Rust workspace、Clippy、build_core）；cargo fmt 与 flutter analyze（0 issues）通过。报告：`docs/diagnostics/2026-11-01-p04/p04.36-copy-lines.md`。
- GitNexus `KeybindingSet` upstream LOW；命令注册、复制操作与 selection helper 查询为 UNKNOWN，源码调用点已确认；入口候选/跨语言属性边截断仍记录，风险不降级。精确暂存补丁应用于 detached `HEAD 25c5285` 的完整 init.sh 通过（Flutter 468、Rust workspace、Clippy、build_core），cargo fmt 与 Flutter analyze 0 issues；GitNexus 重复 detect-changes：staged 11 files / 3 symbols / 45–152 processes / CRITICAL；all-scope 47 files / 10–18 symbols / 144–152 processes / CRITICAL，风险保留。

### 最新进展（2026-11-01，P04.33 / EDT-06i 完成）

- Rust `< >` 现按固定语言配置仅作为 selection surrounding：选区输入 `<` 会成对包围；折叠光标输入 `<` 只插入一个字符，不自动闭合、不加 marker；`>` 保持普通输入。复用 UTF-16 TextOps、撤销/重做、dirty、双视图同步和保存。
- 新增 6 项工作台用例，覆盖三平台 TargetPlatform、Rust 示例、BOM/emoji/CRLF、普通 `>` 输入和 split view 保存回读。定向 bracket suite 24 项、P04.32–P04.33 组合回归 54 项通过；精确 `HEAD c816662 + staged patch` 隔离快照全量 init.sh EXIT=0（Flutter 456、Rust workspace、Clippy、build_core），cargo fmt 和 Flutter analyze 0 issues。报告：`docs/diagnostics/2026-11-01-p04/p04.33-rust-angle-selection-surrounding.md`。
- GitNexus staged 与 all-scope detect 均为 CRITICAL；流程数随文档文字变化，不据此降级编辑前 impact。`_applyRustBracketInput` upstream CRITICAL（66 symbols / 51 processes / 15 modules），`_focusNodeFor` UNKNOWN；源码调用点已核对，风险不降级。下一 slice 候选为 Rust 块注释 Enter 规则。

### 最新进展（2026-11-01，P04.32 / EDT-06h 完成）

- Rust `.rs` 双引号现按固定 Code-OSS 规则自动闭合：只在当前 Tree-sitter 快照的 `string` token 外配对；选区包围独立按 `surroundingPairs` 工作。Tree-sitter 本地刷新不要求启动 rust-analyzer，快照版本不匹配时按普通字符插入。只有仍由 marker 跟踪的右引号才会被跳过或与 Backspace 成对删除。
- 实现复用 Rust UTF-16 TextOps、既有 marker cap、撤销/重做、split view 和保存路径，无 ABI 变化。新增 9 项测试；定向回归 48 项通过，完整 `RUST_TEST_THREADS=1 bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 450），`cargo fmt --all -- --check` 通过，`flutter analyze --no-pub` 0 issues。证据：`docs/diagnostics/2026-11-01-p04/p04.32-rust-double-quote-pairs.md`。
- GitNexus `_applyRustBracketInput` 编辑前 upstream CRITICAL（53 reported processes / 9 modules），直接调用者为 `_focusNodeFor`；图谱其余映射异常不作降级依据。单引号配对、`<>` selection surrounding、块注释 Enter 与 P15 原生平台验收仍未覆盖；下一片从 `docs/03` / `docs/11` 拆解 P04.33。

### 最新进展（2026-10-31，P04.31 / EDT-06g 完成）

- Rust `.rs` 行注释现在按固定 Code-OSS 两条 `onEnterRules` 续写：Enter 左侧匹配行首/行内 `//` 内容且右侧仍有非空白文本时，在新行保留原缩进并添加 `// `；行尾、右侧纯空白和非折叠选区保持普通 Enter。此规则优先于 tracked bracket smart Enter。
- 实现使用 Rust UTF-16 行边界/范围，后缀检查计入既有操作预算；超过预算则安全回退，不改 ABI。新增 7 项用例，三平台、行内规则、tracked brace 优先级、尾部条件、选区、undo/redo 均覆盖。定向 27 项通过；完整 init.sh EXIT=0（Rust workspace、Clippy、build_core、Flutter 441），cargo fmt 与 `app/` Flutter analyze（0 issues）通过。证据：`docs/diagnostics/2026-10-31-p04/p04.31-rust-line-comment-enter.md`。
- GitNexus `_insertNewlineWithIndent` upstream CRITICAL（61 symbols / 44 direct / 3 flows / 3 modules）；真实 Enter 调用链已核对，图谱映射异常不作风险降级。接下来从 docs/03 / docs/11 继续 P04.32；quote pairing、块注释规则仍未覆盖，P15 原生平台验证 pending。

### 最新进展（2026-10-31，P04.30 / EDT-06f 完成）

- Rust `.rs` 中，Enter 现会将 Alula 自动插入且仍由 marker 跟踪的空 `()` / `[]` 展开为内层 +4 空格行与外层原缩进行，光标停在内层。非 Rust、源文件字面量括号、选区与 IME composition 继续走既有路径；复用 Rust 权威 UTF-16 TextOps 和共享 marker，无 FFI/ABI 变化。
- 新增 6 项 Flutter 用例，覆盖 Windows/Linux/macOS TargetPlatform 下两类括号、caret、undo/redo。智能回车与 Enter fallback 定向 20 项通过。完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 434）；cargo fmt 通过，Flutter analyze 0 issues。GitNexus `_insertNewlineWithIndent` LOW（5 symbols / 2 reported flows，callable-value 关系 lower-bound），`_focusNodeFor` HIGH（6 / 3）；风险保留。报告：`docs/diagnostics/2026-10-31-p04/p04.30-rust-smart-enter-paren-square.md`。
- 下一项从 `docs/03` / `docs/11` 选取 P04.31；token-aware 源括号 Enter、注释续行、引号仍未覆盖。P15 原生 DRM Linux、Windows 当前包视觉/读屏/关闭/DPI 与 macOS 原生验证仍 pending。

### 最新进展（2026-10-31，P04.29 / EDT-06e 完成）

- Rust `.rs` 中，Enter 处于 Alula 自动插入并仍由 marker 跟踪的空 `{}` 内时，会展开为内层加 4 空格及外层原缩进两行，光标进入内层；非 Rust、源文件字面量括号、选区与 IME composition 继续沿原 Enter 路径。复用 Rust 权威 UTF-16 TextOps、版本检查、预算和共享 marker，无 FFI/ABI 变化。
- 新增 5 个 Flutter 用例，覆盖 Windows/Linux/macOS TargetPlatform、undo/redo、未标记源括号回退，以及在 split view 中插入并保存 `println!("linux-save-ok");`。Enter 定向回归 14 项通过；`bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 428），cargo fmt 与 Flutter analyze（0 issues）通过；精确 HEAD + 暂存补丁隔离快照的 init.sh（Flutter 428）、cargo fmt 与 analyze 也全绿。报告：`docs/diagnostics/2026-10-31-p04/p04.29-rust-smart-enter.md`。
- GitNexus `_insertNewlineWithIndent` upstream LOW（5 符号/2 流程，但 callable-value 关系仍 lower-bound）；`_focusNodeFor` upstream HIGH（6 符号/3 流程）。不使用 `riskSharedAxes` 降级。接下来继续 EDT-06；token-aware 源括号/注释规则、`()` / `[]` 与引号仍未覆盖，P15 原生验证保持 pending。

### 最新进展（2026-10-31，P04.28 / EDT-06d 完成）

- Rust `.rs` 文件现在仅在所有光标都位于已自动插入的 `()[]{}` 之间时，按一次 Backspace 成对删除；字面量括号、非 Rust、非空选区、组合输入和跨窗选区仍走原输入路径。使用 Rust 权威 UTF-16 范围、文档版本校验与单批 TextOps，已有 marker 重映射负责移除配对记录；无 ABI 变化。
- 新增 9 项测试，覆盖 Windows/Linux/macOS TargetPlatform、三类括号、普通字符和字面量回退、多光标、split view、undo/redo 与保存回读。`bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 423）；cargo fmt 和 Flutter analyze（0 issues）通过；精确 HEAD + 暂存补丁快照的 full init.sh（Flutter 423）、cargo fmt、Flutter analyze 也全绿。报告：`docs/diagnostics/2026-10-31-p04/p04.28-rust-paired-backspace.md`。
- GitNexus pre-edit `_focusNodeFor` 为 HIGH，共享文档状态为 CRITICAL；staged detect 重跑为 CRITICAL（7 文件/7–11 可映射符号/114–136 流程），all-scope 为 CRITICAL（42 文件/17 符号/114–136 流程）。新私有方法仍为 UNKNOWN，调用点已源码核查；`--limit 1000` 仍截断流程列表且风险不降级。P15 原生键盘/IME/读屏/DPI 验收保持 pending。

### 最新进展（2026-10-31，P04.27 / EDT-06c 完成）

- 固定 Code-OSS commit `4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e` 的 Rust `language-configuration.json`，加入 Rust `()[]{}` 自动闭合、选区包围、默认 autoCloseBefore 边界与只跳过编辑器已插入 closer 的行为。使用 Rust 权威 UTF-16 TextOps，无 ABI 改动；跨 split view 共享的 auto-close marker 上限 10,000，随文档操作重映射，版本失配或对应括号删除时清除。
- 12 项目标测试通过，覆盖 Windows/Linux/macOS TargetPlatform、multi-cursor、选区、undo/redo、dirty/save/readback、BOM/emoji/CRLF、普通编辑后 skip、字面量 closer、split view 与非 Rust 文档。完整 `bash init.sh` EXIT=0（Flutter 414、Rust workspace、Clippy、build_core）；`cargo fmt --all -- --check` 与 `flutter analyze`（0 issues）通过。报告：`docs/diagnostics/2026-10-31-p04/p04.27-rust-bracket-pairs.md`。
- GitNexus `_SharedOpenDocState` impact 为 CRITICAL（247 节点/76 流程/20 模块）；图谱缺失边、UNKNOWN 与遍历截断保留，未降级。P04 / feat-026 继续进行中；自动成对删除、引号配对与括号内智能回车留后续 EDT-06 切片。Windows 11 历史 artifact 自动回放已记入 P15；项目级 Windows 主题/布局、Narrator 与退出门仍未通过，原生 DRM Linux 和 macOS 仍 pending。

### 最新进展（2026-10-31，P04.26 / EDT-06b 完成）

- 普通 Enter/NumpadEnter 现在继承 selection.start 之前的行首缩进，处理多光标与选区替换；光标位于缩进中时仅复制光标前的空白，无缩进行则只插入换行。由 Rust `lineBoundary` / 有界 `readRange` 与既有 UTF-16 TextOps 完成，composition 继续交给 IME，无 ABI 变更。
- 新增 9 个测试；与 P04.25 缩进回归合计 19 项通过，覆盖三平台 TargetPlatform、multi-cursor、双视图、undo/redo、BOM/emoji/CRLF 和保存回读。完整 `init.sh` EXIT=0（Flutter 402、Rust workspace、Clippy、build_core），cargo fmt 与 Flutter analyze（0 issues）通过。证据：`docs/diagnostics/2026-10-31-p04/p04.26-enter-indent.md`。
- GitNexus 新方法 impact 为 CRITICAL；`_focusNodeFor` UNKNOWN、`lineBoundary` CRITICAL lower-bound，索引有跨语言漏连与过程截断，均未降级。P04 / feat-026 继续进行中；括号/引号配对与更高级智能回车仍待 EDT-06 后续切片；P15 原生键盘、IME、读屏/DPI 与 macOS 验收仍 pending。

### 最新进展（2026-10-31，P04.25 / EDT-06a 完成）

- EDT-06a 完成 Tab 制表位插入、单行局部选区替换、整行/多行缩进、Shift+Tab 反缩进及 `editor.action.indentLines` / `editor.action.outdentLines` 平台快捷键。新增可见列 helper，按 Unicode grapheme 与固定 Code-OSS 全角/emoji 宽度规则计算；Rust 仍为文本权威，通过既有 UTF-16 行边界/范围读取与 TextOps 提交，无 ABI 变化。composition、版本校验、多光标重叠拒绝、双视图、undo/redo、dirty 与保存回读均覆盖。
- 三平台 TargetPlatform 定向 15 项通过，含用户给出的 Rust `linux-save-ok` fixture 回读；`flutter analyze` 0 issues、cargo fmt 通过。完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 393）。证据：`docs/diagnostics/2026-10-31-p04/p04.25-tab-indent.md`。
- GitNexus `_registerCommands` upstream LOW；`indentationVisibleColumn` impact CRITICAL（3 个符号/39 个流程/12 个模块），staged detect 多次 CRITICAL（16–25 个符号/69–151 个流程），all-scope 47 文件/27 符号/69–151 流程 CRITICAL。`_applyIndentation`、`defaultsFor`、`_focusNodeFor` 精确查询为 UNKNOWN，源码调用点已核对；不相关流程混入且索引丢弃 696/896 个入口候选、跳过 334 个 callee、9 条 walk 超预算，风险未降级，保留 `_focusNodeFor` 的 CRITICAL。P04 / feat-026 继续进行中；自动缩进和括号/引号配对留 EDT-06 后续切片，设置接入留 P07，P15 原生验收仍 pending。

### 最新进展（2026-10-31，P04.24 / EDT-05d 完成）

- EDT-05d 完成覆写模式粘贴：固定 Code-OSS 默认 `editor.overtypeOnPaste=true`；Rust Rope 批量解析最多 10,000 个绝对 UTF-16 覆盖范围，ABI v26 同步 Rust FFI 与 Dart，处理 BOM、emoji 代理对、CRLF、选区扩展和跨行边界。
- 显式 Ctrl/Cmd+V 在覆写模式下走 Rust 权威范围编辑；校验文档版本与 selection 快照，多光标按匹配行数分发、冲突重叠取消，undo/redo、dirty、双视图与保存回读接通。补齐 macOS Cmd+Z/Cmd+Y 到 Rust 文本历史。设置存储/UI 留 P07。
- Windows/Linux/macOS TargetPlatform 9 项覆写/多光标集成、Rust buffer 3 项、FFI 1 项、Dart↔Rust 1 项通过。完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 378）；`cargo fmt --all -- --check` 通过，Flutter analyze 0 issues。证据：`docs/diagnostics/2026-10-31-p04/p04.24-overtype-paste.md`。
- GitNexus `_focusNodeFor` upstream 为 HIGH（6 节点/3 流程），跨语言调用仍含 CRITICAL/HIGH/UNKNOWN；风险未降级。P04 / feat-026 仍进行中，P15 原生平台验收保持 pending；下一切片从 `docs/03` / `docs/11` 选取。

### 阶段进展（2026-10-31，P04.23 / EDT-05c 完成）

- EDT-05c 完成行首/行尾删除：Rust Rope 一次解析最多 10,000 个绝对 UTF-16 选区；选区左删扩展到本行起点，右删保留选区，光标在行首/行尾时分别删除到前一行内容尾/下一行起点。覆盖 BOM、emoji、CRLF、重叠多光标、EOF/BOF；ABI v25 已同步 Rust FFI 与 Dart。
- 工作台命令保护 IME composition，按同一 Rust 版本合并并倒序提交，撤销载荷上限 2,000,000 UTF-16 单元；双视图、dirty、undo/redo、保存回读通过。Windows/Linux 无默认键位，macOS 为 `Cmd+Backspace`、`Ctrl+K` 和 `Cmd+Delete`，命令面板可执行。用户提供的 `fn main() { println!("linux-save-ok"); }` fixture 经真实 FFI 检查 dirty 与文件回读。
- Rust buffer 2 项、FFI 1 项、keybindings 1 项、core_sync 1 项、工作台 1 项定向用例通过。完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 371）；`cargo fmt --all -- --check` 通过，Flutter analyze 为 0 issues；HEAD+index 隔离快照门禁也全绿。报告：`docs/diagnostics/2026-10-31-p04/p04.23-line-boundary-delete.md`。
- GitNexus 相关调用图仍含 CRITICAL/HIGH/UNKNOWN，索引有 683 个入口候选未排序、331 个 callee 被跳过、9 条遍历预算截断，未按低计数降级。P04 / feat-026 仍进行中；P15 原生平台验收继续 pending。下一切片依 `docs/03` 与 `docs/11` 选择并拆解尚未完成的 EDT 项。

### 阶段进展（2026-10-31，P04.19 / EDT-03d 完成）

- 跨输入窗矩形拖选接入 Rust ABI v23 批量绝对 UTF-16 行范围；主动行优先、emoji 安全吸附、CRLF 行尾排除、BOM 按文本保留，硬上限 10,000 行。边缘拖动复用 16ms / 3,600 px/s timer，靠近 2,048 UTF-16 窗口边缘重居中，继续编辑全部选中行并 Rust 保存回读。
- Rust buffer 2、FFI 1、Dart↔Rust 1、跨窗工作台 TargetPlatform 12 项通过（300×1,200 长文，Linux/Windows/macOS fixture）。工作树与精确 `HEAD + index` 隔离快照的完整 `bash init.sh` 均 EXIT=0（Flutter 351、Rust workspace、Clippy、build_core），两边 cargo fmt 和 Flutter analyze（0 issues）通过。报告：`docs/diagnostics/2026-10-31-p04/p04.19-cross-window-mouse-box-selection.md`。
- 重复 GitNexus 检查均为 CRITICAL 但计数波动：staged 14 files / 16–34 symbols / 101–180 processes；全树 50 files / 20–28 symbols / 109–180 processes。索引漏掉 659/859 process-entry candidates。CRITICAL/UNKNOWN 保持未降级，私有入口已源码交叉核查。P04 / feat-026 仍进行中，P15 原生平台验收未被 TargetPlatform 用例替代。

### P15 Windows 11 exact historical artifact 自动复验（2026-10-31）

- 指定的 run `41109679662` artifact `13003880930` 已重新下载并校验 ZIP/exe SHA-256；真实 Windows 11 build 26200 / AMD64 / 120 DPI（125%）下复验可见客户区、MSAA、原生 Microsoft Pinyin、双视图同步、保存回读。浅色系统 registry 值为 `1/1`，但产品仍呈暗色且编辑器仍挤在右侧窄窗。旧 binary `WM_CLOSE` 复现 `0xC000041D`。
- Narrator 探针只有两个 UIA 节点，无 LegacyIAccessible/预期语义，14 次 Tab 都落在 FLUTTERVIEW；未捕获语音。系统原始 dark theme 和 fixture SHA 已恢复。Windows 11 关闭/视觉/读屏门仍未通过；同机 100%/150% DPI 与语音证据仍 pending，详见 `docs/diagnostics/2026-10-31-p03/p03.7-exact-windows-artifact-41109679662.md`。

### 最新进展（2026-10-31，P04.18 / EDT-03c 完成）

- 实现 VS Code 鼠标矩形列选：Windows/Linux `Shift+Alt`、macOS `Shift+Option` 拖动按屏幕横坐标逐行命中；活动行作为主选区，并避免该组合误触发 `Alt+Click`。多行替换复用既有多光标和 Rust 保存路径。
- 多光标工作台定向测试 17 项通过；新用例覆盖 Linux/Windows/macOS TargetPlatform、emoji、CRLF、正反方向框选、逐行编辑和磁盘回读。完整 `bash init.sh` EXIT=0：Rust workspace、Clippy、build_core、Flutter 347 项全绿；`cargo fmt --all -- --check` 与 `flutter analyze --no-pub` 通过。
- 鼠标框选限定当前 64 Ki UTF-16 输入窗；跨窗矩形自动滚动仍待单独实现。GitNexus `RustTextInputFieldState`（80 symbols / 88 flows / 20 modules）与 `WorkbenchPage`（79 / 88 / 20）upstream 均为 CRITICAL；私有入口 UNKNOWN 经源码核对，风险未降级。证据：`docs/diagnostics/2026-10-31-p04/p04.18-mouse-box-selection.md`。

### 前一片进展（2026-10-31，P04.17 / EDT-03b 完成）

- 修复 `Ctrl+Alt+ArrowUp/Down` 在 Rust 有界输入窗里的绝对行列定位：目标行来自 Rust `lineBoundary` / `lineOffset`，目标附近读取不超过 64 Ki UTF-16 单元并在 grapheme 边界落点；跨窗重开后保留旧光标。
- 多光标工作台测试新增 3 项：30,000 单元两行分别向上/向下越过 16 Ki 窗口，插入后 Ctrl+S 磁盘回读正确；Emoji 代理对中间的目标列安全吸附。键位/多光标定向 25 项、Flutter analyze 0 issues、cargo fmt 通过。
- 完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` EXIT=0：Rust workspace、Clippy、build_core 和 Flutter 344 项全绿。精确 `HEAD + 暂存补丁` 隔离快照的完整 init.sh、cargo fmt 与 Flutter analyze 也全部通过。报告：`docs/diagnostics/2026-10-31-p04/p04.17-add-cursor-above-below.md`。
- GitNexus `_addCursorVertical` 为 UNKNOWN；外围 `WorkbenchPage` upstream 是 CRITICAL（66 symbols / 89 flows / 20 modules）。代码改动限于多光标命令；重复 staged detect 为 7 files / 7–8 symbols / 0 flows / LOW；全树 43 files 的检测从 0 / LOW（一次出现损坏路径）到 239–360 flows / CRITICAL 波动，保持高风险结论。

### 最新进展（2026-10-31，P04.16 / EDT-03a 完成）

- P04.16 修正“跳过匹配”行为为 VS Code 的 `editor.action.moveSelectionToNextFindMatch`：Ctrl/Command+K 后 Ctrl/Command+D 移动最后一个匹配选区，保留主选区；Ctrl/Command+D 仍添加下一个 occurrence。bounded Rust scanner 跳过已被其他选区覆盖的匹配，selection history 支持 Ctrl+U 撤销和 Ctrl+Shift+U 重做。
- `flutter test --no-pub test/keybindings_test.dart test/workbench_multi_selection_test.dart` 通过 22 项；`flutter analyze --no-pub` 0 issues，`cargo fmt --all -- --check` 通过；完整 `bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 341 项）。由 HEAD 和暂存补丁组成的隔离快照也完整 `bash init.sh` 通过，cargo fmt、Flutter analyze 均通过。报告：`docs/diagnostics/2026-10-31-p04/p04.16-move-last-occurrence-selection.md`。
- GitNexus `_selectNextOccurrence` 为 UNKNOWN（该工作树私有符号不在提交索引）；外围 `WorkbenchPage` upstream 为 CRITICAL（115 个符号、135 条流程、20 个模块）。代码路径经源码核对，风险和索引限制保留。P15 的原生键盘/IME/读屏/DPI 验收仍待验证。

### 前一片进展（2026-10-31，P04.15 / EDT-02f 完成）

- P04.15 实现跨窗鼠标拖选和边缘自动滚动：指针从有界输入窗拖至边缘后，选区端点以 Rust 绝对 UTF-16 坐标连续更新；窗口重居中后可继续跨页拖动。滚动计时器以 16 ms 节拍、最高 3,600 px/s 运行，并在松开、取消、失焦、dispose、返回视口或到达滚动边界时停止。绝对 selection 仍使用既有 range painter 与 Copy/Cut/Delete 路径。
- 新三平台 TargetPlatform fixture 9 项通过：正向/反向跨 16K 窗口、emoji、范围装饰、Copy/Cut/Delete 与保存回读；纯选区不改 Rust 文本/版本或磁盘。计时器松开/取消/失焦/销毁清理均有断言。跨窗行选择 18 项、鼠标选择 3 项、Rust 输入控件 7 项、输入窗 10 项通过。
- 完整 `bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 339 项）；`cargo fmt --all -- --check` 通过，`flutter analyze --no-pub` 0 issues。报告：`docs/diagnostics/2026-10-31-p04/p04.15-cross-window-mouse-drag.md`。GitNexus 对 `RustTextInputFieldState` / `RustTextInputField` / `OpenDoc` 报 CRITICAL，私有方法结果 UNKNOWN 且有路径损坏；源码引用已核对，限制记录在报告中。

### Windows 11 exact artifact automation (2026-10-31)

- Pushed commit `1359981` adds an isolated light/dark registry matrix and Narrator/UIA focus probe for the exact Release artifact from run `41109679662`.
- Windows 11 ARM64 runner (x64 emulation) run `41187736069`: both themes completed edit, dual-view save/read-back and Narrator probe. Both confirm the old artifact still exits `0xC000041D`; no-UIA close controls match. Narrator UIA exposes only the app root and `FLUTTERVIEW`; 14 Tab probes return the same window node and expected semantic names are missing. The separate source-SHA integration job passed 14 tests including simulated Flutter IME.
- Evidence: `docs/diagnostics/2026-10-31-p03/p03.7-windows11-theme-narrator-41187736069.md`. P15 remains pending for 125/150% DPI, native x64/native IME, actual Narrator speech, and visual review of the blank left split. This exact old binary's failure is not a result for later builds.
- P04 / feat-026 仍进行中；下一片按 docs/03 与 docs/11 选取尚未完成的 EDT 原子项。targetPlatform 合成鼠标不替代 P15 原生鼠标/辅助功能验收；Windows 11 视觉/读屏、原生 DRM Linux 与 macOS 原生验收仍待签收。

### 阶段进展（2026-10-31，P04.14 / EDT-02e 完成）

- P04.14 已完成跨窗选区普通输入、粘贴和 IME 替换：emoji 普通输入与粘贴、Backspace/Delete、中文预编辑更新/取消/提交都应用到 Rust 完整绝对范围；撤销/重做、dirty 和保存回读正确。Workbench 有界输入窗硬上限 16,384 UTF-16 单元，初始化读取预留 256 单元供 composition 使用。
- Windows/Linux/macOS Flutter TargetPlatform 定向跨窗测试 18 项、Rust 输入窗 10 项、输入控件 7 项通过。完整 `bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 330 项），cargo fmt 与 `flutter analyze --no-pub`（0 issues）通过。报告：`docs/diagnostics/2026-10-31-p04/p04.14-cross-window-ime-replacement.md`。
- P04.13 保持超长行跨 16K 输入窗的绝对 selection：三击整行、分块 Copy、Cut/Delete/Paste 通过 undo/dirty/save；40,000 UTF-16 单元测试证明窗外 selection 两端仍完整。报告：`docs/diagnostics/2026-10-31-p04/p04.13-cross-window-line-selection.md`。
- Flutter TargetPlatform 是合成事件，不替代 P15 原生键鼠、IME、读屏、DPI/主题验收。Windows 11 当前 artifact 的布局/读屏门仍待处理，既有记录见 `docs/diagnostics/2026-10-31-p03/p03.7-windows-11-artifact-41109679662/README.md`。下一片为 P04.15 鼠标拖选与边缘自动滚动。

### 阶段进展（2026-10-31，P04.12 / EDT-02c 完成）

- P04.12 对齐 Code-OSS 三击 LineSelect：Linux 用 Rust `lineBoundary` 补齐默认选择漏掉的行尾 LF；Windows/Linux/macOS targetPlatform 下 LF、CRLF 来源（Rust 文本当前归一化为 LF）、无终止符末行各通过，fixture 含 emoji。Flutter/Rust 全文与版本及磁盘字节不变。
- 定向 Flutter 9 项通过；完整 `bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 313 项），`cargo fmt --all -- --check` 通过，`flutter analyze --no-pub` 0 issues。报告：`docs/diagnostics/2026-10-31-p04/p04.12-mouse-triple-click.md`。
- P04.12 的整行跨窗缺口由 P04.13 处理。Windows 11 artifact 自动化结果及仍待处理的布局/读屏门见 `docs/diagnostics/2026-10-31-p03/p03.7-windows-11-artifact-41109679662/README.md`。

### 阶段进展（2026-10-31，P04.10 / EDT-02a 完成）

- P04.10 覆盖 Windows/Linux/macOS targetPlatform 下的普通鼠标点击、从同一 caret 起点的正向与反向 Shift+Click；使用 RenderEditable hit-test 坐标，fixture 含 emoji，并对照 Flutter 文本、Rust 权威全文、输入窗版本和磁盘内容均未改变。
- 定向 Flutter 3 项通过；完整 `bash init.sh` EXIT=0（Rust workspace、Clippy、build_core、Flutter 300 项），`cargo fmt --all -- --check` 通过，`flutter analyze --no-pub` 0 issues。报告：`docs/diagnostics/2026-10-31-p04/p04.10-mouse-click-anchor.md`。这些是 Flutter 自动化，不代表原生平台鼠标或辅助功能验收。
- P04 / feat-026 仍是唯一活动 feature；P04.10–P04.14 的鼠标单击、双击、三击、跨窗全行选择及输入替换已登记；下一步 P04.15 / EDT-02f 覆盖跨窗拖选和边缘自动滚动。

### 阶段进展（2026-10-31，P04.9 / EDT-01f 完成）

- P04.9 完成 PageUp/PageDown 与 Shift 选择：调用 Flutter 可视页 selection Action，macOS plain PageUp/PageDown 从默认纯滚动修正为 caret 分页。三平台 targetPlatform fixture 覆盖 viewport 移动与 anchor；4,000 行文件跨 16K 输入窗重居中，Rust 全文/版本不变。
- 定向 Flutter 4 项通过；完整 `bash init.sh` EXIT=0（Flutter 297 项、Rust workspace、Clippy、build_core），`cargo fmt --all -- --check` 与 `flutter analyze`（0 issues）通过。报告：`docs/diagnostics/2026-10-31-p04/p04.9-page-movement.md`。
- P04 / feat-026 仍是唯一活动 feature；EDT-01 移动项已完成，下一步按 docs/03 与总计划核对并登记 P04 剩余命令/查找/片段/diff/merge 切片。targetPlatform 不等同真实平台键盘/IME/读屏/DPI 证据，这些仍属 P15。

### 阶段进展（2026-10-31，P04.8 / EDT-01e 完成）

- P04.8 增加文件开头/末尾移动与 Shift 选择；Windows/Linux Ctrl+Home/End，macOS Command+Up/Down。命令读取 Rust 文档 UTF-16 总长度并通过受控 selection 路径跨 16K 输入窗重居中，不改文本或版本。
- 键位/工作台定向 Flutter 6 项通过，覆盖三平台键位、双向锚点与 4,000 行文档首尾跳转；完整 `bash init.sh` EXIT=0（Flutter 293 项、Rust workspace、Clippy、build_core）。`cargo fmt --all -- --check` 通过，`flutter analyze` 0 issues。报告：`docs/diagnostics/2026-10-31-p04/p04.8-file-boundary-movement.md`。

### 阶段进展（2026-10-31，P04.7 / EDT-01d 完成）

- P04.7 将 Home/End 行边界查询放在 Rust Rope 内，ABI v22 返回 UTF-16 行首、缩进后的首个非空白位置和排除 CRLF 的行尾。工作台实现 smart Home 来回、End 及 Shift 锚点；macOS 支持 Command+左右键与 Ctrl+A/E，Windows/Linux 使用 Home/End。
- Rust buffer 2 项、FFI 1 项和 Flutter 定向 25 项通过；覆盖 emoji/代理对边界、CRLF/空行、100K 空白缩进、20K 缩进行跨 16K 输入窗、三平台 targetPlatform、文本/版本不变。`bash init.sh` EXIT=0（Flutter 287 项、Rust workspace、Clippy、build_core）；`cargo fmt --all -- --check` 通过，`flutter analyze` 0 issues。报告：`docs/diagnostics/2026-10-31-p04/p04.7-home-end-smart-home.md`。
- P04 / feat-026 仍是唯一活动 feature。targetPlatform 不是原生键盘、IME、读屏或 DPI/主题证据；这些仍属 P15。

### 阶段进展（2026-10-31，P04.6 / EDT-01c 完成）

- 固定 Code-OSS `1.145.0-dev` commit `4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e` 的 word-part 行为已接入：macOS Ctrl+Option+左右方向键与 Shift 选择；Windows/Linux 不注册该默认 chord。Rust Rope 按绝对 UTF-16 偏移计算 camelCase、缩写、下划线/连字符和普通分隔符边界，跨输入窗时重居中，Rust 文本和版本保持不变。
- 新增 ABI v21 `alula_doc_word_part_offset`；Rust 子词单测 4 项、editor-core FFI 对拍 1 项、键位与工作台 Flutter 定向测试 16 项通过。`bash init.sh` EXIT=0（Flutter 280 项、Rust workspace、Clippy、build_core）；`cargo fmt --all -- --check` 通过，`flutter analyze --no-pub` 0 issues。报告：`docs/diagnostics/2026-10-31-p04/p04.6-word-part-movement.md`。
- P04 / feat-026 仍是唯一活动 feature。Flutter targetPlatform 测试不等同真实 macOS 键盘、IME 或辅助功能验收；这些仍属 P15。历史 Windows Release artifact 的 close crash 和其他 EV-P03 pending 门保持原记录。

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

1. 从 `docs/03` 与 `docs/11` 选择下一个未完成 EDT 子项；先更新权威里程碑拆解并做 GitNexus impact，再实现一项。
2. 保持 P04 / feat-026 为唯一活动 feature；每片按 docs/03 验收、留证据并分阶段提交。
3. EV-P03 Linux DRM、Windows 11 UIA/读屏/DPI/主题与 macOS 原生行为继续留在 P15 验收门；P00–P13 完成前不做 500 MiB 数值优化，全部计划完成后继续补齐 CI Release 与 v0.1.0 测试 PR。


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

## P03.7 Windows 11 current Release artifact validation（2026-10-31）

- 在 x64 Windows 11 Pro for Workstations build 26200 上验证了 Actions run `41177214462`、commit `d3a7a56e8ebe48ae47c384618f3955b0516e3f57` 的当前 Release artifact。125% DPI、dark theme、2048×1152 桌面下客户区内容可见；Microsoft Pinyin composition/候选提交/取消、双视图同步编辑、样例保存与磁盘回读、编辑器 MSAA 节点检查、正常关闭均通过。双视图交互后的捕获图中编辑器位于偏右窄视图，左侧有大面积空白；Windows 视觉布局验收仍 pending。
- 复测用户指定的 run `41109679662` 精确历史 artifact：同一保存/IME/双视图交互通过，但关闭以 `0xC000041D` 结束；无 UIA/MSAA 查询的对照启动也复现。该结论只属于旧二进制；当前 `d3a7a56` artifact 关闭 exit 0。
- Narrator UIA 树未暴露预期控件，14 次 Tab 探针均未形成可验证焦点遍历，且未采集播报音频，因此读屏验收仍 pending。当前只覆盖 125%/dark，不代表 DPI/主题矩阵。复用脚本对当前构建输出的 `artifactArchitecture` 字段错误声称 ARM64 仿真；同机 WMI/CPU 确认为 x64（AMD Ryzen 7 9700X）。报告及筛选后的截图、metadata、日志、脚本：`docs/diagnostics/2026-10-31-p03/p03.7-windows-11-artifact-41109679662/README.md`。
- 测试 fixture `tests/fixtures/rust-mini/src/main.rs` 已恢复，SHA-256 与测试前相同；验证进程已退出。项目级平台验收继续 pending：原生 DRM Linux、Windows Narrator/焦点与多 DPI/主题、macOS 原生行为未通过。本机无法提供 macOS 环境；依用户要求先满足 Linux/Windows 可用性，再提供 macOS 测试包。

## P04.34 / EDT-07a：在上方/下方插入行（2026-11-01）

- 对齐固定 Code-OSS 1.145.0-dev 的 `editor.action.insertLineBefore` / `editor.action.insertLineAfter` 和 Ctrl/Cmd+Enter 键位；行位置、行首/行尾及 UTF-16 文本修改继续由 Rust 权威文档提供，工作台经 TextOps 单批提交。
- 三平台 Flutter targetPlatform 测试验证首行 insert-before 光标行为、上下插入、Rust 双视图同步、undo/redo，以及 `fn main() { println!("linux-save-ok"); }` 保存回读。定向 18 项通过；完整 `RUST_TEST_THREADS=1 FLUTTER_BIN=/home/vegetable/develop/flutter/bin/flutter bash init.sh` 在工作树与精确 `HEAD 1388175 + staged patch` 隔离快照均 EXIT=0（Rust workspace、Clippy、build_core、Flutter 460）；`cargo fmt --all -- --check`、Flutter analyze（0 issues）通过。
- GitNexus 编辑前风险：`WorkbenchPage` CRITICAL（295 affected symbols / 72 processes / 20 modules），`_insertNewlineWithIndent` CRITICAL（71 / 56 / 15），`KeybindingSet` LOW。Staged detect 为 9 files / 4 symbols / 140 processes / CRITICAL；all-scope 为 45 / 16 / 140 / CRITICAL，包含其它未暂存修改。更改未修改既有 Enter 实现；EDT-07 的移动/复制/删除/合并/排序/去重仍未完成。
- 证据：`docs/diagnostics/2026-11-01-p04/p04.34-insert-line-above-below.md`。targetPlatform 自动化不替代 P15 原生平台验收。

## P04.35 / EDT-07b：删除行（2026-11-01）

- 新增 Code-OSS `editor.action.deleteLines`，默认 Windows/Linux Ctrl+Shift+K、macOS Cmd+Shift+K。Rust 行位置/UTF-16 边界计算出多选删除范围，按预算执行单次 TextOps，保留 undo/redo、dirty、保存与分屏同步。
- 三平台定向 19 项全过，覆盖首行、emoji、相邻多光标、文件末尾空行、BOM/CRLF 保存回读。完整工作树 `bash init.sh` 通过：Rust workspace、Clippy、build_core、Flutter 464；`cargo fmt --all -- --check` 通过，`flutter analyze --no-pub` 为 0 issues。精确暂存 patch 已应用到 detached `HEAD a69cb36` 隔离 worktree，完整 `bash init.sh` 通过（Flutter 464，含 Rust workspace、Clippy、build_core）。
- GitNexus 编辑前 `_registerCommands`、`KeybindingSet` impact 为 LOW；partial FTS、UNKNOWN 与 broader graph risk 保持未降级。详见 `docs/diagnostics/2026-11-01-p04/p04.35-delete-lines.md`。EDT-07 其他行操作与 P15 原生设备验收仍开放。

## P04.45 / EDT-08e：Pascal Case 文本转换（2026-11-01）

- 注册固定 Code-OSS `editor.action.transformToPascalcase`（无默认快捷键），接入已有版本校验的 Rust UTF-16 selection/caret 规划、多光标事务、selection 映射、undo/redo、dirty、Find、双视图与保存路径。Rust 保留点号并在点后分段，仅拆 `_`、ASCII 空格、tab、连字符；处理全大写词尾、Unicode 和 supplementary UTF-16 starter。NUL-safe JSON FFI ABI v31，输入/输出限 8/16 MiB。
- 三平台 TargetPlatform fixture 验证 `linux-save-ok→LinuxSaveOk`、caret `HTTP→Http`、`foo.bar-baz→Foo.BarBaz`、分屏同步、BOM+CRLF 保存回读、undo/redo；Rust buffer/FFI 和 Dart bridge 覆盖 Unicode、emoji、CRLF、Unicode 行分隔符与 NUL。完整 `bash init.sh` 通过（Rust workspace、Clippy、build_core、Flutter 514），cargo fmt 和 Flutter analyze 通过。报告：`docs/diagnostics/2026-11-01-p04/p04.45-pascal-case.md`。
- GitNexus 编辑前 `WorkbenchPage`/`TextBuffer` 保持 CRITICAL，`AlulaCore` HIGH；全局图索引截断未降级。staged/all/compare-main 最终扫描结果登记在报告。P15 原生平台验收继续 pending。
