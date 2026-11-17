# Session Handoff

Last Updated: 2026-11-17

## Current Objective

继续 PR #3 / `codex/vscode-parity-p05`，按 docs/03 N.2 一次一个切片。PR 保持 OPEN/DRAFT，不合并；数值内存优化后置。

## Current State

- 当前工作树 `E:/Temp/alula-pr3-20261117`，本地分支 `codex/pr3-p05-continuation-20261117`，基于 PR head `4839090`。`E:/Alula_Code`（p00）与 `E:/temp/alula-pr3-p05` 的既存脏工作未改动。
- P05.1–P05.69 历史 closeout 已完成登记。P05.70 / feat-122 产品提交 `231e853` 已推 PR #3，本地门禁/本机 Windows Release/PR CI 全通过；hosted Linux/Windows 成功，macOS 待结果。
- 完整结构化 graph export 保留所有 product 11 symbols/103 processes（26 files）和累计 main 888/304（325 files），无 partial/truncated，均 CRITICAL。CLI 自身固定裁剪展示，不能仅提高 --limit 解决；JSON 已归档。
- 新独立 Windows 启动基线最初 Flutter 1323 passed / 37 failed；路径节点/历史期望/URI 盘符/文本 LF 和 tab 定位修正后暴露产品 `_openFileByPath` 的 raw path equality 重复打开问题。现使用已有 `_canonicalPath` 复用同一文档，保留已有预览/跨组视图流程。
- 完整 `bash init.sh` EXIT 0：Rust workspace tests、Clippy、core build、Flutter 1360/1360；独立 cargo fmt、flutter analyze 0 issues、diff check 通过。
- 使用 Git Bash，脚本以 index LF 内容检出，`FLUTTER_BIN=/e/flutter/bin/flutter.bat`，PATH 加 Flutter bundled Dart SDK。本轮证明旧记忆中的 30 项 Explorer 环境失败不能作为未修复基线直接跳过。
- GitNexus 1.6.12 用 `GITNEXUS_MAX_FILE_SIZE=1024` 纳入 WorkbenchPage；编辑前 `_openFileByPath` HIGH（28 affected、10 direct、3 process families、2 modules）。事件回调/测试 file nodes UNKNOWN 保留；不能把无 caller 当低风险。

## Blockers / Limits

- P05.70 产品提交 `231e853` 已推 PR #3；PR CI `43992774712` 四 job 全绿。Platform Availability `43992763968` Linux/Windows 全绿，macOS 仍在运行；重复手动 run `43992764009` 已取消。Linux/Windows app artifacts `14287584621` / `14288304605`，native DnD `14288801926` / `14288224591` 已核实 move/copy/external text。须等待 macOS 后补齐 closeout。
- P05.67 原生双窗 focus/blur、P05.68 Compact pixel/reference diff、P05.69 auxiliary 原生跨窗交换仍未验证；generic DnD 不能代替专属 auxiliary 路径。macOS hosted pointer route 不可用保持 skip。
- LAY-16b 树筛选未实现。已核实固定版 `list.find` 为 Ctrl/Cmd+Alt+F 或 F3，默认 Highlight/Fuzzy；Escape 清除 active query 并 focus tree；完整 Explorer provider 还搜索未加载节点与祖先。下一切片要明确 loaded-tree 与 full-provider 的范围差异。
- 禁止整文件写入式 dart format WorkbenchPage，避免无关重排。

## Evidence and Files

- P05.70: `docs/diagnostics/2026-11-17-p05/p05.70-windows-path-identity.md` 与 `p05.70-init.log`、`p05.70-startup-red.log`、`p05.70-analyze.log`。
- 产品只改 `app/lib/workbench/workbench_page.dart` 文件身份比较；测试 helper `app/test/helpers/file_paths.dart` 与九个测试文件。
- 既有 P05.69 证据：`docs/diagnostics/2026-11-17-p05/p05.69-auxiliary-window-cross-window-drop.md`；PR CI 43941953054、Platform Availability 43941942416。

## Next Session First Step

先完成 P05.70 提交后的 hosted closeout，再从 docs/03 登记下一独立 slice；推荐 LAY-16b 树查找/筛选。保持原工作树不动；commit 前完整 GitNexus detect-changes，UNKNOWN/截断如实登记。更新 docs/03、feature_list.json、progress、handoff 同步。
