# session-handoff.md — 会话交接

> Last Updated：2026-10-29（固定版 Code-OSS 30 分钟脚本编辑对照）

## 项目目标

按 `docs/10-VSCode无插件全功能复刻总计划.md`，使用 Flutter + Rust 复刻固定版本 VS Code 的默认非 AI 能力。每次只推进 `docs/03` 中一个 feature；P00.1–P00.3 已完成，当前仍是 feat-022 / P00.4。`docs/03` 是状态和 DoD 的唯一权威。

## 当前状态

- 固定 Code-OSS 1.145.0-dev + rust-analyzer 0.3.3089/server 1.97.1 的 30 分钟 API 编辑对照完成：1800.556 秒、1484 个进程树样本、150/150 次保存均逐次读盘验证；Private Bytes 峰值/尾段稳定/末值 2223.14/1774.34/1788.38 MiB，末 Working Set 1853.30 MiB。临时 helper extension 开销计入进程树；一次启动焦点恢复后继续，关闭+30 秒全部观察 PID 退出且临时目录清理。证据：docs/diagnostics/2026-10-28-p00/p00.4-windows-code-oss-rust-lsp-edit-30m-20261029-181513092.json/.md。

- 解决固定 Code-OSS 1.145.0-dev 启动没有 renderer 的问题：旧产物是生产 NLS-indexed bundle，而 `scripts/code.bat` 设置 `VSCODE_DEV=1` 并跳过 NLS 消息加载。使用 Windows Node 24.22.1 执行 `node build/next/index.ts transpile` 后，隔离 smoke 在 6 秒内出现 renderer。仅更新了单独的 pinned reference checkout 生成产物，未修改 Alula 产品代码。
- 完成用户授权的固定版 Code-OSS + rust-analyzer 1.97.1 idle 对照：600 样本/888.565 秒，Private Bytes 峰值/尾段稳定/末值 2346.86/1702.66/1705.49 MiB。RA 可见、前台未变，关闭+30秒 PID 全退且临时数据清理。证据：`docs/diagnostics/2026-10-28-p00/p00.4-windows-code-oss-rust-lsp-idle-20261029-160631502.{json,md,log}`。
- 用户授权的 Microsoft VS Code 同服务 idle 复跑 3 已完成：1.142.0 Stable + rust-analyzer 0.3.3089/server 1.97.1，600 点/858 秒，Private Bytes 峰值/尾段稳定/末值 1728.71/1431.09/1423.68 MiB。RA 可见，启动时焦点恢复一次，关闭+30秒所有观察 PID 退出且隔离目录清理。五轮 VS Code idle 稳定值中位数 1324.33 MiB；此版本不匹配固定 Code-OSS，且不覆盖编辑负载。证据：`docs/diagnostics/2026-10-28-p00/p00.4-windows-vscode-rust-lsp-idle-rerun3-20261029-172235485.{json,md}`，同目录 runner 与 `.log`。
- Windows Alula Rust+RA 前台编辑样本有效：1800.015 秒、150/150 次保存，尾部稳定 Private Bytes 657.93 MiB，高于 500 MiB 预算。Code-OSS idle 样本不能替代这个编辑负载。
- 固定版 rust-analyzer 0.3.3089（commit `5ec20d044d`）的 per-query LRU schema 存在，但数据库实现是 Salsa 迁移 FIXME/no-op；没有启动无效实验。审计：`docs/diagnostics/2026-10-29-p00/p00.4-rust-analyzer-query-lru-config-audit.md`；产品配置未改。
- P00.4 仍 blocked / feat-022 in-progress；用户确认暂无真实 DRM Linux 主机与获授权的 Microsoft 官方客户端身份。WPE GBM/DMABUF、官方服务条件、500 MiB 产品目标和完整 docs/04 矩阵仍未通过。P01 不启动。
- 提交前门禁通过：`bash init.sh`（Rust tests、Clippy、build_core、Flutter 122 tests）、`cargo fmt --check`、`flutter analyze`。

## 上一轮文件（Windows VS Code idle 复跑 3）

- P00.4 报告：Microsoft VS Code 同服务 idle 复跑 3 的 JSON/Markdown/log 与隔离 runner。
- 状态登记：`docs/03-里程碑计划与验收标准.md`、`feature_list.json`、`progress.md`、本文件。
- Microsoft VS Code 临时 profile/扩展副本/shared-data 与固定 Code-OSS 隔离 profile/Rust fixture 均已清理。
## 本次续跑文件

- 固定 Code-OSS 30 分钟编辑 runner、正式 JSON/Markdown 报告与 30 秒预检 JSON/Markdown。
- P00 状态登记：docs/03-里程碑计划与验收标准.md、progress.md、本文件。
- 临时 Code-OSS profile、扩展、shared-data、fixture 均已清理；此前其他工作树改动保留。
## 下一步

1. 下一会话按 Startup Workflow 检查本文件、progress.md、node .gitnexus/run.cjs status 和 bash init.sh --fast。
2. 继续当前唯一 feature feat-022 / P00.4；先看 docs/03 的未通过 DoD 和现有证据，不启动 P01。
3. 如果仍没有真实 DRM Linux 主机或获授权的 Microsoft 官方测试身份，保留对应阻塞；在可用环境中继续补齐不依赖它们的 P00.4 证据。
