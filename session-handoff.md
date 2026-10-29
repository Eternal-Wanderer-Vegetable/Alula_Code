# session-handoff.md — 会话交接

> Last Updated：2026-10-29（用户调整复刻与内存优化顺序）

## 项目目标

按 `docs/10-VSCode无插件全功能复刻总计划.md`，使用 Flutter + Rust 复刻固定版本 VS Code 默认非 AI 能力。`docs/03` 是状态、依赖与 DoD 的唯一权威；一次只推进一个 feature。

## 当前状态

- 当前优先级：P00–P13 完成整体架构和默认功能复刻；P14 做全功能性能/内存优化；P15 做最终对照与发布验收。
- 当前唯一进行项：P01 / feat-023「异步服务/上下文/进程监督」。P00 / feat-022 已完成阶段交付物签收。固定参考、贡献项导出、风险夹具和三项实验 ADR/证据均有登记。
- Rust + rust-analyzer ≤500 MiB 数值目标暂时不再作为验收门。已有采样留作基线，P14 重新定标。架构阶段仍需保证资源有界、关闭时回收、压力下可编辑/保存及无数据丢失。
- 后续风险：真实 DRM/WPE GBM 尚未验证；Microsoft 官方服务身份/许可未提供。分别在 Web/联网集成阶段继续处理，不阻塞 P01。
- 最新 Code-OSS 对照证据：`docs/diagnostics/2026-10-28-p00/p00.4-windows-code-oss-rust-lsp-edit-30m-20261029-181513092.{json,md}`，1800.556 秒、150/150 次保存读盘验证、1484 个进程树样本。此数据只作参考基线，不再用于 500 MiB 门槛判定。
- `bash init.sh --fast` 复跑通过：Rust workspace tests、`build_core`、Flutter 122/122。初次 P00.3 `REF-07-UNDO-01` 因第二文档激活时的 400ms undo coalescing 时间窗偶发失败；测试在第二文档打开后补 450ms 实时等待，复跑记录到预期跨文档撤销串写。`cargo fmt --check`、Clippy、`flutter analyze --no-pub` 也通过。

## 工作树注意事项

仓库有既存未提交改动，包含 `.agents/skills/harness-creator/`、`.claude/`、`agent/`、`app/`、README、docs09、appendix、多个诊断证据目录以及 feature/progress 状态。不得重置或混入无关内容。当前优先级调整只提交其必要的计划/状态文件。

## 下一步

1. 先检查本次状态调整的 GitNexus `detect-changes` 与文档一致性，再提交优先级调整。
2. 从 P01 拆出单一首项，先审计现有 async request/event/version、workspace lifecycle 与 process supervisor 合同，再按 GitNexus 要求做影响分析后编辑。
3. 完成架构阶段；资源使用只记录可比基线和生命周期/稳定性，不提前追逐占用数字。全部优化留到 P14。
