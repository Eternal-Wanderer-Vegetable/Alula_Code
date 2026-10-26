# Alula Code 工程实施方案

> 一个以「低内存 + 内存压力下稳定」为第一目标的跨平台代码编辑器：
> **Flutter 原生工作台 + Rust 编辑核心 + 按需语言服务 + 可选 VS Code 扩展宿主**。
>
> 项目名 **Alula Code**；本仓库（`E:\Alula_Code`）根目录即项目根，目录规划见
> [02-关键技术设计 §1](docs/02-关键技术设计.md)。

本方案由 2026-10 的一次技术调研讨论（ChatGPT 分享对话）收敛而来，将其结论转换为
可直接执行的工程计划：量化目标、定稿架构、接口契约、里程碑、验收标准、测试基准与风险清单。

## 要解决的问题

用户在本地运行大模型（显存+内存占用极大）时，VS Code 常驻内存约 1 GB，且在内存压力下
容易卡死甚至崩溃。现有编辑器（Zed/Lapce 不兼容 VS Code 插件；VSCodium/Theia 仍是
Electron 架构）没有一个同时满足「低内存、跨平台、主流 VS Code 插件生态可用」。

**结论：自研，但不是重写 VS Code** —— 从 VS Code、Helix 等成熟项目中提取经过验证的
设计，在更低资源开销的架构下重新组合。

## 需求定稿（来自讨论的最终约束）

| 约束项 | 定稿 |
|---|---|
| 插件需求范围 | 主流插件：Python、C/C++、Rust、Git、主题、代码补全（不追求全部插件） |
| 兼容策略 | 两级：**功能级兼容**（LSP 等价，第一优先）＋ **扩展级兼容**（选定 VSIX，逐步扩大） |
| 前端 | Flutter Desktop（原生渲染、不依赖系统 WebView；弃用 Tauri/Monaco 路线） |
| 核心 | Rust，独立于 GUI，可单独测试与复用 |
| 平台 | Windows / Linux / macOS；WSL 作为独立里程碑 |
| 第一优先级 | 内存开销与内存压力下的稳定性（可编辑、可保存、不卡死） |
| 扩展来源 | Open VSX / 合法取得的 VSIX（微软 Marketplace 发行包不授权非 VS 家族产品使用） |

## 量化设计目标（V1 验收基线，非承诺值）

| 场景 | 目标 |
|---|---|
| 空工作台（无 LSP、无扩展宿主） | 进程树私有内存 ≤ 200 MiB（挑战值） |
| 普通项目打开、未启动 LSP | ≤ 250 MiB（含文件树、编辑器、基础 Git） |
| Rust/Python 项目 + 对应 LSP | ≤ 500 MiB（受语言服务器规模影响） |
| 同项目同功能对比 VS Code | 总内存 −50%（主竞争性验收目标） |
| 无项目冷启动 | 主界面 2 秒内可交互 |
| 未使用扩展时 | 进程树中不存在 Node.js 进程 |
| 空闲 10 分钟 | CPU 占用 ≈ 0，无内存持续增长 |
| 关闭工作区 | 对应 LSP/子进程全部退出 |
| LSP/扩展宿主被强杀 | 编辑、保存、现有缓冲区不受影响，可自动恢复 |
| 内存受限（cgroup/Job 限额） | 输入、滚动、保存仍然可用（低资源模式生效） |

> 注：若最终稳定在 300–500 MiB（对比 VS Code 1 GB），即使未达极端轻量化，也已具备实用价值。
> 降 RAM 不等于等量增加可用显存，但可减少交换、释放 CPU 推理/模型卸载可用的系统内存。

## 当前进度（MVP · Phase 0 任务 0-1 已实现）

「编辑 → 增量同步 → Rust 应用 → 版本回执」闭环已完成并验证：

| 组件 | 状态 | 说明 |
|---|---|---|
| `crates/editor-buffer` | ✅ 已实现 | Ropey 缓冲区、增量 op、UTF-16↔char 换算（拒绝代理对中间偏移） |
| `crates/editor-core` | ✅ 已实现 | 文档注册表、版本校验协议、手写 C ABI（`alula_doc_open/apply/resync/close`） |
| Rust 测试 | ✅ 20/20 通过 | `cargo test`（含 CJK/emoji/CRLF 边界用例） |
| cdylib | ✅ 已构建 | `alula_core.dll` 429 KB；FFI 二进制经 ctypes 冒烟验证（同步/失配/非法偏移路径） |
| `app/`（Flutter） | ✅ 已安装 SDK 并验证 | Flutter 3.47.8 + VS2026；`flutter analyze` 零问题；`flutter test` 14/14（含加载真实 DLL 的集成测试）；`flutter build windows --release` 成功（主进程 WorkingSet 106.8 MiB，首个真实内存数据点） |
| GUI 视觉与交互验证 | ✅ 通过（2026-10-26 复验） | 界面渲染正确；模拟键入后状态栏显示「已同步 v10（1 op，33 µs）」，全链路闭环在真实 GUI 中确认（证据：[docs/diagnostics/2026-10-25-rendering/](docs/diagnostics/2026-10-25-rendering/诊断报告.md)；2026-10-25 曾出现一次系统级暂时性白屏，当日复验消失，诱因未定位，见 R12） |
| `tools/mem-probe` + 基线 | ✅ 首批数据（2026-10-26） | 进程树 Private Bytes 采集工具（5 测试全绿）+ bench.py 编排；**首批对比：alula 空工作台 179.2 MiB vs VS Code 干净实例 959.5 MiB（−81.3%，主验收线 −50% 已大幅越过）**，见 [docs/baselines/2026-10-26/](docs/baselines/2026-10-26/README.md) |
| 编辑组件评测（0-2） | ✅ 自动化部分（2026-10-26） | `tools/component-lab` 三候选同工程实测：**code_forge 13 分首选**（纯 Dart rope、内置 LSP、多光标）/ re_editor 10 分备选 / flutter_code_editor 否决（无虚拟化，100 行即溢出）；待真机 IME/流畅度人工复核，见 [docs/06-评测-编辑组件选型](docs/06-评测-编辑组件选型.md) |
| VS Code 卡死归因（0-7） | ✅ 完成（2026-10-26） | 事件日志取证：近 30 天 5 次系统提交内存耗尽（python.exe 模型进程 86–93 GB）；Code.exe 90 天 2 次崩溃为受害者；扩展排除（A/B：1257.5 vs 989.9 MiB）；报告 [docs/07](docs/07-诊断-VSCode卡死归因.md) |
| Tree-sitter + LSP 接入（0-3） | ✅ 完成（2026-10-26） | `crates/editor-lsp`（stdio JSON-RPC 客户端，对真实 rust-analyzer 全链路验证）+ `crates/editor-lang`（Tree-sitter 高亮 token）；UI 诊断/补全/语法三面板；实测：键入错误 → 诊断 7 条实时显示、补全 62 项、语法 40 token 着色，截图见 [docs/diagnostics/2026-10-26-lsp-demo/](docs/diagnostics/2026-10-26-lsp-demo/) |
| 原型 A 精简 Code-OSS（0-4） | ✅ 完成（2026-10-26） | dev 构建跑通；移除 86 个内置扩展仅省 −1.5%（1310→1290 MiB）——内存大头是工作台本体；**G1 判定：采用自研路线**，报告 [docs/08](docs/08-原型A-精简Code-OSS.md) |
| **Phase 1 增量 1** | ✅ 完成（2026-10-26） | 打开文件夹 → 懒加载文件树 → 多标签打开/编辑 → Ctrl+S 原子保存（editor-doc）；LSP 按工作区共享进程，诊断/补全/语法跟随多文件；Rust 38 + Dart 15 测试全绿 |

快速开始：

```powershell
# 构建核心动态库（Rust 已装即可）
.\scripts\build_core.ps1

# 直接运行已构建好的 Release 版（验证过可启动、DLL 已随包）
app\build\windows\x64\runner\Release\alula_app.exe

# 或从源码运行/测试（需要 E:\flutter，已加入本机）
cd app
flutter run -d windows
flutter test
```

## 文档索引

| 文档 | 内容 |
|---|---|
| [01-目标与总体架构](docs/01-目标与总体架构.md) | 目标分解、架构定稿、模块职责、8 条关键架构决策（ADR） |
| [02-关键技术设计](docs/02-关键技术设计.md) | 仓库结构、FFI 同步协议、位置换算、LSP 管理、进程监督、低资源模式、原子保存、扩展兼容层 |
| [03-里程碑计划与验收标准](docs/03-里程碑计划与验收标准.md) | Phase 0–3 任务分解、决策门 G1/G2、每阶段 DoD |
| [04-性能预算与测试基准](docs/04-性能预算与测试基准.md) | 内存测量口径、基准测试套件、测试矩阵、CI 策略 |
| [05-风险登记册与外部参考](docs/05-风险登记册与外部参考.md) | 风险清单与缓解、参考项目（已核实）、许可合规 |
| [06-评测-编辑组件选型](docs/06-评测-编辑组件选型.md) | Phase 0 任务 0-2：三候选评测卡（code_forge 13 分首选 / re_editor 10 分备选 / flutter_code_editor 否决） |
| [07-诊断-VSCode卡死归因](docs/07-诊断-VSCode卡死归因.md) | Phase 0 任务 0-7：根因为模型进程提交内存打满（python.exe 86–93 GB 击穿 107 GB 上限），VS Code 是受害者；含缓解建议 |
| [08-原型A-精简Code-OSS](docs/08-原型A-精简Code-OSS.md) | Phase 0 任务 0-4：减法实验——移除 86 个内置扩展仅省 1.5%，G1 判定采用自研路线 |

## 核心技术路线（定稿）

```
┌─────────────────────────────────────────────────────┐
│ Flutter Workbench（仅显示与交互层）                  │
│ 窗口 · 文件树 · 编辑视图 · 面板 · 命令面板 · 终端 UI │
│ 不承担后台索引与语言分析                             │
└───────────────┬─────────────────────────────────────┘
                │ flutter_rust_bridge（FFI）
                │ 增量文本操作 + 版本号 + 状态事件 + 可视范围
┌───────────────┴─────────────────────────────────────┐
│ Rust Editor Core（独立库，可脱离 GUI 测试）          │
│ ┌──────────┬──────────┬──────────┬───────────────┐  │
│ │ Text     │ Language │ Workspace│ Editor        │  │
│ │ Buffer   │ Core     │          │ Services      │  │
│ │ (Ropey)  │(Tree-    │ fs·搜索  │ 撤销·多光标   │  │
│ │          │ sitter+  │ ·Git CLI │ ·命令系统     │  │
│ │          │ LSP客户端)│          │               │  │
│ └──────────┴──────────┴──────────┴───────────────┘  │
└───────┬─────────────────────────┬───────────────────┘
        │ 按需启动/监督            │ 受控 IPC
┌───────┴──────────┐   ┌─────────┴───────────────────┐
│ 语言服务进程       │   │ 可选 Node.js 扩展宿主       │
│ rust-analyzer     │   │ VS Code API Bridge         │
│ clangd            │   │ （默认不启动，崩溃隔离）    │
│ basedpyright/Ruff │   └─────────────────────────────┘
└──────────────────┘
```

参考系：**VS Code = 用户体验与编辑行为参考；Helix = Rust 核心组织参考（helix-core：
Ropey + Transaction + 多选区 + Tree-sitter）；CodeForge/Re-Editor = Flutter 编辑组件
候选；DSCode/Theia = 扩展宿主参考；LVCE Benchmark = 内存测试方法学参考。**

## 立即开始：Phase 0（详见文档 03）

第一周即可并行启动的四件事：

1. **原型 B 骨架**：`flutter create` + flutter_rust_bridge + ropey，跑通「编辑→增量同步→Rust 侧确认」。
2. **组件评测**：CodeForge、Re-Editor、flutter_code_editor 三者按统一评测卡打分（1 万行文件、中文输入法、多光标、撤销）。
3. **基准框架**：搭建进程树内存采集脚本（Windows Private Bytes / Linux PSS），先测 VS Code 基线。
4. **并行动作**：对现有 VS Code 做对照诊断（`code --disable-extensions`、Extension Bisect、`code --disable-gpu`），确认卡死根因归类，为低资源模式设计提供输入。
