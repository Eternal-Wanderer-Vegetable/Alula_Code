# 内存基线：p04.101-candidate

- 可执行文件：`/home/vegetable/develop/flutter/bin/cache/dart-sdk/bin/dartvm docs/diagnostics/2026-11-04-p04/evidence/p04.101-projection-probe.dart.txt candidate`
- 平台/口径：linux / 进程树 Private Bytes（含 PSS）
- 采样：15s，间隔 0.5s，共 30 个样本
- 采集时间：2026-11-03 17:44:50 UTC

| 指标 | Private (MiB) | Working Set (MiB) |
|---|---|---|
| 启动峰值 | 187.2 | — |
| 稳定态（尾部 40% 中位） | 187.2 | — |
| 结束时 | 187.2 | 189.4 |

## 进程明细（结束时）

| PID | 进程 | Private MiB | WS MiB |
|---|---|---|---|
| 855870 | dart:p04.101-pr | 187.2 | 189.4 |
