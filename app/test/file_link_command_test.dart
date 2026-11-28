import 'dart:convert';
import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Open Link opens the local file URI under the active caret',
      (tester) async {
    final profile = Directory.systemTemp.createTempSync('alula-file-link');
    final destination = File('${profile.path}/target file 🐙.txt')
      ..writeAsStringSync('destination text\r\n');
    final targetUri = destination.uri.toString();
    final directoryUri = (Directory('${profile.path}/directory-target')
          ..createSync())
        .uri
        .toString();
    final invalidUri = '$targetUri%00.txt';
    final original = utf8.encode(
      '\uFEFF前缀 🦊\r\n($targetUri)\r\n$directoryUri\r\n$invalidUri\r\n',
    );
    final source = File('${profile.path}/source.md')
      ..writeAsBytesSync(original);
    final session = SessionStore(path: '${profile.path}/session.json')
      ..save({
        'v': 1,
        'workspace': profile.path,
        'focused': 'editor',
        'groups': [
          {
            'region': 'editor',
            'active': 3,
            'docs': [
              {'id': 3, 'path': source.path},
            ],
          },
        ],
      });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => profile.delete(recursive: true));
    });
    late CommandService commands;
    await tester.pumpWidget(MaterialApp(
      home: WorkbenchPage(
        autoFolder: profile.path,
        layoutStore: LayoutStore(path: '${profile.path}/layout.json'),
        sessionStore: session,
        keybindingsStore: KeybindingsStore(path: '${profile.path}/keys.json'),
        onCommandServiceReady: (value) => commands = value,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));

    final editor = find.byType(RustTextInputField);
    expect(editor, findsOneWidget);
    EditableText currentInput() => tester.widget<EditableText>(
          find.descendant(of: editor, matching: find.byType(EditableText)),
        );
    final input = currentInput();
    final start = input.controller.text.indexOf(targetUri);
    expect(start, greaterThanOrEqualTo(0));
    expect(commands.byId('editor.action.openLink'), isNotNull);
    input.controller.selection = const TextSelection.collapsed(offset: 1);
    await tester.pumpAndSettle();
    expect(
      await tester.runAsync(() => commands.execute('editor.action.openLink')),
      CommandExecutionStatus.executed,
    );
    expect(input.controller.selection.extentOffset, 1);
    expect(input.controller.text, contains(targetUri));

    for (final unavailableUri in [directoryUri, invalidUri]) {
      final unavailableStart = input.controller.text.indexOf(unavailableUri);
      expect(unavailableStart, greaterThanOrEqualTo(0));
      final offset = unavailableStart + 9;
      input.controller.selection = TextSelection.collapsed(offset: offset);
      await tester.pumpAndSettle();
      expect(
        await tester.runAsync(() => commands.execute('editor.action.openLink')),
        CommandExecutionStatus.executed,
      );
      expect(currentInput().controller, same(input.controller));
      expect(currentInput().controller.selection.extentOffset, offset);
      expect(currentInput().controller.text, contains(targetUri));
      expect(find.textContaining('打开失败'), findsNothing);
    }

    input.controller.selection = TextSelection.collapsed(offset: start + 9);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();
    final palette = find.byKey(const ValueKey('quick-input'));
    expect(palette, findsOneWidget);
    await tester.enterText(
      find.descendant(of: palette, matching: find.byType(TextField)),
      '打开链接',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('qi-编辑器: 打开链接')), findsOneWidget);
    await tester.runAsync(() => tester.sendKeyEvent(LogicalKeyboardKey.enter));
    await tester.pumpAndSettle();
    expect(palette, findsNothing);
    final opened = tester.widget<RustTextInputField>(editor);
    expect(opened.inputWindow.text, contains('destination text'));
    expect(opened.focusNode!.hasPrimaryFocus, isTrue);
    expect(source.readAsBytesSync(), original);
  });
}
