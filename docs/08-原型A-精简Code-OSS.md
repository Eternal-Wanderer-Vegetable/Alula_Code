# 08 · 原型 A：精简 Code-OSS 实验报告（Phase 0 任务 0-4）

> 日期：2026-10-26 · 对应 G1 判据与 0-6 对照实验的无插件组
> 环境：Windows 11 25H2 · 源码版本 code-oss-dev 1.144.0（2026-10 主线）
> 仓库：E:scode-oss（浅克隆）· 复现脚本：`rebuild-natives.sh`、`install-ext-deps.mjs`、`tools/diag-ab.ps1`

## 实验设计与过程

1. 浅克隆 microsoft/vscode（MIT，Code-OSS）→ `npm install` → `npx gulp compile` →
   preLaunch 下载 Electron → dev 构建可运行。
2. mem-probe（进程树 Private Bytes 口径）采样 10×3s，打开 rust-mini fixture。
3. 减法：移除 **84+2 个内置扩展**（保留 git、merge-conflict、主题、JSON、配置编辑、
   搜索/引用视图、日志、各语言 grammar），重启复测。
4. 全程记录构建期遇到的问题（见附录）。

## 结果

| 配置 | 进程数 | 启动峰值 | 稳态 |
|---|---|---|---|
| 原型 A · 全量内置扩展 | 8 | 1518.1 MiB | **≈1310 MiB** |
| 原型 A · 精简后（-86 个扩展） | 8 | 1474.8 MiB | **≈1290 MiB** |
| （对照）VS Code 稳定版 · 无扩展 | 9 | 1476.1 | 989.9 |
| （对照）VS Code 稳定版 · 25 扩展 | 12 | 2051.7 | 1257.5 |
| （对照）**alula MVP · 空工作台** | **1** | 180.2 | **179.2** |

## 结论

1. **移除 86 个内置扩展仅节省 ≈20 MiB（−1.5%）**——VS Code 的内存大头是工作台本体
   （Electron 多进程 + 未压缩 dev 代码 + 全量加载的工作台模块），不是内置扩展。
   「给 Code-OSS 做减法」这条路收益甚微。
2. **G1 判据判定：数据支持自研路线**。alula（179.2 MiB）比 dev 版 Code-OSS 小
   ≈7.3 倍、比打包版 VS Code 干净实例小 ≈5.4 倍，且原型 A 的架构（Electron +
   Node 工作台）决定了它无法逼近 alula 的量级。
3. 诚实性说明：
   - Code-OSS 测的是 **dev 构建**（未 minify、非 ASAR 打包），比官方打包版重；
     但减法前后同为 dev 构建，**减法收益（−1.5%）这一相对结论不受影响**；
   - 原型 A 移除了 Copilot 编译链、遥测设备 ID、selfhost 测试扩展（构建期减法）；
   - remote/ 目录依赖安装失败，桌面构建不需要它，已忽略。

## 构建期问题记录（复现者必读）

| 问题 | 解决 |
|---|---|
| preinstall.ts 内嵌套 npm 被 .npmrc 的 npm_config_* 污染 | 局部剥离环境变量（preinstall.ts 已打补丁） |
| @vscode/deviceid 需要 Spectre 缓解库（MSB8040） | 移除该依赖（遥测设备 ID 用 uuid 兜底） |
| compile-copilot 模块缺失 | 从编译链移除（原型不需要 Copilot） |
| build/、extensions/ 等子目录依赖未装/装坏 | `VSCODE_FORCE_INSTALL=1 npm run postinstall` + 逐目录 npm install（install-ext-deps.mjs） |
| 扩展构建脚本找不到 esbuild | 根 devDependencies 补 esbuild@0.27.2 |
| 原生模块 ABI 不匹配（按 Node 头编译） | rebuild-natives.sh：node-gyp configure --target=43.8.3 + MSBuild /p:SpectreMitigation=false |

## 对 G1 的最终建议

原型 A 路线（继承 Code-OSS 架构做减法）在内存目标上**不具备竞争力**，
建议 G1 正式判定：**采用原型 B 路线（alula：Flutter + Rust 自研核心）**，
Code-OSS 仓库保留作参考（工作台行为、协议实现细节），不再投入构建维护。
