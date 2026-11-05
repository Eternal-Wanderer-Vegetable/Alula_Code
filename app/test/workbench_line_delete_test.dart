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

Future<void> _pressPrimaryCommand(
  WidgetTester tester,
  TargetPlatform platform,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  final primary = platform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(primary);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(primary);
}

void main() {
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    testWidgets('$platform deletes selected lines through Rust',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(1200, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final temp = Directory.systemTemp.createTempSync('alula-line-delete');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });
      final workspace = Directory('${temp.path}/workspace')..createSync();
      const source = 'fn main() { println!("linux-save-ok"); }\n'
          '// 💻 line to delete\n'
          'fn duplicate() {}\n'
          'fn duplicate() {}\n'
          'fn tail() {}\n';
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
      final controller = tester.widget<TextField>(firstField).controller!;
      var views = tester.widgetList<RustTextInputField>(fields).toList();
      expect(views.first.inputWindow.document.id,
          views.last.inputWindow.document.id);
      expect(controller.text, source);

      // Deleting the first line leaves the next line at document start.
      controller.selection = const TextSelection.collapsed(offset: 8);
      await tester.pump();
      await _pressPrimaryCommand(
        tester,
        platform,
        LogicalKeyboardKey.keyK,
        shift: true,
      );
      await tester.pump(const Duration(milliseconds: 80));
      const withoutFirstLine = '// 💻 line to delete\n'
          'fn duplicate() {}\n'
          'fn duplicate() {}\n'
          'fn tail() {}\n';
      expect(controller.text, withoutFirstLine);
      views = tester.widgetList<RustTextInputField>(fields).toList();
      expect(
          views.first.inputWindow.document.resync().content, withoutFirstLine);
      expect(
          views.last.inputWindow.document.resync().content, withoutFirstLine);
      await _pressPrimaryCommand(tester, platform, LogicalKeyboardKey.keyZ);
      await tester.pump(const Duration(milliseconds: 80));
      expect(controller.text, source);
      await _pressPrimaryCommand(
        tester,
        platform,
        LogicalKeyboardKey.keyZ,
        shift: true,
      );
      await tester.pump(const Duration(milliseconds: 80));
      expect(controller.text, withoutFirstLine);

      // The line after the first is an emoji comment. Its UTF-16 offsets do
      // not affect the Rust-resolved line start or the following code row.
      controller.selection = TextSelection.collapsed(
        offset: withoutFirstLine.indexOf('💻'),
      );
      await tester.pump();
      await _pressPrimaryCommand(
        tester,
        platform,
        LogicalKeyboardKey.keyK,
        shift: true,
      );
      await tester.pump(const Duration(milliseconds: 80));
      const withoutEmojiLine = 'fn duplicate() {}\n'
          'fn duplicate() {}\n'
          'fn tail() {}\n';
      expect(controller.text, withoutEmojiLine);
      await _pressPrimaryCommand(tester, platform, LogicalKeyboardKey.keyZ);
      await tester.pump(const Duration(milliseconds: 80));
      expect(controller.text, withoutFirstLine);
      await _pressPrimaryCommand(
        tester,
        platform,
        LogicalKeyboardKey.keyZ,
        shift: true,
      );
      await tester.pump(const Duration(milliseconds: 80));
      expect(controller.text, withoutEmojiLine);

      // Ctrl/Cmd+D creates two carets. Adjacent selected rows are deleted in
      // one text transaction and the tail row remains intact.
      final duplicateStart =
          withoutEmojiLine.indexOf('fn duplicate') + 'fn '.length;
      controller.selection = TextSelection(
        baseOffset: duplicateStart,
        extentOffset: duplicateStart + 'duplicate'.length,
      );
      await tester.pump();
      await _pressPrimaryCommand(tester, platform, LogicalKeyboardKey.keyD);
      await tester.pump(const Duration(milliseconds: 80));
      views = tester.widgetList<RustTextInputField>(fields).toList();
      expect(views.first.additionalSelections, hasLength(1));
      await _pressPrimaryCommand(
        tester,
        platform,
        LogicalKeyboardKey.keyK,
        shift: true,
      );
      await tester.pump(const Duration(milliseconds: 80));
      const withoutDuplicates = 'fn tail() {}\n';
      expect(controller.text, withoutDuplicates);
      views = tester.widgetList<RustTextInputField>(fields).toList();
      expect(
          views.last.inputWindow.document.resync().content, withoutDuplicates);

      // Undo/redo covers the merged multi-line deletion as a single command.
      await _pressPrimaryCommand(tester, platform, LogicalKeyboardKey.keyZ);
      await tester.pump(const Duration(milliseconds: 80));
      expect(controller.text, withoutEmojiLine);
      await _pressPrimaryCommand(
        tester,
        platform,
        LogicalKeyboardKey.keyZ,
        shift: true,
      );
      await tester.pump(const Duration(milliseconds: 80));
      expect(controller.text, withoutDuplicates);

      // Deleting the final empty row removes the preceding line separator,
      // leaving the last non-empty source line unchanged.
      controller.selection =
          TextSelection.collapsed(offset: controller.text.length);
      await tester.pump();
      await _pressPrimaryCommand(
        tester,
        platform,
        LogicalKeyboardKey.keyK,
        shift: true,
      );
      await tester.pump(const Duration(milliseconds: 80));
      const saved = 'fn tail() {}';
      expect(controller.text, saved);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 120));
      expect(file.readAsBytesSync(), [
        0xef,
        0xbb,
        0xbf,
        ...utf8.encode(saved.replaceAll('\n', '\r\n')),
      ]);
      views = tester.widgetList<RustTextInputField>(fields).toList();
      expect(views.first.inputWindow.document.resync().content, saved);
      expect(views.last.inputWindow.document.resync().content, saved);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
