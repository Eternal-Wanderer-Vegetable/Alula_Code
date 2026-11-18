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
      'Go to Line accepts UTF-16 positions and cancel leaves document state intact',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-goto-position');
    final file = File('${temp.path}/main.txt')
      ..writeAsStringSync('alpha\r\n😀beta\r\nlast');
    final session = SessionStore(path: '${temp.path}/session.json')
      ..save({
        'v': 1,
        'focused': 'editor',
        'workspace': temp.path,
        'groups': [
          {
            'region': 'editor',
            'active': 70,
            'docs': [
              {'id': 70, 'path': file.path}
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
    final text = controller.text;
    await tester.tap(editor);
    final original = controller.selection;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    var input = find.descendant(
        of: find.byKey(const ValueKey('quick-input')),
        matching: find.byType(TextField));
    expect(input, findsOneWidget);
    await tester.enterText(input, ':bad');
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp(r'^错误')), findsWidgets,
        reason: 'Product validator exposes a typed error severity');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quick-input')), findsOneWidget);
    expect(controller.selection, original);
    expect(file.readAsStringSync(), 'alpha\r\n😀beta\r\nlast');
    await tester.enterText(input, ':2:3');
    await tester.pumpAndSettle();
    expect(controller.selection.extentOffset, 8,
        reason: 'valid input previews the target');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(controller.selection, original);
    expect(controller.text, text);
    final navigating = commands!.execute('workbench.action.gotoLine');
    await tester.pumpAndSettle();
    input = find.descendant(
        of: find.byKey(const ValueKey('quick-input')),
        matching: find.byType(TextField));
    await tester.enterText(input, ':2:3');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await navigating;
    expect(controller.selection.extentOffset, 8);
    expect(controller.text, text);
    final offsets = commands!.execute('workbench.action.gotoLine');
    await tester.pumpAndSettle();
    input = find.descendant(
        of: find.byKey(const ValueKey('quick-input')),
        matching: find.byType(TextField));
    await tester.enterText(input, '::9');
    await tester.pumpAndSettle();
    expect(controller.selection.extentOffset, 8);
    await tester.tap(find.byKey(const ValueKey('goto-zero-based-offset')));
    await tester.pumpAndSettle();
    expect(controller.selection.extentOffset, 9);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await offsets;
    await tester.pump(const Duration(milliseconds: 600));
    expect(session.tryLoad()?['gotoLine.useZeroBasedOffset'], isTrue);
    expect(file.readAsStringSync(), 'alpha\r\n😀beta\r\nlast');
  });
}
