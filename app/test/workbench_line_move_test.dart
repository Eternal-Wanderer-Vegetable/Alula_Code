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

Future<void> _pressMoveLine(WidgetTester tester, {required bool down}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(
    down ? LogicalKeyboardKey.arrowDown : LogicalKeyboardKey.arrowUp,
  );
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  await tester.pump(const Duration(milliseconds: 80));
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
  await tester.pump(const Duration(milliseconds: 80));
}

Future<void> _pressSelectNextOccurrence(
  WidgetTester tester,
  TargetPlatform platform,
) async {
  final primary = platform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(primary);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
  await tester.sendKeyUpEvent(primary);
  await tester.pump(const Duration(milliseconds: 80));
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
    testWidgets(
      '$platform moves selected lines through Rust and saves source',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.view.physicalSize = const Size(1200, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final temp = Directory.systemTemp.createTempSync('alula-line-move');
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          if (temp.existsSync()) temp.deleteSync(recursive: true);
        });
        final workspace = Directory('${temp.path}/workspace')..createSync();
        const source =
            'fn main() { println!("linux-save-ok"); }\n'
            '// 💻 target\n'
            'fn tail() {}\n'
            'fn last() {}';
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
        final firstField = textFieldAt(0);
        await tester.tap(firstField);
        await tester.showKeyboard(firstField);
        final controller = tester.widget<TextField>(firstField).controller!;
        var views = tester.widgetList<RustTextInputField>(fields).toList();
        expect(
          views.first.inputWindow.document.id,
          views.last.inputWindow.document.id,
        );
        expect(controller.text, source);

        final targetOffset = source.indexOf('target') + 2;
        controller.selection = TextSelection.collapsed(offset: targetOffset);
        await tester.pump();
        await _pressMoveLine(tester, down: true);
        const afterMoveDown =
            'fn main() { println!("linux-save-ok"); }\n'
            'fn tail() {}\n'
            '// 💻 target\n'
            'fn last() {}';
        expect(controller.text, afterMoveDown);
        expect(
          controller.selection.extentOffset,
          targetOffset + 'fn tail() {}\n'.length,
        );
        views = tester.widgetList<RustTextInputField>(fields).toList();
        expect(
          views.first.inputWindow.document.resync().content,
          afterMoveDown,
        );
        expect(views.last.inputWindow.document.resync().content, afterMoveDown);
        await _pressHistory(tester, platform, redo: false);
        expect(controller.text, source);
        await _pressHistory(tester, platform, redo: true);
        expect(controller.text, afterMoveDown);

        // Move the same line back up, then move a full-line selection whose end
        // is at column one on the next row. The exclusive end stays after the
        // moved line, matching MoveLinesCommand's tracked selection behavior.
        await _pressMoveLine(tester, down: false);
        expect(controller.text, source);
        final targetStart = source.indexOf('// 💻 target');
        final tailStart = source.indexOf('fn tail');
        controller.selection = TextSelection(
          baseOffset: targetStart,
          extentOffset: tailStart,
        );
        await tester.pump();
        await _pressMoveLine(tester, down: true);
        expect(controller.text, afterMoveDown);
        expect(controller.selection.start, tailStart);
        expect(controller.selection.end, afterMoveDown.indexOf('fn last'));

        await _pressSave(tester);
        expect(file.readAsBytesSync(), [
          0xef,
          0xbb,
          0xbf,
          ...utf8.encode(afterMoveDown.replaceAll('\n', '\r\n')),
        ]);
        views = tester.widgetList<RustTextInputField>(fields).toList();
        expect(views.last.inputWindow.document.resync().content, afterMoveDown);

        await _pressHistory(tester, platform, redo: false);
        expect(controller.text, source);
        await _pressHistory(tester, platform, redo: true);
        expect(controller.text, afterMoveDown);

        // Moving the first line up and the final line down are boundary no-ops.
        controller.selection = const TextSelection.collapsed(offset: 1);
        await tester.pump();
        await _pressMoveLine(tester, down: false);
        expect(controller.text, afterMoveDown);
        controller.selection = const TextSelection.collapsed(
          offset: afterMoveDown.length,
        );
        await tester.pump();
        await _pressMoveLine(tester, down: true);
        expect(controller.text, afterMoveDown);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    testWidgets('$platform moves an empty line with its adjacent row', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(1000, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final temp = Directory.systemTemp.createTempSync('alula-empty-line-move');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });
      final workspace = Directory('${temp.path}/workspace')..createSync();
      const source = 'alpha\n\nbeta';
      File('${workspace.path}/main.rs').writeAsStringSync(source);
      final base = temp.path.replaceAll(r'\', '/');
      await tester.pumpWidget(
        AlulaApp(
          autoFolder: workspace.path,
          layoutStore: LayoutStore(path: '$base/layout.json'),
          sessionStore: SessionStore(path: '$base/session.json'),
          keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('main.rs').first);
      await tester.pump(const Duration(milliseconds: 250));
      final field = find.descendant(
        of: find.byType(RustTextInputField).first,
        matching: find.byType(TextField),
      );
      await tester.tap(field);
      await tester.showKeyboard(field);
      final controller = tester.widget<TextField>(field).controller!;

      controller.selection = const TextSelection.collapsed(
        offset: 'alpha\n'.length,
      );
      await tester.pump();
      await _pressMoveLine(tester, down: true);
      expect(controller.text, 'alpha\nbeta\n');
      expect(controller.selection.extentOffset, controller.text.length);

      await _pressMoveLine(tester, down: false);
      expect(controller.text, 'alpha\n\nbeta');
      expect(controller.selection.extentOffset, 'alpha\n'.length);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    testWidgets('$platform keeps both occurrence selections with moved text', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(1000, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final temp = Directory.systemTemp.createTempSync('alula-multi-line-move');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });
      final workspace = Directory('${temp.path}/workspace')..createSync();
      const source = 'line a\nline b\nline c';
      File('${workspace.path}/main.rs').writeAsStringSync(source);
      final base = temp.path.replaceAll(r'\', '/');
      await tester.pumpWidget(
        AlulaApp(
          autoFolder: workspace.path,
          layoutStore: LayoutStore(path: '$base/layout.json'),
          sessionStore: SessionStore(path: '$base/session.json'),
          keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('main.rs').first);
      await tester.pump(const Duration(milliseconds: 250));
      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      await tester.showKeyboard(editor);
      await tester.pump();
      final controller = tester.widget<TextField>(editor).controller!;
      final firstMatch = source.indexOf('line b');
      controller.selection = TextSelection(
        baseOffset: firstMatch,
        extentOffset: firstMatch + 'line'.length,
      );
      await tester.pump();
      await _pressSelectNextOccurrence(tester, platform);

      var field = tester.widget<RustTextInputField>(
        find.byType(RustTextInputField),
      );
      expect(field.additionalSelections, const [
        TextSelection(baseOffset: 14, extentOffset: 18),
      ]);
      await _pressMoveLine(tester, down: true);
      expect(controller.text, 'line a\nline c\nline b');
      expect(
        controller.selection,
        const TextSelection(baseOffset: 14, extentOffset: 18),
      );
      field = tester.widget<RustTextInputField>(
        find.byType(RustTextInputField),
      );
      expect(field.additionalSelections, const [
        TextSelection(baseOffset: 7, extentOffset: 11),
      ]);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
