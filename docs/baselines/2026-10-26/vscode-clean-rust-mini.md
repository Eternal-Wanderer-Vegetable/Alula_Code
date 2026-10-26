# 内存基线：vscode-clean-rust-mini

- 可执行文件：`C:\Users\Vegetable\AppData\Local\Programs\Microsoft VS Code\Code.exe --user-data-dir=C:\Users\Vegetable\AppData\Local\Temp\alula-vsc-profile --extensions-dir=C:\Users\Vegetable\AppData\Local\Temp\alula-vsc-ext E:\Alula_Code\tests\fixtures\rust-mini`
- 平台/口径：windows / 进程树 Private Bytes
- 采样：60s，间隔 1.0s，共 60 个样本
- 采集时间：2026-10-25 23:43:18 UTC

| 指标 | Private (MiB) | Working Set (MiB) |
|---|---|---|
| 启动峰值 | 1468.9 | — |
| 稳定态（尾部 40% 中位） | 971.6 | — |
| 结束时 | 1216.8 | 1426.1 |

## 进程明细（结束时）

| PID | 进程 | Private MiB | WS MiB |
|---|---|---|---|
| 14104 | Code.exe | 322.9 | 379.6 |
| 2084 | Code.exe | 220.3 | 132.7 |
| 23632 | Code.exe | 181.6 | 186.6 |
| 27060 | Code.exe | 129.3 | 177.5 |
| 32920 | Code.exe | 99.0 | 147.0 |
| 18120 | Code.exe | 90.5 | 129.9 |
| 31136 | copilot-runtime.exe | 77.8 | 64.3 |
| 22900 | Code.exe | 68.0 | 109.2 |
| 10904 | Code.exe | 13.0 | 51.5 |
| 30376 | Code.exe | 9.2 | 33.6 |
| 36776 | conhost.exe | 1.2 | 7.1 |
