# progress.md — 项目进度跟踪

> agent 会话状态文件：每完成一项工作就追加记录。任务权威分解在 `docs/03`，
> 功能状态机在 `feature_list.json`，本文件记录「何时、做了什么、证据是什么」。

## Current State（当前状态，2026-10-28 P00 执行）

用户目标变更为：按现有 **Flutter + Rust** 栈，对固定版本VSCode默认无需用户安装扩展的
全部非外接AI功能与界面做1:1复刻。计划已完成，P00.1已完成，P00总包继续执行，**产品完整复刻未实施**。
当前唯一状态/DoD见docs/03新主线；计划在docs/10、逐项功能族在docs/11。
旧原型可复用，但done不继承为新等价验收；未完成旧项保留证据并退回not-started/legacy。
P00.1 固定 SHA 源码/发行物与构建路径、P00.2 原子贡献/运行时注册项导出器、P00.3 Golden 基线与现状故障夹具均已完成；2026-10-28 Windows Git Bash 复跑的四项 P00.3 命令与完整门禁全部通过。P00.4 三项实验均有 ADR 与证据：编辑器 Windows 探针完成；Web 有 Windows Flutter/WebView2（stable 6.1.5 原始结果与 beta 6.2.0 兼容性复跑）、Linux WebKitGTK 原生 GTK，以及 Flutter/WPE 2.52.6 源码构建后的 Xvfb MHTML/截图/销毁回放；基线回放依赖隔离容器关闭 WebKit sandbox 与 GBM；后续在 Docker `SYS_ADMIN` + `seccomp=unconfined`、UID 1000 下运行，sandbox-disable 变量保持 unset，采样含 bwrap/WPEWebProcess，原始无等待首帧 PNG 为全透明缓冲；插件截图 API 只复制当前像素缓冲、不等 WPE 帧回调。隔离探针现于 DOM 查询前轮询页面标题蓝色像素，三次默认 sandbox 冷启动均取得初始页与 MHTML 截图，最终版本一次重试后通过。此为探针级时序处理，不提供产品层帧同步保证；本地回放关闭 GBM，后续 CI 虽将 GBM-disable 变量 unset 但使用 Xvfb/software GL，硬件 GBM 仍未验证。Debian sid WPE 2.54.2 设置 API 不兼容和 Trixie 2.48.3 FDO WebKit API 缺失仍是发行包阻塞；Linux CDP 不支持；WPE 2.52.6 Remote Web Inspector HTTP target discovery/Main.html (HTTP 200) 与 WPE Inspector protocol command session 已验证；经 Target.sendMessageToTarget 调用 Runtime.enable/Runtime.evaluate 并返回页面 title/marker，Linux CDP 仍不支持；WSLg 宿主在 `GALLIUM_DRIVER=d3d12` 下成功创建 D3D12 EGL/GLES context；临时 Debian GBM probe 因缺 DRI driver 返回 null，不能推断 WPE GBM。随后 WPE 2.52.6 快照容器映射 WSLg 设备、GBM enabled 且 software GL unset 时，Flutter EGL context 失败、WPEWebProcess crash、90 秒内未到 initial-loaded；WSLg X11 :0 与 Wayland socket 的容器 EGL 检查都返回 EGL_NOT_INITIALIZED；Wayland socket 可连接但无 GLES2 config；直接 WPE 镜像 GBM probe 打开 render node 后 `gbm_create_device` 返回 null。记录在 `p00.4-linux-wpe-wslg-d3d12-run/` 与 `p00.4-wslg-egl-evidence.json`；这属于当前环境集成失败，WPE GBM 仍未验证。macOS WKWebView Web Archive 已由 macOS 15 runner 验证保存与同一视图重载（693 bytes，title/marker 正确，archiveParsed=true）；Safari Web Inspector 附着与 docs/04 产品内存仍未验证。官方服务实验发现 Marketplace 与 Code-OSS fork 的明确政策阻塞。P00.4 标记 blocked；feat-022/P00 仍 in-progress。2026-10-28 三轮 WPE 自动生命周期采样与三轮无截图 F5 复跑显示销毁+30s仍有残留，中位数见第三十一轮；这些探针样本不满足 docs/04 DoD。Heaptrack 单轮插桩峰值路径见第三十二轮。第三十三轮以 UID 1000 未插桩 smaps 复测得到 +40.9 MiB private/+43.2 MiB PSS；父进程 `[heap]`、WPE WebKit 文件映射与匿名映射驻留增加，但仍无法判断 live object、分配器保留或具体 owner，不能据此判定泄漏。P00.4 继续 blocked；同一 WPE 探针10轮创建/销毁后，第10轮 destroy+30s 比初始高81.2 MiB private/83.6 MiB PSS，匿名映射持续增加且有回落，不能证明泄漏或 owner；P01仍受P00依赖约束。

2026-10-28 WSLg GBM follow-up：`libgbm-dev` 已安装，普通 uid 1000 可在 WSLg faux DRM 的 `card0` 分配/导出 GBM dma-buf；GBM EGL 无 GLES2 pbuffer config，surfaceless context 使用 llvmpipe 软件渲染。未运行 WPE，不满足硬件 GBM 验收；完整数据在 `docs/diagnostics/2026-10-28-p00/wslg-gbm-egl-evidence.json`。WSL Rust fmt/tests/clippy/release build 复验全通过；Flutter Linux SDK 未装，Flutter 门禁仍由 Windows Git Bash runner 承担。

## 今日会话（2026-10-28 第三十九轮）：WSL GBM/EGL 依赖与能力复测

- WSL 安装 `libgbm-dev=25.2.8-0ubuntu0.24.04.4`，将当前账号加入 `video` 与 `render`；以刷新后的 uid 1000 进程复测，card0 dumb buffer/dma-buf 成功，render node dumb-buffer ioctl 仍失败。
- 在 GBM EGL display 上创建 surfaceless GLES2 context 后，renderer 报告 `llvmpipe (LLVM 20.1.2, 256 bits)`；无 GLES2 pbuffer config，确认该 WSLg 路径是软件渲染，不能替代真实 DRM 主机的 WPE GBM/DMABUF 验收。未运行 WPE，也未改 feature 状态。
- WSL Rust fmt、workspace tests、clippy 与 `editor-core` release build 再次全部通过。完整版 Flutter Linux SDK 下载约 1.58 GB，当前镜像连接慢且被 Ubuntu X11 header 下载阻塞，因此没有安装；Flutter 完整门禁继续使用已通过的 Windows Git Bash runner。
- 证据：`docs/diagnostics/2026-10-28-p00/wslg-gbm-egl-evidence.json`、`docs/diagnostics/2026-10-28-p00/wsl-rust-validation.md`。P00.4 仍 blocked，feat-022/P00 仍 in-progress，P01 不启动。

## 今日会话（2026-10-28 第三十八轮）：WSL Rust 工具链与跨 runner 门禁复验

- WSL 安装 rustup stable 1.99.1、rustfmt 与 clippy；rustup-init SHA-256 对照官方 checksum 文件通过。WSL `cargo fmt --check`、`cargo test --workspace --locked`、`cargo clippy --workspace --all-targets --locked -- -D warnings`、`cargo build -p editor-core --release --locked` 全部 EXIT=0。
- Windows Git Bash 使用现成 Flutter 3.47.8 复验 `cargo fmt --check && bash init.sh` 与 `(cd app && flutter analyze)`，全部 EXIT=0；Rust tests、clippy、build_core、Flutter 122 项和 analyze 全绿。P00.3 超 2M UTF-16 恢复夹具再次观测到旧磁盘内容恢复，仍是 characterization，不是修复。
- WSL 已有 GCC/make/pkg-config；未安装 apt GUI 开发包，也未下载 1.58GB Linux Flutter SDK。Flutter gate继续走已授权的 Windows Git Bash runner。证据：`docs/diagnostics/2026-10-28-p00/wsl-rust-validation.md`。
- 没有改产品代码或 feature 状态；P00.4 仍 blocked，feat-022/P00 仍 in-progress，P01 不启动。剩余 gate 见本文件 Current State 与 `docs/03`。

## 今日会话（2026-10-28 第三十七轮）：macOS 与 Linux WPE CI 回放完成

- macOS 15 Actions run 40616364760 在 HEAD `51fe0cd` 通过探针 analyze/test、Release build 与 WKWebView Web Archive 保存/同一视图重载；693 bytes，title/marker 正确且 `archiveParsed=true`。Safari Web Inspector 人工附着与 docs/04 产品内存验收仍未完成。
- Linux Debian sid WPE run 40616364735 在同一 HEAD 通过依赖核验、analyze/test、Release build、memory sampler build 和默认 WebKit sandbox MHTML 回放。使用 WPE 2.52.6 + WPEBackend-FDO 1.16.1，sandbox-disable/GBM-disable 变量均 unset、观察到 bwrap；容器 security label 为 unconfined 且 capabilities 增强，故不代表产品安全 profile。页面 title/marker 正确；初始截图第4次/465ms、MHTML 第1次/50ms，archive 2,587 bytes。销毁+30s进程树 private 406.8 MiB（比创建 WebView 前高117.4 MiB），WebProcess 与 bwrap 退出但 NetworkProcess 留存。单轮探针样本不证明 leak，也不满足 docs/04。
- root CI run 40616364863 全绿。最新 run artifacts、流程、页面截图、归档和内存采样归档于 `p00.4-web-linux-run-40616364735/` 与 `p00.4-web-macos-run-40616364760/`；之前 Linux 包、namespace、network、mount sandbox 失败记录也保留。P00.4/feat-022 仍 blocked/in-progress：GBM、Safari Inspector、官方服务身份/许可、完整产品内存验收仍开放；P01–P15 不启动。
- 本环境启动门禁 `bash init.sh --fast` 因 WSL 无 Cargo 且挂载的 Windows Flutter shell 有 CRLF 失败；Windows Git Bash 2026-10-28 完整门禁 EXIT=0 的日志仍是跨平台门禁证据。本轮只更新诊断和状态文档，没有产品代码变更。

## 今日会话（2026-10-28 第三十六轮）：macOS Web Archive 与 Linux WPE CI

- macOS 15 Actions run 40614141265（commit d47543d）通过探针 analyze、tests、Release build 与 Web Archive replay。693-byte Web Archive 在同一 WKWebView 重载成功，title=`Alula Web Probe`、marker=true、`archiveParsed=true`，截图没有 bplist 原始内容；证据目录为 `docs/diagnostics/2026-10-27-p00/p00.4-web-macos-run-40614141265/`。这不证明 CDP/MHTML 等价，也未完成 Safari Web Inspector 手动附着或 docs/04 产品内存验收。
- Linux WPE run 40614141322 的包版本检查通过，但 Release configure 发现插件需要的 `wpebackend-fdo-1.0` pkg-config 模块未安装（既无 WPEPlatform 也无 FDO fallback），未进入编译。工作流现补 `libwpebackend-fdo-1.0-dev` 并把后端版本写入环境证据；`bash -n`、`git diff --check` 通过，提交/推送 `e853999`。重跑 40614659876 正在执行。
- CI run 40614141412 的 Linux/Windows Rust fmt、clippy、tests 与 Flutter analyze/test 均通过。P00.4 仍 blocked：Linux WPE 重跑、GBM/DMABUF、Safari Inspector、官方服务身份/许可和 docs/04 仍未关闭；P01 不启动。

## 今日会话（2026-10-28 第三十五轮）：复核官方服务策略

- 重新打开 Microsoft VS Code FAQ 与 Settings Sync 官方页面，确认 Code-OSS fork 无权访问 Visual Studio Marketplace；内置 Settings Sync 使用专用服务且不支持自定义后端。没有登录、调用 Marketplace 或写入远程服务。
- 将当前来源与结论登记到 `p00.4-services-evidence.json` 的 `currentPolicyCheck` 并更新 `p00.4-services-adr.md`。服务端许可/身份仍是 P00.4 外部阻塞；macOS workflow 的推送授权仍待用户答复，P01 不启动。

## 今日会话（2026-10-28 第三十四轮）：WPE 同进程十轮内存采样

- 通过 `/mnt/c/Program Files/Git/bin/bash.exe` 从 WSL 调用 Windows Git Bash 执行 `bash init.sh --fast`，EXIT=0：Rust workspace tests、`build_core` 与 Flutter 122 项测试通过；用户 Git Bash `.bashrc` 有 BOM 告警，不影响命令。当前 WSL 直接调用仍因缺 Cargo/Windows Flutter CRLF 失败。
- 在 UID 1000、WPE 2.52.6、Xvfb/software GL、sandbox/GBM disabled 的独立 Release 探针进程里，无截图/MHTML/Inspector 连续创建/销毁 10 次，每次销毁+30s采样。进程树基线 177.57/231.80 MiB private/PSS，第十轮 258.77/315.43 MiB（+81.20/+83.63）；增量在父进程，NetworkProcess PSS 基本稳定，WPEWebProcess 销毁后退出。
- 父进程 `[heap]`、匿名映射、WPE WebKit 文件映射 PSS 分别比基线高 35.17/32.48/14.66 MiB（文件页增量为 15,008 KiB）。周期内有回落，不能由映射数据证明 live leak 或具体 owner；单轮软件渲染探针不满足 docs/04。原始证据和限制见 `p00.4-linux-wpe-multi-cycle-evidence.json` 与 `p00.4-linux-wpe-multi-cycle-run1/`。P00.4 继续 blocked。

## 今日会话（2026-10-28 第三十三轮）：WPE 父进程 smaps 映射 follow-up

- 在 UID 1000 的 Debian 12/WPE 2.52.6/Xvfb 软件 GL 容器中，以无截图自动模式复跑一轮并保存 baseline、WebView open、destroy、destroy+30s 的进程 `smaps`/maps/status；无 MHTML、截图或 Inspector 操作。
- 本轮进程树 private/PSS 从 WebView 前 177.46/231.68 MiB 到销毁+30s 218.36/274.91 MiB，增量 40.90/43.23 MiB；WPEWebProcess 退出，WPENetworkProcess 留存。
- 父进程最大映射组增量为 `[heap]` +21.11 MiB PSS、WPE WebKit 文件映射 +14.62 MiB PSS（主要 private-clean）、匿名映射合计 +7.30 MiB PSS。映射数据不能区分 live object、malloc 保留页或具体库/图形 owner，不构成 leak 证明；sandbox 与 GBM 关闭，单轮探针，不满足 docs/04。
- 原始压缩快照、采集脚本和汇总见 `p00.4-linux-wpe-parent-smaps-run1/`、`p00.4-linux-wpe-parent-smaps-evidence.json` 与更新后的 `p00.4-web-adr.md`。P00.4 继续 blocked，P01 不启动。

## 今日会话（2026-10-28 第三十二轮）：WPE 父进程 heaptrack 探查

- 探针增加 `P00_4_WEB_NO_CAPTURE=1` 路径：复用 WebView 加载和 dispose，但跳过截图、MHTML 与 Inspector 操作。`flutter analyze --no-pub`、`flutter test --no-pub`、Linux Release build 均通过；普通 analyze 因容器 pub.dev 凭据拒绝而无法做联网解析。
- Heaptrack 1.4.0 插桩下一轮销毁+30s父进程比同轮基线多 98.2 MiB Private Bytes / 101.7 MiB PSS；插桩会改变内存行为，不能和此前未插桩的约 41 MiB直接对比。WPEWebProcess退出、NetworkProcess留存。
- 峰值栈有 51.25 MiB 经过 `InAppWebView::InitWpeBackend` 进入 software `swrast_dri.so`，另有 93.52 MiB 调用点未解析。峰值并非销毁后保留量；SIGTERM后的 154.50 MiB `leaked` 报告也不视作泄漏证据。仍未解释原始约40 MiB父进程残留，P00.4保持blocked。
- 证据：`p00.4-linux-wpe-parent-heaptrack-evidence.json`、`p00.4-linux-wpe-parent-heaptrack-run3/`、更新后的 `p00.4-web-adr.md`。

## 今日会话（2026-10-28 第三十一轮）：WPE 无截图生命周期三轮复验

- WPE 2.52.6 source-built Flutter Release 探针在 Debian 12/Xvfb/software GL 下，再以独立进程手动 F5 创建/销毁三次；没有调用截图、MHTML 或 Inspector，三份 TMPDIR 均为空。
- 三轮 WebView 前 Private Bytes/PSS 中位数为 177.1/231.5 MiB；打开时 287.9/390.1 MiB；销毁+30s为 217.3/274.0 MiB。相对基线的三轮增量中位数 40.2/42.5 MiB。
- 三轮销毁后 WPEWebProcess 均退出、WPENetworkProcess 均留存；父进程私有/PSS 内存增量中位数 41.2/42.3 MiB，来源仍未归因。容器元数据采集最初漏设 PKG_CONFIG_PATH，随后确认同一 /work/install 前缀为 WPE 2.52.6；初始 environment.txt 已补全。
- 这是探针级短时周期，不等同 docs/04 的 10min idle、30min edit、工作区关闭场景；P00.4 仍 blocked。汇总及原始文件见 p00.4-linux-wpe-memory-repeat-evidence.json 与 p00.4-linux-wpe-manual-f5-repeat-run1/ 至 run3/。

## 今日会话（2026-10-28 第三十轮）：Windows Git Bash 完整门禁复验

- WSL 启动门禁 bash init.sh --fast 因没有 cargo，且 /mnt/e/flutter/bin/internal/shared.sh 的 CRLF 行在 Bash 报错而失败；这是 runner 限制，不是产品代码失败。
- 按用户选定的 Windows Git Bash 执行 cargo fmt --check、bash init.sh 与 app 下单独 flutter analyze，全部退出 0。Rust workspace tests、Clippy -D warnings、build_core、Flutter 122 项测试全部通过；恢复 P00.3 2,000,001 UTF-16 fixture 耗时 2:11。
- 完整终端输出：docs/diagnostics/2026-10-27-p00/p00-full-validation-windows-gitbash-2026-10-28.log。Git Bash 的用户 .bashrc 有 UTF-16 编码告警，不影响命令结果。没有改产品代码。
- P00.4 外部阻塞未变化；macOS workflow 推送/运行授权问题已单独发给用户，未推送。

## 今日会话（2026-10-28 第二十九轮）：P00.3 fixture 复跑与 WPE 生命周期内存 follow-up

- 按用户选择使用 Windows Git Bash 重放 P00.3 build_core、Flutter risk fixtures 与两个 Rust integration tests，四项命令均通过；超大恢复 fixture 耗时 2 分 10 秒，所有结构化输出与已登记现状一致。完整日志：docs/diagnostics/2026-10-27-p00/p00.3-windows-gitbash-rerun-2026-10-28.log。
- WPE 2.52.6 source-built Flutter Release 探针在 Debian 12/Xvfb/software GL 下连续三轮自动执行页面/MHTML/销毁周期。销毁+30s Private Bytes/PSS 中位数 249.7/308.4 MiB，相对空 WebView 基线高 72.2/76.7 MiB。
- 为排除截图影响，另外手动 F5 创建/销毁一次，不执行 screenshot/MHTML，独立 TMPDIR 为空。WebProcess 退出、NetworkProcess 留存；销毁+30s进程树 218.7 MiB Private Bytes / 275.5 MiB PSS，比空载高 41.9/44.2 MiB，额外内存主要计在 Flutter 父进程，但未归因到具体分配者。
- 结果是探针级探索样本，不满足 docs/04 三轮长时/编辑/关闭要求，不能作为产品预算结论；P00.4 继续 blocked，P01 不启动。总结及原始记录见 p00.4-linux-wpe-memory-repeat-evidence.json 和三个自动/手动 run 目录；ADR 已更新。

## 今日会话（2026-10-28 第二十八轮）：WPE Inspector protocol command session

- WPE 2.52.6 Remote Inspector WebSocket endpoint 握手返回 101，收到 multiplexing page target，并通过 Target.sendMessageToTarget 成功执行 Runtime.enable 与只读 Runtime.evaluate；返回 title=Alula Web Probe、marker=true。
- 初次将 Page/Runtime 直接发送到外层 multiplexing endpoint 得到 domain-not-found；改用 WPE 的 Target.sendMessageToTarget 嵌套路由后命令成功。此为 Web Inspector Protocol，不是 CDP。
- 探针完成 initial-loaded、MHTML reload 与 WebView destroy。运行显式禁用了 sandbox 与 GBM，UID 1000、Xvfb、WPE 2.52.6 source build；不代表产品集成、默认安全配置、硬件渲染或 docs/04 内存 DoD。
- 证据：docs/diagnostics/2026-10-27-p00/p00.4-linux-wpe-inspector-protocol-evidence.json 与 p00.4-linux-wpe-2.52.6-inspector-protocol-run/。P00.4 继续 blocked，P01 not-started。

## 今日会话（2026-10-28 第二十七轮）：macOS workflow dispatch 预检

- 复核当前分支 codex/vscode-parity-p00（HEAD 3b3c7f0）在 origin 上没有对应 branch ref；GitHub workflow 列表仅返回 CI 与 Release；查询 p00-web-engine-macos.yml 明确返回默认分支 404。
- 没有推送，也没有尝试 dispatch；因此没有 macOS runner 或平台通过证据。待用户授权后才可发布当前分支以运行已准备的 macOS workflow。记录在 docs/diagnostics/2026-10-27-p00/p00.4-macos-dispatch-preflight.json。
- P00.4 继续 blocked，feat-022/P00 in-progress，P01 not-started；未改产品代码。

## 今日会话（2026-10-28 第二十六轮）：WSLg Wayland EGL follow-up

- 按启动门禁复核，`bash init.sh --fast` 在当前 WSL shell 因 Cargo 不存在、Windows Flutter 脚本 CRLF 而失败；不代表产品门禁结果。Windows Git Bash 的完整 DoD 与 P00.3 fixture 通过记录保持有效。
- WPE Debian 12 容器以 UID 1000、render supplementary group、`/dev/dxg` 和 `/dev/dri/renderD128` 访问 WSLg Wayland socket；`wl_display_connect` 成功，但 Mesa `eglInitialize` 返回 `EGL_NOT_INITIALIZED`，没有 GLES2 config，因此没有运行 WebView。
- 临时镜像已删除，原 WPE 容器仍运行；没有产品代码改动。WPE GBM 仍未验证，P00.4 blocked。证据：`p00.4-linux-wpe-wslg-d3d12-run/wayland-egl.log` 与 `p00.4-wslg-egl-evidence.json`。

## 今日会话（2026-10-28 第二十五轮）：WSLg D3D12 EGL 与 GBM capability check

- 用户选择 Windows Git Bash 作为 P00.3 runner；四个 fixture 的重放及门禁已记在第二十三轮，当前 WSL shell 没有 `cmd.exe`，本轮没有声称重新运行。
- WSLg EGL/GLES surfaceless probe 在 `GALLIUM_DRIVER=d3d12` 下报告 `D3D12 (AMD Radeon(TM) Graphics)`，context 创建成功。
- 临时 Debian Bookworm 容器可打开 `/dev/dri/renderD128`，但 `gbm_create_device` 返回 null；容器缺 Mesa DRI drivers，结果对 WPE GBM 不确定。
- WPE 2.52.6 容器快照映射 `/dev/dxg` 和 DRM nodes、启用 GBM 并关闭软件 GL 后，Flutter EGL context 失败、WPEWebProcess crash；Xvfb 与容器 X11 `:0` 都未能初始化 EGL。随后 Wayland socket 可连接，但容器 Mesa 的 `eglInitialize` 仍失败且无 GLES2 config。随后直接调用 WPE 镜像 `gbm_create_device` 也返回 null、没有分配 GBM buffer。未到 initial-loaded，也没有 GBM buffer/frame，不能作 WPE 支持结论。
- 未改产品代码或原 WPE 容器；临时镜像已删除，P00.4 仍 blocked。日志与环境见 `p00.4-linux-wpe-wslg-d3d12-run/`、`p00.4-wslg-egl-evidence.json`。

## 今日会话（2026-10-28 第二十四轮）：验证 WPE Remote Inspector HTTP endpoint

- WPE 2.52.6 source build 的 Flutter Linux/WPE Release 探针配置 loopback `WEBKIT_INSPECTOR_HTTP_SERVER=127.0.0.1:9231`；服务 target list 列出 `Alula Web Probe` 和 `/socket/1/1/WebPage`，`/Main.html` HTTP 200、2,680 bytes。同一回放 initial/MHTML 页面 marker、截图、销毁与 30 秒回收采样通过，退出码 0。
- 确认 pinned Linux 插件 capability JSON 仍报 `callDevToolsProtocolMethod=false`、`isInspectable=false`；但 Linux 原生插件源码默认 `enableDeveloperExtras=true` 并调用 WPE setting setter。因此把“Inspector 不支持”改为“WPE Remote Inspector endpoint/target/frontend bootstrap 已验证，命令会话未验证”；CDP 仍不支持。
- 此次 Inspector 回放显式禁用 WebKit sandbox 与 GBM，仍为 Xvfb/source-built WPE 诊断结果；没有 Inspector UI attach 或 protocol command response，不能推断安全发布或 CDP 等价。证据见 `p00.4-linux-wpe-inspector-evidence.json`、`p00.4-linux-wpe-2.52.6-inspector-http-run/` 和 ADR。
- 启动门禁 Windows Git Bash `bash init.sh --fast` EXIT=0；Flutter 122 项测试通过。未改产品 `app/` 或 `crates/`，P00.4 仍 blocked，feat-022 in-progress，P01 not-started。

## 今日会话（2026-10-28 第二十三轮）：重放 P00.3 并处理 WPE 首帧截图时序

- 按用户选择的 Windows Git Bash 与 Flutter wrapper，重跑 `build_core.sh`、P00.3 Flutter characterization test、workspace-close 与 slow-completion Rust tests；全部退出码 0，四个 JSON 观测与既有证据一致。2,000,001 UTF-16 单元恢复夹具约 2 分 03 秒完成。
- 提交前根目录门禁：Windows Git Bash `cargo fmt --check`、完整 `bash init.sh`、单独 `app/ flutter analyze` 全部退出码 0；Rust workspace tests、Clippy、core build 与 Flutter 122 项测试均通过。
- GitNexus 增量索引后 `detect-changes --scope all` risk=medium（91 files/14 symbols/1 flow，包含既有 workbench 改动），staged risk=medium（62 files/4 symbols/1 flow，唯一 flow 为 Build→`_hasProbeHeadingPixel` 探针截图路径）；无 HIGH/CRITICAL。流程索引警告 190 个候选入口未入选、123 个 callee 因预算跳过、2 次 walk 达预算，不能视为无影响证明。
- 解码旧默认-sandbox 首屏 PNG：1280×572 RGBA 的 732,160 像素全部为透明零值；DOM marker 虽存在，但没有页面像素。检查 pinned Linux plugin 发现 `takeScreenshot()` 只复制当前 buffer，不等待 WPE frame callback。
- 独立探针现在在 DOM 查询前轮询截图，最多 30 次、间隔 100ms，要求检测页面标题的蓝色像素。Flutter analyze、test 与 Linux Release build 通过。三次 UID 1000 默认-sandbox 新冷启动均生成可见初始页/MHTML 截图；两次预备 alpha-check 首试通过，最终 heading-check 版本第 2 次（199ms）通过。运行仍将 sandbox-disable 变量保持 unset、GBM disabled，并观察到 bwrap 与 WPEWebProcess。
- 新证据目录为 `p00.4-linux-wpe-2.52.6-frame-poll-run/`、`run2/`、`run3/`；判定为探针级捕获时序处理，不是产品帧同步修复。P00.4 仍因 macOS、官方服务身份/许可、GBM、发行包 API、Linux CDP/Inspector 等未决项 blocked；feat-022 继续 in-progress，P01 not-started。
- 未改 `app/`、`crates/` 或产品依赖；仅改独立 WPE 诊断探针及 P00.4 报告/状态文档。工作区原有的 harness、workbench、docs09 与 parity-plan 改动仍未暂存。

## 今日会话（2026-10-28 第二十二轮）：WPE 默认 sandbox 受限容器复核

- 按启动流程用 Windows Git Bash 重跑 `bash init.sh --fast`，退出码 0；Rust workspace 测试、核心库构建与 Flutter 122 项测试通过。GitNexus 在本次提交前状态 fresh。
- 标准临时容器的 seccomp profile 阻止 bwrap 创建 user namespace。为判断是否是 WPE 本身不支持 sandbox，使用本地一次性镜像启动验证容器，运行参数为 `--cap-add SYS_ADMIN --security-opt seccomp=unconfined`，探针进程仍为 UID/GID 1000；`unshare --user --map-root-user true` 退出 0。
- 在该容器中保持 `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS` unset、设置 `WEBKIT_DMABUF_RENDERER_DISABLE_GBM=1` 后，探针完整经过 initial-loaded、mhtml-loaded、webview-destroyed 与销毁后 30 秒采样，退出码 0。WebView 打开时进程树含两个 `bwrap`、`WPEWebProcess` 和 `WPENetworkProcess`；销毁后 WPEWebProcess 退出，NetworkProcess 留存。
- 首次页面 JSON marker 为 true，但 PNG 只有背景色；MHTML 重载页面的 JSON marker 与截图正常。500ms、2 秒等待都没能修好干净配置的首帧截图，因此撤回了探针中的临时延迟变更，产品/探针源码最终无改动。GBM 硬件渲染仍未验证。
- 默认 sandbox 运行证据在 `p00.4-linux-wpe-2.52.6-default-sandbox-run/`；单轮 Private/Working Set/PSS MiB：基线 227.0/341.9/281.5，view open 314.9/600.7/422.8，MHTML 332.8/622.2/441.4，destroy 255.3/382.5/315.5，destroy+30s 258.5/382.1/317.3。该轮不是 docs/04 三轮与长时产品验收。
- WPE 默认 sandbox launcher 已在具备额外 namespace 能力的隔离 Docker 环境运行；这不证明常规 Docker/GitHub runner/生产主机可用。首帧截图、GBM 硬件、macOS 与官方服务仍是 P00.4 阻塞；feat-022/P00 继续 in-progress，P01 继续 not-started。
- 本轮没有保留探针源代码改动；只更新 P00.4 ADR/证据、README、状态索引与会话交接。提交前需重新 analyze GitNexus、对暂存集跑 detect-changes，并验证 MHTML hash 与 JSON。

## 今日会话（2026-10-28 第二十一轮）：WPE 2.52.6 源码构建与回放

- 使用官方 WPE WebKit 2.52.6 release archive（SHA-256 `b2bafef2751625b7fdf530f230ff0f542ff0eeba3590c3a989d931b2a55c858e`）在临时 Debian Bookworm Docker 容器源码构建；WPEPlatform、Headless、MHTML 均开启，9,421 个 Ninja 步骤与 install 均成功。编译有 15 条 `-Wrestrict`、7 条 `-Wuse-after-free` 警告。构建参数、日志和源码限制见 `p00.4-linux-wpe-2.52.6-build.md`。
- Flutter 3.47.8 / Dart 3.13.7 的 probe `pub get`、`analyze`、1 项 test、Linux Release build 均通过；Rust 1.90.0 下 mem-probe release build 通过。Clang14 的 CMake 探测需设置自定义 WPE `LDFLAGS`；插件的 `-Wno-deprecated-literal-operator` 在本机 Clang14 未知，临时 `CXXFLAGS` 只屏蔽该选项诊断，没有改插件/产品源。
- 默认 WebKit sandbox 因容器禁止非特权 user namespace 无法启动；禁用 sandbox 后，GBM/DMA-BUF 路径不产出 CPU screenshot；设置 `WEBKIT_DMABUF_RENDERER_DISABLE_GBM=1` 后，初始页面、MHTML 重载、PNG、销毁和 30 秒内存采样全部通过。最终回放同时设 `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1`，只作为隔离软件渲染实验，不证明默认安全或硬件渲染。
- 单轮 Private/Working Set/PSS MiB：空 WebView 176.9/290.7/230.9；WebView open 282.5/553.9/384.8；MHTML reload 289.5/564.4/392.5；destroy 219.8/342.3/278.2；destroy+30s 219.3/341.8/277.7。WPEWebProcess 已退出但 NetworkProcess 留存；不满足 docs/04 多轮与长时协议。页面 JSON 仍记录 Linux CDP/Inspector 不支持。
- 更新 smoke runner，使 source-built WPE 不在 dpkg 中时仍可记录 pkg-config 版本，并将 WebKit 安全/GBM overrides 写入 environment.txt。GitNexus 对脚本文件的 impact 为 UNKNOWN；文本检索确认仅 README、Linux Actions workflow 和证据 JSON 引用该脚本。P00.4/feat-022 保持 blocked/in-progress，P01 仍 not-started。未修改 `app/`、`crates/` 或产品依赖。
- 本轮启动时 Windows Git Bash `bash init.sh --fast` 完整退出码 0；Rust/Dart 全门禁与 122 项 Flutter 测试通过。新增变更只涉及探针脚本和文档/实验数据；提交前仍需跑 Bash 语法、JSON/证据校验和 GitNexus graph change analysis。

## 今日会话（2026-10-28 第二十轮）：WPE API 兼容边界复核

- 官方 WPE 2.54 迁移说明确认 `WPE_SETTING_DISABLE_ANIMATIONS` 已替换为 `WPE_SETTING_REDUCED_MOTION`；pub.dev 当前只有 `flutter_inappwebview_linux 0.1.0-beta.1`，仍引用旧名。
- 测试 Debian Trixie `libwpewebkit-2.0-dev=2.48.3-1` 与插件声明的 WPEBackend-FDO legacy fallback。该包没有 WPEPlatform pkg-config/header；为继续检查 FDO 分支，在临时容器补空 include 目录后，干净 `flutter clean` + Release build 仍因 `webkit_web_view_get_theme_color` 未声明失败。容器为 Bookworm 衍生/混合 Debian，不是干净 Trixie；无 WPE runtime 证据。细节见 `p00.4-linux-wpe-trixie-compat.log`。
- 未加编译宏、未改插件源码、未把临时目录 workaround 写入仓库。WPE 2.53.92 是官方开发版，需单独评估是否值得从源码构建；P00.4 仍 blocked，P01 仍 not-started。
- GitNexus 在提交 `5d8b795` 后重建索引：201 flows；188 个入口候选未进入排名、123 个 callee 因分支预算跳过、2 次 walk 达预算；缺失 flow 不能视为无影响。
- 提交前 GitNexus `detect-changes --scope all` risk=low（37 files/33 symbols/0 processes），staged risk=low（8 files/17 symbols/0 processes）。

## 今日会话（2026-10-28 第十九轮）：Flutter Linux/WPE 构建尝试与阻塞

- 本地临时 Debian sid 包环境下，Flutter 3.47.8 / Dart 3.13.7 的 probe `flutter analyze` 与 `flutter test` 通过；Release 构建失败在 `flutter_inappwebview_linux 0.1.0-beta.1`，`in_app_webview_settings.cc:405` 引用了 WPE 2.54.2 头文件不存在的 `WPE_SETTING_DISABLE_ANIMATIONS`（头文件提供 `WPE_SETTING_REDUCED_MOTION`）。没有修改插件源码或加兼容宏。
- 首次 CMake 配置发现遗漏 `libsecret-1-dev`，已补到 `.github/workflows/p00-web-engine-linux.yml` 和 probe README。完整环境、命令结果与编译错误见 `p00.4-linux-wpe-build.log`；更新静态证据 JSON 与 Web ADR。Xvfb runtime replay 未运行，无 WPE MHTML、截图和内存样本。
- 本地容器从缓存的 Bookworm 衍生镜像升级 sid 包，`/etc/os-release` 报 `forky/sid`，不是干净的 `debian:sid` workflow 环境；包版本已在证据中记录。GitNexus 索引在 Flutter 生成文件后重建为 up-to-date；`WebEngineProbePage` impact 为 LOW，1 个直接调用、0 流程；CMake 文件 impact 为 UNKNOWN，文本确认本轮只补构建依赖。
- 提交前 GitNexus `detect-changes --scope all` 为 risk=low（38 files/34 symbols/0 affected processes），staged 为 risk=low（9 files/18 symbols/0 affected processes）。索引仍有流程截断：186 flows、208 个入口候选未纳入、98 个 callee 被跳过、2 次 walk 达预算；不把缺失 flow 当作无影响。
- P00.4 仍 blocked：Mac、Microsoft 官方服务身份/许可未解决，Linux WPE 在该插件/API 组合上无法构建；P01 仍 not-started。没有修改 `app/` 或 `crates/`。
- 收尾门禁：Windows Git Bash `bash init.sh --fast` 与完整 `bash init.sh` 均通过；`cargo fmt --check`、`flutter analyze` 也通过。完整脚本覆盖 Rust 测试、Clippy、核心 DLL 构建和 Flutter 122 项测试；2,000,001 UTF-16 单元恢复夹具约 2 分钟完成，结果符合现状预期。

## 今日会话（2026-10-28 第十八轮）：Linux WPE runner 与 beta 探针复验

- 为 Flutter Linux 加入生成的 Linux runner、Debian sid WPE 构建 workflow 和 Xvfb 生命周期采样脚本；锁定 `flutter_inappwebview 6.2.0-beta.3` / `flutter_inappwebview_linux 0.1.0-beta.1`，Linux WebKit 保存 MHTML 到 `.mht`，用插件 PNG API 截图并验证同 view 重载标记。Linux runner 尚未执行，不记为 runtime evidence。
- 所选插件的公开方法表将 `callDevToolsProtocolMethod` 限于 Windows WebView2；`isInspectable` 表未包含 Linux。静态契约与未运行边界见 `p00.4-linux-wpe-evidence.json`，P00.4 继续 blocked。
- Windows Git Bash Flutter 3.47.8：探针 `dart format`、`flutter analyze`、`flutter test` 通过；NuGet CLI 下载依赖后 Release build 退出码 0。beta.3 自动 WebView2 生命周期回放通过，1,438-byte MHTML 在同一 view 重载且两张截图均含页面标记；销毁后 30 秒单进程 203.2 MiB，探针退出。原始数据见 `p00.4-web-beta-run/` 与 `p00.4-web-beta-evidence.json`。
- Windows Git Bash `bash init.sh` 本轮退出码 0：Rust workspace tests、clippy、核心库构建与 Flutter 122 项测试通过；2,000,001 UTF-16 单元恢复夹具完成并保留预期现状。启动时 bashrc 有编码告警，不影响门禁结果。
- 新增 Linux Flutter/WPE workflow 仅在 PR/手动触发，未 push/dispatch；macOS workflow 也未运行。Marketplace/官方服务授权阻塞仍在，P01 不开工。没有修改 `app/` 或 `crates/`。

## 今日会话（2026-10-28 第十七轮）：补齐 macOS WebArchive 回放 runner

- Windows Git Bash 重验固定 SHA commit 下载 URL，HTTP 404；对官方 CLI 使用的语义版本解析端点发起 GET 也返回 404。微软维护的 `vscode-test` helper 与 VS Code CLI 更新服务源码都采用同一固定 commit URL。证据见 `reference-acquisition.md`；结论限于公开的官方路径，不推断所有内部/企业渠道。
- 给隔离 `tools/web-engine-probe/` 加入 Flutter macOS 工程骨架：macOS 使用 `WKWebView.createWebArchiveData()` 写出 `.webarchive`，在同一个 view 重新打开并验证页面标记。新增 Mac 重放脚本，采集 `footprint -targetChildren`、页面 JSON、Web Archive 和尽力截图；新增仅 `pull_request`/手动触发的 macOS 15 GitHub Actions 工作流。
- Windows Git Bash Flutter 3.47.8 下 `dart format`、探针 `flutter analyze`、`flutter test` 均通过；`cargo fmt --check && bash init.sh` 与单独 app `flutter analyze` 也通过。Mac 构建和运行尚未执行，Safari Web Inspector 附着仍需手动验证。Mac runner 是测试基础设施，不计平台 evidence，P00.4 仍 blocked。
- GitNexus staged 检查为 risk=medium，37 个文件/20 个符号/5 条受影响流程；五条均为隔离探针的 build、导出、重载、销毁与自动回放路径。all scope 还包含工作区用户既存改动。`_captureMhtml`、`_captureRenderedPage`、`_openMhtml`、`_runAutomaticReplay` 的 impact 为 LOW。`_toggleWebView` 显示 HIGH，因此撤回该方法内的状态文案改动并保持方法原样；`State.build` 图谱为 UNKNOWN，源码检索确认它是 Flutter 覆写且动态回调位于该方法内，调用边界已人工复核。流程索引自身存在截断，缺失流程不视作无影响。
- 未修改 `app/` 或 `crates/` 产品代码；P01 未开始。

## 今日会话（2026-10-28 第十六轮）：P00 完整门禁复验

- Windows Git Bash 执行 `cargo fmt --check && bash init.sh` EXIT=0；Rust workspace tests、core 构建、clippy 零警告、Flutter 122 项测试全绿。RECOVERY-01 实际接受 2,000,001 个 UTF-16 单元，重启恢复内容仍只有磁盘上的 5 个单元，夹具符合预期。
- 单独执行 Flutter `analyze` EXIT=0，`No issues found!`。本轮没有改动 `app/`、`crates/` 或产品依赖。
- GitNexus 状态在提交 `7a67d8f` 时 up-to-date；本次仅更新状态/交接文档。只提交本轮文档，不包含工作区已有的其它用户改动。
- P00.4 的 macOS、Linux Flutter/WPE/CDP 与 Microsoft 官方服务身份/许可阻塞仍未解除；feat-022/P00 保持 in-progress，P01 未开始。

## 今日会话（2026-10-28 第十五轮）：复核官方发行物与 Linux WPE runner 前提

- Windows Git Bash 重查 Code-OSS 固定 SHA 的微软发行地址：`latest/win32-x64-archive/insider` 当前回到 1.144.0 Insiders、revision token `abc2b20cb3e724689f78f5d2a3c231589b25483c`；固定 SHA 与 1.145.0 下载 URL 仍 404。P00.1 继续以已启动的 pinned Code-OSS 源码构建为参考，不替换版本，也不把其它版本当等价发行物。
- 重新核对微软 FAQ 与 Settings Sync 文档：Marketplace 限 Visual Studio 产品家族且不允许 Code-OSS fork；Settings Sync 不支持自定义后端。未登录、未请求 Marketplace 或写入服务，P00.4 服务身份/许可阻塞保持。
- 调查 Linux Flutter 路径：上游插件 v6.2.0-beta.3 才加入 Linux，依赖独立 WPE 实现；Ubuntu 24.04 WSL 当前没有 Linux Flutter/Dart SDK 或 WPE 开发包，主机只有 Windows Flutter SDK。Debian sid WPE 2.54.1 包是可选 runner 路线，但本轮未构建/运行 beta 插件；GTK 原生探针不替代该验收。
- GitNexus `detect_changes` all/staged 均 risk=low；staged scope 为 5 个文档文件、0 条受影响流程。返回对象未带 `partial`/`truncated` 字段；分析器流程索引仍有截断（187 flows、406 个入口候选中 206 个未入选、98 个 callee 被跳过、2 次 walk 达预算）。
- Windows Git Bash `bash init.sh --fast` EXIT=0，Flutter 122 项通过。无 app/、crates/ 或产品依赖改动。P00.4 仍 blocked，feat-022/P00=in-progress，P01 依赖未满足。

## 今日会话（2026-10-28 第十四轮）：补充 Linux WebKitGTK 原生引擎证据

- WSL2/WSLg 上运行 GTK 3.24.41 + WebKitGTK 2.52.6 原生探针；离线 HTML 渲染、页面快照、MHTML 保存及同一 view 重载均通过，Web Inspector 成功附着并留存截图。此结果不代表 Flutter Linux/WPE 集成，也不证明 Chrome CDP 兼容。
- 单次 Private_Clean + Private_Dirty 进程树样本：空壳 1 个进程 / 22.7 MiB，页面加载 3 个 / 170.0 MiB，MHTML 重载 3 个 / 199.2 MiB，Inspector 完成 5 个 / 449.8 MiB，销毁 30 秒后 2 个 / 69.6 MiB；NetworkProcess 仍在，且非 docs/04 的三轮及 1/10/30 分钟产品验收。WSLg 报告 DRI3 不可用。
- 新增可重放 runner `tools/web-engine-probe/linux/run-webkitgtk-probe.sh` 和探针 `webkitgtk_probe.py`；原始阶段 JSON、PNG、MHTML 与聚合摘要位于 `docs/diagnostics/2026-10-27-p00/p00.4-linux-webkitgtk-run/` 和 `p00.4-linux-webkitgtk-evidence.json`。不安装依赖包，runner 将所需 typelib/Cairo bridge 解到临时目录。
- Windows Git Bash `bash init.sh --fast` EXIT=0；`bash -n`、Python `py_compile` 与相对输出路径的 Linux runner 重放 EXIT=0，九个阶段均产出；MHTML 两次重放均有 MIME 头/页面标记，截图一致。MHTML MIME boundary 随次生成，哈希不同；归档摘要只记录提交的规范样本哈希。没有修改 app/ 或 crates/ 产品代码。
- GitNexus 本轮 `detect_changes` 的 all 与 staged scope 均为 risk=high；staged scope 覆盖 22 个文件与 8 条受影响流程，流程均落在独立 WebKitGTK GTK 探针的生命周期/采样路径。all scope 还包含未暂存的用户既存 README/app/workbench 修改。检测返回结构未带 `partial`/`truncated` 字段；索引构建报告 process graph 本身被截断（187 flows、406 个候选入口中 206 个未入选、98 个 callee 被跳过、2 次 walk 达预算），所以不把缺失流程视为无影响。
- P00.4 仍 blocked：Flutter Linux 插件/CDP、macOS 和 Marketplace/官方服务条件仍未解决；P01 依赖 P00，不开工。

## 今日会话（2026-10-27 第十三轮）：P00.4 Web 与官方服务风险实验

- Web 实验使用独立 `flutter_inappwebview 6.1.5` Windows Release 探针；按生命周期阶段标记采样，CDP `Page.captureSnapshot(format=mhtml)` 导出 1,438-byte MHTML，并在同一 WebView2 中重载；`Page.captureScreenshot` 导出的初始页与 MHTML 页均含 `WEB_ENGINE_PROBE_OK`。
- 单次进程树 Private Bytes：挂载前 1 进程 / 198.1 MiB，初始 WebView 7 进程 / 369.3 MiB，MHTML 阶段 7 进程 / 404.1 MiB，销毁后 1 进程 / 211.0 MiB，30 秒后 1 进程 / 203.9 MiB。探索样本不是 docs/04 三轮和 1/10/30 分钟验收。
- Windows `flutter analyze` 零问题、`flutter test` 1 项通过、Windows Release 构建通过；当前 MSVC 需 NuGet 和临时 coroutine 弃用宏。没有修改 app/ 或 crates/。
- macOS 无测试设备；WSL 没有 Linux GUI/Flutter Linux/WebKitGTK/WPE，跨平台 Web/CDP/MHTML 仍未验证。
- 固定 Code-OSS 1.145.0 `product.json` 缺少正式版 auth/Sync/gallery/tunnel 配置；本机另装 Microsoft VS Code 1.142.0 Stable 有独立产品身份字段，凭据值未复制。官方 FAQ 明确 Marketplace 不允许 Code-OSS fork 使用，Settings Sync 不支持自定义后端；无账号登录、OAuth 注册、Marketplace 请求或隧道创建。
- 阶段提交门禁：Windows Git Bash `cargo fmt --check`、`bash init.sh` 与单独的根目录 `flutter analyze` 均 EXIT=0；完整 Flutter 测试通过（122 项）。
- GitNexus 索引更新后，完整 `detect-changes --scope all` 无 `partial`/`truncated`：107 files / 271 symbols / 17 flows，risk=critical，包含工作区其它既存改动。仅 staged scope 也无 `partial`/`truncated`：78 files / 255 symbols / 17 flows，risk=critical；受影响项来自两个独立 Flutter 探针的通用 Win32Window 生命周期模板，以及 Web 探针自动回放路径，未涉及 app/ 或 crates/。Analyzer 本身仍报告 process graph 截断（187 flows；393 个候选入口中 193 个未入选、98 个 callee 被跳过、2 次 walk 达到预算），缺失 flow 不视为无影响。
- 证据：`p00.4-web-adr.md`、`p00.4-web-evidence.json`、MHTML/PNG/进程树 JSON、`tools/web-engine-probe/`；`p00.4-services-adr.md`、`p00.4-services-evidence.json`。
- P00.4 记为 blocked，feat-022/P00 保持 in-progress；P01 依赖 P00，当前不能签收或开工。

## 今日会话（2026-10-27 第十二轮）：P00.4 实验1编辑器风险探针

- 独立 Flutter Windows 探针运行 CodeForge 11.3.0；未改 Alula 产品工作台或 Rust 文档模型。
- Windows 11 Microsoft Pinyin 实测 composition/candidate commit/Escape cancel/Latin incremental input。Flutter widget characterization 验证 composing 文本未提前改权威文本、提交后单次撤销恢复；Delta 插入分发到主光标和三次光标并可一次撤销；10,000 行视口滚动。
- Windows Git Bash flutter analyze 与 flutter test 均 EXIT=0，4 项测试通过。Debug混合输入累计帧/按键采样仅作探索记录，不作为延迟或性能验收。
- 决策：CodeForge 11.3.0 保留为 P03 候选，不直接集成；Rust DocumentModel 仍须是唯一权威文本。三平台IME、Rust往返/背压、Release内存/时延、Emoji/ZWJ/组合字符/CRLF/BOM、多视图/无障碍等未验证。
- 证据：docs/diagnostics/2026-10-27-p00/p00.4-editor-adr.md、p00.4-editor-evidence.json、PNG 截图及 tools/editor-ime-probe/。
- P00.4 状态改为 in-progress；下一项顺序执行 Web/CDP/MHTML/按需内存实验，之后才做官方服务/注册前提实验。

## 今日会话（2026-10-27 第十一轮）：P00.3 现状风险夹具验收

- 新增 Flutter 双文件交替撤销、超 2M UTF-16 单元未保存恢复测试；新增 Rust 关闭工作区进程、1.2s 延迟补全测试及专用 fake LSP。
- Windows 11 Git Bash 运行四个现状夹具：撤销跨文件串写；超 2,000,000 UTF-16 单元正文未写入 journal，重启后读回磁盘 `seed\n`；关闭全部文档后 LSP 子进程仍存活；1.2s provider 令调用方等待 1.2s。固定 Code-OSS 1.145.0 的隔离运行再验证双文件分别撤销各自内容。
- 采集真实 Alula 空工作区页面图 `docs/diagnostics/2026-10-27-p00/alula-welcome.png`。与固定参考同为 1505×1005、1204×804 逻辑视口、DPI/DPR 1.25、深色主题；Alula 为 zh-CN、参考为 en-US，文字视觉配对留到 P05。
- DoD 全绿：`bash init.sh --fast`、`bash init.sh`、`cargo fmt --check`、`flutter analyze` 均 exit 0；Rust workspace tests/clippy/build_core 通过；Flutter 122 项通过。Windows 工具链/fixture 输出见 `p00.3-environment.json` 与 `p00.3-current-state.json`。
- `docs/03` 将 P00.3 标为 done，P00.4 仍 not-started。三项限时实验尚未开始；P00 整体仍 in-progress。

## 今日会话（2026-10-27 第十轮）：P00.2 原子贡献与运行时登记导出

- 固定源码 AST、95 个扩展 manifest、`product.json` 和隔离运行时 registry 导出为 12,958 条唯一登记记录；导出器验证 pinned commit/tree，保留运行时独有 ID、无稳定 ID、无目录路由和无 feature 路由等未决项。
- 运行时快照：2,684 条命令、5 种语言、1,289 个配置键；client-only 宿主未加载随附扩展 payload，静态 95 个 manifest 与运行时 0 个产品扩展的差异单独记录。运行时配置候选 1,289/1,289 可查。
- 检查发现并修正对账逻辑，防止把运行时独有项误计为源码项；注册记录 ID 现在唯一。当前尚有 6,828 条未决注册/路由，不计作覆盖率，留待后续逐项复核。
- 证据：`docs/diagnostics/2026-10-27-p00/atomic-contributions.md` 与 JSON ledger；可用 `node tools/vscode-parity/export-atomic-contributions.mjs --source=<pinned-checkout>` 重放。
- P00.2 导出器子项完成，P00 总包继续 in-progress；下一项为 P00.3 黄金基线/故障夹具。`bash init.sh`、`cargo fmt --check`、`flutter analyze` 均 EXIT=0，详见 `docs/diagnostics/2026-10-27-p00/p00.2-validation.log`。
- GitNexus `detect-changes --scope all` 报告 risk=critical（48 files/264 symbols/20 flows），包含此前已有的 README 和 app 修改；staged scope 为 19 files/248 symbols/17 flows，命中本阶段新导出器流程与文档，无 Alula 产品源码。记录于 `docs/diagnostics/2026-10-27-p00/atomic-contributions.md`。

## 今日会话（2026-10-27 第九轮）：P00.1 固定参考构建与启动

- 固定 SHA `4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e` Code-OSS client-only build 成功；Electron `43.8.3` 生成并成功启动 Workbench。构建输出 `client=full, extensions=skip, copilot=skip`，未编译外接 AI lane。
- 使用独立 user-data/extensions 目录启动，无账号登录；CDP 导出 viewport/DPI/locale/主题和 `product.json` 内置扩展清单，并保存 Workbench 欢迎页截图。
- 官方微软精确 SHA 发行物仍未找到；只把 Code-OSS 源码作为参考构建。remote 子树 postinstall 为非桌面 client 依赖，构建取证后停止；不将 remote 依赖视为已安装。
- 仓库 DoD：`bash init.sh` EXIT=0（Rust test、clippy、build_core、Flutter 120 tests）；另跑 `cargo fmt --check`、`flutter analyze` 均通过。Git Bash 启动有 `.bashrc` UTF-16 BOM 提示，但命令继续并全绿。
- 证据：`docs/diagnostics/2026-10-27-p00/reference-acquisition.md`、`capture-reference.mjs`、`runtime-evidence.json`、`reference-workbench.png`。P00.1 已验收，P00 总包仍 in-progress。

## 今日会话（2026-10-27 第八轮）：P00.1 固定参考获取（历史进度）

- 切到 `codex/vscode-parity-p00` 分支，保留工作区既存改动；没有整仓暂存或提交。
- GitHub 官方 commit API 核实 pinned SHA、tree、parent 与签名；`package.json` 为 1.145.0，`product.json` blob 已核验。
- 官方 Insider 最新归档落在 1.144.0 / 不同 commit；精确 SHA 与 1.145.0 的测试下载 URL 返回 404。本地 `code` 为 1.142.0，不能代替固定参考。
- Git smart-protocol 在 WSL 与 Windows Git Bash 均挂起；固定源码后续改用限制目标的 Git 协议 v2 relay 获取，commit/tree 已核验。该轮结束时构建和启动尚未完成。
- 基线：WSL `init.sh --fast` 因无 cargo 及 Flutter shell CRLF 失败；Windows Git Bash 的同命令退出 0，Rust 测试/build_core 与 Flutter 120 项通过。Node 24.22.1、npm 12.0.2、cargo 1.97.1；npm registry ping 17.7 秒成功。
- 证据：`docs/diagnostics/2026-10-27-p00/reference-acquisition.md`。本轮没有产品实现变更，不做内存或 UI 等价结论。

## 今日会话（2026-10-27 第七轮）：完整复刻计划

- 固定上游：vscode `4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e`（1.145.0开发快照）；
  docs `da213552439825628e0ab958dbde1e413dbc36bf`。通过官方GitHub connector实查目录、
  90个非AI产品manifest/74个language ID/89个grammar贡献及3个下载式预置调试扩展。
- 总计划16实施包P00–P15，含架构/依赖/风险/资源/跨平台界面及行为验收；矩阵342条功能族
  与14项边界决策。功能族仍须P00展开为原子注册项，不声称已完成100%语义覆盖。
- 范围包括内置扩展、终端、默认JS调试、Notebook宿主/输出、Markdown rich/math/Mermaid、
  集成浏览器、Profiles/Sync、Cloud Changes、公网Ports等非AI外部服务。外部服务互通前提单列，
  不能因联网删需求，也不冒称额外Python/Jupyter/Remote等provider已默认提供。
- 修正旧计划只要求结构等价、历史状态过期、空窗内存被当同功能−50%已通过的问题。
  现有全局UndoStack/大文档备份/同步FFI/800ms轮询/LSP回收等静态风险列入P00/P01/P02。
- 按Startup规则复验发现当前工作树Flutter编译失败：`_findRenderEditableOf`递归误调用
  接收BuildContext的方法；GitNexus impact LOW（2个上游方法、Ctrl+点击流程），仅一行改为
  正确RenderObject递归辅助方法。保留其余用户既存代码/skill改动。
- 验证：Windows Git Bash执行cargo fmt --check + bash init.sh + flutter analyze，EXIT=0；
  Rust workspace测试全绿、Flutter120测试通过，clippy零警告/analyze零问题。
  证据：docs/diagnostics/2026-10-27-parity-plan/full-validation.log；前后fast日志同目录。
- 当前WSL无cargo且Windows Flutter shell为CRLF，不能直接据WSL失败判业务错误；使用现有
  Windows工具链复验。原Windows GitNexus元数据在WSL无效，隔离索引在
  `/tmp/alula-plan-gitnexus`，不改原`.gitnexus`缓存；过程发现截断不可推断缺失调用不存在。
- 计划结构/链接/依赖自检通过，harness100/100；全工作树graph change analysis记录于同目录。
  最终证据见verification.md。feat-021计划完成；P00–P15未开始，未提交、未推送。

## 今日会话（2026-10-27 第六轮）：feat-outline 大纲视图（首个 Rust 侧功能）

- **全栈贯通**：editor-lang.symbols()（tree-sitter 遍历 10 类定义节点，impl 取
  「Trait for Type」，UTF-16 偏移/行号，嵌套+深度保险）→ editor-core.doc_symbols
  → FFI alula_symbols（**ABI 3→4** 双侧握手）→ Dart core.lsp.symbols →
  大纲侧栏视图（类别徽章/行号/点击跳定义）+ 编辑后防抖刷新（版本去重）。
- **顺修真实 UX bug**：外部刷新重建文件树丢展开状态（git status 写 .git 即
  触发监视刷新，用户展开被抹掉）→ _refreshTree 快照并恢复展开态。
- CI Format 门抓了新代码格式（cargo fmt 补齐）。
- 测试：3 Rust 单测 + 1 端到端 widget；全量 120 绿 + CI 全绿。

## 今日会话（2026-10-27 第五轮）：feat-filewatch 文件监视

- WorkspaceWatcher：Directory.watch(recursive)（Windows/Linux 原生递归，零新
  依赖），600ms 防抖收敛，错误静默降级；先探测本平台递归可用性再动工。
- 外部变更后：文件树刷新（根+已展开目录保留展开态）、Git 状态刷新、
  打开文档检测——干净文档自动重载、脏文档仅提示（不覆盖本地编辑）。
- analyzer info 清零（5 项字符串插值 lint）——init.sh 不含 analyze 的盲区
  被 CI 抓到一次，注意提交前跑 analyze。
- 测试：3 watcher 单测 + 1 端到端（外部写盘→自动重载）；全量 119 绿 + CI 全绿。

## 今日会话（2026-10-27 第四轮）：feat-search 搜索视图

- **SearchService**：后端探测 rg --json → git grep --untracked → 不可用提示；
  流式命中（StreamController + 取消订阅终止子进程）；上限 500。
- **三个实战坑**：① rg 在 stdout 管道化且无显式路径时等待 stdin（补 '.'）；
  ② git grep 默认不搜未跟踪文件（补 --untracked）；③ pattern 必须在
  '--' pathspec 之前。CI 又抓到一个：rg 探测要捕 ProcessException（可执行
  文件不存在直接抛异常，不只是非零退出码）。
- **UI**：活动栏搜索图标激活（侧栏第三视图）+ Ctrl+Shift+F 命令/键位 +
  搜索框（Enter/大小写切换）+ 命中列表；点击命中打开文件并跳转到对应行。
- 测试：10 服务测试 + 1 端到端 widget（runAsync）；全量 115 绿 + CI 全绿。

## 今日会话（2026-10-27 第三轮）：feat-git Git 面板

- **GitCli**（Dart CLI 封装）：status --porcelain -z 解析（rename/中文路径/
  未跟踪目录归一化）、add/reset/commit/diff/log；默认 runner 显式 UTF-8
  （Windows 码表乱码坑）；runner 可注入。6 假 runner 单测 + 4 真 git 集成测试
  （临时仓库全流程，局部 user 配置）。
- **UI**：活动栏双视图切换（资源管理器/源代码管理，重复点折叠）；Git 面板
  （分支/暂存区与工作区分组/单文件暂存取消/提交框/错误展示）；点击更改文件
  → 底部面板「Git Diff」标签看差异。
- **踩坑**：widget 测试假 async zone 里真实 git 子进程永不完成 → tester.runAsync
  包裹；ListTile 在彩色容器内触发框架断言 → 透明 Material 包裹。
- 测试：104 全绿 + init.sh + CI 全绿。

## 今日会话（2026-10-27 第二轮）：feat-010a 撤销/重做 + 查找替换

- **决策**：Flutter 内建 UndoHistory 探测死锁（测试环境）且绑死 TextField
  （组件选型会失效）→ **自研 UndoStack**（文本快照制：400ms 打字合并、
  100 帧/200 万字符双上限淘汰、新变更作废 redo）。撤销 = 快照写回 controller
  经 diff→FFI 同步，一致性天然成立。
- **关键机制**（两条都踩过）：① 每文档 FocusNode onKeyEvent 在事件分发第一站
  拦截 Ctrl+Z/Shift+Z/Y/F/H——原生 UndoHistory 在焦点链更下方注册同键；
  ② 撤销快照基线必须在 savedText 前移之前捕获（先写反过一次，端到端测试抓住）。
- **查找替换**：find_replace.dart 纯逻辑（非重叠匹配/大小写切换/从后向前
  全部替换，UTF-16+Emoji 用例）+ 编辑器右上角浮层（计数 x/y、上下导航、
  替换/全部替换）；标题栏新增「编辑」菜单。
- 测试：16 纯逻辑 + 1 端到端；全量 93 绿 + init.sh + CI 全绿。

## 今日会话（2026-10-27）：W3-2 键位注册表

- **KeybindingSet**：默认表 10 键位（逗号分隔多键位）、parseChord 解析、
  用户 keybindings.json 覆盖（追加 = 同命令重绑定、'-command' 移除、损坏逐条忽略）、
  KeybindingsStore 可注入。
- **页面接入**：全局 CallbackShortcuts 由注册表生成；编辑器级快捷键全部并入；
  F1-F3 命令化；菜单键位提示动态化（用户重绑定后菜单自动跟随）。
- **踩坑记录**：SingleActivator 没有重写 ==/hashCode（Shortcuts 走 accepts()
  分发），不能当查询键——值查询用 KeyChord。
- 用户交互复验通过（W2）；CI 两轮推送全绿。
- DoD：init.sh 全绿（Rust 41 + Flutter 76）。

## 今日会话（2026-10-26 第七轮续）：W3-1 命令面板 + CI 首跑修复

- **git push 首次执行**（8477ecc..ca26c07），CI 首跑**失败并抓到两个真问题**：
  ① mem-probe linux.rs 在返回 u64 的函数里用 `?`（Linux 路径首次被真实编译）；
  ② 5 个 widget 测试依赖 Windows 绝对路径 fixture。已修复：仓库相对 fixtureRoot
  + linux.rs and_then 归零 + 顺修侧栏标题混合分隔符切分 bug。
- **W3-1 命令面板**：CommandRegistry（11 条命令注册）+ fuzzyScore 模糊打分
  （子序列/连续/词首加权）+ QuickInput 浮层；Ctrl+Shift+P / Ctrl+P / Ctrl+B /
  Ctrl+J 全局键位（autofocus Focus 保证无焦点可达）；快速打开用有界文件索引
  （2000 上限，跳过 .git/target 等；同步 FFI 遍历大仓库会卡 UI，已知限制）。
- CI 复跑已触发（40355417691）。

## 今日会话（2026-10-26 第六轮）：W2-3 面包屑 + W2-4 会话 journal + 冒烟

- **W2-3 面包屑**：工作区相对路径段（根以下，对标 VS Code），点文件夹段唤起
  侧栏并沿祖先链展开文件树；多组各自有面包屑。
- **W2-4 会话 journal**：SessionStore（session.json 原子写盘，损坏回退）；启动恢复
  组/标签/焦点/文件树/未保存文本（journal 文本优先于磁盘；脏标记不跨重启保留，
  内容优先）；单文档文本上限 2M 字符。**顺手修正隐性 bug**：原 isDirty 是同步
  基线差值（每次 apply 后基线前移 → 脏点永不显示），新增 dirtyDisk 真磁盘脏标记。
- **实机冒烟**：W2 Release 稳态 189.9 MiB（+1.8% < 5% 护栏，≤200 线内），
  docs/baselines/2026-10-26/alula-w2-empty.md；启动级验证了两笔 Risk high 提交。
- ⚠️ 仍需人工交互复验：拆分/拖标签/强杀后 journal 恢复（真窗口操作）。
- DoD：init.sh 全绿（Rust 41 + Flutter 58）。

## 今日会话（2026-10-26 第五轮）：W2-2 编辑器组拆分

- **W2-2a 布局树分裂原语（commit 7a9d33a）**：splitLeaf（叶子→嵌套分割，权重交接，
  防重名）/removeLeaf（摘除 + 单子 split 自动折叠沿用权重；根直接子节点拒摘）+
  控制器转发 + 7 项模型测试。
- **W2-2b 编辑器组（commit 31b2ba6）**：EditorGroup（region+docs+activeDocId）替代
  全局文档列表；焦点组路由（拆分后新组获焦；点标签/编辑器切焦点；保存/补全/
  快捷键/新开文档进焦点组）；跨组跳转激活；空组自动摘除并组；「拆分编辑器」按钮。
- ⚠️ GitNexus 对 W2-2b 评 Risk high（2 文件 11 符号）——缓解：52 测试全绿含多组
  全链路 widget 测试；**待实机复验**。
- 清理：共享 _editorFocus 删除（多组下不成立）。
- DoD：init.sh 全绿（Rust 41 + Flutter 52）。

## 今日会话（2026-10-26 第四轮）：W1-3 补完 + 内存验收 + W2-1

- **W1-3 无边框窗口（完成，commit 007594a）**：开发者模式开启后接入 window_manager
  0.5.2；TitleBarStyle.hidden + DragToMoveArea + 双击最大化 + 窗口按钮；
  windowControls 开关隔离测试与插件通道。
- **W1 验收内存复测（通过，commit e633955）**：Release 实机 mem-probe 45s：
  **稳态 186.6 / 峰值 197.1 MiB**（≤200 线过；较 MVP +4.0% < 5% 护栏），
  docs/baselines/2026-10-26/alula-w1-empty.md。**feat-015 → done。**
- **W2-1 标签条交互（commit 后续）**：溢出横向滚动、中键关闭（kMiddleMouseButton）、
  Draggable/DragTarget 邻位拖动排序；widget 测试用鼠标指针拖 tab-3 到首位断言。
- **下轮首任务 W2-2 编辑器组拆分**：布局树 editor 叶子可分裂为组分割（复用
  WorkbenchGrid 引擎）；文档模型从全局 _openDocs 改为按组持有 + 焦点组路由快捷键；
  触点面大，需整轮专注做。

## 今日会话（2026-10-26 第三轮）：W1 布局骨架落地（docs/09 开始执行）

- **既有成果分 4 笔提交入库**（clippy/fmt 清理 → harness → CI → docs/09 计划）。
- **W1-1 布局树模型**：WbNode/WbSplit/WbLeaf 分割树（固定/弹性/折叠三形态）、
  moveDivider 拖拽数学（min 钳制 + 退化区间保护）、像素⇄权重双向换算无漂移、
  JSON 序列化 + defaultLayout。18 单测。commit `W1-1`。
- **W1-2 网格渲染 + 五大区**：WorkbenchGrid（分割条只在相邻弹性节点间、内置监听）、
  WorkbenchLayout 控制器（折叠记忆/唤起）；原 EditorPage 全逻辑迁 workbench_page.dart，
  旧工具栏动作拆入标题栏菜单/侧栏头部/编辑器动作区；诊断/补全/语法移入底部面板；
  main.dart 瘦身。38 测试。commit `W1-2`。
- **W1-4 布局持久化**：LayoutStore（原子写盘 + 损坏回退）、启动恢复、500ms 防抖落盘、
  dispose 冲写；layoutStore 注入点隔离测试与真实用户目录。42 测试。commit `W1-4`。
- **W1-3 无边框标题栏（已完成）**：用户开启开发者模式后接入 window_manager 0.5.2：
  TitleBarStyle.hidden + DragToMoveArea 拖拽移动 + 双击切换最大化 + -/□/× 窗口按钮
  （WindowListener 跟踪最大化态）；windowControls 显式开关隔离测试与插件通道。
- **W1 验收内存复测（已过）**：Release 实机 mem-probe 45s 采样，
  **稳态 186.6 MiB / 峰值 197.1 MiB**（≤200 验收线），较 MVP 基线 179.2 **+4.0%**
  （低于 5% 护栏，归属 = 工作台外壳），报告 docs/baselines/2026-10-26/alula-w1-empty.md。
- **feat-015 关闭（done）**：W1 全项完成。
- **决策微调**：Riverpod 推迟到 W3（命令/键位系统）引入；W1 用 ChangeNotifier +
  ListenableBuilder 已满足细粒度重建，少一个依赖。
- DoD：init.sh 全绿（Rust 41 + Flutter 43）。

## 上一会话（2026-10-26 第二轮）：工程化建设

| 项 | 结果 | 证据 |
|---|---|---|
| GitNexus 代码图谱 | ✅ 索引完成 | 796 符号 / 1681 关系 / 34 簇 / 66 执行流；`.gitnexus/run.cjs status` 报 up-to-date；CLAUDE.md / AGENTS.md 注入使用规则 |
| harness-creator 文档 | ✅ 五件套就位，validator 100/100 | AGENTS.md + CLAUDE.md（守则）、feature_list.json（14 项状态机）、progress.md（本文件）、init.sh（一键验证）、session-handoff.md |
| CI/CD | ✅ 工作流就位 | `.github/workflows/ci.yml`：Rust（fmt+clippy+test，Windows/Linux 矩阵）× Flutter（analyze+test，走真实 FFI）× harness 校验；`release.yml`：tag 触发 Windows/Linux 打包；YAML 语法已校验，**Actions 首跑待推送后确认** |
| VSCode 工作台复刻计划 | ✅ 计划成文 | `docs/09-VSCode工作台Flutter复刻计划.md`（W1–W6 里程碑 + 内存护栏） |
| 附带清理 | ✅ clippy/fmt 清零 | 修复 16 处 clippy 警告 + 全仓 cargo fmt；`build_core.sh` 补 Windows dll 支持；修复两处 init.sh 缺陷（flutter 路径解析、shell 语法） |
| 本机 DoD 复验 | ✅ init.sh 全绿 | EXIT=0：cargo test / clippy -D warnings / build_core / flutter analyze+test 全过 |

## 上一会话（2026-10-26 第一轮）：Phase 0 收尾 + Phase 1 增量 1

- 0-3 完成：rust-analyzer 全链路（诊断 7 条 / 补全 62 项 / 语法 40 token），
  截图 `docs/diagnostics/2026-10-26-lsp-demo/`。
- 0-4 完成并否决原型 A 路线（省 1.5% 内存，无竞争力），`docs/08`。
- 0-5 完成：mem-probe + bench + 首批基线 **alula 179.2 vs VS Code 959.5 MiB（−81.3%）**，
  `docs/baselines/2026-10-26/`。
- 0-7 完成：VS Code 卡死根因 = 系统提交内存耗尽，`docs/07`。
- 增量 1：文件夹→文件树→多标签→编辑→Ctrl+S 原子保存 + RA 多文件，
  截图 `docs/diagnostics/2026-10-26-phase1/`。

## 验证记录（本机，2026-10-26）

```
cargo test --workspace   → 10+12+3+2+3+1+3+4 全部 ok（41 passed, 0 failed）
flutter test (app/)      → 15 tests passed（含随机对拍 100 组与真实 FFI 闭环）
```

## Next（下一步，按 docs/03）

1. 继续关闭 P00.4 风险门：获取可用 macOS runner、处理服务身份/许可边界、在真实 DRM 主机验证 WPE GBM/DMABUF，并完成 docs/04 三轮长时多场景采样。
2. 等待用户对推送当前分支以运行 macOS workflow 的明确授权；未授权前保持分支本地，不触发 workflow。
3. P00/feat-022 完成前不启动依赖它的 P01；当前尚有跨平台、官方服务和内存验收项阻塞。
