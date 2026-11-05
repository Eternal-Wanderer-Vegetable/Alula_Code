import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _addCursorBelow(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.pump();
}

Future<void> _addCursorAbove(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.pump();
}

Future<void> _commandKey(
  WidgetTester tester,
  TargetPlatform platform,
  LogicalKeyboardKey key,
) async {
  final modifier = platform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 80));
}

Future<void> _saveWithCurrentBinding(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  const cases = <({
    TargetPlatform platform,
    String source,
    String clipboard,
    String normalizedSource,
    String afterCut,
    String savedAfterCut,
  })>[
    (
      platform: TargetPlatform.windows,
      source: 'first\nmiddle\nlast',
      clipboard: 'middle\nlast\r\n',
      normalizedSource: 'first\nmiddle\nlast',
      afterCut: 'first\n',
      savedAfterCut: 'first\n',
    ),
    (
      platform: TargetPlatform.linux,
      source: 'first\nmiddle\nlast',
      clipboard: 'middle\nlast\n',
      normalizedSource: 'first\nmiddle\nlast',
      afterCut: 'first\n',
      savedAfterCut: 'first\n',
    ),
    (
      platform: TargetPlatform.macOS,
      source: 'first\r\nmiddle\r\nlast',
      clipboard: 'middle\r\nlast\r\n',
      normalizedSource: 'first\nmiddle\nlast',
      afterCut: 'first\n',
      savedAfterCut: 'first\r\n',
    ),
  ];

  for (final testCase in cases) {
    testWidgets(
      'TargetPlatform.${testCase.platform.name} cuts mixed multi-cursor selections as one undoable edit',
      (tester) async {
        final originalPlatform = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = testCase.platform;
        final temp = Directory.systemTemp.createTempSync('alula-multi-cut');
        final workspace = Directory('${temp.path}/workspace')..createSync();
        final file = File('${workspace.path}/sample.txt')
          ..writeAsStringSync(testCase.source);
        final originalBytes = file.readAsBytesSync();
        final base = temp.path.replaceAll(r'\', '/');
        Map<dynamic, dynamic> clipboard = const {};
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboard = Map<dynamic, dynamic>.from(call.arguments as Map);
            }
            if (call.method == 'Clipboard.getData') return clipboard;
            return null;
          },
        );
        addTearDown(() async {
          debugDefaultTargetPlatformOverride = originalPlatform;
          tester.binding.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
          await tester.pumpWidget(const SizedBox.shrink());
          if (temp.existsSync()) temp.deleteSync(recursive: true);
        });

        await tester.pumpWidget(AlulaApp(
          autoFolder: workspace.path,
          layoutStore: LayoutStore(path: '$base/layout.json'),
          sessionStore: SessionStore(path: '$base/session.json'),
          keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
        ));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.tap(find.text('sample.txt').first);
        await tester.pump(const Duration(milliseconds: 300));

        final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
        await tester.showKeyboard(editor);
        await tester.pump();
        final controller = tester.widget<TextField>(editor).controller!;
        expect(controller.text, testCase.normalizedSource);
        controller.selection =
            const TextSelection(baseOffset: 6, extentOffset: 12);
        await tester.pump();
        await _addCursorBelow(tester);

        final field = tester.widget<RustTextInputField>(
          find.ancestor(of: editor, matching: find.byType(RustTextInputField)),
        );
        expect(field.additionalSelections, hasLength(1));
        final document = field.inputWindow.document;
        final originalVersion = document.version;

        await _commandKey(tester, testCase.platform, LogicalKeyboardKey.keyX);

        expect(clipboard['text'], testCase.clipboard);
        expect(controller.text, testCase.afterCut);
        expect(document.resync().content, testCase.afterCut);
        expect(document.version, greaterThan(originalVersion));
        expect(document.isDirty, isTrue);
        expect(file.readAsBytesSync(), originalBytes,
            reason: 'cut changes Rust first; disk waits for explicit save');

        await _commandKey(tester, testCase.platform, LogicalKeyboardKey.keyZ);
        expect(document.resync().content, testCase.normalizedSource);
        expect(document.isDirty, isFalse);

        await _commandKey(tester, testCase.platform, LogicalKeyboardKey.keyY);
        expect(document.resync().content, testCase.afterCut);
        expect(document.isDirty, isTrue);
        await _saveWithCurrentBinding(tester);
        debugDefaultTargetPlatformOverride = originalPlatform;
        expect(file.readAsStringSync(), testCase.savedAfterCut);
        expect(document.resync().content, testCase.afterCut);
      },
    );
  }

  testWidgets(
      'multi-cursor cut reads and removes lines outside the input window',
      (tester) async {
    const lineLength = 12000;
    final first = 'a' * lineLength;
    final middle = 'b' * lineLength;
    final last = 'c' * lineLength;
    final source = '$first\n$middle\n$last';
    final expectedClipboard = '$first\n\n$middle\n\n$last\n';
    final originalPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final temp = Directory.systemTemp.createTempSync('alula-multi-cut-window');
    final workspace = Directory('${temp.path}/workspace')..createSync();
    final file = File('${workspace.path}/sample.txt')
      ..writeAsStringSync(source);
    final base = temp.path.replaceAll(r'\', '/');
    Map<dynamic, dynamic> clipboard = const {};
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = Map<dynamic, dynamic>.from(call.arguments as Map);
        }
        if (call.method == 'Clipboard.getData') return clipboard;
        return null;
      },
    );
    addTearDown(() async {
      debugDefaultTargetPlatformOverride = originalPlatform;
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    await tester.pumpWidget(AlulaApp(
      autoFolder: workspace.path,
      layoutStore: LayoutStore(path: '$base/layout.json'),
      sessionStore: SessionStore(path: '$base/session.json'),
      keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('sample.txt').first);
    await tester.pump(const Duration(milliseconds: 300));

    final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
    await tester.showKeyboard(editor);
    await tester.pump();
    final controller = tester.widget<TextField>(editor).controller!;
    controller.selection =
        const TextSelection.collapsed(offset: lineLength + 1);
    await tester.pump();
    await _addCursorBelow(tester);
    await _addCursorAbove(tester);
    await _addCursorAbove(tester);

    final field = tester.widget<RustTextInputField>(
      find.ancestor(of: editor, matching: find.byType(RustTextInputField)),
    );
    expect(field.inputWindow.endUtf16, lessThan(2 * lineLength));
    final document = field.inputWindow.document;
    final originalVersion = document.version;

    await _commandKey(tester, TargetPlatform.linux, LogicalKeyboardKey.keyX);
    debugDefaultTargetPlatformOverride = originalPlatform;

    expect(clipboard['text'], expectedClipboard);
    expect(controller.text, isEmpty);
    expect(document.resync().content, isEmpty);
    expect(document.version, greaterThan(originalVersion));
    expect(document.isDirty, isTrue);
    expect(file.readAsStringSync(), source);

    await _commandKey(tester, TargetPlatform.linux, LogicalKeyboardKey.keyZ);
    expect(document.resync().content, source);
    expect(document.isDirty, isFalse);

    await _commandKey(tester, TargetPlatform.linux, LogicalKeyboardKey.keyY);
    expect(document.resync().content, isEmpty);
    expect(document.isDirty, isTrue);
  });
}
