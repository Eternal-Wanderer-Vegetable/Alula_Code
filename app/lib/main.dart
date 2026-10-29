/// Alula Code — 应用入口。
///
/// 工作台实现已按 docs/09 拆分到 lib/workbench/：
/// - workbench_page.dart  页面与编辑闭环逻辑
/// - layout_model.dart    分割树布局模型（纯模型）
/// - layout_controller.dart 布局状态
/// - layout_grid.dart     分割树渲染
/// - title_bar / activity_bar / status_bar.dart 区域组件
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'workbench/layout_store.dart';
import 'workbench/keybindings.dart';
import 'workbench/session_store.dart';
import 'workbench/workbench_page.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // 无边框窗口（W1-3）：原生标题栏隐藏，自绘标题栏接管拖拽与窗口控制。
  // 仅真实入口执行；widget 测试直接 pump AlulaApp，不触碰插件。
  await windowManager.ensureInitialized();
  // 拦截系统关闭请求，让工作台先完成 LSP shutdown/exit，再销毁窗口。
  await windowManager.setPreventClose(true);
  const options = WindowOptions(
    title: 'Alula Code',
    minimumSize: Size(640, 400),
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  runApp(AlulaApp(
    autoLsp: args.contains('--lsp-auto'),
    autoFolder: args.contains('--lsp-auto') ? _demoFolder() : null,
    windowControls: true,
  ));
}

/// 演示模式（--lsp-auto）自动打开的 fixture 工程（跨平台探测）。
String? _demoFolder() {
  final rel = Directory('${Directory.current.path}/../tests/fixtures/rust-mini');
  if (rel.existsSync()) return rel.path;
  return null;
}

class AlulaApp extends StatelessWidget {
  const AlulaApp({
    super.key,
    this.autoLsp = false,
    this.autoFolder,
    this.layoutStore,
    this.sessionStore,
    this.keybindingsStore,
    this.windowControls = false,
  });

  /// 启动即自动拉起 rust-analyzer（演示/自动化验证用）。
  final bool autoLsp;

  /// 随 autoLsp 一起自动打开的文件夹。
  final String? autoFolder;

  /// 布局持久化注入点（测试用临时路径；默认真实用户目录）。
  final LayoutStore? layoutStore;

  /// 会话 journal 注入点（测试用临时路径；默认真实用户目录）。
  final SessionStore? sessionStore;

  /// 键位覆盖文件注入点（测试用临时路径；默认真实用户目录）。
  final KeybindingsStore? keybindingsStore;

  /// 自绘窗口控制按钮（- □ ×）与拖拽移动区。
  /// 默认关闭：widget 测试环境没有 window_manager 插件通道；
  /// 真实入口 main() 显式开启。
  final bool windowControls;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Alula Code',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF14161A),
      ),
      home: WorkbenchPage(
        autoLsp: autoLsp,
        autoFolder: autoFolder,
        layoutStore: layoutStore,
        sessionStore: sessionStore,
        keybindingsStore: keybindingsStore,
        windowControls: windowControls,
      ),
    );
  }
}
