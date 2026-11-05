import 'dart:convert';
import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pressComment(WidgetTester tester, TargetPlatform platform) async {
  final primary = platform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(primary);
  await tester.sendKeyEvent(LogicalKeyboardKey.slash);
  await tester.sendKeyUpEvent(primary);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _pressHistory(
  WidgetTester tester,
  TargetPlatform platform, {
  required bool redo,
}) async {
  final primary = platform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(primary);
  if (redo) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
  if (redo) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(primary);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _pressSave(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    testWidgets('$platform toggles Rust line comments through Rust and saves',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(1200, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final temp = Directory.systemTemp.createTempSync('alula-line-comment');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });
      final workspace = Directory('${temp.path}/workspace')..createSync();
      const source = 'fn main() { println!("linux-save-ok"); }\nfn tail() {}';
      final file = File('${workspace.path}/main.rs')
        ..writeAsBytesSync([
          0xef,
          0xbb,
          0xbf,
          ...utf8.encode(source.replaceAll('\n', '\r\n')),
        ]);
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
      await tester.tap(find.byTooltip('拆分编辑器').first);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('main.rs').first);
      await tester.pump(const Duration(milliseconds: 300));

      final fields = find.byType(RustTextInputField);
      expect(fields, findsNWidgets(2));
      Finder textFieldAt(int index) => find.descendant(
            of: fields.at(index),
            matching: find.byType(TextField),
          );
      final firstField = textFieldAt(0);
      await tester.tap(firstField);
      await tester.showKeyboard(firstField);
      final first = tester.widget<TextField>(firstField).controller!;
      final second = tester.widget<TextField>(textFieldAt(1)).controller!;
      expect(first.text, source);
      expect(second.text, source);

      first.selection = const TextSelection.collapsed(offset: 3);
      await tester.pump();
      await _pressComment(tester, platform);
      const commented =
          '// fn main() { println!("linux-save-ok"); }\nfn tail() {}';
      expect(first.text, commented);
      expect(second.text, commented);
      expect(first.selection.extentOffset, 6);
      await _pressSave(tester);
      expect(
        file.readAsBytesSync(),
        [
          0xef,
          0xbb,
          0xbf,
          ...utf8.encode(commented.replaceAll('\n', '\r\n')),
        ],
      );

      await _pressComment(tester, platform);
      expect(first.text, source);
      await _pressHistory(tester, platform, redo: false);
      expect(first.text, commented);
      await _pressHistory(tester, platform, redo: true);
      expect(first.text, source);
      await _pressSave(tester);
      expect(
        file.readAsBytesSync(),
        [
          0xef,
          0xbb,
          0xbf,
          ...utf8.encode(source.replaceAll('\n', '\r\n')),
        ],
      );
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('Python uses # and plaintext remains unchanged', (tester) async {
    tester.view.physicalSize = const Size(1200, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final temp =
        Directory.systemTemp.createTempSync('alula-line-comment-langs');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    const python = 'print("hello")';
    File('${workspace.path}/main.py').writeAsStringSync(python);
    const plain = 'plain text';
    File('${workspace.path}/notes.txt').writeAsStringSync(plain);
    final base = temp.path.replaceAll(r'\', '/');

    await tester.pumpWidget(AlulaApp(
      autoFolder: workspace.path,
      layoutStore: LayoutStore(path: '$base/layout.json'),
      sessionStore: SessionStore(path: '$base/session.json'),
      keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('main.py').first);
    await tester.pump(const Duration(milliseconds: 300));
    final field = find.descendant(
      of: find.byType(RustTextInputField),
      matching: find.byType(TextField),
    );
    await tester.tap(field);
    await tester.showKeyboard(field);
    final controller = tester.widget<TextField>(field).controller!;
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();
    await _pressComment(tester, TargetPlatform.linux);
    expect(controller.text, '# print("hello")');

    await tester.tap(find.text('notes.txt').first);
    await tester.pump(const Duration(milliseconds: 300));
    final plainField = find.descendant(
      of: find.byType(RustTextInputField),
      matching: find.byType(TextField),
    );
    final plainController = tester.widget<TextField>(plainField).controller!;
    plainController.selection = const TextSelection.collapsed(offset: 0);
    await tester.tap(plainField);
    await tester.showKeyboard(plainField);
    await _pressComment(tester, TargetPlatform.linux);
    expect(plainController.text, plain);
    expect(find.text('当前语言没有配置行注释符'), findsOneWidget);
  });
}
