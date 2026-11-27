import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/editor/editor_rendering.dart';
import 'package:alula_app/editor/editor_scroll_controller.dart';
import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/editor/rust_text_input_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final long in [false, true]) {
    for (final emptyLastLine in [false, true]) {
      testWidgets(
          'terminal diagnostic preserves EOF with '
          'long=$long and emptyLastLine=$emptyLastLine', (tester) async {
        final newline = emptyLastLine ? '\r\n' : '\n';
        final source = [
          ...List.filled(long ? 70 : 1, 'source'),
          'final 🦊',
          if (emptyLastLine) '',
        ].join(newline);
        final core = AlulaCore.load();
        final doc = core.openDoc(
          56470 + (long ? 2 : 0) + (emptyLastLine ? 1 : 0),
          source,
        );
        addTearDown(doc.close);
        final input = RustTextInputWindow.open(
          doc,
          startUtf16: 0,
          maxWindowUtf16: 2048,
          selectionUtf16: source.length,
        );
        final scroll = EditorScrollController();
        final focus = FocusNode();
        addTearDown(scroll.dispose);
        addTearDown(focus.dispose);
        final slot = find.byKey(const ValueKey('rust-editor-inline-overlay'));
        final viewport = find.byKey(const ValueKey('editor-region'));
        final field = find.byType(EditableText);

        Future<void> layout({required bool show}) async {
          await tester.pumpWidget(MaterialApp(
            home: Scaffold(
              body: SizedBox(
                key: const ValueKey('editor-region'),
                width: 480,
                height: 260,
                child: RustTextInputField(
                  inputWindow: input,
                  focusNode: focus,
                  scrollController: scroll,
                  wordWrap: emptyLastLine,
                  caretOverlay: show ? const Text('Diagnostic') : null,
                  caretOverlayAnchorUtf16: show ? source.length : null,
                  reserveCaretOverlayLineSpace: true,
                  caretOverlayHeightInLines: 4,
                ),
              ),
            ),
          ));
          await tester.pumpAndSettle();
        }

        Rect eof() {
          final editor = tester.state<EditableTextState>(field).renderEditable;
          final rect = editor.getLocalRectForCaret(
            TextPosition(offset: source.length),
          );
          return editor.localToGlobal(rect.topLeft) & rect.size;
        }

        await layout(show: false);
        focus.requestFocus();
        await tester.pumpAndSettle();
        tester.state<EditableTextState>(field).bringIntoView(
              TextPosition(offset: source.length),
            );
        await tester.pumpAndSettle();
        final before = eof();
        final position = scroll.position as EditorScrollPosition;
        final base = position.maxScrollExtent;

        await layout(show: true);
        expect(slot, findsOneWidget);
        final opened = eof();
        final pane = tester.getRect(slot);
        final bounds = tester.getRect(viewport);
        expect(pane.top, closeTo(opened.bottom + 4, 0.5));
        expect(pane.bottom, lessThanOrEqualTo(bounds.bottom));
        expect(opened.top, greaterThanOrEqualTo(bounds.top));
        expect(opened.left, closeTo(before.left, 0.5));
        expect(position.unpaddedMaxScrollExtent, base);
        if (long) {
          expect(position.maxScrollExtent, greaterThan(base));
          final revealed = position.pixels;
          scroll.jumpTo(0);
          await tester.pumpAndSettle();
          expect(position.pixels, 0);
          scroll.jumpTo(revealed);
          await tester.pumpAndSettle();
          expect(tester.getRect(slot).top, closeTo(pane.top, 0.5));
        } else {
          expect(position.maxScrollExtent, base);
          expect(opened, before);
        }

        final editable = tester.state<EditableTextState>(field);
        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await tester.pumpAndSettle();
        final selection = editable.widget.controller.selection;
        expect(selection.isCollapsed, isTrue);
        expect(selection.extentOffset, source.length);
        expect(editable.renderEditable.plainText, source);
        expect(doc.resync().content, source);
        expect(doc.version, 1);

        await layout(show: false);
        expect(slot, findsNothing);
        expect(position.maxScrollExtent, base);
        expect(position.pixels, lessThanOrEqualTo(base + 0.5));
        expect(eof().left, closeTo(before.left, 0.5));
        expect(doc.resync().content, source);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  for (final newline in ['\n', '\r\n']) {
    final useCrLf = newline.length == 2;
    for (final rowCount in [1, 9, 40]) {
      testWidgets(
          'diagnostic before final break preserves EOF '
          '(CRLF=$useCrLf, rows=$rowCount)', (tester) async {
        final source = [
          ...List.filled(rowCount - 1, 'source'),
          'final 🐙 marker',
          '',
        ].join(newline);
        final anchor = source.indexOf('marker');
        final core = AlulaCore.load();
        final doc = core.openDoc(56600 + rowCount, source);
        addTearDown(doc.close);
        final input = RustTextInputWindow.open(
          doc,
          startUtf16: 0,
          maxWindowUtf16: 2048,
          selectionUtf16: anchor,
        );
        final scroll = EditorScrollController();
        final focus = FocusNode();
        addTearDown(scroll.dispose);
        addTearDown(focus.dispose);
        final slot = find.byKey(const ValueKey('rust-editor-inline-overlay'));
        final viewport = find.byKey(const ValueKey('editor-region'));
        final field = find.byType(EditableText);

        Future<void> layout({required bool show}) async {
          await tester.pumpWidget(MaterialApp(
            home: Scaffold(
              body: SizedBox(
                key: const ValueKey('editor-region'),
                width: 480,
                height: 260,
                child: RustTextInputField(
                  inputWindow: input,
                  focusNode: focus,
                  scrollController: scroll,
                  wordWrap: useCrLf,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 15,
                    height: 1.4,
                  ),
                  caretOverlay: show ? const Text('Diagnostic') : null,
                  caretOverlayAnchorUtf16: show ? anchor : null,
                  reserveCaretOverlayLineSpace: true,
                  caretOverlayHeightInLines: 4,
                ),
              ),
            ),
          ));
          await tester.pumpAndSettle();
        }

        EditorGutterPainter gutter() => tester
            .widget<CustomPaint>(find.byWidgetPredicate(
              (widget) =>
                  widget is CustomPaint &&
                  widget.painter is EditorGutterPainter,
            ))
            .painter! as EditorGutterPainter;
        final afterBreak = TextPosition(offset: source.length);
        EditableTextState editor() => tester.state<EditableTextState>(field);
        Rect caret(TextPosition position) {
          final render = editor().renderEditable;
          final rect = render.getLocalRectForCaret(position);
          return render.localToGlobal(rect.topLeft) & rect.size;
        }

        await layout(show: false);
        focus.requestFocus();
        editor().bringIntoView(TextPosition(offset: anchor));
        await tester.pumpAndSettle();
        final before = caret(afterBreak);
        final position = scroll.position as EditorScrollPosition;
        final base = position.maxScrollExtent;

        await layout(show: true);
        expect(slot, findsOneWidget);
        final pane = tester.getRect(slot);
        final eof = caret(afterBreak);
        final bounds = tester.getRect(viewport);
        expect(pane.top, closeTo(eof.top + 4, 0.5));
        expect(
            pane.bottom + 4 + eof.height, lessThanOrEqualTo(bounds.bottom + 1));
        expect(eof.left, closeTo(before.left, 0.5));
        expect(position.unpaddedMaxScrollExtent, base);
        if (rowCount == 1) {
          expect(position.maxScrollExtent, base);
        } else {
          expect(position.maxScrollExtent, greaterThan(base));
        }
        if (rowCount == 9) expect(base, 0);

        expect(gutter().terminalGapHeight, pane.height + 8);
        final displayedEof =
            eof.center.translate(60, gutter().terminalGapHeight);
        expect(editor().renderEditable.getPositionForPoint(displayedEof).offset,
            source.length);
        await tester.tapAt(displayedEof);
        await tester.pumpAndSettle();
        expect(editor().widget.controller.selection,
            TextSelection.collapsed(offset: source.length));
        expect(editor().renderEditable.plainText, source);

        await layout(show: false);
        expect(slot, findsNothing);
        expect(gutter().terminalGapHeight, 0);
        expect(position.maxScrollExtent, base);
        expect(position.pixels, lessThanOrEqualTo(base + 0.5));
        expect(doc.resync().content, source);
        expect(doc.version, 1);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
