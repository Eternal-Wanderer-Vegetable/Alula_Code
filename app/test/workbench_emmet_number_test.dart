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

Future<void> _invokeEmmetNumber(
  WidgetTester tester, {
  required String query,
  required String label,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump(const Duration(milliseconds: 100));
  final palette = find.byType(TextField).last;
  await tester.enterText(palette, query);
  await tester.pump(const Duration(milliseconds: 100));
  final command = find.text(label).last;
  expect(command, findsOneWidget);
  await tester.tap(command);
  await tester.pump(const Duration(milliseconds: 150));
}

Future<void> _pressUndo(WidgetTester tester, {bool redo = false}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (redo) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
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
    testWidgets('$platform Emmet numeric commands edit and save in split views',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(1200, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final temp = Directory.systemTemp.createTempSync('alula-emmet-numbers');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });
      final workspace = Directory('${temp.path}/workspace')..createSync();
      const source =
          'inc01=123.43\ninc1=100\ninc10=100\ndec01=123.43\ndec1=100\ndec10=100\npad=007\nnegative=-07\nfraction=.1\nnone=word';
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

      final editors = find.byType(RustTextInputField);
      expect(editors, findsNWidgets(2));
      Finder textFieldAt(int index) => find.descendant(
            of: editors.at(index),
            matching: find.byType(TextField),
          );
      final primary = textFieldAt(0);
      await tester.tap(primary);
      await tester.showKeyboard(primary);
      var controller = tester.widget<TextField>(primary).controller!;
      expect(controller.text, source);

      Future<void> applyToNumber(
        String token, {
        required String query,
        required String label,
        bool reversed = false,
      }) async {
        await tester.tap(primary);
        controller = tester.widget<TextField>(primary).controller!;
        final start = controller.text.indexOf(token);
        expect(start, isNonNegative);
        final end = start + token.length;
        controller.selection = reversed
            ? TextSelection(baseOffset: end, extentOffset: start)
            : TextSelection(baseOffset: start, extentOffset: end);
        await tester.pump();
        await _invokeEmmetNumber(tester, query: query, label: label);
        controller = tester.widget<TextField>(primary).controller!;
      }

      await applyToNumber('123.43',
          query: 'Emmet: 增加 0.1', label: 'Emmet: 增加 0.1', reversed: true);
      expect(controller.text, contains('inc01=123.53'));
      await applyToNumber('inc1=100',
          query: 'Emmet: 增加 1', label: 'Emmet: 增加 1');
      await applyToNumber('inc10=100',
          query: 'Emmet: 增加 10', label: 'Emmet: 增加 10');
      await applyToNumber('dec01=123.43',
          query: 'Emmet: 减少 0.1', label: 'Emmet: 减少 0.1');
      await applyToNumber('dec1=100',
          query: 'Emmet: 减少 1', label: 'Emmet: 减少 1');
      await applyToNumber('dec10=100',
          query: 'Emmet: 减少 10', label: 'Emmet: 减少 10');
      await applyToNumber('pad=007',
          query: 'Emmet: 增加 1', label: 'Emmet: 增加 1');
      await applyToNumber('negative=-07',
          query: 'Emmet: 减少 1', label: 'Emmet: 减少 1');
      await applyToNumber('fraction=.1',
          query: 'Emmet: 减少 0.1', label: 'Emmet: 减少 0.1');
      await applyToNumber('none=word',
          query: 'Emmet: 增加 1', label: 'Emmet: 增加 1');

      const expected =
          'inc01=123.53\ninc1=101\ninc10=110\ndec01=123.33\ndec1=99\ndec10=90\npad=008\nnegative=-08\nfraction=\nnone=word';
      expect(controller.text, expected);
      expect(
          tester.widget<TextField>(textFieldAt(1)).controller!.text, expected);

      await tester.tap(primary);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 120));
      expect(file.readAsBytesSync(), <int>[
        0xef,
        0xbb,
        0xbf,
        ...utf8.encode(expected.replaceAll('\n', '\r\n')),
      ]);

      await _pressUndo(tester);
      controller = tester.widget<TextField>(primary).controller!;
      expect(controller.text, contains('fraction=.1'));
      await _pressUndo(tester);
      controller = tester.widget<TextField>(primary).controller!;
      expect(controller.text, contains('negative=-07'));
      await _pressUndo(tester, redo: true);
      controller = tester.widget<TextField>(primary).controller!;
      expect(controller.text, contains('negative=-08'));
      await _pressUndo(tester, redo: true);
      controller = tester.widget<TextField>(primary).controller!;
      expect(controller.text, expected);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 120));
      expect(file.readAsBytesSync(), <int>[
        0xef,
        0xbb,
        0xbf,
        ...utf8.encode(expected.replaceAll('\n', '\r\n')),
      ]);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('Emmet numeric command adjusts multiple carets independently',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final temp = Directory.systemTemp.createTempSync('alula-emmet-multicaret');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    const source = 'a=1\nb=2\nc=word';
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
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('main.rs').first);
    await tester.pump(const Duration(milliseconds: 300));
    final field = find.descendant(
      of: find.byType(RustTextInputField),
      matching: find.byType(TextField),
    );
    await tester.tap(field);
    await tester.showKeyboard(field);
    var controller = tester.widget<TextField>(field).controller!;

    controller.selection = const TextSelection.collapsed(offset: 14);
    await tester.pump();
    await _invokeEmmetNumber(
      tester,
      query: 'Emmet: 增加 1',
      label: 'Emmet: 增加 1',
    );
    controller = tester.widget<TextField>(field).controller!;
    expect(controller.text, source);

    controller.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    await _invokeEmmetNumber(
      tester,
      query: 'Emmet: 增加 1',
      label: 'Emmet: 增加 1',
    );
    controller = tester.widget<TextField>(field).controller!;
    expect(controller.text, 'a=2\nb=3\nc=word');
  });
}
