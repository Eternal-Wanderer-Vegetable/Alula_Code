import 'dart:io';

import 'package:alula_app/bridge/alula_core.dart' show AlulaDoc;
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

typedef _CrossWindowFixture = ({
  AlulaDoc document,
  File file,
  String source,
  String line,
  Finder editor,
  Map<dynamic, dynamic> clipboard,
});

void main() {
  for (final platform in <TargetPlatform>[
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    testWidgets('$platform triple-click copies and cuts a cross-window line',
        (tester) async {
      await _withPlatform(platform, () async {
        final fixture = await _selectLongLine(tester);
        final initialVersion = fixture.document.version;
        await _sendCommandKey(tester, platform, LogicalKeyboardKey.keyC);
        await tester.pump();
        expect(fixture.clipboard['text'], '${fixture.line}\n');
        expect(fixture.document.version, initialVersion);
        expect(fixture.file.readAsStringSync(), fixture.source);

        await _sendCommandKey(tester, platform, LogicalKeyboardKey.keyX);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(fixture.document.resync().content, 'head\nlast\n');
        expect(fixture.file.readAsStringSync(), fixture.source,
            reason: 'cut changes Rust first; disk waits for explicit save');

        await _save(tester);
        expect(fixture.file.readAsStringSync(), 'head\nlast\n');
        expect(
            fixture.document.resync().content, fixture.file.readAsStringSync());
      });
    });

    testWidgets('$platform ordinary typing replaces the cross-window line',
        (tester) async {
      await _withPlatform(platform, () async {
        final fixture = await _selectLongLine(tester);
        final controller = tester.widget<TextField>(fixture.editor).controller!;
        final before = controller.value;
        final caret = before.selection.extentOffset;
        const replacement = '🙂\n';
        tester.testTextInput.updateEditingValue(TextEditingValue(
          text: _replaceAt(before.text, caret, caret, replacement),
          selection: TextSelection.collapsed(
            offset: caret + replacement.length,
          ),
          composing: TextRange.empty,
        ));
        await tester.pump();
        await tester.pump();

        const edited = 'head\n🙂\nlast\n';
        expect(fixture.document.resync().content, edited);
        expect(fixture.document.isDirty, isTrue);
        expect(fixture.file.readAsStringSync(), fixture.source,
            reason: 'typing updates Rust before an explicit save');

        await _sendCommandKey(tester, platform, LogicalKeyboardKey.keyZ);
        await tester.pump();
        expect(fixture.document.resync().content, fixture.source);
        expect(fixture.document.isDirty, isFalse);

        await _sendCommandKey(tester, platform, LogicalKeyboardKey.keyY);
        await tester.pump();
        expect(fixture.document.resync().content, edited);
        await _save(tester);
        expect(fixture.file.readAsStringSync(), edited);
        expect(
            fixture.document.resync().content, fixture.file.readAsStringSync());
      });
    });

    testWidgets('$platform paste replaces the cross-window line',
        (tester) async {
      await _withPlatform(platform, () async {
        final fixture = await _selectLongLine(tester);
        const replacement = 'pasted 🙂\n';
        fixture.clipboard['text'] = replacement;

        await _sendCommandKey(tester, platform, LogicalKeyboardKey.keyV);
        await tester.pump();
        await tester.pump();

        const edited = 'head\npasted 🙂\nlast\n';
        expect(fixture.document.resync().content, edited);
        expect(fixture.document.isDirty, isTrue);
        expect(fixture.file.readAsStringSync(), fixture.source);

        await _sendCommandKey(tester, platform, LogicalKeyboardKey.keyZ);
        await tester.pump();
        expect(fixture.document.resync().content, fixture.source);
        await _sendCommandKey(tester, platform, LogicalKeyboardKey.keyY);
        await tester.pump();
        expect(fixture.document.resync().content, edited);
        await _save(tester);
        expect(fixture.file.readAsStringSync(), edited);
        expect(
          fixture.document.resync().content,
          fixture.file.readAsStringSync(),
        );
      });
    });

    testWidgets(
        '$platform IME cancellation preserves and commit replaces selection',
        (tester) async {
      await _withPlatform(platform, () async {
        final fixture = await _selectLongLine(tester);
        final controller = tester.widget<TextField>(fixture.editor).controller!;
        final before = controller.value;
        final caret = before.selection.extentOffset;
        final initialVersion = fixture.document.version;
        const preedit = 'nihao';
        tester.testTextInput.updateEditingValue(TextEditingValue(
          text: _replaceAt(before.text, caret, caret, preedit),
          selection: TextSelection.collapsed(offset: caret + preedit.length),
          composing: TextRange(start: caret, end: caret + preedit.length),
        ));
        await tester.pump();
        await tester.pump();
        expect(controller.value.composing,
            TextRange(start: caret, end: caret + preedit.length));
        expect(fixture.document.version, initialVersion);
        expect(fixture.document.resync().content, fixture.source);

        const shortenedPreedit = 'niha';
        tester.testTextInput.updateEditingValue(TextEditingValue(
          text: _replaceAt(before.text, caret, caret, shortenedPreedit),
          selection:
              TextSelection.collapsed(offset: caret + shortenedPreedit.length),
          composing: TextRange(
            start: caret,
            end: caret + shortenedPreedit.length,
          ),
        ));
        await tester.pump();
        expect(controller.value.composing,
            TextRange(start: caret, end: caret + shortenedPreedit.length));
        expect(fixture.document.version, initialVersion,
            reason: 'editing the preedit does not write through to Rust');
        expect(fixture.document.resync().content, fixture.source);

        tester.testTextInput.updateEditingValue(TextEditingValue(
          text: before.text,
          selection: before.selection,
          composing: TextRange.empty,
        ));
        await tester.pump();
        await tester.pump();
        expect(controller.value.selection.isValid, isTrue);
        expect(fixture.document.version, initialVersion);
        expect(fixture.document.resync().content, fixture.source);
        _expectCrossWindowDecoration(
          tester,
          find.byType(RustTextInputField),
        );

        final afterCancel = controller.value;
        final commitCaret = afterCancel.selection.extentOffset;
        tester.testTextInput.updateEditingValue(TextEditingValue(
          text: _replaceAt(
            afterCancel.text,
            commitCaret,
            commitCaret,
            preedit,
          ),
          selection:
              TextSelection.collapsed(offset: commitCaret + preedit.length),
          composing: TextRange(
            start: commitCaret,
            end: commitCaret + preedit.length,
          ),
        ));
        await tester.pump();
        await tester.pump();
        final composingValue = controller.value;
        expect(composingValue.composing,
            TextRange(start: commitCaret, end: commitCaret + preedit.length));
        const committed = '你好';
        tester.testTextInput.updateEditingValue(TextEditingValue(
          text: _replaceAt(
            composingValue.text,
            composingValue.composing.start,
            composingValue.composing.end,
            committed,
          ),
          selection: TextSelection.collapsed(
            offset: composingValue.composing.start + committed.length,
          ),
          composing: TextRange.empty,
        ));
        await tester.pump();
        await tester.pump();

        const edited = 'head\n你好last\n';
        expect(fixture.document.resync().content, edited);
        expect(fixture.document.isDirty, isTrue);
        expect(fixture.file.readAsStringSync(), fixture.source);

        await _sendCommandKey(tester, platform, LogicalKeyboardKey.keyZ);
        await tester.pump();
        expect(fixture.document.resync().content, fixture.source);
        await _sendCommandKey(tester, platform, LogicalKeyboardKey.keyY);
        await tester.pump();
        expect(fixture.document.resync().content, edited);
        await _save(tester);
        expect(fixture.file.readAsStringSync(), edited);
        expect(
            fixture.document.resync().content, fixture.file.readAsStringSync());
      });
    });

    for (final key in <LogicalKeyboardKey>[
      LogicalKeyboardKey.backspace,
      LogicalKeyboardKey.delete,
    ]) {
      testWidgets('$platform $key deletes the selected cross-window line',
          (tester) async {
        await _withPlatform(platform, () async {
          final fixture = await _selectLongLine(tester);
          await tester.sendKeyEvent(key);
          await tester.pump();
          await tester.pump();
          expect(fixture.document.resync().content, 'head\nlast\n');
          expect(fixture.document.isDirty, isTrue);
          expect(fixture.file.readAsStringSync(), fixture.source);
        });
      });
    }
  }
}

Future<void> _withPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

Future<_CrossWindowFixture> _selectLongLine(WidgetTester tester) async {
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
  final clipboard = <dynamic, dynamic>{};
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard
          ..clear()
          ..addAll(Map<dynamic, dynamic>.from(call.arguments as Map));
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
    initialField.inputWindow.endUtf16,
    lessThan(prefix.length + line.length),
  );
  expect(document.resync().content, source);

  await _tripleClick(tester, editor, prefix.length + 8);
  _expectCrossWindowDecoration(tester, field);
  final selectedField = tester.widget<RustTextInputField>(field);
  final lineSelection = selectedField.rangeDecorations.singleWhere(
    (decoration) =>
        decoration.startUtf16 == prefix.length &&
        decoration.endUtf16 == prefix.length + line.length + 1,
  );
  expect(lineSelection.documentVersion, initialVersion);
  expect(
    lineSelection.startUtf16,
    lessThan(selectedField.inputWindow.startUtf16),
  );
  expect(
    lineSelection.endUtf16,
    greaterThan(selectedField.inputWindow.endUtf16),
  );
  expect(tester.widget<TextField>(editor).controller!.selection.isCollapsed,
      isTrue,
      reason: 'the local Flutter caret stays within the bounded mirror');
  expect(document.version, initialVersion,
      reason: 'selection does not write text to Rust');
  expect(document.resync().content, source);
  expect(file.readAsStringSync(), source,
      reason: 'selection does not change disk bytes');
  return (
    document: document,
    file: file,
    source: source,
    line: line,
    editor: editor,
    clipboard: clipboard,
  );
}

Future<void> _tripleClick(
  WidgetTester tester,
  Finder editor,
  int localOffset,
) async {
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
  final caret =
      editable.getLocalRectForCaret(TextPosition(offset: localOffset));
  final click = editable.localToGlobal(
    Offset(caret.left + 0.1, caret.center.dy),
  );
  for (var tap = 0; tap < 3; tap++) {
    await tester.tapAt(click, kind: PointerDeviceKind.mouse);
  }
  await tester.pump();
  await tester.pump();
}

void _expectCrossWindowDecoration(WidgetTester tester, Finder fieldFinder) {
  final field = tester.widget<RustTextInputField>(fieldFinder);
  expect(
    field.rangeDecorations.any((decoration) =>
        decoration.startUtf16 == 'head\n'.length &&
        decoration.endUtf16 > field.inputWindow.endUtf16),
    isTrue,
  );
}

String _replaceAt(String text, int start, int end, String replacement) =>
    text.replaceRange(start, end, replacement);

Future<void> _sendCommandKey(
  WidgetTester tester,
  TargetPlatform platform,
  LogicalKeyboardKey key,
) async {
  final commandKey = platform == TargetPlatform.macOS &&
          <LogicalKeyboardKey>{
            LogicalKeyboardKey.keyC,
            LogicalKeyboardKey.keyX,
            LogicalKeyboardKey.keyV,
          }.contains(key)
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(commandKey);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(commandKey);
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byTooltip('文件').first);
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('保存').first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}
