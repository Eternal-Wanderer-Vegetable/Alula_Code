import 'dart:io';

import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/file_paths.dart';
import 'helpers/native_drag_drop.dart';

void main() {
  setUpAll(mockNativeDragDrop);

  testWidgets('tree find filters unloaded files, restores the tree and focus',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-tree-find');
    final workspace = Directory('${temp.path}/workspace')..createSync();
    final nested = Directory('${workspace.path}/nested')..createSync();
    final file = File('${nested.path}/main.rs')..writeAsStringSync('😀\r\n');
    final alpha = File('${workspace.path}/alpha.txt')
      ..writeAsStringSync('alpha');
    CommandService? commands;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => temp.delete(recursive: true));
    });
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: WorkbenchPage(
      autoFolder: workspace.path,
      layoutStore: LayoutStore(path: '${temp.path}/layout.json'),
      sessionStore: SessionStore(path: '${temp.path}/session.json'),
      keybindingsStore: KeybindingsStore(path: '${temp.path}/keys.json'),
      onCommandServiceReady: (value) => commands = value,
    )));
    await tester.pump(const Duration(milliseconds: 600));
    final focus = tester
        .widget<Focus>(find.byKey(const ValueKey('explorer-tree-focus')))
        .focusNode!;
    expect(commands!.isEnabled('list.find'), isFalse);
    focus.requestFocus();
    await tester.pump();
    expect(commands!.isEnabled('list.find'), isTrue);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('tree-find-input')), findsOneWidget);
    expect(explorerFileNode(file.path), findsNothing);
    await tester.enterText(
        find.byKey(const ValueKey('tree-find-input')), 'mrs');
    await tester.tap(find.byKey(const ValueKey('tree-find-filter')));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
      if (explorerFileNode(file.path).evaluate().isNotEmpty) break;
    }
    expect(explorerFileNode(file.path), findsOneWidget);
    expect(explorerFileNode(nested.path), findsOneWidget);
    expect(explorerFileNode(alpha.path), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tree-find-input')));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(focus.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tree-find-fuzzy')));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(find.text('没有结果'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tree-find-input')));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const ValueKey('tree-find-input')), findsNothing);
    expect(explorerFileNode(alpha.path), findsOneWidget);
    expect(explorerFileNode(file.path), findsNothing);
    expect(focus.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN, character: 'n');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(explorerFileNode(file.path), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(explorerFileNode(file.path), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pump();
    await tester.pump();
    final input =
        tester.widget<TextField>(find.byKey(const ValueKey('tree-find-input')));
    expect(input.controller!.text, 'mrs');
    expect(input.controller!.selection,
        const TextSelection(baseOffset: 0, extentOffset: 3));
    expect(file.readAsStringSync(), '😀\r\n');
  });
}
