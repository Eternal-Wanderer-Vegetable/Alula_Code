/// Alula Code — 应用入口。
///
/// 工作台实现已按 docs/09 拆分到 lib/workbench/：
/// - workbench_page.dart  页面与编辑闭环逻辑
/// - layout_model.dart    分割树布局模型（纯模型）
/// - layout_controller.dart 布局状态
/// - layout_grid.dart     分割树渲染
/// - title_bar / activity_bar / status_bar.dart 区域组件
library;

import 'package:flutter/material.dart';

import 'workbench/workbench_page.dart';

void main(List<String> args) {
  runApp(AlulaApp(
    autoLsp: args.contains('--lsp-auto'),
    autoFolder: args.contains('--lsp-auto')
        ? r'E:\Alula_Code\tests\fixtures\rust-mini'
        : null,
  ));
}

class AlulaApp extends StatelessWidget {
  const AlulaApp({super.key, this.autoLsp = false, this.autoFolder});

  /// 启动即自动拉起 rust-analyzer（演示/自动化验证用）。
  final bool autoLsp;

  /// 随 autoLsp 一起自动打开的文件夹。
  final String? autoFolder;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Alula Code',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF14161A),
      ),
      home: WorkbenchPage(autoLsp: autoLsp, autoFolder: autoFolder),
    );
  }
}
