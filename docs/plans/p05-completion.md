# P05 连续完成目标与执行顺序

2026-11-17 用户明确要求：整体完成 P05，中间无需停止报告。按 docs/03 N.2 与 docs/11 的 LAY-01–20、CMD-01–12 逐行完成；PR #3 保持 OPEN/DRAFT，不合并。既有 child done 不等于整行 done，不以占位、mock provider、generic DnD 或其他 OS 替代真实结果。

## 执行约束

一次只推进一个产品 feature；调研/评审可服务于当前阶段盘点。单片实现→定向/全量→图谱→提交→hosted→证据登记后继续下一项。500 MiB 数值目标后置；数据安全、资源上限与退出清理持续生效。原 E:/Alula_Code 和 E:/temp/alula-pr3-p05 脏工作区保留。

## 剩余交付顺序

1. P05.70 hosted closeout（当前产品 231e853、证据 76113f6）：PR CI 全绿、Linux/Windows 全绿；等待 macOS package/launch/native Quit。随后恢复唯一 active feature。
2. LAY-16：Explorer tree find/filter，固定 Ctrl/Cmd+Alt+F/F3，Highlight/Fuzzy 默认、Filter/Contiguous 切换、Escape/tree focus、查询记忆、祖先可见与 unloaded descendants、取消/错误/无结果；补通用列表 keyboard/range/context 与实际表格列 resize。
3. LAY-17/18：QuickInput 真正输入历史/异步 validation/MRU 分节/按钮与选择状态，通知 timeout/progress 完成/取消和产品错误接线。
4. LAY-11 与 CMD-06/07：Open Editors 排序/重排/批量动作、Breadcrumb 路径/符号完整导航和 cursor-follow、Outline 层级/过滤/排序/折叠。
5. LAY-07–10：组移动/复制/顺序/均分/最大化/锁定、same-group split、批量标签与跨组 MRU、复制视图 scroll 状态、pinned/sticky 的剩余 presentation/关闭规则。
6. LAY-04/05/06：通用 view container grouping/split/collapse/reorder，侧栏/Panel 目的地与 pointer DnD，布局和 sash reset/collapse/zoom 恢复。
7. LAY-12/15/20：辅助窗口 tabs/groups 与文档共享、双向/aux间移动复制和关闭恢复，保留用户已选择的 window/group-only focus channel；跨窗滚动、原生焦点/跨应用文件与资源 drop/IME/快捷键完整链路。
8. LAY-01/02/03/13/14/19：完整已支持菜单/Command Center/layout controls/activity context menu，Modal 内容宿主与 lifecycle、Zen/fullscreen/center/zoom/compact、Welcome 普通 editor lifecycle 与 Walkthrough/help。依赖 P06/P07/P08/P13/P14 的业务 provider 不伪造，逐项写明 owning phase 与 P05 宿主合同。
9. CMD-01–12：Quick Access registry/命令面板/快速打开全文件可达/行列语法/符号 picker preview/取消侧开/工作区符号/Peek/各类语义导航/层级/Problems/links 逐原子项补齐；保持实际 provider 与 mock 验证区分。
10. 阶段验收：全部产品门禁、原子贡献映射覆盖、固定版本同环境视觉/交互/文件结果和资源生命周期证据。原生设备能力不足明确未验证；不能据此标 P05 整体 done。

## 验收账本

每项以 docs/03 status + feature_list evidence + diagnostic report 为准。每个矩阵行最终需列：实现、测试、正常/边界/失败/取消/恢复、各平台结果、截图/diff、剩余差异；普通进度不请求批准，遇到只能由用户决策的外部阻塞再说明。
