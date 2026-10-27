# P00.1 · 固定参考版本获取记录

日期：2026-10-27（Asia/Shanghai）
状态：P00.1 验收完成；固定 SHA 的 Code-OSS client lane 已构建并启动，环境快照与 `product.json` 内置扩展清单已导出。未找到与该 SHA 匹配的微软发行二进制；参考对象明确为固定 SHA 的 Code-OSS 源码构建，不把它冒充为微软发行物。

## 已核验的上游身份

- 仓库：`microsoft/vscode`
- 固定 commit：`4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e`
- GitHub commit API 返回该 SHA 的 tree `1eda2e0b7d26792acb7ded9945676df13e36c18b`、parent `c5f99e81a5d0ce82a55615da27c322bbe48ad00e`；GitHub 的签名校验为 `verified=true`、`reason=valid`。提交时间为 `2026-10-27T05:27:37Z`。
- GitHub 页面标题为 `[cherry-pick] [1.144] ...`；版本判断以 pinned 源码元数据为准，不以提交标题推断。
- pinned `package.json` 的 GitHub blob SHA 为 `3a076f0f8815b72de62a954a2fbe23bd547fb226`，其中 `version` 为 `1.145.0`，`distro` 为 `38ed30f01031ca05f59fb111be203efae74036c2`。
- Windows 构建副本清单 SHA-256：`package.json`=`a6f0f8b1ba8cfb8aea149f6c805a50fd63f0819da7a95ec0168d10fd89d1c570`；`package-lock.json`=`51f5155c64f8dc09b6adabe25ccc114129bf89ce89c1ad6269819c07a834afb4`；`product.json`=`104a252a18d584b91176d24d20a12b7e08ce9225cf0cb176906928c068c1a945`；`.nvmrc`=`d9f318747a126ce2247661af67852b185def7789492eabfad7bba322be087c33`；`.npmrc`=`81c68bd8031151d4363aec9632af6b6baf289f87fabcd4bfd335872ff6f69be7`；`remote/.npmrc`=`82c234978bc2c994d33ffdf92679eeae95bca9fb54ac101c9a30419473649551`。
- pinned `product.json` 的 GitHub blob SHA 为 `64e1c4d2c64e998526ce3b8ef179f45bbe29d068`；其 `builtInExtensions` 列出 `ms-vscode.js-debug-companion@1.1.3`、`ms-vscode.js-debug@1.140.0`、`ms-vscode.vscode-js-profile-table@1.0.11`，并带有各自 SHA-256。
- `package.json` 与 `product.json` 元数据来自固定 commit 的 GitHub Contents 接口；工作树由同一固定 commit 的 Git partial clone 获取。本记录的版本值不代表已完成 Code-OSS 构建或微软发行物验证。

## 官方发行物探测

VS Code 官方 FAQ 描述的下载 URL 以版本占位符和平台/渠道组成；官方网络文档将 `update.code.visualstudio.com` 列为下载/更新服务器。实际 HEAD 探测结果：

| 请求 | HTTP | 结果 |
|---|---:|---|
| `https://update.code.visualstudio.com/latest/win32-x64-archive/insider` | 302 | 重定向至 `VSCode-win32-x64-1.144.0-insider.zip`，commit `9559530ba165bcd4db3e16a1d2d72e1cb2d7991b` |
| `https://update.code.visualstudio.com/commit:4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/win32-x64-archive/insider` | 404 | 未提供该固定 SHA 的发行物 |
| `https://update.code.visualstudio.com/1.145.0/win32-x64-archive/insider` | 404 | 未提供该版本路径下的发行物 |

这只能证明上述官方 URL 路径当前不可用，不能据此宣称所有微软发行渠道均不存在该构建。当前没有找到与 pinned SHA 完全匹配的官方桌面二进制；Code-OSS 固定 SHA 源码构建仍是下一条验证路径。

本机 `code --version` 为 `1.142.0` / commit `6d62b1d5dace93a33b3a6d3eca1317bd5e15bcb1`，不是目标参考；没有发现 `code-insiders` 命令。

## 本机预启动环境快照

- Windows 查询值：`WindowsProductName=Windows 10 Pro for Workstations`、`WindowsVersion=2009`、`OsBuildNumber=26200`、x64。
- 系统 locale 与 UI culture 均为 `zh-CN`；区域短日期 `yyyy/M/d`、短时间 `H:mm`。
- NVIDIA GeForce RTX 5080 当前显示模式为 `2560×1440 @ 180 Hz`；Windows `AppliedDPI=120`（125%），Apps/System theme 注册表值均为 `0`（dark）。
- 已另行保存 Electron/renderer 实际观测值；见下方 `runtime-evidence.json` 的 `devicePixelRatio`、逻辑屏幕/窗口尺寸、实际 Workbench 主题与 locale。注册表快照仅描述启动前的 Windows 配置。

## 源码传输与构建状态

- WSL 与 Windows Git Bash 的直连 `git ls-remote` 均无响应。为只读获取公开固定源码，临时启动了限制目标为 `microsoft/vscode.git` 的本地 Git 协议 v2 流式 relay；没有改主仓库 Git 配置或凭据。
- 通过 relay 完成浅层 partial clone，`HEAD` 精确为 `4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e`，根 tree 为 `1eda2e0b7d26792acb7ded9945676df13e36c18b`。当前 sparse checkout 包含 `.vscode/`、`build/`、`extensions/`、`remote/`、`resources/`、`scripts/`、`src/`、`test/` 与根清单；`HEAD` 未变且 tracked worktree clean。
- Windows 构建副本位于仓库外：`E:\_alula_vscode_ref_4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e`。`remote/.npmrc` 的 Git blob SHA 已与 pinned tree 一致（`562a15b1a4c080355c19e89e9e20b1ba4be3ef0b`）。
- codeload tar.gz 的早期 49,152 字节残片已放弃，未用于构建。完整源码采用上述固定 Git tree，不依赖该归档。
- 固定源码 `.nvmrc` 指定 Node `24.22.1`，本机 Node 版本匹配；本机 npm `12.0.2` 低于上游安装脚本禁止的 npm 13。第一次 `npm ci` 被机器用户级 `.npmrc` 中的 `allow-scripts` 影响，嵌套 `npm ci` 报 `EALLOWSCRIPTS`。改用临时空 userconfig 后已通过；该用户设置及固定源码均未修改。该行为与 npm CLI [#9912](https://github.com/npm/cli/issues/9912) 记录的生命周期脚本环境继承问题一致。
- 第二次 `npm ci` 完成了锁文件依赖下载，但在 `@vscode/deviceid` 的 `node-gyp rebuild` 遇到 MSBuild `MSB8040`：VS 2026 的 MSVC 14.51 缺 Spectre 缓解库。已用官方安装器成功补装 `Microsoft.VisualStudio.Component.VC.14.51.x86.x64.Spectre`，对应 `lib/spectre/{x64,x86}/libcmt.lib` 均存在。微软说明 MSB8040 需安装对应 Spectre 库，且安装器支持按 component ID 增补组件：[MSB8040](https://learn.microsoft.com/en-us/visualstudio/msbuild/errors/msb8040)、[Visual Studio 安装器命令行](https://learn.microsoft.com/en-us/visualstudio/install/use-command-line-parameters-to-install-visual-studio)。
- 随后根 `npm ci` 的所有原生模块均成功编译；`foundry-local-sdk@2.0.1` 的生命周期返回 code 0。该 runtime 只用于计划排除的 Chat 语音能力，本次用 `FOUNDRY_LOCAL_SKIP_INSTALL=1` 跳过其 NuGet runtime 下载；此环境变量必须在 Windows PowerShell 进程内设置，先前从 WSL 传给 Git Bash 的标记没有传入生命周期进程。
- 根 `build/npm/postinstall.ts` 首次成功安装 `build/` 与 `remote/` 子树依赖后，按固定清单尝试 51 个 npm 子项目；当时 sparse checkout 不含 `extensions/`、`test/`、`.vscode/`，48 个子项目以 `spawn C:\\windows\\system32\\cmd.exe ENOENT` 失败。补齐这些路径后，直接重跑成功安装 `build/`，但 `remote/` 也不在当时的 sparse pattern，进入 remote 时缺 `.npmrc` 再次失败。现已将 `remote/` 加入 sparse checkout；`remote/package.json`、`remote/package-lock.json`、`remote/.npmrc` 均存在且 `HEAD` 不变。未编辑上游源码。
- Windows PowerShell 中执行 `node build/next/build-fast.ts --client-only` 成功：输出 `client=full, extensions=skip, copilot=skip`，transpile 找到 10,846 个文件并在约 21 秒完成。`node build/lib/electron.ts` 成功生成 `.build/electron/Code - OSS.exe`（239,554,048 bytes），Electron 版本为 `43.8.3`。这条路径构建桌面 client，不编译扩展或 Copilot lane；桌面启动不依赖未完成的 remote 子树安装。完整 `build/npm/postinstall.ts` 当时正下载 remote 子树依赖；在 client 构建、启动和取证完成后停止该额外安装，remote node_modules 不作为已安装或已验收内容。
- 用上游 `scripts/code.bat` 的开发启动方式（`NODE_ENV=development`、`VSCODE_DEV=1`、`VSCODE_CLI=1`、`ELECTRON_ENABLE_LOGGING=1`、`ELECTRON_ENABLE_STACK_DUMPING=1`，并把 `.` 作为启动参数）启动固定 SHA Workbench。进程用 `--disable-extensions`、独立 `.build/p00-user-data` / `.build/p00-extensions` 和本机 CDP 端口 `9222`；首次 Welcome 选择了“不登录”继续，没有进行账号或 AI 交互。随后进入 Workbench Welcome 页并保存截图。当前产品源仍显示 Chat 面板 UI；`--disable-extensions` 不会移除该内置视图，记录此差异但没有使用它。
- 环境与截图由 `docs/diagnostics/2026-10-27-p00/capture-reference.mjs` 通过本机 Chromium DevTools Protocol 采集到 `runtime-evidence.json` 和 `reference-workbench.png`。实际运行版本 `Code - OSS Dev 1.145.0`、Electron `43.8.3`、Chromium `150.0.7871.250`；renderer `devicePixelRatio=1.25`，系统显示逻辑尺寸 `2048×1152`（对应 Windows 配置 `2560×1440 @ 180 Hz`），应用 viewport `1204×804`、外窗 `1220×811`；系统 locale/UI culture 为 `zh-CN`，renderer locale 为 `en-US`，语言列表 `en-US` / `zh-Hans-CN`，时区 `Asia/Shanghai`。Workbench 实际 theme class 含 `vs-dark` 与 `vscode-theme-defaults-themes-2026-dark-json`，计算背景色 `rgb(25, 26, 27)`、字体 `Segoe WPC` / `Segoe UI`。
- 本次实际启动使用 `--disable-extensions`，没有安装或启用 marketplace 扩展；独立用户数据目录避免污染用户 VS Code。`runtime-evidence.json` 同时导出 pinned `product.json` 声明的三项默认内置扩展及版本、SHA-256：`ms-vscode.js-debug-companion@1.1.3`、`ms-vscode.js-debug@1.140.0`、`ms-vscode.vscode-js-profile-table@1.0.11`。这些是产品清单声明，不代表它们已下载或出现在此次 Code-OSS 进程中。
- 本阶段提交门运行 Windows Git Bash `bash init.sh` 成功（Rust test、clippy、build_core、Flutter 120 tests）；独立 `cargo fmt --check` 与 `E:\flutter\bin\flutter.bat analyze` 均通过。Git Bash 启动读取 UTF-16 BOM `.bashrc` 有 shell 提示，但 `init.sh` 正常完成并退出 0。

## 2026-10-28 官方发行 URL 复核

本地时间 2026-10-28 00:22（Asia/Shanghai）从 Windows Git Bash 用 `curl -sSIL` 重查官方分发地址：

| 请求 | 最终状态 | 最终地址/结果 |
|---|---:|---|
| `https://update.code.visualstudio.com/latest/win32-x64-archive/insider` | 200 | `VSCode-win32-x64-1.144.0-insider.zip`；发行路径 revision token `abc2b20cb3e724689f78f5d2a3c231589b25483c` |
| `https://update.code.visualstudio.com/commit:4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/win32-x64-archive/insider` | 404 | 固定 SHA 地址无此发行物 |
| `https://update.code.visualstudio.com/1.145.0/win32-x64-archive/insider` | 404 | 固定源码版本号地址无此发行物 |

该次复核与前面的探测一致：当前 `latest/insider` 仍是不同版本/提交，不能替代 pinned Code-OSS 1.145.0；只证明这些官方 URL 当前不可用，不推断其它发行渠道不存在。Code-OSS 固定 SHA 构建仍是可重放桌面对照；微软同 SHA 二进制保持 unavailable/blocker。

## 验收边界与下一步

P00.1 已按 Code-OSS 固定 SHA 源码路径完成验收：上游身份/签名和版本元数据可核验、微软精确发行物探测结果已登记、桌面 client 可构建与启动，环境及产品声明的默认扩展包清单已有可复核文件。限制是这不是微软签名发行包；未下载 marketplace 扩展，未构建 Copilot / remote lane，也未覆盖登录、同步、市场、Web 与官方服务。P00.2 原子注册项导出器现在具备 pinned 源码与运行时参考，仍需按 `docs/03` 顺序单独开工。
