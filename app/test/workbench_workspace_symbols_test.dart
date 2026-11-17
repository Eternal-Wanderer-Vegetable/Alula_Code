import 'dart:async';
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
      'workspace symbol picker reports unavailable provider without fake results',
      (tester) async {
    final temp =
        Directory.systemTemp.createTempSync('alula-workspace-symbol-empty');
    final file = File('${temp.path}/source.rs')
      ..writeAsStringSync('fn source() {}');
    final session = SessionStore(path: '${temp.path}/session.json')
      ..save({
        'v': 1,
        'focused': 'editor',
        'workspace': temp.path,
        'groups': [
          {
            'region': 'editor',
            'active': 97,
            'docs': [
              {'id': 97, 'path': file.path}
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
      autoFolder: temp.path,
      layoutStore: LayoutStore(path: '${temp.path}/layout.json'),
      sessionStore: session,
      keybindingsStore: KeybindingsStore(path: '${temp.path}/keys.json'),
      onCommandServiceReady: (value) => commands = value,
    )));
    await tester.pump(const Duration(milliseconds: 600));
    final opening = commands!.execute('workbench.action.showAllSymbols');
    await tester.pump(const Duration(milliseconds: 120));
    final input = find.descendant(
        of: find.byKey(const ValueKey('quick-input')),
        matching: find.byType(TextField));
    await tester.enterText(input, '#anything');
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('当前工作区没有可用符号提供程序'), findsOneWidget);
    expect(find.text('Source'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 120));
    await opening;
  });

  testWidgets('workspace symbol query cancellation discards late results',
      (tester) async {
    final temp =
        Directory.systemTemp.createTempSync('alula-workspace-symbol-cancel');
    final file = File('${temp.path}/source.rs')
      ..writeAsStringSync('fn source() {}');
    final session = SessionStore(path: '${temp.path}/session.json')
      ..save({
        'v': 1,
        'focused': 'editor',
        'workspace': temp.path,
        'groups': [
          {
            'region': 'editor',
            'active': 97,
            'docs': [
              {'id': 97, 'path': file.path}
            ]
          }
        ],
      });
    final pending = Completer<List<Map<String, Object?>>?>();
    final cancelled = Completer<void>();
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
      sessionStore: session,
      keybindingsStore: KeybindingsStore(path: '${temp.path}/keys.json'),
      onCommandServiceReady: (value) => commands = value,
      workspaceSymbolRequest: (id, query, signal) async {
        signal.then((_) {
          if (!cancelled.isCompleted) cancelled.complete();
        });
        return pending.future;
      },
    )));
    await tester.pump(const Duration(milliseconds: 600));
    final opening = commands!.execute('workbench.action.showAllSymbols');
    await tester.pump(const Duration(milliseconds: 120));
    final input = find.descendant(
        of: find.byKey(const ValueKey('quick-input')),
        matching: find.byType(TextField));
    await tester.enterText(input, '#slow');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester
        .runAsync(() => cancelled.future.timeout(const Duration(seconds: 2)));
    pending.complete([
      {
        'name': 'late',
        'kind': 12,
        'uri': 'file:///late.rs',
        'line': 0,
        'character': 0,
        'endLine': 0,
        'endCharacter': 4
      }
    ]);
    await tester.pump();
    expect(find.byKey(const ValueKey('quick-input')), findsNothing);
    expect(find.text('late'), findsNothing);
    await opening;
  });

  testWidgets(
      'workspace symbol provider fixture navigates cross-file UTF-16 ranges',
      (tester) async {
    final temp =
        Directory.systemTemp.createTempSync('alula-workspace-symbol-picker');
    final source = File('${temp.path}/source.rs')
      ..writeAsStringSync('fn source() {}\n');
    final target = File('${temp.path}/target.rs')
      ..writeAsStringSync('head\r\n😀target\r\n');
    final session = SessionStore(path: '${temp.path}/session.json')
      ..save({
        'v': 1,
        'focused': 'editor',
        'workspace': temp.path,
        'groups': [
          {
            'region': 'editor',
            'active': 98,
            'docs': [
              {'id': 98, 'path': source.path}
            ]
          }
        ],
      });
    CommandService? commands;
    final queries = <String>[];
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => temp.delete(recursive: true));
    });
    await tester.pumpWidget(MaterialApp(
        home: WorkbenchPage(
      autoFolder: temp.path,
      layoutStore: LayoutStore(path: '${temp.path}/layout.json'),
      sessionStore: session,
      keybindingsStore: KeybindingsStore(path: '${temp.path}/keys.json'),
      onCommandServiceReady: (value) => commands = value,
      workspaceSymbolRequest: (id, query, cancel) async {
        queries.add(query);
        return [
          {
            'name': 'target',
            'kind': 12,
            'uri': Uri.file(target.path).toString(),
            'line': 1,
            'character': 2,
            'endLine': query == 'stale' ? 99 : 1,
            'endCharacter': 8,
            'containerName': 'fixture'
          }
        ];
      },
    )));
    await tester.pump(const Duration(milliseconds: 600));
    final opening = commands!.execute('workbench.action.showAllSymbols');
    await tester.pump(const Duration(milliseconds: 120));
    final input = find.descendant(
        of: find.byKey(const ValueKey('quick-input')),
        matching: find.byType(TextField));
    await tester.enterText(input, '#target');
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('qi-target')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
      final fields = find.byKey(const ValueKey('rust-bounded-text-input'));
      if (fields.evaluate().isNotEmpty &&
          tester
              .widget<TextField>(fields)
              .controller!
              .text
              .contains('😀target')) {
        break;
      }
    }
    await opening;
    final controller = tester
        .widget<TextField>(
            find.byKey(const ValueKey('rust-bounded-text-input')))
        .controller!;
    expect(controller.selection,
        const TextSelection(baseOffset: 7, extentOffset: 13));
    expect(queries, ['target']);
    final oldSelection = controller.selection;
    final stale = commands!.execute('workbench.action.showAllSymbols');
    await tester.pump(const Duration(milliseconds: 120));
    final staleInput = find.descendant(
        of: find.byKey(const ValueKey('quick-input')),
        matching: find.byType(TextField));
    await tester.enterText(staleInput, '#stale');
    await tester.pump();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await stale;
    expect(controller.selection, oldSelection);
    expect(tester.takeException(), isNull);
    expect(target.readAsStringSync(), 'head\r\n😀target\r\n');
  });
}
