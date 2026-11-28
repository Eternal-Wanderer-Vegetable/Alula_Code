import 'dart:convert';
import 'dart:io';

import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_grid.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  late Directory temp;
  late Directory workspace;
  late LayoutStore layoutStore;
  late SessionStore sessionStore;
  CommandService? commands;

  String baseOf() => temp.path.replaceAll(r'\', '/');

  Finder zenStrip(String region) =>
      find.byKey(ValueKey('editor-tab-strip-$region'));

  Future<void> mountPage(WidgetTester tester,
      {bool windowControls = false}) async {
    tester.view.physicalSize = const Size(2400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: WorkbenchPage(
        autoFolder: workspace.path,
        layoutStore: layoutStore,
        sessionStore: sessionStore,
        keybindingsStore:
            KeybindingsStore(path: '${baseOf()}/keybindings.json'),
        windowControls: windowControls,
        onCommandServiceReady: (service) => commands = service,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    expect(commands, isNotNull);
  }

  Future<void> prepareWorkspace(
    WidgetTester tester, {
    bool zenMode = false,
    bool windowControls = false,
  }) async {
    temp = Directory.systemTemp.createTempSync('alula-zen-mode');
    workspace = Directory('${temp.path}/workspace')..createSync();
    final base = temp.path.replaceAll(r'\', '/');
    layoutStore = LayoutStore(path: '$base/layout.json');
    sessionStore = SessionStore(path: '$base/session.json');
    File('${baseOf()}/session.json').writeAsStringSync(jsonEncode({
      'v': 1,
      'editorTabMode': 'multiple',
      'zenMode': zenMode,
      'groups': <Object?>[],
    }));
    File('${workspace.path}/main.rs').writeAsStringSync('fn main() {}\n');
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
    await mountPage(tester, windowControls: windowControls);
  }

  Future<void> execute(WidgetTester tester, String command) async {
    expect(
      await commands!.execute(command),
      CommandExecutionStatus.executed,
      reason: '$command is registered and callable',
    );
    await tester.pump(const Duration(milliseconds: 700));
  }

  void Function(bool) installNativeFullscreen(
    WidgetTester tester,
    List<bool> requests, {
    bool fullscreen = false,
    bool Function()? isVisible,
  }) {
    var state = fullscreen;
    final messenger = tester.binding.defaultBinaryMessenger;
    const channel = MethodChannel('window_manager');
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'isFullScreen':
          return state;
        case 'isVisible':
          return isVisible?.call() ?? true;
        case 'setFullScreen':
          state = (call.arguments as Map)['isFullScreen'] as bool;
          requests.add(state);
          return null;
        case 'isMaximized':
        case 'isMinimized':
        case 'isFocused':
        case 'isAlwaysOnTop':
          return false;
        default:
          return null;
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    return (value) {
      state = value;
    };
  }

  for (final alreadyFullscreen in [false, true]) {
    testWidgets(
      'zen only restores fullscreen when it entered it ($alreadyFullscreen)',
      (tester) async {
        final requests = <bool>[];
        installNativeFullscreen(tester, requests,
            fullscreen: alreadyFullscreen);
        await prepareWorkspace(tester, windowControls: true);
        await execute(tester, 'workbench.action.toggleZenMode');
        expect(find.text('文件(F)'), findsNothing);
        expect(requests, alreadyFullscreen ? isEmpty : [true]);

        await execute(tester, 'workbench.action.toggleZenMode');
        expect(find.text('文件(F)'), findsOneWidget);
        expect(requests, alreadyFullscreen ? isEmpty : [true, false]);
      },
    );
  }

  testWidgets('externally leaving Zen-owned fullscreen restores the shell',
      (tester) async {
    final requests = <bool>[];
    final nativeChanged = installNativeFullscreen(tester, requests);
    await prepareWorkspace(tester, windowControls: true);
    await execute(tester, 'workbench.action.toggleZenMode');
    expect(find.text('文件(F)'), findsNothing);

    nativeChanged(false);
    final listener = tester.state(find.byType(WorkbenchPage)) as WindowListener;
    listener.onWindowLeaveFullScreen();
    await tester.pumpAndSettle();
    expect(find.text('文件(F)'), findsOneWidget);
    expect(requests, [true]);
  });

  testWidgets('viewport changes recover an unreported fullscreen exit',
      (tester) async {
    final requests = <bool>[];
    final nativeChanged = installNativeFullscreen(tester, requests);
    await prepareWorkspace(tester, windowControls: true);
    await execute(tester, 'workbench.action.toggleZenMode');

    tester.view.physicalSize = const Size(2300, 1000);
    await tester.pumpAndSettle();
    expect(find.text('文件(F)'), findsNothing);

    nativeChanged(false);
    tester.view.physicalSize = const Size(1150, 750);
    tester.view.physicalSize = const Size(1149, 749);
    await tester.pumpAndSettle();
    expect(find.text('文件(F)'), findsOneWidget);
    expect(requests, [true]);
  });

  testWidgets(
    'toggling zen mode hides the shell chrome and centers the editor',
    (tester) async {
      await prepareWorkspace(tester);
      expect(find.text('文件(F)'), findsOneWidget);
      expect(zenStrip('editor'), findsOneWidget);

      await execute(tester, 'workbench.action.toggleZenMode');
      await tester.pumpAndSettle();
      expect(find.text('文件(F)'), findsNothing,
          reason: 'zen mode hides the title bar');
      expect(zenStrip('editor'), findsOneWidget,
          reason: 'the editor remains visible');

      final gridRect = tester.getRect(find.byType(WorkbenchGrid));
      expect(gridRect.left, greaterThan(0),
          reason: 'the centered grid leaves side margins');
      expect(gridRect.width, lessThan(2400),
          reason: 'the centered grid is width-limited');

      // Esc 退出禅模式并恢复标题行。
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('文件(F)'), findsOneWidget,
          reason: 'Esc exits zen mode and restores the title bar');
      expect(zenStrip('editor'), findsOneWidget);
    },
  );

  testWidgets(
    'zen mode persists across a session restore',
    (tester) async {
      final requests = <bool>[];
      installNativeFullscreen(tester, requests);
      await prepareWorkspace(tester, zenMode: true, windowControls: true);
      await tester.pumpAndSettle();
      expect(requests, [true]);
      expect(find.text('文件(F)'), findsNothing,
          reason: 'a zen-mode session restores without the title bar');
      final gridRect = tester.getRect(find.byType(WorkbenchGrid));
      expect(gridRect.width, lessThan(2400),
          reason: 'the centered grid restores');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('文件(F)'), findsOneWidget, reason: 'Esc exits zen mode');
      expect(requests, [true, false]);
    },
  );

  testWidgets('restored zen waits until the native window is shown',
      (tester) async {
    final requests = <bool>[];
    var visible = false;
    installNativeFullscreen(tester, requests, isVisible: () => visible);
    await prepareWorkspace(tester, zenMode: true, windowControls: true);
    await tester.pumpAndSettle();
    expect(find.text('文件(F)'), findsNothing);
    expect(requests, isEmpty);

    visible = true;
    final listener = tester.state(find.byType(WorkbenchPage)) as WindowListener;
    listener.onWindowEvent('show');
    await tester.pumpAndSettle();
    expect(requests, [true]);
    expect(find.text('文件(F)'), findsNothing);
  });

  testWidgets(
    'the zen toggle round-trips through the registered command',
    (tester) async {
      await prepareWorkspace(tester);
      await execute(tester, 'workbench.action.toggleZenMode');
      expect(find.text('文件(F)'), findsNothing);
      await execute(tester, 'workbench.action.toggleZenMode');
      expect(find.text('文件(F)'), findsOneWidget);
    },
  );
}
