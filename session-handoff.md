# session-handoff.md — 会话交接

> 收尾时更新本文件，让下一个会话无需考古即可续作。
> Last Updated：2026-10-26（第二轮会话收尾）

## 项目一句话

低内存代码编辑器（对标 VS Code 但内存 −50%）：Flutter 桌面工作台 + Rust 编辑核心。
Phase 0 已关闭（G1 决策：原型 B 自研路线），当前处于 **Phase 1（V1 轻量编辑器）**。

## Current Objective

本会话完成工程化建设（GitNexus 图谱 / harness 文档 / CI/CD / 复刻计划）；
**下一会话回到功能开发：feat-010 下一增量。**

## 本会话完成了什么

1. **GitNexus 代码图谱**：`npx gitnexus analyze` 建立索引（796 符号/1681 关系/66 执行流）。
   `.gitnexus/` 已入 gitignore（本地缓存，新 clone 后重跑即可）。CLAUDE.md/AGENTS.md
   里 `<!-- gitnexus:start -->` 块之间是自动生成区，项目守则写在其上方，勿删块标记。
2. **harness 文档五件套**：AGENTS.md/CLAUDE.md（守则+不变量+DoD）、feature_list.json、
   progress.md、init.sh、本文件。skill 装在 `.agents/skills/harness-creator/`，
   用 `node .agents/skills/harness-creator/scripts/validate-harness.mjs --target .` 可复查。
3. **CI/CD**：`.github/workflows/ci.yml`（Rust fmt+clippy+test 双系统矩阵 / Flutter
   analyze+test 走真实 FFI / harness 结构校验）+ `release.yml`（tag 触发 Windows/Linux
   打包并发布 Release）。附带把全仓 clippy 警告清零、cargo fmt 统一、
   build_core.sh 补 Windows dll —— 这些是让 CI 门能过的前置修复。
4. **VSCode 工作台复刻计划**：`docs/09-VSCode工作台Flutter复刻计划.md`
   （W1–W6 里程碑 + 内存护栏 + 风险表；仅计划，未实施）。

## 验证状态

- `bash init.sh` 一键全绿（EXIT=0，2026-10-26）：cargo fmt --check / cargo test（41）/
  clippy -D warnings（0 警告）/ build_core / flutter analyze / flutter test（15）
- Flutter SDK 在 `E:\flutter`，Git Bash 不在 PATH：init.sh 会自动探测，
  手动调用用 `/e/flutter/bin/flutter`
- CI 工作流 YAML 语法已校验；**Actions 真机首跑待推送后确认**

## Blockers（阻塞项）

- 无硬阻塞。两个外部依赖：
  - CI/CD 工作流未在 GitHub Actions 实机跑过（remote 已配置：
    github.com/Eternal-Wanderer-Vegetable/Alula_Code，需用户推送）；
  - feat-002 编辑器组件人工复核需真机 + 微软拼音（人工环节，agent 无法替代）。

## Files（本会话涉及文件）

- `CLAUDE.md` / `AGENTS.md`（守则 + gitnexus 块）、`feature_list.json`、`progress.md`、
  `init.sh`、`session-handoff.md`（本文件）
- `.github/workflows/ci.yml`、`.github/workflows/release.yml`（新增）
- `docs/09-VSCode工作台Flutter复刻计划.md`（新增，仅计划）
- `.gitignore`（加 `.gitnexus/`）

## Next Session（推荐首步）

1. **推送 GitHub 看 CI 首跑**（用户操作）：`git push`；若 Rust/Flutter job 挂在环境差异
   （Linux PSS mem-probe 首次在 CI 验证，feat-005 遗留项），按日志修。
2. **首选开发任务**：实现 feat-010 下一增量 —— 撤销/重做 UI 化（先查
   `crates/editor-buffer` undo 现状）、查找替换（先 crate 内实现+测试，再接 FFI）、
   文件监视（crates/editor-workspace）。
3. feat-002 人工复核（需要真机+微软拼音，属人工环节）：code_forge IME 与万行流畅度。

## 已知坑

- FFI 偏移一律 UTF-16 code unit，动协议前读 AGENTS.md 不变量 1–3。
- `app/windows/`、`app/native/`、`.gitnexus/` 都在 gitignore，clone 后需
  `flutter create` + `build_core` 重建。
- docs/03 任务表是状态权威源；改状态时同步 feature_list.json + progress.md。
