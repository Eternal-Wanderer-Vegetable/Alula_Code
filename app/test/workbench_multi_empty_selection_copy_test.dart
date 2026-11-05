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

Future<void> _pressAddCursorVertical(
  WidgetTester tester, {
  required bool above,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(
    above ? LogicalKeyboardKey.arrowUp : LogicalKeyboardKey.arrowDown,
  );
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.pump();
}

void main() {
  const cases = <({TargetPlatform platform, String source, String expected})>[
    (
      platform: TargetPlatform.windows,
      source: 'first\nmiddle\nlast',
      expected: 'first\r\n\nmiddle\r\n\nlast\r\n',
    ),
    (
      platform: TargetPlatform.linux,
      source: 'first\nmiddle\nlast',
      expected: 'first\n\nmiddle\n\nlast\n',
    ),
    (
      platform: TargetPlatform.macOS,
      source: 'first\r\nmiddle\r\nlast',
      expected: 'first\r\n\r\nmiddle\r\n\r\nlast\r\n',
    ),
  ];

  for (final testCase in cases) {
    testWidgets(
      'TargetPlatform.${testCase.platform.name} copies multiple empty selections as lines',
      (tester) async {
        final originalPlatform = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = testCase.platform;
        final temp =
            Directory.systemTemp.createTempSync('alula-multi-copy-line');
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
        expect(controller.text, 'first\nmiddle\nlast');
        controller.selection = const TextSelection.collapsed(offset: 6);
        await tester.pump();

        await _pressAddCursorVertical(tester, above: false);
        await _pressAddCursorVertical(tester, above: true);
        final input = tester.widget<RustTextInputField>(
          find.ancestor(of: editor, matching: find.byType(RustTextInputField)),
        );
        expect(input.additionalSelections, hasLength(2));
        final document = input.inputWindow.document;
        final sourceVersion = document.version;
        expect(document.resync().content, 'first\nmiddle\nlast');

        final modifier = testCase.platform == TargetPlatform.macOS
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(modifier);
        await tester.pump();
        await tester.pump();
        debugDefaultTargetPlatformOverride = originalPlatform;

        expect(clipboard['text'], testCase.expected);
        expect(document.version, sourceVersion);
        expect(document.resync().content, 'first\nmiddle\nlast');
        expect(document.isDirty, isFalse);
        expect(file.readAsBytesSync(), originalBytes);
      },
    );
  }

  testWidgets('multi-cursor line copy reads carets outside the input window',
      (tester) async {
    const lineLength = 12000;
    final source =
        '${'a' * lineLength}\n${'b' * lineLength}\n${'c' * lineLength}';
    final expected =
        '${'a' * lineLength}\n\n${'b' * lineLength}\n\n${'c' * lineLength}\n';
    final originalPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final temp = Directory.systemTemp.createTempSync('alula-multi-copy-window');
    final workspace = Directory('${temp.path}/workspace')..createSync();
    final file = File('${workspace.path}/sample.txt')
      ..writeAsStringSync(source);
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
    controller.selection =
        const TextSelection.collapsed(offset: lineLength + 1);
    await tester.pump();

    await _pressAddCursorVertical(tester, above: false);
    await _pressAddCursorVertical(tester, above: true);
    await _pressAddCursorVertical(tester, above: true);
    final input = tester.widget<RustTextInputField>(
      find.ancestor(of: editor, matching: find.byType(RustTextInputField)),
    );
    expect(input.inputWindow.endUtf16, lessThan(2 * lineLength));
    final document = input.inputWindow.document;
    final sourceVersion = document.version;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();
    debugDefaultTargetPlatformOverride = originalPlatform;

    expect(clipboard['text'], expected);
    expect(document.version, sourceVersion);
    expect(document.resync().content, source);
    expect(document.isDirty, isFalse);
    expect(file.readAsBytesSync(), originalBytes);
  });
}
