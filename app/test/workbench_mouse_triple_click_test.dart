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
  const cases = <({
    String name,
    String source,
    int clickOffset,
    int selectionStart,
    int selectionEnd,
    String selectedText,
  })>[
    (
      name: 'LF line terminator',
      source: 'alpha 😀 beta\nsecond row\n',
      clickOffset: 11,
      selectionStart: 0,
      selectionEnd: 14,
      selectedText: 'alpha 😀 beta\n',
    ),
    (
      name: 'CRLF file with Rust-normalized LF text',
      source: 'alpha 😀 beta\r\nsecond row',
      clickOffset: 11,
      selectionStart: 0,
      selectionEnd: 14,
      selectedText: 'alpha 😀 beta\n',
    ),
    (
      name: 'final line without a terminator',
      source: 'alpha 😀 beta\nsecond row',
      clickOffset: 16,
      selectionStart: 14,
      selectionEnd: 24,
      selectedText: 'second row',
    ),
  ];
  for (final platform in <TargetPlatform>[
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    for (final fixture in cases) {
      testWidgets('$platform mouse triple-click selects ${fixture.name}',
          (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          await _runTripleClickSelection(
            tester,
            source: fixture.source,
            clickOffset: fixture.clickOffset,
            selectionStart: fixture.selectionStart,
            selectionEnd: fixture.selectionEnd,
            selectedText: fixture.selectedText,
          );
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
}

Future<void> _runTripleClickSelection(
  WidgetTester tester, {
  required String source,
  required int clickOffset,
  required int selectionStart,
  required int selectionEnd,
  required String selectedText,
}) async {
  final temp = Directory.systemTemp.createTempSync('alula-mouse-triple-click');
  addTearDown(() async {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });
  final workspace = Directory('${temp.path}/workspace')..createSync();
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
  final rustText = source.replaceAll('\r\n', '\n');
  expect(initialRustText, rustText);

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

  final render = editable();
  final caret = render.getLocalRectForCaret(TextPosition(offset: clickOffset));
  final click = render.localToGlobal(Offset(caret.left + 0.1, caret.center.dy));
  for (var tap = 0; tap < 3; tap++) {
    await tester.tapAt(click, kind: PointerDeviceKind.mouse);
  }
  await tester.pump();

  // VS Code LineSelect selects the clicked line plus its line terminator when
  // a following line exists.
  expect(controller.selection.baseOffset, selectionStart);
  expect(controller.selection.extentOffset, selectionEnd);
  expect(
    controller.text.substring(
      controller.selection.start,
      controller.selection.end,
    ),
    selectedText,
  );
  expect(controller.text, rustText);
  final currentWindow = tester
      .widget<RustTextInputField>(find.byType(RustTextInputField))
      .inputWindow;
  expect(currentWindow.document.resync().content, initialRustText);
  expect(currentWindow.version, initialVersion);
  expect(file.readAsStringSync(), source);
}
