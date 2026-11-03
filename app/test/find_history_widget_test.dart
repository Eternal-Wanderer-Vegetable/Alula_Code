import 'dart:io';

import 'package:alula_app/editor/find_replace_history.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/find_history_store.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Find and Replace history navigates and survives restart',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-find-history-ui-');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    final workspace = Directory('${temp.path}/workspace')..createSync();
    File('${workspace.path}/notes.txt').writeAsStringSync('first second');
    final base = temp.path.replaceAll(r'\', '/');
    final layoutStore = LayoutStore(path: '$base/layout.json');
    final sessionStore = SessionStore(path: '$base/session.json');
    final keybindingsStore = KeybindingsStore(path: '$base/keybindings.json');
    final historyStore =
        FindReplaceHistoryStore(directory: '$base/find-history');

    Future<void> launch() async {
      await tester.pumpWidget(AlulaApp(
        autoFolder: workspace.path,
        layoutStore: layoutStore,
        sessionStore: sessionStore,
        keybindingsStore: keybindingsStore,
        findReplaceHistoryStore: historyStore,
      ));
      await tester.pump(const Duration(milliseconds: 600));
    }

    Future<void> pressChord(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 100));
    }

    await launch();
    await pressChord(LogicalKeyboardKey.keyF);
    final findInput = find.byKey(const ValueKey('find-query-input'));
    await tester.enterText(findInput, 'first');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.enterText(findInput, 'second');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.enterText(findInput, 'draft');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(tester.widget<TextField>(findInput).controller!.text, 'second');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(tester.widget<TextField>(findInput).controller!.text, 'draft');
    await tester.pump(const Duration(milliseconds: 600));

    await pressChord(LogicalKeyboardKey.keyH);
    final replaceInput = find.byKey(const ValueKey('replace-query-input'));
    await tester.enterText(replaceInput, 'replacement-one');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.enterText(replaceInput, 'replacement-two');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(tester.widget<TextField>(replaceInput).controller!.text,
        'replacement-two');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(tester.widget<TextField>(replaceInput).controller!.text,
        'replacement-one');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(tester.widget<TextField>(replaceInput).controller!.text,
        'replacement-two');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(
        historyStore.load(workspace.path).find, ['first', 'second', 'draft']);
    expect(historyStore.load(workspace.path).replace,
        ['replacement-one', 'replacement-two']);
    await launch();
    await pressChord(LogicalKeyboardKey.keyF);
    await tester.tap(findInput);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(tester.widget<TextField>(findInput).controller!.text, 'draft');

    await pressChord(LogicalKeyboardKey.keyH);
    await tester.tap(find.byKey(const ValueKey('replace-query-input')));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('replace-query-input')))
          .controller!
          .text,
      'replacement-two',
    );
  });

  testWidgets('never history stays in memory only', (tester) async {
    final temp =
        Directory.systemTemp.createTempSync('alula-find-history-never-');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    final workspace = Directory('${temp.path}/workspace')..createSync();
    File('${workspace.path}/notes.txt').writeAsStringSync('needle');
    final base = temp.path.replaceAll(r'\', '/');
    final historyStore =
        FindReplaceHistoryStore(directory: '$base/find-history');
    final configuration = FindReplaceHistoryConfiguration.fromSettings({
      'editor.find.history': 'never',
      'editor.find.replaceHistory': 'never',
    });

    Future<void> launch() async {
      await tester.pumpWidget(AlulaApp(
        autoFolder: workspace.path,
        layoutStore: LayoutStore(path: '$base/layout.json'),
        sessionStore: SessionStore(path: '$base/session.json'),
        keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
        findReplaceHistoryStore: historyStore,
        findReplaceHistoryConfiguration: configuration,
      ));
      await tester.pump(const Duration(milliseconds: 600));
    }

    Future<void> openFind() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 100));
    }

    await launch();
    await openFind();
    final findInput = find.byKey(const ValueKey('find-query-input'));
    await tester.enterText(findInput, 'private-query');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(
        tester.widget<TextField>(findInput).controller!.text, 'private-query');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(historyStore.load(workspace.path).find, isEmpty);
    await launch();
    await openFind();
    await tester.tap(findInput);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(tester.widget<TextField>(findInput).controller!.text, isEmpty);
  });
}
