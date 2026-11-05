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
  String text = ' \talpha  \r\n  beta🦊 \r\n',
}) async {
  debugDefaultTargetPlatformOverride = platform;
  final temp = Directory.systemTemp.createTempSync('alula-line-boundary');
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

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
  bool meta = false,
}) async {
  if (meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pump();
}

void main() {
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    testWidgets('$platform Home/End use Rust line boundaries and preserve anchors',
        (tester) async {
      try {
        await _openFixture(tester, platform);
        final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
        var controller = tester.widget<TextField>(editor).controller!;
        final field = tester
            .widget<RustTextInputField>(find.byType(RustTextInputField));
        final document = field.inputWindow.document;
        final version = document.version;
        const normalizedText = ' \talpha  \n  beta🦊 \n';
        expect(controller.text, normalizedText);

        controller.selection = const TextSelection.collapsed(offset: 5);
        await tester.pump();
        await _press(tester, LogicalKeyboardKey.home);
        expect(controller.selection, const TextSelection.collapsed(offset: 2));
        await _press(tester, LogicalKeyboardKey.home);
        expect(controller.selection, const TextSelection.collapsed(offset: 0));
        await _press(tester, LogicalKeyboardKey.home);
        expect(controller.selection, const TextSelection.collapsed(offset: 2));

        controller.selection = const TextSelection.collapsed(offset: 4);
        await tester.pump();
        await _press(tester, LogicalKeyboardKey.end);
        expect(controller.selection, const TextSelection.collapsed(offset: 9));

        controller.selection = const TextSelection.collapsed(offset: 6);
        await tester.pump();
        await _press(tester, LogicalKeyboardKey.home, shift: true);
        expect(
          controller.selection,
          const TextSelection(baseOffset: 6, extentOffset: 2),
        );

        controller.selection = const TextSelection.collapsed(offset: 15);
        await tester.pump();
        await _press(tester, LogicalKeyboardKey.end, shift: true);
        expect(
          controller.selection,
          const TextSelection(baseOffset: 15, extentOffset: 19),
        );

        if (platform == TargetPlatform.macOS) {
          controller.selection = const TextSelection.collapsed(offset: 6);
          await tester.pump();
          await _press(tester, LogicalKeyboardKey.arrowLeft, meta: true);
          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 2),
          );
          await _press(tester, LogicalKeyboardKey.arrowRight,
              meta: true, shift: true);
          expect(
            controller.selection,
            const TextSelection(baseOffset: 2, extentOffset: 9),
          );
        }

        expect(document.resync().content, normalizedText);
        expect(document.version, version,
            reason: 'cursor navigation must not edit Rust text');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('smart Home reaches the first code character beyond a 16K window',
      (tester) async {
    try {
      final source = '${' ' * 20000}fn main() {}\n';
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
      await _press(tester, LogicalKeyboardKey.home);

      controller = tester.widget<TextField>(editor).controller!;
      field = tester.widget<RustTextInputField>(find.byType(RustTextInputField));
      expect(field.inputWindow.startUtf16, greaterThan(0));
      expect(
        field.inputWindow.startUtf16 + controller.selection.extentOffset,
        20000,
      );
      expect(controller.text.length, lessThan(source.length));
      expect(document.resync().content, source);
      expect(document.version, version);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
