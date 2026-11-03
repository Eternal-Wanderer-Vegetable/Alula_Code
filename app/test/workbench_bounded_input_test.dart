import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('find selection scope limits matches and replacement',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-find-selection');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    final workspace = Directory('${temp.path}/workspace')..createSync();
    File('${workspace.path}/notes.txt').writeAsStringSync('foo foo\nbar');
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

    tester
        .state<RustTextInputFieldState>(find.byType(RustTextInputField))
        .setSelection(const TextSelection(baseOffset: 0, extentOffset: 3));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 100));

    final findBar = find.byKey(const ValueKey('find-bar'));
    final fields =
        find.descendant(of: findBar, matching: find.byType(TextField));
    await tester.enterText(fields.first, 'foo');
    await tester.pump();
    expect(find.text('-/2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('find-in-selection')));
    await tester.pump();
    expect(find.text('-/1'), findsOneWidget);
    expect(
      tester
          .widget<RustTextInputField>(find.byType(RustTextInputField))
          .rangeDecorations
          .map((decoration) => (decoration.startUtf16, decoration.endUtf16))
          .toList(),
      [(0, 3)],
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 100));
    final replaceFields =
        find.descendant(of: findBar, matching: find.byType(TextField));
    await tester.enterText(replaceFields.at(1), 'X');
    await tester.tap(find.byTooltip('全部替换'));
    await tester.pump(const Duration(milliseconds: 100));

    final editor = tester.widget<RustTextInputField>(
      find.byType(RustTextInputField),
    );
    expect(editor.inputWindow.document.resync().content, 'X foo\nbar');
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('find-in-selection')))
          .isSelected,
      isFalse,
      reason: 'editing invalidates the captured version-bound scope',
    );
    expect(find.text('-/1'), findsOneWidget);
  });

  testWidgets('find whole-word toggle refreshes count and editor highlights',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-find-whole-word');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    final workspace = Directory('${temp.path}/workspace')..createSync();
    const source = '👨foo foo_bar foo-bar\r\nfoo';
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

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 100));
    final findBar = find.byKey(const ValueKey('find-bar'));
    await tester.enterText(
      find.descendant(of: findBar, matching: find.byType(TextField)).first,
      'foo',
    );
    await tester.pump();
    expect(find.text('-/4'), findsOneWidget);

    await tester.tap(find.byTooltip('全字匹配'));
    await tester.pump();
    expect(find.text('-/2'), findsOneWidget);
    final editor = tester.widget<RustTextInputField>(
      find.byType(RustTextInputField),
    );
    expect(
      editor.rangeDecorations
          .map((decoration) => (decoration.startUtf16, decoration.endUtf16))
          .toList(),
      [(14, 17), (22, 25)],
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 100));
    final fields =
        find.descendant(of: findBar, matching: find.byType(TextField));
    await tester.enterText(fields.at(1), 'X');
    await tester.tap(find.byTooltip('替换').first);
    await tester.pump();
    await tester.tap(find.byTooltip('替换').first);
    await tester.pump(const Duration(milliseconds: 100));
    final document = tester
        .widget<RustTextInputField>(find.byType(RustTextInputField))
        .inputWindow
        .document;
    expect(document.resync().content, '👨foo foo_bar X-bar\nfoo');
  });

  testWidgets('regex find runs asynchronously and rejects stale results',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-find-regex');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    final workspace = Directory('${temp.path}/workspace')..createSync();
    File('${workspace.path}/notes.txt').writeAsStringSync(
      'foo\nfoo-bar\nbar\nfoo',
    );
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
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 100));

    final findBar = find.byKey(const ValueKey('find-bar'));
    final query = find
        .descendant(
          of: findBar,
          matching: find.byType(TextField),
        )
        .first;
    await tester.enterText(query, '^foo');
    await tester.tap(find.byKey(const ValueKey('find-regex')));
    await tester.pump();
    await tester.enterText(query, r'^bar$');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    expect(find.text('-/1'), findsOneWidget);
    final editor = tester.widget<RustTextInputField>(
      find.byType(RustTextInputField),
    );
    expect(
      editor.rangeDecorations
          .map((decoration) => (decoration.startUtf16, decoration.endUtf16))
          .toList(),
      [(12, 15)],
      reason:
          r'the older ^foo result must not overwrite the latest ^bar$ query',
    );

    await tester.enterText(query, r'(?=a)');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(find.text('-/2'), findsOneWidget);
    await tester.tap(find.byTooltip('下一个匹配'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(find.text('1/2'), findsOneWidget);
    await tester.tap(find.byTooltip('下一个匹配'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(find.text('2/2'), findsOneWidget);
  });

  testWidgets('Workbench paints find hits as versioned Rust UTF-16 ranges',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-find-ranges');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    final workspace = Directory('${temp.path}/workspace')..createSync();
    const source = '👨 needle\nx needle';
    File('${workspace.path}/notes.txt').writeAsStringSync(source);
    File('${workspace.path}/other.txt').writeAsStringSync('needle');
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

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 100));
    final findBar = find.byKey(const ValueKey('find-bar'));
    expect(findBar, findsOneWidget);
    await tester.enterText(
      find.descendant(of: findBar, matching: find.byType(TextField)).first,
      'needle',
    );
    await tester.pump();

    final editor = tester.widget<RustTextInputField>(
      find.byType(RustTextInputField),
    );
    expect(
      editor.rangeDecorations
          .map((decoration) => (decoration.startUtf16, decoration.endUtf16))
          .toList(),
      [(3, 9), (12, 18)],
      reason: 'find ranges use document absolute UTF-16 offsets after emoji',
    );
    expect(
      editor.rangeDecorations.every(
        (decoration) =>
            decoration.documentVersion == editor.inputWindow.version,
      ),
      isTrue,
    );

    await tester.tap(find.text('other.txt').first);
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester
          .widget<RustTextInputField>(find.byType(RustTextInputField))
          .rangeDecorations,
      isEmpty,
      reason: 'find hits from another document must not leak into this editor',
    );
  });

  testWidgets('workbench recenters bounded input and saves the Rust edit',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-bounded-editor');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    final workspace = Directory('${temp.path}/workspace')..createSync();
    final source = 'a' * 50000;
    final file = File('${workspace.path}/large.txt')..writeAsStringSync(source);
    final base = temp.path.replaceAll(r'\', '/');
    await tester.pumpWidget(AlulaApp(
      autoFolder: workspace.path,
      layoutStore: LayoutStore(path: '$base/layout.json'),
      sessionStore: SessionStore(path: '$base/session.json'),
      keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('large.txt').first);
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('拆分编辑器').first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('large.txt').first);
    await tester.pump(const Duration(milliseconds: 300));

    final viewsFinder = find.byType(RustTextInputField);
    expect(viewsFinder, findsNWidgets(2));
    var views = tester.widgetList<RustTextInputField>(viewsFinder).toList();
    expect(views.map((view) => view.inputWindow.document.id).toSet(),
        hasLength(1));
    expect(identical(views[0].scrollController, views[1].scrollController),
        isFalse);

    final activeView = viewsFinder.last;
    final editor = find.descendant(
      of: activeView,
      matching: find.byKey(const ValueKey('rust-bounded-text-input')),
    );
    await tester.showKeyboard(editor);
    await tester.pump();
    var bounded = tester.widget<RustTextInputField>(activeView);
    var textField = tester.widget<TextField>(editor);
    final controller = textField.controller!;
    expect(controller.text.length, lessThan(source.length));

    controller.selection =
        TextSelection.collapsed(offset: controller.text.length);
    await tester.pump();
    await tester.pump();

    bounded = tester.widget<RustTextInputField>(activeView);
    textField = tester.widget<TextField>(editor);
    expect(bounded.inputWindow.startUtf16, greaterThan(0));
    final absoluteCaret = bounded.inputWindow.startUtf16 +
        textField.controller!.selection.extentOffset;
    expect(absoluteCaret, greaterThan(10000));

    final current = textField.controller!.value;
    final localCaret = current.selection.extentOffset;
    textField.controller!.value = current.copyWith(
      text: current.text.replaceRange(localCaret, localCaret, 'X'),
      selection: TextSelection.collapsed(offset: localCaret + 1),
      composing: TextRange.empty,
    );
    await tester.pump();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final expected = '${source.substring(0, absoluteCaret)}X'
        '${source.substring(absoluteCaret)}';
    expect(file.readAsStringSync(), expected);
    views = tester.widgetList<RustTextInputField>(viewsFinder).toList();
    expect(views.map((view) => view.inputWindow.document.id).toSet(),
        hasLength(1));
    expect(
      views.every(
          (view) => view.inputWindow.document.resync().content == expected),
      isTrue,
      reason: 'both views observe the saved Rust-authoritative long line',
    );
    expect(bounded.inputWindow.text.length, lessThan(20000));
  });
}
