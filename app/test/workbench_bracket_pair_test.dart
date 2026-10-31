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
  String text, {
  String extension = 'rs',
}) async {
  debugDefaultTargetPlatformOverride = platform;
  final temp = Directory.systemTemp.createTempSync('alula-bracket-pair');
  addTearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });
  final workspace = Directory('${temp.path}/workspace')..createSync();
  final file = File('${workspace.path}/sample.$extension')
    ..writeAsStringSync(text);
  final base = temp.path.replaceAll(r'\', '/');
  await tester.pumpWidget(AlulaApp(
    autoFolder: workspace.path,
    layoutStore: LayoutStore(path: '$base/layout.json'),
    sessionStore: SessionStore(path: '$base/session.json'),
  ));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.tap(find.text('sample.$extension').first);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.showKeyboard(
    find.byKey(const ValueKey('rust-bounded-text-input')),
  );
  await tester.pump();
  return (temp, file);
}

Future<void> _typeCharacter(WidgetTester tester, String character) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: character);
  await tester.pump();
  await tester.pump();
}

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
}) async {
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.pump();
}

TextEditingController _controller(WidgetTester tester, {int index = 0}) {
  final fields = find.byType(RustTextInputField);
  return tester
      .widget<TextField>(
        find.descendant(
          of: fields.at(index),
          matching: find.byType(TextField),
        ),
      )
      .controller!;
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
    platformTest('$platform Rust brackets auto-close and skip existing closers',
        (tester) async {
      final (_, file) = await _openFixture(tester, platform, '');
      await _typeCharacter(tester, '(');
      expect(_controller(tester).text, '()');
      expect(
        _controller(tester).selection,
        const TextSelection.collapsed(offset: 1),
      );

      await _typeCharacter(tester, '[');
      expect(_controller(tester).text, '([])');
      await _typeCharacter(tester, '{');
      expect(_controller(tester).text, '([{}])');
      await _typeCharacter(tester, '}');
      await _typeCharacter(tester, ']');
      await _typeCharacter(tester, ')');
      expect(_controller(tester).text, '([{}])');
      expect(
        _controller(tester).selection,
        const TextSelection.collapsed(offset: 6),
      );

      await _press(tester, LogicalKeyboardKey.keyS, control: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(file.readAsStringSync(), '([{}])');
      await _press(tester, LogicalKeyboardKey.keyZ, control: true);
      expect(_controller(tester).text, '([])');
      await _press(tester, LogicalKeyboardKey.keyY, control: true);
      expect(_controller(tester).text, '([{}])');
    });
  }

  platformTest('Rust opening bracket surrounds the selection and is undoable',
      (tester) async {
    await _openFixture(tester, TargetPlatform.linux, 'value');
    _controller(tester).selection =
        const TextSelection(baseOffset: 0, extentOffset: 5);
    await tester.pump();

    await _typeCharacter(tester, '(');
    expect(_controller(tester).text, '(value)');
    expect(
      _controller(tester).selection,
      const TextSelection(baseOffset: 1, extentOffset: 6),
    );
    await _press(tester, LogicalKeyboardKey.keyZ, control: true);
    expect(_controller(tester).text, 'value');
    await _press(tester, LogicalKeyboardKey.keyY, control: true);
    expect(_controller(tester).text, '(value)');
  });

  platformTest('Rust bracket input applies to each multi-cursor selection',
      (tester) async {
    await _openFixture(tester, TargetPlatform.linux, 'ab\ncd');
    _controller(tester).selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(
      tester
          .widget<RustTextInputField>(find.byType(RustTextInputField))
          .additionalSelections,
      hasLength(1),
    );

    await _typeCharacter(tester, '[');
    expect(_controller(tester).text, 'ab[]\ncd[]');
    expect(
      tester
          .widget<RustTextInputField>(find.byType(RustTextInputField))
          .inputWindow
          .document
          .resync()
          .content,
      'ab[]\ncd[]',
    );
    await _press(tester, LogicalKeyboardKey.keyZ, control: true);
    expect(_controller(tester).text, 'ab\ncd');
  });

  platformTest(
      'Rust bracket TextOps preserve BOM, emoji UTF-16 offsets and CRLF',
      (tester) async {
    final (_, file) = await _openFixture(
      tester,
      TargetPlatform.linux,
      '\uFEFF😀\r\n',
    );
    expect(_controller(tester).text, '😀\n');
    _controller(tester).selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();

    await _typeCharacter(tester, '(');
    expect(_controller(tester).text, '😀()\n');
    expect(
      _controller(tester).selection,
      const TextSelection.collapsed(offset: 3),
    );
    await _press(tester, LogicalKeyboardKey.keyS, control: true);
    await tester.pump(const Duration(milliseconds: 100));
    final bytes = file.readAsBytesSync();
    expect(bytes.take(3).toList(), [0xef, 0xbb, 0xbf]);
    expect(utf8.decode(bytes.skip(3).toList()), '😀()\r\n');
  });

  platformTest('Rust closing bracket without a matching pair is inserted',
      (tester) async {
    await _openFixture(tester, TargetPlatform.linux, 'abc');
    _controller(tester).selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();

    await _typeCharacter(tester, ')');
    expect(_controller(tester).text, 'a)bc');
    expect(
      _controller(tester).selection,
      const TextSelection.collapsed(offset: 2),
    );
  });

  platformTest('Rust overtype skips only its tracked auto-closed closer',
      (tester) async {
    await _openFixture(tester, TargetPlatform.linux, '');
    await _typeCharacter(tester, '(');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyX, character: 'x');
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: '(x)',
      selection: TextSelection.collapsed(offset: 2),
    ));
    await tester.pump();
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyX);
    expect(_controller(tester).text, '(x)');
    await _typeCharacter(tester, ')');
    expect(_controller(tester).text, '(x)');
    expect(
      _controller(tester).selection,
      const TextSelection.collapsed(offset: 3),
    );
  });

  platformTest('Rust does not overtype a literal closer from the source',
      (tester) async {
    await _openFixture(tester, TargetPlatform.linux, ')');
    _controller(tester).selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();

    await _typeCharacter(tester, ')');
    expect(_controller(tester).text, '))');
  });

  platformTest('Rust opener before a non-closing boundary stays unpaired',
      (tester) async {
    await _openFixture(tester, TargetPlatform.linux, 'value');
    _controller(tester).selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();

    await _typeCharacter(tester, '(');
    expect(_controller(tester).text, '(value');
    expect(
      _controller(tester).selection,
      const TextSelection.collapsed(offset: 1),
    );
  });

  platformTest('Rust bracket edits synchronize split views and save',
      (tester) async {
    const source = 'value';
    final (_, file) = await _openFixture(tester, TargetPlatform.linux, source);
    await tester.tap(find.byTooltip('拆分编辑器').first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('sample.rs').first);
    await tester.pump(const Duration(milliseconds: 300));
    final fields = find.byType(RustTextInputField);
    expect(fields, findsNWidgets(2));
    await tester.showKeyboard(
      find.descendant(
        of: fields.at(1),
        matching: find.byType(TextField),
      ),
    );
    _controller(tester, index: 1).selection =
        const TextSelection.collapsed(offset: source.length);
    await tester.pump();

    await _typeCharacter(tester, '{');
    const edited = 'value{}';
    final views = tester.widgetList<RustTextInputField>(fields).toList();
    expect(views[0].inputWindow.initialValue.text, edited);
    expect(views[1].inputWindow.initialValue.text, edited);
    await _press(tester, LogicalKeyboardKey.keyS, control: true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(file.readAsStringSync(), edited);
  });

  platformTest('Rust bracket input leaves plaintext files unchanged',
      (tester) async {
    await _openFixture(
      tester,
      TargetPlatform.linux,
      '',
      extension: 'txt',
    );
    await _typeCharacter(tester, '(');
    expect(_controller(tester).text, '');
  });

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    platformTest('$platform Rust double quotes auto-close and overtype',
        (tester) async {
      final (_, file) = await _openFixture(tester, platform, '');

      await _typeCharacter(tester, '"');
      expect(_controller(tester).text, '""');
      expect(
        _controller(tester).selection,
        const TextSelection.collapsed(offset: 1),
      );

      await _typeCharacter(tester, '"');
      expect(_controller(tester).text, '""');
      expect(
        _controller(tester).selection,
        const TextSelection.collapsed(offset: 2),
      );
      await _press(tester, LogicalKeyboardKey.keyS, control: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(file.readAsStringSync(), '""');
      await _press(tester, LogicalKeyboardKey.keyZ, control: true);
      expect(_controller(tester).text, '');
      await _press(tester, LogicalKeyboardKey.keyY, control: true);
      expect(_controller(tester).text, '""');
    });
  }

  platformTest('Rust quote pairing is disabled inside string tokens',
      (tester) async {
    await _openFixture(tester, TargetPlatform.linux, 'let s = "text";');
    _controller(tester).selection = const TextSelection.collapsed(offset: 10);
    await tester.pump(const Duration(milliseconds: 100));

    await _typeCharacter(tester, '"');
    expect(_controller(tester).text, 'let s = "t"ext";');
  });

  platformTest('Rust quotes surround a selection using UTF-16 TextOps',
      (tester) async {
    final (_, file) = await _openFixture(
      tester,
      TargetPlatform.linux,
      '\uFEFF😀\r\n',
    );
    _controller(tester).selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 2,
    );
    await tester.pump();

    await _typeCharacter(tester, '"');
    expect(_controller(tester).text, '"😀"\n');
    expect(
      _controller(tester).selection,
      const TextSelection(baseOffset: 1, extentOffset: 3),
    );
    await _press(tester, LogicalKeyboardKey.keyS, control: true);
    await tester.pump(const Duration(milliseconds: 100));
    final bytes = file.readAsBytesSync();
    expect(bytes.take(3).toList(), [0xef, 0xbb, 0xbf]);
    expect(utf8.decode(bytes.skip(3).toList()), '"😀"\r\n');
  });

  platformTest('Rust Backspace removes its auto-closed quote pair once',
      (tester) async {
    await _openFixture(tester, TargetPlatform.linux, '');
    await _typeCharacter(tester, '"');
    expect(_controller(tester).text, '""');

    await _press(tester, LogicalKeyboardKey.backspace);
    expect(_controller(tester).text, '');
  });
}
