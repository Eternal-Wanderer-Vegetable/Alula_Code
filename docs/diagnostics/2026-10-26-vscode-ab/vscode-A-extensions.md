# 内存基线：vscode-A-extensions

- 可执行文件：`C:\Users\Vegetable\AppData\Local\Programs\Microsoft VS Code\Code.exe --user-data-dir=C:\Users\VEGETA~1\AppData\Local\Temp\vsdiag-A-ext-profile --extensions-dir=C:\Users\Vegetable\.vscode\extensions E:\Alula_Code\tests\fixtures\rust-mini`
- 平台/口径：windows / 进程树 Private Bytes
- 采样：45s，间隔 1.0s，共 45 个样本
- 采集时间：2026-10-26 01:39:34 UTC

| 指标 | Private (MiB) | Working Set (MiB) |
|---|---|---|
| 启动峰值 | 2051.7 | — |
| 稳定态（尾部 40% 中位） | 1257.5 | — |
| 结束时 | 1224.5 | 1703.1 |

## 进程明细（结束时）

| PID | 进程 | Private MiB | WS MiB |
|---|---|---|---|
| 31652 | Code.exe | 240.0 | 305.7 |
| 33296 | Code.exe | 181.3 | 227.2 |
| 35580 | Code.exe | 175.1 | 180.4 |
| 18880 | Code.exe | 171.9 | 131.7 |
| 18896 | Code.exe | 126.9 | 127.4 |
| 4564 | Code.exe | 107.5 | 159.2 |
| 35300 | Code.exe | 65.2 | 105.2 |
| 5436 | Code.exe | 51.2 | 133.3 |
| 33872 | Code.exe | 41.1 | 120.4 |
| 10396 | Code.exe | 40.7 | 124.8 |
| 8756 | Code.exe | 15.2 | 55.3 |
| 11508 | Code.exe | 9.2 | 33.6 |
