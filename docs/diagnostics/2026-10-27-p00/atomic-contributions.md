# P00.2 原子贡献项与运行时注册表

## 结论

固定源码 `microsoft/vscode@4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e`（版本 1.145.0，tree `1eda2e0b7d26792acb7ded9945676df13e36c18b`）的原子登记表已生成。它交叉记录源码 AST、95 个仓库内扩展 manifest、`product.json` 和隔离 Code-OSS 开发宿主的公开运行时注册 API。每条记录都有唯一 `registration_id`、来源路径/行/源码 blob SHA、运行时可达状态、A–G 路由候选、feature/case 候选和未决原因。

此账本是后续逐项签收的来源索引，不代表项目语义覆盖或 Alula 已实现。目录路由仍只是候选；未知项保留在 `unresolved`，没有用推测值补齐。

## 生成与复核

从 Alula 仓库根目录执行：

```bash
node tools/vscode-parity/export-atomic-contributions.mjs \
  --source=/mnt/e/_alula_vscode_ref_4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e
```

导出器会拒绝非固定 SHA/tree 输入，并记录源清单、feature 矩阵、内置 manifest 索引和运行时快照的 SHA-256。TypeScript AST 使用固定源码安装的 TypeScript 解析；脚本覆盖 Action2、编辑器动作、命令、菜单/子菜单、键位、配置、服务、语言、视图、主题及 provider 注册，以及 manifest 中所有 `contributes`、激活事件和扩展依赖。

隔离探针通过 `vscode.commands.getCommands(false)`、`vscode.languages.getLanguages()`、`workspace.getConfiguration().inspect(key)` 和 `vscode.extensions.all` 导出 registry。探针扩展 ID 为 `alula-internal.alula-vscode-runtime-registry-probe`，`productFeature=false`，不计入产品扩展数。

## 当前数量

| 数据 | 结果 |
|---|---:|
| AST 候选源 | 14,811 个跟踪 TS/JS 文件；其中 1,490 个文件含注册候选并进入 AST 解析 |
| AST 注册调用 | 6,766 次；38 次未能物化为原子值 |
| 原子登记记录 | 12,958 条，其中源码/manifest/product 项 10,818 条、运行时独有 ID 2,140 条；`registration_id` 唯一数 12,958，重复数 0 |
| 根扩展 manifest | 95 个；另记录 `product.json` 中 3 个外部内置扩展和 9 个产品开关 |
| 来源与运行时字段 | 12,958 条都有来源路径和可达状态；9,832 条带源码行号 |
| 候选 A–G 路由 | 8,683 条有目录范围候选；2,135 条源码项无匹配目录路由，另有 2,140 条运行时独有项没有源码路由，均标为未分类并保留原因 |
| 候选 feature/case 路由 | 8,679 条有 feature 候选；2,139 条源码项无功能族路由，另有 2,140 条运行时独有项无 feature 路由，均标为未映射并保留原因 |
| 未决登记 | 3,453 条没有稳定 ID；总计 6,828 个注册 ID/路由项目留在 `unresolved` |
| 既有目录发现 | 462 项中 131 项仍需判断可达性或混合依赖 |

命令对账：源码静态 1,709 个唯一 ID，运行时 2,684 个，匹配 580 个，源码独有 1,129 个，运行时独有 2,104 个。配置对账：源码静态 1,256 个、运行时 1,289 个，匹配 1,256 个，另有 33 个运行时独有。语言对账：源码静态 77 个、运行时 5 个，匹配 2 个，源码独有 75 个、运行时独有 3 个。扩展对账：源码 manifest 95 个；本次运行时快照排除探针后为 0 个。

运行时快照是在 client-only 开发构建中采集；其 extension host 只发现探针扩展，5 种核心语言也不含 manifest 扩展提供的语言。这个结果表示当前参考构建没有加载内置扩展 payload，不能解释为上游产品没有这些扩展。菜单、键位、provider、主题及多数服务通过源码/manifest 静态登记，并明确标为 `static-only`；公开 API 不提供完整的运行时枚举接口。

## 产物

- `atomic-contributions.json`：逐项 ledger、四类 registry 对账数组、未决发现和未决登记项。
- `atomic-contributions-summary.json`：统计与对账计数。
- `runtime-registry.json`：隔离开发宿主快照。
- `runtime-configuration-candidates.json`：运行时配置检查使用的配置键输入。
- [`export-atomic-contributions.mjs`](../../../tools/vscode-parity/export-atomic-contributions.mjs)：可重放 AST/manifest/product/runtime 导出器。
- [`runtime-probe/`](../../../tools/vscode-parity/runtime-probe/)：只用于固定源码开发宿主的临时探针扩展。
- `p00.2-validation.log`：仓库 DoD 命令结果。

## 验证与提交前影响分析

`bash init.sh`、`cargo fmt --check`、`flutter analyze` 均以 EXIT=0 结束；完整输出见 `p00.2-validation.log`。Node 导出器语法检查与 12,958 条结构/唯一 ID/对账不变量核验通过。

GitNexus 全工作树检查包含此前已有的 README 与 `app/lib/workbench/` 修改，报告 48 个文件、264 个符号、20 个流程，risk=critical。仅分析已暂存的本阶段文件时，报告 19 个文件、248 个符号、17 个流程，risk=critical，主要命中新导出器自身的 AST→manifest→ledger 调用流程与文档章节；暂存集合没有 Alula 产品源码。上述高风险结果保留，不把共享轴或空调用集当作豁免。

候选 feature 路由尚未签收为映射（所有记录的 `mapped_feature_ids` 与 `case_ids` 仍为空）。下一步应先复核无目录路由、无 feature 路由和无稳定 ID 的记录，再将已确认项目映射到 Alula 实现、`case_id` 与证据。当前候选数量不应作为功能覆盖率。
