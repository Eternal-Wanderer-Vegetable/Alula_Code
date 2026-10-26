# Alula Code — Agent 工作守则

低内存跨平台代码编辑器：**Flutter 桌面工作台（`app/`）+ Rust 编辑核心（`crates/`）**。
第一优先级是内存开销与内存压力下的稳定性（可编辑、可保存、不卡死）。
本文件只放路由与不变量；设计事实、验收标准与里程碑在 `docs/`，**`docs/03` 是任务
状态与 DoD 的唯一权威来源**，不要在本文件重复。

## 仓库地图

| 路径 | 内容 |
|---|---|
| `crates/` | Rust 工作区：editor-buffer（Ropey 缓冲）/ editor-core（FFI 入口）/ editor-lsp（LSP 客户端）/ editor-lang（tree-sitter 高亮）/ editor-workspace / editor-doc（原子保存） |
| `app/` | Flutter 原型 B：`lib/bridge/`（FFI 绑定与协议）、`lib/editor/`（diff）、`lib/main.dart`（工作台） |
| `scripts/build_core.{sh,ps1}` | 构建 Rust 动态库并拷贝到 `app/native/`；**跑 Flutter 前 / core_sync_test 前必须先执行** |
| `tools/` | mem-probe（进程树内存采集）、bench（基准脚本）、对照诊断脚本 |
| `docs/01–08` | 方案、架构、里程碑、内存预算、风险、评测、诊断报告 |
| `feature_list.json` / `progress.md` / `session-handoff.md` | agent 状态跟踪（harness） |

## Startup Workflow（会话启动）

每个会话开始时，按顺序：

1. 读 `session-handoff.md` 与 `progress.md` 的「Current State」恢复上下文；
2. `node .gitnexus/run.cjs status` 确认代码图谱新鲜度（stale 则 `analyze` 重建）；
3. `bash init.sh --fast` 确认基线全绿（不为绿就先修复，不带病开工）；
4. 从 `feature_list.json` 选一个 `in-progress` 或依赖已满足的 `not-started` 项开工。

## 硬性不变量

1. **UTF-16 口径**：FFI 协议中所有偏移/长度一律 UTF-16 code unit；Rust 侧换算为字节。
   改协议或 diff 逻辑必须带 Emoji（代理对）/CRLF/BOM 用例，`app/test/text_diff_test.dart`
   的随机对拍必须保持全绿。
2. **编辑核心无 GUI 依赖**：`crates/` 禁止依赖任何 GUI；新能力先在 crate 内实现并测试，
   再经 FFI 暴露。
3. **FFI ABI 是版本化契约**：改 ABI 必须双侧同步 + 版本握手 + 对拍用例，禁止单边修改。
4. **一致性校验失败是 bug**：本地文本与 Rust 权威全文逐字符比对不一致一律视为缺陷，
   不允许放宽容忍度。
5. **内存预算是设计约束**（docs/04）：避免无界缓存与常驻轮询；LSP/子进程按需启停、
   关闭工作区必须退出；新增常驻结构要在 mem-probe 基准里可见。

## 范围纪律（Scope）

- **One feature at a time**：同一时刻只推进 `feature_list.json` 中的一项功能；
  做完（含证据登记）再开下一项，不并行开挖。
- **Stay in scope**：发现相邻问题记录到 `progress.md`「下一步」，不顺手扩大改动范围；
  功能是否「做完」以下面 Definition of Done 为准，不以「看起来能跑」为准。

## Definition of Done（完成定义）— 提交前全部通过

```bash
cargo fmt --check                   # Rust 格式门
bash scripts/build_core.sh          # 或 PowerShell: .\scripts\build_core.ps1
cargo test --workspace              # Rust 全绿
cargo clippy --workspace --all-targets -- -D warnings   # 零警告
flutter analyze                     # Dart 静态检查零问题
flutter test                        # 在 app/ 下；SDK 通常在 E:\flutter\bin
bash init.sh                        # 一键跑完以上核心项（含 Flutter 自动探测）
```

- 改动影响内存/性能 → 用 `tools/mem-probe` 采集并对比 `docs/baselines/` 最新基线。
- 完成的功能在 `feature_list.json` 登记 evidence（命令输出/截图路径/文档链接），
  并更新 `progress.md`。

## End of Session（会话收尾）

收尾例程，保证下个会话 clean restart（restartable）：

1. 跑 `bash init.sh` 确认全绿；未完成的半成品退回 `not-started` 并注明阻塞点；
2. 更新 `feature_list.json`（status + evidence）与 `progress.md`（今日做了什么、证据）；
3. 重写 `session-handoff.md`：Last Updated、当前目标、Blockers、涉及文件、Next Session 首步；
4. commit 前按 GitNexus 规则做 graph change analysis（见下方 gitnexus 块）。

## GitNexus

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **Alula_Code** (796 symbols, 1681 relationships, 66 execution flows).

> Index stale? Run `node .gitnexus/run.cjs analyze --index-only` from the project root — it auto-selects an available runner. No `.gitnexus/run.cjs` yet? Bootstrap with `npx`, `bunx`, or `pnpm dlx` — e.g. `bunx gitnexus@latest analyze` (npm 11 npx crash; #1939).

## Always Do

- **MUST run impact before editing.** Use `impact({target: "symbolName", direction: "upstream"})` or `node .gitnexus/run.cjs impact "symbolName" --direction upstream --repo .`; report callers, processes, and risk. Never substitute grep for graph analysis.
- **MUST analyze graph changes before committing.** Use `detect_changes({scope: "all"})` (MCP) or `node .gitnexus/run.cjs detect-changes --scope all --repo .` (CLI fallback). `partial: true` or `truncated: true` is not a clean check — a zero means unseen, not unaffected; re-run it. For regression review: `detect_changes({scope: "compare", base_ref: "main"})` or `node .gitnexus/run.cjs detect-changes --scope compare --base-ref "main" --repo .`.
- MUST warn on HIGH/CRITICAL `risk` pre-edit; never use `riskSharedAxes` to waive a HIGH/CRITICAL `risk` warning. Compare File/symbol: MCP File omits axes; Graph-RAG expands File.
- **MUST treat `risk: UNKNOWN` as unresolved, not as low.** An empty caller set is not evidence the symbol is unused — it can also mean the callers are not resolvable by the index (plain-object property access, dynamic dispatch, cross-language calls). `impact` pairs `UNKNOWN` with a `riskNote` saying so. Confirm with a text search before treating the symbol as safe to change or delete; do not proceed on the strength of a zero.
- **MUST use `query({search_query: "concept"})` for concepts/flows, `context({name: "symbolName"})` for a named symbol, or `impact` for blast radius, on read-only callers, dependencies, imports, or execution flow.** Graph first; text search only for empty/`UNKNOWN`/literals.
- For security review, `explain({target: "fileOrSymbol"})` lists taint findings (source→sink flows; needs `analyze --pdg`).

## Never Do

- NEVER edit a function, class, or method before MCP/CLI impact analysis.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis, and never read `UNKNOWN` as an all-clear — it means the walk could not answer, which is the one verdict that requires confirming by other means.
- NEVER rename symbols with find-and-replace — use `rename` which understands the call graph.
- NEVER commit before MCP/CLI graph change analysis.

## Resources

| Resource | Use for |
| --- | --- |
| `gitnexus://repo/Alula_Code/context` | Codebase overview, check index freshness |
| `gitnexus://repo/Alula_Code/clusters` | All functional areas |
| `gitnexus://repo/Alula_Code/processes` | All execution flows |
| `gitnexus://repo/Alula_Code/process/{name}` | Step-by-step execution trace |

## CLI

| Task | Read this skill file |
| --- | --- |
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->
