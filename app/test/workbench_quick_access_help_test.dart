import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/workbench/command_history_store.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('quick access help opens existing providers and restores focus',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-provider-help-');
    addTearDown(() => temp.deleteSync(recursive: true));
    await tester.pumpWidget(MaterialApp(
      home: WorkbenchPage(
        layoutStore: LayoutStore(path: '${temp.path}/layout.json'),
        sessionStore: SessionStore(path: '${temp.path}/session.json'),
        keybindingsStore: KeybindingsStore(path: '${temp.path}/keys.json'),
        commandHistoryStore:
            CommandHistoryStore(path: '${temp.path}/history.json'),
      ),
    ));
    await tester.pumpAndSettle();
    final editor = tester.widget<RustTextInputField>(
      find.byType(RustTextInputField).first,
    );
    editor.focusNode!.requestFocus();
    await tester.pump();
    final panel = find.byKey(const ValueKey('quick-input'));
    final field = find.descendant(of: panel, matching: find.byType(TextField));
    Future<void> enter(String value) async {
      await tester.enterText(field, value);
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);
    }

    Future<void> close() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(editor.focusNode!.hasFocus, isTrue);
    }

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await enter('?');
    expect(find.text('显示快速访问入口'), findsOneWidget);
    expect(find.text('转到文件'), findsOneWidget);
    expect(find.text('显示并运行命令'), findsOneWidget);
    expect(find.text('Ctrl+Shift+P'), findsOneWidget);
    expect(find.text('按类别转到编辑器中的符号'), findsOneWidget);
    await tester.tap(find.text('转到行/列'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, ':');
    await enter(':2');
    await enter('?');
    expect(find.text('显示快速访问入口'), findsOneWidget);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    await enter('?>诊断面板');
    expect(tester.widget<TextField>(field).controller!.text, '>诊断面板');
    expect(find.text('查看: 诊断面板'), findsOneWidget);
    await close();

    // A pasted help prefix can route in one input event.
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();
    await enter('?:2');
    expect(tester.widget<TextField>(field).controller!.text, ':2');
    await close();

    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();
    await enter('?');
    await tester.tap(find.text('转到字符偏移'));
    await tester.pumpAndSettle();
    final position = tester.widget<TextField>(field).controller!;
    expect(position.text, '::');
    await enter(':2');
    expect(tester.widget<TextField>(field).controller, same(position));
    await enter('::1');
    expect(tester.widget<TextField>(field).controller, same(position));
    expect(
        find.byKey(const ValueKey('goto-zero-based-offset')), findsOneWidget);
    await close();

    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();
    await enter('?');
    await tester.tap(find.text('转到文件'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('文件名、路径或 path:行:列'), findsOneWidget);
    await close();
  });

  testWidgets('Quick Open routes typed prefixes to the existing providers',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-provider-prefix-');
    final file = File('${temp.path}/main.rs')
      ..writeAsStringSync('fn alpha() {}\n\nfn zebra() {}\n');
    final session = SessionStore(path: '${temp.path}/session.json')
      ..save({
        'v': 1,
        'workspace': temp.path,
        'focused': 'editor',
        'groups': [
          {
            'region': 'editor',
            'active': 95,
            'docs': [
              {'id': 95, 'path': file.path},
            ],
          },
        ],
      });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => temp.delete(recursive: true));
    });
    await tester.pumpWidget(MaterialApp(
      home: WorkbenchPage(
        layoutStore: LayoutStore(path: '${temp.path}/layout.json'),
        sessionStore: session,
        keybindingsStore: KeybindingsStore(path: '${temp.path}/keys.json'),
        commandHistoryStore:
            CommandHistoryStore(path: '${temp.path}/history.json'),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    final editor = tester.widget<RustTextInputField>(
      find.byType(RustTextInputField).first,
    );
    editor.focusNode!.requestFocus();
    await tester.pump();
    final panel = find.byKey(const ValueKey('quick-input'));
    final field = find.descendant(of: panel, matching: find.byType(TextField));

    Future<void> route(String value, String hint,
        {bool replaceFileQuery = false,
        List<String> earlierEdits = const []}) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.widget<TextField>(field).decoration?.hintText,
          '文件名、路径或 path:行:列');
      if (replaceFileQuery) {
        await tester.enterText(field, 'main');
        await tester.pump();
      }
      if (earlierEdits.isEmpty) {
        await tester.enterText(field, value);
      } else {
        final controller = tester.widget<TextField>(field).controller!;
        for (final text in [...earlierEdits, value]) {
          controller.value = TextEditingValue(
              text: text,
              selection: TextSelection.collapsed(offset: text.length));
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      }
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);
      final input = tester.widget<TextField>(field);
      expect(input.decoration?.hintText, hint);
      expect(input.controller!.text, value);
      expect(input.focusNode!.hasFocus, isTrue);
    }

    Future<void> close() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(editor.focusNode!.hasFocus, isTrue);
    }

    await route('>诊断面板', '输入命令名（> 前缀可省）', replaceFileQuery: true);
    expect(find.text('查看: 诊断面板'), findsOneWidget);
    await close();

    await route(':2:1', '转到行/列（:行:列，::字符偏移）');
    await close();

    await route('::9', '转到行/列（:行:列，::字符偏移）');
    expect(
        find.byKey(const ValueKey('goto-zero-based-offset')), findsOneWidget);
    await close();

    await route('@zebra', '转到符号（@名称，@: 按类别）');
    expect(find.byKey(const ValueKey('qi-zebra')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('qi-separator-function (1)')), findsNothing);
    await close();

    await route('@:zebra', '转到符号（@名称，@: 按类别）');
    expect(find.byKey(const ValueKey('qi-zebra')), findsOneWidget);
    expect(find.byKey(const ValueKey('qi-separator-function (1)')),
        findsOneWidget);
    await close();

    await route('@:zebra', '转到符号（@名称，@: 按类别）',
        earlierEdits: ['@', '@:', '@:z']);
    expect(find.byKey(const ValueKey('qi-zebra')), findsOneWidget);
    expect(find.byKey(const ValueKey('qi-separator-function (1)')),
        findsOneWidget);
    await close();

    await route('#zebra', '工作区符号（#名称）');
    await close();

    final editorField = tester.widget<TextField>(
        find.byKey(const ValueKey('rust-bounded-text-input')));
    final controller = editorField.controller!;
    const original = TextSelection(baseOffset: 1, extentOffset: 4);
    controller.selection = original;
    await tester.pump();

    Future<void> editPrefix(String value, String expectedHint) async {
      await tester.enterText(field, value);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 120));
      expect(panel, findsOneWidget);
      final input = tester.widget<TextField>(field);
      expect(input.decoration?.hintText, expectedHint);
      expect(input.controller!.text, value);
      expect(input.focusNode!.hasFocus, isTrue);
    }

    await route('>诊断面板', '输入命令名（> 前缀可省）');
    await editPrefix(':3:1', '转到行/列（:行:列，::字符偏移）');
    expect(
        controller.selection.extentOffset, controller.text.indexOf('fn zebra'));
    await editPrefix('@alpha', '转到符号（@名称，@: 按类别）');
    expect(find.byKey(const ValueKey('qi-alpha')), findsOneWidget);
    expect(controller.selection.extentOffset, 0);
    final symbolFocus = tester.widget<TextField>(field).focusNode;
    await editPrefix('@:alpha', '转到符号（@名称，@: 按类别）');
    expect(tester.widget<TextField>(field).focusNode, same(symbolFocus));
    expect(find.byKey(const ValueKey('qi-separator-function (1)')),
        findsOneWidget);
    await editPrefix('main.rs:3:1', '文件名、路径或 path:行:列');
    expect(controller.selection, original);
    await close();

    await route('?', '显示快速访问入口');
    await editPrefix('main.rs', '文件名、路径或 path:行:列');
    await tester.enterText(field, '@');
    await close();
    expect(controller.selection, original);
  });
}
