# session-handoff.md — 会话交接

> 收尾时更新本文件，让下一个会话无需考古即可续作。
> Last Updated：2026-10-26（第八轮收尾：W3-1 命令面板完成；CI 首跑失败已修复并复跑）

## 项目一句话

低内存代码编辑器（对标 VS Code 但内存 −50%）：Flutter 桌面工作台 + Rust 编辑核心。
Phase 0 已关闭（G1 决策：原型 B 自研路线），当前处于 **Phase 1（V1 轻量编辑器）**。

## Current Objective

**W1 全部完成 + W2 全部完成（交互复验用户已过）+ W3-1 命令面板完成**
（67 测试绿 + init.sh 全绿；已首次 push GitHub，CI 首跑失败→修复→复跑中）。
- W3-1 已落能力：CommandRegistry（11 命令）/fuzzyScore/QuickInput 浮层/
  Ctrl+Shift+P 命令面板/Ctrl+P 快速打开（有界文件索引）/Ctrl+B、Ctrl+J。
- W3 剩余：完整 KeybindingRegistry（when 子句 + keybindings.json 覆盖）、
  快速打开异步化（同步 FFI 遍历大仓库卡 UI）。
- W2 已落能力：标签条交互（溢出/中键/拖动排序）、编辑器组（拆分/焦点路由/空组并组）、
  面包屑（点击展开树）、会话 journal（未保存内容崩溃恢复）+ dirtyDisk 真脏标记
  （修正了原 isDirty 永假的隐性 bug，标签脏点现在正确显示）。
- ⚠️ 交互级人工复验未做（agent 无法操作真窗口）：拆分按钮/拖标签/强杀进程后
  重启恢复未保存内容。复验通过即可 push。
- 下轮候选：W2-5 符号大纲面包屑（需 editor-lang symbol 查询 + FFI，Rust 侧）、
  W3 命令面板（CommandRegistry/QuickInput，docs/09）、feat-010 撤销重做/查找替换。

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

- **W2 交互级人工复验**（agent 无法操作真窗口）：拆分/拖标签/强杀恢复，
  清单见 Next Session 第 2 条。
- CI/CD 工作流未在 GitHub Actions 实机跑过（remote 已配置：
  github.com/Eternal-Wanderer-Vegetable/Alula_Code，需用户推送）。
- feat-002 编辑器组件人工复核需真机 + 微软拼音（人工环节，agent 无法替代）。

## Files（第三轮新增/改动）

- `app/lib/workbench/`：layout_model.dart（分割树模型）、layout_controller.dart、
  layout_grid.dart（渲染+分割条）、layout_store.dart（持久化）、workbench_page.dart
  （原 main.dart 全逻辑迁移）、title_bar/activity_bar/status_bar.dart
- `app/lib/main.dart`：瘦身为入口；`app/test/`：layout_model/grid/store/widget 测试
- 本轮提交：`443e3e5`→`W1-4`（chore 清理、harness、ci、docs09、W1-1/2/4 共 7 笔）
- `feature_list.json`（feat-015 登记）、`progress.md`、`session-handoff.md`（本文件）

## Next Session（推荐首步）

1. **推送 GitHub 看 CI 首跑**（用户操作）：`git push`。
2. **人工交互复验（需真窗口，见 Blockers）**：`flutter run -d windows` →
   ① 拆分按钮出双组、拖标签跨组；② 编辑不保存 → 任务管理器强杀 → 重启 →
   未保存内容从 journal 恢复；③ 标签脏点（•）随编辑出现、Ctrl+S 消失。
3. 复验通过后 `git push`（CI 首跑 + Linux PSS 首验）。
3. feat-010（撤销/重做/查找替换）与 W2 并行线，先做谁由用户定。

## 已知坑

- FFI 偏移一律 UTF-16 code unit，动协议前读 AGENTS.md 不变量 1–3。
- `app/windows/`、`app/native/`、`.gitnexus/` 都在 gitignore，clone 后需
  `flutter create` + `build_core` 重建。
- docs/03 任务表是状态权威源；改状态时同步 feature_list.json + progress.md。
