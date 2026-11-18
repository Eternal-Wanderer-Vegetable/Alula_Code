# P05 连续完成目标与执行顺序

2026-11-17 用户明确要求：整体完成 P05，中间无需停止报告。按 docs/03 N.2 与 docs/11 的 LAY-01–20、CMD-01–12 逐行完成；PR #3 保持 OPEN/DRAFT，不合并。既有 child done 不等于整行 done，不以占位、mock provider、generic DnD 或其他 OS 替代真实结果。

## 执行约束

一次只推进一个产品 feature；调研/评审可服务于当前阶段盘点。单片实现→定向/全量→图谱→提交→hosted→证据登记后继续下一项。500 MiB 数值目标后置；数据安全、资源上限与退出清理持续生效。原 E:/Alula_Code 和 E:/temp/alula-pr3-p05 脏工作区保留。

## 剩余交付顺序

1. P05.80已收尾：最新产品6e529d4本地Flutter1446/1446与全部门禁通过，CI44222976491四job和Platform44222968734三平台通过；macOS nativeQuit/package通过，DnD pointerroute不可用明确skip。mac包14393775629已核对81项/sidecar。历史9117a06/e865b11失败保留、不以最终成功抹除。P05.70–76准确SHA证据已补，P05.75仍保留macnativeDnD失败。下一项按docs/03单独登记SCM多选/范围，不关闭P05父阶段。
2. LAY-16：Explorer tree find/filter、固定评分/字符范围、查询历史与键盘导航已在P05.71登记；Explorer Shift+Arrow扩选P05.78、SCM基本键盘焦点/hover P05.80已实现。当前片收尾后继续SCM多选/范围与通用列表context；实际表格列resize、完整树分组及原生hover/visual仍待验收。
3. LAY-17/18：P05.72已交付QuickInput输入历史、异步validation、过滤隐藏已选保留与命令面板MRU分节；P05.79已交付通知progress完成/取消状态，P05.54–59已登记步骤/按钮/多选、通知宿主及部分产品错误接线。剩余分级校验、按钮/选择与复杂provider交互、通知timeout及其余当前产品错误/进度接线；业务provider归所属阶段，父行保持开放。
4. LAY-11 与 CMD-06/07：Open Editors 排序/重排/批量动作、Breadcrumb 路径/符号完整导航和 cursor-follow；P05.75已交付版本化Outline层级/过滤/排序/折叠/follow cursor，继续补剩余交互与视觉对照，真实语言provider覆盖归P08，不重复列为全未实现、不关闭父行。
5. LAY-07–10：组移动/复制/顺序/均分/最大化/锁定、same-group split、批量标签与跨组 MRU、复制视图 scroll 状态、pinned/sticky 的剩余 presentation/关闭规则。
6. LAY-04/05/06：通用 view container grouping/split/collapse/reorder，侧栏/Panel 目的地与 pointer DnD，布局和 sash reset/collapse/zoom 恢复。
7. LAY-12/15/20：辅助窗口 tabs/groups 与文档共享、双向/aux间移动复制和关闭恢复，保留用户已选择的 window/group-only focus channel；跨窗滚动、原生焦点/跨应用文件与资源 drop/IME/快捷键完整链路。
8. LAY-01/02/03/13/14/19：完整已支持菜单/Command Center/layout controls/activity context menu，Modal 内容宿主与 lifecycle、Zen/fullscreen/center/zoom/compact、Welcome 普通 editor lifecycle 与 Walkthrough/help。依赖 P06/P07/P08/P13/P14 的业务 provider 不伪造，逐项写明 owning phase 与 P05 宿主合同。
9. CMD-01–12：P05.72–77已分别登记命令面板分节、行列/偏移预览与取消、分页异步Quick Open、版本化Outline、文档符号preview/取消/侧开及异步工作区符号。继续补Quick Access registry与默认命令原子映射、评分/参数/条件、Quick Open侧开/复制/provider快照、位置修饰与符号分组/评分，以及Peek/各类语义导航/层级/Problems/links宿主；多根归P06、真实语言provider归P08、系统URI/可信域安全整合归P14。保持实际provider与mock验证区分，子项done不关闭父行。
10. 阶段验收：全部产品门禁、原子贡献映射覆盖、固定版本同环境视觉/交互/文件结果和资源生命周期证据。原生设备能力不足明确未验证；不能据此标 P05 整体 done。

## 验收账本

每项以 docs/03 status + feature_list evidence + diagnostic report 为准。每个矩阵行最终需列：实现、测试、正常/边界/失败/取消/恢复、各平台结果、截图/diff、剩余差异；普通进度不请求批准，遇到只能由用户决策的外部阻塞再说明。
