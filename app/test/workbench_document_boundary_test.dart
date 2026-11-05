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

Future<void> _openFixture(
  WidgetTester tester,
  TargetPlatform platform, {
  required String text,
}) async {
  debugDefaultTargetPlatformOverride = platform;
  final temp = Directory.systemTemp.createTempSync('alula-document-boundary');
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    if (temp.existsSync()) await temp.delete(recursive: true);
  });
  final workspace = Directory('${temp.path}/workspace')..createSync();
  File('${workspace.path}/sample.txt').writeAsStringSync(text);
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
  await tester
      .showKeyboard(find.byKey(const ValueKey('rust-bounded-text-input')));
  await tester.pump();
}

Future<void> _pressBoundary(
  WidgetTester tester,
  TargetPlatform platform, {
  required bool toBottom,
  bool shift = false,
}) async {
  final key = platform == TargetPlatform.macOS
      ? toBottom
          ? LogicalKeyboardKey.arrowDown
          : LogicalKeyboardKey.arrowUp
      : toBottom
          ? LogicalKeyboardKey.end
          : LogicalKeyboardKey.home;
  final modifier = platform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

void main() {
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    testWidgets('$platform document start/end moves and extends selection',
        (tester) async {
      try {
        const source = 'fn main() {\n    println!("boundary");\n}\n';
        await _openFixture(tester, platform, text: source);
        final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
        final controller = tester.widget<TextField>(editor).controller!;
        final field =
            tester.widget<RustTextInputField>(find.byType(RustTextInputField));
        final document = field.inputWindow.document;
        final version = document.version;
        final length = controller.text.length;

        controller.selection = const TextSelection.collapsed(offset: 8);
        await tester.pump();
        await _pressBoundary(tester, platform, toBottom: false);
        expect(controller.selection, const TextSelection.collapsed(offset: 0));

        controller.selection = const TextSelection.collapsed(offset: 0);
        await tester.pump();
        await _pressBoundary(tester, platform, toBottom: true);
        expect(controller.selection, TextSelection.collapsed(offset: length));

        controller.selection = const TextSelection.collapsed(offset: 8);
        await tester.pump();
        await _pressBoundary(tester, platform, toBottom: false, shift: true);
        expect(
          controller.selection,
          const TextSelection(baseOffset: 8, extentOffset: 0),
        );

        controller.selection = const TextSelection.collapsed(offset: 3);
        await tester.pump();
        await _pressBoundary(tester, platform, toBottom: true, shift: true);
        expect(
          controller.selection,
          TextSelection(baseOffset: 3, extentOffset: length),
        );

        expect(document.resync().content, source);
        expect(document.version, version,
            reason: 'document boundary navigation must not edit Rust text');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('document boundaries recenter a file beyond the 16K input window',
      (tester) async {
    try {
      final source = List.generate(4000, (line) => 'line-$line').join('\n');
      await _openFixture(tester, TargetPlatform.linux, text: source);
      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      var controller = tester.widget<TextField>(editor).controller!;
      var field =
          tester.widget<RustTextInputField>(find.byType(RustTextInputField));
      final document = field.inputWindow.document;
      final version = document.version;
      expect(controller.text.length, lessThan(source.length));

      controller.selection = TextSelection.collapsed(offset: controller.text.length);
      await tester.pump();
      await _pressBoundary(tester, TargetPlatform.linux, toBottom: true);

      controller = tester.widget<TextField>(editor).controller!;
      field = tester.widget<RustTextInputField>(find.byType(RustTextInputField));
      expect(field.inputWindow.startUtf16, greaterThan(0));
      expect(
        field.inputWindow.startUtf16 + controller.selection.extentOffset,
        source.length,
      );
      expect(controller.text.length, lessThan(source.length));

      await _pressBoundary(tester, TargetPlatform.linux, toBottom: false);
      controller = tester.widget<TextField>(editor).controller!;
      field = tester.widget<RustTextInputField>(find.byType(RustTextInputField));
      expect(field.inputWindow.startUtf16, 0);
      expect(controller.selection, const TextSelection.collapsed(offset: 0));
      expect(document.resync().content, source);
      expect(document.version, version);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
