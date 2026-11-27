import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/editor/rust_text_input_window.dart';
import 'package:alula_app/workbench/diagnostic_navigation_peek.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('diagnostic details request three header lines and up to 17 body lines',
      () {
    int lines(String message) => DiagnosticNavigationPeek(
          fileName: 'source.rs',
          ordinal: 1,
          total: 1,
          severity: 1,
          message: message,
          onClose: () {},
        ).preferredHeightInEditorLines;

    expect(lines(''), 4);
    expect(lines('one'), 4);
    expect(lines('one\r\ntwo\rthree\nfour'), 7);
    expect(lines('one\n'), 5);
    expect(lines(List.filled(30, 'row').join('\n')), 20);
  });

  testWidgets('inline diagnostic height follows its content and viewport',
      (tester) async {
    const source = '// 🦊 first\nsecond row\nthird row\n';
    final core = AlulaCore.load();
    final doc = core.openDoc(9758, source);
    addTearDown(doc.close);
    final window = RustTextInputWindow.open(
      doc,
      startUtf16: 0,
      maxWindowUtf16: 128,
      selectionUtf16: 5,
    );
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final slot = find.byKey(const ValueKey('rust-editor-inline-overlay'));
    final region = find.byKey(const ValueKey('editor-region'));

    Future<double> layout(int lines, double height) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            key: const ValueKey('editor-region'),
            width: 480,
            height: height,
            child: RustTextInputField(
              inputWindow: window,
              scrollController: scroll,
              caretOverlay: const Text('Diagnostics'),
              caretOverlayAnchorUtf16: 5,
              reserveCaretOverlayLineSpace: true,
              caretOverlayHeightInLines: lines,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(slot, findsOneWidget);
      final pane = tester.getRect(slot);
      final editor = tester.getRect(region);
      expect(pane.top, greaterThanOrEqualTo(editor.top));
      expect(pane.bottom, lessThanOrEqualTo(editor.bottom));
      final editable =
          tester.state<EditableTextState>(find.byType(EditableText));
      expect(editable.renderEditable.plainText, source);
      expect(editable.widget.controller.selection,
          const TextSelection.collapsed(offset: 5));
      expect(doc.resync().content, source);
      return pane.height;
    }

    final short = await layout(4, 420);
    final long = await layout(8, 420);
    expect(long - short, greaterThan(60));
    final capped = await layout(20, 180);
    expect(capped, greaterThan(short));
    expect(capped, lessThan(long));
    expect(await layout(4, 420), closeTo(short, 1));
    await tester.pumpWidget(const SizedBox());
  });
}
