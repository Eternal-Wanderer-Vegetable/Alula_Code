# progress.md — 项目进度跟踪

> agent 会话状态文件：每完成一项工作就追加记录。任务权威分解在 `docs/03`，
> 功能状态机在 `feature_list.json`，本文件记录「何时、做了什么、证据是什么」。

## Current State（当前状态，2026-10-26）

**Phase 0 技术验证已关闭（决策门 G1 已过）：固定原型 B 自研路线**
（Flutter 工作台 + Rust 核心 + Tree-sitter + LSP + 可选 Node 宿主）。
**Phase 1 增量 1 完成**：多文件工作台闭环 + rust-analyzer 按工作区共享接入。

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

## Next（下一步，按优先级）

1. **feat-010 下一增量**：撤销/重做 UI 化、查找替换、Git 面板（status/stage/commit）、文件监视。
2. **feat-002 人工复核**：code_forge 真机 IME + 万行文件流畅度 → 通过后执行编辑器组件切换。
3. **feat-013 收尾**：推送 GitHub 后验证 CI 全绿；GitNexus 在 commit 后按 hook 提示重建索引。
4. 诊断/补全异步化（替换现轮询+阻塞 FFI）——为跳转定义/悬浮做准备。
