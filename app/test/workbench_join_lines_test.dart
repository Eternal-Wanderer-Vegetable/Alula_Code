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

Future<void> _invokeJoinLines(
  WidgetTester tester,
  TargetPlatform platform,
) async {
  if (platform == TargetPlatform.macOS) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 100));
    return;
  }

  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump(const Duration(milliseconds: 100));
  final palette = find.byType(TextField).last;
  await tester.enterText(palette, '合并行');
  await tester.pump(const Duration(milliseconds: 100));
  final command = find.text('编辑器: 合并行');
  expect(command, findsOneWidget);
  await tester.tap(command);
  await tester.pump(const Duration(milliseconds: 120));
}

Future<void> _pressHistory(
  WidgetTester tester,
  TargetPlatform platform, {
  required bool redo,
}) async {
  final primary = platform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(primary);
  if (redo) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
  if (redo) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(primary);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _pressSelectNextOccurrence(
  WidgetTester tester,
  TargetPlatform platform,
) async {
  final primary = platform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(primary);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
  await tester.sendKeyUpEvent(primary);
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
    testWidgets('$platform joins selected lines with Rust undo and save',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(1200, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final temp = Directory.systemTemp.createTempSync('alula-line-join');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });
      final workspace = Directory('${temp.path}/workspace')..createSync();
      const source = 'fn main() {\n'
          '    println!("linux-save-ok");\n'
          '}\n'
          'hello \n'
          '    world\n'
          '\n'
          'pair\n'
          '    alpha\n'
          '\n'
          'pair\n'
          '    beta\n'
          'tail';
      final file = File('${workspace.path}/main.rs')
        ..writeAsBytesSync([
          0xef,
          0xbb,
          0xbf,
          ...utf8.encode(source.replaceAll('\n', '\r\n')),
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
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('拆分编辑器').first);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('main.rs').first);
      await tester.pump(const Duration(milliseconds: 300));

      final fields = find.byType(RustTextInputField);
      expect(fields, findsNWidgets(2));
      Finder textFieldAt(int index) => find.descendant(
            of: fields.at(index),
            matching: find.byType(TextField),
          );
      final firstField = textFieldAt(0);
      await tester.tap(firstField);
      await tester.showKeyboard(firstField);
      final controller = tester.widget<TextField>(firstField).controller!;
      var views = tester.widgetList<RustTextInputField>(fields).toList();
      expect(views.first.inputWindow.document.id,
          views.last.inputWindow.document.id);
      expect(controller.text, source);

      final firstLineEnd = source.indexOf('\n');
      controller.selection = TextSelection.collapsed(offset: firstLineEnd);
      await tester.pump();
      await _invokeJoinLines(tester, platform);
      final afterFirstJoin = source.replaceFirst(
        'fn main() {\n    println!("linux-save-ok");',
        'fn main() { println!("linux-save-ok");',
      );
      expect(controller.text, afterFirstJoin);
      expect(controller.selection.extentOffset, 'fn main() {'.length);
      views = tester.widgetList<RustTextInputField>(fields).toList();
      expect(views.first.inputWindow.document.resync().content, afterFirstJoin);
      expect(views.last.inputWindow.document.resync().content, afterFirstJoin);
      await _pressHistory(tester, platform, redo: false);
      expect(controller.text, source);
      await _pressHistory(tester, platform, redo: true);
      expect(controller.text, afterFirstJoin);
      await _pressSave(tester);
      expect(
        file.readAsBytesSync(),
        [
          0xef,
          0xbb,
          0xbf,
          ...utf8.encode(afterFirstJoin.replaceAll('\n', '\r\n'))
        ],
      );

      final helloStart = controller.text.indexOf('hello ');
      final worldStart = controller.text.indexOf('world');
      controller.selection = TextSelection(
        baseOffset: helloStart + 2,
        extentOffset: worldStart + 2,
      );
      await tester.pump();
      await _invokeJoinLines(tester, platform);
      final afterSelectedJoin =
          afterFirstJoin.replaceFirst('hello \n    world', 'hello world');
      expect(controller.text, afterSelectedJoin);
      expect(controller.selection.start, helloStart + 2);
      expect(controller.selection.end, helloStart + 7);
      await _pressHistory(tester, platform, redo: false);
      expect(controller.text, afterFirstJoin);
      await _pressHistory(tester, platform, redo: true);
      expect(controller.text, afterSelectedJoin);

      controller.selection = TextSelection.collapsed(
        offset: controller.text.indexOf('tail') + 1,
      );
      await tester.pump();
      await _invokeJoinLines(tester, platform);
      expect(controller.text, afterSelectedJoin);
      expect(controller.selection.extentOffset, afterSelectedJoin.length);

      final firstPair = controller.text.indexOf('pair');
      controller.selection = TextSelection(
        baseOffset: firstPair,
        extentOffset: firstPair + 'pair'.length,
      );
      await tester.pump();
      await _pressSelectNextOccurrence(tester, platform);
      views = tester.widgetList<RustTextInputField>(fields).toList();
      expect(views.first.additionalSelections, hasLength(1));
      await _invokeJoinLines(tester, platform);
      final afterMultiJoin = afterSelectedJoin
          .replaceFirst('pair\n    alpha', 'pair alpha')
          .replaceFirst('pair\n    beta', 'pair beta');
      expect(controller.text, afterMultiJoin);
      views = tester.widgetList<RustTextInputField>(fields).toList();
      expect(views.first.inputWindow.document.resync().content, afterMultiJoin);
      expect(views.last.inputWindow.document.resync().content, afterMultiJoin);
      await _pressHistory(tester, platform, redo: false);
      expect(controller.text, afterSelectedJoin);
      await _pressHistory(tester, platform, redo: true);
      expect(controller.text, afterMultiJoin);
      await _pressSave(tester);
      expect(
        file.readAsBytesSync(),
        [
          0xef,
          0xbb,
          0xbf,
          ...utf8.encode(afterMultiJoin.replaceAll('\n', '\r\n'))
        ],
      );
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
