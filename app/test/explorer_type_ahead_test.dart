import 'dart:io';

import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Explorer 节点键含原生分隔符（P05.48 已知）：归一化后用后缀匹配。
Finder _explorerNode(String fileName) => find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('explorer-node:') &&
          key.value.replaceAll(r'\', '/').endsWith('/$fileName');
    });

/// 类型导航选中态以多选高亮色呈现（`_isExplorerFileSelected` → 0xFF24476D）。
bool _isSelected(WidgetTester tester, String fileName) {
  final color = tester.widget<Container>(
    find
        .descendant(
          of: _explorerNode(fileName),
          matching: find.byType(Container),
        )
        .first,
  ).color;
  return color == const Color(0xFF24476D);
}

void main() {
  late Directory temp;
  late Directory workspace;
  late LayoutStore layoutStore;
  late SessionStore sessionStore;

  Future<void> mountPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: WorkbenchPage(
        autoFolder: workspace.path,
        layoutStore: layoutStore,
        sessionStore: sessionStore,
        keybindingsStore: KeybindingsStore(
            path: '${temp.path.replaceAll(r'\', '/')}/keybindings.json'),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> prepareWorkspace(WidgetTester tester) async {
    temp = Directory.systemTemp.createTempSync('alula-tree-typeahead');
    workspace = Directory('${temp.path}/workspace')..createSync();
    layoutStore = LayoutStore(
        path: '${temp.path.replaceAll(r'\', '/')}/layout.json');
    sessionStore = SessionStore(
        path: '${temp.path.replaceAll(r'\', '/')}/session.json');
    // 文件名首字母覆盖不同分支：alpha/beta/main + zebra（大小写混合）。
    File('${workspace.path}/alpha.txt').writeAsStringSync('a\n');
    File('${workspace.path}/beta.txt').writeAsStringSync('b\n');
    File('${workspace.path}/main.rs').writeAsStringSync('m\n');
    File('${workspace.path}/zebra.md').writeAsStringSync('z\n');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      for (var attempt = 0; attempt < 50; attempt++) {
        if (!temp.existsSync()) return;
        try {
          await temp.delete(recursive: true);
          return;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });
    await mountPage(tester);
  }

  Future<void> focusTree(WidgetTester tester) async {
    // 直接聚焦树容器（单击会打开预览并把焦点移给编辑器）。
    final focusWidget = tester.widget<Focus>(
      find.byKey(const ValueKey('explorer-tree-focus')),
    );
    focusWidget.focusNode!.requestFocus();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets(
    'typing characters jumps to the first matching visible item',
    (tester) async {
      await prepareWorkspace(tester);
      await focusTree(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pump();
      expect(_isSelected(tester, 'main.rs'), isTrue,
          reason: "typing 'm' selects main.rs");

      // 缓冲超时前继续键入：'ma' 仍匹配 main.rs。
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();
      expect(_isSelected(tester, 'main.rs'), isTrue);
    },
  );

  testWidgets(
    'the buffer resets after the idle timeout',
    (tester) async {
      await prepareWorkspace(tester);
      await focusTree(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.pump();
      expect(_isSelected(tester, 'beta.txt'), isTrue);

      // 超过 500ms 空闲后缓冲清空：'z' 从头匹配 zebra.md。
      await tester.pump(const Duration(milliseconds: 600));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.pump();
      expect(_isSelected(tester, 'zebra.md'), isTrue,
          reason: "the buffer reset so 'z' matches zebra.md");
    },
  );

  testWidgets(
    'modifier chords are ignored by type navigation',
    (tester) async {
      await prepareWorkspace(tester);
      await focusTree(tester);

      // Ctrl+M 是编辑器快捷键链的一部分，type navigation 不吞并。
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(_isSelected(tester, 'main.rs'), isFalse,
          reason: 'modifier chords do not drive type navigation');
    },
  );
}
