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

Future<void> _invokeRemoveDuplicates(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump(const Duration(milliseconds: 100));
  final palette = find.byType(TextField).last;
  await tester.enterText(palette, '删除重复行');
  await tester.pump(const Duration(milliseconds: 100));
  final command = find.text('编辑器: 删除重复行');
  expect(command, findsOneWidget);
  await tester.tap(command);
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
    testWidgets('$platform removes exact duplicate lines through Rust', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(1200, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final temp = Directory.systemTemp.createTempSync(
        'alula-remove-duplicates',
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });
      final workspace = Directory('${temp.path}/workspace')..createSync();
      const source =
          'keep\ndup\ndup\nCase\ncase\n spaced \n spaced \n\n\n🌱 seed\n🌱 seed';
      const after = 'keep\ndup\nCase\ncase\n spaced \n\n🌱 seed';
      final file = File('${workspace.path}/sample.txt')
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
      await tester.tap(find.text('sample.txt').first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('拆分编辑器').first);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('sample.txt').first);
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
      final controller = tester.widget<TextField>(firstField).controller!;
      expect(controller.text, source);
      controller.selection = TextSelection.collapsed(
        offset: source.indexOf('Case') + 2,
      );
      await tester.pump();

      await _invokeRemoveDuplicates(tester);
      expect(controller.text, after);
      expect(
        controller.selection,
        TextSelection.collapsed(offset: after.indexOf('Case') + 2),
      );
      var views = tester.widgetList<RustTextInputField>(fields).toList();
      expect(views.first.inputWindow.document.resync().content, after);
      expect(views.last.inputWindow.document.resync().content, after);

      await _pressHistory(tester, platform, redo: false);
      expect(controller.text, source);
      await _pressHistory(tester, platform, redo: true);
      expect(controller.text, after);
      await _pressSave(tester);
      expect(file.readAsBytesSync(), [
        0xef,
        0xbb,
        0xbf,
        ...utf8.encode(after.replaceAll('\n', '\r\n')),
      ]);
      views = tester.widgetList<RustTextInputField>(fields).toList();
      expect(views.first.inputWindow.document.resync().content, after);
      expect(views.last.inputWindow.document.resync().content, after);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    testWidgets(
      '$platform deduplicates whole selected rows including column one',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final temp = Directory.systemTemp.createTempSync('alula-dedupe-range');
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          if (temp.existsSync()) temp.deleteSync(recursive: true);
        });
        final workspace = Directory('${temp.path}/workspace')..createSync();
        const source = 'head\nbeta\nbeta\ntail\nbeta';
        const after = 'head\nbeta\ntail\nbeta';
        File('${workspace.path}/sample.txt').writeAsStringSync(source);
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
        await tester.tap(find.text('sample.txt').first);
        await tester.pump(const Duration(milliseconds: 300));

        final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
        await tester.showKeyboard(editor);
        await tester.pump();
        final controller = tester.widget<TextField>(editor).controller!;
        final start = source.indexOf('beta');
        final end = source.indexOf('tail');
        controller.selection = TextSelection(
          baseOffset: start,
          extentOffset: end,
        );
        await tester.pump();

        await _invokeRemoveDuplicates(tester);
        expect(controller.text, after);
        expect(
          controller.selection,
          TextSelection(baseOffset: after.indexOf('beta'), extentOffset: 14),
        );
        await _pressHistory(tester, platform, redo: false);
        expect(controller.text, source);
        await _pressHistory(tester, platform, redo: true);
        expect(controller.text, after);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}
