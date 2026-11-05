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
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in <TargetPlatform>[
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    testWidgets('$platform mouse double-click selects a word', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _runDoubleClickSelection(tester);
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

Future<void> _runDoubleClickSelection(WidgetTester tester) async {
  final temp = Directory.systemTemp.createTempSync('alula-mouse-double-click');
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
  final controller = tester.widget<TextField>(editor).controller!;
  final inputWindow = tester
      .widget<RustTextInputField>(find.byType(RustTextInputField))
      .inputWindow;
  final initialRustText = inputWindow.document.resync().content;
  final initialVersion = inputWindow.version;
  const wordStart = 9;
  const wordEnd = 13;

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

  final click = pointForOffset(wordStart + 2);
  await tester.tapAt(click, kind: PointerDeviceKind.mouse);
  await tester.tapAt(click, kind: PointerDeviceKind.mouse);
  await tester.pump();

  expect(
      controller.text
          .substring(controller.selection.start, controller.selection.end),
      'beta');
  expect(controller.selection.baseOffset, wordStart);
  expect(controller.selection.extentOffset, wordEnd);
  expect(controller.text, source);
  final currentWindow = tester
      .widget<RustTextInputField>(find.byType(RustTextInputField))
      .inputWindow;
  expect(currentWindow.document.resync().content, initialRustText);
  expect(currentWindow.version, initialVersion);
  expect(file.readAsStringSync(), source);
}
