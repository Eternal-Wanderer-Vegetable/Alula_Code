import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('multi-selection copy/cut writes clipboard and Rust once',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-multicursor-clip');
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    final file = File('${workspace.path}/sample.txt')
      ..writeAsStringSync('foo foo');
    final base = temp.path.replaceAll(r'\', '/');
    Map<dynamic, dynamic> clipboard = const {};
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = Map<dynamic, dynamic>.from(call.arguments as Map);
        }
        if (call.method == 'Clipboard.getData') return clipboard;
        return null;
      },
    );
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
    tester.widget<TextField>(editor).controller!.selection =
        const TextSelection(baseOffset: 0, extentOffset: 3);
    await tester.pump();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(clipboard['text'], 'foo\nfoo');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();
    expect(tester.widget<TextField>(editor).controller!.text, ' ');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(file.readAsStringSync(), ' ');
  });

  testWidgets('Ctrl+V distributes copied lines and saves the Rust document',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-multicursor-paste');
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    final file = File('${workspace.path}/sample.txt')
      ..writeAsStringSync('foo x foo');
    final base = temp.path.replaceAll(r'\', '/');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData'
          ? <String, Object?>{'text': 'left\r\nright'}
          : null,
    );
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
    tester.widget<TextField>(editor).controller!.selection =
        const TextSelection(baseOffset: 0, extentOffset: 3);
    await tester.pump();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();
    expect(tester.widget<TextField>(editor).controller!.text, 'left x right');
    final field =
        tester.widget<RustTextInputField>(find.byType(RustTextInputField));
    expect(field.additionalSelections,
        const [TextSelection.collapsed(offset: 12)]);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(file.readAsStringSync(), 'left x right');
  });

  testWidgets('Ctrl+D adds an occurrence and typing updates both Rust ranges',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-multicursor');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    final file = File('${workspace.path}/sample.txt')
      ..writeAsStringSync('foo foo');
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
    var textField = tester.widget<TextField>(editor);
    textField.controller!.selection =
        const TextSelection(baseOffset: 0, extentOffset: 3);
    await tester.pump();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();

    var field =
        tester.widget<RustTextInputField>(find.byType(RustTextInputField));
    expect(field.additionalSelections, const [
      TextSelection(baseOffset: 4, extentOffset: 7),
    ]);

    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: 'bar foo',
      selection: TextSelection.collapsed(offset: 3),
    ));
    await tester.pump();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(file.readAsStringSync(), 'bar bar');
    field = tester.widget<RustTextInputField>(find.byType(RustTextInputField));
    expect(
        field.additionalSelections, const [TextSelection.collapsed(offset: 7)]);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    field = tester.widget<RustTextInputField>(find.byType(RustTextInputField));
    expect(field.additionalSelections, isEmpty);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    field = tester.widget<RustTextInputField>(find.byType(RustTextInputField));
    expect(
        field.additionalSelections, const [TextSelection.collapsed(offset: 7)]);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(tester.widget<TextField>(editor).controller!.text, 'foo foo');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(tester.widget<TextField>(editor).controller!.text, 'bar bar');
  });

  testWidgets('Alt+Shift+Down edits a CRLF file at each column caret',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-columnselect');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    File('${workspace.path}/sample.txt').writeAsStringSync('ab\r\ncd\r\nef');
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
    controller.selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    await tester.pump();

    final field =
        tester.widget<RustTextInputField>(find.byType(RustTextInputField));
    expect(
        field.additionalSelections, const [TextSelection.collapsed(offset: 1)]);
    expect(controller.selection, const TextSelection.collapsed(offset: 4));

    tester.testTextInput.updateEditingValue(TextEditingValue(
      text: controller.text.replaceRange(4, 4, 'X'),
      selection: const TextSelection.collapsed(offset: 5),
    ));
    await tester.pump();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(File('${workspace.path}/sample.txt').readAsStringSync(),
        'aXb\r\ncXd\r\nef');
  });

  testWidgets('secondary occurrence follows IME preedit and commits to Rust',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-multicursor-ime');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    final file = File('${workspace.path}/sample.txt')
      ..writeAsStringSync('ni ni');
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
    tester.widget<TextField>(editor).controller!.selection =
        const TextSelection(baseOffset: 0, extentOffset: 2);
    await tester.pump();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: 'bei ni',
      selection: TextSelection.collapsed(offset: 3),
      composing: TextRange(start: 0, end: 3),
    ));
    await tester.pump();
    expect(file.readAsStringSync(), 'ni ni');
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: '北 ni',
      selection: TextSelection.collapsed(offset: 1),
      composing: TextRange.empty,
    ));
    await tester.pump();
    await tester.pump();

    expect(file.readAsStringSync(), 'ni ni');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(file.readAsStringSync(), '北 北');
    final field =
        tester.widget<RustTextInputField>(find.byType(RustTextInputField));
    expect(
        field.additionalSelections, const [TextSelection.collapsed(offset: 3)]);
  });

  testWidgets('selection sets remain independent when switching document tabs',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-selection-tabs');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    File('${workspace.path}/first.txt').writeAsStringSync('foo foo');
    File('${workspace.path}/second.txt').writeAsStringSync('bar bar');
    final base = temp.path.replaceAll(r'\', '/');
    await tester.pumpWidget(AlulaApp(
      autoFolder: workspace.path,
      layoutStore: LayoutStore(path: '$base/layout.json'),
      sessionStore: SessionStore(path: '$base/session.json'),
      keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('first.txt').first);
    await tester.pump(const Duration(milliseconds: 300));
    final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
    await tester.showKeyboard(editor);
    await tester.pump();
    tester.widget<TextField>(editor).controller!.selection =
        const TextSelection(baseOffset: 0, extentOffset: 3);
    await tester.pump();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    await tester.tap(find.text('second.txt').first);
    await tester.pump(const Duration(milliseconds: 300));
    final secondField = tester.widget<RustTextInputField>(
      find.byType(RustTextInputField),
    );
    expect(secondField.additionalSelections, isEmpty);
    final secondEditor = find.byKey(const ValueKey('rust-bounded-text-input'));
    await tester.showKeyboard(secondEditor);
    await tester.pump();
    tester.widget<TextField>(secondEditor).controller!.selection =
        const TextSelection(baseOffset: 0, extentOffset: 3);
    await tester.pump();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    final secondSelections = tester
        .widget<RustTextInputField>(find.byType(RustTextInputField))
        .additionalSelections;
    expect(secondSelections,
        const [TextSelection(baseOffset: 4, extentOffset: 7)]);

    await tester.tap(find.text('first.txt').last);
    await tester.pump();
    final firstSelections = tester
        .widget<RustTextInputField>(find.byType(RustTextInputField))
        .additionalSelections;
    expect(
        firstSelections, const [TextSelection(baseOffset: 4, extentOffset: 7)]);
    await tester.tap(find.text('second.txt').last);
    await tester.pump();
    expect(
      tester
          .widget<RustTextInputField>(find.byType(RustTextInputField))
          .additionalSelections,
      secondSelections,
    );
  });
}
