import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
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
  bool shift = false,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _waitForIsolates(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 80)),
  );
  await tester.pump();
}

String _documentText(WidgetTester tester) => tester
    .state<RustTextInputFieldState>(find.byType(RustTextInputField))
    .widget
    .inputWindow
    .document
    .resync()
    .content;

void main() {
  testWidgets(
    'regex current and replace-all edits use one undo step and save back',
    (tester) async {
      final temp = Directory.systemTemp.createTempSync('alula-regex-replace-');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });

      final workspace = Directory('${temp.path}/workspace')..createSync();
      final file = File('${workspace.path}/notes.txt')
        ..writeAsStringSync('foo_1 foo_2');
      final base = temp.path.replaceAll(r'\', '/');
      await tester.pumpWidget(AlulaApp(
        autoFolder: workspace.path,
        layoutStore: LayoutStore(path: '$base/layout.json'),
        sessionStore: SessionStore(path: '$base/session.json'),
        keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
      ));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('notes.txt').first);
      await tester.pump(const Duration(milliseconds: 300));

      await _pressChord(tester, LogicalKeyboardKey.keyH);
      final findInput = find.byKey(const ValueKey('find-query-input'));
      final replaceInput = find.byKey(const ValueKey('replace-query-input'));
      await tester.enterText(findInput, r'foo_(\d+)');
      await tester.enterText(replaceInput, r'item-$1');
      await tester.tap(find.byKey(const ValueKey('find-regex')));
      await _waitForIsolates(tester);
      await tester.pumpAndSettle();
      expect(find.text('-/2'), findsOneWidget);

      await tester.tap(find.byTooltip('替换'));
      await _waitForIsolates(tester);
      await tester.pumpAndSettle();
      expect(_documentText(tester), 'foo_1 foo_2',
          reason: 'the first click selects the next match');
      expect(
        tester
            .state<RustTextInputFieldState>(find.byType(RustTextInputField))
            .editingValue
            .selection,
        const TextSelection(baseOffset: 0, extentOffset: 5),
      );
      await tester.tap(find.byTooltip('替换'));
      await _waitForIsolates(tester);
      await tester.pumpAndSettle();
      expect(_documentText(tester), 'item-1 foo_2');

      await tester.tap(find.byType(RustTextInputField));
      await _pressChord(tester, LogicalKeyboardKey.keyS);
      await tester.pump(const Duration(milliseconds: 200));
      expect(file.readAsStringSync(), 'item-1 foo_2');

      await _pressChord(tester, LogicalKeyboardKey.keyZ);
      await tester.pumpAndSettle();
      expect(_documentText(tester), 'foo_1 foo_2');
      await _pressChord(tester, LogicalKeyboardKey.keyZ, shift: true);
      await tester.pumpAndSettle();
      expect(_documentText(tester), 'item-1 foo_2');

      await tester.tap(find.byTooltip('全部替换'));
      await _waitForIsolates(tester);
      await tester.pumpAndSettle();
      expect(_documentText(tester), 'item-1 item-2');
      await _pressChord(tester, LogicalKeyboardKey.keyZ);
      await tester.pumpAndSettle();
      expect(_documentText(tester), 'item-1 foo_2',
          reason: 'replace-all is one reversible document edit');
    },
  );

  testWidgets('a superseded regex replace cannot apply its stale result',
      (tester) async {
    final temp =
        Directory.systemTemp.createTempSync('alula-regex-replace-stale-');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    final workspace = Directory('${temp.path}/workspace')..createSync();
    final source = '${'a' * 20000}b';
    File('${workspace.path}/notes.txt').writeAsStringSync(source);
    final base = temp.path.replaceAll(r'\', '/');
    await tester.pumpWidget(AlulaApp(
      autoFolder: workspace.path,
      layoutStore: LayoutStore(path: '$base/layout.json'),
      sessionStore: SessionStore(path: '$base/session.json'),
      keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('notes.txt').first);
    await tester.pump(const Duration(milliseconds: 300));

    await _pressChord(tester, LogicalKeyboardKey.keyH);
    final findInput = find.byKey(const ValueKey('find-query-input'));
    await tester.enterText(findInput, r'^(a+)+$');
    await tester.enterText(
      find.byKey(const ValueKey('replace-query-input')),
      'replacement',
    );
    await tester.tap(find.byKey(const ValueKey('find-regex')));
    await tester.tap(find.byTooltip('全部替换'));
    await tester.enterText(findInput, 'no-match');
    await _waitForIsolates(tester);
    await tester.pumpAndSettle();

    expect(_documentText(tester), source);
  });
}
