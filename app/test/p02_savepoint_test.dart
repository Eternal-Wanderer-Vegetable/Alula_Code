import 'dart:io';

import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pressChord(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
  bool shift = false,
}) async {
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  late Directory temp;
  late Directory workspace;
  late File file;
  late LayoutStore layout;
  late SessionStore session;
  late KeybindingsStore keybindings;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('alula_p02_savepoint_');
    workspace = Directory('${temp.path}/workspace')..createSync();
    file = File('${workspace.path}/note.txt')..writeAsStringSync('seed\n');
    final base = temp.path.replaceAll(r'\', '/');
    layout = LayoutStore(path: '$base/layout.json');
    session = SessionStore(path: '$base/session.json');
    keybindings = KeybindingsStore(path: '$base/keybindings.json');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  testWidgets('P02.2 dirty follows the saved text through undo and redo',
      (tester) async {
    await tester.pumpWidget(AlulaApp(
      autoFolder: workspace.path,
      layoutStore: layout,
      sessionStore: session,
      keybindingsStore: keybindings,
    ));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('note.txt').first);
    await tester.pump(const Duration(milliseconds: 200));

    final tab = find.byKey(const ValueKey('tab-2'));
    final editor = find.byType(TextField).first;
    final before = tester.widget<TextField>(editor).controller!.text;
    final edited = '$before# p02 savepoint\n';
    await tester.enterText(editor, edited);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.descendant(of: tab, matching: find.text('note.txt •')),
        findsOneWidget);

    await _pressChord(tester, LogicalKeyboardKey.keyS, control: true);
    await tester.pump(const Duration(milliseconds: 300));
    expect(file.readAsStringSync(), edited);
    expect(find.descendant(of: tab, matching: find.text('note.txt')),
        findsOneWidget,
        reason: '保存后 dirty 清除');

    await _pressChord(tester, LogicalKeyboardKey.keyZ, control: true);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<TextField>(editor).controller!.text, before);
    expect(find.descendant(of: tab, matching: find.text('note.txt •')),
        findsOneWidget,
        reason: 'undo 离开 savepoint 后重新变脏');
    expect(file.readAsStringSync(), edited, reason: 'undo 只改变缓冲区，不回写磁盘');

    await _pressChord(tester, LogicalKeyboardKey.keyZ,
        control: true, shift: true);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<TextField>(editor).controller!.text, edited);
    expect(find.descendant(of: tab, matching: find.text('note.txt')),
        findsOneWidget,
        reason: 'redo 回到 savepoint 后清除 dirty');
    expect(file.readAsStringSync(), edited);
  });
}
