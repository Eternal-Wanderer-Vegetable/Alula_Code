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

Future<void> _invokeTranspose(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump(const Duration(milliseconds: 100));
  final palette = find.byType(TextField).last;
  await tester.enterText(palette, '转置字母');
  await tester.pump(const Duration(milliseconds: 100));
  final command = find.text('编辑器: 转置字母');
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
    testWidgets(
      '$platform transpose-letters edits, syncs, saves, undoes and redoes',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.view.physicalSize = const Size(1200, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final temp = Directory.systemTemp.createTempSync('alula-transpose');
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          if (temp.existsSync()) temp.deleteSync(recursive: true);
        });
        final workspace = Directory('${temp.path}/workspace')..createSync();
        const source = 'abc\nwxyz';
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

        controller.selection = const TextSelection.collapsed(offset: 2);
        await tester.pump();
        await _invokeTranspose(tester);
        controller = tester.widget<TextField>(primaryField).controller!;
        const transposed = 'acb\nwxyz';
        expect(controller.text, transposed);
        expect(controller.selection, const TextSelection.collapsed(offset: 3));
        expect(tester.widget<TextField>(textFieldAt(1)).controller!.text,
            transposed);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump(const Duration(milliseconds: 120));
        expect(file.readAsBytesSync(), <int>[
          0xef,
          0xbb,
          0xbf,
          ...utf8.encode(transposed.replaceAll('\n', '\r\n')),
        ]);

        await _pressUndo(tester);
        controller = tester.widget<TextField>(primaryField).controller!;
        expect(controller.text, source);
        await _pressUndo(tester, redo: true);
        controller = tester.widget<TextField>(primaryField).controller!;
        expect(controller.text, transposed);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump(const Duration(milliseconds: 120));
        expect(file.readAsBytesSync(), <int>[
          0xef,
          0xbb,
          0xbf,
          ...utf8.encode(transposed.replaceAll('\n', '\r\n')),
        ]);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets('transpose supports line starts and leaves text selections alone',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final temp = Directory.systemTemp.createTempSync('alula-transpose-lines');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    const source = 'abc\nwxyz';
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

    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 2);
    await tester.pump();
    await _invokeTranspose(tester);
    controller = tester.widget<TextField>(field).controller!;
    expect(controller.text, source);
    expect(controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 2));

    controller.selection = const TextSelection.collapsed(offset: 4);
    await tester.pump();
    await _invokeTranspose(tester);
    controller = tester.widget<TextField>(field).controller!;
    expect(controller.text, 'abcw\nxyz');
    expect(controller.selection, const TextSelection.collapsed(offset: 5));
  });

  testWidgets('transpose applies independent secondary carets atomically',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final temp = Directory.systemTemp.createTempSync('alula-transpose-cursors');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    const source = 'abcd\nwxyz';
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
    final controller = tester.widget<TextField>(field).controller!;
    controller.selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();

    await _invokeTranspose(tester);
    final edited = tester.widget<TextField>(field).controller!;
    expect(edited.text, 'bacd\nxwyz');
    expect(edited.selection, const TextSelection.collapsed(offset: 2));
  });
}
