# Session Handoff

Last Updated: 2026-11-18

## Current Objective

连续完成PR #3的P05，按docs03 N.2和LAY/CMD矩阵一次一片。PR保持OPEN/DRAFT、不合并；普通进度不需批准。用户已明确无macOS设备，原生/视觉/实测和历史缺口暂留未验证，继续P05，不以macOS实机或探针排障为前置。hosted不替代设备。

## Current State

- 独立worktree E:/Temp/alula-pr3-20261117，branch codex/pr3-p05-continuation-20261117，上游codex/vscode-parity-p05。最新产品7fe2a11d2ec2fc724ae03ad625bc0fdb94aceadf已推，当前待最后137hosted收尾文档提交。原E:/Alula_Code和E:/temp/alula-pr3-p05脏工作区保留。
- P05.85/feat137通知toast期限窄子项done：Info10/Warning12/Error15s，在deadline重评hover/descendantfocus/activeprogress/Erroractions并整周期延期；窗口失焦到期后等聚焦重新给完整周期。到期前恢复/离开不重置，重建不重置。每keyed可见toast1Timer，最多现有3条，无polling；remove/clear/DND/evict/unmount取消。只dismissToast，center/unread保留。Workbench既有WindowListener传windowFocused，不改auxchannel/progress业务。
- 组件16+真实WorkbenchUI5=21通过，完整顺序init1495/1495、Rusttests/Clippy/core、独立fmt/analyze0、Harness100/100。审查代理认证失败，父侧定向review完成，不能记代理pass。首轮full1494/1495仅SCMfixture write-tree128、无stderr根因未定；改只读gitls-files--stage-z比较path/OID/mode/stage并打印stderr，真实repo1与最终全量通过，失败日志保留。
- 准确7fe CI44282450910四项成功，actual1495tests/analyze clean；Platform44282442631 Linux10:11:58Z/Windows10:17:50Z成功。Win desktop25/clipboard1/DnD12pointercallbacks，App14418790274/DnD14417887324；Linuxclipboard1/两launch/DnD20pointercallbacks，App14418625084/DnD14417832413。探针只证明原生路由回调，不扩展buffer/undo。mac未等待/下载/probe。
- 完整graphall19files/7symbols/439flows及main570/311/441 CRITICAL，无partial/truncated、snapshot稳定；toast/私有focusimpactUNKNOWN、空name异常，actualcaller核对，历史共享WorkbenchCRITICAL保留。
- P05.84/feat136完成，产品697ab24、收尾7ffc101、交接37db43c已推；typedvalidationInfoWarning接受/Error空也阻止，旧API兼容，GotoLine集成；专项13/full1478/review与CI44272272721/WinLinux成功。P05.83/feat135菜单产品f4b1faf、收尾14b9420已推，component37/repo1/full1472与CI/WinLinux成功。
- P05父阶段及LAY/CMD父行仍开放；前80–82/mac历史证据保留，不以新SHA覆盖。

## Blockers / Limits

- macOS无设备，原生/视觉/实机以及历史Quit/AX/DnD问题暂留，不阻塞继续功能实现，不追加mac排障。
- GitNexus空name/privateUNKNOWN/跨语言/trace预算限制保留；完整JSON无partial/truncated不代表全覆盖。不要全文件formatWorkbenchPage。
- 通知ClearAll的activeprogress例外、完整provider/actions/errorwiring仍未完成；本片只验证被移除toast清理和deadline，不改中心清除语义。
- 七个generatedregistrants为既有构建产物未提交，两原脏树未动。Flutter前build_core，避免同时加载DLL的专项与initbuild并行。

## Evidence and Files

- docs/diagnostics/2026-11-18-p05/p05.85-notification-toast-lifetime.md、acceptance-map、hosted.md、hosted-verification.json及red/green/full/graph；原始hosted E:/Temp/alula-p0585-hosted-20261118/20261118T100943Z-4bdecf71。
- P05.83/84同目录完整证据；graph导出脚本E:/Temp/alula-p0580-graph-export.mjs。

## Next Session First Step

先提交137最后准确hosted/状态证据（Harness/JSON/diff+graphall/main），更新PR。下一推荐P05.86/feat138 OpenEditors排序：editorOrder/alphabetical/fullPath，按组排序副本不改tabs/MRU/active/view，稳定tie保留原tab顺序；固定版numeric/locale比较需认真对拍并明确locale边界，不能直接lowercasecompareTo。尚未登记/实施；先impact并核对现有OpenEditorsView及pinnedopenEditorsView.ts，headerselector/session偏好属P05适配，正式配置优先级P07。代码1495已绿、无变化不重复全量，mac缺口暂留。
