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
    testWidgets('$platform triple-click copies and cuts a cross-window line',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _runCrossWindowLineSelection(tester, platform);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}

Future<void> _runCrossWindowLineSelection(
  WidgetTester tester,
  TargetPlatform platform,
) async {
  final temp = Directory.systemTemp.createTempSync('alula-long-line-select');
  addTearDown(() async {
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    await tester.pumpWidget(const SizedBox.shrink());
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  const prefix = 'head\n';
  final line = 'a' * 40000;
  final source = '$prefix$line\nlast\n';
  final workspace = Directory('${temp.path}/workspace')..createSync();
  final file = File('${workspace.path}/sample.txt')..writeAsStringSync(source);
  final base = temp.path.replaceAll(r'\', '/');
  Map<dynamic, dynamic> clipboard = const {};
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = Map<dynamic, dynamic>.from(call.arguments as Map);
      }
      if (call.method == 'Clipboard.getData') return clipboard;
      return null;
    },
  );

  await tester.pumpWidget(AlulaApp(
    autoFolder: workspace.path,
    layoutStore: LayoutStore(path: '$base/layout.json'),
    sessionStore: SessionStore(path: '$base/session.json'),
    keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
  ));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.tap(find.text('sample.txt').first);
  await tester.pump(const Duration(milliseconds: 300));

  final field = find.byType(RustTextInputField);
  final editor = find.descendant(
    of: field,
    matching: find.byKey(const ValueKey('rust-bounded-text-input')),
  );
  await tester.showKeyboard(editor);
  await tester.pump();
  final initialField = tester.widget<RustTextInputField>(field);
  final document = initialField.inputWindow.document;
  final initialVersion = document.version;
  expect(initialField.inputWindow.startUtf16, 0);
  expect(
      initialField.inputWindow.endUtf16, lessThan(prefix.length + line.length));
  expect(document.resync().content, source);

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

  final editable = findEditable(root)!;
  const clickOffset = prefix.length + 8;
  final caret = editable.getLocalRectForCaret(
    const TextPosition(offset: clickOffset),
  );
  final click = editable.localToGlobal(
    Offset(caret.left + 0.1, caret.center.dy),
  );
  for (var tap = 0; tap < 3; tap++) {
    await tester.tapAt(click, kind: PointerDeviceKind.mouse);
  }
  await tester.pump();
  await tester.pump();

  final selectedField = tester.widget<RustTextInputField>(field);
  final lineSelection = selectedField.rangeDecorations.singleWhere(
    (decoration) =>
        decoration.startUtf16 == prefix.length &&
        decoration.endUtf16 == prefix.length + line.length + 1,
  );
  expect(lineSelection.documentVersion, initialVersion);
  expect(
      lineSelection.startUtf16, lessThan(selectedField.inputWindow.startUtf16));
  expect(
      lineSelection.endUtf16, greaterThan(selectedField.inputWindow.endUtf16));
  expect(tester.widget<TextField>(editor).controller!.selection.isCollapsed,
      isTrue,
      reason: 'the local Flutter caret stays within the bounded mirror');
  expect(document.version, initialVersion,
      reason: 'selection does not write text to Rust');
  expect(document.resync().content, source);
  expect(file.readAsStringSync(), source,
      reason: 'selection does not change disk bytes');

  final commandKey = platform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(commandKey);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
  await tester.sendKeyUpEvent(commandKey);
  await tester.pump();
  expect(clipboard['text'], '$line\n');
  expect(document.version, initialVersion);
  expect(file.readAsStringSync(), source);

  await tester.sendKeyDownEvent(commandKey);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
  await tester.sendKeyUpEvent(commandKey);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  expect(document.resync().content, 'head\nlast\n');
  expect(file.readAsStringSync(), source,
      reason: 'cut changes Rust first; disk waits for explicit save');

  await tester.tap(find.byTooltip('文件').first);
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('保存').first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  expect(file.readAsStringSync(), 'head\nlast\n');
  expect(document.resync().content, file.readAsStringSync());
}
