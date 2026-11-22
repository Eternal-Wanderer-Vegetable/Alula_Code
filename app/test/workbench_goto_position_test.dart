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
    expect(tester.widget<TextField>(input).controller!.text, ':');
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
    final offsets = commands!.execute('workbench.action.gotoOffset');
    await tester.pumpAndSettle();
    input = find.descendant(
        of: find.byKey(const ValueKey('quick-input')),
        matching: find.byType(TextField));
    expect(tester.widget<TextField>(input).controller!.text, '::');
    expect(
        find.byKey(const ValueKey('goto-zero-based-offset')), findsOneWidget);
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

  testWidgets('Go to Position Alt+Enter opens a shared view on the right',
      (tester) async {
    final temp =
        Directory.systemTemp.createTempSync('alula-goto-position-side');
    final file = File('${temp.path}/source.txt')
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
              {'id': 70, 'path': file.path},
            ],
          },
        ],
      });
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => temp.delete(recursive: true));
    });

    late CommandService commands;
    await tester.pumpWidget(MaterialApp(
      home: WorkbenchPage(
        layoutStore: LayoutStore(path: '${temp.path}/layout.json'),
        sessionStore: session,
        keybindingsStore: KeybindingsStore(path: '${temp.path}/keys.json'),
        onCommandServiceReady: (value) => commands = value,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    final panel = find.byKey(const ValueKey('quick-input'));
    final input = find.descendant(of: panel, matching: find.byType(TextField));
    Finder editorField(String region) => find.descendant(
          of: find.byKey(ValueKey('editor-body-drop-$region')),
          matching: find.byType(RustTextInputField),
        );
    RustTextInputField editor(String region) =>
        tester.widget<RustTextInputField>(editorField(region));
    TextSelection selection(String region) =>
        editor(region).inputWindow.initialValue.selection;

    Future<void> aside(String command, String query, int position) async {
      final original = selection('editor');
      final navigation = commands.execute(command);
      await tester.pumpAndSettle();
      await tester.enterText(input, query);
      await tester.pumpAndSettle();
      expect(selection('editor').extentOffset, position);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(await navigation, CommandExecutionStatus.executed);
      expect(panel, findsNothing);
      expect(selection('editor'), original);
      expect(selection('editor-2').extentOffset, position);
      expect(editor('editor-2').focusNode!.hasFocus, isTrue);
      expect(
        editor('editor-2').inputWindow.document,
        same(editor('editor').inputWindow.document),
      );
      expect(find.byType(RustTextInputField), findsNWidgets(2));
    }

    await tester.tap(editorField('editor'));
    await tester.pump();
    await aside('workbench.action.gotoLine', ':2:3', 8);

    await tester.tap(find.byKey(const ValueKey('editor-tab-label-editor-70')));
    await tester.pumpAndSettle();
    expect(editor('editor').focusNode!.hasFocus, isTrue);
    await aside('workbench.action.gotoOffset', '::10', 9);
    expect(file.readAsStringSync(), 'alpha\r\n😀beta\r\nlast');
  });

  testWidgets('Position commands explain how to proceed without an editor',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-goto-no-editor');
    final file = File('${temp.path}/source.txt')..writeAsStringSync('source');
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
              {'id': 70, 'path': file.path},
            ],
          },
        ],
      });
    final previousFocus = FocusNode();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      previousFocus.dispose();
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
            TextField(focusNode: previousFocus),
          ],
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    final editor = find.byType(RustTextInputField);
    expect(editor, findsOneWidget);
    expect(
      await commands.execute('workbench.action.closeAllEditors'),
      CommandExecutionStatus.executed,
    );
    await tester.pumpAndSettle();
    expect(editor, findsNothing);
    previousFocus.requestFocus();
    await tester.pump();
    expect(previousFocus.hasPrimaryFocus, isTrue);

    final panel = find.byKey(const ValueKey('quick-input'));
    final input = find.descendant(of: panel, matching: find.byType(TextField));
    final guidance = find.text('先打开文本编辑器，再转到行列或字符偏移。');

    Future<void> check(String prefix) async {
      expect(tester.widget<TextField>(input).controller!.text, prefix);
      expect(guidance, findsOneWidget);
      expect(
          find.byKey(const ValueKey('goto-zero-based-offset')), findsNothing);
      await tester.enterText(input, '${prefix}12');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(guidance, findsOneWidget);
      expect(find.byType(RustTextInputField), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(previousFocus.hasPrimaryFocus, isTrue);
    }

    for (final (command, prefix) in const [
      ('workbench.action.gotoLine', ':'),
      ('workbench.action.gotoOffset', '::'),
    ]) {
      final navigation = commands.execute(command);
      await tester.pumpAndSettle();
      await check(prefix);
      expect(await navigation, CommandExecutionStatus.executed);
    }

    await commands.execute('workbench.action.quickOpen', arguments: '?');
    await tester.pumpAndSettle();
    expect(find.text('转到行/列'), findsOneWidget);
    await tester.tap(find.text('转到字符偏移'));
    await tester.pumpAndSettle();
    await check('::');
    expect(file.readAsStringSync(), 'source');
  });
}
