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
  final temp = Directory.systemTemp.createTempSync('alula-smart-enter');
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

Future<void> _typeCharacter(WidgetTester tester, String character) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: character);
  await tester.pump();
  await tester.pump();
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

Future<void> _typeTextAtSelection(
  WidgetTester tester,
  String text, {
  int index = 0,
}) async {
  final controller = _controller(tester, index: index);
  final selection = controller.selection;
  final updated = controller.text.replaceRange(
    selection.start,
    selection.end,
    text,
  );
  tester.testTextInput.updateEditingValue(TextEditingValue(
    text: updated,
    selection: TextSelection.collapsed(offset: selection.start + text.length),
  ));
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
      '$platform Enter expands an auto-inserted Rust brace pair and is undoable',
      (tester) async {
        const prefix = 'fn main() ';
        await _openFixture(tester, platform, prefix);
        _controller(tester).selection =
            const TextSelection.collapsed(offset: prefix.length);
        await tester.pump();

        await _typeCharacter(tester, '{');
        expect(_controller(tester).text, 'fn main() {}');
        await _press(tester, LogicalKeyboardKey.enter);

        const expanded = 'fn main() {\n    \n}';
        expect(_controller(tester).text, expanded);
        expect(
          _controller(tester).selection,
          const TextSelection.collapsed(offset: 16),
        );
        expect(
          tester
              .widget<RustTextInputField>(find.byType(RustTextInputField))
              .inputWindow
              .document
              .resync()
              .content,
          expanded,
        );

        await _press(
          tester,
          LogicalKeyboardKey.keyZ,
          control: !isMac,
          meta: isMac,
        );
        expect(_controller(tester).text, 'fn main() {}');
        await _press(
          tester,
          LogicalKeyboardKey.keyZ,
          control: !isMac,
          meta: isMac,
          shift: true,
        );
        expect(_controller(tester).text, expanded);
        expect(
          _controller(tester).selection,
          const TextSelection.collapsed(offset: 16),
        );
      },
    );
  }

  for (final pair in <List<String>>[
    ['(', ')'],
    ['[', ']'],
  ]) {
    for (final platform in [
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    ]) {
      final isMac = platform == TargetPlatform.macOS;
      platformTest(
        '$platform Enter expands an auto-inserted Rust ${pair[0]}${pair[1]} pair',
        (tester) async {
          await _openFixture(tester, platform, '');
          await _typeCharacter(tester, pair[0]);
          expect(_controller(tester).text, '${pair[0]}${pair[1]}');

          await _press(tester, LogicalKeyboardKey.enter);

          final expanded = '${pair[0]}\n    \n${pair[1]}';
          expect(_controller(tester).text, expanded);
          expect(
            _controller(tester).selection,
            const TextSelection.collapsed(offset: 6),
          );
          await _press(
            tester,
            LogicalKeyboardKey.keyZ,
            control: !isMac,
            meta: isMac,
          );
          expect(_controller(tester).text, '${pair[0]}${pair[1]}');
          await _press(
            tester,
            LogicalKeyboardKey.keyZ,
            control: !isMac,
            meta: isMac,
            shift: true,
          );
          expect(_controller(tester).text, expanded);
        },
      );
    }
  }

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    final isMac = platform == TargetPlatform.macOS;
    platformTest(
      '$platform Enter continues a Rust line comment before remaining text',
      (tester) async {
        const source = '    // leftright';
        await _openFixture(tester, platform, source);
        _controller(tester).selection =
            TextSelection.collapsed(offset: source.indexOf('right'));
        await tester.pump();

        await _press(tester, LogicalKeyboardKey.enter);

        const expected = '    // left\n    // right';
        expect(_controller(tester).text, expected);
        expect(
          _controller(tester).selection,
          TextSelection.collapsed(offset: expected.indexOf('right')),
        );
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
        expect(_controller(tester).text, expected);
      },
    );
  }

  platformTest(
    'Rust Enter continues an inline line comment using its second rule',
    (tester) async {
      const source = 'let x = 1; // leftright';
      await _openFixture(tester, TargetPlatform.linux, source);
      _controller(tester).selection =
          TextSelection.collapsed(offset: source.indexOf('right'));
      await tester.pump();

      await _press(tester, LogicalKeyboardKey.enter);

      expect(_controller(tester).text, 'let x = 1; // left\n// right');
    },
  );

  platformTest(
    'Rust line-comment Enter rule takes priority over an auto-closed brace',
    (tester) async {
      const source = '// ';
      await _openFixture(tester, TargetPlatform.linux, source);
      _controller(tester).selection =
          const TextSelection.collapsed(offset: source.length);
      await tester.pump();
      await _typeCharacter(tester, '{');
      expect(_controller(tester).text, '// {}');

      await _press(tester, LogicalKeyboardKey.enter);

      expect(_controller(tester).text, '// {\n// }');
    },
  );

  platformTest(
    'Rust Enter only continues a line comment when afterText has content',
    (tester) async {
      const source = '// left';
      await _openFixture(tester, TargetPlatform.linux, source);
      _controller(tester).selection =
          const TextSelection.collapsed(offset: source.length);
      await tester.pump();

      await _press(tester, LogicalKeyboardKey.enter);

      expect(_controller(tester).text, '$source\n');
    },
  );

  platformTest(
    'Rust comment continuation keeps a selected-text Enter on the fallback path',
    (tester) async {
      const source = '// leftright';
      await _openFixture(tester, TargetPlatform.linux, source);
      _controller(tester).selection = const TextSelection(
        baseOffset: 7,
        extentOffset: 8,
      );
      await tester.pump();

      await _press(tester, LogicalKeyboardKey.enter);

      expect(_controller(tester).text, '// left\night');
    },
  );

  platformTest(
    'Rust smart Enter edits the second view and saves the supplied sample',
    (tester) async {
      const prefix = 'fn main() ';
      final (_, file) =
          await _openFixture(tester, TargetPlatform.linux, prefix);
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
      _controller(tester, index: 1).selection =
          const TextSelection.collapsed(offset: prefix.length);
      await tester.pump();

      await _typeCharacter(tester, '{');
      await _press(tester, LogicalKeyboardKey.enter);
      await _typeTextAtSelection(tester, 'println!("linux-save-ok");',
          index: 1);

      const expected = 'fn main() {\n    println!("linux-save-ok");\n}';
      final views = tester.widgetList<RustTextInputField>(fields).toList();
      expect(views[0].inputWindow.initialValue.text, expected);
      expect(views[1].inputWindow.initialValue.text, expected);
      await _press(tester, LogicalKeyboardKey.keyS, control: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(file.readAsStringSync(), expected);
    },
  );

  platformTest(
    'Rust Enter does not treat an untracked source brace pair as auto-inserted',
    (tester) async {
      const source = 'fn main() {}';
      await _openFixture(tester, TargetPlatform.linux, source);
      _controller(tester).selection =
          const TextSelection.collapsed(offset: source.length - 1);
      await tester.pump();

      await _press(tester, LogicalKeyboardKey.enter);

      expect(_controller(tester).text, 'fn main() {\n}');
    },
  );
}
