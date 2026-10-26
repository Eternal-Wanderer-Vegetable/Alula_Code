# 内存基线 · 2026-10-26

首批正式基线（Phase 0 任务 0-5 产出，对应 docs/04 §6「一次性基线采集」）。

## 对比结果

| 场景 | 进程数 | 峰值 MiB | 稳态 MiB | 结束 MiB |
|---|---|---|---|---|
| **alula-mvp-empty**（空工作台，无 LSP/扩展） | 1 | 180.2 | **179.2** | 179.2 |
| vscode-clean-rust-mini（首启，无扩展，打开 rust-mini） | 11 | 1468.9 | 971.6 | 1216.8 |
| vscode-clean-rust-mini-warm（同上，热启动） | 11 | 1511.8 | **959.5** | 959.5 |

**稳定态对比：alula MVP 比 VS Code 干净实例低 81.3%**（主验收线为 −50%，已大幅越过；
用户此前自述的「VS Code 常驻 ~1 GB」与本实测 959.5 MiB 吻合，交叉验证了测量口径）。

## 口径与方法

- 工具：`tools/mem-probe`（进程树 Private Bytes = `PROCESS_MEMORY_COUNTERS_EX::PrivateUsage`
  求和；禁止 RSS 累加），场景编排 `tools/bench/bench.py`；
- alula：`app/build/windows/x64/runner/Release/alula_app.exe`，45s 采样间隔 1s；
- VS Code：`Code.exe --user-data-dir=<全新> --extensions-dir=<全新> tests/fixtures/rust-mini`
  （隔离 profile = 无扩展状态，与 alula 无 LSP/扩展场景对齐），60s 采样间隔 1s；
- 机器：Windows 11 25H2，AMD 核显 + RTX 5080。

## 已知局限（后续补齐）

1. VS Code 首启含信任对话框/欢迎页/更新检查，但热启动数据（959.5）与首启（971.6）
   基本一致，结论稳健；
2. 尚缺「带语言服务」对照组：VS Code + rust-analyzer 扩展 vs alula + 原生
   rust-analyzer（docs/04 §3.1 场景矩阵的第二组，Phase 1 接入 LSP 后补测）；
3. 尚缺原型 A（精简 Code-OSS）对照（Phase 0 任务 0-4）；
4. 单机单次采样，换硬件/系统后需重采；长时间运行（30 分钟编辑）与关闭回收
   场景待 bench 矩阵补齐。


## 2026-10-26 追加：原型 A 对照（任务 0-4）

| 场景 | 进程数 | 峰值 MiB | 稳态 MiB |
|---|---|---|---|
| 原型 A（Code-OSS 1.144 dev）· 全量内置扩展 | 8 | 1518.1 | ≈1310 |
| 原型 A · 精简（移除 86 个内置扩展） | 8 | 1474.8 | ≈1290 |

alula 稳态 179.2 MiB 相对原型 A 精简版降低 **−86.1%**。dev 构建口径差异与结论详见
docs/08-原型A-精简Code-OSS.md。


## 2026-10-26 追加：W1 布局骨架复测（docs/09 W1 验收）

| 场景 | 进程数 | 峰值 MiB | 稳态 MiB | 结束 MiB |
|---|---|---|---|---|
| alula-mvp-empty（增量 1 工作台） | 1 | 180.2 | 179.2 | 179.2 |
| **alula-w1-empty**（W1：分割树网格+五大区+标题栏菜单+布局持久化+无边框窗口） | 1 | 197.1 | **186.6** | 186.6 |

- **稳态 +4.0%（+7.4 MiB）**：低于 docs/09 §4 的 5% 回归护栏，无需归因报告；
  归属明确 = 工作台外壳（WorkbenchGrid/五大区/菜单/持久化）。
- 满足 docs/03「空工作台 ≤ 200 MiB」验收线（稳态与峰值均在预算内）。
- 口径与首批基线一致：mem-probe watch 45s 间隔 1s，进程树 Private Bytes。
- 报告：`alula-w1-empty.md` / `.json`。
