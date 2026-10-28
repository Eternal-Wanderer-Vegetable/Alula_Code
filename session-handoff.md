# session-handoff.md — 会话交接

> Last Updated：2026-10-28（第五十轮：VS Code 同服务对照前台安全预检）

## 项目一句话

Flutter桌面工作台 + Rust编辑核心，低内存与资源压力下稳定编辑/保存优先。
用户最新要求：执行docs/10中的全功能复刻计划并分阶段提交；P00.1、P00.2、P00.3 已完成，P00.4继续进行。

## Current Objective
macOS 15 Actions run 40647161201 在 HEAD `5da053b` 通过探针 analyze/test、Release build、693-byte Web Archive 同 WKWebView 重载及 Safari Web Inspector 页面级附着；附着截图显示目标页 DOM，原始证据在 `docs/diagnostics/2026-10-28-p00/p00.4-web-macos-run-40647161201/`。Linux Debian sid/WPE run 40616364735 在 HEAD `51fe0cd` 通过 MHTML 回放；sandbox-disable 与 GBM-disable 变量 unset 时观察到 bwrap，但 CI 容器 security label 为 unconfined 且 capabilities 增强，不代表生产安全 profile。Linux 单轮 Xvfb/software-GL 探针销毁+30s private 406.8 MiB、较 WebView 前高117.4 MiB，NetworkProcess 留存；不能据此证明 leak 或满足 docs/04 产品门。旧证据目录：`p00.4-web-linux-run-40616364735/`。

剩余阻塞：真实 DRM Linux 主机 WPE GBM/DMABUF；Microsoft 官方服务 client 身份/许可；按 docs/04 对完整产品执行三轮 1/10/30 分钟及关闭+30s 进程树预算验收。P00.4 保持 blocked，feat-022/P00 仍 in-progress；P01–P15 不开始。WebKit Inspector Protocol 不等于 CDP，Linux 插件 CDP 标志仍为不支持。
Windows Git Bash 的完整门禁与 P00.3 fixture 均已复跑通过。WSL stable Rust 1.99.1 与 Flutter stable 3.47.8/Dart 3.13.7 均已原生安装；clang/CMake/Ninja/pkg-config/GTK/libstdc++/Epoxy/libsecret/GBM 开发依赖已安装，`flutter doctor -v` 确认 Linux desktop toolchain 可用（Android SDK 未安装，`eglinfo` 不可用只是诊断信息缺失）。`cargo fmt --check`、完整 `bash init.sh`、`flutter analyze --no-pub` 和 `flutter test --no-pub --concurrency=1` 全部通过，Flutter 122 项全绿。离线 Pub 依赖按锁文件解析，tracked pubspec/lock 未改。完整记录：`docs/diagnostics/2026-10-28-p00/wsl-flutter-validation.md`。root GitHub CI run 40616364863 全绿。
WSL 登录环境中 `bash scripts/build_core.sh` 通过；主应用 `app/` 执行 `flutter build linux --release --no-pub` 时 Flutter 报告没有配置 Linux desktop project，因此没有开始编译。`tools/web-engine-probe/` 有独立 Linux runner 和 WPE CI evidence，但不能代表主应用 Linux build。把主应用 Linux scaffold 作为后续跨平台工作项，当前未新增 `app/linux`。详情同上方诊断记录。跨 OS package-config 恢复后的 `bash init.sh --fast` 日志：`docs/diagnostics/2026-10-28-p00/p00.4-wsl-init-fast-recovery-2026-10-28.log`。
Windows Git Bash 侧 `build_core.sh`、`flutter pub get --enforce-lockfile` 与 `flutter build windows --release --no-pub` 均通过，Release artifact 为 `app/build/windows/x64/runner/Release/alula_app.exe`。锁文件相对 HEAD 只有已有行尾差异，无语义变化。诊断记录已同时列出 Linux 主应用目标缺失。
Windows `mem-probe` 对当前带既存 app 修改的工作树 Release 做三轮 45 秒空窗口采样，稳态 Private Bytes 中位数 187.46 MiB；最后一轮关闭+30s 后进程数为 0。记录 `docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-current-empty-summary.md`。不等于 docs/04 的完整产品内存验收。
Windows Release `--lsp-auto` 首轮 45 秒采样只有主进程；原因是默认 session 恢复了有效 workspace，使 demo autoFolder 分支跳过。隔离 HOME 后进行了三轮 Rust+RA 样本。数据：`docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-lsp-autostart-attempt.json`。
Windows Rust+RA Release 三轮各 60 秒稳定态 Private Bytes 为 589.84/593.10/588.58 MiB；三轮 600 秒 idle 样本尾部稳定态 589.09/589.27/589.09 MiB，中位数 589.09 MiB，结束值 588.11/590.77/591.70 MiB，均仍比 500 MiB 目标高约 89 MiB。三轮结束+30秒后各四个 PID 均退出。用户确认暂无真实 DRM Linux 主机或获授权的 Microsoft 官方客户端身份。VS Code 1.142.0 + 隔离扩展副本经 PowerShell 最小化和 WSH `SW_SHOWMINNOACTIVE` 两种方式启动都切换前台；安全守卫每次均恢复前台并停止实例，未采集对照数据；临时数据已清理，后续前台对照尚待许可。树含 Alula、两个 `rust-analyzer.exe` 与 proc-macro server；每次启动有两条 watcher path 告警。汇总与原始报告：`docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-rust-lsp-summary.md` 与同目录 JSON/Markdown。没有 30 分钟脚本编辑、VS Code 对照及完整产品服务门证据。
当前任务与DoD唯一权威：docs/03当前主线；docs/10为范围/架构/方法，docs/11为需求矩阵。旧Phase/W里程碑只作历史；原型done不继承为1:1完成。
## What Changed

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
- docs/03：新P00–P15状态/依赖/DoD；docs/09与README标历史范围与新入口。
- feature_list.json、progress.md、本文件：可续作状态。
- app/lib/workbench/workbench_page.dart：本轮仅_findRenderEditableOf中递归调用一行；其余既存修改归用户。
- docs/diagnostics/2026-10-27-parity-plan/：验证日志。

## Next Session

1. 按 AGENTS 启动流程重读状态并检查 GitNexus freshness。WSL Rust 与 Flutter 工具链、Windows Flutter Windows Release 构建均有本地验证；完整 `bash init.sh`、独立 Flutter analyze 和串行 test 已全绿，可避免重复全量 recovery fixture，除非代码变化要求复验。
2. P00.4 剩余门槛：真实 DRM 主机 WPE GBM/DMABUF、官方服务身份/许可，以及 docs/04 完整产品的三轮 1/10/30 分钟多场景预算采样和 VS Code 对照。Windows Rust+RA 已有三轮 1 分钟与单轮 10 分钟 idle exploratory evidence；10 分钟稳态仍约 589 MiB，且没有 30 分钟编辑。
3. 主应用 `app/` 的 Linux desktop runner 未配置；`flutter build linux --release --no-pub` 在编译前失败。将 scaffold 排在 docs/03 跨平台阶段，P00 完成前不启动 P01。独立 WPE probe 有 Linux runner 与 CI evidence。分支 `codex/vscode-parity-p00` 的推送授权已执行；Linux CDP 不支持，WPE Inspector Protocol 不能作为 CDP 等价。
4. 后续阶段提交只暂存该阶段证据与状态文件；保留用户既有 app/、harness 等未提交变更。

## 已知风险（尚未因本轮计划而修复）

全局UndoStack跨文档风险；>2M字符未保存内容不入journal；同步FFI与800ms全量轮询；
Tree-sitter Rust-only/全文parse；lsp_stop仅detach；watcher全事件重读；快速打开/搜索硬上限。
详见docs/10 §2，不把静态风险冒充已运行复现。


## Next Session 首步

1. 阅读 `docs/diagnostics/2026-10-28-p00/p00.4-windows-alula-rust-lsp-summary.md` 和 10 分钟 raw report；设计隔离 fixture 的脚本化 30 分钟编辑采样，并补 VS Code 同场景对照，避免修改用户 profile/workspace。
2. P00.4 其余真实 DRM WPE GBM/DMABUF、官方服务身份/许可门保持待解；docs/04 完整产品预算仍未验收，不启动 P01。
