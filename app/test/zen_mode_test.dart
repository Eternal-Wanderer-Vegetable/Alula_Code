import 'dart:convert';
import 'dart:io';

import 'package:alula_app/editor/editor_rendering.dart';
import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_controller.dart';
import 'package:alula_app/workbench/layout_grid.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/status_bar.dart';
import 'package:alula_app/workbench/title_bar.dart';
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
    Map<String, bool>? regions,
    Object? zenPreviousCollapsed,
  }) async {
    temp = Directory.systemTemp.createTempSync('alula-zen-mode');
    workspace = Directory('${temp.path}/workspace')..createSync();
    final base = temp.path.replaceAll(r'\', '/');
    layoutStore = LayoutStore(path: '$base/layout.json');
    if (regions != null) {
      final initial = WorkbenchLayout();
      for (final region in regions.entries) {
        initial.setRegionCollapsed(region.key, !region.value);
      }
      layoutStore.save(initial.root);
      initial.dispose();
    }
    sessionStore = SessionStore(path: '$base/session.json');
    File('${baseOf()}/session.json').writeAsStringSync(jsonEncode({
      'v': 1,
      'editorTabMode': 'multiple',
      'zenMode': zenMode,
      if (zenPreviousCollapsed != null)
        'zenPreviousCollapsed': zenPreviousCollapsed,
      if (regions != null) 'workspace': workspace.path,
      'groups': <Object?>[],
    }));
    File('${workspace.path}/main.rs')
        .writeAsStringSync('fn main() {\n    let value = 1;\n}\n');
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

  Future<void> pressEscape(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }

  Future<RustTextInputFieldState> openEditor(WidgetTester tester) async {
    await tester.tap(find.text('main.rs').first);
    await tester.pump(const Duration(milliseconds: 400));
    final state =
        tester.state<RustTextInputFieldState>(find.byType(RustTextInputField));
    state.requestFocus();
    await tester.pump();
    return state;
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
        expect(find.byType(AlulaStatusBar), findsNothing);
        expect(requests, alreadyFullscreen ? isEmpty : [true]);

        await execute(tester, 'workbench.action.toggleZenMode');
        expect(find.byType(AlulaStatusBar), findsOneWidget);
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
    expect(find.byType(AlulaStatusBar), findsNothing);

    nativeChanged(false);
    final listener = tester.state(find.byType(WorkbenchPage)) as WindowListener;
    listener.onWindowLeaveFullScreen();
    await tester.pumpAndSettle();
    expect(find.byType(AlulaStatusBar), findsOneWidget);
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
    expect(find.byType(AlulaStatusBar), findsNothing);

    nativeChanged(false);
    tester.view.physicalSize = const Size(1150, 750);
    tester.view.physicalSize = const Size(1149, 749);
    await tester.pumpAndSettle();
    expect(find.byType(AlulaStatusBar), findsOneWidget);
    expect(requests, [true]);
  });

  testWidgets(
    'toggling zen mode hides the status bar and centers the editor',
    (tester) async {
      await prepareWorkspace(tester);
      expect(find.byType(AlulaStatusBar), findsOneWidget);
      expect(zenStrip('editor'), findsOneWidget);

      await execute(tester, 'workbench.action.toggleZenMode');
      await tester.pumpAndSettle();
      expect(find.byType(AlulaStatusBar), findsNothing,
          reason: 'zen mode hides the status bar');
      expect(zenStrip('editor'), findsOneWidget,
          reason: 'the editor remains visible');

      final gridRect = tester.getRect(find.byType(WorkbenchGrid));
      expect(gridRect.left, greaterThan(0),
          reason: 'the centered grid leaves side margins');
      expect(gridRect.width, lessThan(2400),
          reason: 'the centered grid is width-limited');

      await pressEscape(tester);
      expect(find.byType(AlulaStatusBar), findsNothing);
      await pressEscape(tester);
      expect(find.byType(AlulaStatusBar), findsOneWidget,
          reason:
              'the second Escape exits zen mode and restores the status bar');
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
      expect(find.byType(AlulaStatusBar), findsNothing,
          reason: 'a zen-mode session restores without the status bar');
      final gridRect = tester.getRect(find.byType(WorkbenchGrid));
      expect(gridRect.width, lessThan(2400),
          reason: 'the centered grid restores');

      await pressEscape(tester);
      expect(requests, [true]);
      await pressEscape(tester);
      expect(find.byType(AlulaStatusBar), findsOneWidget);
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
    expect(find.byType(AlulaStatusBar), findsNothing);
    expect(requests, isEmpty);

    visible = true;
    final listener = tester.state(find.byType(WorkbenchPage)) as WindowListener;
    listener.onWindowEvent('show');
    await tester.pumpAndSettle();
    expect(requests, [true]);
    expect(find.byType(AlulaStatusBar), findsNothing);
  });

  testWidgets('zen chord timeout and invalid second key preserve editor state',
      (tester) async {
    await prepareWorkspace(tester);
    final editor = await openEditor(tester);
    const caret = TextSelection.collapsed(offset: 3);
    editor.setSelection(caret);
    await execute(tester, 'workbench.action.toggleZenMode');

    await pressEscape(tester);
    expect(find.byType(AlulaStatusBar), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(editor.editingValue.selection, caret);
    expect(find.byType(AlulaStatusBar), findsNothing);

    await pressEscape(tester);
    await tester.pump(const Duration(milliseconds: 5200));
    await pressEscape(tester);
    expect(find.byType(AlulaStatusBar), findsNothing);
    await pressEscape(tester);
    expect(find.byType(AlulaStatusBar), findsOneWidget);
    expect(editor.widget.focusNode!.hasFocus, isTrue);
    expect(editor.editingValue.selection, caret);
  });

  testWidgets('a repeated Escape can finish the held zen chord',
      (tester) async {
    await prepareWorkspace(tester);
    final editor = await openEditor(tester);
    await execute(tester, 'workbench.action.toggleZenMode');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    final stayedInZen = find.byType(AlulaStatusBar).evaluate().isEmpty;
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(stayedInZen, isTrue);
    expect(find.byType(AlulaStatusBar), findsOneWidget);
    expect(editor.widget.focusNode!.hasFocus, isTrue);
  });

  for (final overlay in ['quick open', 'find']) {
    testWidgets('Escape closes $overlay before starting the zen chord',
        (tester) async {
      await prepareWorkspace(tester);
      final editor = await openEditor(tester);
      await execute(tester, 'workbench.action.toggleZenMode');
      final overlayInput = overlay == 'find'
          ? find.byKey(const ValueKey('find-query-input'))
          : find.byWidgetPredicate((widget) =>
              widget is TextField &&
              widget.focusNode?.debugLabel == 'quick-input-field');
      await execute(tester,
          overlay == 'find' ? 'editor.find' : 'workbench.action.quickOpen');
      expect(overlayInput, findsOneWidget);
      await tester.tap(overlayInput);
      await tester.pump();
      final input = find.descendant(
          of: overlayInput, matching: find.byType(EditableText));
      expect(tester.widget<EditableText>(input).focusNode.hasFocus, isTrue);
      await pressEscape(tester);
      expect(overlayInput, findsNothing);
      expect(find.byType(AlulaStatusBar), findsNothing);
      expect(editor.widget.focusNode!.hasFocus, isTrue);

      await pressEscape(tester);
      expect(find.byType(AlulaStatusBar), findsNothing);
      await pressEscape(tester);
      expect(find.byType(AlulaStatusBar), findsOneWidget);
      expect(editor.widget.focusNode!.hasFocus, isTrue);
    });
  }

  testWidgets(
      'leaving zen or losing main window focus clears its pending chord',
      (tester) async {
    await prepareWorkspace(tester);
    await execute(tester, 'workbench.action.toggleZenMode');
    await pressEscape(tester);
    expect(find.byType(AlulaStatusBar), findsNothing);
    await execute(tester, 'workbench.action.toggleZenMode');
    await execute(tester, 'workbench.action.toggleZenMode');
    await pressEscape(tester);
    expect(find.byType(AlulaStatusBar), findsNothing);

    final listener = tester.state(find.byType(WorkbenchPage)) as WindowListener;
    listener.onWindowBlur();
    listener.onWindowFocus();
    await pressEscape(tester);
    expect(find.byType(AlulaStatusBar), findsNothing);
    await pressEscape(tester);
    expect(find.byType(AlulaStatusBar), findsOneWidget);
  });

  const layoutCases = {
    'panel visible': {
      'activity': false,
      'sidebar': true,
      'secondarySidebar': false,
      'panel': true,
    },
    'secondary sidebar visible': {
      'activity': true,
      'sidebar': false,
      'secondarySidebar': true,
      'panel': false,
    },
  };

  Finder region(String name) => find.byKey(ValueKey('wb-region-$name'));

  void expectRegions(Map<String, bool> visibility) {
    for (final state in visibility.entries) {
      expect(region(state.key), state.value ? findsOneWidget : findsNothing,
          reason: state.key);
    }
  }

  Map<String, Rect> visibleRegionBounds(
    WidgetTester tester,
    Map<String, bool> visibility,
  ) =>
      {
        for (final state in visibility.entries)
          if (state.value) state.key: tester.getRect(region(state.key)),
      };

  for (final layout in layoutCases.entries) {
    testWidgets('Zen restores independent shell regions with ${layout.key}',
        (tester) async {
      await prepareWorkspace(tester, regions: layout.value);
      expectRegions(layout.value);
      final before = visibleRegionBounds(tester, layout.value);

      await execute(tester, 'workbench.action.toggleZenMode');
      expectRegions({for (final key in layout.value.keys) key: false});
      await execute(tester, 'workbench.action.toggleZenMode');
      expectRegions(layout.value);
      expect(visibleRegionBounds(tester, layout.value), before);
    });

    testWidgets(
        'Zen recovers the original shell after restart with ${layout.key}',
        (tester) async {
      await prepareWorkspace(tester, regions: layout.value);
      final before = visibleRegionBounds(tester, layout.value);
      await execute(tester, 'workbench.action.toggleZenMode');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      final journal = sessionStore.tryLoad()!;
      expect(journal['zenMode'], isTrue);

      await mountPage(tester);
      expectRegions({for (final key in layout.value.keys) key: false});
      await execute(tester, 'workbench.action.toggleZenMode');
      expectRegions(layout.value);
      expect(visibleRegionBounds(tester, layout.value), before);
      expect(journal['zenPreviousCollapsed'],
          {for (final entry in layout.value.entries) entry.key: !entry.value});
      expect(
          sessionStore.tryLoad()!.containsKey('zenPreviousCollapsed'), false);
    });
  }

  testWidgets(
      'restoring Zen uses defaults for missing and invalid region values',
      (tester) async {
    const hidden = {
      'activity': false,
      'sidebar': false,
      'secondarySidebar': false,
      'panel': false,
    };
    await prepareWorkspace(
      tester,
      zenMode: true,
      regions: hidden,
      zenPreviousCollapsed: {
        'activity': true,
        'sidebar': 'bad',
        'ignored': false,
      },
    );
    expectRegions(hidden);
    await execute(tester, 'workbench.action.toggleZenMode');
    expectRegions({
      'activity': false,
      'sidebar': true,
      'secondarySidebar': false,
      'panel': false,
    });
  });

  testWidgets(
    'Zen hides line numbers in visible and newly opened editors',
    (tester) async {
      await prepareWorkspace(tester);
      final source = File('${workspace.path}/main.rs');
      final original = source.readAsBytesSync();
      final editor = await openEditor(tester);
      final document = editor.widget.inputWindow.document;
      final version = document.version;
      final content = document.resync().content;

      List<bool> numberModes() => tester
          .widgetList<RustTextInputField>(find.byType(RustTextInputField))
          .map((field) => field.showLineNumbers)
          .toList();

      List<EditorGutterPainter> gutters() => tester
          .widgetList<CustomPaint>(find.byWidgetPredicate((widget) =>
              widget is CustomPaint && widget.painter is EditorGutterPainter))
          .map((paint) => paint.painter! as EditorGutterPainter)
          .toList();

      await execute(tester, 'workbench.action.splitEditorRight');
      expect(numberModes(), [true, true]);
      expect(gutters().where((gutter) => gutter.showLineNumbers), hasLength(2));

      await execute(tester, 'workbench.action.toggleZenMode');
      expect(numberModes(), [false, false]);
      expect(gutters().where((gutter) => gutter.showLineNumbers), isEmpty);
      expect(gutters().any((gutter) => gutter.foldableLineIndices.contains(0)),
          isTrue,
          reason: 'a Rust fold control keeps its gutter in Zen');

      await execute(tester, 'workbench.action.files.newUntitledFile');
      expect(numberModes(), [false, false]);
      expect(gutters().where((gutter) => gutter.showLineNumbers), isEmpty);

      await execute(tester, 'workbench.action.toggleZenMode');
      expect(numberModes(), [true, true]);
      expect(gutters().where((gutter) => gutter.showLineNumbers), hasLength(2));
      expect(document.resync().content, content);
      expect(document.version, version);
      expect(document.isDirty, isFalse);
      expect(source.readAsBytesSync(), original);
    },
  );

  testWidgets('Command Palette placement stays at the window top in Zen',
      (tester) async {
    await prepareWorkspace(tester);
    final card = find.byKey(const ValueKey('quick-input'));

    Rect paintedCard() {
      final style = tester.widget<Container>(card).decoration;
      return tester.getRect(find.descendant(
        of: card,
        matching: find.byWidgetPredicate((widget) =>
            widget is DecoratedBox && identical(widget.decoration, style)),
      ));
    }

    Future<void> expectCommandPalette() async {
      await execute(tester, showCommandsCommandId);
      final bounds = paintedCard();
      expect(bounds.top, 6);
      expect(bounds.center.dx, 1200);
      final input =
          find.descendant(of: card, matching: find.byType(EditableText));
      expect(tester.widget<EditableText>(input).focusNode.hasFocus, isTrue);
      await pressEscape(tester);
      expect(card, findsNothing);
    }

    await expectCommandPalette();
    await execute(tester, 'workbench.action.toggleZenMode');
    await expectCommandPalette();
    await execute(tester, 'workbench.action.toggleZenMode');
    await expectCommandPalette();

    await execute(tester, quickOpenCommandId);
    expect(paintedCard().top, 56);
    await pressEscape(tester);
  });

  testWidgets('Zen keeps the default title bar and Command Center reachable',
      (tester) async {
    await prepareWorkspace(tester);
    await openEditor(tester);
    final title = find.byType(AlulaTitleBar);
    final commandCenter = find.byKey(const ValueKey('command-center-control'));
    final status = find.byType(AlulaStatusBar);
    final initialTitle = tester.getRect(title);
    final initialCenter = tester.getRect(commandCenter);
    expect(initialTitle.top, 0);
    expect(initialTitle.height, 35);
    expect(status, findsOneWidget);

    await execute(tester, 'workbench.action.toggleZenMode');
    expect(status, findsNothing);
    expect(tester.getRect(title), initialTitle);
    expect(tester.getRect(commandCenter), initialCenter);
    await tester.tap(commandCenter);
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('quick-input'));
    expect(card, findsOneWidget);
    final field =
        find.descendant(of: card, matching: find.byType(EditableText));
    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
    await pressEscape(tester);
    expect(card, findsNothing);
    expect(status, findsNothing);

    await execute(tester, 'workbench.action.toggleZenMode');
    expect(status, findsOneWidget);
    expect(tester.getRect(title), initialTitle);
    expect(tester.getRect(commandCenter), initialCenter);
  });

  testWidgets(
    'the zen toggle round-trips through the registered command',
    (tester) async {
      await prepareWorkspace(tester);
      await execute(tester, 'workbench.action.toggleZenMode');
      expect(find.byType(AlulaStatusBar), findsNothing);
      await execute(tester, 'workbench.action.toggleZenMode');
      expect(find.byType(AlulaStatusBar), findsOneWidget);
    },
  );
}
