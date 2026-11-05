# 11 · VS Code 功能对照矩阵

> 日期：2026-10-27；参考版本与范围合同见 [总计划](10-VSCode无插件全功能复刻总计划.md)。
> 本表含 **342 项功能族验收条目、14 项边界决策**。每个分号/注册命令仍需P00展开成原子case，不能将条目数量当作上游命令数量或完成率。
> **本表不是完成状态表**：实施包状态与DoD唯一权威在 [docs/03](03-里程碑计划与验收标准.md)。所有现有原型都必须重新对照验收。
> [机器可读JSON](plans/vscode-parity-matrix.json) 与本表同源；A=核心，B=随附扩展，C=系统工具，D=非AI外部服务，E=用户扩展业务，F=外接AI，G=条件/开发与差异项。

共同验收：同SHA/OS/字体/主题/DPI/窗口/fixture；键鼠/IME/焦点/错误/取消/恢复；保存截图和可观察状态。每条以所列case_id为前缀建立正常、边界、失败与平台子case，不能只做happy path。普通能力可用范围服从provider能力与实际默认配置，不将测试mock当默认provider。

## REF · 参考版本与可验收资产（P00，A）

当前基础：未建立完整对照。上游：[product.json](https://github.com/microsoft/vscode/blob/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/product.json)，[src/vs/workbench/contrib](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib)，[extensions](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/extensions)；[官方行为文档](https://github.com/microsoft/vscode-docs/blob/da213552439825628e0ab958dbde1e413dbc36bf/docs/toc.json)。

| ID / case前缀 | 功能 | 必须验收的结果 |
|---|---|---|
| REF-01 / parity-ref-01 | 固定构建与配置 | 构建固定SHA，保存版本/产品配置/OS/默认flags；重复构建产物来源可追踪 |
| REF-02 / parity-ref-02 | 默认贡献清单 | 核心运行时注册、AST和全部随附manifest交叉核对；命令/菜单/键位/设置均有原子ID |
| REF-03 / parity-ref-03 | 下载式预置物 | js-debug/companion/profile-table锁版本与hash并验证真实可运行，不漏仓库外预置扩展 |
| REF-04 / parity-ref-04 | 范围与排除账本 | 每项分类A–G并附理由；默认关闭实验功能独立标记，未知项不能计完成 |
| REF-05 / parity-ref-05 | 视觉参考资产 | 固定主题/字体/DPI/尺寸，保存核心页面及交互状态golden，不混用旧版截图 |
| REF-06 / parity-ref-06 | 行为对拍资产 | 相同fixture和操作序列比较文本/选区/dirty/磁盘/焦点/进程 |
| REF-07 / parity-ref-07 | 现存风险复现 | 双文件撤销、超2M字符恢复、关闭工作区进程、慢补全各有可重复用例 |
| REF-08 / parity-ref-08 | 版本升级差异 | 升级参考版本时列新增/删改注册项与回归，未经登记不能滚动跟随main |
| REF-09 / parity-ref-09 | P00早期技术风险实验 | 依次限时验证编辑器IME+delta/多光标、三平台web引擎DevTools-CDP-MHTML、官方服务参考/客户端注册可行性；各有ADR与证据，不等到P12/P13才发现阻塞 |

## SRV · 服务基础与生命周期（P01，A）

当前基础：同步FFI与原型命令可复用。上游：[src/vs/workbench/services](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/services)，[src/vs/workbench/contrib/commands](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/commands)；[官方行为文档](https://github.com/microsoft/vscode-docs/blob/da213552439825628e0ab958dbde1e413dbc36bf/docs/editing/workspaces/workspaces.md)。

| ID / case前缀 | 功能 | 必须验收的结果 |
|---|---|---|
| SRV-01 / parity-srv-01 | 文档和视图身份 | 同一workbench的组和辅助浮窗共享文档；独立顶层窗口按session+URI隔离dirty buffer，以外改/保存冲突协调 |
| SRV-02 / parity-srv-02 | 异步请求事件合同 | request/document/workspace/version标识齐全，慢请求不阻塞UI |
| SRV-03 / parity-srv-03 | 取消超时与背压 | 关视图/工作区取消任务，超时返回明确状态，事件队列/并发有界 |
| SRV-04 / parity-srv-04 | 过期和失序回包 | 旧版本补全/诊断/搜索结果不覆盖新文档和新工作区 |
| SRV-05 / parity-srv-05 | FFI版本与资源 | 双侧ABI握手、错误/内存释放合同及真实UTF-16对拍全绿 |
| SRV-06 / parity-srv-06 | 命令与上下文引擎 | 命令ID/参数/条件/启用状态由菜单/面板/键位共用，条件变化立即生效 |
| SRV-07 / parity-srv-07 | 进程监督树 | Git/rg/LSP/DAP/PTY/Node/web子树可归属、限额、取消、重启和回收 |
| SRV-08 / parity-srv-08 | 资源压力与预算 | Warn/Critical可见，优先保留编辑保存；缓存与后台任务可回收 |
| SRV-09 / parity-srv-09 | 事件驱动更新 | 空闲无周期性全文件解析；修改只触发必要文档和范围更新 |
| SRV-10 / parity-srv-10 | 多工作区生命周期 | 打开/切换/关闭根目录释放其订阅和服务，后台失败不破坏文本 |

## DOC · 文档、保存与恢复（P02，A）

当前基础：Rope/原子保存/journal原型；等价未验证。上游：[src/vs/workbench/services/textfile](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/services/textfile)，[src/vs/workbench/services/workingCopy](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/services/workingCopy)，[src/vs/workbench/contrib/localHistory](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/localHistory)；[官方行为文档](https://github.com/microsoft/vscode-docs/blob/da213552439825628e0ab958dbde1e413dbc36bf/docs/editing/codebasics.md)。

| ID / case前缀 | 功能 | 必须验收的结果 |
|---|---|---|
| DOC-01 / parity-doc-01 | 打开与未命名文档 | 文件/URI/untitled/语言选择/打开失败状态与参考一致 |
| DOC-02 / parity-doc-02 | 保存另存为全部保存 | 保存点、路径变更、编码、脏标记与窗口标题同步 |
| DOC-03 / parity-doc-03 | 自动保存 | 延时/失焦/窗口切换及例外设置遵循同一状态机 |
| DOC-04 / parity-doc-04 | 撤销重做与保存点 | 每文档事务历史独立，IME合并/undo stop/redo分支正确 |
| DOC-05 / parity-doc-05 | 跨文档编辑事务 | WorkspaceEdit范围/版本校验，部分失败可回滚，undo归属明确 |
| DOC-06 / parity-doc-06 | 编码探测和重开 | UTF-8/UTF-8 BOM/UTF-16/GBK等固定支持清单逐项roundtrip |
| DOC-07 / parity-doc-07 | 按编码保存 | 不可表示字符/转换失败有明确反馈，不静默损坏内容 |
| DOC-08 / parity-doc-08 | 换行符处理 | LF/CRLF/BOM/无末尾换行保持，转换后的dirty与undo正确 |
| DOC-09 / parity-doc-09 | 外部变更重载 | 干净文档自动重载且保留视图；脏文档提示冲突 |
| DOC-10 / parity-doc-10 | 保存冲突比较 | 比较/覆盖/重试/取消保留双方文本，不先覆盖磁盘 |
| DOC-11 / parity-doc-11 | 删除重命名孤儿文档 | 外部删改后缓冲仍可编辑/另存，路径和标签状态一致 |
| DOC-12 / parity-doc-12 | 只读权限和二进制 | 识别只读/权限/二进制，拒绝或确认动作清晰 |
| DOC-13 / parity-doc-13 | 可靠原子写入 | 磁盘满/权限/锁文件/中断下磁盘无半写且原内容可恢复 |
| DOC-14 / parity-doc-14 | Hot Exit与退出确认 | 各OS退出/关末窗/重载策略和未保存确认一致 |
| DOC-15 / parity-doc-15 | 已接受编辑文档的可靠恢复 | 所有已接受编辑文档含>2M字符均可靠备份，dirty正确；超支持容量须编辑前明确拒绝或采用可验证流式策略 |
| DOC-16 / parity-doc-16 | journal损坏与掉电 | 校验/版本/备份/原子替换、保存中强杀均有恢复证据 |
| DOC-17 / parity-doc-17 | Local History | 条目合并/上限/exclude/create/rename/delete/compare/restore及删除文件恢复 |
| DOC-18 / parity-doc-18 | 会话隔离与视图恢复 | 布局/组/标签/选择/滚动/折叠/MRU按窗口和工作区恢复 |

## REN · 编辑器绘制与输入（P03，A）

当前基础：仍为TextField；需组件硬门。上游：[src/vs/editor/contrib](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/editor/contrib)，[src/vs/workbench/contrib/codeEditor](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/codeEditor)；[官方行为文档](https://github.com/microsoft/vscode-docs/blob/da213552439825628e0ab958dbde1e413dbc36bf/docs/editing/codebasics.md)。

| ID / case前缀 | 功能 | 必须验收的结果 |
|---|---|---|
| REN-01 / parity-ren-01 | 虚拟化与大文件 | 万行/五万行/超长行编辑滚动达预算，显式降级不截断文本 |
| REN-02 / parity-ren-02 | 字体与文本布局 | 字号/字重/行高/字距/连字/CJK/emoji/组合字符宽度和命中一致 |
| REN-03 / parity-ren-03 | IME与复杂输入 | 微软拼音/fcitx5/ibus/macOS组合、撤销、移动与候选窗位置正确 |
| REN-04 / parity-ren-04 | RTL与双向文本 | 混排光标、选择、显示和控制字符提示对照通过 |
| REN-05 / parity-ren-05 | 行号和gutter | 绝对/相对/间隔/关闭，断点/折叠/装饰命中正确 |
| REN-06 / parity-ren-06 | 光标与选区 | 样式/闪烁/动画/多光标/不活动选区及选区方向一致 |
| REN-07 / parity-ren-07 | 缩进与括号引导 | indent/bracket guides、括号对颜色、匹配与错误装饰正确 |
| REN-08 / parity-ren-08 | 空白控制字符和rulers | 显示模式、制表宽度、不可见/Unicode疑似字符和标尺正确 |
| REN-09 / parity-ren-09 | 换行与水平滚动 | wordWrap/缩进/长行/scrollBeyondLastLine等选项影响与参考一致 |
| REN-10 / parity-ren-10 | Minimap与概览标尺 | 缩放/位置/高亮/section header/拖动跳转与可见区同步 |
| REN-11 / parity-ren-11 | Sticky Scroll | 嵌套层级/点击/折叠/滚动与语言结构一致 |
| REN-12 / parity-ren-12 | 折叠视图 | 手动/缩进/语义折叠状态与hidden range、选择移动兼容 |
| REN-13 / parity-ren-13 | 装饰层和inline内容 | 诊断波浪线/hover/CodeLens/inlay/inline hints/字形与布局不漂移 |
| REN-14 / parity-ren-14 | 滚动输入 | 平滑/鼠标中键/触控板/自动滚动/字体缩放及跨DPI对齐 |
| REN-15 / parity-ren-15 | 编辑器可访问语义 | screen reader读行/选区/诊断与Tab焦点模式；不能只绘制canvas无语义 |

## EDT · 编辑命令与比较（P04，A）

当前基础：基础查找/快照撤销原型；需完整重验。上游：[src/vs/editor/contrib](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/editor/contrib)，[src/vs/workbench/contrib/mergeEditor](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/mergeEditor)，[src/vs/workbench/contrib/multiDiffEditor](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/multiDiffEditor)；[官方行为文档](https://github.com/microsoft/vscode-docs/blob/da213552439825628e0ab958dbde1e413dbc36bf/docs/editing/codebasics.md)。

| ID / case前缀 | 功能 | 必须验收的结果 |
|---|---|---|
| EDT-01 / parity-edt-01 | 移动与选择命令 | 字符/word/subword/行/页/文件首尾与选择变体、smart Home逐项对照 |
| EDT-02 / parity-edt-02 | 鼠标选择与锚点 | 单双三击/拖选/anchor/自动滚动/方向保持正确 |
| EDT-03 / parity-edt-03 | 多光标与列选 | 增加上下光标/各次出现/跳过匹配/合并重叠/box选择一致 |
| EDT-04 / parity-edt-04 | 光标撤销重做 | cursor undo/redo与文本undo分别工作，不串文档 |
| EDT-05 / parity-edt-05 | 插入覆写和删除 | insert/OVR/词删除/行边界删除/粘贴覆写及状态栏正确 |
| EDT-06 / parity-edt-06 | 缩进与自动闭合 | Tab/反缩进/自动缩进/括号引号surround/跳过/删除/智能回车一致 |
| EDT-07 / parity-edt-07 | 行操作 | 移动/复制/删除/插入上下行/合并/排序/去重等实际注册项全部有case |
| EDT-08 / parity-edt-08 | 大小写与文本转换 | 大小写/title/camel/snake等固定注册项、transpose、数值替换正确 |
| EDT-09 / parity-edt-09 | 注释和格式清理 | 行块注释、尾空白/末换行/缩进转换与语言配置一致 |
| EDT-10 / parity-edt-10 | 剪贴板与多选粘贴 | 空选区整行copy/cut、多光标分发、CRLF、缩进、富文本copy正确 |
| EDT-11 / parity-edt-11 | 文本拖放和Paste As | 同/跨编辑器move/copy，纯文本/链接/图片paste-drop provider及撤销正确 |
| EDT-12 / parity-edt-12 | 片段会话 | placeholder/Tabstop/choice/变量/转换/嵌套/多光标/取消与用户片段正确 |
| EDT-13 / parity-edt-13 | 查找基础 | case/whole word/regex/selection scope/多行、上下循环/计数/高亮/历史正确 |
| EDT-14 / parity-edt-14 | 替换语义 | capture/preserve case/转义/大小写变换/零宽匹配/当前与全部替换可撤销 |
| EDT-15 / parity-edt-15 | 查找交互和异常 | Esc/Enter/Alt+Enter/焦点/调整大小/非法regex/巨大结果反馈一致 |
| EDT-16 / parity-edt-16 | 定义导航与导航历史 | F12/鼠标跳转到定义（同文件/跨文件 provider）；back/forward/last edit与跨文档/组选择位置、最近文件正确 |
| EDT-17 / parity-edt-17 | 文本差异编辑器 | inline/side-by-side/word diff/moved blocks/忽略空白/折叠未变区/下一差异正确 |
| EDT-18 / parity-edt-18 | 差异操作 | 选中文件比较/与剪贴板/已保存版本、可编辑右侧、apply/revert块对照 |
| EDT-19 / parity-edt-19 | 三方合并 | base/input1/input2/result、accept/combine/conflict导航、保存与未解状态正确 |
| EDT-20 / parity-edt-20 | 批量编辑预览与Multi Diff | 按文件/块选择、预览、应用失败/回滚、dirty/undo与多资源差异一致 |

## LAY · 工作台界面与通用控件（P05，A）

当前基础：分割树/五区/标签原型可复用。上游：[src/vs/workbench/browser/parts](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/browser/parts)，[src/vs/workbench/services/layout](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/services/layout)，[src/vs/workbench/services/views](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/services/views)；[官方行为文档](https://github.com/microsoft/vscode-docs/blob/da213552439825628e0ab958dbde1e413dbc36bf/docs/configure/custom-layout.md)。

| ID / case前缀 | 功能 | 必须验收的结果 |
|---|---|---|
| LAY-01 / parity-lay-01 | 标题栏与菜单 | native/custom、拖动/双击/窗口按钮、菜单层级/mnemonic/macOS菜单一致 |
| LAY-02 / parity-lay-02 | Command Center和布局控制 | 标题模板/dirty/profile/workspace、命令中心/布局按钮状态和键盘路径一致 |
| LAY-03 / parity-lay-03 | Activity Bar | 位置/大小/隐藏、顺序/切换/徽章/Accounts/Manage与右键一致 |
| LAY-04 / parity-lay-04 | 主次侧栏 | 左右/显示/默认策略、视图移动/拆分/折叠、空态与持久化一致 |
| LAY-05 / parity-lay-05 | Panel位置与alignment | 固定注册位置/对齐/最大化/还原/拖放、最小尺寸正确 |
| LAY-06 / parity-lay-06 | sash与布局恢复 | 拖动/双击重置/折叠记忆/reset view locations跨缩放不漂移 |
| LAY-07 / parity-lay-07 | 编辑器组布局 | 任意水平垂直分割、同组split、移动复制/顺序/均分/最大化/锁组正确 |
| LAY-08 / parity-lay-08 | 标签模式 | multiple/single/none、wrap/multirow、大小/关闭按钮/图标/路径消歧正确 |
| LAY-09 / parity-lay-09 | preview/pinned/sticky标签 | 预览被替换/首次编辑转永久、sticky单行/关闭规则正确 |
| LAY-10 / parity-lay-10 | 标签交互与关闭菜单 | 拖放/跨组/复制/中键/overflow/MRU、关闭左右其他已保存及脏确认正确 |
| LAY-11 / parity-lay-11 | Open Editors与面包屑 | 各组树、路径/符号picker、排序/键盘/复制/随光标定位一致 |
| LAY-12 / parity-lay-12 | 浮动辅助窗口 | 拖标签新窗、组/焦点同步、compact/pin-top/移回/关闭恢复一致 |
| LAY-13 / parity-lay-13 | Modal Editor | workbench.editor.useModal=off/some/all；Settings/Keys/Profiles/Trust/Extensions、Esc/外点/最大化/移回tab/focus trap逐项对照 |
| LAY-14 / parity-lay-14 | Zen全屏居中和密度 | 进入退出/Esc/toolbar/window zoom/palette位置/compact状态可恢复 |
| LAY-15 / parity-lay-15 | 跨编辑器锁定滚动 | Toggle/Hold locked scrolling及状态栏、不同文档长度/组/窗口正确 |
| LAY-16 / parity-lay-16 | 列表树表格控件 | 多选/range/键盘/type navigation/filter/列resize/右键/hover状态一致 |
| LAY-17 / parity-lay-17 | QuickInput和多步picker | 分组/多选/描述/detail/buttons/back/校验/历史/取消及焦点恢复一致 |
| LAY-18 / parity-lay-18 | 通知与进度 | toast/center/banner/DND/来源过滤/actions/取消/loading/error/可访问提示一致 |
| LAY-19 / parity-lay-19 | 欢迎与引导 | Welcome/Walkthrough/空组watermark/最近项目/帮助路径及持久化一致 |
| LAY-20 / parity-lay-20 | 焦点和拖放全链路 | 菜单/树/编辑器/面板/浮窗切换焦点、跨应用DnD、drop overlay与快捷键路由一致 |

## CMD · 快速访问与结构导航（P05，A）

当前基础：CommandRegistry/QuickInput/大纲原型。上游：[src/vs/workbench/contrib/quickaccess](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/quickaccess)，[src/vs/workbench/contrib/outline](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/outline)，[src/vs/editor/contrib/peekView](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/editor/contrib/peekView)；[官方行为文档](https://github.com/microsoft/vscode-docs/blob/da213552439825628e0ab958dbde1e413dbc36bf/docs/editing/editingevolved.md)。

| ID / case前缀 | 功能 | 必须验收的结果 |
|---|---|---|
| CMD-01 / parity-cmd-01 | 命令面板 | 类别/模糊匹配/MRU/参数/禁用条件/键位提示与默认命令全集正确 |
| CMD-02 / parity-cmd-02 | 快速打开 | 路径/文件名/多根/fuzzy/MRU/绝对路径/:line:column，全部文件可达 |
| CMD-03 / parity-cmd-03 | Go to Line与位置 | 行列输入/比例等实际注册格式及UTF-16定位正确 |
| CMD-04 / parity-cmd-04 | 文档符号picker | 层级/类别/过滤/预览/侧开/取消恢复位置一致 |
| CMD-05 / parity-cmd-05 | 工作区符号 | provider/多根/取消/排序/无结果/侧开定位正确 |
| CMD-06 / parity-cmd-06 | Breadcrumbs符号路径 | 显示开关/顺序/下拉/键盘/鼠标切组路径正确 |
| CMD-07 / parity-cmd-07 | Outline视图 | 层级/过滤/排序/follow cursor/折叠/定位与最新版本一致 |
| CMD-08 / parity-cmd-08 | Peek与References | 可调整/固定/树与编辑器切换/下一项/打开关闭焦点正确 |
| CMD-09 / parity-cmd-09 | 定义声明实现类型导航 | 支持Location/LocationLink/多结果/跨文件，不以同名匹配替代 |
| CMD-10 / parity-cmd-10 | 调用与类型层级 | 上游provider可用时方向/分页/导航、无provider为空态 |
| CMD-11 / parity-cmd-11 | Problems导航 | F8/Shift+F8/筛选/跨文件/内联错误与位置范围正确 |
| CMD-12 / parity-cmd-12 | 链接打开与可信域 | 路径/URL识别、修饰键/hover/open-to-side、确认和允许域持久化正确 |

## FS · 资源管理器与工作区（P06，A）

当前基础：懒树/Dart watcher/单根原型。上游：[src/vs/workbench/contrib/files](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/files)，[src/vs/workbench/contrib/workspaces](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/workspaces)，[src/vs/workbench/contrib/timeline](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/timeline)；[官方行为文档](https://github.com/microsoft/vscode-docs/blob/da213552439825628e0ab958dbde1e413dbc36bf/docs/editing/workspaces/multi-root-workspaces.md)。

| ID / case前缀 | 功能 | 必须验收的结果 |
|---|---|---|
| FS-01 / parity-fs-01 | Explorer创建与重命名 | 文件/文件夹/嵌套路径/大小写rename/重复名/非法路径正确 |
| FS-02 / parity-fs-02 | 删除与回收站 | trash/permanent/确认/失败/撤销可用性按平台对照 |
| FS-03 / parity-fs-03 | 复制剪切粘贴和duplicate | 文件夹递归/名称冲突/权限/脏文档身份和状态一致 |
| FS-04 / parity-fs-04 | 文件拖放与导入 | 移动复制/跨根/跨窗/系统导入/覆盖确认/取消不丢文件 |
| FS-05 / parity-fs-05 | 多选和树导航 | range/键盘/type navigation/展开折叠/刷新保持选择与展开态 |
| FS-06 / parity-fs-06 | compact与file nesting | 压缩路径/嵌套规则/排序/exclude/gitignore/autoreveal一致 |
| FS-07 / parity-fs-07 | 文件装饰与Open With | dirty/SCM/只读/符号链接、默认编辑器/侧开/重新打开正确 |
| FS-08 / parity-fs-08 | 路径动作 | copy absolute/relative path、reveal OS/terminal、比较选定文件正确 |
| FS-09 / parity-fs-09 | 空窗单文件与文件夹 | 打开/复用新窗策略与最近列表符合平台设置 |
| FS-10 / parity-fs-10 | 多根工作区 | add/remove/reorder/name、重复basename、嵌套根和多根disambiguation一致 |
| FS-11 / parity-fs-11 | .code-workspace | 相对绝对路径、JSONC schema/settings/tasks/launch、Save Workspace As roundtrip |
| FS-12 / parity-fs-12 | 根目录失效和切换 | 目录被删/重命名/离线、关闭根脏确认及进程回收正确 |
| FS-13 / parity-fs-13 | URI和平台路径 | Windows drive/UNC/case、Unix权限/symlink、路径编码与URI往返正确 |
| FS-14 / parity-fs-14 | 文件系统provider合同 | stat/read/write/watch/atomic/readonly/error语义，默认本地provider真实可用 |
| FS-15 / parity-fs-15 | 递归watcher与事件合并 | 创建/修改/移动/删除按path刷新，风暴不重读全部文档 |
| FS-16 / parity-fs-16 | watcher失效恢复 | overflow/权限/平台递归限制有观测、重扫与错误状态 |
| FS-17 / parity-fs-17 | Timeline视图 | 筛选provider/refresh/paging/排序，与Git和Local History关联 |
| FS-18 / parity-fs-18 | 本地历史恢复入口 | 从Explorer/Timeline查找已删文件、比较和恢复与文档模型同步 |

## SRC · 全局搜索与Search Editor（P06，A）

当前基础：rg/git grep流式原型；硬上限需替代。上游：[src/vs/workbench/contrib/search](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/search)，[src/vs/workbench/contrib/searchEditor](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/searchEditor)，[extensions/search-result](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/extensions/search-result)；[官方行为文档](https://github.com/microsoft/vscode-docs/blob/da213552439825628e0ab958dbde1e413dbc36bf/docs/editing/codebasics.md)。

| ID / case前缀 | 功能 | 必须验收的结果 |
|---|---|---|
| SRC-01 / parity-src-01 | 搜索选项 | case/whole word/regex/multiline/上下文行与参考命中一致 |
| SRC-02 / parity-src-02 | include exclude与ignore | glob/多根path/.ignore/.gitignore/files.exclude/search.exclude和开关正确 |
| SRC-03 / parity-src-03 | 隐藏符号链接和编码 | 按配置搜索含非UTF8/hidden/symlink/binary策略，不无界递归 |
| SRC-04 / parity-src-04 | 未保存内存文本 | 搜索/替换包含dirty缓冲区且与磁盘结果去重 |
| SRC-05 / parity-src-05 | 增量结果与取消 | 流式结果/进度/取消/新查询替换旧查询不泄漏子进程 |
| SRC-06 / parity-src-06 | 结果树与统计 | 按文件分组/list/sort/collapse/remove、计数/截断/错误状态一致 |
| SRC-07 / parity-src-07 | 结果定位与复制 | 点击/键盘next-prev/侧开/复制结果路径命中、中文UTF-16行列正确 |
| SRC-08 / parity-src-08 | 范围与变更文件搜索 | 多根/选中文件夹/changed-files-only按固定设置与菜单支持 |
| SRC-09 / parity-src-09 | 替换预览 | 单条/文件/全局预览和确认，regex/capture/preserve case正确 |
| SRC-10 / parity-src-10 | 全局替换事务 | dirty/readonly/外部修改冲突、部分失败/撤销不丢内容 |
| SRC-11 / parity-src-11 | Quick Text Search | 快速面板搜索/预览/转完整视图/键盘操作与取消正确 |
| SRC-12 / parity-src-12 | Search Editor创建与保存 | 结果文档可保存重开，位置链接/上下文/参数正确 |
| SRC-13 / parity-src-13 | Search Editor重搜和编辑 | rerun/query focus/reuse配置/open-to-side与可编辑结果一致 |
| SRC-14 / parity-src-14 | 有界但全量可达 | maxResults明确提示并可继续/分页/重查，不能静默限制500条或2000文件 |

## CFG · 设置、键位、Profiles（P07，A）

当前基础：少量keybindings.json覆盖原型。上游：[src/vs/workbench/contrib/preferences](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/preferences)，[src/vs/workbench/contrib/keybindings](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/keybindings)，[src/vs/workbench/contrib/userDataProfile](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/userDataProfile)；[官方行为文档](https://github.com/microsoft/vscode-docs/blob/da213552439825628e0ab958dbde1e413dbc36bf/docs/configure/settings.md)。

| ID / case前缀 | 功能 | 必须验收的结果 |
|---|---|---|
| CFG-01 / parity-cfg-01 | 设置注册表和默认值 | 全部范围内key/type/default/scope/tags/deprecation/限制可追踪 |
| CFG-02 / parity-cfg-02 | Settings GUI | category/search/类型控件/reset/copy key-JSON/有效值/错误与默认体验一致 |
| CFG-03 / parity-cfg-03 | 设置搜索筛选 | modified/language/id/tag/feature等注册过滤及普通文本搜索；AI搜索另排除 |
| CFG-04 / parity-cfg-04 | Settings JSONC | 注释/trailing comma/schema/补全/默认设置/用户-工作区-根目录入口一致 |
| CFG-05 / parity-cfg-05 | 优先级和合并 | default/user/workspace/folder/language/policy按固定规则，object合并/array替换正确 |
| CFG-06 / parity-cfg-06 | 语言覆盖和资源scope | 单/多language override、不同根/URI有效值隔离 |
| CFG-07 / parity-cfg-07 | 设置热更新与失败 | 重载/需重启/无效值/写失败/外部修改保留文本并说明 |
| CFG-08 / parity-cfg-08 | 键位平台默认表 | Ctrl/Cmd/Alt/Meta/scancode/keyboard layout/AltGr/dead key一致 |
| CFG-09 / parity-cfg-09 | chord与when | 多段chord/超时/条件表达式/优先级/焦点上下文及冲突判定正确 |
| CFG-10 / parity-cfg-10 | 用户键位语义 | 移除规则/空命令/args/runCommands/JSONC reload及默认回退正确 |
| CFG-11 / parity-cfg-11 | 键位编辑器 | 搜索/录制/增改删/reset/冲突/同键/来源/布局选择正确 |
| CFG-12 / parity-cfg-12 | 键位诊断与systemWide | 系统级仅桌面/用户定义/单组合键，忽略when/不支持chord，后台触发；OS冲突通知，前台由命令决定；另验troubleshooting |
| CFG-13 / parity-cfg-13 | 用户snippets与tasks | 语言/global/project片段、用户tasks与Profiles隔离正确 |
| CFG-14 / parity-cfg-14 | Profiles创建和切换 | default/named/copy/empty/temporary、名称图标/新窗/删除和关联正确 |
| CFG-15 / parity-cfg-15 | Profiles内容与共享 | settings/keys/snippets/tasks/UI/extensions按选项隔离或all profiles共享 |
| CFG-16 / parity-cfg-16 | Profiles导入导出 | .code-profile本地/URL/Gist预览/选择部分/损坏失败与回滚 |
| CFG-17 / parity-cfg-17 | 工作区信任设置合同 | 受限配置/父目录继承/可信目录管理/外部文件限制，不能被工作区JSON绕过 |

## THM · 颜色、图标与主题（P07，B）

当前基础：未实现VSCode主题等价。上游：[src/vs/workbench/contrib/themes](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/themes)，[src/vs/workbench/services/themes](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/services/themes)，[extensions/theme-defaults](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/extensions/theme-defaults)，[extensions/theme-seti](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/extensions/theme-seti)；[官方行为文档](https://github.com/microsoft/vscode-docs/blob/da213552439825628e0ab958dbde1e413dbc36bf/docs/configure/themes.md)。

| ID / case前缀 | 功能 | 必须验收的结果 |
|---|---|---|
| THM-01 / parity-thm-01 | 所有随附颜色主题 | Dark/Light Modern、Dark+/Light+、高对比及其他内置主题数据全部覆盖 |
| THM-02 / parity-thm-02 | 主题picker预览 | 即时预览/取消回滚/保存选择/工作区偏好和键盘操作正确 |
| THM-03 / parity-thm-03 | 系统外观联动 | OS light/dark/high-contrast检测与preferred theme实时切换 |
| THM-04 / parity-thm-04 | workbench颜色定制 | theme通配覆盖/自定义token/透明度/缺省回退一致 |
| THM-05 / parity-thm-05 | TextMate token主题 | scope匹配/嵌套/优先级与实际grammar scopes对拍 |
| THM-06 / parity-thm-06 | 语义token定制 | legend/modifier/主题规则与TextMate回退、禁用设置正确 |
| THM-07 / parity-thm-07 | 文件图标主题 | Seti/Modern或当前实际内置清单、Minimal/None、文件夹/扩展名/语言优先级 |
| THM-08 / parity-thm-08 | 产品图标主题 | 默认codicon/product icon映射、字体加载与图标定制正确 |
| THM-09 / parity-thm-09 | 主题开发工具 | token-scope inspector/生成当前主题、设置JSON入口与诊断正确 |
| THM-10 / parity-thm-10 | 资产离线加载 | 全部默认主题/语法/图标可离线使用，导入包来源与notice可追踪 |

## LNG · 默认语言能力与Problems（P08，B）

当前基础：Rust-only tree-sitter/RA原型可保留。上游：[extensions](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/extensions)，[src/vs/workbench/contrib/markers](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/markers)，[src/vs/workbench/contrib/languageDetection](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/languageDetection)，[src/vs/editor/contrib/suggest](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/editor/contrib/suggest)；[官方行为文档](https://github.com/microsoft/vscode-docs/blob/da213552439825628e0ab958dbde1e413dbc36bf/docs/languages/overview.md)。

| ID / case前缀 | 功能 | 必须验收的结果 |
|---|---|---|
| LNG-01 / parity-lng-01 | 全部随附语言配置 | 90个源manifest中的74个language ID逐一映射；别名/扩展名/filename/firstLine正确 |
| LNG-02 / parity-lng-02 | TextMate语法与嵌入注入 | 89个grammar条目全部有colorize fixture，HTML内JS/CSS/Markdown fence等不漏 |
| LNG-03 / parity-lng-03 | 语言配置与基础高亮 | 注释/括号/wordPattern/indent/fold/snippets及语言切换/文件关联正确 |
| LNG-04 / parity-lng-04 | 自动语言检测和状态 | 本地识别/状态项/相关命令、错误与禁用设置，普通能力不按AI误排 |
| LNG-05 / parity-lng-05 | provider注册与能力协商 | 按资源/语言/trust按需启动，位置编码/取消/版本/失序完整 |
| LNG-06 / parity-lng-06 | Suggest和传统补全 | 排序/过滤/触发/commit chars/snippets/textEdit/additionalEdit/resolve和文档正确 |
| LNG-07 / parity-lng-07 | Hover与签名 | Markdown/代码块/链接/重载/参数高亮/延时取消及定位正确 |
| LNG-08 / parity-lng-08 | 语义导航与重构 | definition/declaration/implementation/type/references/rename/code action/WorkspaceEdit完整 |
| LNG-09 / parity-lng-09 | 格式化与语义装饰 | format document-range-onType-onSave/CodeLens/inlay/semantic token/color picker按provider能力 |
| LNG-10 / parity-lng-10 | JS-TS项目与诊断 | tsserver工程/ts-jsconfig/推断工程/版本切换/诊断/自动类型获取按默认设置工作 |
| LNG-11 / parity-lng-11 | JS-TS导航补全重构 | auto import/organize imports/rename file/import paths/refactors/quick fixes/JSX-TSX/JSDoc完整 |
| LNG-12 / parity-lng-12 | HTML语言服务 | 标签属性/链接/颜色/格式/linked editing/validation/embedded support一致 |
| LNG-13 / parity-lng-13 | CSS-SCSS-LESS语言服务 | 补全/诊断/导航/rename/颜色/格式/数据配置与Emmet联动一致 |
| LNG-14 / parity-lng-14 | JSON-JSONC与配置编辑 | schema本地远程/关联/缓存/补全/验证/格式、settings/tasks/launch/package配置支持 |
| LNG-15 / parity-lng-15 | Markdown语言服务 | 符号/链接路径/补全/验证/rename/update links/file references与配置一致 |
| LNG-16 / parity-lng-16 | PHP默认有限能力 | 按上游注册补全/hover/signature及php lint；不冒称完整PHP LSP/调试 |
| LNG-17 / parity-lng-17 | Emmet完整非AI能力 | 缩写/展开/包裹/平衡/拆合标签/编辑点/计算等命令和配置逐项对拍 |
| LNG-18 / parity-lng-18 | Problems面板 | 文件分组/筛选/严重性/source/code/相关信息/复制/定位/状态栏与内联显示一致 |
| LNG-19 / parity-lng-19 | References和层级视图 | 默认references-view、调用/类型层级有provider时真实可用，无provider正确空态 |
| LNG-20 / parity-lng-20 | 其他内置开发辅助 | npm/extension-editing/configuration-editing/reference/search-result包非AI命令全部映射 |
| LNG-21 / parity-lng-21 | 非AI Inline Suggestions通用宿主 | ghost text/多行/逐词逐行接受/下一建议/取消/快捷键/无provider空态用协议fixture验证；不虚构默认内联provider |

## GIT · Git与源代码管理（P09，B/C）

当前基础：status/stage/commit/text diff原型。上游：[extensions/git](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/extensions/git)，[extensions/git-base](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/extensions/git-base)，[extensions/github](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/extensions/github)，[src/vs/workbench/contrib/scm](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/scm)；[官方行为文档](https://github.com/microsoft/vscode-docs/blob/da213552439825628e0ab958dbde1e413dbc36bf/docs/sourcecontrol/overview.md)。

| ID / case前缀 | 功能 | 必须验收的结果 |
|---|---|---|
| GIT-01 / parity-git-01 | 工具探测与仓库发现 | Git缺失/版本/多仓/子模块/嵌套/多根识别、选择与刷新正确 |
| GIT-02 / parity-git-02 | SCM视图与装饰 | 工作区/暂存/未跟踪/冲突分组、徽章/树列表/排序/空态一致 |
| GIT-03 / parity-git-03 | 文件和块暂存 | stage/unstage文件、选区/hunk/行、rename/二进制及恢复状态正确 |
| GIT-04 / parity-git-04 | 丢弃和撤销 | discard/clean/undo last commit/amend确认及失败不丢数据 |
| GIT-05 / parity-git-05 | 提交编辑器 | message/验证/template/signoff/amend/签名/空提交/输入历史及SCM输入编辑器正确 |
| GIT-06 / parity-git-06 | diff与Quick Diff | index/worktree/HEAD比较、gutter块/下一修改/revert/stage，dirty同步 |
| GIT-07 / parity-git-07 | 提交历史图 | SCM Graph/分支标签/过滤/分页/点击commit/Multi Diff按固定默认功能对照 |
| GIT-08 / parity-git-08 | Blame与Timeline | 行/编辑器/状态hover、commit细节/复制/历史版本/Timeline正确 |
| GIT-09 / parity-git-09 | 分支和tag | create/checkout/rename/delete/publish/tag、脏工作树切换与错误反馈 |
| GIT-10 / parity-git-10 | merge与rebase | 固定注册和默认可达的merge/rebase/cherry-pick/continue/abort等动作及冲突状态正确，不扩成全部Git CLI |
| GIT-11 / parity-git-11 | stash | save/apply/pop/drop/查看与未跟踪处理、失败保留状态 |
| GIT-12 / parity-git-12 | worktrees | create/open/remove/迁移与分支关联、窗口/工作区关系正确 |
| GIT-13 / parity-git-13 | remotes和同步 | 按实际默认动作验add/remove remote、fetch/pull/push/sync/rebase/autofetch；不凭底层API假定rename菜单 |
| GIT-14 / parity-git-14 | 认证与credential交互 | 终端/askpass/SSH/HTTPS/凭据失败不阻塞UI，secrets不写日志 |
| GIT-15 / parity-git-15 | 冲突编辑器 | 文本冲突标记/accept current-incoming-both/比较/三方merge/完成状态一致 |
| GIT-16 / parity-git-16 | clone与init | 本地/URL clone、进度/取消、打开新窗/添加工作区/错误正确 |
| GIT-17 / parity-git-17 | ignore与文件操作联动 | gitignore编辑、rename/move/delete对index和dirty一致 |
| GIT-18 / parity-git-18 | 子模块与大量更改 | 子模块打开/更新/差异、大仓阈值提示与继续可达 |
| GIT-19 / parity-git-19 | GitHub内置基础集成 | clone选择/远程链接/发布仓库/认证纳入条件验收，PR业务另排 |
| GIT-20 / parity-git-20 | 故障与取消 | 锁文件/冲突/超时/网络断线/子进程强杀可恢复，危险动作有相同确认 |

## TER · 集成终端（P10，A/B/C）

当前基础：未有完整PTY终端。上游：[src/vs/workbench/contrib/terminal](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/terminal)，[src/vs/workbench/contrib/terminalContrib](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/terminalContrib)，[extensions/terminal-suggest](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/extensions/terminal-suggest)；[官方行为文档](https://github.com/microsoft/vscode-docs/blob/da213552439825628e0ab958dbde1e413dbc36bf/docs/terminal/basics.md)。

| ID / case前缀 | 功能 | 必须验收的结果 |
|---|---|---|
| TER-01 / parity-ter-01 | 跨平台PTY | Windows ConPTY/Unix PTY，窗口resize/编码/退出码和信号正确 |
| TER-02 / parity-ter-02 | VT终端状态 | ANSI/CSI/OSC/SGR/alternate screen/光标/真彩/应用键盘常用套件对拍 |
| TER-03 / parity-ter-03 | Unicode和输入法 | CJK/Emoji/组合字符/宽度/IME/AltGr/粘贴/死键无乱码 |
| TER-04 / parity-ter-04 | 终端创建关闭 | new/kill/relaunch/rename/icon/color/active状态与确认一致 |
| TER-05 / parity-ter-05 | tabs与split组 | 拖放/排序/多选/均分/切组/焦点/关闭组正确 |
| TER-06 / parity-ter-06 | 终端作为编辑器 | 面板-编辑器移动/side group/浮窗/restore与布局一致 |
| TER-07 / parity-ter-07 | profiles和默认shell | 检测/指定shell/args/env/cwd/icon/color/OS override正确 |
| TER-08 / parity-ter-08 | 环境变量与工作区 | env inheritance/变量解析/多根cwd/信任/relaunch提示正确 |
| TER-09 / parity-ter-09 | 渲染与外观 | 字体/连字/行高/contrast/cursor/GPU选项对应等价可用行为 |
| TER-10 / parity-ter-10 | scrollback和查找 | 有界滚动历史/clear/find regex-case-word/highlight/navigation正确 |
| TER-11 / parity-ter-11 | 选择复制粘贴 | word/line/column/多行安全粘贴提示/右键/复制选择与OS映射正确 |
| TER-12 / parity-ter-12 | 快捷键路由 | commandsToSkipShell/send key/chord/alt-click/tab focus与编辑器隔离 |
| TER-13 / parity-ter-13 | 链接检测与打开 | 文件行列/URL/port、hover/确认/选择provider和搜索回退正确 |
| TER-14 / parity-ter-14 | shell integration探测 | bash/zsh/fish/PowerShell启动脚本、状态/不支持回退正确 |
| TER-15 / parity-ter-15 | 命令导航与装饰 | 检测cwd/命令/完成退出码、mark/跳转/selection/hover与退出状态 |
| TER-16 / parity-ter-16 | 最近命令目录和Sticky Scroll | 历史picker/运行复制/当前命令区域/工作区scope正确 |
| TER-17 / parity-ter-17 | 终端建议 | 内置terminal-suggest命令/参数/路径/补全键位与非AI筛选正确 |
| TER-18 / parity-ter-18 | 持久化和恢复 | reload/reconnect/重启revive、输出恢复与不可能恢复的进程区别可见 |
| TER-19 / parity-ter-19 | 任务调试终端 | 复用/专用/共享终端、任务状态/输入/隐藏/结束一致 |
| TER-20 / parity-ter-20 | 音频与无障碍 | bell/signals/accessible buffer/读命令/选择与链接正确 |
| TER-21 / parity-ter-21 | 流控与子进程树 | 大量输出背压/限额/取消/孤儿回收，关闭工作区无遗留 |
| TER-22 / parity-ter-22 | 外部终端入口 | open external terminal与平台设置、路径/环境正确 |
| TER-23 / parity-ter-23 | 传统Terminal Quick Fix | 端口占用kill-rerun/Git上游与拼写/链接/PowerShell反馈等实际非AI修复菜单和执行结果正确 |
| TER-24 / parity-ter-24 | 终端图像协议 | enableImages默认off；开启时Sixel/iTerm图像按平台能力对拍；明确上游不恢复图像历史、不支持动画GIF的边界 |
| TER-25 / parity-ter-25 | 发送控制与自动回复 | sendSequence/sendSignal、restricted autoReplies默认空且节流、命令guide等实际设置动作正确，信任限制不被绕过 |

## TSK · 任务系统（P11，A/B/C）

当前基础：未实现。上游：[src/vs/workbench/contrib/tasks](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/tasks)，[extensions/npm](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/extensions/npm)，[extensions/gulp](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/extensions/gulp)，[extensions/grunt](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/extensions/grunt)，[extensions/jake](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/extensions/jake)；[官方行为文档](https://github.com/microsoft/vscode-docs/blob/da213552439825628e0ab958dbde1e413dbc36bf/docs/debugtest/tasks.md)。

| ID / case前缀 | 功能 | 必须验收的结果 |
|---|---|---|
| TSK-01 / parity-tsk-01 | tasks.json配置 | schema/JSONC/版本/type/shell-process/OS覆盖与错误定位正确 |
| TSK-02 / parity-tsk-02 | 任务发现与picker | workspace/user/multi-root任务、自动检测/分组/最近/默认构建测试任务正确 |
| TSK-03 / parity-tsk-03 | 内置工具任务 | npm/Gulp/Grunt/Jake及tsconfig build-watch发现运行；$tsc/$tsc-watch/$tsgo-watch等实际matchers，缺工具反馈一致 |
| TSK-04 / parity-tsk-04 | 变量解析 | workspace/file/env/config/input/command及递归/失败/多根消歧正确 |
| TSK-05 / parity-tsk-05 | 输入和依赖图 | promptString/pickString/command、dependsOn/顺序并行/循环错误正确 |
| TSK-06 / parity-tsk-06 | 运行配置 | cwd/env/quoting/shell executable/args/Windows转义正确 |
| TSK-07 / parity-tsk-07 | presentation和terminal复用 | reveal/focus/echo/panel/group/clear/close等配置正确 |
| TSK-08 / parity-tsk-08 | problem matchers | 单多行/background/begin-end/文件解析/owner/severity与Problems一致 |
| TSK-09 / parity-tsk-09 | 后台和自动任务 | watch task/readiness/runOn folderOpen/信任确认与取消正确 |
| TSK-10 / parity-tsk-10 | 任务生命周期 | 运行中列表/restart/rerun/terminate/退出码/部分失败和进程树清理 |
| TSK-11 / parity-tsk-11 | 任务与调试联动 | preLaunch/postDebug/失败继续确认及依赖等待无死锁 |
| TSK-12 / parity-tsk-12 | 任务配置编辑体验 | 自动生成/定制/default task/最近命令及无任务空态正确 |

## DBG · 默认调试与Testing容器（P11，A/B/C）

当前基础：未实现。上游：[src/vs/workbench/contrib/debug](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/debug)，[src/vs/workbench/contrib/testing](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/testing)，[extensions/debug-auto-launch](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/extensions/debug-auto-launch)，[extensions/debug-server-ready](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/extensions/debug-server-ready)，[product.json](https://github.com/microsoft/vscode/blob/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/product.json)；[官方行为文档](https://github.com/microsoft/vscode-docs/blob/da213552439825628e0ab958dbde1e413dbc36bf/docs/debugtest/debugging.md)。

| ID / case前缀 | 功能 | 必须验收的结果 |
|---|---|---|
| DBG-01 / parity-dbg-01 | launch.json与调试配置 | schema/变量/OS覆盖/compound/多根/动态配置与无配置入口正确 |
| DBG-02 / parity-dbg-02 | DAP协议生命周期 | initialize/launch-attach/configurationDone/断连/取消/失序/adapter崩溃正确 |
| DBG-03 / parity-dbg-03 | 断点 | 源码/inline column/条件/hit count/logpoint/triggered/function/data/exception按adapter能力，启停和验证态正确 |
| DBG-04 / parity-dbg-04 | 执行控制 | continue/pause/step in-over-out/restart/stop/run-to-cursor/set-next按能力工作 |
| DBG-05 / parity-dbg-05 | 调用栈与线程 | 多线程/异步栈/加载源/模块/选择frame、未知源按需加载正确 |
| DBG-06 / parity-dbg-06 | 变量与Watch | 懒展开/分页/set value/evaluate/作用域/内存对象、错误与过期状态正确 |
| DBG-07 / parity-dbg-07 | Debug Console | REPL/补全/历史/过滤/复制/多session、对象树和输出链路正确 |
| DBG-08 / parity-dbg-08 | 调试UI | toolbar位置、gutter/current line/hover/status/选择session、键位焦点正确 |
| DBG-09 / parity-dbg-09 | 多会话和复合调试 | 父子/多根/compound stopAll、console切换和终端回收正确 |
| DBG-10 / parity-dbg-10 | 源码映射与定位 | source maps/loaded scripts/skip files/blackbox/远程路径等默认JS能力 |
| DBG-11 / parity-dbg-11 | Node默认调试 | launch/attach/process picker/auto attach/JavaScript Debug Terminal实际可用 |
| DBG-12 / parity-dbg-12 | 浏览器默认调试 | P11验外部Chrome/Edge launch-attach/CDP及真实断点；集成浏览器联调在P12验收，按交叉case登记 |
| DBG-13 / parity-dbg-13 | serverReady与自动启动 | 输出匹配后openExternally/debugWithChrome等固定action与任务联动 |
| DBG-14 / parity-dbg-14 | 性能分析与可视化 | JS profiling与预置profile-table/companion动作有真实数据和查看器 |
| DBG-15 / parity-dbg-15 | 能力可用性边界 | 不支持memory/disassembly等显示正确条件/空态，支持时按DAP能力验收 |
| DBG-16 / parity-dbg-16 | Testing通用容器 | view/filter/group/tag/profiles/run-debug/结果历史/peek/output无provider正确空态 |
| DBG-17 / parity-dbg-17 | Testing覆盖率与持续运行 | 内部协议fixture验证UI/行分支装饰/取消，不冒称默认pytest-Jest可用 |
| DBG-18 / parity-dbg-18 | 调试与测试故障 | adapter/程序退出/端口占用/权限/超时保持编辑可用并回收资源 |
| DBG-19 / parity-dbg-19 | Comments通用宿主 | thread/range/reply/collapse/resolve/权限和焦点用内部provider fixture验UI合同；默认无provider保持真实空态 |

## NBK · Notebook与随附输出渲染（P12，A/B）

当前基础：未实现；不含Jupyter业务扩展。上游：[src/vs/workbench/contrib/notebook](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/notebook)，[extensions/ipynb](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/extensions/ipynb)，[extensions/notebook-renderers](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/extensions/notebook-renderers)；[官方行为文档](https://github.com/microsoft/vscode-docs/blob/da213552439825628e0ab958dbde1e413dbc36bf/docs/datascience/jupyter-notebooks.md)。

| ID / case前缀 | 功能 | 必须验收的结果 |
|---|---|---|
| NBK-01 / parity-nbk-01 | ipynb解析与序列化 | 未知metadata/attachments/output/indent/cell id roundtrip不丢失 |
| NBK-02 / parity-nbk-02 | Notebook虚拟化 | 大单元/多单元/大输出按需渲染，内容与选区不被缓存淘汰丢失 |
| NBK-03 / parity-nbk-03 | cell编辑和命令模式 | code/markdown切换、键位/焦点/multi-select/折叠正确 |
| NBK-04 / parity-nbk-04 | cell操作 | insert/delete/move/copy/cut/paste/split/join/undo跨cell事务正确 |
| NBK-05 / parity-nbk-05 | cell语言与代码能力 | cell URI/版本/补全/诊断/折叠与实际默认provider能力一致 |
| NBK-06 / parity-nbk-06 | Markdown cell | 预览/编辑/数学/Mermaid/附件链接、安全与键盘路径正确 |
| NBK-07 / parity-nbk-07 | Notebook导航 | Outline/sticky scroll/行号/标题折叠/定位/选择与滚动正确 |
| NBK-08 / parity-nbk-08 | Notebook查找 | input/rendered/output过滤、多行/regex/替换与cell位置正确 |
| NBK-09 / parity-nbk-09 | Notebook差异 | cell增删改移动/output/metadata差异显示及导航正确 |
| NBK-10 / parity-nbk-10 | kernel选择空态 | 无provider清晰提示，不伪造执行；安装外部Jupyter执行不计默认能力 |
| NBK-11 / parity-nbk-11 | renderer MIME集合 | 内置text/stream/error/json/HTML/JS/image/SVG/Markdown/math逐项对拍 |
| NBK-12 / parity-nbk-12 | 输出交互 | collapse/scroll/copy/save/clear/open、错误/截断/延迟加载可达 |
| NBK-13 / parity-nbk-13 | 输出安全隔离 | HTML/JS/CSP/信任/资源根限制，不能访问任意本地文件与宿主 |
| NBK-14 / parity-nbk-14 | 保存与崩溃恢复 | cell编辑/附件/metadata/输出dirty及journal恢复一致 |
| NBK-15 / parity-nbk-15 | Interactive与REPL Notebook宿主 | 通用输入/输出/历史/执行状态在默认provider存在时验真实能力，无provider空态；不额外捆绑Jupyter扩展 |

## MDK · Markdown与媒体编辑器（P12，B）

当前基础：未实现。上游：[extensions/markdown-language-features](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/extensions/markdown-language-features)，[extensions/markdown-math](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/extensions/markdown-math)，[extensions/mermaid-markdown-features](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/extensions/mermaid-markdown-features)，[src/vs/workbench/contrib/mediaPreview](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/mediaPreview)；[官方行为文档](https://github.com/microsoft/vscode-docs/blob/da213552439825628e0ab958dbde1e413dbc36bf/docs/languages/markdown.md)。

| ID / case前缀 | 功能 | 必须验收的结果 |
|---|---|---|
| MDK-01 / parity-mdk-01 | Markdown源与预览 | CommonMark/GFM实际配置、标题/Outline导航、表格/代码fence/图片链接显示一致，不假定额外TOC生成器 |
| MDK-02 / parity-mdk-02 | 预览同步 | side-by-side/locked preview/source scroll与选区同步、点击回源正确 |
| MDK-03 / parity-mdk-03 | 预览配置和安全 | styles/font/换行/link/trust/CSP/本地资源与远程限制一致 |
| MDK-04 / parity-mdk-04 | 数学与Mermaid | KaTeX行内块、Mermaid图pan/zoom/resize/reset/open source/copy source等实际命令正确；不臆造导出 |
| MDK-05 / parity-mdk-05 | Markdown富文本编辑 | 实验标识/开启条件保留，source-rich切换/选区/内容roundtrip与undo无损 |
| MDK-06 / parity-mdk-06 | Markdown差异预览 | source/rendered diff与自定义editor、链接/布局/保存行为正确 |
| MDK-07 / parity-mdk-07 | 链接更新与拖贴 | rename时update links、paste-drop图片/URL/文件、路径选择可撤销 |
| MDK-08 / parity-mdk-08 | Markdown任务列表与大文件 | 列表编辑/粘贴/格式/预览限额、长文导航与后台取消 |
| MDK-09 / parity-mdk-09 | 图片与SVG预览 | 缩放/适配/尺寸/背景/复制/选择/源-预览切换与失败状态正确 |
| MDK-10 / parity-mdk-10 | 音频视频预览 | 支持格式播放/暂停/seek/音量/错误/平台codec差异登记 |
| MDK-11 / parity-mdk-11 | 二进制和自定义编辑器 | 默认打开策略/重开为文本/readonly/保存合同，普通宿主可用 |
| MDK-12 / parity-mdk-12 | 预览生命周期 | 关闭释放renderer；隐藏按retain-context设置/预算回收并恢复交互状态，未打开时无web常驻 |

## WEB · Simple Browser与集成浏览器（P12，A/B/C）

当前基础：未实现；需跨平台引擎实验。上游：[extensions/simple-browser](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/extensions/simple-browser)，[src/vs/workbench/contrib/browserView](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/browserView)；[官方行为文档](https://github.com/microsoft/vscode-docs/blob/da213552439825628e0ab958dbde1e413dbc36bf/docs/debugtest/integrated-browser.md)。

| ID / case前缀 | 功能 | 必须验收的结果 |
|---|---|---|
| WEB-01 / parity-web-01 | Simple Browser | URL/前后/刷新/外部打开/focus lock提示/iframe限制与参考一致 |
| WEB-02 / parity-web-02 | 集成浏览器导航 | 地址输入/建议/搜索/前后/刷新/停止/协议错误状态正确 |
| WEB-03 / parity-web-03 | 本地HTML和MHTML | file/HTML-HTM/MHT-MHTML打开、资源根/权限与保存来源正确 |
| WEB-04 / parity-web-04 | browser tabs和独立窗 | tab管理/编辑器组/新窗/浮窗/关闭重开与键盘路径一致 |
| WEB-05 / parity-web-05 | 历史收藏最近项 | 默认容量/可配置历史/搜索/收藏/删除/清空及隐私scope正确 |
| WEB-06 / parity-web-06 | 页面查找缩放 | find/next-prev/page zoom/重置/设置、快捷键focus路由正确 |
| WEB-07 / parity-web-07 | DevTools与调试 | 真实DevTools/CDP与editor-browser DAP桥接，不能用静态面板替代 |
| WEB-08 / parity-web-08 | 网站权限 | camera/mic/clipboard/location等实际权限提示/记忆/撤销与系统权限协调 |
| WEB-09 / parity-web-09 | 会话和存储 | global/workspace/ephemeral cookies-cache-history隔离，clear storage正确 |
| WEB-10 / parity-web-10 | 拼写和页面输入 | 字典/输入法/表单/选择复制/页面快捷键与浏览器焦点正确 |
| WEB-11 / parity-web-11 | localhost链接接管 | 终端/任务serverReady/浏览器打开策略、选择和外部打开正确 |
| WEB-12 / parity-web-12 | 下载与外链策略 | 参考支持的下载/新窗/外部URI及失败/确认逐项验收 |
| WEB-13 / parity-web-13 | 网络代理与证书 | 代理/localhost/HTTPS错误、远程代理仅连接provider存在时正确 |
| WEB-14 / parity-web-14 | 浏览器资源与安全 | 多页CPU/内存/GPU/关闭回收、页面与工作区/宿主权限隔离 |

## NET · 账户、同步与非AI服务（P13，D）

当前基础：未实现；官方互通有外部前提。上游：[src/vs/workbench/contrib/authentication](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/authentication)，[src/vs/workbench/contrib/userDataSync](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/userDataSync)，[src/vs/workbench/contrib/editSessions](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/editSessions)，[extensions/github-authentication](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/extensions/github-authentication)，[extensions/microsoft-authentication](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/extensions/microsoft-authentication)，[extensions/tunnel-forwarding](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/extensions/tunnel-forwarding)；[官方行为文档](https://github.com/microsoft/vscode-docs/blob/da213552439825628e0ab958dbde1e413dbc36bf/docs/configure/settings-sync.md)。

| ID / case前缀 | 功能 | 必须验收的结果 |
|---|---|---|
| NET-01 / parity-net-01 | 账户和认证会话 | GitHub/Microsoft登录登出/授权scope/多账户/取消/过期/权限面板完整 |
| NET-02 / parity-net-02 | secrets与加密存储 | OS credential store/密钥轮换/加密失败，token不入设置或日志 |
| NET-03 / parity-net-03 | Settings Sync选择 | settings/keys/snippets/tasks/UI/profiles与Extensions IDs/启用状态按开关同步，ignoredSettings/ignoredExtensions正确 |
| NET-04 / parity-net-04 | 同步冲突和恢复 | merge/接受local-remote/历史备份/机器列表/关闭删除/故障日志正确 |
| NET-05 / parity-net-05 | 跨平台同步 | 平台差异与machine-scoped项处理正确，离线编辑重连不丢配置 |
| NET-06 / parity-net-06 | Cloud Changes | Store/Show/Resume Working Changes/Show Log/Serialized Data/Continue Working On和Existing Local Folder、身份/冲突/取消真实可用 |
| NET-07 / parity-net-07 | GitHub基础服务 | clone仓库选择/发布/远程链接/权限/失败回滚；PR-Issues业务不冒称内置 |
| NET-08 / parity-net-08 | Ports视图 | add/remove/name/local-forwarded地址/open/copy/status/进程检测等实际支持项正确 |
| NET-09 / parity-net-09 | 公网隧道 | public/private/GitHub认证/复用/停止/网络失败/端口冲突与服务生命周期正确 |
| NET-10 / parity-net-10 | Remote Tunnel内置入口 | 固定发行构建具备的serve/connect/share入口、状态/凭据/退出有证据 |
| NET-11 / parity-net-11 | 扩展管理界面 | 内置/installed/recommended/search/详情/enable-disable/profile作用域与错误状态完整 |
| NET-12 / parity-net-12 | 扩展包生命周期 | 来源/下载校验/依赖/安装更新卸载/回滚管理可用；第三方激活不假成功 |
| NET-13 / parity-net-13 | 联网与证书代理 | HTTP proxy/系统证书/离线/计量连接/重试/取消与设置正确 |
| NET-14 / parity-net-14 | 后端互通与替代账本 | 官方端点/client注册/预置包可用性实测；自建兼容不冒称官方1:1 |

## ACC · 可访问性、系统与可观测性（P14，A）

当前基础：部分平台框架与mem-probe可复用。上游：[src/vs/workbench/contrib/accessibility](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/accessibility)，[src/vs/workbench/contrib/accessibilitySignals](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/accessibilitySignals)，[src/vs/workbench/contrib/processExplorer](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/processExplorer)，[src/vs/workbench/contrib/logs](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/logs)；[官方行为文档](https://github.com/microsoft/vscode-docs/blob/da213552439825628e0ab958dbde1e413dbc36bf/docs/configure/accessibility/accessibility.md)。

| ID / case前缀 | 功能 | 必须验收的结果 |
|---|---|---|
| ACC-01 / parity-acc-01 | Screen Reader全流程 | 编辑/树/菜单/quick input/终端/Notebook/browser/设置以semantics tree+NVDA/VoiceOver/Orca实机验证焦点读出 |
| ACC-02 / parity-acc-02 | Accessible View和Help | hover/通知/输出/终端等可访问视图、导航/帮助和返回焦点正确 |
| ACC-03 / parity-acc-03 | 键盘全可达 | Tab focus mode/菜单/状态栏/面板/浮窗/对话框focus trap无死角 |
| ACC-04 / parity-acc-04 | 高对比减少动画和信号 | contrast/zoom/reduced motion/audio cues/announcement设置与OS联动 |
| ACC-05 / parity-acc-05 | 系统窗口与多显示器 | DPI跨屏/最小最大/全屏/恢复尺寸/原生菜单按三平台正确 |
| ACC-06 / parity-acc-06 | CLI和文件关联 | open/add/goto/diff/merge/wait/reuse-new-window/profile/user-data等固定非AI选项映射 |
| ACC-07 / parity-acc-07 | 外部URI与系统集成 | 协议注册/open path-URL/剪贴板/OS reveal/系统对话框路径正确 |
| ACC-08 / parity-acc-08 | 信任和安全全链路 | restricted mode/可信域/任务执行/预览/secret/网络边界一致 |
| ACC-09 / parity-acc-09 | Output与日志 | channel选择/levels/filter/clear/save/scroll lock/限额及服务关联正确 |
| ACC-10 / parity-acc-10 | 进程资源与性能工具 | 进程树CPU/内存、日志/启动诊断/性能视图有真实数据与可停订阅 |
| ACC-11 / parity-acc-11 | Help和Issue Reporter | 版本/许可/快捷键参考/问题报告/诊断包，敏感数据处理和取消正确 |
| ACC-12 / parity-acc-12 | 语言和策略 | 默认English/locale切换与外部language pack边界、policy导出/受管状态正确 |
| ACC-13 / parity-acc-13 | 开发者检查与故障诊断命令 | Screencast/Inspect Context Keys/键位排查/日志/运行内置能力与禁用-bisect等默认可达命令逐项映射，不依赖第三方业务扩展 |
| ACC-14 / parity-acc-14 | 遥测反馈与实验控制 | telemetry等级/退出/crash配置/调查反馈/非AI公告及受管策略遵循设置；数据发送内容和端点单独登记 |
| ACC-15 / parity-acc-15 | 辅助语音provider边界 | 普通辅助朗读/声音信号保留；依赖额外Speech扩展或仅Agent的语音单列E/F，无provider不假称默认语音服务 |

## REL · 资源压力、分发与总验收（P15，A）

当前基础：已有CI/Windows打包；完整证据未达。上游：[src/vs/workbench/contrib/update](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/update)，[src/vs/workbench/contrib/performance](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/contrib/performance)，[src/vs/workbench/services/lifecycle](https://github.com/microsoft/vscode/tree/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/workbench/services/lifecycle)；[官方行为文档](https://github.com/microsoft/vscode-docs/blob/da213552439825628e0ab958dbde1e413dbc36bf/docs/setup/windows.md)。

| ID / case前缀 | 功能 | 必须验收的结果 |
|---|---|---|
| REL-01 / parity-rel-01 | 三平台安装包 | Windows安装便携/Linux/macOS包可启动、包含默认离线资产并有完整notice |
| REL-02 / parity-rel-02 | 更新回滚与卸载 | 检查/下载/安装/重启/失败回滚/卸载保留用户数据行为明确可测 |
| REL-03 / parity-rel-03 | 完整性注册项核对 | 范围内原子贡献每项映射case/evidence；未映射/未消化不为零不能宣告完成 |
| REL-04 / parity-rel-04 | 全视觉回归 | 所有核心页/状态/主题/缩放/平台保存golden与diff，掩膜逐项有依据 |
| REL-05 / parity-rel-05 | 行为结果对拍 | 正常/边界/失败序列的文本/选区/磁盘/配置/焦点/进程状态一致 |
| REL-06 / parity-rel-06 | 相同功能内存对照 | 包含所有实际子进程，同项目同服务至少3次，不拿空UI比带语言VSCode |
| REL-07 / parity-rel-07 | 空闲与30min稳定性 | 无轮询空转、内存持续增长；长时间编辑/切根/关闭回收有曲线 |
| REL-08 / parity-rel-08 | 限额与系统提交压力 | Warn/Critical输入保存可用、可重建缓存降级、最低可工作档位报告 |
| REL-09 / parity-rel-09 | 保存恢复故障注入 | 磁盘满/权限/强杀/坏journal/超大未保存文本无静默丢失 |
| REL-10 / parity-rel-10 | 服务与网络故障 | 强杀LSP/DAP/PTY/web/隧道、慢请求/断线/认证失效编辑仍可用 |
| REL-11 / parity-rel-11 | 预算与容量可见 | undo/token/index/search/history/scrollback/output/web缓存有owner/上限/回收证据 |
| REL-12 / parity-rel-12 | 发布差异清单 | 未解决功能/外部服务/实验和平台差异逐项公开，硬门未过保持未完成 |

## 边界与不纳入的业务provider

外部非AI服务属于D，不能误记为排除。实验功能有明确设置入口/产品可达性时条件纳入；P00用运行参考确认。以下决策保留具体原因，不能按目录一刀切。

| ID | 条目 | 分类 | 决策 |
|---|---|---|---|
| EX-01 | 外接AI | F | Chat/Inline Chat/Copilot/Agents/AI completions/AI search/MCP代理等按依赖逐项排除；普通编辑共享组件保留 |
| EX-02 | Canvas与Agent专用界面 | F | 当前Canvas菜单受ChatContextKeys.enabled控制；不当作普通非AI画布；将来若独立默认能力需重审 |
| EX-03 | Python/C++/Rust等完整业务provider | E | 默认语法/snippets纳入LNG；需用户安装的LSP/调试/测试能力不归入默认复刻，现有RA另记附加能力 |
| EX-04 | Jupyter执行与kernel | E | 保留NBK宿主/ipynb/renderer；额外Jupyter/Python provider的执行/变量浏览不冒称默认可用 |
| EX-05 | 测试框架provider | E | pytest/JUnit/Jest等需要用户扩展；保留Testing UI与协议空态，测试fixture仅用于验证宿主 |
| EX-06 | Remote SSH/WSL/Containers/Codespaces业务扩展 | E | 默认未随附的连接provider排除；内置远程指示/Ports/Tunnel实际能力仍在NET |
| EX-07 | GitHub PR-Issues与Remote Repositories业务 | E | GitHub基础认证/clone/publish纳入；用户扩展PR/Issues/remotehub能力不自动纳入 |
| EX-08 | 任意第三方vscode API兼容 | E | 通用扩展运行时不是本次产品目标；扩展管理自身功能纳入NET，受支持状态必须诚实 |
| EX-09 | 额外主题语法语言包 | E | 默认包全部纳入；用户导入数据格式兼容按THM/LNG测试，不要求所有外部包业务可用 |
| EX-10 | 源码测试与构建辅助 | G | vscode-api-tests/colorize-tests/test-resolver/types等不是默认用户功能；可复用测试数据不算产品需求 |
| EX-11 | 实验和默认关闭功能 | G | 先登记flag/平台/可达性，不直接删除；范围内有设置入口的非AI能力仍需条件case |
| EX-12 | 官方服务和预置包不可用 | D | 不属于排除：保持NET/P00阻塞项，替代实现与官方互通分别签收 |
| EX-13 | 系统依赖缺失 | C | 不属于排除：Git/运行时/shell缺失要有相同前提检测，具备条件时验收真实能力 |
| EX-14 | 品牌名称和标识 | G | Alula自有名称与图标单列可见差异；不据此削减功能/布局/交互验收 |

## 从功能族到逐项1:1证据

P00贡献项导出必须补充：upstream_id、来源文件/行、默认值/when/平台条件、所属功能族、本地实现入口、子case、截图/状态/进程证据和差异或阻塞。未映射不能算覆盖；目录发现完整不等于语义审核完整。[目录快照](plans/vscode-source-inventory.json)、[内置manifest摘要](plans/vscode-builtin-manifests.json)。

安装和分发另参考：[linux](https://github.com/microsoft/vscode-docs/blob/da213552439825628e0ab958dbde1e413dbc36bf/docs/setup/linux.md)、[mac](https://github.com/microsoft/vscode-docs/blob/da213552439825628e0ab958dbde1e413dbc36bf/docs/setup/mac.md)、[portable](https://github.com/microsoft/vscode-docs/blob/da213552439825628e0ab958dbde1e413dbc36bf/docs/setup/portable.md)、[uninstall](https://github.com/microsoft/vscode-docs/blob/da213552439825628e0ab958dbde1e413dbc36bf/docs/setup/uninstall.md)。
