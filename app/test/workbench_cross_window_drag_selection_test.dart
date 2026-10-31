import 'dart:io';

import 'package:alula_app/bridge/alula_core.dart' show AlulaDoc;
import 'package:alula_app/editor/editor_rendering.dart'
    show EditorRangeDecoration;
import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart' show kPrimaryButton, PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderEditable, RenderObject;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _DragFixture = ({
  AlulaDoc document,
  File file,
  String source,
  int initialWindowEnd,
  Finder editor,
  Map<dynamic, dynamic> clipboard,
});

void main() {
  for (final platform in <TargetPlatform>[
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    testWidgets('$platform forward and reverse drag cross the input window',
        (tester) async {
      await _withPlatform(platform, () async {
        final fixture = await _openDragFixture(tester);
        final initialVersion = fixture.document.version;
        final initialWindowEnd = fixture.initialWindowEnd;
        final firstPoint = _pointForOffset(tester, fixture.editor, 0);
        final firstViewport = _editableRect(tester, fixture.editor);
        final forward = await tester.startGesture(
          firstPoint,
          kind: PointerDeviceKind.mouse,
          buttons: kPrimaryButton,
        );
        await forward.moveTo(
          Offset(firstPoint.dx, firstViewport.bottom + 1200),
        );
        expect(
          tester
              .state<RustTextInputFieldState>(find.byType(RustTextInputField))
              .hasActiveMouseDragAutoScrollTimer,
          isTrue,
        );
        await _pumpFor(tester, const Duration(milliseconds: 600));
        await forward.up();
        await tester.pump();
        expect(
          tester
              .state<RustTextInputFieldState>(find.byType(RustTextInputField))
              .hasActiveMouseDragAutoScrollTimer,
          isFalse,
        );

        final afterForward = tester.widget<RustTextInputField>(
          find.byType(RustTextInputField),
        );
        final forwardRange = _crossWindowRange(afterForward);
        expect(afterForward.inputWindow.startUtf16, greaterThan(0));
        expect(forwardRange.startUtf16, 0);
        expect(forwardRange.endUtf16, greaterThan(initialWindowEnd));
        expect(forwardRange.endUtf16, lessThanOrEqualTo(fixture.source.length));
        expect(fixture.document.version, initialVersion,
            reason: 'drag selection must not edit the Rust document');
        expect(fixture.document.resync().content, fixture.source);
        expect(fixture.file.readAsStringSync(), fixture.source,
            reason: 'drag selection must not write to disk');

        final forwardScroll = afterForward.scrollController!.position.pixels;
        await _pumpFor(tester, const Duration(milliseconds: 120));
        expect(afterForward.scrollController!.position.pixels, forwardScroll,
            reason: 'mouse-up must stop viewport auto-scroll');

        await _sendCopy(tester, platform);
        expect(
          fixture.clipboard['text'],
          fixture.source
              .substring(forwardRange.startUtf16, forwardRange.endUtf16),
        );

        final controller = tester.widget<TextField>(fixture.editor).controller!;
        final reverseStart = _pointForOffset(
          tester,
          fixture.editor,
          controller.selection.extentOffset,
        );
        final reverseViewport = _editableRect(tester, fixture.editor);
        final reverseWindowStart = afterForward.inputWindow.startUtf16;
        final reverse = await tester.startGesture(
          reverseStart,
          kind: PointerDeviceKind.mouse,
          buttons: kPrimaryButton,
        );
        await reverse.moveTo(
          Offset(reverseStart.dx, reverseViewport.top - 1200),
        );
        await _pumpFor(tester, const Duration(milliseconds: 600));
        await reverse.up();
        await tester.pump();

        final afterReverse = tester.widget<RustTextInputField>(
          find.byType(RustTextInputField),
        );
        final reverseRange = _crossWindowRange(afterReverse);
        expect(
            afterReverse.inputWindow.startUtf16, lessThan(reverseWindowStart));
        expect(reverseRange.endUtf16, greaterThan(reverseWindowStart));
        expect(reverseRange.startUtf16, lessThan(reverseRange.endUtf16));
        expect(fixture.document.version, initialVersion);
        expect(fixture.document.resync().content, fixture.source);
        expect(fixture.file.readAsStringSync(), fixture.source);

        await _sendCopy(tester, platform);
        expect(
          fixture.clipboard['text'],
          fixture.source
              .substring(reverseRange.startUtf16, reverseRange.endUtf16),
        );
        final afterDelete = fixture.source.replaceRange(
          reverseRange.startUtf16,
          reverseRange.endUtf16,
          '',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(fixture.document.resync().content, afterDelete);
        expect(fixture.document.isDirty, isTrue);
        expect(fixture.file.readAsStringSync(), fixture.source);
        await _save(tester);
        expect(fixture.file.readAsStringSync(), afterDelete);
      });
    });

    testWidgets('$platform cut removes the full cross-window drag selection',
        (tester) async {
      await _withPlatform(platform, () async {
        final fixture = await _openDragFixture(tester);
        final initialVersion = fixture.document.version;
        final firstPoint = _pointForOffset(tester, fixture.editor, 0);
        final viewport = _editableRect(tester, fixture.editor);
        final gesture = await tester.startGesture(
          firstPoint,
          kind: PointerDeviceKind.mouse,
          buttons: kPrimaryButton,
        );
        await gesture.moveTo(Offset(firstPoint.dx, viewport.bottom + 1200));
        await _pumpFor(tester, const Duration(milliseconds: 600));
        await gesture.up();
        await tester.pump();
        final field = tester.widget<RustTextInputField>(
          find.byType(RustTextInputField),
        );
        final range = _crossWindowRange(field);
        final expected = fixture.source.replaceRange(
          range.startUtf16,
          range.endUtf16,
          '',
        );
        await _sendCommandKey(tester, platform, LogicalKeyboardKey.keyX);
        expect(
          fixture.clipboard['text'],
          fixture.source.substring(range.startUtf16, range.endUtf16),
        );
        expect(fixture.document.resync().content, expected);
        expect(fixture.document.version, greaterThan(initialVersion));
        expect(fixture.document.isDirty, isTrue);
        expect(fixture.file.readAsStringSync(), fixture.source);
        await _save(tester);
        expect(fixture.file.readAsStringSync(), expected);
        expect(fixture.document.resync().content, expected);
      });
    });

    testWidgets('$platform cancel, focus loss and dispose stop drag scrolling',
        (tester) async {
      await _withPlatform(platform, () async {
        final fixture = await _openDragFixture(
          tester,
          lineWidth: 300,
          lineCount: 100,
        );
        final editor = fixture.editor;
        final fieldFinder = find.byType(RustTextInputField);
        final field = tester.widget<RustTextInputField>(fieldFinder);
        final scrollController = field.scrollController!;
        final firstPoint = _pointForOffset(tester, editor, 0);
        var viewport = _editableRect(tester, editor);
        var gesture = await tester.startGesture(
          firstPoint,
          kind: PointerDeviceKind.mouse,
          buttons: kPrimaryButton,
        );
        await gesture.moveTo(Offset(firstPoint.dx, viewport.bottom + 1200));
        await tester.pump(const Duration(milliseconds: 16));
        expect(scrollController.position.pixels, greaterThan(0),
            reason: 'dragging below the viewport starts auto-scroll');
        await gesture.cancel();
        await tester.pump();
        expect(
          tester
              .state<RustTextInputFieldState>(fieldFinder)
              .hasActiveMouseDragAutoScrollTimer,
          isFalse,
        );
        await _pumpFor(tester, const Duration(milliseconds: 120));
        var stoppedAt = scrollController.position.pixels;
        await _pumpFor(tester, const Duration(milliseconds: 120));
        expect(scrollController.position.pixels, stoppedAt,
            reason: 'pointer-cancel must stop auto-scroll');

        final textField = tester.widget<TextField>(editor);
        final currentController = textField.controller!;
        final startOffset = currentController.selection.isValid
            ? currentController.selection.extentOffset
            : 0;
        final focusPoint = _pointForOffset(tester, editor, startOffset);
        viewport = _editableRect(tester, editor);
        gesture = await tester.startGesture(
          focusPoint,
          kind: PointerDeviceKind.mouse,
          buttons: kPrimaryButton,
        );
        await gesture.moveTo(Offset(focusPoint.dx, viewport.bottom + 1200));
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          tester
              .state<RustTextInputFieldState>(fieldFinder)
              .hasActiveMouseDragAutoScrollTimer,
          isTrue,
        );
        final focusNode = textField.focusNode!;
        focusNode.unfocus();
        await tester.pump();
        expect(
          tester
              .state<RustTextInputFieldState>(fieldFinder)
              .hasActiveMouseDragAutoScrollTimer,
          isFalse,
        );
        await _pumpFor(tester, const Duration(milliseconds: 120));
        stoppedAt = scrollController.position.pixels;
        await _pumpFor(tester, const Duration(milliseconds: 120));
        expect(scrollController.position.pixels, stoppedAt,
            reason: 'losing editor focus must stop auto-scroll');
        await gesture.up();
        await tester.pump();

        final disposePoint = _pointForOffset(
          tester,
          editor,
          currentController.selection.extentOffset.clamp(
            0,
            currentController.text.length,
          ),
        );
        viewport = _editableRect(tester, editor);
        final disposingGesture = await tester.startGesture(
          disposePoint,
          kind: PointerDeviceKind.mouse,
          buttons: kPrimaryButton,
        );
        await disposingGesture.moveTo(
          Offset(disposePoint.dx, viewport.bottom + 1200),
        );
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          tester
              .state<RustTextInputFieldState>(fieldFinder)
              .hasActiveMouseDragAutoScrollTimer,
          isTrue,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpFor(tester, const Duration(milliseconds: 120));
      });
    });
  }
}

Future<_DragFixture> _openDragFixture(
  WidgetTester tester, {
  int lineWidth = 380,
  int lineCount = 100,
}) async {
  final temp = Directory.systemTemp.createTempSync('alula-cross-window-drag');
  addTearDown(() async {
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    await tester.pumpWidget(const SizedBox.shrink());
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });
  final line = '${'a' * lineWidth}🙂';
  final source = List<String>.filled(lineCount, line).join('\n');
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

  final fieldFinder = find.byType(RustTextInputField);
  final editor = find.descendant(
    of: fieldFinder,
    matching: find.byKey(const ValueKey('rust-bounded-text-input')),
  );
  await tester.showKeyboard(editor);
  await tester.pump();
  final field = tester.widget<RustTextInputField>(fieldFinder);
  return (
    document: field.inputWindow.document,
    file: file,
    source: source,
    initialWindowEnd: field.inputWindow.endUtf16,
    editor: editor,
    clipboard: clipboard,
  );
}

RenderEditable _editable(WidgetTester tester, Finder editor) {
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

Offset _pointForOffset(WidgetTester tester, Finder editor, int offset) {
  final render = _editable(tester, editor);
  final text = tester.widget<TextField>(editor).controller!.text;
  final caret = render.getLocalRectForCaret(
    TextPosition(offset: offset.clamp(0, text.length)),
  );
  return render.localToGlobal(Offset(caret.left + 0.1, caret.center.dy));
}

Rect _editableRect(WidgetTester tester, Finder editor) {
  final render = _editable(tester, editor);
  return render.localToGlobal(Offset.zero) & render.size;
}

EditorRangeDecoration _crossWindowRange(RustTextInputField field) =>
    field.rangeDecorations
        .where((decoration) => decoration.backgroundColor != null)
        .reduce((left, right) =>
            right.endUtf16 - right.startUtf16 > left.endUtf16 - left.startUtf16
                ? right
                : left);

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final frames = (duration.inMilliseconds + 15) ~/ 16;
  for (var frame = 0; frame < frames; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _sendCopy(WidgetTester tester, TargetPlatform platform) async {
  await _sendCommandKey(tester, platform, LogicalKeyboardKey.keyC);
}

Future<void> _sendCommandKey(
  WidgetTester tester,
  TargetPlatform platform,
  LogicalKeyboardKey key,
) async {
  final commandKey = platform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(commandKey);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(commandKey);
  await tester.pump();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byTooltip('文件').first);
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('保存').first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
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
