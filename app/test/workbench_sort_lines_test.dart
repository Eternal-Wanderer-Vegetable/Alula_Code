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

Future<void> _invokeSortLines(WidgetTester tester, String label) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump(const Duration(milliseconds: 100));
  final palette = find.byType(TextField).last;
  await tester.enterText(palette, label);
  await tester.pump(const Duration(milliseconds: 100));
  final command = find.text('编辑器: $label');
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
    testWidgets('$platform sorts lines with Rust undo and save',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(1200, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final temp = Directory.systemTemp.createTempSync('alula-line-sort');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });
      final workspace = Directory('${temp.path}/workspace')..createSync();
      const source = 'fn main() { println!("linux-save-ok"); }\n'
          'zeta\n'
          'beta\n'
          'alpha\n'
          'keep\n'
          'gamma\n'
          'delta\n'
          'epsilon\n'
          '🌱 plant\n'
          'tail';
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
      final views = tester.widgetList<RustTextInputField>(fields).toList();
      expect(views.first.inputWindow.document.id,
          views.last.inputWindow.document.id);
      expect(controller.text, source);

      final zetaStart = source.indexOf('zeta');
      final keepStart = source.indexOf('keep');
      controller.selection = TextSelection(
        baseOffset: zetaStart,
        extentOffset: keepStart,
      );
      await tester.pump();
      await _invokeSortLines(tester, '按升序排序行');
      final afterAscending = source.replaceRange(
        zetaStart,
        keepStart,
        'alpha\nbeta\nzeta\n',
      );
      expect(controller.text, afterAscending);
      expect(controller.selection.start, zetaStart);
      expect(controller.selection.end, keepStart);
      var currentViews = tester.widgetList<RustTextInputField>(fields).toList();
      expect(currentViews.first.inputWindow.document.resync().content,
          afterAscending);
      expect(currentViews.last.inputWindow.document.resync().content,
          afterAscending);

      await _pressHistory(tester, platform, redo: false);
      expect(controller.text, source);
      await _pressHistory(tester, platform, redo: true);
      expect(controller.text, afterAscending);

      final alphaStart = controller.text.indexOf('alpha');
      final keepAfterAscending = controller.text.indexOf('keep');
      controller.selection = TextSelection(
        baseOffset: alphaStart,
        extentOffset: keepAfterAscending,
      );
      await tester.pump();
      await _invokeSortLines(tester, '按降序排序行');
      final afterDescending = afterAscending.replaceRange(
        alphaStart,
        keepAfterAscending,
        'zeta\nbeta\nalpha\n',
      );
      expect(controller.text, afterDescending);
      await _pressHistory(tester, platform, redo: false);
      expect(controller.text, afterAscending);
      await _pressHistory(tester, platform, redo: true);
      expect(controller.text, afterDescending);
      await _pressSave(tester);
      expect(
        file.readAsBytesSync(),
        [
          0xef,
          0xbb,
          0xbf,
          ...utf8.encode(afterDescending.replaceAll('\n', '\r\n')),
        ],
      );

      controller.selection = TextSelection.collapsed(
        offset: controller.text.indexOf('keep') + 2,
      );
      await tester.pump();
      await _invokeSortLines(tester, '按升序排序行');
      const afterWholeDocumentSort = 'alpha\n'
          'beta\n'
          'delta\n'
          'epsilon\n'
          'fn main() { println!("linux-save-ok"); }\n'
          'gamma\n'
          'keep\n'
          'tail\n'
          'zeta\n'
          '🌱 plant';
      expect(controller.text, afterWholeDocumentSort);
      expect(controller.selection.start, 0);
      expect(controller.selection.end, afterWholeDocumentSort.length);
      currentViews = tester.widgetList<RustTextInputField>(fields).toList();
      expect(currentViews.first.inputWindow.document.resync().content,
          afterWholeDocumentSort);
      expect(currentViews.last.inputWindow.document.resync().content,
          afterWholeDocumentSort);
      await _pressHistory(tester, platform, redo: false);
      expect(controller.text, afterDescending);
      await _pressHistory(tester, platform, redo: true);
      expect(controller.text, afterWholeDocumentSort);
      await _pressSave(tester);
      expect(
        file.readAsBytesSync(),
        [
          0xef,
          0xbb,
          0xbf,
          ...utf8.encode(afterWholeDocumentSort.replaceAll('\n', '\r\n')),
        ],
      );
      debugDefaultTargetPlatformOverride = null;
    });
  }

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    testWidgets('$platform keeps sorting atomic for multiple cursors',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final temp = Directory.systemTemp.createTempSync('alula-sort-cursors');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });
      final workspace = Directory('${temp.path}/workspace')..createSync();
      const source = 'zeta\nbeta\nalpha';
      File('${workspace.path}/sample.txt').writeAsStringSync(source);
      final base = temp.path.replaceAll(r'\', '/');
      await tester.pumpWidget(AlulaApp(
        autoFolder: workspace.path,
        layoutStore: LayoutStore(path: '$base/layout.json'),
        sessionStore: SessionStore(path: '$base/session.json'),
        keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
      ));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('sample.txt').first);
      await tester.pump(const Duration(milliseconds: 300));

      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      await tester.showKeyboard(editor);
      await tester.pump();
      final controller = tester.widget<TextField>(editor).controller!;
      controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester
            .widget<RustTextInputField>(find.byType(RustTextInputField))
            .additionalSelections,
        const [TextSelection.collapsed(offset: 5)],
      );

      await _invokeSortLines(tester, '按升序排序行');
      expect(controller.text, source);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
