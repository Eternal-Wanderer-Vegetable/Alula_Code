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

Future<void> _openFixture(WidgetTester tester, TargetPlatform platform) async {
  debugDefaultTargetPlatformOverride = platform;
  final temp = Directory.systemTemp.createTempSync('alula-cursor-movement');
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    if (temp.existsSync()) await temp.delete(recursive: true);
  });
  final workspace = Directory('${temp.path}/workspace')..createSync();
  File('${workspace.path}/sample.txt').writeAsStringSync('a😀b');
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

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
    testWidgets('$platform arrow movement keeps emoji surrogate pairs intact',
        (tester) async {
      try {
        await _openFixture(tester, platform);
        final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
        final controller = tester.widget<TextField>(editor).controller!;
        final document = tester
            .widget<RustTextInputField>(find.byType(RustTextInputField))
            .inputWindow
            .document;
        final sourceVersion = document.version;

        controller.selection = const TextSelection.collapsed(offset: 3);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(controller.selection, const TextSelection.collapsed(offset: 1));

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(
          controller.selection,
          const TextSelection(baseOffset: 1, extentOffset: 3),
          reason:
              'Shift+Right must extend over the complete supplementary rune',
        );

        controller.selection = const TextSelection.collapsed(offset: 0);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(controller.selection, const TextSelection.collapsed(offset: 0));
        expect(document.resync().content, 'a😀b');
        expect(document.version, sourceVersion,
            reason: 'cursor movement must not edit the Rust document');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
