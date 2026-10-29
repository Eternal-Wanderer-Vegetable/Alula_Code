# 10 · VS Code 无插件全功能 1:1 复刻总计划

> 制定日期：2026-10-27。交付物是实施计划，尚未实施完整复刻。
> 技术栈固定：Flutter 桌面界面 + Rust 核心；保留低内存与压力下可编辑、可保存的不变量。
> **任务状态、依赖、阶段 DoD 以 [docs/03](03-里程碑计划与验收标准.md) 的新主线为唯一权威。**
> 本文定义范围、架构、方法与实施包；[docs/11](11-VSCode功能对照矩阵.md) 是逐项需求与验收索引。

## 1. 交付目标与版本合同

目标是复刻 VS Code 在**不额外安装用户扩展**时提供的桌面功能、界面布局、视觉层级、默认操作、快捷键、设置语义和文件结果，排除需要外接 AI 的功能。不能用“类似工作台”“核心流程可用”或“主要功能覆盖”替代 1:1 验收。

原 docs/09 只要求工作台结构等价，并排除像素级界面、Notebook、完整调试等；这部分范围声明自本计划起失效。已有代码可作为起点，不能据旧任务的 done 推定新目标完成。原 Phase 2 的通用 VSIX API 兼容不再是本主线的前置目标。

### 1.1 固定上游

| 参考 | 固定版本 | 用途 |
|---|---|---|
| [microsoft/vscode](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e) | `4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e`；package.json 为 **1.145.0 开发版** | 实际实现、命令、菜单、键位、设置、样式、随附扩展 |
| [microsoft/vscode-docs](https://github.com/microsoft/vscode-docs/tree/da213552439825628e0ab958dbde1e413dbc36bf) | `da213552439825628e0ab958dbde1e413dbc36bf` | 用户可见行为、前提条件、边界与操作路径 |
| 本地起点 | 当前工作树；审计时 HEAD `a29d707`，有既存未提交修改 | 可复用基础、真实缺口；不能只审 HEAD |

此次选择开发快照是为了准确参照用户指定仓库当前内容，**不是把 main 称为 Stable**。P00 构建该快照作为桌面对照版本，记录实际打包清单、feature flags、平台差异、locale、字体、主题和窗口尺寸；若构建不可复现，登记阻塞，不暗换版本。后续迁到 Stable tag 必须有一次独立版本差异清单和新的验收基线，不能在实施中持续跟随 main。

参考分两层：核心与随附功能用该SHA的Code-OSS；微软发行配置专有的默认服务用注明版本/commit的官方二进制及product差异作额外参考。若该SHA没有官方发行物，服务项标记reference unavailable，在P00确认可测试路径，不能假设源码构建天然拥有相同端点/客户端身份。视觉参考配置只移除已逐项认定的AI贡献，记录被移除控件与重排，不拿默认AI侧栏空位误判非AI布局。

当前快照已包括集成浏览器、Markdown 富文本编辑、Markdown diff、内置 Mermaid 等；不能仅按旧版 VS Code 的记忆列功能。文档有比源码更新或描述其他发行渠道的情况，冲突以固定源码、构建配置和实测为准，并登记差异。

### 1.2 “不需要插件”的准确口径

| 分类 | 本次处理 | 示例 |
|---|---|---|
| A 核心桌面功能 | 全部纳入 | 编辑器、布局、搜索、配置、diff、任务、调试容器 |
| B 默认随附的内置扩展 | 全部纳入其非 AI 能力；可改写为内建 provider | Git、JS/TS、HTML/CSS/JSON、Markdown、Emmet、主题、ipynb |
| C 依赖系统工具/本机运行时 | 纳入；安装前提与 VS Code 一致并明确提示 | Git CLI、shell、Node 被调试程序、PHP lint、npm/构建工具 |
| D 默认具备但依赖非 AI 外部服务 | **纳入条件验收，不能因联网就删掉** | Settings Sync、GitHub/Microsoft 账号、公开端口转发、发布到 GitHub |
| E 需用户额外安装扩展的业务能力 | 排除对应业务 provider，保留随附的通用界面/服务 | Python/C++/Rust 完整语言服务与调试器、Jupyter kernel、PR/Issues、Remote SSH/WSL/Containers |
| F 依赖外接 AI | 排除，逐上游项登记原因 | Copilot、Chat/Inline Chat、Agent、AI 编辑/补全/提交信息/语义搜索、MCP 驱动代理 |
| G 测试/开发工具、实现细节或未进入产品的实验代码 | 按构建可达性判定；不能把源码目录直接当产品功能 | vscode-api-tests、test-resolver、内部 telemetry helper |

具体规则：

- **内置扩展也算无需用户安装插件的功能。** `extensions/` 不是统一排除区。`product.json` 还声明下载式预置扩展，js-debug 及其配套需另锁版本与源码，不能只扫描仓库目录。
- Testing、Comments、Notebook、自定义编辑器、Inline Suggestions 等有通用宿主不等于默认带齐所有 provider。保留核心容器和默认存在的能力；不能拿 mock provider 冒充默认 Python 测试/Jupyter 执行可用。
- 基础语言语法包与完整语言服务分别验收。默认 Python/Rust/C++ 等语法配置在范围；现有 rust-analyzer 能力保留为项目附加能力，不能替代 JS/TS、HTML/CSS/JSON 等上游默认语言服务。
- 现有 Python/C++/Rust LSP 目标不删除，但转为后续可选增量，不阻塞本次默认能力复刻，不默认新增多语言索引进程。
- 非外接 AI 的本地语言自动识别、普通单词补全、语义 token、传统 Emmet/IntelliSense 在范围；不能只因带模型/embedding 字样一刀切，须看实际依赖。
- 远程服务、扩展市场和官方账号的**前端与本地逻辑**纳入；官方后端互通、客户端注册、端点许可和可再分发物须在 P00/P13 分别验证。若只能提供自建兼容服务，记录为“有替代实现，官方互通未完成”，**不能标 1:1 完成**。
- Extensions 管理自身是内置功能：列表、搜索、内置扩展开关、安装包管理、错误状态纳入。运行任意第三方扩展及完整 `vscode` API 兼容属于 E；包下载成功不能声称第三方业务可用。此边界在管理 UI 中必须明确，不能静默假激活。

### 1.3 1:1 的可检验定义

1. **视觉**：同 OS/字体/缩放/窗口/主题下，布局、间距、颜色 token、图标、字重、层级、菜单、悬浮、禁用态与动画状态逐项对照。使用自定义 Flutter 组件；不能直接以 Material 默认控件代替。
2. **交互**：鼠标、触控板、键盘、IME、拖放、焦点、菜单条件、操作历史、错误提示一致；同文档多视图共享内容，各自保留选区和滚动。
3. **语义**：同操作序列得到相同文本、选区、撤销边界、dirty 状态、文件结果、配置优先级和进程生命周期。
4. **完整性**：每个范围内的上游贡献项有映射和验收证据。占位界面、简单字符串补全、单文件同名跳转、静默结果截断均不算完成。
5. **差异**：系统原生窗口装饰、字体抗锯齿等必须逐项解释并限制掩膜区域；不能全图放宽阈值。产品名称、标识与自有服务端点明确列入差异表，不冒充微软发行版。

“全部”以固定版本为边界。P00 将本次功能族矩阵展开为源码/运行时注册项；在未消化项不为零之前，只能报告覆盖率，不能发布“100% 复刻”结论。

## 2. 现有项目审计与保留策略

### 2.1 可复用的基础

保留 Flutter/Rust 工程、Ropey、UTF-16 校验、ABI v4 握手、真实 FFI 和 diff 对拍、保存 crate、布局分割树、标签/组/面包屑模型、命令与快速输入原型、Git/search/watcher 通路、Rust 大纲及 mem-probe/bench/CI。复用意味着减少重写，不意味着省略新对照验收。

### 2.2 先解决的结构与可靠性缺口

以下为源码审计事实或待复现风险；不能把静态风险写成已经运行复现的事故。

| 现状/风险 | 影响 | 进入的实施包 |
|---|---|---|
| 编辑器仍是普通 `TextField`；code_forge 只有候选评测 | 多光标、列选、虚拟化、折叠、装饰、IME/无障碍都无等价证据 | P03 |
| 编辑时全文 diff、LSP 全文发送；Tree-sitter `parse(text, None)` | 大文件每键扫描/复制，无法承载低内存全功能目标 | P01/P02/P08 |
| 全工作台一个全文快照 UndoStack，未带文档身份 | 疑似跨文件撤销串写；需先复现再修复 | P02 |
| LSP 补全同步 FFI 可等到 10 秒；目录遍历/外部重读同步 | UI 卡住；版本过期回包无完备合同 | P01 |
| 每 800ms 遍历文档轮询诊断与语法 | 常驻空转、隐藏文档全量解析 | P01/P08 |
| journal 只记录 ≤200 万字符内容，先删旧文件再 rename | 大未保存文件未获备份；掉电窗口与 dirty 恢复不完整 | P02 |
| `lsp_stop` 仅 detach，全局工作区服务器表未显式回收 | 关闭工作区后进程可能仍驻留 | P01/P02 |
| watcher 是 Dart `Directory.watch`，事件后重读全部打开文档 | 风暴、递归覆盖、删除/重命名/overflow、冲突处理不足 | P06 |
| 键位为 SingleActivator，缺 `when`/真实 chord/完整平台映射；有硬编码拦截 | 用户重绑定和菜单状态不一致 | P01/P07 |
| 快速打开上限 2000、搜索上限 500 | 有界策略可以保留；必须支持分页/继续、明确截断，保持全工程可达 | P06 |
| 语法只支持 Rust；补全只保留插入字符串 | TextMate scopes、snippet、range、resolve、语义 provider 缺失 | P08 |
| 本地同名符号查找被称跳转定义 | 不能视为语义/跨文件定义实现 | P08 |
| 一个大 WorkbenchPage 混合 UI、IO、子进程和会话 | 子系统难以独立取消、关闭与验收 | P01 后按功能渐迁移 |

原 G1 的路线选择保留，但 docs/06 未完成的真机 IME/万行流畅度必须重新作为 P03 硬门。原空工作台约 179–190 MiB 的观测只作为原型自身基线，不证明全功能与 VS Code 同场景降低 50%。

本轮启动复验遇到 `RenderObject` 被传入接收 `BuildContext` 的递归方法，已按启动规则仅纠正辅助函数调用；其余既存工作树改动不归入本计划实施成果。

## 3. 目标架构：延续 Flutter + Rust

```text
Flutter desktop
  platform           窗口/菜单/IME/剪贴板/拖放/无障碍/系统对话框
  workbench          布局/组/视图容器/命令/ContextKey/菜单/键位/通知
  editor_ui          视口渲染/输入/选区/装饰/滚动；Document 与 View 分离
  features/*         explorer/search/scm/terminal/debug/settings/notebook/preview
                  │ versioned async command/event protocol
Rust editor-core   │ request/workspace/document/view/version/session IDs
  editor-buffer      Rope/事务/位置索引/撤销/保存点/多文档编辑
  editor-doc         编码/EOL/BOM/保存/journal/本地历史/冲突
  editor-workspace   URI/多根/FS provider/watcher/excludes
  editor-lang/lsp    grammar/语义 provider/协议能力协商
  editor-search/scm  rg 与 Git 适配、流式结果/缓存
  editor-process     监督树/取消/限额/退出/资源压力
  editor-terminal    PTY/终端状态；显示由 Flutter 提供
  editor-tasks/dap    任务图/problem matcher/DAP/会话
                  │ on-demand, supervised, budgeted
  tsserver、HTML/CSS/JSON services、js-debug、shell、Git、rg、web renderer
```

新增 crate/目录是目标边界，按相应实施包建立，不能一次空建所有模块。Rust 编辑核心不依赖 GUI；平台 GUI/WebView 的宿主适配在 Flutter/平台层，通过受限协议交换数据。

### 3.1 文本、视图与一致性

- P02/P03 验证“Rust 统一 DocumentModel + Flutter 可视区/短输入缓存”为首选。与组件自带 rope 镜像方案比较 IME、增量 delta、多光标、撤销、可访问性和总内存后写 ADR，不能在计划中把未实验方案称为事实。
- 同一workbench的组与辅助浮窗按DocumentId/URI共享事务与保存点，每个view独立selection/scroll/fold/focus；独立顶层窗口按session+workspace+URI隔离dirty缓冲，以外部变更/保存冲突协调，不能全应用只按URI强制合并。跨文件WorkspaceEdit具有事务身份、失败回滚与独立文件历史协调。
- FFI 全部偏移/长度维持 UTF-16 code unit；Rust 映射到字节/行列。LSP positionEncoding 与 server 能力协商，跨边界转换测试含 Emoji/ZWJ/组合字符/CRLF/BOM。
- ABI 逐版双侧升级、版本握手、错误对象、资源释放规则、兼容窗口与真实 FFI 对拍一起提交。是否继续手写 C ABI 或引入生成绑定由 P01 ADR 决定，不以“改架构”为名单边换协议。

### 3.2 异步、状态与进程

- UI 主 isolate/线程不等待磁盘、Git、rg、语言服务、PTY 或全文分析。所有慢请求有 id、取消、deadline、版本戳、并发上限、背压；关闭工作区能撤销并清空其任务。
- 用事件推送代替 800ms 全文轮询；只计算受影响范围、可见文档与必要后台任务。过期请求不能覆盖新内容或新工作区。
- `ContextKey` + Command + Menu + Keybinding 共用一套条件/启用状态；when 表达式、优先级、移除规则、chord 超时、平台键位与输入法处理有独立协议测试。
- 先保留 ChangeNotifier 等现有机制，按 service/view-model 切分；不因旧 docs/09 写过 Riverpod 就强制全局重写。
- 所有工具进程进入统一 supervisor：进程归属、启动预算、stdin/stdout 流控、退出等待、崩溃隔离、重启退避、父窗口退出回收。不能用 detach 替代 stop。

### 3.3 内置能力的复用策略

| 子系统 | 拟用方式 | 必须证明 |
|---|---|---|
| TextMate/语言配置/snippets/主题数据 | 读取固定上游数据，Rust 兼容 tokenizer/scopes；Tree-sitter 用于结构与增量分析 | 各语言嵌套、注入规则、主题 token 与官方快照对拍；单用 tree-sitter 不等于 TextMate 1:1 |
| JS/TS | 按需运行固定 TypeScript/tsserver，适配其原生协议；不把它误当 LSP | 补全、导航、refactor、自动导入、项目配置、版本切换等默认能力 |
| HTML/CSS/JSON/Markdown | 优先复用上游官方语言服务/库，受监督 sidecar 或兼容适配 | 真实 provider 结果与设置/工作区配置等价 |
| Git/rg | Rust 服务调用系统 Git、固定随附 rg，明确能力/版本探测 | 路径、转义、ignore、取消、性能、错误与用户前提一致 |
| JavaScript 调试 | 锁定 `product.json` 的 js-debug/companion/profile-table，对 DAP 与 companion 行为做适配 | 不能只支持任意 DAP 就声称默认 JS 调试相同 |
| 终端 | Windows ConPTY / Unix PTY；评估 Dart 终端组件与 Rust VT 状态机 | 终端转义、宽字符、shell integration、可访问性与回收；不能用日志框冒充终端 |
| Markdown 富文本、公式/Mermaid、Notebook renderer、集成浏览器 | 按需隔离 WebView/系统 web engine；原生方案作为实测对照 | 离屏/关闭释放、无空载 web 进程、隔离/CSP、实际功能和进程树预算 |
| 账号/同步/端口转发 | 前端原生 + Rust 网络/secret 服务 + 有文档的可用后端 | 官方互通/授权前提单列；自建实现不能消除官方差异 |

“现有技术栈”不意味着禁止复用数据、CLI 或专用服务，也不允许把整个 Electron 工作台/Monaco 内嵌后宣称 Flutter/Rust 复刻。Node/WebView 只在相应默认功能需要时按需启动；资源实测若不合格，记录架构门失败并迭代，不能删除该功能假装达标。

## 4. 全功能实施包

下表给出边界与工程量，**不是当前状态表**；状态与正式 DoD 在 docs/03。每包进一步拆成可单独审查的 feature，当前只推进一项。允许多个代理为同一项做源码调研、实现、测试或评审，不并行开挖其他 feature。

| 包 | 具体产出 | 关键前置 | 工程量：人周 |
|---|---|---|---|
| P00 版本与对照资产 | 可复现 Code-OSS、默认发行清单、注册项清单、截图/行为基线、例外账本、现状故障 fixture、三项早期风险实验 | 无 | 3–5 |
| P01 平台服务与协议 | async command/event、ContextKey/commands、workspace lifecycle、supervisor、预算服务、服务边界 ADR | P00 | 6–10 |
| P02 文档与数据安全 | Document/View 身份、事务撤销、编码保存、未命名、dirty/savepoint、可靠恢复/历史/外部冲突 | P01 | 12–20 |
| P03 编辑器输入与绘制 | 选定/扩展/自研控件、虚拟化、多光标/列选、IME、字体/RTL、minimap/折叠/装饰/无障碍基本面 | P02 | 24–40 |
| P04 编辑命令与比较 | 全部基础/高级编辑命令、查找替换、片段、导航、diff/merge/批量编辑 | P03 | 18–30 |
| P05 工作台 1:1 | 标题/菜单/活动栏/双侧栏/面板/状态栏、组/标签/浮窗/布局模式、浮层/焦点/拖放 | P01/P03 | 18–30 |
| P06 文件/工作区/搜索 | Explorer CRUD、多根/.code-workspace、watcher、ignore、全局搜索与替换/Search Editor、Timeline | P02/P05 | 16–26 |
| P07 配置/外观/个人环境 | settings JSON/UI/层级、keyboard UI/when/chords、主题/图标/snippets、Profiles/迁移 | P01/P05 | 18–28 |
| P08 全部内置语言能力 | TextMate/配置包全覆盖、JS/TS/HTML/CSS/JSON/Markdown/PHP/Emmet、语义 provider、Problems | P04/P06/P07 | 26–44 |
| P09 Git 与 SCM | 多仓/暂存/commit/branch/remotes/stash/worktree/history/blame/graph/conflicts/Multi Diff | P04/P06 | 16–28 |
| P10 终端 | PTY/VT、会话/分组/标签/终端编辑器、profiles、shell integration、suggest、任务联动 | P01/P05/P07 | 20–34 |
| P11 任务与默认调试 | tasks.json/变量/problem matchers/npm/gulp/grunt/jake/tsconfig、DAP/launch、JS/Node/外部Chrome-Edge debugger、Testing/Comments容器 | P08/P10 | 24–40 |
| P12 文档格式与浏览 | Markdown source/rich/diff/math/Mermaid、media/custom editor、Notebook/ipynb/renderer、集成浏览器及其调试联调 | P04/P05/P07/P08/P11 | 28–48 |
| P13 账户/联网/内置管理 | 账户/secrets、Settings Sync/冲突、GitHub基础集成、公开端口/隧道、扩展管理、更新/联网配置 | P06/P07/P10 | 20–40 |
| P14 跨平台与质量闭环 | 三平台窗口/CLI/无障碍完整审计、日志/进程资源面板、安全/信任/故障注入、全功能内存优化 | P08–P13 | 18–30 |
| P15 全量对照与发布 | 消化所有未映射注册项、逐项签收、GUI/压力/性能回归、安装更新卸载、版本差异报告 | P14 | 8–14 |

粗估合计 **275–467 人周**（重新估算以 P00/P03/P12/P13 实测为准），按4.345周/月约63–108人月；这是多平台1:1目标的数量级，不是报价或交付承诺。建议4名核心研发+专职测试/设计协作，考虑串行依赖约24–40个月；单人名义全职约5–9年，考虑非有效工时约6–11年。未知处额外保留30–50%变动空间，不沿用旧“几个月完成轻量V1”的估算。

P03/P12/P13是最大不确定性。P00内顺序执行三个限时实验：编辑器IME+增量输入+多光标/视口最小原型；三平台Web引擎DevTools/CDP/MHTML与按需进程内存原型；官方服务参考/端点与客户端注册前提探测。每项产出ADR、可运行最小证据、预计差距/阻塞，失败须重估路线；它们不依赖完成P08，更不以试验通过代替最终完整交付。P00的3–5人周仅含可行性实验，不含这些子系统的最终实现。

P11只签收外部Chrome/Edge调试合同；集成浏览器的DAP/CDP交叉case留在P12，P12明确依赖P11，避免循环依赖或提前假签收。

### 4.1 每包必须交付什么

每包都包含：上游条目映射、用户流程与状态设计、Rust/Flutter 服务合同、实现与迁移、小范围单元/真实集成/GUI 对照、故障与内存采样、所有设置/键位/错误文案、文档与 evidence。不能只交 UI 或只交后端接口。

P00 先产出并验证注册项提取器，枚举：

- 核心 command/action/editor contribution、菜单/子菜单、默认键位/when、configuration/editorOptions；
- 内置 manifest 的 commands/configuration/views/viewContainers/languages/grammars/snippets/themes/iconThemes/debuggers/taskDefinitions/notebook renderer/serializer 等；
- 默认实际激活的提供者、`product.json` 外部预置物、可选功能开关及平台条件；
- theme color/product icon、工作台状态/空态/错误/恢复页面；
- core framework 与默认 provider 的依赖，区分 A–G，保存排除证据。

静态提取不能只靠搜 `registerCommand`；核心注册经 Action2/编辑器动作/多层包装、运行时注入。结合构建运行时 registry 导出、manifest 与源码 AST，互相校验，标记来源和可达性。命令/设置每个原子项记录 `upstream_id → 功能族 → 本地实现 → case_id → evidence`；不确定项保持未消化。

本次已实查 [源目录快照](plans/vscode-source-inventory.json) 和 [内置 manifest 摘要](plans/vscode-builtin-manifests.json)，并建立[发现项路由](plans/vscode-source-coverage.json)：417个目录条目+45个文档条目全部路由到功能族，131项需进一步判定注册可达性/混合依赖。目录遍历完整不等于已阅读每个源文件；全部462项仍需P00原子审查，不把路由数当语义覆盖率。

### 4.2 首轮执行顺序

1. P00：固定可运行参考、导出贡献清单，建立双文件交替撤销、超大未保存文件、关闭工作区进程、长延迟补全四个现状fixture；顺序执行编辑器/Web引擎/官方服务三项限时风险实验。
2. P01：先把生命周期/异步/版本合同建好，再逐项迁移现有功能；同时保留真实 FFI 回归。
3. P02/P03：先保证文本不丢与可扩展编辑控件；IME、万行/长行、多光标、视图共享、undo 任一硬门失败，不堆语言/终端 UI。
4. P04/P05/P06/P07：完成标准工作台闭环和配置骨架，视觉对照从 P05 开始逐页验收。
5. P08/P09/P10/P11/P12/P13：按依赖逐项交付全部默认能力，全部使用同一命令/配置/进程框架。
6. P14/P15：清空差异与服务阻塞，完成三平台和完整场景对照；未经证据签收不得宣称 1:1。

## 5. 界面与交互的复刻方法

### 5.1 设计资产

从固定上游 CSS、theme color、icon registry、默认设置和截图中提取 token，不猜测过时的固定像素值。建立 `WorkbenchTheme`、`Metrics/Density`、`ProductIconTheme`、`FileIconTheme`、`EditorTheme`，让标题栏、列表、树、输入框、菜单、按钮、徽章、工具提示、滚动条、sash 共享同一套 token 与状态。

参考页至少包括：空窗口/Welcome、普通项目、多根、资源管理器/搜索/SCM/调试/测试、单/多编辑器组、浮窗与 modal editor、Settings/键位/Profiles、终端/Problems/Output、diff/merge、多文档保存冲突、Markdown/Notebook/浏览器、账号/同步/端口、所有关闭恢复和错误状态。每页覆盖鼠标与纯键盘路径。

测试基线：Windows 11、Linux X11/Wayland、macOS；100/125/150/200% 缩放；默认暗/亮/高对比主题；英文默认文案 + 中文覆盖；固定字体和窗口尺寸。上游中文若需额外 language pack，作为明确的 locale 参考资产，不冒称默认内置中文包。

### 5.2 视觉通过标准

- 几何基线：默认密度下关键矩形边界/对齐误差 ≤1 个逻辑像素；颜色/图标标识/顺序/文案逐项一致；文本 baseline 与滚动/点击命中区一致。
- PNG golden：保存上游图、Alula 图、difference/overlay；确定性控件要求零结构性差异。抗锯齿差异单独掩膜并附理由，掩膜不能覆盖整个编辑器/复杂视图。
- 交互状态逐一匹配：hover、focus、active/inactive、checked、disabled、loading、error、empty、dirty、preview/pinned、拖放预览和键位提示。
- 任何被接受的差异都有 `difference_id / 原因 / 影响 / 验收人 / 版本`。确实妨碍 1:1 的差异保持 open；不能写进“已知限制”后仍标总目标完成。

### 5.3 行为对照

同一 fixtures 与操作脚本驱动参考版和 Alula，比较完整可观察状态：文本/UTF-16 selection/undo/redo/savepoint、焦点/组/导航栈、磁盘 hash/编码/EOL、配置有效值、Git 状态、进程退出、错误提示。固定时间只用于稳定等待，不能把慢服务竞态藏进 sleep。依赖外部系统的场景使用协议 fixture + 真实服务试跑两层证据。

## 6. 内存、性能与稳定性合同

沿用 docs/04 的平台口径：Windows 进程树 Private Bytes；Linux 进程树 PSS；macOS phys_footprint。**不累加 RSS。** Flutter/Rust 主进程、语言服务、Node helper、终端、WebView、浏览器子进程与隧道逐项归因；端口/窗口关闭后也要观察回收。

| 场景 | 目标与通过口径 |
|---|---|
| 空白工作台 | ≤200 MiB 目标；300 MiB 是旧阶段退让线，超过200必须说明，不自动算挑战值达成 |
| 普通项目、无语言服务 | ≤250 MiB；同根目录/同文件/同配置 |
| Rust + rust-analyzer 附加能力 | ≤500 MiB 既有目标；服务规模单列，不代替默认 JS/TS 的对照 |
| 默认完整功能场景 | 同工程、同已开启功能与相同工具链，对 VS Code 总进程树降低 ≥50% 为主目标；未到则报告差距 |
| 冷启动 | ≤2s 可交互目标，固定硬件/缓存状态，至少3次，报中位/峰值 |
| 输入/帧率 | 普通编辑输入到绘制 p95≤50ms；交互帧 p95≤16.7ms 为60Hz目标；大文件另报上界/降级条件 |
| 空闲 | 10min CPU 近0、无全量常驻轮询、无持续内存增长 |
| 回收 | 关闭工作区后30s内无其遗留服务/PTY/索引任务；共享引擎内存归属说明 |

新增每种常驻结构必须有 owner、容量预算、淘汰/关闭策略和观测值：文档缓存、undo/redo、token/Tree、文件索引、搜索结果、Git diff、终端 scrollback、Notebook 输出、本地历史、网络队列。禁止靠静默截断文档/journal 或删功能省内存。

至少采集启动峰值、1min稳定态、10min空闲、30min编辑、关闭+30s，重复≥3次。旧 179–190 MiB 空载数字不能充当默认内置语言、终端、Notebook、浏览器全开后的数据。

压力/故障矩阵：内存限额扫描、系统提交压力、慢/坏盘/磁盘满/权限失败、保存中强杀、损坏journal、watcher overflow、Git锁、LSP/DAP/终端/WebView强杀、网络断线/认证失效。Warn/Critical 模式优先保留输入、缓冲区和保存；释放可重建缓存，暂停后台索引/预览；不得丢未保存数据。64MiB 等低档只报告能否启动和最低可工作档位，不承诺 Flutter 在每档均可运行。

## 7. 风险与决策门

| 门 | 必须回答的问题 | 失败后的行动 |
|---|---|---|
| G-P00 参考可重复 | 该SHA能否构建？下载式预置物/服务是否有确定来源？所有条目可分类？ | 阻塞范围声明；明确缺失资产；一次有记录的版本调整 |
| G-P01 异步和生命周期 | 慢/失序服务、切工作区、强杀能否不阻塞且无遗留？ | 修协议/监督树；不继续挂更多服务 |
| G-P03 编辑器 | IME/多光标/万行/长行/可访问性/多视图/内存均达标？ | 扩展组件或自研局部渲染；保留架构，不直接切回Electron |
| G-P08 语言等价 | TextMate scopes/JS-TS默认语义/编辑返回是否完整？ | 补provider与协议，不以rust-analyzer demo替代 |
| G-P12 富内容 | Markdown rich/Notebook/browser 是否1:1且按需内存可接受？ | 调整隔离/缓存/引擎；保持功能未完成，不能取消需求 |
| G-P13 官方服务 | OAuth/client/同步/隧道/市场的真实互通与发布前提是否满足？ | 记录外部阻塞，继续独立模块；自有服务单独验收但不抹去差异 |
| G-P15 发布 | 范围内每项有证据、未消化项=0、所有硬门绿？ | 保持阶段未完成，不用“基本一致”通过 |

若 1:1 功能与低内存目标发生冲突，分别列出功能通过情况与资源差距，优先优化/按需启动。任何永久删减或改变目标都需要用户明确调整范围；不能由实施者私自把目标降为 MVP。

## 8. 版本、依赖与分发

引用或移植上游代码/资产时建立来源清单、固定版本、原始许可/notice、修改记录与 SBOM。VS Code 源码的 [MIT 许可](https://github.com/microsoft/vscode/blob/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/LICENSE.txt) 与 docs 的 [文档/示例许可](https://github.com/microsoft/vscode-docs/blob/da213552439825628e0ab958dbde1e413dbc36bf/LICENSE.md)分别登记；自有产品名与标识单列。第三方预置扩展、字体/图标、Web组件、OAuth和官方服务的再分发与互通条件分别核查，不能从一个仓库的许可推导所有下载物可用。

发布包必须包含可离线提供的默认语法/主题/服务资产；本机 Git/运行时/联网服务的前提有检测与可操作错误。Windows安装/便携模式、Linux包、macOS包、CLI/文件关联/URL、升级回退、卸载保留用户数据策略纳入P14/P15。

## 9. 执行与证据管理

- docs/03：唯一阶段状态、依赖与 DoD；feature_list.json 是它的执行镜像，不另立第二套完成判据。
- docs/11 + plans/vscode-parity-matrix.json：需求、上游、验收映射；当前基础只是复用提示，不是完成状态。原型 done 不继承为等价 done。
- plans/vscode-source-inventory.json + vscode-builtin-manifests.json：此次上游发现证据。P00 将补贡献注册项导出与 coverage ledger。
- `docs/parity/<reference>/<os>/<case_id>/`（P00建立）：参考/实际截图、diff、文本/文件/进程快照、环境清单；`docs/baselines/` 继续存性能。
- 每次仅取一个可满足依赖的 feature，impact→实现→必要测试→完整DoD→证据→状态更新；commit前detect_changes，不代替实际测试。

计划完成的判据是：版本与范围明确、功能族无遗漏分类、逐项验收可执行、依赖/风险/估算齐全、台账和交接可续作。它与产品复刻完成是两个不同的结论。本轮交付前会记录实际验证命令结果，不以历史“init.sh全绿”代替当前证据；`init.sh` 目前不含 fmt/analyze，二者须显式执行。

## 10. 主要官方来源

- [工作台 parts](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/browser/parts)、[contrib](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib)、[services](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/services)。
- [编辑器贡献](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/editor/contrib)、[内置扩展](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/extensions)、[产品预置物](https://github.com/microsoft/vscode/blob/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/product.json)。
- [编辑与工作区文档](https://github.com/microsoft/vscode-docs/tree/da213552439825628e0ab958dbde1e413dbc36bf/docs/editing)、[配置](https://github.com/microsoft/vscode-docs/tree/da213552439825628e0ab958dbde1e413dbc36bf/docs/configure)、[源码管理](https://github.com/microsoft/vscode-docs/tree/da213552439825628e0ab958dbde1e413dbc36bf/docs/sourcecontrol)。
- [终端](https://github.com/microsoft/vscode-docs/tree/da213552439825628e0ab958dbde1e413dbc36bf/docs/terminal)、[任务/调试/测试/浏览器/端口](https://github.com/microsoft/vscode-docs/tree/da213552439825628e0ab958dbde1e413dbc36bf/docs/debugtest)、[语言文档](https://github.com/microsoft/vscode-docs/tree/da213552439825628e0ab958dbde1e413dbc36bf/docs/languages)。
