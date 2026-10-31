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
  final temp = Directory.systemTemp.createTempSync('alula-bracket-delete');
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

Future<void> _type(WidgetTester tester, String character) async {
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
    platformTest('$platform Backspace removes Rust auto-closed pair once',
        (tester) async {
      final (_, file) = await _openFixture(tester, platform, '');
      await _type(tester, '(');
      expect(_controller(tester).text, '()');
      expect(
        _controller(tester).selection,
        const TextSelection.collapsed(offset: 1),
      );

      await _press(tester, LogicalKeyboardKey.backspace);
      expect(_controller(tester).text, '');
      expect(
        _controller(tester).selection,
        const TextSelection.collapsed(offset: 0),
      );
      await _press(tester, LogicalKeyboardKey.keyZ, control: true);
      expect(_controller(tester).text, '()');
      await _press(tester, LogicalKeyboardKey.keyY, control: true);
      expect(_controller(tester).text, '');
      await _press(tester, LogicalKeyboardKey.keyS, control: true);
      expect(file.readAsStringSync(), '');
    });
  }

  platformTest('Backspace only removes the opener of a literal Rust pair',
      (tester) async {
    await _openFixture(tester, TargetPlatform.linux, '()');
    _controller(tester).selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();

    await _press(tester, LogicalKeyboardKey.backspace);
    expect(_controller(tester).text, ')');
    expect(
      _controller(tester).selection,
      const TextSelection.collapsed(offset: 0),
    );
  });

  platformTest('Backspace removes each Rust bracket pair type', (tester) async {
    await _openFixture(tester, TargetPlatform.linux, '');
    for (final (open, pair) in [
      ('(', '()'),
      ('[', '[]'),
      ('{', '{}'),
    ]) {
      await _type(tester, open);
      expect(_controller(tester).text, pair);
      await _press(tester, LogicalKeyboardKey.backspace);
      expect(_controller(tester).text, '');
    }
  });

  platformTest('Backspace first removes inner text before the tracked pair',
      (tester) async {
    await _openFixture(tester, TargetPlatform.linux, '');
    await _type(tester, '(');
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: '(x)',
      selection: TextSelection.collapsed(offset: 2),
    ));
    await tester.pump();
    await tester.pump();
    expect(_controller(tester).text, '(x)');

    await _press(tester, LogicalKeyboardKey.backspace);
    expect(_controller(tester).text, '()');
    await _press(tester, LogicalKeyboardKey.backspace);
    expect(_controller(tester).text, '');
  });

  platformTest('Backspace removes each matching pair at multiple cursors',
      (tester) async {
    await _openFixture(tester, TargetPlatform.linux, 'a\nb');
    _controller(tester).selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    await _type(tester, '(');
    expect(_controller(tester).text, 'a()\nb()');
    await _press(tester, LogicalKeyboardKey.backspace);
    expect(_controller(tester).text, 'a\nb');
    final doc = tester
        .widget<RustTextInputField>(find.byType(RustTextInputField))
        .inputWindow
        .document
        .resync();
    expect(doc.content, 'a\nb');
    await _press(tester, LogicalKeyboardKey.keyZ, control: true);
    expect(_controller(tester).text, 'a()\nb()');
  });

  platformTest('Backspace synchronizes paired deletion across split views',
      (tester) async {
    final (_, file) = await _openFixture(tester, TargetPlatform.linux, '');
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
    await _type(tester, '(');
    await _press(tester, LogicalKeyboardKey.backspace);

    for (final field in tester.widgetList<RustTextInputField>(fields)) {
      expect(field.inputWindow.initialValue.text, '');
    }
    await _press(tester, LogicalKeyboardKey.keyS, control: true);
    expect(file.readAsStringSync(), '');
  });

  platformTest('non-Rust Backspace keeps ordinary single-character behavior',
      (tester) async {
    await _openFixture(tester, TargetPlatform.linux, '()', extension: 'txt');
    _controller(tester).selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();

    await _press(tester, LogicalKeyboardKey.backspace);
    expect(_controller(tester).text, ')');
  });
}
