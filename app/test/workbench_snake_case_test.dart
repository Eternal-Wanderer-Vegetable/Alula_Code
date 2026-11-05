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

Future<void> _invokeSnakeCase(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump(const Duration(milliseconds: 100));
  final palette = find.byType(TextField).last;
  await tester.enterText(palette, '蛇形命名');
  await tester.pump(const Duration(milliseconds: 100));
  final command = find.text('编辑器: 转换为蛇形命名');
  expect(command, findsOneWidget);
  await tester.tap(command);
  await tester.pump(const Duration(milliseconds: 150));
}

Future<void> _pressKey(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool redo = false,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (redo) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (redo) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    testWidgets('$platform snake-case command edits, syncs, saves and undoes', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(1200, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final temp = Directory.systemTemp.createTempSync('alula-snake-case');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });
      final workspace = Directory('${temp.path}/workspace')..createSync();
      const source =
          'fn main() { println!("linux-save-ok"); }\nfooBARBaz\nXMLHttpRequest';
      final file = File('${workspace.path}/main.rs')
        ..writeAsBytesSync([
          0xef,
          0xbb,
          0xbf,
          ...utf8.encode(source.replaceAll('\n', '\r\n')),
        ]);
      final base = temp.path.replaceAll(r'\', '/');
      await tester.pumpWidget(
        AlulaApp(
          autoFolder: workspace.path,
          layoutStore: LayoutStore(path: '$base/layout.json'),
          sessionStore: SessionStore(path: '$base/session.json'),
          keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
        ),
      );
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
      final primaryField = textFieldAt(0);
      await tester.tap(primaryField);
      await tester.showKeyboard(primaryField);
      var controller = tester.widget<TextField>(primaryField).controller!;
      expect(controller.text, source);

      final selectedStart = source.indexOf('fooBARBaz');
      controller.selection = TextSelection(
        baseOffset: selectedStart,
        extentOffset: selectedStart + 'fooBARBaz'.length,
      );
      await tester.pump();
      await _invokeSnakeCase(tester);
      controller = tester.widget<TextField>(primaryField).controller!;
      var transformed = source.replaceFirst('fooBARBaz', 'foo_bar_baz');
      expect(controller.text, transformed);
      expect(
        controller.selection.extentOffset - controller.selection.baseOffset,
        'foo_bar_baz'.length,
      );
      expect(
        tester.widget<TextField>(textFieldAt(1)).controller!.text,
        transformed,
      );

      await _pressKey(tester, LogicalKeyboardKey.keyS);
      expect(file.readAsBytesSync(), <int>[
        0xef,
        0xbb,
        0xbf,
        ...utf8.encode(transformed.replaceAll('\n', '\r\n')),
      ]);

      final caretOffset = transformed.indexOf('XMLHttpRequest') + 3;
      controller.selection = TextSelection.collapsed(offset: caretOffset);
      await tester.pump();
      await _invokeSnakeCase(tester);
      controller = tester.widget<TextField>(primaryField).controller!;
      transformed = transformed.replaceFirst(
        'XMLHttpRequest',
        'xml_http_request',
      );
      expect(controller.text, transformed);
      expect(
        controller.selection,
        TextSelection.collapsed(offset: caretOffset),
      );
      expect(
        tester.widget<TextField>(textFieldAt(1)).controller!.text,
        transformed,
      );

      await _pressKey(tester, LogicalKeyboardKey.keyZ);
      controller = tester.widget<TextField>(primaryField).controller!;
      expect(controller.text, source.replaceFirst('fooBARBaz', 'foo_bar_baz'));
      await _pressKey(tester, LogicalKeyboardKey.keyZ, redo: true);
      controller = tester.widget<TextField>(primaryField).controller!;
      expect(controller.text, transformed);
      await _pressKey(tester, LogicalKeyboardKey.keyS);
      expect(file.readAsBytesSync(), <int>[
        0xef,
        0xbb,
        0xbf,
        ...utf8.encode(transformed.replaceAll('\n', '\r\n')),
      ]);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
