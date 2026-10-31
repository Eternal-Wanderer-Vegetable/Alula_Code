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
  testWidgets('F12 goes to a same-file Rust definition and reports misses',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-nav');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) await temp.delete(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    const source =
        '\uFEFF// 🦊 navigation fixture\r\nfn target() {}\r\nfn 目标() {}\r\nfn f() {}\r\nfn main() {\r\n    target();\r\n    目标();\r\n    f();\r\n    missing();\r\n}\r\n';
    const normalizedSource =
        '// 🦊 navigation fixture\nfn target() {}\nfn 目标() {}\nfn f() {}\nfn main() {\n    target();\n    目标();\n    f();\n    missing();\n}\n';
    File('${workspace.path}/main.rs').writeAsStringSync(source);
    final base = temp.path.replaceAll(r'\', '/');

    await tester.pumpWidget(AlulaApp(
      autoFolder: workspace.path,
      layoutStore: LayoutStore(path: '$base/layout.json'),
      sessionStore: SessionStore(path: '$base/session.json'),
      keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('main.rs').first);
    await tester.pump(const Duration(milliseconds: 300));

    final editor = find.byType(RustTextInputField);
    expect(editor, findsOneWidget);
    final textFieldFinder = find.descendant(
      of: editor,
      matching: find.byType(TextField),
    );
    await tester.tap(textFieldFinder);
    await tester.pump();
    final controller = tester.widget<TextField>(textFieldFinder).controller!;
    final definitionOffset = normalizedSource.indexOf('target()');
    final unicodeDefinitionOffset = normalizedSource.indexOf('目标()');
    final oneLetterDefinitionOffset = normalizedSource.indexOf('f()');
    final callOffset = normalizedSource.indexOf(
      'target();',
      normalizedSource.indexOf('fn main'),
    );

    controller.selection = TextSelection.collapsed(offset: callOffset);
    await tester.pump();
    expect(
      controller.selection.extentOffset,
      callOffset,
      reason: 'the call-site caret must reach the editor before F12',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('跳转到 target'), findsOneWidget);
    final selectionAfterJump =
        tester.widget<TextField>(textFieldFinder).controller!.selection;
    expect(
      selectionAfterJump.extentOffset,
      definitionOffset,
      reason: 'F12 from the call site must select the local Rust definition',
    );

    final controllerAfterJump =
        tester.widget<TextField>(textFieldFinder).controller!;
    controllerAfterJump.selection = TextSelection.collapsed(
      offset: normalizedSource.indexOf(
        '目标();',
        normalizedSource.indexOf('fn main'),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('跳转到 目标'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(textFieldFinder)
          .controller!
          .selection
          .extentOffset,
      unicodeDefinitionOffset,
      reason: 'F12 must resolve a Rust identifier containing Unicode XID chars',
    );

    final controllerAfterUnicodeJump =
        tester.widget<TextField>(textFieldFinder).controller!;
    controllerAfterUnicodeJump.selection = TextSelection.collapsed(
      offset: normalizedSource.indexOf(
        'f();',
        normalizedSource.indexOf('fn main'),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('跳转到 f'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(textFieldFinder)
          .controller!
          .selection
          .extentOffset,
      oneLetterDefinitionOffset,
      reason: 'definition search must match the identifier boundary, not `fn`',
    );

    final controllerAfterOneLetterJump =
        tester.widget<TextField>(textFieldFinder).controller!;
    controllerAfterOneLetterJump.selection = TextSelection.collapsed(
      offset: normalizedSource.indexOf('missing()'),
    );
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 200));
    final quickInput = find.byKey(const ValueKey('quick-input'));
    await tester.enterText(
      find.descendant(of: quickInput, matching: find.byType(TextField)),
      '跳转定义',
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('qi-编辑器: 跳转定义')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('未找到「missing」的定义'), findsOneWidget);

    final controllerAfterMiss =
        tester.widget<TextField>(textFieldFinder).controller!;
    controllerAfterMiss.selection =
        const TextSelection.collapsed(offset: normalizedSource.length);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('光标不在符号上'), findsOneWidget);
  });
}
