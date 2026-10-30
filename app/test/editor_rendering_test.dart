import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/editor/editor_rendering.dart';
import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/editor/rust_text_input_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _CoreBootstrap {
  _CoreBootstrap() {
    try {
      core = AlulaCore.load();
    } catch (error) {
      skip = 'alula_core is unavailable; build it first ($error)';
    }
  }

  AlulaCore? core;
  String? skip;
}

final _bootstrap = _CoreBootstrap();

void main() {
  test('logical lines and whitespace retain UTF-16 offsets across CRLF', () {
    const text = '  \tfoo \t\r\n漢👩‍💻  \nשלום\t\n';
    final lines = editorLogicalLines(text);

    expect(lines.map((line) => line.startUtf16), [0, 10, 19, 25]);
    expect(lines.first.contentEndUtf16, 8);
    expect(
      editorIndentGuideOffsets(text, lines.first),
      [3],
    );
    expect(
      editorWhitespaceOffsets(text, lines.first, EditorWhitespaceMode.all),
      [0, 1, 2, 6, 7],
    );
    expect(
      editorWhitespaceOffsets(
        text,
        lines.first,
        EditorWhitespaceMode.trailing,
      ),
      [6, 7],
    );
    expect(
      editorWhitespaceOffsets(text, lines.first, EditorWhitespaceMode.none),
      isEmpty,
    );
  });

  testWidgets(
    'Rust-backed gutter resolves absolute line and paints bidi decorations',
    (tester) async {
      final doc = _bootstrap.core!.openDoc(
        9750,
        'first\n  汉e\u0301 👩‍💻 שלום \t\nthird',
      );
      addTearDown(doc.close);
      final window = RustTextInputWindow.open(
        doc,
        startUtf16: 6,
        maxWindowUtf16: 64,
      );
      final fieldKey = GlobalKey<RustTextInputFieldState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SizedBox(
                width: 420,
                height: 180,
                child: RustTextInputField(
                  key: fieldKey,
                  inputWindow: window,
                  whitespaceMode: EditorWhitespaceMode.all,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final gutterFinder = find.byKey(const ValueKey('rust-editor-gutter'));
      expect(gutterFinder, findsOneWidget);
      expect(
        tester.getRect(gutterFinder).right,
        lessThanOrEqualTo(
          tester
              .getRect(find.byKey(const ValueKey('rust-bounded-text-input')))
              .left,
        ),
      );
      final gutter = tester.widget<CustomPaint>(
        find.descendant(
          of: gutterFinder,
          matching: find.byType(CustomPaint),
        ),
      );
      expect(gutter.painter, isA<EditorGutterPainter>());
      expect((gutter.painter! as EditorGutterPainter).firstLineNumber, 1);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint &&
              widget.painter is EditorTextDecorationPainter,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      final editedWindowText = '${window.text}!';
      fieldKey.currentState!.setEditingValue(TextEditingValue(
        text: editedWindowText,
        selection: TextSelection.collapsed(offset: editedWindowText.length),
      ));
      await tester.pump();
      final updatedGutter = tester.widget<CustomPaint>(
        find.descendant(
          of: gutterFinder,
          matching: find.byType(CustomPaint),
        ),
      );
      expect((updatedGutter.painter! as EditorGutterPainter).text,
          editedWindowText);
      await tester.pump();
      expect(doc.resync().content, 'first\n$editedWindowText');
    },
    skip: _bootstrap.skip != null,
  );

  testWidgets(
    'no-wrap keeps multiline input and scrolls the primary caret into view',
    (tester) async {
      final text = '${List.filled(100, 'longword').join(' ')}\nnext';
      final doc = _bootstrap.core!.openDoc(9752, text);
      addTearDown(doc.close);
      final window = RustTextInputWindow.open(
        doc,
        startUtf16: 0,
        maxWindowUtf16: 2048,
      );
      final horizontalScroll = ScrollController();
      addTearDown(horizontalScroll.dispose);
      final fieldKey = GlobalKey<RustTextInputFieldState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 160,
              child: RustTextInputField(
                key: fieldKey,
                inputWindow: window,
                horizontalScrollController: horizontalScroll,
                showLineNumbers: false,
                showIndentGuides: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(fieldKey.currentState!.editingValue.text, text);
      expect(horizontalScroll.hasClients, isTrue);
      expect(horizontalScroll.position.maxScrollExtent, greaterThan(0));
      final editableState = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      final firstCaret = editableState.renderEditable.getLocalRectForCaret(
        const TextPosition(offset: 0),
      );
      final lastCaret = editableState.renderEditable.getLocalRectForCaret(
        TextPosition(offset: text.indexOf('\n') - 1),
      );
      expect(lastCaret.top, firstCaret.top);

      fieldKey.currentState!.setSelection(
        TextSelection.collapsed(offset: text.indexOf('\n') - 1),
      );
      await tester.pump();
      await tester.pump();

      expect(horizontalScroll.offset, greaterThan(0));
      final viewport = tester.getRect(find.byType(SingleChildScrollView));
      final caret = editableState.renderEditable.getLocalRectForCaret(
        TextPosition(offset: text.indexOf('\n') - 1),
      );
      final caretGlobal =
          editableState.renderEditable.localToGlobal(caret.topLeft);
      expect(caretGlobal.dx, greaterThanOrEqualTo(viewport.left - 1));
      expect(caretGlobal.dx, lessThanOrEqualTo(viewport.right + 1));
    },
    skip: _bootstrap.skip != null,
  );

  testWidgets(
    'word-wrap mode fits the text field and leaves horizontal scrolling idle',
    (tester) async {
      final text = List.filled(100, 'longword').join(' ');
      final doc = _bootstrap.core!.openDoc(9753, text);
      addTearDown(doc.close);
      final window = RustTextInputWindow.open(
        doc,
        startUtf16: 0,
        maxWindowUtf16: 2048,
      );
      final horizontalScroll = ScrollController();
      addTearDown(horizontalScroll.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 160,
              child: RustTextInputField(
                inputWindow: window,
                horizontalScrollController: horizontalScroll,
                showLineNumbers: false,
                showIndentGuides: false,
                wordWrap: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(horizontalScroll.hasClients, isFalse);
      final editableState = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      final firstCaret = editableState.renderEditable.getLocalRectForCaret(
        const TextPosition(offset: 0),
      );
      final lastCaret = editableState.renderEditable.getLocalRectForCaret(
        TextPosition(offset: text.length),
      );
      expect(lastCaret.top, greaterThan(firstCaret.top));
      expect(tester.takeException(), isNull);
    },
    skip: _bootstrap.skip != null,
  );

  testWidgets(
    'no-wrap caret reveal follows RTL horizontal scroll direction',
    (tester) async {
      final line = List.filled(100, 'שלום').join();
      final text = '$line\nend';
      final doc = _bootstrap.core!.openDoc(9754, text);
      addTearDown(doc.close);
      final window = RustTextInputWindow.open(
        doc,
        startUtf16: 0,
        maxWindowUtf16: 2048,
      );
      final horizontalScroll = ScrollController();
      addTearDown(horizontalScroll.dispose);
      final fieldKey = GlobalKey<RustTextInputFieldState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SizedBox(
                width: 320,
                height: 160,
                child: RustTextInputField(
                  key: fieldKey,
                  inputWindow: window,
                  horizontalScrollController: horizontalScroll,
                  showLineNumbers: false,
                  showIndentGuides: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(horizontalScroll.position.axisDirection, AxisDirection.left);
      expect(horizontalScroll.position.maxScrollExtent, greaterThan(0));
      fieldKey.currentState!.setSelection(
        TextSelection.collapsed(offset: line.length - 1),
      );
      await tester.pump();
      await tester.pump();

      expect(horizontalScroll.offset, greaterThan(0));
      final viewport = tester.getRect(find.byType(SingleChildScrollView));
      final editableState = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      final caret = editableState.renderEditable.getLocalRectForCaret(
        TextPosition(offset: line.length - 1),
      );
      final caretGlobal =
          editableState.renderEditable.localToGlobal(caret.topLeft);
      expect(caretGlobal.dx, greaterThanOrEqualTo(viewport.left - 1));
      expect(caretGlobal.dx, lessThanOrEqualTo(viewport.right + 1));
    },
    skip: _bootstrap.skip != null,
  );

  test('Rust line lookup handles a nonzero UTF-16 offset and EOF', () {
    final doc = _bootstrap.core!.openDoc(9751, 'head\n漢👩‍💻\nend\n');
    addTearDown(doc.close);

    expect(resolveEditorDocumentLinePosition(doc, 0).firstLineNumber, 0);
    expect(resolveEditorDocumentLinePosition(doc, 5).firstLineNumber, 1);
    expect(resolveEditorDocumentLinePosition(doc, 11).firstLineNumber, 1);
    expect(resolveEditorDocumentLinePosition(doc, 12).firstLineNumber, 2);
    expect(resolveEditorDocumentLinePosition(doc, 16).firstLineNumber, 3);
  }, skip: _bootstrap.skip != null);
}
