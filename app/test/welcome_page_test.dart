import 'dart:io';

import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/recent_history_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/file_paths.dart';

late Directory temp;
late LayoutStore layoutStore;
late SessionStore sessionStore;

void main() {
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('alula_welcome');
    final root = temp.path.replaceAll(r'\', '/');
    layoutStore = LayoutStore(path: '$root/layout.json');
    sessionStore = SessionStore(path: '$root/session.json');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  testWidgets(
      'palette command opens the welcome page and close restores the editor',
      (tester) async {
    await _mountApp(tester);
    try {
      expect(find.byKey(const ValueKey('welcome-page')), findsNothing);
      await _runPaletteCommand(tester, '欢迎', '帮助: 欢迎');

      expect(find.byKey(const ValueKey('welcome-page')), findsOneWidget);
      expect(find.byKey(const ValueKey('wb-region-editor')), findsNothing,
          reason: '欢迎页替代编辑器网格');
      expect(find.byKey(const ValueKey('welcome-section-开始')), findsOneWidget);
      expect(find.byKey(const ValueKey('welcome-section-帮助')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('welcome-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('welcome-page')), findsNothing);
      expect(find.byKey(const ValueKey('wb-region-editor')), findsOneWidget);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('welcome actions run their command and hide the page',
      (tester) async {
    await _mountApp(tester);
    try {
      await _runPaletteCommand(tester, '欢迎', '帮助: 欢迎');
      await tester.tap(
          find.byKey(const ValueKey('welcome-action-view.commandPalette')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('welcome-page')), findsNothing,
          reason: '选择欢迎条目后收回欢迎页');
      expect(find.byKey(const ValueKey('quick-input')), findsOneWidget,
          reason: '欢迎条目执行的是真实命令（命令面板）');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await _runPaletteCommand(tester, '欢迎', '帮助: 欢迎');
      await tester.tap(find.byKey(const ValueKey(
          'welcome-action-workbench.action.files.newUntitledFile')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('welcome-page')), findsNothing);
      expect(find.byKey(const ValueKey('wb-region-editor')), findsOneWidget);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('welcome visibility survives a session restore', (tester) async {
    await _mountApp(tester);
    try {
      await _runPaletteCommand(tester, '欢迎', '帮助: 欢迎');
      await tester.pump(const Duration(milliseconds: 700));

      await _unmountApp(tester);
      await _mountApp(tester);
      expect(find.byKey(const ValueKey('welcome-page')), findsOneWidget,
          reason: '会话 journal 恢复欢迎页状态');

      await tester.tap(find.byKey(const ValueKey('welcome-close')));
      await tester.pump(const Duration(milliseconds: 700));
      await _unmountApp(tester);
      await _mountApp(tester);
      expect(find.byKey(const ValueKey('welcome-page')), findsNothing);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('empty editor group watermark offers its entries',
      (tester) async {
    await _mountApp(tester);
    try {
      await _runPaletteCommand(tester, '关闭所有编辑器', '编辑器: 关闭所有编辑器（保留固定项）');
      expect(
          find.byKey(const ValueKey('empty-group-watermark')), findsOneWidget);
      expect(find.text('此编辑器组没有打开的文件'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('watermark-show-welcome')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('welcome-page')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('welcome-close')));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('empty-group-watermark')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey(
          'watermark-action-workbench.action.files.newUntitledFile')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('empty-group-watermark')), findsNothing,
          reason: 'watermark 的“新建文件”打开文档');
      expect(find.byKey(const ValueKey('wb-region-editor')), findsOneWidget);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('welcome recent section opens a persisted recent file',
      (tester) async {
    final file = File('${temp.path}/recent-note.txt')
      ..writeAsStringSync('recent');
    final store = RecentHistoryStore(
      path: '${sessionStore.resolvePath()}.recent-history',
    );
    expect(store.recordFile(file.path), isTrue);

    await _mountApp(tester);
    try {
      await _runPaletteCommand(tester, '欢迎', '帮助: 欢迎');
      expect(find.byKey(const ValueKey('welcome-section-最近')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('welcome-recent-file-0')), findsOneWidget);
      expect(find.text('recent-note.txt'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('welcome-recent-file-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('welcome-page')), findsNothing);
      expect(find.byKey(const ValueKey('tab-2')), findsOneWidget,
          reason: 'Welcome 最近项打开磁盘文件');
      expect(store.load().files.first.path, nativeTestPath(file.path));
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('File > Open Recent lists workspaces before files and opens one',
      (tester) async {
    final workspace = Directory('${temp.path}/recent-project')..createSync();
    final olderWorkspace = Directory('${temp.path}/older-project')
      ..createSync();
    final file = File('${temp.path}/recent-file.txt')
      ..writeAsStringSync('recent');
    final store = RecentHistoryStore(
      path: '${sessionStore.resolvePath()}.recent-history',
    );
    store.recordFile(file.path);
    store.recordWorkspace(olderWorkspace.path);
    store.recordWorkspace(workspace.path);

    await _mountApp(tester);
    try {
      await tester.tap(find.text('文件(F)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开最近'));
      await tester.pumpAndSettle();

      final workspaceItem = find.textContaining('recent-project');
      final olderWorkspaceItem = find.textContaining('older-project');
      final fileItem = find.textContaining('recent-file.txt');
      expect(workspaceItem, findsOneWidget);
      expect(olderWorkspaceItem, findsOneWidget);
      expect(fileItem, findsOneWidget);
      expect(tester.getTopLeft(workspaceItem).dy,
          lessThan(tester.getTopLeft(fileItem).dy),
          reason: 'File 菜单工作区排在文件之前');

      await tester.tap(olderWorkspaceItem);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      expect(store.load().workspaces.first.path,
          nativeTestPath(olderWorkspace.path),
          reason: '成功打开工作区后更新文件夹 MRU');
      expect(sessionStore.tryLoad()?['workspace'],
          nativeTestPath(olderWorkspace.path),
          reason: 'File > Open Recent 打开所选工作区');
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('empty Open Recent menu stays visible and disabled',
      (tester) async {
    await _mountApp(tester);
    try {
      await tester.tap(find.text('文件(F)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开最近'));
      await tester.pumpAndSettle();

      final placeholder = find.text('暂无最近项目');
      expect(placeholder, findsOneWidget);
      final menuItem = find.ancestor(
        of: placeholder,
        matching: find.byType(MenuItemButton),
      );
      expect(menuItem, findsOneWidget);
      expect(tester.widget<MenuItemButton>(menuItem).onPressed, isNull);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('Open Recent menu is capped at ten entries for each kind',
      (tester) async {
    final store = RecentHistoryStore(
      path: '${sessionStore.resolvePath()}.recent-history',
    );
    for (var index = 0; index < 12; index++) {
      final workspace = Directory('${temp.path}/project-$index')..createSync();
      final file = File('${temp.path}/recent-file-$index.txt')
        ..writeAsStringSync('recent');
      store.recordWorkspace(workspace.path);
      store.recordFile(file.path);
    }

    await _mountApp(tester);
    try {
      await tester.tap(find.text('文件(F)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开最近'));
      await tester.pumpAndSettle();

      expect(find.textContaining('project-').evaluate(), hasLength(10));
      expect(find.textContaining('recent-file-').evaluate(), hasLength(10));
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('startup prunes stale recent paths and explains the cleanup',
      (tester) async {
    final store = RecentHistoryStore(
      path: '${sessionStore.resolvePath()}.recent-history',
    );
    expect(store.recordFile('${temp.path}/gone.txt'), isTrue);

    await _mountApp(tester);
    try {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(store.load().isEmpty, isTrue);
      expect(find.text('已从最近项目移除 1 个不存在的路径。'), findsOneWidget);
    } finally {
      await _unmountApp(tester);
    }
  });
}

Future<void> _runPaletteCommand(
    WidgetTester tester, String query, String key) async {
  if (find.byKey(const ValueKey('quick-input')).evaluate().isEmpty) {
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();
  }
  await tester.enterText(
    find.descendant(
      of: find.byKey(const ValueKey('quick-input')),
      matching: find.byType(TextField),
    ),
    query,
  );
  await tester.pumpAndSettle();
  final item = find.byKey(ValueKey('qi-$key'));
  expect(item, findsOneWidget, reason: '命令 $key 应出现在命令面板');
  await tester.tap(item);
  await tester.pumpAndSettle();
}

Future<void> _mountApp(WidgetTester tester) async {
  await tester.pumpWidget(AlulaApp(
    layoutStore: layoutStore,
    sessionStore: sessionStore,
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _unmountApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}
