import 'dart:async';
import 'dart:io';

import 'package:alula_app/editor/editor_clipboard.dart';
import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/editor/snippet_template.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irondash_message_channel/irondash_message_channel.dart';
// Test fixtures need the package's native-channel override, which is test-only.
// ignore: implementation_imports
import 'package:super_native_extensions/src/native/context.dart'
    show setContextOverride;

Future<(Directory, File)> _openSnippetFixture(
  WidgetTester tester,
  TargetPlatform platform, {
  String initialText = 'x',
}) async {
  debugDefaultTargetPlatformOverride = platform;
  final temp = Directory.systemTemp.createTempSync('alula-snippet');
  addTearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });
  final workspace = Directory('${temp.path}/workspace')..createSync();
  final file = File('${workspace.path}/sample.rs')
    ..writeAsStringSync(initialText);
  final base = temp.path.replaceAll(r'\', '/');
  await tester.pumpWidget(AlulaApp(
    autoFolder: workspace.path,
    layoutStore: LayoutStore(path: '$base/layout.json'),
    sessionStore: SessionStore(path: '$base/session.json'),
    keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
  ));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.tap(find.text('sample.rs').first);
  await tester.pump(const Duration(milliseconds: 300));
  final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
  await tester.showKeyboard(editor);
  await tester.pump();
  return (temp, file);
}

Future<void> _insertSnippetFromPalette(
  WidgetTester tester, {
  required String template,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.enterText(find.byType(TextField).last, '插入片段');
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.text('编辑器: 插入片段…').last);
  await tester.pump(const Duration(milliseconds: 100));
  final input = find.byKey(const ValueKey('snippet-template-input'));
  await tester.enterText(input, template);
  await tester.tap(find.byKey(const ValueKey('snippet-template-confirm')));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
}

Future<void> _replaceCurrentSelection(WidgetTester tester, String replacement,
    {bool pump = true}) async {
  final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
  final value = tester.widget<TextField>(editor).controller!.value;
  final selection = value.selection;
  final text = value.text.replaceRange(
    selection.start,
    selection.end,
    replacement,
  );
  tester.testTextInput.updateEditingValue(TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(
      offset: selection.start + replacement.length,
    ),
  ));
  if (pump) await tester.pump();
}

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
  bool meta = false,
  bool shift = false,
}) async {
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(() {
    final mockContext = MockMessageChannelContext();
    for (final channel in ['DragManager', 'DropManager']) {
      mockContext.registerMockChannelHandler(
        channel,
        (_) async => ['ok', null],
      );
    }
    setContextOverride(mockContext);
    TestWidgetsFlutterBinding.ensureInitialized()
        .defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.irondash.engine_context'),
          (call) async => call.method == 'getEngineHandle' ? 1 : null,
        );
  });

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    final isMac = platform == TargetPlatform.macOS;
    testWidgets('$platform snippet mirrors edits, navigates, saves and undoes',
        (tester) async {
      try {
        tester.view.physicalSize = const Size(1100, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final (_, file) = await _openSnippetFixture(tester, platform);
        final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
        var controller = tester.widget<TextField>(editor).controller!;
        controller.selection = const TextSelection.collapsed(offset: 1);
        await tester.pump();

        await _insertSnippetFromPalette(
          tester,
          template: r'${1:name} = $1; ${2:value}$0',
        );
        controller = tester.widget<TextField>(editor).controller!;
        expect(controller.text, 'xname = name; value');
        expect(controller.selection,
            const TextSelection(baseOffset: 1, extentOffset: 5));
        expect(
          tester
              .widget<RustTextInputField>(find.byType(RustTextInputField))
              .additionalSelections,
          hasLength(1),
        );

        await _press(
          tester,
          LogicalKeyboardKey.keyZ,
          control: !isMac,
          meta: isMac,
        );
        controller = tester.widget<TextField>(editor).controller!;
        expect(controller.text, 'x');

        controller.selection = const TextSelection.collapsed(offset: 1);
        await tester.pump();
        await _insertSnippetFromPalette(
          tester,
          template: r'${1:name} = $1; ${2:value}$0',
        );
        await _replaceCurrentSelection(tester, 'foo', pump: false);
        controller = tester.widget<TextField>(editor).controller!;
        expect(controller.text, 'xfoo = foo; value');

        await _press(tester, LogicalKeyboardKey.tab);
        controller = tester.widget<TextField>(editor).controller!;
        expect(controller.selection,
            const TextSelection(baseOffset: 12, extentOffset: 17));
        await _press(tester, LogicalKeyboardKey.tab, shift: true);
        controller = tester.widget<TextField>(editor).controller!;
        expect(controller.selection,
            const TextSelection(baseOffset: 1, extentOffset: 4));
        await _press(tester, LogicalKeyboardKey.tab);
        controller = tester.widget<TextField>(editor).controller!;
        expect(controller.selection,
            const TextSelection(baseOffset: 12, extentOffset: 17));
        await _replaceCurrentSelection(tester, 'bar');
        controller = tester.widget<TextField>(editor).controller!;
        expect(controller.text, 'xfoo = foo; bar');

        await _press(tester, LogicalKeyboardKey.tab);
        controller = tester.widget<TextField>(editor).controller!;
        expect(controller.selection, const TextSelection.collapsed(offset: 15));
        await _press(tester, LogicalKeyboardKey.keyS, control: true);
        await tester.pump(const Duration(milliseconds: 100));
        expect(file.readAsStringSync(), 'xfoo = foo; bar');

        await _insertSnippetFromPalette(
          tester,
          template: r'${1:again} $1',
        );
        await _press(tester, LogicalKeyboardKey.escape);
        controller = tester.widget<TextField>(editor).controller!;
        expect(controller.selection.isCollapsed, isTrue);
        expect(
          tester
              .widget<RustTextInputField>(find.byType(RustTextInputField))
              .additionalSelections,
          isEmpty,
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('$platform nested snippet tabstop edits mirror and save',
        (tester) async {
      try {
        tester.view.physicalSize = const Size(1100, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final (_, file) = await _openSnippetFixture(
          tester,
          platform,
          initialText: '🙂\r\nx',
        );
        final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
        final controller = tester.widget<TextField>(editor).controller!;
        controller.selection = const TextSelection.collapsed(offset: 3);
        await tester.pump();

        await _insertSnippetFromPalette(
          tester,
          template: r'${1:outer ${2:inner}}-$1-$2$0',
        );
        expect(controller.text, '🙂\nouter inner-outer inner-innerx');
        expect(controller.selection,
            const TextSelection(baseOffset: 3, extentOffset: 14));

        await _press(tester, LogicalKeyboardKey.tab);
        expect(controller.selection,
            const TextSelection(baseOffset: 9, extentOffset: 14));
        final input = tester.widget<RustTextInputField>(
          find.byType(RustTextInputField),
        );
        expect(input.additionalSelections, hasLength(2));
        expect(input.additionalSelections[0],
            const TextSelection(baseOffset: 21, extentOffset: 26));
        expect(input.additionalSelections[1],
            const TextSelection(baseOffset: 27, extentOffset: 32));

        await _replaceCurrentSelection(tester, '🙂z');
        expect(controller.text, '🙂\nouter 🙂z-outer 🙂z-🙂zx');
        await _press(tester, LogicalKeyboardKey.tab, shift: true);
        expect(controller.selection,
            const TextSelection(baseOffset: 3, extentOffset: 12));
        final updatedInput = tester.widget<RustTextInputField>(
          find.byType(RustTextInputField),
        );
        expect(updatedInput.additionalSelections, hasLength(1));
        expect(updatedInput.additionalSelections.single,
            const TextSelection(baseOffset: 13, extentOffset: 22));
        await _press(tester, LogicalKeyboardKey.tab);
        await _press(tester, LogicalKeyboardKey.tab);
        expect(controller.selection, const TextSelection.collapsed(offset: 26));

        await _press(tester, LogicalKeyboardKey.keyS, control: true);
        await tester.pump(const Duration(milliseconds: 100));
        expect(file.readAsStringSync(), '🙂\r\nouter 🙂z-outer 🙂z-🙂zx');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets(
      'choice suggestions preview and accept with linked UTF-16 ranges, save and undo',
      (tester) async {
    try {
      tester.view.physicalSize = const Size(1100, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (_, file) = await _openSnippetFixture(
        tester,
        TargetPlatform.linux,
        initialText: '🙂\r\nx',
      );
      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      final controller = tester.widget<TextField>(editor).controller!;
      controller.selection = const TextSelection.collapsed(offset: 3);
      await tester.pump();

      await _insertSnippetFromPalette(
        tester,
        template: r'${1|blue,green|}-$1$0',
      );

      expect(controller.text, '🙂\nblue-bluex');
      expect(controller.selection,
          const TextSelection(baseOffset: 3, extentOffset: 7));
      expect(find.byKey(const ValueKey('snippet-choice-suggestion-list')),
          findsOneWidget);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(
        find.byKey(const ValueKey('snippet-choice-option-highlighted-1')),
        findsOneWidget,
      );
      expect(controller.text, '🙂\nblue-bluex');
      await _press(tester, LogicalKeyboardKey.enter);
      expect(controller.text, '🙂\ngreen-greenx');
      expect(find.byKey(const ValueKey('snippet-choice-suggestion-list')),
          findsNothing);

      await _press(tester, LogicalKeyboardKey.keyS, control: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(file.readAsStringSync(), '🙂\r\ngreen-greenx');
      await _press(tester, LogicalKeyboardKey.keyZ, control: true);
      expect(controller.text, '🙂\nblue-bluex');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('choice click and Tab accept mirror every linked occurrence',
      (tester) async {
    try {
      tester.view.physicalSize = const Size(1100, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (_, file) = await _openSnippetFixture(
        tester,
        TargetPlatform.windows,
      );
      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      final controller = tester.widget<TextField>(editor).controller!;
      controller.selection = const TextSelection.collapsed(offset: 1);
      await tester.pump();

      await _insertSnippetFromPalette(
        tester,
        template: r'${1|blue,green|}-$1-${2:end}-$0',
      );
      expect(controller.text, 'xblue-blue-end-');
      await tester.tap(
        find.byKey(const ValueKey('snippet-choice-option-1')),
      );
      await tester.pump();
      expect(controller.text, 'xgreen-green-end-');
      expect(controller.selection,
          const TextSelection(baseOffset: 13, extentOffset: 16));
      expect(find.byKey(const ValueKey('snippet-choice-suggestion-list')),
          findsNothing);

      await _press(tester, LogicalKeyboardKey.tab, shift: true);
      expect(controller.selection,
          const TextSelection(baseOffset: 1, extentOffset: 6));
      expect(find.byKey(const ValueKey('snippet-choice-suggestion-list')),
          findsOneWidget);
      await _press(tester, LogicalKeyboardKey.tab);
      expect(controller.text, 'xblue-blue-end-');
      expect(controller.selection,
          const TextSelection(baseOffset: 11, extentOffset: 14));

      await _press(tester, LogicalKeyboardKey.keyS, control: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(file.readAsStringSync(), 'xblue-blue-end-');
      await _press(tester, LogicalKeyboardKey.keyZ, control: true);
      expect(controller.text, 'xgreen-green-end-');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Escape dismisses choices before leaving the snippet session',
      (tester) async {
    try {
      tester.view.physicalSize = const Size(1100, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _openSnippetFixture(tester, TargetPlatform.linux);
      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      final controller = tester.widget<TextField>(editor).controller!;
      controller.selection = const TextSelection.collapsed(offset: 1);
      await tester.pump();

      await _insertSnippetFromPalette(
        tester,
        template: r'${1:pre}-$1-${2|blue,green|}-$0',
      );
      expect(find.byKey(const ValueKey('snippet-choice-suggestion-list')),
          findsNothing);
      await _press(tester, LogicalKeyboardKey.tab);
      expect(find.byKey(const ValueKey('snippet-choice-suggestion-list')),
          findsOneWidget);
      await _press(tester, LogicalKeyboardKey.tab, shift: true);
      expect(find.byKey(const ValueKey('snippet-choice-suggestion-list')),
          findsNothing);
      expect(controller.selection,
          const TextSelection(baseOffset: 1, extentOffset: 4));
      await _press(tester, LogicalKeyboardKey.tab);
      expect(find.byKey(const ValueKey('snippet-choice-suggestion-list')),
          findsOneWidget);
      await _press(tester, LogicalKeyboardKey.escape);
      expect(find.byKey(const ValueKey('snippet-choice-suggestion-list')),
          findsNothing);
      expect(controller.selection,
          const TextSelection(baseOffset: 9, extentOffset: 13));
      await _press(tester, LogicalKeyboardKey.escape);
      expect(find.byKey(const ValueKey('snippet-choice-suggestion-list')),
          findsNothing);
      expect(controller.selection, const TextSelection.collapsed(offset: 13));
      await _replaceCurrentSelection(tester, '!');
      expect(controller.text, 'xpre-pre-blue!-');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('selected-text variable inserts the original UTF-16 selection',
      (tester) async {
    try {
      tester.view.physicalSize = const Size(1100, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (_, file) = await _openSnippetFixture(
        tester,
        TargetPlatform.windows,
        initialText: '🙂x',
      );
      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      final controller = tester.widget<TextField>(editor).controller!;
      controller.selection =
          const TextSelection(baseOffset: 0, extentOffset: 2);
      await tester.pump();

      await _insertSnippetFromPalette(
        tester,
        template: r'<$TM_SELECTED_TEXT>$0',
      );

      expect(controller.text, '<🙂>x');
      expect(controller.selection, const TextSelection.collapsed(offset: 4));
      await _press(tester, LogicalKeyboardKey.keyS, control: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(file.readAsStringSync(), '<🙂>x');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('filename variables use the active document basename',
      (tester) async {
    try {
      tester.view.physicalSize = const Size(1100, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (_, file) = await _openSnippetFixture(
        tester,
        TargetPlatform.windows,
      );
      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      final controller = tester.widget<TextField>(editor).controller!;
      controller.selection = const TextSelection.collapsed(offset: 1);
      await tester.pump();

      await _insertSnippetFromPalette(
        tester,
        template: r'<$TM_FILENAME|${TM_FILENAME_BASE:fallback}>$0',
      );

      expect(controller.text, 'x<sample.rs|sample>');
      await _press(tester, LogicalKeyboardKey.keyS, control: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(file.readAsStringSync(), 'x<sample.rs|sample>');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('path variables use the active document path and save',
      (tester) async {
    try {
      tester.view.physicalSize = const Size(1100, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (_, file) = await _openSnippetFixture(
        tester,
        TargetPlatform.linux,
      );
      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      final controller = tester.widget<TextField>(editor).controller!;
      controller.selection = const TextSelection.collapsed(offset: 1);
      await tester.pump();

      final homeVariable = Platform.isWindows ? 'USERPROFILE' : 'HOME';
      final variables = snippetDocumentPathVariables(
        file.path,
        windows: Platform.isWindows,
        userHome: Platform.environment[homeVariable],
      );
      await _insertSnippetFromPalette(
        tester,
        template: r'<$TM_DIRECTORY|$TM_DIRECTORY_BASE|$TM_FILEPATH>$0',
      );

      final inserted = '<${variables['TM_DIRECTORY']}|'
          '${variables['TM_DIRECTORY_BASE']}|${variables['TM_FILEPATH']}>';
      expect(controller.text, 'x$inserted');
      await _press(tester, LogicalKeyboardKey.keyS, control: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(file.readAsStringSync(), 'x$inserted');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('workspace variables use the opened folder and save',
      (tester) async {
    try {
      tester.view.physicalSize = const Size(1100, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (_, file) = await _openSnippetFixture(
        tester,
        TargetPlatform.linux,
      );
      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      final controller = tester.widget<TextField>(editor).controller!;
      controller.selection = const TextSelection.collapsed(offset: 1);
      await tester.pump();

      final variables = snippetWorkspaceVariables(
        file.parent.path,
        windows: Platform.isWindows,
      );
      await _insertSnippetFromPalette(
        tester,
        template: r'<$WORKSPACE_NAME|$WORKSPACE_FOLDER>$0',
      );

      final inserted = '<${variables['WORKSPACE_NAME']}|'
          '${variables['WORKSPACE_FOLDER']}>';
      expect(controller.text, 'x$inserted');
      await _press(tester, LogicalKeyboardKey.keyS, control: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(file.readAsStringSync(), 'x$inserted');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('clipboard variable inserts the clipboard text and saves',
      (tester) async {
    final previousClipboardFallback =
        EditorClipboard.forceFlutterClipboardFallbackForTesting;
    EditorClipboard.forceFlutterClipboardFallbackForTesting = true;
    var clipboardReads = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          clipboardReads++;
          return const {'text': 'copied 🙂'};
        }
        return null;
      },
    );
    addTearDown(() {
      EditorClipboard.forceFlutterClipboardFallbackForTesting =
          previousClipboardFallback;
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    try {
      tester.view.physicalSize = const Size(1100, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (_, file) = await _openSnippetFixture(
        tester,
        TargetPlatform.windows,
      );
      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      final controller = tester.widget<TextField>(editor).controller!;
      controller.selection = const TextSelection.collapsed(offset: 1);
      await tester.pump();

      await _insertSnippetFromPalette(
        tester,
        template: r'<${CLIPBOARD:fallback}>$0',
      );

      expect(controller.text, 'x<copied 🙂>');
      expect(clipboardReads, 1);
      await _press(tester, LogicalKeyboardKey.keyS, control: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(file.readAsStringSync(), 'x<copied 🙂>');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('clipboard read does not apply to an edited document snapshot',
      (tester) async {
    final previousClipboardFallback =
        EditorClipboard.forceFlutterClipboardFallbackForTesting;
    EditorClipboard.forceFlutterClipboardFallbackForTesting = true;
    final clipboardResult = Completer<Map<String, String>>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) => call.method == 'Clipboard.getData'
          ? clipboardResult.future
          : Future<Object?>.value(null),
    );
    addTearDown(() {
      EditorClipboard.forceFlutterClipboardFallbackForTesting =
          previousClipboardFallback;
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    try {
      tester.view.physicalSize = const Size(1100, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (_, file) = await _openSnippetFixture(
        tester,
        TargetPlatform.linux,
      );
      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      final controller = tester.widget<TextField>(editor).controller!;
      controller.selection = const TextSelection.collapsed(offset: 1);
      await tester.pump();

      await _insertSnippetFromPalette(
        tester,
        template: r'<$CLIPBOARD>$0',
      );
      await tester.showKeyboard(editor);
      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: 'changed',
        selection: TextSelection.collapsed(offset: 7),
      ));
      await tester.pump();

      clipboardResult.complete(const {'text': 'stale clipboard'});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.text, 'changed');
      expect(file.readAsStringSync(), 'x');
    } finally {
      if (!clipboardResult.isCompleted) {
        clipboardResult.complete(const {'text': 'unused'});
      }
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'relative filepath variable resolves against the open folder and saves',
      (tester) async {
    try {
      tester.view.physicalSize = const Size(1100, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (_, file) = await _openSnippetFixture(
        tester,
        TargetPlatform.linux,
      );
      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      final controller = tester.widget<TextField>(editor).controller!;
      controller.selection = const TextSelection.collapsed(offset: 1);
      await tester.pump();

      await _insertSnippetFromPalette(
        tester,
        template: r'<$RELATIVE_FILEPATH>$0',
      );

      expect(controller.text, 'x<sample.rs>');
      await _press(tester, LogicalKeyboardKey.keyS, control: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(file.readAsStringSync(), 'x<sample.rs>');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('current-line variable reads the full Rust line without CRLF',
      (tester) async {
    try {
      tester.view.physicalSize = const Size(1100, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (_, file) = await _openSnippetFixture(
        tester,
        TargetPlatform.windows,
        initialText: 'before\r\nse🙂cond\r\nlast',
      );
      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      final controller = tester.widget<TextField>(editor).controller!;
      controller.selection = const TextSelection.collapsed(offset: 11);
      await tester.pump();

      await _insertSnippetFromPalette(
        tester,
        template: r'<$TM_CURRENT_LINE>$0',
      );

      const expectedEditor = 'before\nse🙂<se🙂cond>cond\nlast';
      const expectedOnDisk = 'before\r\nse🙂<se🙂cond>cond\r\nlast';
      expect(controller.text, expectedEditor);
      await _press(tester, LogicalKeyboardKey.keyS, control: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(file.readAsStringSync(), expectedOnDisk);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('current-line variable transform resolves from Rust and saves',
      (tester) async {
    try {
      tester.view.physicalSize = const Size(1100, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (_, file) = await _openSnippetFixture(
        tester,
        TargetPlatform.windows,
        initialText: 'before\r\nse🙂cond\r\nlast',
      );
      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      final controller = tester.widget<TextField>(editor).controller!;
      controller.selection = const TextSelection.collapsed(offset: 11);
      await tester.pump();

      await _insertSnippetFromPalette(
        tester,
        template: r'<${TM_CURRENT_LINE/(.*)/${1:/upcase}/}>$0',
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();

      const expectedEditor = 'before\nse🙂<SE🙂COND>cond\nlast';
      const expectedOnDisk = 'before\r\nse🙂<SE🙂COND>cond\r\nlast';
      expect(controller.text, expectedEditor);
      await _press(tester, LogicalKeyboardKey.keyS, control: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(file.readAsStringSync(), expectedOnDisk);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('snippet transform does not overwrite edits made while resolving',
      (tester) async {
    try {
      tester.view.physicalSize = const Size(1100, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (_, file) = await _openSnippetFixture(
        tester,
        TargetPlatform.windows,
      );
      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      final controller = tester.widget<TextField>(editor).controller!;
      controller.selection = const TextSelection.collapsed(offset: 1);
      await tester.pump();

      await _insertSnippetFromPalette(
        tester,
        template: r'<${TM_FILENAME/(.*)/$1/}>$0',
      );
      expect(controller.text, 'x');

      await tester.showKeyboard(editor);
      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: 'changed',
        selection: TextSelection.collapsed(offset: 7),
      ));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();

      expect(controller.text, 'changed');
      await _press(tester, LogicalKeyboardKey.keyS, control: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(file.readAsStringSync(), 'changed');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'snippet transform does not touch a controller closed while resolving',
      (tester) async {
    try {
      tester.view.physicalSize = const Size(1100, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _openSnippetFixture(tester, TargetPlatform.windows);
      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      final controller = tester.widget<TextField>(editor).controller!;
      controller.selection = const TextSelection.collapsed(offset: 1);
      await tester.pump();

      await _insertSnippetFromPalette(
        tester,
        template: r'<${TM_FILENAME/(.*)/$1/}>$0',
      );
      expect(controller.text, 'x');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('current-word variable uses the Rust cursor and saves',
      (tester) async {
    try {
      tester.view.physicalSize = const Size(1100, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (_, file) = await _openSnippetFixture(
        tester,
        TargetPlatform.windows,
        initialText: 'before\r\n🙂prefix targetSuffix\r\nlast',
      );
      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      final controller = tester.widget<TextField>(editor).controller!;
      controller.selection = const TextSelection.collapsed(offset: 20);
      await tester.pump();

      await _insertSnippetFromPalette(
        tester,
        template: r'<$TM_CURRENT_WORD>$0',
      );

      const expectedEditor =
          'before\n🙂prefix targ<targetSuffix>etSuffix\nlast';
      const expectedOnDisk =
          'before\r\n🙂prefix targ<targetSuffix>etSuffix\r\nlast';
      expect(controller.text, expectedEditor);
      await _press(tester, LogicalKeyboardKey.keyS, control: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(file.readAsStringSync(), expectedOnDisk);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('current-word variable bounds long-line reads', (tester) async {
    try {
      tester.view.physicalSize = const Size(1100, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final longWord = "${'a' * 100}Q${'a' * 1100}";
      final expected = "${'a' * 100}Q${'a' * 2100}";
      final (_, file) = await _openSnippetFixture(
        tester,
        TargetPlatform.windows,
        initialText: longWord,
      );
      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      final controller = tester.widget<TextField>(editor).controller!;
      controller.selection = const TextSelection.collapsed(offset: 600);
      await tester.pump();

      await _insertSnippetFromPalette(tester, template: r'$TM_CURRENT_WORD');

      expect(controller.text, expected);
      await _press(tester, LogicalKeyboardKey.keyS, control: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(file.readAsStringSync(), expected);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'current-line variable rejects a line larger than the input window',
      (tester) async {
    try {
      tester.view.physicalSize = const Size(1100, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final oversizedLine = 'a' * 16385;
      final (_, file) = await _openSnippetFixture(
        tester,
        TargetPlatform.windows,
        initialText: oversizedLine,
      );
      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      final controller = tester.widget<TextField>(editor).controller!;
      final visibleText = controller.text;
      controller.selection = const TextSelection.collapsed(offset: 8192);
      await tester.pump();

      await _insertSnippetFromPalette(
        tester,
        template: r'$TM_CURRENT_LINE',
      );

      expect(controller.text, visibleText);
      expect(file.readAsStringSync(), oversizedLine);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('ordinary snippet does not read or reject an oversized line',
      (tester) async {
    try {
      tester.view.physicalSize = const Size(1100, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final oversizedLine = 'a' * 16385;
      final (_, file) = await _openSnippetFixture(
        tester,
        TargetPlatform.windows,
        initialText: oversizedLine,
      );
      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      final controller = tester.widget<TextField>(editor).controller!;
      controller.selection = const TextSelection.collapsed(offset: 8192);
      await tester.pump();

      await _insertSnippetFromPalette(tester, template: r'<$0>');

      await _press(tester, LogicalKeyboardKey.keyS, control: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(file.readAsStringSync(), '${'a' * 8192}<>${'a' * (16385 - 8192)}');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('line variables use the Rust document cursor line and save',
      (tester) async {
    try {
      tester.view.physicalSize = const Size(1100, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (_, file) = await _openSnippetFixture(
        tester,
        TargetPlatform.windows,
        initialText: '🙂x\nsecond',
      );
      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      final controller = tester.widget<TextField>(editor).controller!;
      controller.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();

      await _insertSnippetFromPalette(
        tester,
        template: r'<$TM_LINE_INDEX|$TM_LINE_NUMBER>$0',
      );

      expect(controller.text, '🙂x\ns<1|2>econd');
      await _press(tester, LogicalKeyboardKey.keyS, control: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(file.readAsStringSync(), '🙂x\ns<1|2>econd');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('placeholder transforms run on Tab, save, and undo',
      (tester) async {
    try {
      tester.view.physicalSize = const Size(1100, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (_, file) = await _openSnippetFixture(
        tester,
        TargetPlatform.windows,
      );
      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      final controller = tester.widget<TextField>(editor).controller!;
      controller.selection = const TextSelection.collapsed(offset: 1);
      await tester.pump();

      await _insertSnippetFromPalette(
        tester,
        template:
            r'${1:name}-${1/(.*)/${1:/upcase}/}-${1/(.*)/${1:/downcase}/}$0',
      );
      await _replaceCurrentSelection(tester, 'CaRgO');
      expect(controller.text, 'xCaRgO-CaRgO-CaRgO');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();

      expect(controller.text, 'xCaRgO-CARGO-cargo');
      await _press(tester, LogicalKeyboardKey.keyS, control: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(file.readAsStringSync(), 'xCaRgO-CARGO-cargo');

      await _press(tester, LogicalKeyboardKey.keyZ, control: true);
      expect(controller.text, 'xCaRgO-CaRgO-CaRgO');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'multi-cursor snippet resolves each selection and keeps per-line transform indentation',
      (tester) async {
    try {
      tester.view.physicalSize = const Size(1100, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (_, file) = await _openSnippetFixture(
        tester,
        TargetPlatform.windows,
        initialText: '  🙂 name\r\n    🦊 name',
      );
      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      var controller = tester.widget<TextField>(editor).controller!;
      controller.selection =
          const TextSelection(baseOffset: 5, extentOffset: 9);
      await tester.pump();

      await _press(tester, LogicalKeyboardKey.keyD, control: true);
      final field =
          tester.widget<RustTextInputField>(find.byType(RustTextInputField));
      expect(field.additionalSelections, const [
        TextSelection(baseOffset: 17, extentOffset: 21),
      ]);

      await _insertSnippetFromPalette(
        tester,
        template:
            '\$TM_LINE_NUMBER:\$TM_SELECTED_TEXT:\$TM_CURRENT_LINE:\$TM_CURRENT_WORD-\${1:x}-\${2:y}-\${2/x/\${1:-fallback\nnext}/}\$0',
      );
      controller = tester.widget<TextField>(editor).controller!;
      expect(
        controller.text,
        '  🙂 1:name:  🙂 name:name-x-y-y\n'
        '    🦊 2:name:    🦊 name:name-x-y-y',
      );

      await _press(tester, LogicalKeyboardKey.tab);
      await _replaceCurrentSelection(tester, 'dog');
      controller = tester.widget<TextField>(editor).controller!;
      expect(
        controller.text,
        '  🙂 1:name:  🙂 name:name-x-dog-dog\n'
        '    🦊 2:name:    🦊 name:name-x-dog-dog',
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();

      const transformed = '  🙂 1:name:  🙂 name:name-x-dog-fallback\n  next\n'
          '    🦊 2:name:    🦊 name:name-x-dog-fallback\n    next';
      controller = tester.widget<TextField>(editor).controller!;
      expect(controller.text, transformed);
      await _press(tester, LogicalKeyboardKey.keyS, control: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(file.readAsStringSync(), transformed.replaceAll('\n', '\r\n'));

      await _press(tester, LogicalKeyboardKey.keyZ, control: true);
      expect(
        tester.widget<TextField>(editor).controller!.text,
        '  🙂 1:name:  🙂 name:name-x-dog-dog\n'
        '    🦊 2:name:    🦊 name:name-x-dog-dog',
      );
      await _press(tester, LogicalKeyboardKey.keyY, control: true);
      expect(tester.widget<TextField>(editor).controller!.text, transformed);
      await _press(tester, LogicalKeyboardKey.keyZ, control: true);
      await _press(tester, LogicalKeyboardKey.keyZ, control: true);
      await _press(tester, LogicalKeyboardKey.keyZ, control: true);
      expect(tester.widget<TextField>(editor).controller!.text,
          '  🙂 name\n    🦊 name');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('multi-cursor snippet rejects selection counts above its bound',
      (tester) async {
    try {
      tester.view.physicalSize = const Size(1100, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final initialText = List<String>.filled(65, 'name').join(' ');
      final (_, file) = await _openSnippetFixture(
        tester,
        TargetPlatform.windows,
        initialText: initialText,
      );
      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      final controller = tester.widget<TextField>(editor).controller!;
      controller.selection =
          const TextSelection(baseOffset: 0, extentOffset: 4);
      await tester.pump();
      for (var index = 1; index < 65; index++) {
        await _press(tester, LogicalKeyboardKey.keyD, control: true);
      }
      expect(
        tester
            .widget<RustTextInputField>(find.byType(RustTextInputField))
            .additionalSelections,
        hasLength(64),
      );

      await _insertSnippetFromPalette(tester, template: r'${1:x}$0');

      expect(controller.text, initialText);
      expect(file.readAsStringSync(), initialText);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'placeholder transforms run on Shift+Tab with UTF-16, multiline, and CRLF save',
      (tester) async {
    try {
      tester.view.physicalSize = const Size(1100, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (_, file) = await _openSnippetFixture(
        tester,
        TargetPlatform.windows,
        initialText: '🙂\r\n  ',
      );
      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      final controller = tester.widget<TextField>(editor).controller!;
      controller.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();

      await _insertSnippetFromPalette(
        tester,
        template: '\${1:x}-\${2:y}-\${2/x/\${1:-fallback\nnext}/}\$0',
      );
      await _press(tester, LogicalKeyboardKey.tab);
      await _replaceCurrentSelection(tester, 'dog');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();

      expect(controller.text, '🙂\n  x-dog-fallback\n  next');
      expect(controller.selection,
          const TextSelection(baseOffset: 5, extentOffset: 6));
      await _press(tester, LogicalKeyboardKey.keyS, control: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(file.readAsStringSync(), '🙂\r\n  x-dog-fallback\r\n  next');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('placeholder transform drops its result after a concurrent edit',
      (tester) async {
    try {
      tester.view.physicalSize = const Size(1100, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (_, file) = await _openSnippetFixture(
        tester,
        TargetPlatform.windows,
      );
      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      final controller = tester.widget<TextField>(editor).controller!;
      controller.selection = const TextSelection.collapsed(offset: 1);
      await tester.pump();

      await _insertSnippetFromPalette(
        tester,
        template: r'${1:a}-${1/(a|aa)+$/FAIL/}$0',
      );
      final slowValue = "${'a' * 48}b";
      await _replaceCurrentSelection(tester, slowValue);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: 'xchanged-changed',
        selection: TextSelection.collapsed(offset: 16),
      ));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 900)),
      );
      await tester.pump();

      expect(controller.text, 'xchanged-changed');
      await _press(tester, LogicalKeyboardKey.keyS, control: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(file.readAsStringSync(), 'xchanged-changed');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
