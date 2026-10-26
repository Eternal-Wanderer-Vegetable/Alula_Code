# alula_app — Alula Code MVP（原型 B）

Flutter 工作台 + Rust 核心的最小闭环（对应 docs/03 Phase 0 任务 0-1）。

每次在编辑区输入，应用会：
1. 对前后文本做 diff，得到增量操作（UTF-16 口径，见 `lib/editor/text_diff.dart`）；
2. 通过 FFI 提交给 Rust 核心（`crates/editor-core`，Ropey 缓冲区）；
3. Rust 应用后回执新版本号，状态栏显示「已同步 vN」与耗时；
4. 「校验一致性」按钮会从 Rust 拉取权威全文与本地逐字符比对。

## 运行步骤

前置：安装 Flutter SDK（3.24+，含 Dart），`flutter doctor` 通过；Rust 工具链在位。

```powershell
# 1. 生成平台目录（windows/ 等；不会覆盖已存在的 lib/、pubspec.yaml、test/）
cd app
flutter create --platforms=windows --project-name alula_app .

# 2. 构建并拷贝核心动态库（在仓库根目录）
cd ..
.\scripts\build_core.ps1        # Linux/macOS: bash scripts/build_core.sh

# 3. 运行
cd app
flutter run -d windows          # 或 -d linux / -d macos

# 4. 测试
flutter test                    # text_diff_test 纯 Dart；core_sync_test 走真实 FFI
```

## 目录

```
lib/
├── main.dart               # 最小工作台：编辑区 + 同步状态栏
├── bridge/alula_ffi.dart   # dart:ffi 原始绑定 + 动态库加载
├── bridge/alula_core.dart  # 协议封装：TextOp、版本管理、失配/重同步
└── editor/text_diff.dart   # 前后文本 diff → op（MVP 过渡，见 docs/02 §5）
```

## 已知边界（MVP 刻意为之）

- 编辑控件是 `TextField` + 前后 diff，不是真正的代码编辑器组件；
  Phase 0 组件评测（CodeForge/Re-Editor 等）完成后再替换（docs/03 §1.2）。
- FFI 为手写 C ABI + JSON 承载语义，未用 flutter_rust_bridge 代码生成；
  ABI 面窄，后续迁移 FRB 时只替换 `lib/bridge/`（docs/02 §2.2）。
- 单文档（id=1），无文件打开/保存——文件系统属 editor-workspace（Phase 1）。
