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
    expect(find.byKey(const ValueKey('qi-separator-function (1)')),
        findsOneWidget);
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

  testWidgets('Document symbols rank fuzzy results and group each kind once',
      (tester) async {
    final temp =
        Directory.systemTemp.createTempSync('alula-document-symbol-kinds');
    const text = 'fn root_fn() {}\n'
        'mod outer_a {\n  fn nested_a() {}\n  struct Packet;\n}\n'
        'mod outer_b {\n  fn nested_b() {}\n}\nfn n_branch() {}\n';
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
    final editor = find.byType(RustTextInputField);
    await tester.tap(editor);
    await tester.pump();
    RustTextInputField active() => tester.widget<RustTextInputField>(editor);
    final original = active().inputWindow.initialValue.selection;
    final opening = commands.execute('workbench.action.gotoSymbol');
    await tester.pumpAndSettle();
    final panel = find.byKey(const ValueKey('quick-input'));
    final input = find.descendant(of: panel, matching: find.byType(TextField));
    Finder row(String name) => find.byKey(ValueKey('qi-$name'));
    double y(String name) => tester.getTopLeft(row(name)).dy;
    List<String?> marks(String name) {
      final label = tester.widget<Text>(find.descendant(
        of: row(name),
        matching: find.byWidgetPredicate(
            (w) => w is Text && (w.data ?? w.textSpan?.toPlainText()) == name),
      ));
      final spans = (label.textSpan as TextSpan?)?.children ?? const [];
      return [
        for (final span in spans.whereType<TextSpan>())
          if (span.style?.fontWeight == FontWeight.bold) span.text,
      ];
    }

    Future<void> query(String value) async {
      await tester.enterText(input, value);
      await tester.pumpAndSettle();
    }

    await query('@:');
    expect(row('separator-function'), findsNothing);
    for (final name in [
      'separator-function (4)',
      'root_fn',
      'nested_a',
      'nested_b',
      'n_branch',
      'separator-mod (2)',
      'outer_a',
      'outer_b',
      'separator-struct (1)',
      'Packet',
    ]) {
      expect(row(name), findsOneWidget);
    }
    expect(y('separator-function (4)'), lessThan(y('root_fn')));
    expect(y('root_fn'), lessThan(y('nested_a')));
    expect(y('nested_a'), lessThan(y('nested_b')));
    expect(y('nested_b'), lessThan(y('n_branch')));
    expect(y('n_branch'), lessThan(y('separator-mod (2)')));
    expect(y('outer_b'), lessThan(y('separator-struct (1)')));

    await query('@n_b');
    expect(row('separator-符号 (2)'), findsOneWidget);
    expect(y('n_branch'), lessThan(y('nested_b')));
    expect(marks('n_branch'), ['n_b']);
    expect(marks('nested_b'), ['n', '_b']);

    await query('@ NB');
    expect(row('separator-符号 (2)'), findsOneWidget);
    expect(y('n_branch'), lessThan(y('nested_b')));

    await query('@:nest');
    expect(row('separator-function (2)'), findsOneWidget);
    expect(row('separator-mod (2)'), findsNothing);
    expect(y('nested_a'), lessThan(y('nested_b')));
    expect(marks('nested_a'), ['nest']);
    expect(marks('nested_b'), ['nest']);

    await query('@:nested_b');
    expect(row('separator-function (1)'), findsOneWidget);
    expect(row('separator-mod (1)'), findsNothing);
    expect(row('separator-struct (1)'), findsNothing);
    expect(row('nested_a'), findsNothing);
    expect(active().inputWindow.initialValue.selection.extentOffset,
        text.indexOf('fn nested_b'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await opening, CommandExecutionStatus.executed);
    expect(panel, findsNothing);
    expect(active().inputWindow.initialValue.selection, original);
    expect(active().focusNode!.hasPrimaryFocus, isTrue);
    expect(file.readAsStringSync(), text);
  });

  testWidgets('Document symbols show total counts and distinct empty states',
      (tester) async {
    final temp =
        Directory.systemTemp.createTempSync('alula-document-symbol-empty');
    const content = 'fn alpha() {}\n\nfn zebra() {}\n';
    const emptyContent = '// No symbols 😀\n';
    final file = File('${temp.path}/main.rs')..writeAsStringSync(content);
    final empty = File('${temp.path}/empty.rs')
      ..writeAsStringSync(emptyContent);
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
              {'id': 96, 'path': empty.path},
            ],
          },
        ],
      });
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
    final editor = find.byType(RustTextInputField);
    final panel = find.byKey(const ValueKey('quick-input'));
    final input = find.descendant(of: panel, matching: find.byType(TextField));
    await tester.tap(editor);
    await tester.pump();
    final populated = commands.execute('workbench.action.gotoSymbol');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('qi-separator-符号 (2)')), findsOneWidget);
    await tester.enterText(input, '@zebra');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('qi-separator-符号 (1)')), findsOneWidget);
    expect(find.byKey(const ValueKey('qi-zebra')), findsOneWidget);
    await tester.enterText(input, '@:missing');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的文档符号。'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await populated, CommandExecutionStatus.executed);

    await tester.tap(find.byKey(const ValueKey('editor-tab-label-editor-96')));
    await tester.pumpAndSettle();
    final emptyPicker = commands.execute('workbench.action.gotoSymbol');
    await tester.pumpAndSettle();
    expect(find.text('当前编辑器没有符号。'), findsOneWidget);
    await tester.enterText(input, '@:');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的文档符号。'), findsOneWidget);
    await tester.enterText(input, '@');
    await tester.pumpAndSettle();
    expect(find.text('当前编辑器没有符号。'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await emptyPicker, CommandExecutionStatus.executed);
    expect(panel, findsNothing);
    expect(tester.widget<RustTextInputField>(editor).focusNode!.hasPrimaryFocus,
        isTrue);
    expect(file.readAsStringSync(), content);
    expect(empty.readAsStringSync(), emptyContent);
  });
}
