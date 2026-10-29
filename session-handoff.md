# session-handoff.md — 会话交接

> Last Updated：2026-10-29（固定版 rust-analyzer 按查询 LRU 配置审计）

## 项目目标

按 `docs/10-VSCode无插件全功能复刻总计划.md`，使用 Flutter + Rust 复刻固定版本 VS Code 的默认非 AI 能力。每次只推进 `docs/03` 中一个 feature；P00.1–P00.3 已完成，当前仍是 feat-022 / P00.4。`docs/03` 是状态和 DoD 的唯一权威。

## 当前状态

- 解决固定 Code-OSS 1.145.0-dev 启动没有 renderer 的问题：旧产物是生产 NLS-indexed bundle，而 `scripts/code.bat` 设置 `VSCODE_DEV=1` 并跳过 NLS 消息加载。使用 Windows Node 24.22.1 执行 `node build/next/index.ts transpile` 后，隔离 smoke 在 6 秒内出现 renderer。仅更新了单独的 pinned reference checkout 生成产物，未修改 Alula 产品代码。
- 完成用户授权的固定版 Code-OSS + rust-analyzer 1.97.1 idle 对照：600 样本/888.565 秒，Private Bytes 峰值/尾段稳定/末值 2346.86/1702.66/1705.49 MiB。RA 可见、前台未变，关闭+30秒 PID 全退且临时数据清理。证据：`docs/diagnostics/2026-10-28-p00/p00.4-windows-code-oss-rust-lsp-idle-20261029-160631502.{json,md,log}`。
- Windows Alula Rust+RA 前台编辑样本有效：1800.015 秒、150/150 次保存，尾部稳定 Private Bytes 657.93 MiB，高于 500 MiB 预算。Code-OSS idle 样本不能替代这个编辑负载。
- 固定版 rust-analyzer 0.3.3089（commit `5ec20d044d`）的 per-query LRU schema 存在，但数据库实现是 Salsa 迁移 FIXME/no-op；没有启动无效实验。审计：`docs/diagnostics/2026-10-29-p00/p00.4-rust-analyzer-query-lru-config-audit.md`；产品配置未改。
- P00.4 仍 blocked / feat-022 in-progress；用户确认暂无真实 DRM Linux 主机与获授权的 Microsoft 官方客户端身份。WPE GBM/DMABUF、官方服务条件、500 MiB 产品目标和完整 docs/04 矩阵仍未通过。P01 不启动。
- 提交前门禁通过：`bash init.sh`（Rust tests、Clippy、build_core、Flutter 122 tests）、`cargo fmt --check`、`flutter analyze`。

## 本轮文件

- P00.4 报告：固定版 Code-OSS idle JSON/Markdown/log、启动根因补充，以及 `docs/diagnostics/2026-10-29-p00/p00.4-rust-analyzer-query-lru-config-audit.md` / `.json` 配置审计。
- 状态登记：`docs/03-里程碑计划与验收标准.md`、`feature_list.json`、`progress.md`、本文件。
- `app/build` 中的临时 smoke runner/摘要已清理；Code-OSS 隔离 profile 与 Rust fixture 已由 runner 清理。

## 下一步

1. 按仓库 Startup Workflow 读取本文件和 `progress.md`，检查 `node .gitnexus/run.cjs status`；如 stale，先重建索引。
2. 查 `docs/03` 的 P00.4 剩余 DoD，继续推进当前环境可完成的证据项；不要启动 P01。真实 DRM 主机和官方客户端身份若仍不可用，保留阻塞和准确证据。
3. 阶段证据提交 `b6dd5f4` 已推送到 `origin/codex/vscode-parity-p00`；保留工作树中其余既有未提交改动，不要把它们混入后续提交。
