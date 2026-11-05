import 'dart:io';
import 'dart:convert';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pressCopyLine(
  WidgetTester tester,
  TargetPlatform platform, {
  required bool down,
}) async {
  final linux = platform == TargetPlatform.linux;
  if (linux) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(
    down ? LogicalKeyboardKey.arrowDown : LogicalKeyboardKey.arrowUp,
  );
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  if (linux) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
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

void main() {
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    testWidgets('$platform copies lines through Rust and saves the source',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(1200, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final temp = Directory.systemTemp.createTempSync('alula-line-copy');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });
      final workspace = Directory('${temp.path}/workspace')..createSync();
      const source = 'fn main() { println!("linux-save-ok"); }\n'
          '// 💻 target\n'
          'fn tail() {}';
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

      // Copy Line Down inserts a copy before the source line and keeps the
      // caret attached to the original line.
      controller.selection = TextSelection.collapsed(
        offset: source.indexOf('target') + 2,
      );
      await tester.pump();
      await _pressCopyLine(tester, platform, down: true);
      const afterCopyDown = 'fn main() { println!("linux-save-ok"); }\n'
          '// 💻 target\n'
          '// 💻 target\n'
          'fn tail() {}';
      expect(controller.text, afterCopyDown);
      expect(controller.selection.extentOffset,
          source.indexOf('target') + 2 + '// 💻 target\n'.length);
      views = tester.widgetList<RustTextInputField>(fields).toList();
      expect(views.first.inputWindow.document.resync().content, afterCopyDown);
      expect(views.last.inputWindow.document.resync().content, afterCopyDown);
      await _pressHistory(tester, platform, redo: false);
      expect(controller.text, source);
      await _pressHistory(tester, platform, redo: true);
      expect(controller.text, afterCopyDown);

      // A selection that ends at column one on the following row copies only
      // the preceding selected row, matching the Code-OSS line range rule.
      final targetStart = controller.text.lastIndexOf('// 💻 target');
      final tailLineStart = controller.text.indexOf('fn tail');
      controller.selection = TextSelection(
        baseOffset: targetStart,
        extentOffset: tailLineStart,
      );
      await tester.pump();
      await _pressCopyLine(tester, platform, down: true);
      const afterColumnOneRange = 'fn main() { println!("linux-save-ok"); }\n'
          '// 💻 target\n'
          '// 💻 target\n'
          '// 💻 target\n'
          'fn tail() {}';
      expect(controller.text, afterColumnOneRange);
      await _pressHistory(tester, platform, redo: false);
      expect(controller.text, afterCopyDown);
      await _pressHistory(tester, platform, redo: true);
      expect(controller.text, afterColumnOneRange);
      await _pressHistory(tester, platform, redo: false);
      expect(controller.text, afterCopyDown);

      // Copy Line Up inserts a copy after the selected source line.
      controller.selection = TextSelection.collapsed(
        offset: controller.text.lastIndexOf('fn tail') + 4,
      );
      await tester.pump();
      await _pressCopyLine(tester, platform, down: false);
      const afterCopyUp = 'fn main() { println!("linux-save-ok"); }\n'
          '// 💻 target\n'
          '// 💻 target\n'
          'fn tail() {}\n'
          'fn tail() {}';
      expect(controller.text, afterCopyUp);
      views = tester.widgetList<RustTextInputField>(fields).toList();
      expect(views.last.inputWindow.document.resync().content, afterCopyUp);

      // Two occurrences on adjacent rows are copied in one Rust transaction.
      final tailStart = controller.text.indexOf('fn tail');
      controller.selection = TextSelection(
        baseOffset: tailStart,
        extentOffset: tailStart + 'fn tail'.length,
      );
      await tester.pump();
      await _pressSelectNextOccurrence(tester, platform);
      views = tester.widgetList<RustTextInputField>(fields).toList();
      expect(views.first.additionalSelections, hasLength(1));
      await _pressCopyLine(tester, platform, down: true);
      const saved = 'fn main() { println!("linux-save-ok"); }\n'
          '// 💻 target\n'
          '// 💻 target\n'
          'fn tail() {}\n'
          'fn tail() {}\n'
          'fn tail() {}\n'
          'fn tail() {}';
      expect(controller.text, saved);
      views = tester.widgetList<RustTextInputField>(fields).toList();
      expect(views.last.inputWindow.document.resync().content, saved);
      await _pressHistory(tester, platform, redo: false);
      expect(controller.text, afterCopyUp);
      await _pressHistory(tester, platform, redo: true);
      expect(controller.text, saved);

      // Save through the already supported Ctrl+S command; this fixture checks
      // file-format preservation, not the separate platform save shortcut.
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
      expect(views.first.inputWindow.document.resync().content, saved);
      expect(views.last.inputWindow.document.resync().content, saved);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
