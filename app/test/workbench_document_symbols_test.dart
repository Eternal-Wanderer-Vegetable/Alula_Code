import 'dart:io';

import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'symbol picker previews, cancels, groups and accepts Rust symbols',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-document-symbols');
    const text = 'fn alpha() {}\n\nfn zebra() {}\n';
    final file = File('${temp.path}/main.rs')..writeAsStringSync(text);
    final session = SessionStore(path: '${temp.path}/session.json')
      ..save({
        'v': 1,
        'focused': 'editor',
        'workspace': temp.path,
        'groups': [
          {
            'region': 'editor',
            'active': 95,
            'docs': [
              {'id': 95, 'path': file.path}
            ]
          }
        ],
      });
    CommandService? commands;
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
      onCommandServiceReady: (value) => commands = value,
    )));
    await tester.pump(const Duration(milliseconds: 600));
    final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
    final controller = tester.widget<TextField>(editor).controller!;
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 4);
    await tester.pump();
    final original = controller.selection;
    final opening = commands!.execute('workbench.action.gotoSymbol');
    await tester.pump(const Duration(milliseconds: 120));
    var input = find.descendant(
        of: find.byKey(const ValueKey('quick-input')),
        matching: find.byType(TextField));
    await tester.enterText(input, '@zebra');
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('qi-zebra')), findsOneWidget);
    expect(controller.selection.extentOffset, text.indexOf('fn zebra'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await opening;
    expect(controller.selection, original);
    final accepting = commands!.execute('workbench.action.gotoSymbol');
    await tester.pump(const Duration(milliseconds: 120));
    input = find.descendant(
        of: find.byKey(const ValueKey('quick-input')),
        matching: find.byType(TextField));
    await tester.enterText(input, '@:zebra');
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('qi-separator-function')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await accepting;
    expect(controller.selection.extentOffset, text.indexOf('fn zebra'));
    expect(controller.text, text);
    final side = commands!.execute('workbench.action.gotoSymbol');
    await tester.pump(const Duration(milliseconds: 120));
    input = find.descendant(
        of: find.byKey(const ValueKey('quick-input')),
        matching: find.byType(TextField));
    await tester.enterText(input, '@alpha');
    await tester.pump();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await side;
    expect(find.byKey(const ValueKey('wb-region-editor-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('rust-bounded-text-input')),
        findsNWidgets(2));
    final sourceField = find.descendant(
        of: find.byKey(const ValueKey('wb-region-editor')),
        matching: find.byKey(const ValueKey('rust-bounded-text-input')));
    final targetField = find.descendant(
        of: find.byKey(const ValueKey('wb-region-editor-2')),
        matching: find.byKey(const ValueKey('rust-bounded-text-input')));
    expect(
        tester
            .widget<TextField>(sourceField)
            .controller!
            .selection
            .extentOffset,
        text.indexOf('fn zebra'));
    expect(
        tester
            .widget<TextField>(targetField)
            .controller!
            .selection
            .extentOffset,
        text.indexOf('fn alpha'));
    expect(file.readAsStringSync(), text);
  });

  testWidgets('Document symbol picker guides an empty workbench',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-symbol-guidance');
    final file = File('${temp.path}/main.rs')
      ..writeAsStringSync('fn alpha() {}\n');
    final session = SessionStore(path: '${temp.path}/session.json')
      ..save({
        'v': 1,
        'focused': 'editor',
        'workspace': temp.path,
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
    final origin = FocusNode();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      origin.dispose();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => temp.delete(recursive: true));
    });
    late CommandService commands;
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: Column(
          children: [
            Expanded(
              child: WorkbenchPage(
                layoutStore: LayoutStore(path: '${temp.path}/layout.json'),
                sessionStore: session,
                keybindingsStore:
                    KeybindingsStore(path: '${temp.path}/keys.json'),
                onCommandServiceReady: (value) => commands = value,
              ),
            ),
            TextField(focusNode: origin),
          ],
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
    expect(editor, findsOneWidget);
    expect(
      await commands.execute('workbench.action.closeAllEditors'),
      CommandExecutionStatus.executed,
    );
    await tester.pumpAndSettle();
    expect(editor, findsNothing);
    origin.requestFocus();
    await tester.pump();
    expect(origin.hasPrimaryFocus, isTrue);

    final panel = find.byKey(const ValueKey('quick-input'));
    final input = find.descendant(of: panel, matching: find.byType(TextField));
    final guidance = find.text('先打开提供符号信息的文本编辑器，再转到符号。');
    final opening = commands.execute('workbench.action.gotoSymbol');
    await tester.pumpAndSettle();
    expect(guidance, findsOneWidget);
    expect(tester.widget<TextField>(input).controller!.text, '@');
    expect(tester.widget<TextField>(input).focusNode!.hasPrimaryFocus, isTrue);
    await tester.enterText(input, '@:alpha');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(guidance, findsOneWidget);
    expect(tester.widget<TextField>(input).controller!.text, '@:alpha');
    expect(editor, findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await opening, CommandExecutionStatus.executed);
    expect(panel, findsNothing);
    expect(origin.hasPrimaryFocus, isTrue);

    expect(await commands.execute('workbench.action.quickOpen'),
        CommandExecutionStatus.executed);
    await tester.pumpAndSettle();
    await tester.enterText(input, '@:beta');
    await tester.pumpAndSettle();
    expect(guidance, findsOneWidget);
    expect(tester.widget<TextField>(input).controller!.text, '@:beta');
    expect(tester.widget<TextField>(input).focusNode!.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(origin.hasPrimaryFocus, isTrue);
    expect(file.readAsStringSync(), 'fn alpha() {}\n');
  });
}
