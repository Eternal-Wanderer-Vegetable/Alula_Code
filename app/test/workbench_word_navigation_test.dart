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

Future<void> _openWordFixture(
  WidgetTester tester,
  TargetPlatform platform, {
  String text = 'alpha beta\r\nmore words',
}) async {
  debugDefaultTargetPlatformOverride = platform;
  final temp = Directory.systemTemp.createTempSync('alula-word-navigation');
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

Future<void> _pressWordArrow(
  WidgetTester tester, {
  required TargetPlatform platform,
  required LogicalKeyboardKey arrow,
  required bool extendSelection,
}) async {
  final modifier = platform == TargetPlatform.macOS
      ? LogicalKeyboardKey.altLeft
      : LogicalKeyboardKey.controlLeft;
  if (extendSelection) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  }
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(arrow);
  await tester.sendKeyUpEvent(modifier);
  if (extendSelection) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  }
  await tester.pump();
}

void main() {
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    testWidgets('$platform word-left moves and extends selection',
        (tester) async {
      try {
        await _openWordFixture(tester, platform);
        final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
        final controller = tester.widget<TextField>(editor).controller!;
        final document = tester
            .widget<RustTextInputField>(find.byType(RustTextInputField))
            .inputWindow
            .document;
        final sourceVersion = document.version;
        const normalizedText = 'alpha beta\nmore words';
        expect(controller.text, normalizedText);

        // Word-left from the end of "beta" returns its start.
        controller.selection = const TextSelection.collapsed(offset: 10);
        await tester.pump();
        await _pressWordArrow(
          tester,
          platform: platform,
          arrow: LogicalKeyboardKey.arrowLeft,
          extendSelection: false,
        );
        expect(controller.selection, const TextSelection.collapsed(offset: 6));

        controller.selection = const TextSelection.collapsed(offset: 10);
        await tester.pump();
        await _pressWordArrow(
          tester,
          platform: platform,
          arrow: LogicalKeyboardKey.arrowLeft,
          extendSelection: true,
        );
        expect(
          controller.selection,
          const TextSelection(baseOffset: 10, extentOffset: 6),
          reason: 'the platform word-left shortcut must preserve its anchor',
        );

        // Word-right uses the matching platform modifier and keeps the same
        // selection anchor when Shift is held.
        controller.selection = const TextSelection.collapsed(offset: 0);
        await tester.pump();
        await _pressWordArrow(
          tester,
          platform: platform,
          arrow: LogicalKeyboardKey.arrowRight,
          extendSelection: false,
        );
        expect(controller.selection, const TextSelection.collapsed(offset: 5));

        controller.selection = const TextSelection.collapsed(offset: 0);
        await tester.pump();
        await _pressWordArrow(
          tester,
          platform: platform,
          arrow: LogicalKeyboardKey.arrowRight,
          extendSelection: true,
        );
        expect(
          controller.selection,
          const TextSelection(baseOffset: 0, extentOffset: 5),
        );

        // The CRLF fixture is normalized to Rust's LF text model. Movement on
        // the second line must still stop at the expected word boundary.
        controller.selection = const TextSelection.collapsed(offset: 21);
        await tester.pump();
        await _pressWordArrow(
          tester,
          platform: platform,
          arrow: LogicalKeyboardKey.arrowLeft,
          extendSelection: false,
        );
        expect(controller.selection, const TextSelection.collapsed(offset: 16));

        expect(document.resync().content, normalizedText);
        expect(document.version, sourceVersion,
            reason: 'word navigation must not edit the Rust document');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('word-left remains bounded near a recentered input window edge',
      (tester) async {
    try {
      final source = List<String>.filled(12000, 'alpha').join(' ');
      await _openWordFixture(
        tester,
        TargetPlatform.linux,
        text: source,
      );

      final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
      var controller = tester.widget<TextField>(editor).controller!;
      controller.selection =
          TextSelection.collapsed(offset: controller.text.length);
      await tester.pump();
      await tester.pump();

      var field =
          tester.widget<RustTextInputField>(find.byType(RustTextInputField));
      controller = tester.widget<TextField>(editor).controller!;
      expect(field.inputWindow.startUtf16, greaterThan(0));
      final document = field.inputWindow.document;
      final sourceVersion = document.version;
      expect(controller.text.length, lessThan(source.length));
      final before = controller.selection.extentOffset;
      await _pressWordArrow(
        tester,
        platform: TargetPlatform.linux,
        arrow: LogicalKeyboardKey.arrowLeft,
        extendSelection: false,
      );
      controller = tester.widget<TextField>(editor).controller!;
      field =
          tester.widget<RustTextInputField>(find.byType(RustTextInputField));

      expect(controller.selection.extentOffset, lessThan(before));
      expect(controller.selection.extentOffset, greaterThanOrEqualTo(0));
      expect(controller.text.length, lessThan(source.length));
      expect(document.resync().content, source);
      expect(document.version, sourceVersion,
          reason: 'word navigation at the window edge must not edit Rust text');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
