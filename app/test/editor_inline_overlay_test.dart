import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/editor/editor_rendering.dart';
import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/editor/rust_text_input_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final eol in ['\n', '\r\n']) {
    final encoding = eol == '\n' ? 'LF' : 'CRLF';
    for (final wordWrap in [true, false]) {
      for (final indent in ['    ', '\t']) {
        final indentation = indent == '\t' ? 'tab' : 'spaces';
        testWidgets(
            'inline overlay keeps code and gutter positions together in $encoding with $indentation (wrap: $wordWrap)',
            (tester) async {
          final core = AlulaCore.load();
          final source = '\ufeff// 🦊 first$eol'
              '${indent}second row$eol'
              'third row$eol';
          final doc = core.openDoc(9756, source);
          addTearDown(doc.close);
          final window = RustTextInputWindow.open(
            doc,
            startUtf16: 0,
            maxWindowUtf16: 128,
            selectionUtf16: 5,
          );
          final scroll = ScrollController();
          addTearDown(scroll.dispose);
          final semantics = tester.ensureSemantics();
          Future<void> show({required bool inline}) async {
            await tester.pumpWidget(MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 480,
                  height: 350,
                  child: RustTextInputField(
                    inputWindow: window,
                    scrollController: scroll,
                    showLineNumbers: true,
                    wordWrap: wordWrap,
                    semanticsLabel: '编辑区',
                    caretOverlay: inline ? const Text('诊断详情') : null,
                    caretOverlayAnchorUtf16: inline ? 5 : null,
                    reserveCaretOverlayLineSpace: inline,
                  ),
                ),
              ),
            ));
            await tester.pumpAndSettle();
          }

          final offsets = [
            0,
            source.indexOf('${indent}second row'),
            source.indexOf('second row'),
            source.indexOf('third row'),
          ];
          List<Rect> locations() {
            final editable =
                tester.state<EditableTextState>(find.byType(EditableText));
            expect(editable.renderEditable.plainText, source);
            expect(editable.widget.controller.text, source);
            expect(editable.widget.controller.selection,
                const TextSelection.collapsed(offset: 5));
            expect(doc.resync().content, source);
            return [
              for (final offset in offsets)
                editable.renderEditable
                    .getLocalRectForCaret(TextPosition(offset: offset)),
            ];
          }

          List<double> gutterTops() {
            final paints =
                tester.widgetList<CustomPaint>(find.byType(CustomPaint));
            final gutter = paints
                .map((paint) => paint.painter)
                .whereType<EditorGutterPainter>()
                .single;
            final painter = TextPainter(
              text: gutter.textSpan,
              textDirection: gutter.textDirection,
              textScaler: gutter.textScaler,
              textWidthBasis: TextWidthBasis.parent,
              strutStyle: gutter.strutStyle,
            )..layout(maxWidth: gutter.textWidth - gutter.padding.horizontal);
            try {
              return [
                for (final offset in offsets)
                  painter
                      .getOffsetForCaret(
                          TextPosition(offset: offset), Rect.zero)
                      .dy,
              ];
            } finally {
              painter.dispose();
            }
          }

          try {
            await show(inline: false);
            final before = locations();
            final initialGutter = gutterTops();
            await show(inline: true);
            final after = locations();
            final inlineGutter = gutterTops();
            final slot =
                find.byKey(const ValueKey('rust-editor-inline-overlay'));
            expect(slot, findsOneWidget);
            expect(after.first.top, closeTo(before.first.top, 1));
            expect(after[1].top - before[1].top, greaterThan(100));
            expect(after[2].left - after[1].left,
                closeTo(before[2].left - before[1].left, 1));
            expect(after[2].top, closeTo(after[1].top, 1));
            expect(after.last.top - after[1].top,
                closeTo(before.last.top - before[1].top, 1));
            for (var index = 0; index < offsets.length; index++) {
              expect(inlineGutter[index] - initialGutter[index],
                  closeTo(after[index].top - before[index].top, 1));
            }
            expect(
              tester
                  .getSemantics(find.bySemanticsLabel('编辑区'))
                  .getSemanticsData()
                  .value,
              source,
            );
            await show(inline: false);
            expect(locations(), before);
            expect(gutterTops(), initialGutter);
            expect(slot, findsNothing);
          } finally {
            semantics.dispose();
            await tester.pumpWidget(const SizedBox());
          }
        });
      }
    }
  }
}
