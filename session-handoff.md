# Session Handoff

Last Updated: 2026-11-18

## Current Objective

用户已授权连续整体完成 P05，不因普通进度等待批准。按 docs/03 N.2、LAY-01–20 与 CMD-01–12 一次一片推进 PR #3；保持 OPEN/DRAFT，不合并。路线 `docs/plans/p05-completion.md`；父阶段和矩阵行不能因子切片完成而关闭。

## Current State

- 唯一工作树 `E:/Temp/alula-pr3-20261117`，分支 `codex/pr3-p05-continuation-20261117`，上游 PR 分支 `codex/vscode-parity-p05`。已推产品 head `9117a06ef5130c3513648b514a164af481082c64`；原 `E:/Alula_Code` p00 与 `E:/temp/alula-pr3-p05` 脏工作区不覆盖。
- 当前 P05.80 review修复尚未提交：行FocusNode按Enter内部转容器焦点导致async guard拒绝；同entries父刷新无条件reveal导致手动scroll回跳。新测均先红后绿，组件11/11、真实仓库1/1、analyze0；首轮1445/1446仅merge cleanup errno32，补fixture卸载/settle/runAsync后专项15/15、最终init.sh Flutter1446/1446、Rust/Clippy/core/fmt全绿。实现仅GitChangesList：保留已有descendant焦点，update仅focused pixel offset变化时reveal；无新常驻state。报告`docs/diagnostics/2026-11-18-p05/p05.80-focus-scroll-review-fixes.md`。P05.81未开工。
- 当前 P05.80 / feat-132 / LAY-16d：SCM 基本资源列表键盘导航。新 `app/lib/git/git_changes_list.dart` 管理单个 focus/scroll、lazy rows、focus/selection分离、arrows/Home/End reveal、Enter open、Space open preserve focus不暂存、hover独立、action button键盘激活。工作台按workspace key重建列表、Git diff显示panel并拒绝迟到Git/workspace/request结果，Enter按源焦点未变时交焦点。
- P05.80 组件9/9、组件+Git CLI/真实repo20/20、WorkBench真实临时仓库fixture及原最终 `bash init.sh` Flutter1444/1444通过；产品9117a06、PR CI44141662139四job成功。Platform44141648010 attempt1 Linux成功、Windows native DnD drop超时、macOS native Quit调用后20秒未退出；attempt2 Windows全绿（native DnD13 pointerevents），macOS1443/1444仅SCM焦点固定100ms断言失败，后续Release/Quit/package skipped；修正提交e865b11的CI/Platform与日志b162222 CI运行中。2026-11-18启动基线Flutter1442/1444：SCM焦点断言固定100ms不足，改10秒上限等待实际焦点；Smart Enter teardown errno32，改显式卸载/settle/runAsync删除。专项1/1及27/27通过；修正后完整init.sh Flutter1444/1444、Rust tests/Clippy/core、fmt/analyze0通过，首次失败与最终绿日志均归档。范围报告 `docs/diagnostics/2026-11-17-p05/p05.80-scm-list-navigation.md`；新诊断 `docs/diagnostics/2026-11-18-p05/p05.80-startup-focus-regression.md`。
- P05.79 `0683785`，证据 `4f20623`/`4f2b9bb`；PR CI44110829105全绿，Platform44110812720 Linux/Windows全绿，macOS tests/Release/clipboard/Quit/package通过；DnD integration app90秒未ready（Building macOS application...），probe失败，DnD未验证。app artifacts14339774563/14340438602/14344941314，DnD14343719095。
- P05.78 `76d70d5`，证据80277e4；CI44094751711 attempt2全绿，attempt1既有editor多选tab测试一次空selection，根因未修；隔离重跑通过。Platform44094742100 Linux/Windows通过，macOS tests/Release/clipboard通过，Quit卡住60分钟timeout，package未执行；不可由别的SHA成功覆盖。
- P05.77 ABI41 `5683e77`、CI fixture build0995dc8；CI44077819111全绿，Platform44077810454三平台全绿，macOS native DnD pointer route不可用skip。P05.71–76已核对exact SHA与hosted/ZIP证据并补记窄子项done；P05.75 Platform44037183025 attempt2整体失败（native DnD skip notice后40秒超时），但macOS tests/Release/launch/Quit/package通过。其余五项准确PA成功，macOS DnD因pointer route不可用明确skip。六份macOS ZIP均81项完整且SHA256匹配sidecar；父LAY/CMD/P05不关闭。

## Blockers / Limits

- P05.80只补基本SCM列表宿主；混合index/worktree双侧资源、完整树分组/多选/范围/type/find/context menu仍未覆盖（LAY-16/P09）。当前diff目的地仍既有bottom panel，不声称完整SCM editor复刻。表格尚未有实际surface，勿加未使用generic widget凑验收。
- GitNexus重建使用 `GITNEXUS_MAX_FILE_SIZE=1024`；_gitTile pre-edit CRITICAL、_showGitDiff/_buildGitPanel/_buildGitDiffPanel UNKNOWN。源码caller核验是UNKNOWN补充，不是low证明。index有entry/callee/trace/cross-language覆盖限制；完整JSON export的无partial/truncated不抹除index限制。
- P05.67原生双窗focus、P05.68Compact像素、P05.69aux交换、固定主题/字体/DPI/reference视觉等仍未验证。generic DnD不替代aux专属链路；skip不作pass。
- generated registrants（7文件）仅构建状态，未纳入产品提交。禁止全文件写入式format WorkbenchPage。

## Evidence and Files

- P05.80报告与新控件/测试；`app/test/widget_test.dart`真实仓库fixture；工作台最小接线。
- 新会话基线修正已推e865b11，原始日志已推b162222；`docs/diagnostics/2026-11-18-p05/p05.80-startup-focus-regression.md`与同目录完整failed/green/analyze/graph日志。历史六项hosted账本`p05.71-76-hosted-ledger.md`和`p05.72-76-package-verification.json`已提交。
- 完整图谱导出脚本 `E:/Temp/alula-p0580-graph-export.mjs`；参数：repo、output prefix、main。暂存新文件后再rebuild/export，保留all和compare-main原始JSON。

## Next Session First Step

先收齐P05.80原产品9117a06的Platform44141648010 attempt2 macOS结果与ZIP；Windows attempt2已全绿，勿做第三轮无诊断重试。基线修正e865b11的CI44219803751、Platform44219797014及日志头b162222的CI44220241478待结果；不以其他SHA成功替代原提交验收。原产品收尾/只读review后按docs/03单独登记SCM多选范围slice，再实施；参考已核实Shift-click保留disjoint、Shift+Arrow采用tree扩选而非通用range算法、Enter/Space仅focused资源。继续剩余P05路线，不停在普通进度确认。所有Git Bash测试需PATH含 `/e/flutter/bin/cache/dart-sdk/bin:/e/flutter/bin`。PR保持OPEN/DRAFT。
