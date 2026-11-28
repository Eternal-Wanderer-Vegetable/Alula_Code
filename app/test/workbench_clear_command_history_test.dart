import 'dart:io';

import 'package:alula_app/workbench/command_history.dart';
import 'package:alula_app/workbench/command_history_store.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _clear = 'workbench.action.clearCommandHistory';

void main() {
  test('clear replaces both persisted generations of command history', () {
    final temp = Directory.systemTemp.createTempSync('alula-clear-history-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final store = CommandHistoryStore(path: '${temp.path}/history.json');
    final previous = CommandHistory(commandIds: ['file.save']);
    expect(store.save(previous), isTrue);
    previous.record('view.panelDiagnostics');
    expect(store.save(previous), isTrue);
    final backup = CommandHistoryStore(path: '${store.path}.bak');
    expect(backup.load().commandIds, ['file.save']);

    expect(store.clear(), isTrue);
    expect(store.load().isEmpty, isTrue);
    expect(backup.load().isEmpty, isTrue);
    File(store.path).writeAsStringSync('invalid primary');
    expect(store.load().isEmpty, isTrue);
  });

  test('a blocked journal write leaves saved command history available', () {
    final temp = Directory.systemTemp.createTempSync('alula-clear-history-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final store = CommandHistoryStore(path: '${temp.path}/history.json');
    expect(store.save(CommandHistory(commandIds: ['file.save'])), isTrue);
    Directory('${store.path}.tmp').createSync();

    expect(store.clear(), isFalse);
    expect(store.load().commandIds, ['file.save']);
  });

  testWidgets(
      'clear command history waits for confirmation and survives restart',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-clear-palette-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final store = CommandHistoryStore(path: '${temp.path}/history.json');
    expect(store.save(CommandHistory(commandIds: ['file.save'])), isTrue);

    Future<void> start() async {
      await tester.pumpWidget(MaterialApp(
        home: WorkbenchPage(
          layoutStore: LayoutStore(path: '${temp.path}/layout.json'),
          sessionStore: SessionStore(path: '${temp.path}/session.json'),
          keybindingsStore:
              KeybindingsStore(path: '${temp.path}/keybindings.json'),
          commandHistoryStore: store,
        ),
      ));
      await tester.pumpAndSettle();
    }

    final palette = find.byKey(const ValueKey('quick-input'));
    final dialog = find.byType(AlertDialog);
    Future<void> openPalette() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      expect(palette, findsOneWidget);
    }

    Future<void> openConfirmation() async {
      await openPalette();
      await tester.enterText(
        find.descendant(of: palette, matching: find.byType(TextField)),
        '清除命令历史记录',
      );
      await tester.pumpAndSettle();
      expect(find.text('查看: 清除命令历史记录'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(dialog, findsOneWidget);
      expect(find.text('清除最近使用的命令？'), findsOneWidget);
    }

    await start();
    await openConfirmation();
    expect(store.load().commandIds, [_clear, 'file.save']);
    await tester.tap(find.descendant(of: dialog, matching: find.text('取消')));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(store.load().commandIds, [_clear, 'file.save']);

    await openConfirmation();
    await tester.tap(find.descendant(of: dialog, matching: find.text('清除')));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(store.load().isEmpty, isTrue);
    await openPalette();
    expect(find.text('最近使用'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    File(store.path).writeAsStringSync('invalid primary');
    await start();
    await openPalette();
    expect(find.text('最近使用'), findsNothing);
    expect(store.load().isEmpty, isTrue);
  });
}
