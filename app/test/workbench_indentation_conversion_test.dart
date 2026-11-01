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

Future<void> _invokeIndentationCommand(
  WidgetTester tester,
  String title,
) async {
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
    testWidgets('$platform converts indentation across split views and history',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        tester.view.physicalSize = const Size(1200, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final temp =
            Directory.systemTemp.createTempSync('alula-indent-convert');
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          if (temp.existsSync()) temp.deleteSync(recursive: true);
        });
        final workspace = Directory('${temp.path}/workspace')..createSync();
        const mixed = 'fn main() {\n\tprintln!("hi");\n    let value = 1;\n}\n';
        const spaces =
            'fn main() {\n    println!("hi");\n    let value = 1;\n}\n';
        const tabs = 'fn main() {\n\tprintln!("hi");\n\tlet value = 1;\n}\n';
        final file = File('${workspace.path}/main.rs')
          ..writeAsBytesSync([
            0xef,
            0xbb,
            0xbf,
            ...utf8.encode(mixed.replaceAll('\n', '\r\n')),
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
        final lineThreeStart = mixed.indexOf('    let');
        final selection = TextSelection.collapsed(offset: lineThreeStart + 3);
        first.selection = selection;
        second.selection = selection;
        await tester.pump();

        await _invokeIndentationCommand(tester, '将缩进转换为空格');
        expect(first.text, spaces);
        expect(second.text, spaces);
        expect(first.selection.extentOffset, lineThreeStart + 6);

        await _invokeIndentationCommand(tester, '将缩进转换为制表符');
        expect(first.text, tabs);
        expect(second.text, tabs);
        expect(first.selection.extentOffset, lineThreeStart + 1);
        expect(second.selection.extentOffset, lineThreeStart + 1);

        await _invokeIndentationCommand(tester, '将缩进转换为制表符');
        expect(first.text, tabs);
        await tester.tap(secondField);
        await tester.showKeyboard(secondField);
        second.selection =
            TextSelection.collapsed(offset: tabs.indexOf('println'));
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump(const Duration(milliseconds: 120));
        final tabInserted = tabs.replaceFirst('\tprintln', '\t\tprintln');
        expect(first.text, tabInserted);
        expect(second.text, tabInserted);
        await _press(
          tester,
          LogicalKeyboardKey.keyZ,
          control: platform != TargetPlatform.macOS,
          meta: platform == TargetPlatform.macOS,
        );
        expect(first.text, tabs);
        expect(second.text, tabs);
        await _press(
          tester,
          LogicalKeyboardKey.keyZ,
          control: platform != TargetPlatform.macOS,
          meta: platform == TargetPlatform.macOS,
        );
        expect(first.text, spaces);
        await _press(
          tester,
          LogicalKeyboardKey.keyZ,
          control: platform != TargetPlatform.macOS,
          meta: platform == TargetPlatform.macOS,
          shift: true,
        );
        expect(first.text, tabs);
        expect(second.text, tabs);

        await _press(
          tester,
          LogicalKeyboardKey.keyS,
          control: true,
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          file.readAsBytesSync(),
          [0xef, 0xbb, 0xbf, ...utf8.encode(tabs.replaceAll('\n', '\r\n'))],
        );
        expect(
          tester
              .widgetList<RustTextInputField>(fields)
              .every((view) => view.tabSize == 4),
          isTrue,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }
}
