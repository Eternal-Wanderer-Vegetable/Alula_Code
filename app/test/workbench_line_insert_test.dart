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

Future<void> _pressEnterCommand(
  WidgetTester tester,
  TargetPlatform platform, {
  required bool before,
}) async {
  final primary = platform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(primary);
  if (before) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  if (before) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(primary);
}

Future<void> _pressHistoryCommand(
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
}

void main() {
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    testWidgets('$platform inserts lines above and below through Rust',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(1200, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final temp = Directory.systemTemp.createTempSync('alula-line-insert');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });
      final workspace = Directory('${temp.path}/workspace')..createSync();
      const source = 'fn main() { println!("linux-save-ok"); }\nfn helper() {}';
      final file = File('${workspace.path}/main.rs')..writeAsStringSync(source);
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
      var firstController = tester.widget<TextField>(firstField).controller!;
      var views = tester.widgetList<RustTextInputField>(fields).toList();
      final documentId = views.first.inputWindow.document.id;
      expect(views.last.inputWindow.document.id, documentId);

      // Inserting above the first line creates an empty first line and keeps
      // the cursor attached to the original source line.
      firstController.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();
      await _pressEnterCommand(tester, platform, before: true);
      await tester.pump(const Duration(milliseconds: 80));
      expect(firstController.text, '\n$source');
      expect(firstController.selection.extentOffset, 6);
      views = tester.widgetList<RustTextInputField>(fields).toList();
      expect(views.first.inputWindow.document.resync().content, '\n$source');
      await _pressHistoryCommand(tester, platform, redo: false);
      await tester.pump(const Duration(milliseconds: 80));
      expect(firstController.text, source);
      await _pressHistoryCommand(tester, platform, redo: true);
      await tester.pump(const Duration(milliseconds: 80));
      expect(firstController.text, '\n$source');

      // Insert below the Rust main line. Both views share the Rust document,
      // and text undo/redo remains independent from cursor history.
      firstController.selection = const TextSelection.collapsed(offset: 6);
      await tester.pump();
      await _pressEnterCommand(tester, platform, before: false);
      await tester.pump(const Duration(milliseconds: 80));
      const afterMain =
          '\nfn main() { println!("linux-save-ok"); }\n\nfn helper() {}';
      expect(firstController.text, afterMain);
      views = tester.widgetList<RustTextInputField>(fields).toList();
      expect(views.first.inputWindow.document.resync().content, afterMain);
      expect(views.last.inputWindow.document.resync().content, afterMain);
      await _pressHistoryCommand(tester, platform, redo: false);
      await tester.pump(const Duration(milliseconds: 80));
      expect(firstController.text, '\n$source');
      await _pressHistoryCommand(tester, platform, redo: true);
      await tester.pump(const Duration(milliseconds: 80));
      expect(firstController.text, afterMain);

      // Insert above helper and save the caller supplied Linux fixture.
      firstController.selection = TextSelection.collapsed(
        offset: afterMain.lastIndexOf('fn helper') + 5,
      );
      await tester.pump();
      await _pressEnterCommand(tester, platform, before: true);
      await tester.pump(const Duration(milliseconds: 80));
      const saved =
          '\nfn main() { println!("linux-save-ok"); }\n\n\nfn helper() {}';
      expect(firstController.text, saved);

      // The existing save command is invoked with Ctrl on every target here;
      // this slice checks persistence, not the platform save keybinding.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 120));
      expect(file.readAsStringSync(), saved);
      views = tester.widgetList<RustTextInputField>(fields).toList();
      expect(views.first.inputWindow.document.resync().content, saved);
      expect(views.last.inputWindow.document.resync().content, saved);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
