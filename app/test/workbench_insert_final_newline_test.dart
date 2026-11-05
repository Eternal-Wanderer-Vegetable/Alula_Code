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

Future<void> _invokeFinalNewlineCommand(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump(const Duration(milliseconds: 100));
  final palette = find.byType(TextField).last;
  await tester.enterText(palette, '插入末尾换行');
  await tester.pump(const Duration(milliseconds: 100));
  final command = find.text('编辑器: 插入末尾换行');
  expect(command, findsOneWidget);
  await tester.tap(command);
  await tester.pump(const Duration(milliseconds: 180));
}

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
  bool meta = false,
  bool shift = false,
}) async {
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump(const Duration(milliseconds: 120));
}

void main() {
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    testWidgets(
        '$platform inserts and saves a final newline across split views',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        tester.view.physicalSize = const Size(1200, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final temp = Directory.systemTemp.createTempSync('alula-final-newline');
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          if (temp.existsSync()) temp.deleteSync(recursive: true);
        });
        final workspace = Directory('${temp.path}/workspace')..createSync();
        const content = 'fn main() { println!("🌙"); }\n// eof';
        final file = File('${workspace.path}/main.rs')
          ..writeAsBytesSync([
            0xef,
            0xbb,
            0xbf,
            ...utf8.encode(content.replaceAll('\n', '\r\n')),
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
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byTooltip('拆分编辑器').first);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(find.text('main.rs').first);
        await tester.pump(const Duration(milliseconds: 250));

        final fields = find.byType(RustTextInputField);
        expect(fields, findsNWidgets(2));
        Finder textFieldAt(int index) => find.descendant(
              of: fields.at(index),
              matching: find.byType(TextField),
            );
        final firstField = textFieldAt(0);
        final secondField = textFieldAt(1);
        await tester.tap(firstField);
        await tester.showKeyboard(firstField);
        final first = tester.widget<TextField>(firstField).controller!;
        final second = tester.widget<TextField>(secondField).controller!;
        const eof = content.length;
        const preservedOffset = 5;
        first.selection =
            const TextSelection.collapsed(offset: preservedOffset);
        second.selection =
            const TextSelection.collapsed(offset: preservedOffset);
        await tester.pump();

        await _invokeFinalNewlineCommand(tester);
        expect(first.text, '$content\n');
        expect(second.text, '$content\n');
        expect(first.selection.extentOffset, preservedOffset);
        expect(second.selection.extentOffset, preservedOffset);

        await _press(
          tester,
          LogicalKeyboardKey.keyZ,
          control: platform != TargetPlatform.macOS,
          meta: platform == TargetPlatform.macOS,
        );
        expect(first.text, content);
        expect(second.text, content);
        first.selection = const TextSelection.collapsed(offset: eof);
        second.selection = const TextSelection.collapsed(offset: eof);
        await tester.pump();

        await _invokeFinalNewlineCommand(tester);
        expect(first.text, '$content\n');
        expect(second.text, '$content\n');
        expect(first.selection.extentOffset, eof + 1);
        expect(second.selection.extentOffset, eof + 1);

        await _press(
          tester,
          LogicalKeyboardKey.keyS,
          control: true,
        );
        expect(
          file.readAsBytesSync(),
          [
            0xef,
            0xbb,
            0xbf,
            ...utf8.encode('${content.replaceAll('\n', '\r\n')}\r\n'),
          ],
        );

        await _press(
          tester,
          LogicalKeyboardKey.keyZ,
          control: platform != TargetPlatform.macOS,
          meta: platform == TargetPlatform.macOS,
        );
        expect(first.text, content);
        expect(second.text, content);
        await _press(
          tester,
          LogicalKeyboardKey.keyZ,
          control: platform != TargetPlatform.macOS,
          meta: platform == TargetPlatform.macOS,
          shift: true,
        );
        expect(first.text, '$content\n');
        expect(second.text, '$content\n');

        // Code-OSS inserts another EOL at EOF even if one already exists.
        await _invokeFinalNewlineCommand(tester);
        expect(first.text, '$content\n\n');
        expect(second.text, '$content\n\n');
        await _press(
          tester,
          LogicalKeyboardKey.keyZ,
          control: platform != TargetPlatform.macOS,
          meta: platform == TargetPlatform.macOS,
        );
        expect(first.text, '$content\n');
        expect(second.text, '$content\n');
      } finally {
        debugDefaultTargetPlatformOverride = null;
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }

  testWidgets('an empty document accepts the final newline command',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final temp = Directory.systemTemp.createTempSync('alula-empty-final-eol');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });
      final workspace = Directory('${temp.path}/workspace')..createSync();
      final file = File('${workspace.path}/empty.txt')..createSync();
      final base = temp.path.replaceAll(r'\', '/');
      await tester.pumpWidget(AlulaApp(
        autoFolder: workspace.path,
        layoutStore: LayoutStore(path: '$base/layout.json'),
        sessionStore: SessionStore(path: '$base/session.json'),
        keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
      ));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('empty.txt').first);
      await tester.pump(const Duration(milliseconds: 250));
      final field = find.descendant(
        of: find.byType(RustTextInputField).first,
        matching: find.byType(TextField),
      );
      await tester.tap(field);
      await tester.showKeyboard(field);

      await _invokeFinalNewlineCommand(tester);
      expect(tester.widget<TextField>(field).controller!.text, '\n');
      await _press(tester, LogicalKeyboardKey.keyS, control: true);
      expect(file.readAsBytesSync(), [0x0a]);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
