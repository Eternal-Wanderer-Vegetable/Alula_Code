# progress.md — 项目进度跟踪

> agent 会话状态文件：每完成一项工作就追加记录。任务权威分解在 `docs/03`，
> 功能状态机在 `feature_list.json`，本文件记录「何时、做了什么、证据是什么」。

## Current State（当前状态，2026-10-26）

**Phase 0 技术验证已关闭（决策门 G1 已过）：固定原型 B 自研路线**
（Flutter 工作台 + Rust 核心 + Tree-sitter + LSP + 可选 Node 宿主）。
**Phase 1 增量 1 完成**：多文件工作台闭环 + rust-analyzer 按工作区共享接入。

## 今日会话（2026-10-26 第二轮）：工程化建设

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
