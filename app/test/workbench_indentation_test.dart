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

Future<(Directory, File)> _openFixture(
  WidgetTester tester,
  TargetPlatform platform,
  String text,
) async {
  debugDefaultTargetPlatformOverride = platform;
  final temp = Directory.systemTemp.createTempSync('alula-indentation');
  addTearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });
  final workspace = Directory('${temp.path}/workspace')..createSync();
  final file = File('${workspace.path}/sample.rs')..writeAsStringSync(text);
  final base = temp.path.replaceAll(r'\', '/');
  await tester.pumpWidget(AlulaApp(
    autoFolder: workspace.path,
    layoutStore: LayoutStore(path: '$base/layout.json'),
    sessionStore: SessionStore(path: '$base/session.json'),
    keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
  ));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.tap(find.text('sample.rs').first);
  await tester.pump(const Duration(milliseconds: 300));
  final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
  await tester.showKeyboard(editor);
  await tester.pump();
  return (temp, file);
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
  await tester.pump();
  await tester.pump();
}

void main() {
  void platformTest(
    String description,
    Future<void> Function(WidgetTester tester) body,
  ) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    final isMac = platform == TargetPlatform.macOS;
    platformTest(
        '$platform Tab indentation saves and text undo/redo round-trips',
        (tester) async {
      const source = 'fn main() {\r\nprintln!("linux-save-ok");\r\n}\r\n';
      final (_, file) = await _openFixture(tester, platform, source);
      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      var controller = tester.widget<TextField>(editor).controller!;
      const normalized = 'fn main() {\nprintln!("linux-save-ok");\n}\n';
      expect(controller.text, normalized);
      controller.selection = const TextSelection.collapsed(offset: 12);
      await tester.pump();

      await _press(tester, LogicalKeyboardKey.tab);
      const indented = 'fn main() {\n    println!("linux-save-ok");\n}\n';
      expect(controller.text, indented);

      await _press(tester, LogicalKeyboardKey.keyS, control: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(file.readAsStringSync(), indented.replaceAll('\n', '\r\n'));

      await _press(
        tester,
        LogicalKeyboardKey.keyZ,
        control: !isMac,
        meta: isMac,
      );
      controller = tester.widget<TextField>(editor).controller!;
      expect(controller.text, normalized);
      await _press(
        tester,
        LogicalKeyboardKey.keyZ,
        control: !isMac,
        meta: isMac,
        shift: true,
      );
      controller = tester.widget<TextField>(editor).controller!;
      expect(controller.text, indented);
      await _press(tester, LogicalKeyboardKey.keyS, control: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(file.readAsStringSync(), indented.replaceAll('\n', '\r\n'));
    });

    platformTest(
        '$platform selection Tab, Shift+Tab and line commands edit rows',
        (tester) async {
      const source = 'one\n\ntwo\nthree\n';
      await _openFixture(tester, platform, source);
      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      var controller = tester.widget<TextField>(editor).controller!;

      controller.selection =
          const TextSelection(baseOffset: 0, extentOffset: 9);
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.tab);
      const indented = '    one\n\n    two\nthree\n';
      expect(controller.text, indented);

      controller.selection =
          const TextSelection(baseOffset: 0, extentOffset: 17);
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.tab, shift: true);
      expect(controller.text, source);

      controller.selection = const TextSelection.collapsed(offset: 6);
      await tester.pump();
      await _press(
        tester,
        LogicalKeyboardKey.bracketRight,
        control: !isMac,
        meta: isMac,
      );
      expect(controller.text, 'one\n\n    two\nthree\n');
      await _press(
        tester,
        LogicalKeyboardKey.bracketLeft,
        control: !isMac,
        meta: isMac,
      );
      expect(controller.text, source);
    });
  }

  platformTest(
      'Tab applies all same-document carets and undo restores the text',
      (tester) async {
    const source = 'ax\nax\n';
    await _openFixture(tester, TargetPlatform.linux, source);
    final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
    var controller = tester.widget<TextField>(editor).controller!;
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 2);
    await tester.pump();

    await _press(tester, LogicalKeyboardKey.keyD, control: true);
    var field = tester.widget<RustTextInputField>(
      find.byType(RustTextInputField),
    );
    expect(field.additionalSelections, hasLength(1));
    await _press(tester, LogicalKeyboardKey.tab);
    controller = tester.widget<TextField>(editor).controller!;
    expect(controller.text, 'a   \na   \n');
    expect(
      tester
          .widget<RustTextInputField>(find.byType(RustTextInputField))
          .additionalSelections,
      hasLength(1),
    );

    await _press(tester, LogicalKeyboardKey.keyZ, control: true);
    controller = tester.widget<TextField>(editor).controller!;
    expect(controller.text, source);
    field = tester.widget<RustTextInputField>(find.byType(RustTextInputField));
    expect(field.inputWindow.document.resync().content, source);
  });

  platformTest('Tab edit synchronizes a second view and save readback',
      (tester) async {
    const source = 'one\n';
    final (_, file) = await _openFixture(tester, TargetPlatform.linux, source);
    await tester.tap(find.byTooltip('拆分编辑器').first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('sample.rs').first);
    await tester.pump(const Duration(milliseconds: 300));

    final fields = find.byType(RustTextInputField);
    expect(fields, findsNWidgets(2));
    Finder textFieldAt(int index) => find.descendant(
          of: fields.at(index),
          matching: find.byType(TextField),
        );
    await tester.showKeyboard(textFieldAt(1));
    var controller = tester.widget<TextField>(textFieldAt(1)).controller!;
    controller.selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();
    await _press(tester, LogicalKeyboardKey.tab);

    const edited = 'o   ne\n';
    final views = tester.widgetList<RustTextInputField>(fields).toList();
    expect(views[0].inputWindow.initialValue.text, edited);
    expect(views[1].inputWindow.initialValue.text, edited);
    await _press(tester, LogicalKeyboardKey.keyS, control: true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(file.readAsStringSync(), edited);
  });

  platformTest(
      'Tab after an emoji uses UTF-16 offsets and the visible tab stop',
      (tester) async {
    const source = 'a😀b\n';
    await _openFixture(tester, TargetPlatform.linux, source);
    final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
    final controller = tester.widget<TextField>(editor).controller!;
    controller.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();

    await _press(tester, LogicalKeyboardKey.tab);
    expect(controller.text, 'a😀 b\n');
    expect(controller.selection, const TextSelection.collapsed(offset: 4));
  });

  platformTest('Tab edit preserves a file BOM through Rust save',
      (tester) async {
    final (_, file) = await _openFixture(
      tester,
      TargetPlatform.linux,
      '\uFEFFvalue\r\n',
    );
    final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
    var controller = tester.widget<TextField>(editor).controller!;
    expect(controller.text, 'value\n');
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();
    await _press(tester, LogicalKeyboardKey.tab);
    controller = tester.widget<TextField>(editor).controller!;
    expect(controller.text, '    value\n');
    await _press(tester, LogicalKeyboardKey.keyS, control: true);
    await tester.pump(const Duration(milliseconds: 100));
    final bytes = file.readAsBytesSync();
    expect(bytes.take(3).toList(), [0xef, 0xbb, 0xbf]);
    expect(String.fromCharCodes(bytes.skip(3)), '    value\r\n');
  });
}
