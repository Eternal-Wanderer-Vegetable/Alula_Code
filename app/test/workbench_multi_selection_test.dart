import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/editor/occurrence_search.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/rendering.dart' show RenderEditable, RenderObject;
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

  testWidgets('Alt+Click adds a cursor at the hit-tested UTF-16 position',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-alt-click-cursor');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    File('${workspace.path}/sample.txt').writeAsStringSync('alpha beta');
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
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();

    final editableRoot = tester.renderObject<RenderObject>(
      find.descendant(of: editor, matching: find.byType(EditableText)),
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
    const targetOffset = 6;
    final caretRect = editable.getLocalRectForCaret(
      const TextPosition(offset: targetOffset),
    );
    final localClick = Offset(caretRect.left + 0.1, caretRect.center.dy);
    final globalClick = editable.localToGlobal(localClick);
    expect(editable.getPositionForPoint(globalClick).offset, targetOffset);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.tapAt(globalClick, kind: PointerDeviceKind.mouse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    await tester.pump();

    final field =
        tester.widget<RustTextInputField>(find.byType(RustTextInputField));
    expect(field.additionalSelections,
        const [TextSelection.collapsed(offset: targetOffset)]);
    expect(controller.selection, const TextSelection.collapsed(offset: 0));
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

  testWidgets('Ctrl+K Ctrl+D moves the last selected occurrence forward',
      (tester) async {
    final temp =
        Directory.systemTemp.createTempSync('alula-move-last-occurrence');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    File('${workspace.path}/sample.txt').writeAsStringSync('foo foo foo foo');
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
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
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

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();

    field = tester.widget<RustTextInputField>(find.byType(RustTextInputField));
    expect(controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 3));
    expect(field.additionalSelections, const [
      TextSelection(baseOffset: 8, extentOffset: 11),
    ]);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    field = tester.widget<RustTextInputField>(find.byType(RustTextInputField));
    expect(field.additionalSelections, const [
      TextSelection(baseOffset: 4, extentOffset: 7),
    ]);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    field = tester.widget<RustTextInputField>(find.byType(RustTextInputField));
    expect(field.additionalSelections, const [
      TextSelection(baseOffset: 8, extentOffset: 11),
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ctrl+D finds and reveals an occurrence outside the input window',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-multicursor-range');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    const prefix = 'foo';
    const gapLength = 17000;
    final fileText = '$prefix${'x' * gapLength}foo';
    final file = File('${workspace.path}/sample.txt')
      ..writeAsStringSync(fileText);
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
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
    await tester.pump();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();

    final field =
        tester.widget<RustTextInputField>(find.byType(RustTextInputField));
    final selected = controller.selection;
    expect(field.inputWindow.startUtf16, greaterThan(0));
    expect(field.inputWindow.startUtf16 + selected.baseOffset,
        fileText.lastIndexOf('foo'));
    expect(
        field.inputWindow.startUtf16 + selected.extentOffset, fileText.length);

    final localText = controller.text;
    const replacement = 'a👩‍💻';
    final replacedText =
        localText.replaceRange(selected.start, selected.end, replacement);
    tester.testTextInput.updateEditingValue(TextEditingValue(
      text: replacedText,
      selection:
          TextSelection.collapsed(offset: selected.start + replacement.length),
    ));
    await tester.pump();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
        file.readAsStringSync(), '$replacement${'x' * gapLength}$replacement');

    await tester.pump(const Duration(milliseconds: 500));
    final caret = controller.selection.extentOffset;
    final deleteStart = caret - '👩‍💻'.length;
    final afterBackspace = controller.text.replaceRange(deleteStart, caret, '');
    tester.testTextInput.updateEditingValue(TextEditingValue(
      text: afterBackspace,
      selection: TextSelection.collapsed(offset: deleteStart),
    ));
    await tester.pump();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(file.readAsStringSync(), 'a${'x' * gapLength}a');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
        file.readAsStringSync(), '$replacement${'x' * gapLength}$replacement');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(file.readAsStringSync(), fileText);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(file.readAsStringSync(), 'a${'x' * gapLength}a');
  });

  testWidgets('Ctrl+D ignores a selection that splits an emoji surrogate pair',
      (tester) async {
    final temp =
        Directory.systemTemp.createTempSync('alula-multicursor-surrogate');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    File('${workspace.path}/sample.txt').writeAsStringSync('a😀b 😀');
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
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 2);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('先选择要匹配的文本'), findsOneWidget);
  });

  testWidgets('Ctrl+Shift+L respects the VS Code multi-cursor limit',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-multicursor-limit');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    File('${workspace.path}/sample.txt').writeAsStringSync('a' * 10001);
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
        const TextSelection(baseOffset: 0, extentOffset: 1);
    await tester.pump();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    final field =
        tester.widget<RustTextInputField>(find.byType(RustTextInputField));
    expect(field.additionalSelections, hasLength(defaultMultiCursorLimit - 1));
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
