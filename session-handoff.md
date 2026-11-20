# Session Handoff

Last Updated: 2026-11-20

## Current Objective

完成草稿 PR #3 的全部范围内任务，再向用户汇报。按 docs/03 一次推进一个 P05 子项。P05.110 / feat-162 已完成。P05.111 / feat-163 的前置依赖已满足。

## Current State

- 产品 `3ed5f8d244790a5b8db1e0de3ae161216eb2a23d` 已推草稿 PR #3。toast 右键与通知中心键盘菜单实机开启，Escape 关闭。组件层核对含中文、Emoji、CRLF 的原文写入、焦点恢复、Delete 不受影响。专项 69/69，完整 Flutter 1,600 passed / 2 skipped，Rust fmt、工作区测试、Clippy、核心库和 Flutter analyze 通过。同一 SHA 的 PR CI 44691943586 四项及 Platform Availability 44691935212 Windows/Linux 通过。macOS 实机验收暂缓。证据 docs/diagnostics/2026-11-20-p05/p05.110-notification-copy-text.md。
- 产品 `630f42bbd16e6749e24bd96ce8e019a7f6bdb046` 已推草稿 PR #3。toast 和通知中心共用绑定当前条目的次级操作菜单。Windows 11 125% DPI 实机记录两次选择各一次回调，Escape 取消无回调，Enter 能重开。菜单到期、撤出、错误和进度保护经专项 60/60 验证。完整 Flutter 1,598 passed / 2 skipped，Rust fmt、工作区测试、Clippy、核心库和 Flutter analyze 通过。同一 SHA 的 PR CI 44688759654 四项及 Platform Availability 44688750790 Windows/Linux 通过。macOS 实机验收暂缓。详见 docs/diagnostics/2026-11-20-p05/p05.109-notification-secondary-actions.md。
- 产品 `a8ae00621f360db2e6acb0592f798642e09b5be4` 已推 PR #3。Windows 11 125% DPI 同样本对照：三处锚点侧距 8、顶或底距 36，toast 间距 4，外框宽 452 对照固定版 451.6，位置按钮 24 × 24。三种位置的铃铛打开中心、退出码 0。专项 48/48，完整 Flutter 1,595 passed / 2 skipped，Rust fmt、工作区测试、Clippy、核心库和 Flutter analyze 通过。同一 SHA 的 PR CI 44685832926 四项及 Platform Availability 44685826609 Windows/Linux 通过。中心总高差 7.4，留待中心密度复验；macOS 实机验收暂缓。证据 docs/diagnostics/2026-11-20-p05/p05.108-notification-modern-geometry.md。
- 产品 `9573dd41f5e299d62088f0014a89c0ec4c127a8e` 已推草稿 PR #3。通知 UI 和编辑器绘制定向 39/39，Dart analyze、Rust fmt、完整 bash init.sh 通过，Flutter 1,595 passed / 2 skipped。Windows 11 125% DPI 开着 Rust 编辑器时三种位置的铃铛均可打开中心，修复前共享画布覆盖标题栏。最终精确 SHA 的 PR CI 44683449380 四项及 Platform Availability 44683443277 Windows/Linux 通过。固定版几何差异由 P05.108 跟踪，macOS 实机验收暂缓。证据 docs/diagnostics/2026-11-20-p05/p05.107-notification-position.md。
- 独立 WSL 工作树 `/home/vegetable/.codex/worktrees/pr3-20261119`。推送前 fetch 并检查 PR 分支 `codex/vscode-parity-p05` 可快进。原 Windows 工作区包含既有未提交改动。
- 产品 `91488d11bb6464e9df3afa01d7ae0aef747cb222` 已推 PR #3。在同一 Windows 11 x64 桌面以 125% DPI 复拍固定 Code-OSS、Alula 基线和修复版。中心和 toast 共用宽度与右下锚点，最新 toast 在上，普通消息默认单行，展开状态跨两表面继承，来源与操作同行，进度条移到底部。可见填充宽度由 336.8 / 377.6 统一为 447.2 逻辑像素。通知与键位专项 104/104，本地全量 Flutter 1,591 passed / 2 skipped。精确 SHA 的 CI 44676516275 四项及 Platform Availability 44676509667 Windows/Linux 通过。采集时 macOS 托管 job 仍在 Flutter 测试。macOS 实机验收继续暂缓。详见 docs/diagnostics/2026-11-20-p05/p05.106-notification-visual-parity.md。
- P05.105 收尾 `17d43c8` 的 CI 四项通过。[P05.105 收尾 CI](https://github.com/Eternal-Wanderer-Vegetable/Alula_Code/actions/runs/44671559130)
- 跨窗焦点消息按既有约定仅包含窗口、组和修订序号。[P05.99 证据](docs/diagnostics/2026-11-19-p05/p05.99-auxiliary-focus-native-smoke-scope.md)

## Blockers / Limits

macOS 实机验收暂缓。固定版实机对照覆盖默认右下与深色样本。三种位置的 Windows 实机验证已完成。P05.108 已校准固定版本的三处锚点和 toast 间距。中心总高、标题栏按钮横向顺序仍有视觉差异。单条更多操作已通过本地、Windows 实机与托管验收。复制文本已通过本地、Windows 菜单与托管验证。全局及按来源请勿打扰等 LAY-18 行为继续按矩阵追踪。

## Files

`app/lib/workbench/notification_widgets.dart`、`app/test/notification_ui_test.dart` 和 [P05.110 证据](docs/diagnostics/2026-11-20-p05/p05.110-notification-copy-text.md)。

## Next Session First Step

核对 P05.110 文档收尾 CI，然后按 docs/03 继续 P05.111 全局请勿打扰规则。
