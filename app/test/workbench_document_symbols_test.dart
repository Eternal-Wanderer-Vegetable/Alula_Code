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
      'symbol picker previews, cancels, groups and accepts Rust symbols',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-document-symbols');
    const text = 'fn alpha() {}\n\nfn zebra() {}\n';
    final file = File('${temp.path}/main.rs')..writeAsStringSync(text);
    final session = SessionStore(path: '${temp.path}/session.json')
      ..save({
        'v': 1,
        'focused': 'editor',
        'workspace': temp.path,
        'groups': [
          {
            'region': 'editor',
            'active': 95,
            'docs': [
              {'id': 95, 'path': file.path}
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
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 4);
    await tester.pump();
    final original = controller.selection;
    final opening = commands!.execute('workbench.action.gotoSymbol');
    await tester.pump(const Duration(milliseconds: 120));
    var input = find.descendant(
        of: find.byKey(const ValueKey('quick-input')),
        matching: find.byType(TextField));
    await tester.enterText(input, '@zebra');
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('qi-zebra')), findsOneWidget);
    expect(controller.selection.extentOffset, text.indexOf('fn zebra'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await opening;
    expect(controller.selection, original);
    final accepting = commands!.execute('workbench.action.gotoSymbol');
    await tester.pump(const Duration(milliseconds: 120));
    input = find.descendant(
        of: find.byKey(const ValueKey('quick-input')),
        matching: find.byType(TextField));
    await tester.enterText(input, '@:zebra');
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('qi-separator-function')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await accepting;
    expect(controller.selection.extentOffset, text.indexOf('fn zebra'));
    expect(controller.text, text);
    final side = commands!.execute('workbench.action.gotoSymbol');
    await tester.pump(const Duration(milliseconds: 120));
    input = find.descendant(
        of: find.byKey(const ValueKey('quick-input')),
        matching: find.byType(TextField));
    await tester.enterText(input, '@alpha');
    await tester.pump();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await side;
    expect(find.byKey(const ValueKey('wb-region-editor-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('rust-bounded-text-input')),
        findsNWidgets(2));
    final sourceField = find.descendant(
        of: find.byKey(const ValueKey('wb-region-editor')),
        matching: find.byKey(const ValueKey('rust-bounded-text-input')));
    final targetField = find.descendant(
        of: find.byKey(const ValueKey('wb-region-editor-2')),
        matching: find.byKey(const ValueKey('rust-bounded-text-input')));
    expect(
        tester
            .widget<TextField>(sourceField)
            .controller!
            .selection
            .extentOffset,
        text.indexOf('fn zebra'));
    expect(
        tester
            .widget<TextField>(targetField)
            .controller!
            .selection
            .extentOffset,
        text.indexOf('fn alpha'));
    expect(file.readAsStringSync(), text);
  });

  testWidgets('Document symbol picker guides an empty workbench',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-symbol-guidance');
    final file = File('${temp.path}/main.rs')
      ..writeAsStringSync('fn alpha() {}\n');
    final session = SessionStore(path: '${temp.path}/session.json')
      ..save({
        'v': 1,
        'focused': 'editor',
        'workspace': temp.path,
        'groups': [
          {
            'region': 'editor',
            'active': 95,
            'docs': [
              {'id': 95, 'path': file.path},
            ],
          },
        ],
      });
    final origin = FocusNode();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      origin.dispose();
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
            TextField(focusNode: origin),
          ],
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
    expect(editor, findsOneWidget);
    expect(
      await commands.execute('workbench.action.closeAllEditors'),
      CommandExecutionStatus.executed,
    );
    await tester.pumpAndSettle();
    expect(editor, findsNothing);
    origin.requestFocus();
    await tester.pump();
    expect(origin.hasPrimaryFocus, isTrue);

    final panel = find.byKey(const ValueKey('quick-input'));
    final input = find.descendant(of: panel, matching: find.byType(TextField));
    final guidance = find.text('先打开提供符号信息的文本编辑器，再转到符号。');
    final opening = commands.execute('workbench.action.gotoSymbol');
    await tester.pumpAndSettle();
    expect(guidance, findsOneWidget);
    expect(tester.widget<TextField>(input).controller!.text, '@');
    expect(tester.widget<TextField>(input).focusNode!.hasPrimaryFocus, isTrue);
    await tester.enterText(input, '@:alpha');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(guidance, findsOneWidget);
    expect(tester.widget<TextField>(input).controller!.text, '@:alpha');
    expect(editor, findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await opening, CommandExecutionStatus.executed);
    expect(panel, findsNothing);
    expect(origin.hasPrimaryFocus, isTrue);

    expect(await commands.execute('workbench.action.quickOpen'),
        CommandExecutionStatus.executed);
    await tester.pumpAndSettle();
    await tester.enterText(input, '@:beta');
    await tester.pumpAndSettle();
    expect(guidance, findsOneWidget);
    expect(tester.widget<TextField>(input).controller!.text, '@:beta');
    expect(tester.widget<TextField>(input).focusNode!.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(origin.hasPrimaryFocus, isTrue);
    expect(file.readAsStringSync(), 'fn alpha() {}\n');
  });

  testWidgets(
      'Document symbol side shortcuts retain the target and reuse the right view',
      (tester) async {
    final temp =
        Directory.systemTemp.createTempSync('alula-document-symbol-aside');
    const text = '// emoji 😀\nfn alpha() {}\n\nfn zebra() {}\n';
    final file = File('${temp.path}/main.rs')..writeAsStringSync(text);
    final session = SessionStore(path: '${temp.path}/session.json')
      ..save({
        'v': 1,
        'focused': 'editor',
        'workspace': temp.path,
        'groups': [
          {
            'region': 'editor',
            'active': 95,
            'preview': 95,
            'docs': [
              {'id': 95, 'path': file.path},
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
    Finder field(String region) => find.descendant(
          of: find.byKey(ValueKey('editor-body-drop-$region')),
          matching: find.byType(RustTextInputField),
        );
    RustTextInputField editor(String region) =>
        tester.widget<RustTextInputField>(field(region));
    TextSelection selection(String region) =>
        editor(region).inputWindow.initialValue.selection;
    Finder tab(String region) =>
        find.byKey(ValueKey('editor-tab-label-$region-95'));
    FontStyle? tabStyle(String region) =>
        tester.widget<Text>(tab(region)).style?.fontStyle;

    Future<void> aside(String symbol, LogicalKeyboardKey modifier) async {
      final position = text.indexOf('fn $symbol');
      final original = selection('editor');
      final opening = commands.execute('workbench.action.gotoSymbol');
      await tester.pumpAndSettle();
      await tester.enterText(input, '@:$symbol');
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('qi-$symbol')), findsOneWidget);
      expect(selection('editor').extentOffset, position);
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
      expect(await opening, CommandExecutionStatus.executed);
      expect(panel, findsNothing);
      expect(find.byType(RustTextInputField), findsNWidgets(2));
      expect(selection('editor'), original);
      expect(selection('editor-2').extentOffset, position);
      expect(editor('editor-2').focusNode!.hasPrimaryFocus, isTrue);
      expect(editor('editor-2').inputWindow.document,
          same(editor('editor').inputWindow.document));
      expect(tabStyle('editor'), FontStyle.italic);
      expect(tabStyle('editor-2'), isNot(FontStyle.italic));
    }

    await tester.tap(field('editor'));
    await tester.pump();
    await aside('zebra', LogicalKeyboardKey.altLeft);
    final right = editor('editor-2').focusNode;
    await tester.tap(tab('editor'));
    await tester.pumpAndSettle();
    expect(editor('editor').focusNode!.hasPrimaryFocus, isTrue);
    final platform = Theme.of(tester.element(field('editor'))).platform;
    await aside(
      'alpha',
      platform == TargetPlatform.macOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft,
    );
    expect(editor('editor-2').focusNode, same(right));
    expect(file.readAsStringSync(), text);
  },
      variant: const TargetPlatformVariant({
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.macOS,
      }));
}
