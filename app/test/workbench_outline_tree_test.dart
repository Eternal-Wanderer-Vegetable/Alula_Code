import 'dart:io';

import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/document_symbols.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'Outline filters descendants, sorts, collapses and clears across same-name documents',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-outline-tree');
    final one = Directory('${temp.path}/one')..createSync();
    final two = Directory('${temp.path}/two')..createSync();
    final first = File('${one.path}/main.rs')
      ..writeAsStringSync(
          'mod outer {\n fn zebra() {}\n fn alpha() {}\n}\nfn root_fn() {}\n');
    final second = File('${two.path}/main.rs')
      ..writeAsStringSync('fn different() {}\n');
    final session = SessionStore(path: '${temp.path}/session.json')
      ..save({
        'v': 1,
        'focused': 'editor',
        'workspace': temp.path,
        'groups': [
          {
            'region': 'editor',
            'active': 90,
            'docs': [
              {'id': 90, 'path': first.path},
              {'id': 91, 'path': second.path}
            ]
          }
        ],
      });
    CommandService? commands;
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    await commands!.execute('view.outline');
    await tester.pump();
    expect(find.text('outer'), findsOneWidget);
    expect(find.text('zebra'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(ListTile), matching: find.text('alpha')),
        findsOneWidget);
    await tester.tap(find.byTooltip('折叠符号').first);
    await tester.pump();
    expect(find.text('zebra'), findsNothing);
    await tester.enterText(
        find.byKey(const ValueKey('outline-filter')), 'alpha');
    await tester.pump();
    expect(find.text('outer'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(ListTile), matching: find.text('alpha')),
        findsOneWidget);
    expect(find.text('root_fn'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('outline-filter')), '');
    await tester.pump();
    await tester.tap(find.byTooltip('展开符号').first);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('outline-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.ancestor(
        of: find.text('按名称排序'),
        matching: find.byType(CheckedPopupMenuItem<DocumentSymbolSort>)));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('alpha')).dy,
        lessThan(tester.getTopLeft(find.text('zebra')).dy));
    await tester.tap(find.byKey(const ValueKey('tab-91')).first);
    await tester.pump(const Duration(milliseconds: 600));
    await commands!.execute('view.outline');
    await commands!.execute('view.outline');
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('different'), findsOneWidget);
    expect(find.text('zebra'), findsNothing);
  });
}
