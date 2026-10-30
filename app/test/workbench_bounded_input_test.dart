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

    final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
    await tester.showKeyboard(editor);
    await tester.pump();
    var bounded =
        tester.widget<RustTextInputField>(find.byType(RustTextInputField));
    var textField = tester.widget<TextField>(editor);
    final controller = textField.controller!;
    expect(controller.text.length, lessThan(source.length));

    controller.selection =
        TextSelection.collapsed(offset: controller.text.length);
    await tester.pump();
    await tester.pump();

    bounded =
        tester.widget<RustTextInputField>(find.byType(RustTextInputField));
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

    expect(
        file.readAsStringSync(),
        '${source.substring(0, absoluteCaret)}X'
        '${source.substring(absoluteCaret)}');
    expect(
      tester
          .widget<RustTextInputField>(find.byType(RustTextInputField))
          .inputWindow
          .text
          .length,
      lessThan(20000),
    );
  });
}
