import 'dart:io';

import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/native_drag_drop.dart';

void main() {
  setUpAll(mockNativeDragDrop);

  testWidgets('Quick Open disables repeated page actions during loading',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-quick-open-pages');
    for (var i = 0; i < 220; i++) {
      File('${temp.path}/file-$i.txt').writeAsStringSync('');
    }
    CommandService? commands;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => temp.delete(recursive: true));
    });
    await tester.pumpWidget(MaterialApp(
        home: WorkbenchPage(
      autoFolder: temp.path,
      layoutStore: LayoutStore(path: '${temp.path}/layout.json'),
      sessionStore: SessionStore(path: '${temp.path}/session.json'),
      keybindingsStore: KeybindingsStore(path: '${temp.path}/keys.json'),
      onCommandServiceReady: (value) => commands = value,
    )));
    await tester.pump(const Duration(milliseconds: 600));
    await commands!.execute('view.quickOpen');
    await tester.pump(const Duration(milliseconds: 120));
    final input = find.descendant(
        of: find.byKey(const ValueKey('quick-input')),
        matching: find.byType(TextField));
    await tester.enterText(input, 'file-');
    final next = find.byKey(const ValueKey('quick-open-next-page'));
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
      if (next.evaluate().isNotEmpty &&
          tester.widget<IconButton>(next).onPressed != null) {
        break;
      }
    }
    expect(next, findsOneWidget);
    await tester.tap(next);
    await tester.pump();
    expect(tester.widget<IconButton>(next).onPressed, isNull);
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
      if (find.byKey(const ValueKey('quick-input-loading')).evaluate().isEmpty) {
        break;
      }
    }
    expect(next, findsNothing);
    expect(
        find.byKey(const ValueKey('quick-open-previous-page')), findsOneWidget);
    expect(find.text('无匹配项'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

  testWidgets(
      'Quick Open resolves absolute path and line suffix without a workspace',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-quick-open-query');
    final file = File('${temp.path}/position.txt')
      ..writeAsStringSync('alpha\r\n😀beta\r\nlast');
    CommandService? commands;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => temp.delete(recursive: true));
    });
    await tester.pumpWidget(MaterialApp(
        home: WorkbenchPage(
      layoutStore: LayoutStore(path: '${temp.path}/layout.json'),
      sessionStore: SessionStore(path: '${temp.path}/session.json'),
      keybindingsStore: KeybindingsStore(path: '${temp.path}/keys.json'),
      onCommandServiceReady: (value) => commands = value,
    )));
    await tester.pump(const Duration(milliseconds: 600));
    await commands!.execute('view.quickOpen');
    await tester.pump(const Duration(milliseconds: 120));
    final input = find.descendant(
        of: find.byKey(const ValueKey('quick-input')),
        matching: find.byType(TextField));
    await tester.enterText(input, '${file.path}:2:3');
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
      if (find.byKey(const ValueKey('qi-position.txt')).evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.byKey(const ValueKey('qi-position.txt')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
      final fields = find.byKey(const ValueKey('rust-bounded-text-input'));
      if (fields.evaluate().isNotEmpty &&
          tester.widget<TextField>(fields).controller!.selection.extentOffset ==
              8) {
        break;
      }
    }
    final controller = tester
        .widget<TextField>(
            find.byKey(const ValueKey('rust-bounded-text-input')))
        .controller!;
    expect(controller.text, 'alpha\n😀beta\nlast');
    expect(controller.selection.extentOffset, 8);
    expect(file.readAsStringSync(), 'alpha\r\n😀beta\r\nlast');
  });
}
