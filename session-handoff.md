# session-handoff.md — 会话交接

> Last Updated：2026-10-30（P02.2 dirty/savepoint 完成）

## 项目目标

按 docs/10-VSCode无插件全功能复刻总计划.md，使用 Flutter + Rust 复刻固定版本 VS Code 默认非 AI 能力。docs/03 是状态、依赖与 DoD 的唯一权威；一次只推进一个 feature 切片。

## 当前状态

- 当前优先级：P00–P13 完成整体架构和默认功能复刻；P14 做全功能性能/内存优化；P15 做最终对照与发布验收。
- P00 阶段交付物已签收。P01 / feat-023 的 P01.1–P01.4 已完成并分阶段提交。P02 / feat-024 当前 in-progress：P02.1 每文档 undo/redo 与共享历史预算、P02.2 dirty/savepoint 跨编辑/undo/redo/既有路径保存已完成；下一切片 P02.3 Save As/Revert。
- Rust + rust-analyzer ≤500 MiB 暂时不作为验收门；历史与新增测量保留为基线，P14 重新定标。P00–P13 仍须满足有界资源、关闭时回收、压力下可编辑/保存和无数据丢失要求。
- 真实 DRM/WPE GBM 与 Microsoft 官方服务身份/许可仍有外部阻塞，按 docs/03 对应阶段处理，不阻塞当前 P02。
- P02.1 证据：docs/diagnostics/2026-10-30-p02/p02.1-per-document-undo.md。P02.2 证据与验证：docs/diagnostics/2026-10-30-p02/p02.2-savepoint-dirty-undo.md。

## 工作树注意事项

仓库有既存未提交改动，包含 harness 技能迁移、agent/、README、app 中其他功能及格式、docs09、appendix、旧诊断证据等；不得重置或混入无关内容。app/lib/workbench/workbench_page.dart 尤其包含既存的跳转定义/Git 命令/鼠标处理等用户改动，阶段提交必须从当前 HEAD 创建只含本切片 hunk 的 staged snapshot。

## 下一步

1. 开始 P02.3 前按 GitNexus 做 Save As/Revert 路径查询及 impact；保持一次只推进一个切片。
2. P02 完成后按 docs/03 依赖进入 P03，继续先复刻整体架构和默认能力；资源/生命周期约束照常执行，500 MiB 数值优化放到 P14。
