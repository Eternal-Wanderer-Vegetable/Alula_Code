import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderEditable, RenderObject;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in <TargetPlatform>[
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    testWidgets('$platform mouse click places caret; Shift-click keeps anchor',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _runMouseSelection(tester);
      } finally {
        try {
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      }
    });
  }
}

Future<void> _runMouseSelection(WidgetTester tester) async {
  final temp = Directory.systemTemp.createTempSync('alula-mouse-select');
  addTearDown(() async {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });
  final workspace = Directory('${temp.path}/workspace')..createSync();
  const source = 'alpha 😀 beta\nsecond row\n';
  final file = File('${workspace.path}/sample.txt')..writeAsStringSync(source);
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
  final textField = tester.widget<TextField>(editor);
  final controller = textField.controller!;
  final field = tester.widget<RustTextInputField>(
    find.byType(RustTextInputField),
  );
  final initialText = controller.text;
  final initialRustText = field.inputWindow.document.resync().content;
  final initialWindowVersion = field.inputWindow.version;

  RenderEditable editable() {
    final root = tester.renderObject<RenderObject>(
      find.descendant(of: editor, matching: find.byType(EditableText)),
    );
    RenderEditable? findEditable(RenderObject object) {
      if (object is RenderEditable) return object;
      RenderEditable? result;
      object.visitChildren((child) {
        result ??= findEditable(child);
      });
      return result;
    }

    return findEditable(root)!;
  }

  Offset pointForOffset(int offset) {
    final render = editable();
    final caret = render.getLocalRectForCaret(TextPosition(offset: offset));
    return render.localToGlobal(Offset(caret.left + 0.1, caret.center.dy));
  }

  const anchor = 4;
  final forwardExtent = source.indexOf('beta') + 2;
  await tester.tapAt(
    pointForOffset(anchor),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  expect(controller.selection.baseOffset, anchor);
  expect(controller.selection.extentOffset, anchor);

  // Keep deliberate Shift-clicks outside Flutter's double-tap window.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.tapAt(
    pointForOffset(forwardExtent),
    kind: PointerDeviceKind.mouse,
  );
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
  expect(controller.selection.baseOffset, anchor);
  expect(controller.selection.extentOffset, forwardExtent);

  // Reset the caret to check reverse selection from the same origin.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tapAt(pointForOffset(anchor), kind: PointerDeviceKind.mouse);
  await tester.pump();
  expect(controller.selection.baseOffset, anchor);
  expect(controller.selection.extentOffset, anchor);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.tapAt(pointForOffset(1), kind: PointerDeviceKind.mouse);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
  expect(controller.selection.baseOffset, anchor);
  expect(controller.selection.extentOffset, 1);

  expect(controller.text, initialText);
  expect(
    tester
        .widget<RustTextInputField>(find.byType(RustTextInputField))
        .inputWindow
        .document
        .resync()
        .content,
    initialRustText,
  );
  expect(
    tester
        .widget<RustTextInputField>(find.byType(RustTextInputField))
        .inputWindow
        .version,
    initialWindowVersion,
  );
  expect(file.readAsStringSync(), source);
}
