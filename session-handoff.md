# session-handoff.md — 会话交接

> Last Updated：2026-10-29（第六十七轮：Windows VS Code idle 对照复跑）

指标口径修正（2026-10-29）：两份同服务 VS Code idle 报告原先对全部 600 个 Private Bytes 样本按数值排序再取最高 40%，这不代表时间尾段。原始采样未变。现按 `tools/mem-probe::summarize` 重算：取时间顺序最后 240 个样本，对这 240 个值排序并取上中位数。首轮稳定值为 1267.18 MiB（尾段起始 t=460.405 s）；新 profile 复跑为 1324.33 MiB（t=466.223 s）。

## 项目一句话

Flutter桌面工作台 + Rust编辑核心，低内存与资源压力下稳定编辑/保存优先。
用户最新要求：执行docs/10中的全功能复刻计划并分阶段提交；P00.1、P00.2、P00.3 已完成，P00.4继续进行。

## Current Objective
macOS 15 Actions run 40647161201 在 HEAD `5da053b` 通过探针 analyze/test、Release build、693-byte Web Archive 同 WKWebView 重载及 Safari Web Inspector 页面级附着；附着截图显示目标页 DOM，原始证据在 `docs/diagnostics/2026-10-28-p00/p00.4-web-macos-run-40647161201/`。Linux Debian sid/WPE run 40616364735 在 HEAD `51fe0cd` 通过 MHTML 回放；sandbox-disable 与 GBM-disable 变量 unset 时观察到 bwrap，但 CI 容器 security label 为 unconfined 且 capabilities 增强，不代表生产安全 profile。Linux 单轮 Xvfb/software-GL 探针销毁+30s private 406.8 MiB、较 WebView 前高117.4 MiB，NetworkProcess 留存；不能据此证明 leak 或满足 docs/04 产品门。旧证据目录：`p00.4-web-linux-run-40616364735/`。

剩余阻塞：真实 DRM Linux 主机 WPE GBM/DMABUF；Microsoft 官方服务 client 身份/许可；最近一次 Windows Alula Rust+RA 前台编辑复跑为 1800.015 秒、150/150 次保存、1815 个样本，Private Bytes 峰值/稳定/最终 841.89/657.93/233.85 MiB；稳定值超 500 MiB 目标 157.93 MiB，6 个观察 PID 在关闭+30 秒后退出，stderr 仍有两条 watcher-path 警告但无非优雅 LSP shutdown 警告。隔离 Microsoft VS Code 1.142.0 + 相同 rust-analyzer 1.97.1 的 idle 对照已复跑两次：首轮稳定 Private Bytes 1267.18 MiB；新 profile 复跑稳定 1324.33 MiB（600样本、783.187秒），13个 PID 关闭+30秒全退；版本仍不匹配固定 Code-OSS。WSLg/Xvfb 主应用 Rust+RA 10 分钟 idle 单轮也已完成，1 GiB cgroup、memory.current 峰值 803.91 MiB、scope PSS 峰值 889.30 MiB、CPU 8.036%、OOM=0；完整产品其他服务与跨平台 docs/04 场景未完成。旧 WSL cgroup 单轮探索：512 MiB 无 RA 单轮可保存，含 RA 的 512 MiB OOM，1 GiB 含 RA 单轮可保存并退出（旧单轮的 Xvfb 在 systemd scope 外，峰值约 861.9 MiB）；成功退出仍打印 `FlutterEngineRemoveView returned kInvalidArguments`。新的 31 次 cgroup 矩阵将 Xvfb、应用与子服务全部纳入 scope：no-RA 256/512/1024 MiB 成功保存关闭 3/4、3/3、3/3；RA 1 GiB 3/3 成功，RA 64–512 MiB 每档 3/3 OOM。no-RA 256 MiB 一次 marker 校验失败保留，另有一次补跑成功。矩阵仅短时 WSLg/Xvfb/software-GL `rust-mini`，仍未完成 docs/04 产品矩阵。新增 1 GiB RA cgroup 长测 1800 秒、150/150 次保存；scope PSS 峰值 924.75 MiB，产品进程树尾部 PSS 中位数 870.53 MiB（高于 500 MiB 目标 370.53 MiB），关闭+30 秒 RA 服务退出；前后 10 分钟中位数增约 13 MiB，尚不能断言稳定，仍有 watcher 与 FlutterEngineRemoveView 告警。证据：`docs/diagnostics/2026-10-29-p00/p00.4-wsl-rust-ra-30m-cgroup-1024-20261028-223917.md` 和 JSON。P00.4 保持 blocked，feat-022/P00 仍 in-progress；P01–P15 不开始。新矩阵：`docs/diagnostics/2026-10-29-p00/p00.4-wsl-main-app-cgroup-matrix.md` 和同名 JSON；旧探索：`docs/diagnostics/2026-10-29-p00/p00.4-wsl-linux-cgroup-interaction.md`。WebKit Inspector Protocol 不等于 CDP，Linux 插件 CDP 标志仍为不支持。下一步先处理真实 DRM/WPE GBM 与 Microsoft 官方服务身份/许可，并推进完整跨平台 docs/04 内存矩阵；同服务 VS Code idle 补充对照已完成，但未匹配固定 Code-OSS 版本，保持 P00.4 blocked，不启动 P01。详情：`docs/diagnostics/2026-10-29-p00/p00.4-wsl-linux-cgroup-interaction.md`。
本轮 GitNexus `detect-changes --scope all` 为 low（48 files / 42 symbols / 0 affected processes）；结果包含工作区既有的 README/app 等代码改动，此次只暂存 17 个 P00.4 证据/状态文件。索引报告 202 flows、404 个入口候选中 204 个未纳入、123 个 callee 跳过、2 次 walk 达预算，因此 0 affected processes 不构成完整无影响证明。
提交 `e0256b2` 已推送；GitHub CI run `40772304233` 全绿：Harness、Ubuntu/Windows Rust fmt/Clippy/tests、Flutter analyze 与 122 项测试通过。CI 不覆盖此处的 cgroup 完整矩阵或真实 DRM/WPE GBM。
本轮证据提交 `c7f0d9b` 已推送至 PR #1；其 GitHub CI run `40791174980`、macOS Web Engine Probe `40791174984`、Linux WPE Web Engine Probe `40791174974` 均通过（Flutter 122 项、Rust Ubuntu/Windows、Harness、WKWebView/Safari、WPE MHTML）。
本机完整 `PATH=/home/vegetable/.cargo/bin:/home/vegetable/develop/flutter/bin:$PATH PUB_CACHE=/tmp/alula-pub-cache bash init.sh` 随后退出 0：Rust tests、Clippy、build_core 与 Flutter 122 项均通过；P00.3 recovery fixture 用时 2:36。
此前一轮前台闭环复跑（2026-10-29）：1800.015 秒、150/150 次保存、1808 个样本，Private Bytes 峰值/稳定/最终值 683.19/661.77/665.47 MiB；稳定值超 500 MiB 目标 161.77 MiB。关闭+30 秒四个观察 PID 均退出，临时 HOME/fixture 清除且前台恢复。报告：`docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-rust-lsp-edit-30m-run2-20261029-011542390.*`。此前 `Code.exe --version` 版本预检意外启动默认 VS Code profile 并初始化应用共享存储；观察到的进程树已停止，但共享存储未检查或回滚，也没有取得对照样本。该记录是当时状态；隔离 VS Code 前台对照已于第六十五轮获授权并完成，见同目录 `p00.4-windows-vscode-rust-lsp-idle.md`。
按用户要求在前台进程意外关闭后再次完整重跑 Windows Rust+RA 编辑验收：1800.011 秒、150/150 次保存、1817 个样本，Private Bytes 峰值/稳定/最终值 846.68/661.44/233.00 MiB；稳定值超 500 MiB 目标 161.44 MiB。marker/hash 通过，关闭+30 秒 4 个观察 PID 均退出，临时 HOME/fixture 删除且前台恢复。报告：`docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-rust-lsp-edit-30m-run3-20261029-043806492.*`。
Windows Git Bash 的完整门禁与 P00.3 fixture 均已复跑通过。WSL stable Rust 1.99.1 与 Flutter stable 3.47.8/Dart 3.13.7 均已原生安装；clang/CMake/Ninja/pkg-config/GTK/libstdc++/Epoxy/libsecret/GBM 开发依赖已安装，`flutter doctor -v` 确认 Linux desktop toolchain 可用（Android SDK 未安装，`eglinfo` 不可用只是诊断信息缺失）。`cargo fmt --check`、完整 `bash init.sh`、`flutter analyze --no-pub` 和 `flutter test --no-pub --concurrency=1` 全部通过，Flutter 122 项全绿。离线 Pub 依赖按锁文件解析，tracked pubspec/lock 未改。完整记录：`docs/diagnostics/2026-10-28-p00/wsl-flutter-validation.md`。root GitHub CI run 40616364863 全绿。
WSL 登录环境中 `bash scripts/build_core.sh` 通过；主应用 `app/` 执行 `flutter build linux --release --no-pub` 时 Flutter 报告没有配置 Linux desktop project，因此没有开始编译。`tools/web-engine-probe/` 有独立 Linux runner 和 WPE CI evidence，但不能代表主应用 Linux build。把主应用 Linux scaffold 作为后续跨平台工作项，当前未新增 `app/linux`。详情同上方诊断记录。跨 OS package-config 恢复后的 `bash init.sh --fast` 日志：`docs/diagnostics/2026-10-28-p00/p00.4-wsl-init-fast-recovery-2026-10-28.log`。
第六十一轮 follow-up 已补齐并追踪 `app/linux`：Release bundle 含 Rust `.so`，6 项 Linux FFI 对拍通过。该 WSLg build 不等于真实 DRM/WPE GBM；cgroup 限额交互和 docs/04 产品长时内存矩阵仍未完成，详见 `docs/diagnostics/2026-10-29-p00/p00.4-wsl-linux-main-runner.md`。
Windows Git Bash 侧 `build_core.sh`、`flutter pub get --enforce-lockfile` 与 `flutter build windows --release --no-pub` 均通过，Release artifact 为 `app/build/windows/x64/runner/Release/alula_app.exe`。锁文件相对 HEAD 只有已有行尾差异，无语义变化。诊断记录已同时列出 Linux 主应用目标缺失。
host triple 选择现已在 WSL 与 Windows Git Bash 两端验证，复制各自 DLL/SO 且不覆盖另一平台库。
Windows `mem-probe` 对当前带既存 app 修改的工作树 Release 做三轮 45 秒空窗口采样，稳态 Private Bytes 中位数 187.46 MiB；最后一轮关闭+30s 后进程数为 0。记录 `docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-current-empty-summary.md`。不等于 docs/04 的完整产品内存验收。
Windows Release `--lsp-auto` 首轮 45 秒采样只有主进程；原因是默认 session 恢复了有效 workspace，使 demo autoFolder 分支跳过。隔离 HOME 后进行了三轮 Rust+RA 样本。数据：`docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-lsp-autostart-attempt.json`。
Windows Rust+RA Release 三轮各 60 秒稳定态 Private Bytes 为 589.84/593.10/588.58 MiB；三轮 600 秒 idle 样本尾部稳定态 589.09/589.27/589.09 MiB，中位数 589.09 MiB，结束值 588.11/590.77/591.70 MiB，均仍比 500 MiB 目标高约 89 MiB。三轮结束+30秒后各四个 PID 均退出。用户确认暂无真实 DRM Linux 主机或获授权的 Microsoft 官方客户端身份。VS Code 1.142.0 + 隔离扩展副本经 PowerShell 最小化和 WSH `SW_SHOWMINNOACTIVE` 两种方式启动都切换前台；安全守卫每次均恢复前台并停止实例，未采集对照数据；临时数据已清理，后续前台对照尚待许可。树含 Alula、两个 `rust-analyzer.exe` 与 proc-macro server；每次启动有两条 watcher path 告警。汇总与原始报告：`docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-rust-lsp-summary.md` 与同目录 JSON/Markdown。已有三轮30分钟脚本编辑数据：稳定 Private Bytes 676.20/672.36/660.81 MiB，中位数672.36 MiB，超500 MiB目标172.36 MiB；每轮150次保存、1,808个样本，关闭+30秒后进程全退。尚无 VS Code 对照及完整产品服务门证据。
当前任务与DoD唯一权威：docs/03当前主线；docs/10为范围/架构/方法，docs/11为需求矩阵。旧Phase/W里程碑只作历史；原型done不继承为1:1完成。
## Verification Update（第六十一轮）

主应用 Linux runner 已新增并纳入源码控制；`flutter build linux --release --no-pub` 成功，bundle 含 `libalula_core.so`。WSL 与 Windows Git Bash 的 `build_core.sh` host 选择均通过；Linux FFI 对拍 6 项通过，`cargo fmt --check`、workspace Clippy、`flutter analyze --no-pub` 和修正后的 `bash init.sh --fast` 均通过（Flutter 122 项）。目前只证明 WSL Linux build/FFI；隔离窗口 UI smoke 与 cgroup 限额交互尚未完成，WSLg 软件渲染不代表 DRM GBM。P00.4 仍 blocked，P01 不启动。证据：`docs/diagnostics/2026-10-29-p00/p00.4-wsl-linux-main-runner.md`。

## Verification Update（第六十轮）

At `5e6e0ce`, WSL `PATH=/home/vegetable/.cargo/bin:/home/vegetable/develop/flutter/bin:$PATH PUB_CACHE=/tmp/alula-pub-cache bash init.sh --fast` passed Rust workspace tests, `build_core`, and all 122 Flutter tests under default parallel execution. One earlier parallel `REF-07-UNDO-01` failure remains unreproduced; isolated and serial runs plus this parallel rerun passed, with root cause unknown.

The authorized branch push completed. GitHub CI run 40758401730 passed (Rust Ubuntu/Windows, Flutter analyze/test, harness); macOS Web Engine Probe run 40758401692 and Linux WPE Web Engine Probe run 40758401773 also passed. The latter two are probe evidence only; Linux used CI Xvfb/software GL and does not prove real DRM GBM/DMABUF. P00.4 remains blocked; a separate isolated VS Code idle-comparator foreground-permission question is pending, and P01 remains not started. Evidence: `docs/diagnostics/2026-10-29-p00/p00.4-cross-platform-validation-followup-20261029.md`.

## What Changed

本轮新增 ABI v5 workspace LSP shutdown FFI：tab close 发 didClose 并保留共享服务；workbench 关闭时对剩余文档执行 didClose、shutdown-response、exit 与有界进程回收。Windows Release 真实 rust-analyzer 已在第五十九轮通过关闭复验；`window_manager` 0.5.2 的 `WM_CLOSE` 需先 `setPreventClose(true)` 并由 `onWindowClose` 发起 shutdown，单靠 widget `dispose()` 不可靠。Flutter analyze、122 项测试与 Release build 全通过。当前稳定 Private Bytes 657.82 MiB，仍高于500 MiB；两条 watcher-path 告警仍在。完整测试使用的 workbench 仍含用户的未提交变更；其中 Ctrl+Click/Git 功能 hunks 保持未暂存。GitNexus `WorkbenchPage`/`AlulaTitleBar` impact 为 LOW，dispose 为 UNKNOWN（5 个接收者调用未解析），并已用文本确认回调路径。详细证据：`docs/diagnostics/2026-10-29-p00/p00.4-lsp-graceful-shutdown.md`。


- 第五十九轮：用户误关前台窗口后完整重跑。先记录一轮 1800 秒有效编辑样本但发现 shutdown 错误，追踪到 Windows `WM_CLOSE` 默认绕开 Flutter disposal；加入 `setPreventClose(true)` 与 `onWindowClose` 处理。Windows analyze/test 122项/Release build 全通过，30秒真实 LSP 冒烟和新 1800.011 秒运行均不再出现非优雅 shutdown 错误。最终 150/150 次保存，1815 个样本，峰值/稳定/最终 Private Bytes 798.17/657.82/232.52 MiB；6 个 PID 关闭+30秒全退，HOME/fixture 清理、marker/hash 和前台恢复通过。两条 watcher-path 警告仍在，稳定内存超标 157.82 MiB，P00.4 继续 blocked。证据已登记到 docs/03、progress.md 与 `docs/diagnostics/2026-10-29-p00/p00.4-lsp-graceful-shutdown.md`。
- WSL package config 用 `/tmp/alula-pub-cache` 离线恢复；Rust workspace tests 与 core build 通过。并行 `init.sh --fast` 的 Flutter suite 曾有一次 `REF-07-UNDO-01` 文件内容错配；单项重跑和完整 `flutter test --concurrency=1`（122项）通过，根因未定位。Windows 默认并行 122 项亦通过。

- 第五十七轮：响应用户要求完整重跑此前前台进程意外关闭的 Windows Rust+RA 流程。1800.015 秒内 150/150 次编辑保存、1808 个一秒样本；Private Bytes 峰值/稳定/最终值 683.19/661.77/665.45 MiB。32 个快照中尾部逐进程中位数为主 rust-analyzer 429.00 MiB、Alula 226.94 MiB、launcher 3.05 MiB、proc-macro 2.88 MiB。最终 SHA/marker 校验通过，四个观察 PID 关闭+30 秒退出，fixture/HOME 已清理，前台已恢复。watcher-path 与非优雅 LSP shutdown 警告仍在；无产品源代码修改，P00.4 继续 blocked。证据已登记到 docs/03、progress.md 和 Rust+RA summary。

- 第五十六轮：按用户要求从启动、1800 秒编辑、关闭到清理完整重跑 Windows Rust+RA 隔离验收。150/150 次保存、1808 个内存样本，稳定 Private Bytes 657.55 MiB（高于 500 MiB 目标 157.55 MiB）。32 个快照中的末 40% 逐进程中位数为主 rust-analyzer 427.02 MiB、Alula 223.49 MiB、launcher 3.05 MiB、proc-macro 2.86 MiB。最终 SHA/marker 校验通过，4 个观察 PID 关闭+30 秒退出，临时目录清除、前台恢复。watcher-path 与非优雅 LSP shutdown 警告仍在。PowerShell parse、`cargo fmt --check`、完整 `bash init.sh`（Rust tests、Clippy、core build、Flutter 122 tests）和 `flutter analyze` 全部通过；没有改 app/ 或 crates/ 产品代码。P00.4 继续 blocked，P01 不启动。详细数据见 docs/03 与 Rust+RA summary。

- 第五十五轮：在此前三轮之外另完成一次 30 分钟隔离编辑，150 次保存、1809 个一秒 mem-probe 样本。全树稳定 Private Bytes 660.29 MiB，仍超过 500 MiB 160.29 MiB。32 个 PID 级快照显示尾部主 rust-analyzer 428.68 MiB、Alula 227.75 MiB，RA launcher 3.14 MiB，proc-macro server 2.88 MiB。关闭+30 秒所有观察 PID 退出；LSP graceful shutdown 仍未证实。PowerShell 解析及脚本运行通过；完整原始路径列于 progress.md 与 docs/03。P00.4 继续 blocked，P01 不启动。

- 第五十四轮：Windows Rust+RA 三轮30分钟编辑在同一Release/fixture/`--lsp-auto` 配置下完成，150次保存/轮，稳定 Private Bytes 中位数672.36 MiB（目标500 MiB）；关闭+30秒观察到所有 PID 退出，但 RA stderr 有非优雅关闭警告。两次失败重试不计入样本，最终 run3 改用 Ctrl+S 并通过。WSL原生 `bash init.sh --fast` 与完整 `bash init.sh` 均退出0。GitNexus 在最终状态更新后重建索引；detect-changes all/staged 均为 risk=low（0 条受影响流程）；all 范围也包含工作区未暂存的 app/、README 等修改。阶段提交只含 P00.4 文档、诊断和测试脚本。process graph 仍截断，缺失流程不能视为无影响证明。详见 `docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-rust-lsp-summary.md` 与 `p00.4-windows-alula-rust-lsp-edit-interrupted-attempts.md`。


- 第五十一轮：WSL `bash init.sh --fast` 通过 Rust workspace tests、`build_core` 和 Flutter 122 项测试。独立 rust-analyzer 1.97.1 LSP 初始化复现 watcher path 告警，定位为 rust-analyzer stderr；notify-rs 错误条件提示失败 watch path 缺失或非文件/目录，但路径未确认。WSL Windows-interop `RA_LOG=trace` 尝试未完成握手；已停止隔离进程。没有改产品代码。证据：`docs/diagnostics/2026-10-28-p00/p00.4-windows-ra-notify-warning.md`。

- 第五十轮：VS Code 同服务对照安全预检发现 PowerShell 最小化和 WSH `SW_SHOWMINNOACTIVE` 启动都会切换前台；前台守卫两次均恢复原窗口，隔离实例已退出，临时 profile/扩展副本已删除，未进行 10 分钟采样。VS Code 1.142.0 与锁定的 Code-OSS 1.145.0-dev 有版本差异。30 分钟 Alula 编辑实测的前台测试请求待用户回复；VS Code 对照也需要另行取得前台测试许可。证据：`docs/diagnostics/2026-10-28-p00/p00.4-vscode-rust-lsp-preflight.json`。

- 第四十九轮：Windows Rust+RA 第三轮 10 分钟 idle 采样完成，峰值/尾部稳定态/结束 Private Bytes 为 608.72/589.09/591.70 MiB。三轮 idle 稳态中位数 589.09 MiB，仍超 500 MiB 目标 89.09 MiB；没有观察到 idle 增长。关闭+30秒复查本轮四个 PID 均已退出，隔离 HOME 已清理。用户确认暂无真实 DRM Linux 主机或获授权的 Microsoft 官方客户端身份。30 分钟编辑与同服务 VS Code 对照仍未完成。原始数据：`docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-rust-lsp-idle-run3.json`、`.md`。

- 第四十八轮：Windows Rust+RA 第二轮 10 分钟 idle 采样完成，600 个一秒样本的尾部稳定态为 589.27 MiB、结束值 590.77 MiB，较首轮 idle 稳态只高 0.18 MiB，仍超过 500 MiB 目标 89.27 MiB。关闭+30秒复查四个 PID 均已退出，隔离 HOME 已清理。用户确认暂无真实 DRM Linux 主机或获授权的 Microsoft 官方客户端身份；第三轮 idle 采样进行中。原始数据：`docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-rust-lsp-idle-run2.json`、`.md`。

- 第四十六轮：刷新 GitNexus 索引后确认默认 Windows profile session 会跳过 `--lsp-auto` fixture；隔离 HOME 让 Rust+RA 真正启动。三轮 60 秒 Release 进程树稳定态 Private Bytes 中位数 589.84 MiB，高于 500 MiB 目标；重复出现 watcher path 告警。末轮关闭+30 秒后 Alula/RA/proc-macro 均退出。完整范围限制见 Rust+RA summary；长时编辑/idle、VS Code 对照、DRM 与官方服务门仍未完成。

- 第四十五轮：修复 WSL 共享生成态 `.dart_tool/package_config.json` 的跨 OS Pub Cache URI 后，`bash init.sh --fast` 通过 Rust tests、build_core、Flutter 122 项 tests（跳过 Clippy）。Windows Release `--lsp-auto` 45 秒进程树采样只有 `alula_app.exe`，未观察到 rust-analyzer 子进程；不算 Rust+LSP 内存证据，根因未确认。详见 `docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-lsp-autostart-attempt.md`。P00.4 其余外部/完整内存门仍未通过。

- 第四十四轮：Windows 当前工作树主应用 Release 做三轮空窗口 45 秒进程树采样；稳态 Private Bytes 中位数 187.46 MiB，末轮关闭+30s 后未见残留进程。此样本不覆盖完整功能/长时编辑，不关闭 P00.4 内存门。
- 第四十三轮：Windows Git Bash 下主应用 Release build 成功。首次构建因生成的 Windows plugin links 缺失而失败；随后锁文件强制模式的 `flutter pub get` 成功并生成链接，重跑 Release build 通过。没有改产品源文件。
- 第四十二轮：在 WSL 完成 core build；主应用 Linux Release 构建检查发现没有 Linux desktop project 配置，因此将 Linux runner scaffold 留作后续跨平台阶段。独立 WPE probe 有 Linux runner。没有修改产品代码。
- 第四十一轮：WSL ext4 安装 Flutter stable 3.47.8/Dart 3.13.7 和 Linux desktop 开发依赖；`flutter doctor -v` 的 Linux toolchain 检查通过。Rust 格式、workspace tests、Clippy、build_core、Flutter analyze 与 122 项 test 全通过。P00.3 大文本恢复夹具的 2,000,001 UTF-16 单元观测符合既有 current-state fixture；没有改产品代码或测试。P00.4 仍 blocked，P01 不启动。详见 `docs/diagnostics/2026-10-28-p00/wsl-flutter-validation.md`。
- 第四十轮：macOS run 40647161201 在 HEAD `5da053b` 通过 Safari Web Inspector 页面级附着，窗口标题匹配归档页，截图显示目标 DOM；probe analyze/test、Release build、Web Archive replay 全通过。证据已保存于 `docs/diagnostics/2026-10-28-p00/p00.4-web-macos-run-40647161201/`。Safari Inspector 子项通过，但完整产品内存、真实 WPE GBM 与官方服务身份/许可仍阻塞 P00.4。
- 第三十九轮：WSL 安装 GBM development header 并补足本地账号 `video`/`render` 设备组；uid 1000 `card0` GBM buffer/dma-buf 导出成功，render node buffer ioctl 失败；GBM EGL 只有 llvmpipe surfaceless GLES、无 pbuffer GLES2 config。未运行 WPE，真实硬件 DRM 主机门槛仍开放。WSL Rust fmt/tests/clippy/editor-core release build 全部通过；1.58 GB Linux Flutter SDK 未下载完成。

- 第三十七轮：Linux run 40616364735 和 macOS run 40616364760 在 HEAD `51fe0cd` 均通过 probe analyze/test、Release build 与 WebArchive/MHTML 回放；Linux WPE 默认 sandbox 环境变量未关闭，观察到 bwrap，但容器 security label=unconfined、capabilities 增强。Linux 单轮 destroy+30s 为 406.8 MiB private（较 WebView 前+117.4 MiB），不满足 docs/04；root CI 40616364863 全绿。原始 artifacts 已归档，P00.4 仍 blocked。
- 第三十六轮：修复 Linux WPE CI 缺少插件要求的 legacy FDO development package，加入 `libwpebackend-fdo-1.0-dev` 并记录实际 pkg-config 后端；`bash -n`、`git diff --check` 通过，提交并推送 `e853999`。macOS 15 Actions run 40614141265 的 Web Archive replay 通过，title/marker 正确，`archiveParsed=true`；证据在 `p00.4-web-macos-run-40614141265/`。Linux run 40614659876 仍在执行，P00.4 保持 blocked。
- 第三十五轮：重新核对当前 Microsoft VS Code FAQ 与 Settings Sync 官方文档，确认 Marketplace fork 限制和 Sync 专用服务/不支持自定义后端；更新 `p00.4-services-evidence.json` 与 ADR。没有登录或服务写操作。P00.4 外部阻塞未解除；macOS 分支推送授权仍待用户答复。
- 第三十四轮：Windows Git Bash 从 WSL 调用 `bash init.sh --fast` EXIT=0（Rust tests、build_core、Flutter 122 项）；同一 WPE probe 连做十轮 no-capture F5 生命周期，第十轮 destroy+30s 比基线多81.20/83.63 MiB private/PSS，父进程映射类别持续增长但不能证明泄漏。证据见 `p00.4-linux-wpe-multi-cycle-evidence.json`。
- 第三十三轮：UID 1000 未插桩 WPE smaps 生命周期采样在 destroy+30s 观察到 +40.90 MiB private/+43.23 MiB PSS；父进程 heap、WPE 文件页和匿名映射均有驻留增量，但无法判断 live allocation 或具体分配 owner。sandbox/GBM 关闭，单轮诊断不满足 docs/04；原始快照与限制见 `p00.4-linux-wpe-parent-smaps-evidence.json`。
- 第三十二轮：为独立WPE探针增加无截图自动生命周期模式并通过离线 analyze/test 与 Linux Release build。Heaptrack 1.4.0 的单轮插桩样本在销毁+30s时父进程比该轮基线高98.2/101.7 MiB private/PSS；一个51.25 MiB峰值栈走过插件初始化与 software `swrast_dri.so`，另一93.52 MiB峰值调用点未解析。插桩开销与peak/leak统计限制见 evidence JSON；仍不足以归因未插桩约40 MiB残留，P00.4 blocked。

- 第三十一轮：三轮无截图/MHTML F5 创建销毁复验，destroy+30s Private Bytes/PSS中位数比空载高40.2/42.5 MiB；WebProcess退出、NetworkProcess留存，父进程残留未归因。仅探针级，P00.4仍blocked，见 p00.4-linux-wpe-manual-f5-repeat-run1/至run3/。
- 第三十轮：Windows Git Bash 完整门禁通过；Flutter 122 项、Rust tests、Clippy、build_core、cargo fmt --check 与 flutter analyze 全绿。2,000,001 UTF-16 fixture 2:11。WSL fast 门禁失败为 runner/挂载问题，见 docs/diagnostics/2026-10-27-p00/p00-full-validation-windows-gitbash-2026-10-28.log。
- 第二十九轮：Windows Git Bash 重跑 P00.3 build_core、Flutter 两项 risk fixtures 和两个 Rust integration tests，四项全通过，恢复 fixture 2:10；输出 p00.3-windows-gitbash-rerun-2026-10-28.log。同一 WPE 2.52.6 source-built probe 连续三轮自动采样，并补一轮不触发截图/MHTML 的手动 F5 创建/销毁；无截图 TMPDIR 为空，WebProcess 销毁后退出、NetworkProcess 保留，父进程仍有约 42 MiB Private Bytes 增量。P00.4 继续 blocked，汇总为 p00.4-linux-wpe-memory-repeat-evidence.json。
- 第二十八轮：WPE 2.52.6 Remote Inspector target multiplexing session 成功调用 Runtime.enable/Runtime.evaluate，返回 title 与 marker；CDP 仍不支持。Xvfb 诊断禁用 sandbox/GBM；记录见 p00.4-linux-wpe-inspector-protocol-evidence.json 与 p00.4-linux-wpe-2.52.6-inspector-protocol-run/。
- 第二十七轮：复核当前分支在 origin 无对应引用；GitHub 当前只列出 CI、Release，查询 macOS workflow 返回默认分支 404。没有推送或 dispatch；macOS runner 未运行。证据：docs/diagnostics/2026-10-27-p00/p00.4-macos-dispatch-preflight.json。

- 第二十六轮：按启动流程检查 GitNexus fresh；当前 WSL `bash init.sh --fast` 因 Cargo 缺失与挂载 Flutter shell CRLF 失败，Windows Git Bash 完整门禁已有通过记录。WPE Debian 12 容器映射 `/dev/dxg`、render node、render GID 992 与 WSLg Wayland socket 后能连接 socket，但 EGL 返回 `EGL_NOT_INITIALIZED`、无 GLES2 config；直接 GBM API 打开 render node 后 `gbm_create_device` 返回 null、没有 buffer；没有运行 WebView。原 WPE 容器未改，临时快照镜像已清理，日志见 `p00.4-linux-wpe-wslg-d3d12-run/wayland-egl.log`。P00.4 仍 blocked。
- 第二十五轮：WSLg EGL surfaceless probe 在 `GALLIUM_DRIVER=d3d12` 下成功创建 GLES context，renderer 为 `D3D12 (AMD Radeon(TM) Graphics)`。WPE 2.52.6 快照容器映射 `/dev/dxg` 与 DRM devices、GBM enabled、software GL unset 时，Flutter EGL context 未创建，WPEWebProcess crash，90 秒内未到 initial-loaded；容器 X11 `:0` 可连接但 EGL_NOT_INITIALIZED。未获得 WPE GBM/DMABUF 证据，属于当前 Debian Mesa/WSLg integration failure，不是 WPE 支持结论。临时 GBM probe 也因缺 Mesa DRI drivers 而不确定。WSL shell 无 `cmd.exe`；P00.3 四个 fixture 与 Windows Git Bash 门禁已有第二十三轮通过记录，本轮没有冒称重跑。未改产品或原 WPE 容器，临时镜像已删除。证据：`docs/diagnostics/2026-10-27-p00/p00.4-linux-wpe-wslg-d3d12-run/`、`p00.4-wslg-egl-evidence.json`。
- 第二十四轮：在 WPE 2.52.6 source build 的 Flutter Linux/WPE 探针上配置 loopback `WEBKIT_INSPECTOR_HTTP_SERVER=127.0.0.1:9231`；target list 列出 `Alula Web Probe`，`Main.html` HTTP 200、2,680 bytes。页面/MHTML/销毁回放退出码 0。运行显式禁用 sandbox 与 GBM；只证明 Remote Inspector HTTP target discovery/frontend bootstrap 可用，未证明 Inspector command session，也不支持 CDP。更正“Linux Inspector 不支持”为“WPE native endpoint 可用、插件静态 capability=false、命令交互未验证”。P00.4 仍 blocked，P01 未启动。证据见 `p00.4-linux-wpe-inspector-evidence.json` 与 `p00.4-linux-wpe-2.52.6-inspector-http-run/`。
- 本轮 Windows Git Bash `bash init.sh --fast` EXIT=0，Flutter 122 项测试通过。
- 第二十三轮：按用户选择的 Windows Git Bash 重跑 P00.3 `build_core`、Flutter fixture 与两个 Rust fixture 命令；四项夹具全部通过，输出与既有记录一致，超大文档用例约 2 分 03 秒。WPE 旧首屏的 732,160 个 RGBA 像素均透明；插件只复制当前缓冲。独立探针改为 DOM 查询前检查标题蓝色像素并有界重试。analyze/test/Linux Release build 通过，三次新的默认 sandbox 冷启动均取得 initial/MHTML 截图，最终版本的一次回放第 2 次截图才得到目标帧。P00.4 仍 blocked，未动产品代码。证据见 `p00.4-linux-wpe-evidence.json` 与三个 `p00.4-linux-wpe-2.52.6-frame-poll-run*/`。
  提交前 Windows Git Bash `cargo fmt --check`、完整 `bash init.sh`、单独 `app/ flutter analyze` 均 EXIT=0；完整脚本覆盖 Rust workspace tests、Clippy、build_core 和 Flutter 122 项测试。
  GitNexus `detect-changes` all risk=medium（91 files/14 symbols/1 flow，含既有 workbench 变更），staged risk=medium（62 files/4 symbols/1 flow，Build→`_hasProbeHeadingPixel`）；无 HIGH/CRITICAL。流程图截断提示 190 个入口候选未入选、123 个 callee 因预算跳过、2 次 walk 达预算，不能把缺失 flow 作为无影响证据。
- 第二十二轮：以 `--cap-add SYS_ADMIN --security-opt seccomp=unconfined` 本地容器复测默认 WebKit sandbox；探针用户 UID 1000、sandbox-disable 环境变量 unset、GBM disabled。`unshare` 成功，bwrap/WebProcess 进程可见，MHTML 重载截图通过；初始 DOM marker 虽通过，首帧 PNG 背景空白。延迟 500ms/2s 未修复，探针源码保持原状。证据见 `p00.4-linux-wpe-2.52.6-default-sandbox-run/`。

- P00.4 实验1：独立 Flutter Windows CodeForge 11.3.0 探针通过真实 Microsoft Pinyin composition/commit/cancel/Latin 输入；4 个 widget tests 覆盖 composition undo、Delta 多光标插入/撤销与 10k 行视口。见 p00.4-editor-adr.md 与 p00.4-editor-evidence.json。CodeForge 仅保留为 P03 候选。
- P00.4 实验2：Windows Flutter/WebView2、Linux WebKitGTK 原生 GTK 与 WPE、macOS WKWebView Web Archive probe 均有运行证据；各 API 的边界不等于跨平台 CDP/MHTML。macOS runner 40616364760 与 Linux WPE runner 40616364735 均已通过；Safari Web Inspector 附着仍需单独实测。证据见 p00.4-web-adr.md、p00.4-web-macos-run-40614141265/、p00.4-web-evidence.json、p00.4-linux-webkitgtk-evidence.json 及 p00.4-linux-webkitgtk-run/。
- P00.4 实验3：固定 Code-OSS 产品配置与本机 Microsoft VS Code 1.142.0 Stable 产品配置对照；官方文档确认 Settings Sync 不支持自定义后端，Marketplace 不允许 Code-OSS fork。未登录、未注册 OAuth 应用、未调用 Marketplace API、未创建隧道。见 p00.4-services-adr.md、p00.4-services-evidence.json。
- 第十五轮复核：固定 SHA 与 1.145.0 官方 Insiders URL 仍 404，latest 返回 1.144.0 不同 revision；Marketplace fork 禁止与 Sync 无自定义后端政策保持。Linux 插件路线为 v6.2 beta + 独立 WPE 包；当前 Ubuntu WSL 无 Linux Flutter/Dart 与 WPE dev SDK。证据补充在 reference-acquisition.md、p00.4-web-adr.md、p00.4-services-adr.md。
- 第十七轮：重验 pinned commit 下载 URL 与官方 CLI 的 1.145.0 版本解析 GET 均为 404；微软维护的 `vscode-test` helper 与 VS Code CLI 更新实现使用同一 commit URL，公开官方路径没有发现可替代的固定版本端点。该结果不覆盖所有内部/企业发行渠道，记录在 `reference-acquisition.md`。
- 第十七轮：新增隔离 macOS Flutter 工程、WKWebView Web Archive 保存/同 view 重载验证、页面标记输出、`footprint -targetChildren` 采样脚本及 macOS 15 GitHub Actions runner。它们尚未在 Mac 执行，不是平台通过证据；Safari Web Inspector 附着仍是独立手动步骤。细节见 `p00.4-web-adr.md`、`tools/web-engine-probe/README.md` 与 `.github/workflows/p00-web-engine-macos.yml`。
- 第十八轮：新增 Flutter Linux runner、Debian sid WPE 构建 workflow、Xvfb replay 与 `mem-probe` 采样；锁定插件 beta 6.2.0。Windows Git Bash analyze/test/Release build 与 WebView2 CDP/MHTML 自动回放通过；新增 1,438-byte MHTML、截图与五阶段内存 JSON。Linux workflow 尚未运行，静态契约显示其 WPE 插件没有 CDP handler，Inspector 标志不支持 Linux。详见 `p00.4-linux-wpe-evidence.json`、`p00.4-web-beta-evidence.json` 与 `p00.4-web-adr.md`。
- 第十八轮收尾：Windows Git Bash `bash init.sh` EXIT=0，Rust workspace tests、clippy、build_core 与 Flutter 122 项测试通过；恢复夹具的 2,000,001 UTF-16 输入在约 2 分钟后完成，输出仍为预期的磁盘 5 单元恢复结果。Git Bash 启动时 `.bashrc` 编码告警但不影响命令成功。
- 第十八轮 GitNexus `detect-changes --scope all` 为 risk=low（61 files/58 symbols/0 flows），staged scope 为 risk=low（32 files/42 symbols/0 flows）；all 包含用户原有工作区改动。两个结果均未报告 partial/truncated，但索引过程图本身有截断：186 flows、208 个入口候选未纳入、98 个 callee 被跳过、2 次 walk 达预算；缺失流程不视为无影响。
- 第十九轮：在本地临时 sid 包环境跑 Flutter 3.47.8 / Dart 3.13.7 的 `flutter analyze` 与 `flutter test`，均通过。Release 构建在 `flutter_inappwebview_linux 0.1.0-beta.1` 的 `WPE_SETTING_DISABLE_ANIMATIONS` 未定义错误处失败；WPE 2.54.2 头文件提供 `WPE_SETTING_REDUCED_MOTION`。未修改插件源码或增加编译兼容宏，无 Xvfb runtime replay。证据见 `p00.4-linux-wpe-build.log` 与 `p00.4-linux-wpe-evidence.json`。
- 第二十轮：WPE 官方 2.54 migration notes 确认旧动画 setting 已替换；pub.dev 当前只发布 Linux beta.1。Debian Trixie 2.48.3 的 FDO fallback 在混合容器中仍因 `webkit_web_view_get_theme_color` 未声明而构建失败。没有宏或插件源码补丁，无 runtime；证据见 `p00.4-linux-wpe-trixie-compat.log` 与更新后的 Web ADR。
- 第二十一轮：官方 WPE 2.52.6 release 源码在 Bookworm 临时容器以 WPEPlatform/Headless/MHTML 配置构建成功，Flutter probe Release build 与 Xvfb MHTML/PNG/destroy replay 通过。容器不允许 bwrap namespace，因此关闭 sandbox；GBM/DMA-BUF 路径不提供截图像素，设置 `WEBKIT_DMABUF_RENDERER_DISABLE_GBM=1` 后软件缓冲回放通过。完整构建参数、警告、内存数据和边界见 `p00.4-linux-wpe-2.52.6-build.md` 与 `p00.4-linux-wpe-2.52.6-run/`。
- 本轮 `mem-probe` Linux Release build 成功；探针 `flutter pub get/analyze/test/build linux --release` 均退出码 0。脚本现在兼容 source-installed WPE pkg-config 记录，并把 sandbox/GBM overrides 写入环境证据。
- P00.4 仍 blocked：macOS、官方服务身份/许可、Linux 默认 sandbox/硬件渲染/CDP/Inspector 未解决；P01 仍 not-started。无 `app/`、`crates/` 或产品依赖改动。
- 本轮 GitNexus reindex：201 flows；188 个入口候选未进入排名、123 个 callee 因分支预算跳过、2 次 walk 达预算；缺失 flow 不视为无影响。提交前 detect-changes all risk=low（37 files/33 symbols/0 processes），staged risk=low（8 files/17 symbols/0 processes）。
- 首次 Linux CMake 配置还发现缺少 `libsecret-1-dev`，已加入 Linux workflow 和 README 依赖清单。临时容器以 Bookworm 衍生镜像为基础安装 sid 包，OS 文件报告 `forky/sid`，不等同于干净的 `debian:sid`。
- GitNexus 在 Flutter 生成文件出现后重建为 up-to-date。`WebEngineProbePage` impact 为 LOW（1 个直接调用、0 流程）；CMake 文件目标为 UNKNOWN，文本确认本轮只补构建依赖。提交前 `detect-changes --scope all` risk=low（38 files/34 symbols/0 processes），staged risk=low（9 files/18 symbols/0 processes）。索引仍有流程截断：186 flows、208 个入口候选未纳入、98 个 callee 被跳过、2 次 walk 达预算，缺失 flow 不视为无影响。
- 收尾 Windows Git Bash `bash init.sh --fast` 与完整 `bash init.sh` 均 EXIT=0；另行执行 `cargo fmt --check` 和 Flutter `analyze` 也通过。完整脚本覆盖 Rust tests、Clippy、core DLL 构建与 Flutter 122 项测试；2,000,001 UTF-16 单元恢复夹具约 2 分钟完成。
第十七轮 GitNexus staged `detect-changes` 为 risk=medium（37 files/20 symbols/5 flows），五条受影响流程均在隔离 Web Probe 的 build、导出、重载、销毁与自动回放；all scope 还包含工作区用户既存改动。`_toggleWebView` impact 为 HIGH，该方法的状态文案改动已撤回；`State.build` impact 为 UNKNOWN，确认是 Flutter 覆写后按动态回调路径人工审阅。其余探针回放方法 impact 为 LOW。分析器报告的 process graph truncation 仍存在。
- 第十六轮完成 Windows Git Bash `cargo fmt --check && bash init.sh`，退出码 0；单独 Flutter `analyze` 也为 0（No issues found）。完整门禁覆盖 Rust workspace tests、core 构建、clippy 零警告和 Flutter 122 项测试；RECOVERY-01 接受 2,000,001 UTF-16 单元后仍只从磁盘恢复 5 单元，现状故障夹具保持预期。
- 第十六轮仅更新进度/交接文档，没有修改 `app/`、`crates/` 或产品依赖。用户工作区中原有的未提交修改继续保持未暂存、未纳入提交。
- 本轮 GitNexus `detect_changes` all/staged 均 risk=low；staged 为 5 个文档文件、0 条受影响流程。结果对象无 `partial`/`truncated` 字段；索引流程图本身仍截断（187 flows，406 个入口候选丢弃 206 个、98 个 callee 跳过、2 次 walk 达预算）。
- P00.4 标记 blocked；feat-022/P00 保持 in-progress。没有改动 app/ 或 crates/ 产品代码。

- 固定vscode SHA 4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e（1.145.0开发版，非Stable）；
  vscode-docs SHA da213552439825628e0ab958dbde1e413dbc36bf。
- 总计划16实施包，342条功能族验收/14边界决策；另有源目录/全部90个非AI产品manifest及下载预置调试器清单。
- P00.2 exporter从固定 SHA 的 14,811 个 tracked TS/JS 文件中解析 1,490 个候选源文件，导出 AST、95 个扩展 manifest、`product.json` 和隔离运行时 registry，共 12,958 条唯一记录；2,140 条为运行时独有登记。
- 当前保留 6,828 条未决登记/路由，不能计作覆盖率。运行时探针观测 2,684 个命令、1,289 个配置键、5 种语言；client-only lane 未加载默认扩展 payload，运行时产品扩展数为 0。
- 默认随附扩展全部纳入；终端/JS调试/Markdown rich-Mermaid/Notebook宿主/集成浏览器/Sync/Cloud Changes/Ports不漏。
  外接AI排除；需用户另装的Python/Jupyter/Remote等业务provider不冒充默认能力。
- 官方服务互通是条件验收，不能因联网删需求；自建替代不等于官方1:1完成。
- 旧未完成feature保留evidence并退回not-started/legacy；新执行轨为vscode-builtin-parity，单feature推进。
- Startup发现原工作树Flutter编译错误，按规则仅一行修复_findRenderEditableOf递归误调；impact LOW。

## Verification Evidence

- P00.3：Windows Git Bash `bash init.sh --fast` EXIT=0、`bash init.sh` EXIT=0、`cargo fmt --check` EXIT=0、`flutter analyze` EXIT=0。完整门禁包含 Rust workspace tests、clippy 零警告、build_core 与 Flutter 122 项测试全绿。
- 四个夹具均实际运行：UNDO-01 两份 Alula 文档各自撤销时互相串写；RECOVERY-01 接受 2,000,001 UTF-16 单元但恢复为磁盘 5 单元；CLOSE-01 文档关闭后 workspace LSP 仍活着；SLOW-01 provider 延迟与调用方等待均为 1,200ms。
- 固定 Code-OSS 1.145.0 / Electron 43.8.3 的隔离实例验证双文件 undo 每个文档恢复自己的原始文本。参考行为输出与 Alula 观测见 `p00.3-current-state.json`。
- 页面证据：`reference-workbench.png` 与真实 Alula `alula-welcome.png`。窗口均 1505×1005、DPR 1.25、深色；Alula 画面为中文，固定参考为英文，未声称文字级视觉一致。
- GitNexus `detect-changes --scope all`：43 files/40 symbols/3 flows，risk=medium，来自其它既存工作区改动；staged scope：14 files/24 symbols/0 flows，risk=low，仅有 characterization fixtures、fake LSP、证据与状态文档。隔离索引报告 process graph 截断，缺失 flow 不作无影响证明；详见 `p00.3-replay.md`。
- 更早的 WSL 直接运行失败是 runner 不兼容，不是产品测试失败；最终 Windows Git Bash 的全量 DoD 已通过。早期输出保留在 `p00.3-validation.log`（ignored，本轮退出码以以上可重放命令为准）。
- P00.4 探针：Windows Git Bash `flutter analyze` EXIT=0、`flutter test` EXIT=0（1 项）、Windows Release build EXIT=0；详见 web evidence。根目录 `cargo fmt --check`、`bash init.sh`、单独的 `flutter analyze` 均 EXIT=0，完整 Flutter 测试通过（122 项）。
- GitNexus 索引更新后执行完整 `detect-changes --scope all`，结构化结果无 `partial`/`truncated`：107 files / 271 symbols / 17 flows，risk=critical；staged scope 为 78 files / 255 symbols / 17 flows，risk=critical。staged 受影响流程都落在独立探针的 Flutter Win32Window 生命周期模板或 Web 自动回放，没有 app/ 或 crates/ 产品代码；全量 scope 还包含用户既存工作区改动，未纳入阶段提交。Analyzer 的 process graph 仍有截断（187 flows；393 个候选入口中 193 个未入选、98 个 callee 被跳过、2 次 walk 达到预算）；缺失 flow 不视作无影响。
- 本轮 `bash init.sh --fast` EXIT=0；新增 GTK runner `bash -n`、Python `py_compile` 和完整相对路径重放均 EXIT=0，九阶段证据齐全。MHTML 每次生成边界不同，页面截图字节一致，MHTML MIME 头与页面标记重放一致。
- 第十六轮 `cargo fmt --check && bash init.sh` EXIT=0，单独 Flutter `analyze` EXIT=0；完整门禁包含 Rust 测试、clippy、core 构建与 Flutter 122 项测试。
- 第十七轮根目录 Windows Git Bash `cargo fmt --check && bash init.sh` EXIT=0；单独主应用 Flutter `analyze` EXIT=0（No issues found）。探针 `dart format`、Flutter `analyze`、`flutter test` 均 EXIT=0；Mac 编译/执行未运行。Mac runner Bash 脚本 `bash -n` 与 workflow YAML 解析通过。
- 本轮 GitNexus `detect_changes` 的 all 与 staged scope 均为 risk=high；staged scope 覆盖 22 个文件与 8 条受影响流程，八条均为 GTK 探针生命周期/采样路径。结果对象没有 `partial`/`truncated` 字段；索引构建日志报告 process graph 被截断：187 flows，406 个入口候选丢弃 206 个，98 个 callee 跳过，2 次 walk 达预算。all scope 同时涵盖未暂存用户改动。
- 本轮没有 app/ 或 crates/ 产品实现变更；Linux WebKitGTK 证据作为 P00.4 scoped follow-up 提交，不把 GTK/WebView 证明写成产品能力；其它既存工作区改动不纳入提交。

## Blockers / 待核实前提

- P00.1：2026-10-28 重验官方 `latest/insider` 指向 1.144.0 的其他 revision token `abc2b20cb3e724689f78f5d2a3c231589b25483c`；固定 SHA 与 1.145.0 下载路径仍 404。Code-OSS client-only build/start 已完成；remote 子树依赖未安装，Copilot/remote lane 未构建；不能把此源码构建称作微软发行物。
- P00.2：client-only 运行时没有加载随附扩展 payload；静态 95 个 manifest 与运行时 0 个产品扩展的差异保留。6,828 条未决记录和候选映射必须在后续逐项复核，不计为已覆盖。
- P00 需固定参考的 Microsoft 同 SHA 发行物尚不可得；Code-OSS 与微软发行配置差异不能抹平。
- P00.4 实验1只在 Windows 验证；macOS/Linux IME、Rust 往返/背压、Release 内存、完整 Unicode/EOL 与无障碍仍未验证。
- P00.4 实验2：Linux 原生 WebKitGTK 的 MHTML/快照/Inspector/单轮内存已有 WSLg 证据；WPE 2.52.6 source build/Xvfb MHTML replay 通过。默认 sandbox 后续在 Docker `SYS_ADMIN` + `seccomp=unconfined` 配置、UID 1000 下运行，sandbox-disable 变量 unset，进程树观察到 bwrap/WPEWebProcess；旧的无等待首帧 PNG 全透明，MHTML 重载截图通过；后续探针在 DOM 查询前轮询页面标题蓝色像素，三次默认 sandbox 回放都呈现初始页与 MHTML 页面，最终版有一次重试。GBM 硬件仍关闭；WPE 2.54.2 Release 与 Trixie 2.48.3 FDO 构建仍失败；所选 beta 插件静态声明 CDP 与 Inspector 不支持 Linux。docs/04 长时多轮内存协议仍未实测；macOS WKWebView/Web Archive/Safari Inspector 和内存仍未实测。
- P00.4 实验3：官方 FAQ 明确 Marketplace 不允许 Code-OSS fork 访问，Microsoft 扩展许可限定 VS family；Settings Sync 不支持自定义后端。本地正式版 1.142.0 产品身份字段不属于固定 1.145.0 Code-OSS 参考。需解决许可/产品身份边界才可声称官方服务 1:1。
- 原Windows .gitnexus元数据在WSL路径无效。本轮隔离索引位于/tmp/alula-plan-gitnexus，不修改原缓存；
  使用 GITNEXUS_STORAGE_ROOT=/tmp/alula-plan-gitnexus node .gitnexus/run.cjs ... 。缓存临时丢失可重建。
  代码图谱process发现可能截断，缺失flow不等于无调用；UNKNOWN先做文本确认。

## Files

- docs/10-VSCode无插件全功能复刻总计划.md、docs/11-VSCode功能对照矩阵.md、docs/plans/：新计划及官方源证据。
- docs/diagnostics/2026-10-27-p00/reference-acquisition.md：P00.1固定参考获取与下载探测记录。
- docs/diagnostics/2026-10-27-p00/atomic-contributions.md：P00.2统计、运行时差异和未决项；`atomic-contributions.json` 是逐项 ledger。
- docs/diagnostics/2026-10-27-p00/p00.3-replay.md、`p00.3-environment.json`、`p00.3-current-state.json`、`alula-welcome.png`：P00.3门禁、环境、现状夹具输出与页面基线。
- app/test/p00_risk_fixtures_test.dart、crates/editor-core/tests/p00_workspace_close.rs、crates/editor-lsp/tests/p00_slow_completion.rs：四个现状风险复放测试及专用 fake LSP。
- tools/vscode-parity/export-atomic-contributions.mjs、runtime-probe/：P00.2可重放导出器和临时探针。
- docs/diagnostics/2026-10-27-p00/p00.4-editor-adr.md、p00.4-editor-evidence.json 与 tools/editor-ime-probe/：P00.4实验1决策、数据、重放探针及真机截图。
- docs/diagnostics/2026-10-27-p00/p00.4-web-adr.md、p00.4-web-evidence.json、MHTML/PNG/进程树采样与 tools/web-engine-probe/：P00.4实验2及 Windows 子实验。
- docs/diagnostics/2026-10-27-p00/p00.4-web-linux-run-40616364735/ 与 docs/diagnostics/2026-10-28-p00/p00.4-web-macos-run-40647161201/：通过的 Linux WPE/MHTML 与 macOS WKWebView/Web Archive/Safari Inspector workflow 原始输出和结构化证据。
- tools/web-engine-probe/lib/main.dart、tools/web-engine-probe/README.md、docs/diagnostics/2026-10-27-p00/p00.4-linux-wpe-parent-heaptrack-evidence.json 与 p00.4-linux-wpe-parent-heaptrack-run3/：WPE 无截图自动生命周期模式、Heaptrack 原始 trace 与单轮父进程峰值分配路径探查。
- docs/diagnostics/2026-10-27-p00/p00.4-linux-wpe-parent-smaps-evidence.json 与 p00.4-linux-wpe-parent-smaps-run1/：UID 1000 未插桩生命周期的父进程 `/proc/smaps` 映射快照和分类汇总。
- docs/diagnostics/2026-10-27-p00/p00.4-linux-wpe-multi-cycle-evidence.json 与 p00.4-linux-wpe-multi-cycle-run1/：单个 probe 进程十次 WPE WebView 创建/销毁后的 maps/smaps 生命周期采样。
- docs/diagnostics/2026-10-27-p00/p00.4-web-beta-evidence.json、p00.4-web-beta-run/、p00.4-linux-wpe-evidence.json、p00.4-linux-wpe-build.log 与 p00.4-linux-wpe-trixie-compat.log：当前 beta Windows 兼容性复跑及两种 Linux WPE API 组合的构建阻塞证据。
- docs/diagnostics/2026-10-27-p00/p00.4-linux-wpe-2.52.6-build.md、p00.4-linux-wpe-2.52.6-run/、p00.4-linux-wpe-2.52.6-default-sandbox-run/、三个 p00.4-linux-wpe-2.52.6-frame-poll-run*/ 与 p00.4-linux-wpe-2.52.6-inspector-http-run/：WPE 2.52.6 源码构建、Flutter Release/Xvfb replay、首帧有界轮询、Remote Inspector HTTP target discovery、MHTML/PNG、sandbox 进程及单轮内存证据；明确记录临时 sandbox/GBM overrides。
- .github/workflows/p00-web-engine-linux.yml、tools/web-engine-probe/linux/ 与 scripts/run-web-smoke-linux.sh：Linux WPE Debian sid CI workflow 40616364735 已通过 Xvfb MHTML 回放；本地 source-build 及历史失败/修复 run 证据保留。
- docs/diagnostics/2026-10-27-p00/p00.4-linux-wpe-inspector-evidence.json：WPE Remote Inspector HTTP target/frontend endpoint 回放与限制。
- docs/diagnostics/2026-10-27-p00/p00.4-linux-webkitgtk-evidence.json、p00.4-linux-webkitgtk-run/ 与 tools/web-engine-probe/linux/：P00.4 Linux WebKitGTK 原生引擎补充及可重放 GTK 探针。
- docs/diagnostics/2026-10-27-p00/p00.4-services-adr.md、p00.4-services-evidence.json：P00.4实验3端点、正式版配置差异、Marketplace/Sync 阻塞。
- docs/diagnostics/2026-10-28-p00/wsl-rust-validation.md：WSL stable Rust 安装校验、Linux Rust 检查及 Windows Git Bash 完整门禁复验。
- docs/diagnostics/2026-10-28-p00/wsl-flutter-validation.md：WSL 原生 Flutter 版本、锁文件依赖解析与完整跨语言门禁结果。
- docs/diagnostics/2026-10-28-p00/wslg-gbm-egl-evidence.json：WSLg faux DRM GBM buffer/dma-buf 与 llvmpipe EGL/GLES 能力复测；不作为硬件 WPE/GBM 验收。
- docs/diagnostics/2026-10-29-p00/p00.4-wsl-linux-cgroup-interaction.md 与 `p00.4-wsl-linux-cgroup{512-save-run4,1024-run1}`、`p00.4-wsl-linux-rust-lsp-cgroup512-run2`：主应用 WSLg/Xvfb 下 512 MiB 无 LSP 保存、512 MiB Rust Analyzer OOM 和 1 GiB Rust Analyzer 保存探索；不是完整限额矩阵。
- docs/03：新P00–P15状态/依赖/DoD；docs/09与README标历史范围与新入口。
- feature_list.json、progress.md、本文件：可续作状态。
- app/lib/workbench/workbench_page.dart：本轮仅_findRenderEditableOf中递归调用一行；其余既存修改归用户。
- docs/diagnostics/2026-10-27-parity-plan/：验证日志。

## Next Session

1. 按 AGENTS 启动流程重读状态并检查 GitNexus freshness。WSL Rust 与 Flutter 工具链、Windows Flutter Windows Release 构建均有本地验证；完整 `bash init.sh`、独立 Flutter analyze 和串行 test 已全绿，可避免重复全量 recovery fixture，除非代码变化要求复验。
2. P00.4 剩余门槛：真实 DRM 主机 WPE GBM/DMABUF、官方服务身份/许可，以及完整产品多服务/跨平台预算。Windows Rust+RA 最近一次30分钟编辑稳定态657.93 MiB，超过500 MiB预算157.93 MiB；隔离 VS Code 1.142 idle 对照已完成，但未匹配固定 Code-OSS 版本，也未覆盖编辑负载。
3. 主应用 `app/linux` runner 已建立。WSLg/Xvfb smoke 已运行；512 MiB 无 LSP 单轮保存通过，Rust Analyzer 512 MiB OOM、1 GiB 单轮保存通过。下一步若继续预算探索，应补齐各档至少三轮与 30 分钟编辑/10 分钟 idle 的产品进程树采样；记录中的 FlutterEngineRemoveView warning 仍需归因。真实 DRM/WPE GBM 仍需外部主机。P00.4 未满足全部跨平台与内存门，完成 P00 前不启动 P01。Linux CDP 仍不支持，WPE Inspector Protocol 不等于 CDP。
4. 后续阶段提交只暂存该阶段证据与状态文件；保留用户既有 app/、harness 等未提交变更。

## 已知风险（尚未因本轮计划而修复）

全局UndoStack跨文档风险；>2M字符未保存内容不入journal；同步FFI与800ms全量轮询；
Tree-sitter Rust-only/全文parse；lsp_stop仅detach；watcher全事件重读；快速打开/搜索硬上限。
详见docs/10 §2，不把静态风险冒充已运行复现。


## Next Session 首步

1. 先运行 `node .gitnexus/run.cjs detect-changes --scope all --repo .`，审阅并只暂存本阶段文件；保留既有用户工作区改动。
2. 需要继续内存门时，按 docs/04 对 64/128/256/512/1024 MiB 各档至少跑三轮，并加入长时 idle/edit、进程树与 Windows Job Object 场景；当前 WSL cgroup 的 idle/edit 数据仍是单轮探索。
3. 同服务 VS Code idle 补充对照已完成，但仍未覆盖固定 Code-OSS 版本与编辑负载；真实 DRM WPE GBM/DMABUF、Microsoft 官方身份/许可和完整产品内存门仍需解决。P00 未签收前不启动 P01。


## Verification Update（第六十七轮）

- 按用户授权重跑隔离 Windows VS Code + rust-analyzer idle 对照。新建空 user-data/shared-data，复用隔离 rust-analyzer 0.3.3089 副本，server 为 1.97.1；采集 600 个样本、783.187 秒，Private Bytes 峰值/时间尾段40%上中位/最终 1651.25/1324.33/1322.04 MiB，末 Working Set 1539.75 MiB。一次启动焦点切换已恢复，之后未再切换；关闭+30秒 13 个 PID 全退。临时 profile/shared-data 和运行副本已清理。详细证据及参数化脚本见 `docs/diagnostics/2026-10-28-p00/p00.4-windows-vscode-rust-lsp-idle-rerun-20261029-002522.*` 与同目录 timestamped log。
- 对照结果仍是 Microsoft VS Code 1.142.0 Stable，不是固定 Code-OSS 1.145.0-dev，且只覆盖 idle；Windows Alula Rust+RA 编辑稳态仍超 500 MiB，P00.4/feat-022 blocked/in-progress。真实 DRM/WPE GBM/DMABUF、官方服务身份/许可及完整 docs/04 跨平台矩阵未完成；P01 不启动。本轮未改产品代码。

## Verification Update（第六十六轮）

- Windows Alula Rust+RA 前台编辑完整复跑通过：1800.015 秒、150/150 次保存、1815 个样本；Private Bytes 峰值/稳定/最终 841.89/657.93/233.85 MiB，稳定值超 500 MiB 目标 157.93 MiB。marker/hash 通过、6 个观察 PID 关闭+30 秒全部退出、HOME/fixture 清理并恢复前台；仅有两条 watcher-path 告警，无非优雅关闭告警。
- 用户授权的 Windows VS Code 同服务 idle 对照完成：600 个样本、实际 759.872 秒、峰值/稳定/最终 Private Bytes 1655.61/1267.18/1265.46 MiB。隔离实例使用相同 rust-analyzer 1.97.1；一次启动期前台切换已恢复并记录，采样期间未再切换。与 Alula 的同服务对照仍是补充证据，因为 VS Code 1.142.0 不等于 pinned Code-OSS 1.145.0-dev。
- WSLg/Xvfb 主应用 + Rust Analyzer 10 分钟 idle 单轮通过：600 秒无输入，1 GiB/swap=0，memory.current 峰值 803.91 MiB、scope PSS 峰值 889.30 MiB、单核归一 CPU 8.036%，OOM=0；关闭+30 秒 RA/proc-macro 全退。
- P00.4/feat-022 继续 blocked/in-progress：Alula 稳态内存超目标，真实 DRM/WPE GBM/DMABUF、官方服务身份/许可和完整产品跨平台压力矩阵未完成；P01 不启动。当前轮未改产品代码。
- WSL 启动基线重验：以现有 Windows Pub Cache 离线恢复依赖后，`bash init.sh --fast` 的 Rust tests、`build_core`、Flutter 122 项全通过；`flutter pub get --enforce-lockfile` 未改 tracked pubspec/lock。
- Windows Alula run3 进程归因从活动 JSON 重算：尾部13组快照的 rust-analyzer server/Alula/launcher/proc-macro 中位数425.05/226.11/3.21/2.86 MiB；同时间点 Private Bytes 树总量中位数657.38 MiB。若服务器 footprint 不变，500 MiB 预算给 Alula 留约68.88 MiB；这是估算，不是不可优化的结论。明细：`docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-rust-lsp-edit-30m-run3-20261029-065714888-process-breakdown.md`。
- P00.4/feat-022 继续 blocked/in-progress：Rust+RA 稳态超目标，真实 DRM/WPE GBM/DMABUF、官方服务身份/许可和完整产品跨平台矩阵未完成；不删减 LSP 能力、不调整预算，P01 不启动。
