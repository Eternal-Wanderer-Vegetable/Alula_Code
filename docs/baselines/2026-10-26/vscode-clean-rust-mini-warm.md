# 内存基线：vscode-clean-rust-mini-warm

- 可执行文件：`C:\Users\Vegetable\AppData\Local\Programs\Microsoft VS Code\Code.exe --user-data-dir=C:\Users\Vegetable\AppData\Local\Temp\alula-vsc-profile --extensions-dir=C:\Users\Vegetable\AppData\Local\Temp\alula-vsc-ext E:\Alula_Code\tests\fixtures\rust-mini`
- 平台/口径：windows / 进程树 Private Bytes
- 采样：60s，间隔 1.0s，共 60 个样本
- 采集时间：2026-10-25 23:44:48 UTC

| 指标 | Private (MiB) | Working Set (MiB) |
|---|---|---|
| 启动峰值 | 1511.8 | — |
| 稳定态（尾部 40% 中位） | 959.5 | — |
| 结束时 | 959.5 | 1277.4 |

## 进程明细（结束时）

| PID | 进程 | Private MiB | WS MiB |
|---|---|---|---|
| 13752 | Code.exe | 191.5 | 269.9 |
| 34192 | Code.exe | 172.6 | 178.9 |
| 15504 | Code.exe | 122.7 | 172.5 |
| 21520 | Code.exe | 120.7 | 119.1 |
| 34840 | Code.exe | 100.6 | 149.4 |
| 16436 | Code.exe | 84.7 | 124.7 |
| 36164 | copilot-runtime.exe | 75.4 | 62.7 |
| 7148 | Code.exe | 66.3 | 105.6 |
| 36828 | Code.exe | 13.4 | 52.6 |
| 33880 | Code.exe | 9.2 | 33.7 |
| 35984 | conhost.exe | 1.2 | 7.1 |
