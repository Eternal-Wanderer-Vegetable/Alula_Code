import 'dart:convert';
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

Future<void> _pressCommand(
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
}

void main() {
  const cases = <({
    TargetPlatform platform,
    String source,
    String editorText,
    int caretOffset,
    String clipboardText,
    String cutText,
  })>[
    (
      platform: TargetPlatform.windows,
      source: 'before\nline 🙂\nafter',
      editorText: 'before\nline 🙂\nafter',
      caretOffset: 10,
      clipboardText: 'line 🙂\r\n',
      cutText: 'before\nafter',
    ),
    (
      platform: TargetPlatform.windows,
      source: 'only',
      editorText: 'only',
      caretOffset: 2,
      clipboardText: 'only\r\n',
      cutText: '',
    ),
    (
      platform: TargetPlatform.linux,
      source: 'before\nlast',
      editorText: 'before\nlast',
      caretOffset: 9,
      clipboardText: 'last\n',
      cutText: 'before',
    ),
    (
      platform: TargetPlatform.macOS,
      source: 'before\r\n\r\nafter',
      editorText: 'before\n\nafter',
      caretOffset: 7,
      clipboardText: '\r\n',
      cutText: 'before\nafter',
    ),
  ];

  for (final testCase in cases) {
    testWidgets(
      'TargetPlatform.${testCase.platform.name} cuts an empty-selection line and supports undo/redo',
      (tester) async {
        final originalPlatform = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = testCase.platform;
        final temp = Directory.systemTemp.createTempSync('alula-cut-line');
        final workspace = Directory('${temp.path}/workspace')..createSync();
        final file = File('${workspace.path}/sample.txt')
          ..writeAsBytesSync(utf8.encode(testCase.source));
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
        expect(controller.text, testCase.editorText);
        controller.selection = TextSelection.collapsed(
          offset: testCase.caretOffset,
        );
        await tester.pump();

        await _pressCommand(
          tester,
          testCase.platform,
          LogicalKeyboardKey.keyX,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        expect(clipboard['text'], testCase.clipboardText);
        expect(controller.text, testCase.cutText);
        final rustInput = find.ancestor(
          of: editor,
          matching: find.byType(RustTextInputField),
        );
        final document = tester
            .widget<RustTextInputField>(rustInput)
            .inputWindow
            .document;
        expect(document.resync().content, testCase.cutText);
        expect(document.isDirty, isTrue);
        expect(file.readAsBytesSync(), originalBytes);

        await _pressCommand(
          tester,
          testCase.platform,
          LogicalKeyboardKey.keyZ,
        );
        await tester.pump(const Duration(milliseconds: 80));
        expect(controller.text, testCase.editorText);
        expect(document.isDirty, isFalse);

        await _pressCommand(
          tester,
          testCase.platform,
          LogicalKeyboardKey.keyY,
        );
        await tester.pump(const Duration(milliseconds: 80));
        expect(controller.text, testCase.cutText);
        expect(document.isDirty, isTrue);
        expect(file.readAsBytesSync(), originalBytes);
        debugDefaultTargetPlatformOverride = originalPlatform;
      },
    );
  }
}
