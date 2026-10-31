import 'dart:convert';
import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderEditable, RenderObject;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _invokeCaseCommand(WidgetTester tester, String title) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump(const Duration(milliseconds: 100));
  final palette = find.byType(TextField).last;
  await tester.enterText(palette, title);
  await tester.pump(const Duration(milliseconds: 100));
  final command = find.text('编辑器: $title');
  expect(command, findsOneWidget);
  await tester.tap(command);
  await tester.pump(const Duration(milliseconds: 150));
}

Future<void> _pressHistory(WidgetTester tester, {required bool redo}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (redo) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
  if (redo) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
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
    testWidgets(
        '$platform transforms selected text and the configured default word',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(1200, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final temp = Directory.systemTemp.createTempSync('alula-case-conversion');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });
      final workspace = Directory('${temp.path}/workspace')..createSync();
      const source = 'hello world\nöçşğü\n   \n🌱 seed\nstraße';
      const upperSelection = 'HELLO WORLD\nöçşğü\n   \n🌱 seed\nstraße';
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
      final primaryField = textFieldAt(0);
      await tester.tap(primaryField);
      await tester.showKeyboard(primaryField);
      var controller = tester.widget<TextField>(primaryField).controller!;
      expect(controller.text, source);

      controller.selection =
          const TextSelection(baseOffset: 0, extentOffset: 11);
      await tester.pump();
      await _invokeCaseCommand(tester, '转换为大写');
      controller = tester.widget<TextField>(primaryField).controller!;
      expect(controller.text, upperSelection);
      expect(controller.selection,
          const TextSelection(baseOffset: 0, extentOffset: 11));
      expect(
        tester.widget<TextField>(textFieldAt(1)).controller!.text,
        upperSelection,
      );

      await _pressSave(tester);
      expect(
        file.readAsBytesSync(),
        <int>[
          0xef,
          0xbb,
          0xbf,
          ...utf8.encode(upperSelection.replaceAll('\n', '\r\n')),
        ],
      );
      await _pressHistory(tester, redo: false);
      controller = tester.widget<TextField>(primaryField).controller!;
      expect(controller.text, source);
      expect(tester.widget<TextField>(textFieldAt(1)).controller!.text, source);
      await _pressHistory(tester, redo: true);
      await _pressHistory(tester, redo: false);

      controller = tester.widget<TextField>(primaryField).controller!;
      controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
      await tester.tap(primaryField);
      await tester.showKeyboard(primaryField);
      controller = tester.widget<TextField>(primaryField).controller!;
      controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
      final editableRoot = tester.renderObject<RenderObject>(
        find.descendant(
          of: primaryField,
          matching: find.byType(EditableText),
        ),
      );
      RenderEditable? findEditable(RenderObject object) {
        if (object is RenderEditable) return object;
        RenderEditable? found;
        object.visitChildren((child) {
          found ??= findEditable(child);
        });
        return found;
      }

      final editable = findEditable(editableRoot)!;
      const secondWordOffset = 6;
      final caretRect = editable.getLocalRectForCaret(
        const TextPosition(offset: secondWordOffset),
      );
      final globalClick = editable.localToGlobal(
        Offset(caretRect.left + 0.1, caretRect.center.dy),
      );
      expect(
          editable.getPositionForPoint(globalClick).offset, secondWordOffset);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(globalClick, kind: PointerDeviceKind.mouse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      await tester.pump();
      expect(
        tester.widget<RustTextInputField>(fields.first).additionalSelections,
        const [TextSelection.collapsed(offset: secondWordOffset)],
      );
      await _invokeCaseCommand(tester, '转换为大写');
      controller = tester.widget<TextField>(primaryField).controller!;
      expect(controller.text, upperSelection);
      expect(controller.selection, const TextSelection.collapsed(offset: 0));
      expect(
        tester.widget<RustTextInputField>(fields.first).additionalSelections,
        const [TextSelection.collapsed(offset: secondWordOffset)],
      );
      expect(tester.widget<TextField>(textFieldAt(1)).controller!.text,
          upperSelection);

      await tester.tap(primaryField);
      controller = tester.widget<TextField>(primaryField).controller!;
      controller.selection = const TextSelection.collapsed(offset: 2);
      await tester.pump();
      await _invokeCaseCommand(tester, '转换为小写');
      controller = tester.widget<TextField>(primaryField).controller!;
      expect(controller.text, 'hello WORLD\nöçşğü\n   \n🌱 seed\nstraße');
      expect(controller.selection, const TextSelection.collapsed(offset: 2));

      final unicodeStart = controller.text.indexOf('öçşğü');
      controller.selection = TextSelection(
        baseOffset: unicodeStart,
        extentOffset: unicodeStart + 'öçşğü'.length,
      );
      await tester.pump();
      await _invokeCaseCommand(tester, '转换为大写');
      controller = tester.widget<TextField>(primaryField).controller!;
      expect(controller.text, 'hello WORLD\nÖÇŞĞÜ\n   \n🌱 seed\nstraße');

      final seedStart = controller.text.indexOf('seed');
      controller.selection = TextSelection(
        baseOffset: seedStart,
        extentOffset: seedStart + 4,
      );
      await tester.pump();
      await _invokeCaseCommand(tester, '转换为大写');
      controller = tester.widget<TextField>(primaryField).controller!;
      expect(controller.text, 'hello WORLD\nÖÇŞĞÜ\n   \n🌱 SEED\nstraße');

      final whitespaceCaret = controller.text.indexOf('   ') + 1;
      controller.selection = TextSelection.collapsed(offset: whitespaceCaret);
      await tester.pump();
      await _invokeCaseCommand(tester, '转换为小写');
      controller = tester.widget<TextField>(primaryField).controller!;
      expect(controller.text, 'hello WORLD\nÖÇŞĞÜ\n   \n🌱 SEED\nstraße');

      final sharpSStart = controller.text.lastIndexOf('straße');
      controller.selection = TextSelection(
        baseOffset: sharpSStart,
        extentOffset: sharpSStart + 'straße'.length,
      );
      await tester.pump();
      await _invokeCaseCommand(tester, '转换为大写');
      controller = tester.widget<TextField>(primaryField).controller!;
      expect(controller.text, 'hello WORLD\nÖÇŞĞÜ\n   \n🌱 SEED\nSTRASSE');
      expect(
        controller.selection,
        TextSelection(baseOffset: sharpSStart, extentOffset: sharpSStart + 7),
      );
      expect(
        tester.widget<TextField>(textFieldAt(1)).controller!.text,
        'hello WORLD\nÖÇŞĞÜ\n   \n🌱 SEED\nSTRASSE',
      );

      await _pressHistory(tester, redo: false);
      controller = tester.widget<TextField>(primaryField).controller!;
      expect(controller.text, 'hello WORLD\nÖÇŞĞÜ\n   \n🌱 SEED\nstraße');
      await _pressHistory(tester, redo: true);
      controller = tester.widget<TextField>(primaryField).controller!;
      expect(controller.text, 'hello WORLD\nÖÇŞĞÜ\n   \n🌱 SEED\nSTRASSE');

      await _pressSave(tester);
      expect(
        file.readAsBytesSync(),
        <int>[
          0xef,
          0xbb,
          0xbf,
          ...utf8.encode(
            'hello WORLD\r\nÖÇŞĞÜ\r\n   \r\n🌱 SEED\r\nSTRASSE',
          ),
        ],
      );
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
