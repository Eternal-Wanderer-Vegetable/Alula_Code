import 'dart:convert';
import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/main.dart';
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
  final temp = Directory.systemTemp.createTempSync('alula-auto-indent');
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
  ));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.tap(find.text('sample.rs').first);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.showKeyboard(
    find.byKey(const ValueKey('rust-bounded-text-input')),
  );
  await tester.pump();
  return (temp, file);
}

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
  bool meta = false,
  bool alt = false,
  bool shift = false,
}) async {
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  if (meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.pump();
}

TextEditingController _controller(WidgetTester tester) => tester
    .widget<TextField>(
      find.descendant(
        of: find.byType(RustTextInputField).first,
        matching: find.byType(TextField),
      ),
    )
    .controller!;

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
    platformTest('$platform Enter continues the current leading indentation',
        (tester) async {
      const source = '    fn main() {}';
      final (_, file) = await _openFixture(tester, platform, source);
      _controller(tester).selection =
          const TextSelection.collapsed(offset: source.length);
      await tester.pump();

      await _press(tester, LogicalKeyboardKey.enter);
      const edited = '    fn main() {}\n    ';
      expect(_controller(tester).text, edited);
      expect(
        _controller(tester).selection,
        const TextSelection.collapsed(offset: edited.length),
      );
      await _press(tester, LogicalKeyboardKey.keyS, control: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(file.readAsStringSync(), edited);

      await _press(
        tester,
        LogicalKeyboardKey.keyZ,
        control: !isMac,
        meta: isMac,
      );
      expect(_controller(tester).text, source);
      await _press(
        tester,
        LogicalKeyboardKey.keyZ,
        control: !isMac,
        meta: isMac,
        shift: true,
      );
      expect(_controller(tester).text, edited);
      await _press(tester, LogicalKeyboardKey.keyS, control: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(file.readAsStringSync(), edited);
    });
  }

  platformTest(
      'Enter replaces a selection and inherits indentation at its start',
      (tester) async {
    const source = '  alpha beta';
    await _openFixture(tester, TargetPlatform.linux, source);
    _controller(tester).selection =
        const TextSelection(baseOffset: 8, extentOffset: 12);
    await tester.pump();

    await _press(tester, LogicalKeyboardKey.enter);
    const edited = '  alpha \n  ';
    expect(_controller(tester).text, edited);
    expect(
      _controller(tester).selection,
      const TextSelection.collapsed(offset: edited.length),
    );
    await _press(tester, LogicalKeyboardKey.keyZ, control: true);
    expect(_controller(tester).text, source);
  });

  platformTest('Enter in indentation copies only whitespace before the caret',
      (tester) async {
    const source = '    alpha';
    await _openFixture(tester, TargetPlatform.linux, source);
    _controller(tester).selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();

    await _press(tester, LogicalKeyboardKey.enter);
    expect(_controller(tester).text, '  \n    alpha');
    expect(
      _controller(tester).selection,
      const TextSelection.collapsed(offset: 5),
    );
  });

  platformTest('Enter on an unindented line inserts only a newline',
      (tester) async {
    const source = 'value';
    await _openFixture(tester, TargetPlatform.linux, source);
    _controller(tester).selection =
        const TextSelection.collapsed(offset: source.length);
    await tester.pump();

    await _press(tester, LogicalKeyboardKey.enter);
    expect(_controller(tester).text, 'value\n');
    expect(
      _controller(tester).selection,
      const TextSelection.collapsed(offset: source.length + 1),
    );
  });

  platformTest('Enter applies each caret indentation in a multi-cursor edit',
      (tester) async {
    const source = '  one\n  two';
    await _openFixture(tester, TargetPlatform.linux, source);
    _controller(tester).selection = const TextSelection.collapsed(offset: 5);
    await tester.pump();
    await _press(
      tester,
      LogicalKeyboardKey.arrowDown,
      control: true,
      alt: true,
    );
    expect(
      tester
          .widget<RustTextInputField>(find.byType(RustTextInputField))
          .additionalSelections,
      hasLength(1),
    );

    await _press(tester, LogicalKeyboardKey.enter);
    const edited = '  one\n  \n  two\n  ';
    expect(_controller(tester).text, edited);
    await _press(tester, LogicalKeyboardKey.keyZ, control: true);
    expect(_controller(tester).text, source);
    expect(
      tester
          .widget<RustTextInputField>(find.byType(RustTextInputField))
          .inputWindow
          .document
          .resync()
          .content,
      source,
    );
  });

  platformTest('Enter after an emoji preserves UTF-16 offsets, BOM and CRLF',
      (tester) async {
    final (_, file) = await _openFixture(
      tester,
      TargetPlatform.linux,
      '\uFEFF  😀\r\n',
    );
    expect(_controller(tester).text, '  😀\n');
    _controller(tester).selection = const TextSelection.collapsed(offset: 4);
    await tester.pump();

    await _press(tester, LogicalKeyboardKey.numpadEnter);
    const edited = '  😀\n  \n';
    expect(_controller(tester).text, edited);
    await _press(tester, LogicalKeyboardKey.keyS, control: true);
    await tester.pump(const Duration(milliseconds: 100));

    final bytes = file.readAsBytesSync();
    expect(bytes.take(3).toList(), [0xef, 0xbb, 0xbf]);
    expect(utf8.decode(bytes.skip(3).toList()), '  😀\r\n  \r\n');
  });

  platformTest('Enter edit updates both views and saves the Rust document',
      (tester) async {
    const source = '  value';
    final (_, file) = await _openFixture(tester, TargetPlatform.linux, source);
    await tester.tap(find.byTooltip('拆分编辑器').first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('sample.rs').first);
    await tester.pump(const Duration(milliseconds: 300));

    final fields = find.byType(RustTextInputField);
    expect(fields, findsNWidgets(2));
    Finder editorAt(int index) => find.descendant(
          of: fields.at(index),
          matching: find.byType(TextField),
        );
    await tester.showKeyboard(editorAt(1));
    final secondController = tester.widget<TextField>(editorAt(1)).controller!;
    secondController.selection =
        const TextSelection.collapsed(offset: source.length);
    await tester.pump();
    await _press(tester, LogicalKeyboardKey.enter);

    const edited = '  value\n  ';
    final views = tester.widgetList<RustTextInputField>(fields).toList();
    expect(views[0].inputWindow.initialValue.text, edited);
    expect(views[1].inputWindow.initialValue.text, edited);
    await _press(tester, LogicalKeyboardKey.keyS, control: true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(file.readAsStringSync(), edited);
  });
}
