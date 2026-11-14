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

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'bridge/alula_core.dart';
import 'workbench/auxiliary_window.dart';
import 'editor/find_replace_history.dart';
import 'editor/paste_as.dart';
import 'workbench/find_history_store.dart';
import 'workbench/layout_store.dart';
import 'workbench/keybindings.dart';
import 'workbench/session_store.dart';
import 'workbench/window_chrome_configuration.dart';
import 'workbench/workbench_page.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // desktop_multi_window 新引擎重跑 main：按载荷分流到辅助编辑器窗口
  // （LAY-12a）。主引擎定义不可用时按主窗继续。
  try {
    final controller = await WindowController.fromCurrentEngine();
    final payload =
        AuxiliaryWindowPayload.fromArguments(controller.arguments);
    if (payload.isAuxiliary) {
      await runAlulaAuxiliaryEngine(payload.toArguments());
      return;
    }
  } on Object {
    // 主窗/测试环境：继续常规入口。
  }
  // 真实入口读取 native/custom chrome，再初始化原生窗口样式。
  // widget 测试直接 pump AlulaApp，不触碰窗口插件通道。
  await windowManager.ensureInitialized();
  final windowChrome = WindowChromeConfiguration.fromArguments(
    args,
    targetPlatform: defaultTargetPlatform,
  );
  // 拦截系统关闭请求，让工作台先完成 LSP shutdown/exit，再销毁窗口。
  await windowManager.setPreventClose(true);
  final options = WindowOptions(
    title: 'Alula Code',
    minimumSize: const Size(640, 400),
    titleBarStyle:
        windowChrome.isCustom ? TitleBarStyle.hidden : TitleBarStyle.normal,
    windowButtonVisibility: true,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  runApp(AlulaApp(
    autoLsp: args.contains('--lsp-auto'),
    autoFolder: args.contains('--lsp-auto') ? _demoFolder() : null,
    windowChromeConfiguration: windowChrome,
    windowControls: true,
  ));
}

/// 演示模式（--lsp-auto）自动打开的 fixture 工程（跨平台探测）。
String? _demoFolder() {
  final rel =
      Directory('${Directory.current.path}/../tests/fixtures/rust-mini');
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
    this.windowChromeConfiguration,
    this.windowControls = false,
    this.definitionRequest,
    this.savedCompareFileStat,
    this.pasteAsConfiguration = const PasteAsConfiguration(),
    this.findReplaceHistoryConfiguration =
        const FindReplaceHistoryConfiguration(),
    this.findReplaceHistoryStore,
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

  /// Launch-time native/custom title bar selection; injectable by tests.
  final WindowChromeConfiguration? windowChromeConfiguration;

  /// 启用窗口状态监听、拖动区域与适用平台的窗口控制。
  /// 默认关闭：widget 测试环境没有原生窗口通道；真实入口显式开启。
  final bool windowControls;

  /// Optional provider override used by deterministic navigation fixtures.
  final Future<DefinitionResult?> Function(
    int documentId,
    int offsetUtf16,
    int version,
  )? definitionRequest;

  /// Optional file-stat provider for deterministic saved-compare fixtures.
  final Future<FileStat> Function(String path)? savedCompareFileStat;

  /// Editor Paste As settings forwarded to the workbench.
  final PasteAsConfiguration pasteAsConfiguration;

  /// Find/replace history options are hydrated by the settings store in P07.
  final FindReplaceHistoryConfiguration findReplaceHistoryConfiguration;

  /// Optional per-workspace history store (tests can use a temporary folder).
  final FindReplaceHistoryStore? findReplaceHistoryStore;

  @override
  Widget build(BuildContext context) {
    final windowChrome = windowChromeConfiguration ??
        WindowChromeConfiguration.forPlatform(defaultTargetPlatform);
    return MaterialApp(
      title: 'Alula Code',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF14161A),
      ),
      home: WindowChromeConfigurationScope(
        configuration: windowChrome,
        child: WorkbenchPage(
          autoLsp: autoLsp,
          autoFolder: autoFolder,
          layoutStore: layoutStore,
          sessionStore: sessionStore,
          keybindingsStore: keybindingsStore,
          windowControls: windowControls,
          definitionRequest: definitionRequest,
          savedCompareFileStat: savedCompareFileStat,
          pasteAsConfiguration: pasteAsConfiguration,
          findReplaceHistoryConfiguration: findReplaceHistoryConfiguration,
          findReplaceHistoryStore: findReplaceHistoryStore,
        ),
      ),
    );
  }
}
