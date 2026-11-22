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
    await tester.tap(find.text('转到文件'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('文件名、路径或 path:行:列'), findsOneWidget);
    await close();
  });
}
