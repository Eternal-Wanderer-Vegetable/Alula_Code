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

Future<void> _pressTrim(WidgetTester tester, TargetPlatform platform) async {
  final primary = platform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(primary);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyUpEvent(primary);
  await tester.sendKeyDownEvent(primary);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
  await tester.sendKeyUpEvent(primary);
  await tester.pump(const Duration(milliseconds: 120));
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
    testWidgets('$platform trims Rust whitespace through Rust and saves',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(1200, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final temp = Directory.systemTemp.createTempSync('alula-trim-whitespace');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });
      final workspace = Directory('${temp.path}/workspace')..createSync();
      const source =
          'fn one() {}  \n \t\n\tfn two() {}\n// 💻 \t\n// keep\u00a0';
      const trimmed = 'fn one() {}\n\n\tfn two() {}\n// 💻\n// keep\u00a0';
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
      final cursorInTrimRange = source.indexOf('  \n') + 1;
      first.selection = TextSelection.collapsed(offset: cursorInTrimRange);
      await tester.pump();

      await _pressTrim(tester, platform);
      expect(first.text, trimmed);
      expect(second.text, trimmed);
      expect(first.selection.extentOffset, trimmed.indexOf('\n'));
      final views = tester.widgetList<RustTextInputField>(fields).toList();
      expect(views.first.inputWindow.document.resync().content, trimmed);
      expect(views.last.inputWindow.document.resync().content, trimmed);

      await _pressHistory(tester, platform, redo: false);
      expect(first.text, source);
      await _pressHistory(tester, platform, redo: true);
      expect(first.text, trimmed);
      await _pressSave(tester);
      expect(
        file.readAsBytesSync(),
        [
          0xef,
          0xbb,
          0xbf,
          ...utf8.encode(trimmed.replaceAll('\n', '\r\n')),
        ],
      );
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
