import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Directory> _openPageFixture(
  WidgetTester tester,
  TargetPlatform platform, {
  required String text,
}) async {
  debugDefaultTargetPlatformOverride = platform;
  tester.view.physicalSize = const Size(1200, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final temp = Directory.systemTemp.createTempSync('alula-page-movement');
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
  ));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.tap(find.text('sample.txt').first);
  await tester.pump(const Duration(milliseconds: 300));
  await tester
      .showKeyboard(find.byKey(const ValueKey('rust-bounded-text-input')));
  await tester.pump();
  return temp;
}

int _lineAt(String text, int offset) =>
    '\n'.allMatches(text.substring(0, offset)).length;

int _lineStart(String text, int line) {
  var offset = 0;
  for (var current = 0; current < line; current++) {
    final next = text.indexOf('\n', offset);
    if (next < 0) return text.length;
    offset = next + 1;
  }
  return offset;
}

void main() {
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    testWidgets('$platform PageUp/PageDown move and extend by a viewport',
        (tester) async {
      try {
        final text = List<String>.generate(
          500,
          (line) => 'line-${line.toString().padLeft(3, '0')} abcdefghijklmnop',
        ).join('\n');
        await _openPageFixture(tester, platform, text: text);

        final input = find.byKey(const ValueKey('rust-bounded-text-input'));
        final controller = tester.widget<TextField>(input).controller!;
        final rustField = tester.widget<RustTextInputField>(
          find.byType(RustTextInputField),
        );
        final document = rustField.inputWindow.document;
        final version = document.version;
        final authoritativeText = document.resync().content;
        final editable =
            tester.state<EditableTextState>(find.byType(EditableText));
        final pageLines = (editable.renderEditable.size.height /
                editable.renderEditable.preferredLineHeight)
            .floor();

        final start = _lineStart(controller.text, 180) + 5;
        controller.selection = TextSelection.collapsed(offset: start);
        await tester.pumpAndSettle();
        final beforeDownLine = _lineAt(controller.text, start);
        await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
        await tester.pumpAndSettle();
        final down = controller.selection.extentOffset;
        final downLine = _lineAt(controller.text, down);
        expect(downLine - beforeDownLine, greaterThanOrEqualTo(pageLines - 2));

        final anchor = _lineStart(controller.text, 220) + 4;
        controller.selection = TextSelection.collapsed(offset: anchor);
        await tester.pumpAndSettle();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        expect(controller.selection.baseOffset, anchor);
        expect(controller.selection.extentOffset, lessThan(anchor));
        expect(
          anchor - controller.selection.extentOffset,
          greaterThanOrEqualTo(pageLines - 2),
        );

        expect(document.resync().content, authoritativeText);
        expect(document.version, version,
            reason: 'PageUp/PageDown only move the caret or selection');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('PageDown recenters a bounded Rust input window without editing',
      (tester) async {
    try {
      const platform = TargetPlatform.linux;
      final text = List<String>.generate(
        4000,
        (line) => 'L${line.toString().padLeft(4, '0')}',
      ).join('\n');
      await _openPageFixture(tester, platform, text: text);

      final input = find.byKey(const ValueKey('rust-bounded-text-input'));
      final controller = tester.widget<TextField>(input).controller!;
      final document = tester
          .widget<RustTextInputField>(find.byType(RustTextInputField))
          .inputWindow
          .document;
      final version = document.version;
      final authoritativeText = document.resync().content;
      final inputWindow = tester
          .widget<RustTextInputField>(find.byType(RustTextInputField))
          .inputWindow;
      expect(inputWindow.totalUtf16Length, greaterThan(controller.text.length));

      final start = controller.text.length - 2600;
      controller.selection = TextSelection.collapsed(offset: start);
      await tester.pumpAndSettle();
      for (var page = 0; page < 6; page++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
        await tester.pumpAndSettle();
      }

      final refreshedInputWindow = tester
          .widget<RustTextInputField>(find.byType(RustTextInputField))
          .inputWindow;
      expect(refreshedInputWindow.startUtf16, greaterThan(0));
      expect(document.resync().content, authoritativeText);
      expect(document.version, version);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
