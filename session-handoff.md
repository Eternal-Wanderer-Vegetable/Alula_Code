# session-handoff.md — 会话交接

> Last Updated：2026-10-30（P02.4 编码/BOM/EOL 完成）

## 项目目标

按 docs/10-VSCode无插件全功能复刻总计划.md，使用 Flutter + Rust 复刻固定版本 VS Code 默认非 AI 能力。docs/03 是状态、依赖与 DoD 的唯一权威；一次只推进一个 feature 切片。

## 当前状态

- 当前优先级：P00–P13 完成整体架构和默认功能复刻；P14 做全功能性能/内存优化；P15 做最终对照与发布验收。
- P00 阶段交付物已签收。P01 / feat-023 的 P01.1–P01.4 已完成并分阶段提交。P02 / feat-024 当前 in-progress：P02.1 undo/redo 与共享历史预算、P02.2 dirty/savepoint、P02.3 Save As/Revert、P02.4 编码/BOM/EOL 已完成；当前唯一活动切片为 P02.5 外部变更/冲突/只读/孤儿文档。
- Rust + rust-analyzer ≤500 MiB 目标暂时移出当前目标集合与验收门；历史与新增测量仅作基线，P14 完成整体架构后重新制定优化指标。P00–P13 仍须满足有界资源、关闭时回收、压力下可编辑/保存和无数据丢失要求。
- 真实 DRM/WPE GBM 与 Microsoft 官方服务身份/许可仍有外部阻塞，按 docs/03 对应阶段处理，不阻塞当前 P02。
- P02.1：docs/diagnostics/2026-10-30-p02/p02.1-per-document-undo.md；P02.2：docs/diagnostics/2026-10-30-p02/p02.2-savepoint-dirty-undo.md；P02.3：docs/diagnostics/2026-10-30-p02/p02.3-save-as-revert.md。
- P02.4：docs/diagnostics/2026-10-30-p02/p02.4-encoding-bom-eol.md。`workbench_page.dart` 含既存未提交编辑器/Git 变更，编码阶段提交需只暂存 P02.4 hunk；`keybindings.dart` 与 harness/agent/docs09 等工作区改动保持不纳入。

## 工作树注意事项

仓库有既存未提交改动，包含 harness 技能迁移、agent/、README、app 中其他功能及格式、docs09、appendix、旧诊断证据等；不得重置或混入无关内容。app/lib/workbench/workbench_page.dart 与 app/lib/workbench/keybindings.dart 尤其包含既存用户修改，阶段提交必须创建只含当前阶段目标的 staged snapshot。

## 下一步

1. 从 P02.5 开始：GitNexus impact 后验证干净文件自动重载、脏文件冲突保留双侧、只读保存失败和删除/重命名后继续编辑/另存。
2. 完成 P02.5 后继续 P02.6，再按 docs/03 的依赖与切片顺序推进；P00–P13 完成前不做 500 MiB 数值优化。
