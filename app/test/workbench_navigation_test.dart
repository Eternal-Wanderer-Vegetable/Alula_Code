import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/rendering.dart' show RenderEditable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

RenderEditable _findRenderEditable(RenderObject root) {
  if (root is RenderEditable) return root;
  RenderEditable? found;
  root.visitChildren((child) {
    found ??= _findRenderEditable(child);
  });
  return found ?? (throw StateError('No RenderEditable under test editor'));
}

void main() {
  testWidgets('F12 goes to a same-file Rust definition and reports misses',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-nav');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) await temp.delete(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    const source =
        '\uFEFF// 🦊 navigation fixture\r\nfn target() {}\r\nfn 目标() {}\r\nfn f() {}\r\nfn main() {\r\n    target();\r\n    目标();\r\n    f();\r\n    missing();\r\n}\r\n';
    const normalizedSource =
        '// 🦊 navigation fixture\nfn target() {}\nfn 目标() {}\nfn f() {}\nfn main() {\n    target();\n    目标();\n    f();\n    missing();\n}\n';
    File('${workspace.path}/main.rs').writeAsStringSync(source);
    final base = temp.path.replaceAll(r'\', '/');

    await tester.pumpWidget(AlulaApp(
      autoFolder: workspace.path,
      layoutStore: LayoutStore(path: '$base/layout.json'),
      sessionStore: SessionStore(path: '$base/session.json'),
      keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('main.rs').first);
    await tester.pump(const Duration(milliseconds: 300));

    final editor = find.byType(RustTextInputField);
    expect(editor, findsOneWidget);
    final textFieldFinder = find.descendant(
      of: editor,
      matching: find.byType(TextField),
    );
    await tester.tap(textFieldFinder);
    await tester.pump();
    final controller = tester.widget<TextField>(textFieldFinder).controller!;
    final definitionOffset = normalizedSource.indexOf('target()');
    final unicodeDefinitionOffset = normalizedSource.indexOf('目标()');
    final oneLetterDefinitionOffset = normalizedSource.indexOf('f()');
    final callOffset = normalizedSource.indexOf(
      'target();',
      normalizedSource.indexOf('fn main'),
    );

    controller.selection = TextSelection.collapsed(offset: callOffset);
    await tester.pump();
    expect(
      controller.selection.extentOffset,
      callOffset,
      reason: 'the call-site caret must reach the editor before F12',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('跳转到 target'), findsOneWidget);
    final selectionAfterJump =
        tester.widget<TextField>(textFieldFinder).controller!.selection;
    expect(
      selectionAfterJump.extentOffset,
      definitionOffset,
      reason: 'F12 from the call site must select the local Rust definition',
    );

    final controllerAfterJump =
        tester.widget<TextField>(textFieldFinder).controller!;
    controllerAfterJump.selection = TextSelection.collapsed(
      offset: normalizedSource.indexOf(
        '目标();',
        normalizedSource.indexOf('fn main'),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('跳转到 目标'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(textFieldFinder)
          .controller!
          .selection
          .extentOffset,
      unicodeDefinitionOffset,
      reason: 'F12 must resolve a Rust identifier containing Unicode XID chars',
    );

    final controllerAfterUnicodeJump =
        tester.widget<TextField>(textFieldFinder).controller!;
    controllerAfterUnicodeJump.selection = TextSelection.collapsed(
      offset: normalizedSource.indexOf(
        'f();',
        normalizedSource.indexOf('fn main'),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('跳转到 f'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(textFieldFinder)
          .controller!
          .selection
          .extentOffset,
      oneLetterDefinitionOffset,
      reason: 'definition search must match the identifier boundary, not `fn`',
    );

    final controllerAfterOneLetterJump =
        tester.widget<TextField>(textFieldFinder).controller!;
    controllerAfterOneLetterJump.selection = TextSelection.collapsed(
      offset: normalizedSource.indexOf('missing()'),
    );
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 200));
    final quickInput = find.byKey(const ValueKey('quick-input'));
    await tester.enterText(
      find.descendant(of: quickInput, matching: find.byType(TextField)),
      '跳转定义',
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('qi-编辑器: 跳转定义')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('未找到「missing」的定义'), findsOneWidget);

    final controllerAfterMiss =
        tester.widget<TextField>(textFieldFinder).controller!;
    controllerAfterMiss.selection =
        const TextSelection.collapsed(offset: normalizedSource.length);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('光标不在符号上'), findsOneWidget);
  });

  testWidgets('Control-click and Command-click jump to a Rust definition',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-pointer-nav');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) await temp.delete(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    const source =
        '// 🦊 pointer fixture\nfn target() {}\nfn main() {\n    target();\n}\n';
    File('${workspace.path}/main.rs').writeAsStringSync(source);
    final base = temp.path.replaceAll(r'\', '/');

    await tester.pumpWidget(AlulaApp(
      autoFolder: workspace.path,
      layoutStore: LayoutStore(path: '$base/layout.json'),
      sessionStore: SessionStore(path: '$base/session.json'),
      keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('main.rs').first);
    await tester.pump(const Duration(milliseconds: 300));

    final editor = find.byType(RustTextInputField);
    final textFieldFinder = find.descendant(
      of: editor,
      matching: find.byType(TextField),
    );
    await tester.tap(textFieldFinder);
    await tester.pump();
    final editableFinder = find.descendant(
      of: editor,
      matching: find.byType(EditableText),
    );
    final callOffset = source.indexOf(
      'target();',
      source.indexOf('fn main'),
    );
    final definitionOffset = source.indexOf('target()');

    Future<void> jumpWith(LogicalKeyboardKey modifier) async {
      final controller = tester.widget<TextField>(textFieldFinder).controller!;
      controller.selection = TextSelection.collapsed(offset: callOffset);
      await tester.pump();
      expect(controller.selection.extentOffset, callOffset);
      final render = _findRenderEditable(
        tester.renderObject<RenderObject>(editableFinder),
      );
      final caret = render.getLocalRectForCaret(
        TextPosition(offset: callOffset + 3),
      );
      final point = render.localToGlobal(caret.center);
      final hitOffset = render.getPositionForPoint(point).offset;
      expect(hitOffset, inInclusiveRange(callOffset, callOffset + 6));
      await tester.sendKeyDownEvent(modifier);
      expect(
        modifier == LogicalKeyboardKey.controlLeft
            ? HardwareKeyboard.instance.isControlPressed
            : HardwareKeyboard.instance.isMetaPressed,
        isTrue,
      );
      await tester.tapAt(point);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester
            .widget<TextField>(textFieldFinder)
            .controller!
            .selection
            .extentOffset,
        definitionOffset,
      );
    }

    await jumpWith(LogicalKeyboardKey.controlLeft);
    await jumpWith(LogicalKeyboardKey.metaLeft);
  });

  testWidgets('Control-click maps a bounded input window to document offsets',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-pointer-window');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) await temp.delete(recursive: true);
    });
    final workspace = Directory('${temp.path}/workspace')..createSync();
    final padding = List.filled(6000, '// filler 🦊\n').join();
    final source = '// header 🦊\nfn target() {}\n$padding'
        'fn main() {\n    target();\n}\n';
    File('${workspace.path}/main.rs').writeAsStringSync(source);
    final base = temp.path.replaceAll(r'\', '/');

    await tester.pumpWidget(AlulaApp(
      autoFolder: workspace.path,
      layoutStore: LayoutStore(path: '$base/layout.json'),
      sessionStore: SessionStore(path: '$base/session.json'),
      keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('main.rs').first);
    await tester.pump(const Duration(milliseconds: 300));

    final editor = find.byType(RustTextInputField);
    final textFieldFinder = find.descendant(
      of: editor,
      matching: find.byType(TextField),
    );
    await tester.tap(textFieldFinder);
    await tester.pump();
    final definitionOffset = source.indexOf('target()');
    final callOffset = source.lastIndexOf('target();');
    var field = tester.widget<RustTextInputField>(editor);
    var controller = tester.widget<TextField>(textFieldFinder).controller!;
    for (var attempt = 0; attempt < 8; attempt++) {
      field = tester.widget<RustTextInputField>(editor);
      controller = tester.widget<TextField>(textFieldFinder).controller!;
      final windowStart = field.inputWindow.startUtf16;
      final previousWindowEnd = windowStart + controller.text.length;
      if (callOffset >= windowStart && callOffset + 7 <= previousWindowEnd) {
        break;
      }
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
      await tester.pump();
      await tester.pump();
      field = tester.widget<RustTextInputField>(editor);
      controller = tester.widget<TextField>(textFieldFinder).controller!;
      expect(
        field.inputWindow.startUtf16 + controller.text.length,
        greaterThan(previousWindowEnd),
        reason: 'moving the caret to the bounded edge should rebase forward',
      );
    }

    field = tester.widget<RustTextInputField>(editor);
    controller = tester.widget<TextField>(textFieldFinder).controller!;
    expect(field.inputWindow.startUtf16, greaterThan(0));
    final localCallOffset = callOffset - field.inputWindow.startUtf16;
    expect(localCallOffset, inInclusiveRange(0, controller.text.length - 1));
    controller.selection = TextSelection.collapsed(offset: localCallOffset);
    await tester.pump();

    field = tester.widget<RustTextInputField>(editor);
    controller = tester.widget<TextField>(textFieldFinder).controller!;
    final scrollController = field.scrollController!;
    if (scrollController.hasClients) {
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      await tester.pump();
    }
    field = tester.widget<RustTextInputField>(editor);
    final editableFinder = find.descendant(
      of: editor,
      matching: find.byType(EditableText),
    );
    final render = _findRenderEditable(
      tester.renderObject<RenderObject>(editableFinder),
    );
    final caret = render.getLocalRectForCaret(
      TextPosition(offset: localCallOffset + 3),
    );
    final point = render.localToGlobal(caret.center);
    expect(tester.getRect(editor).contains(point), isTrue);
    expect(
      render.getPositionForPoint(point).offset,
      inInclusiveRange(localCallOffset, localCallOffset + 6),
    );
    final absoluteWindowStart = field.inputWindow.startUtf16;
    expect(absoluteWindowStart, greaterThan(0));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tapAt(point);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    final navigatedController =
        tester.widget<TextField>(textFieldFinder).controller!;
    expect(navigatedController.selection.extentOffset, definitionOffset);
  });
}
