import 'dart:ui' as ui;

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

  test('range decorations clip absolute UTF-16 spans to the input window', () {
    const leftOverlap =
        EditorRangeDecoration(documentVersion: 1, startUtf16: 1, endUtf16: 5);
    const visible =
        EditorRangeDecoration(documentVersion: 1, startUtf16: 8, endUtf16: 12);
    const rightTouch =
        EditorRangeDecoration(documentVersion: 1, startUtf16: 11, endUtf16: 14);
    const stale =
        EditorRangeDecoration(documentVersion: 0, startUtf16: 7, endUtf16: 9);
    final resolved = resolveEditorRangeDecorations(
      decorations: const [leftOverlap, visible, rightTouch, stale],
      windowVersion: 1,
      windowStartUtf16: 3,
      windowLengthUtf16: 8,
    );

    expect(resolved, hasLength(2));
    expect(resolved[0].decoration, same(leftOverlap));
    expect(
        resolved[0].range, const TextSelection(baseOffset: 0, extentOffset: 2));
    expect(resolved[1].decoration, same(visible));
    expect(
        resolved[1].range, const TextSelection(baseOffset: 5, extentOffset: 8));
  });

  test('range decoration painter draws background and underline at text bounds',
      () async {
    const text = 'abcdef';
    const style = TextStyle(fontFamily: 'monospace', fontSize: 18);
    const decoration = EditorRangeDecoration(
      documentVersion: 1,
      startUtf16: 1,
      endUtf16: 4,
      backgroundColor: Color(0xFFE53935),
      underlineColor: Color(0xFF1565C0),
      underlineWidth: 2,
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = Size(200, 40);
    EditorRangeDecorationPainter(
      text: text,
      windowVersion: 1,
      windowStartUtf16: 0,
      decorations: const [decoration],
      style: style,
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      padding: EdgeInsets.zero,
      scrollController: null,
      paintBackgrounds: true,
    ).paint(canvas, size);
    EditorRangeDecorationPainter(
      text: text,
      windowVersion: 1,
      windowStartUtf16: 0,
      decorations: const [decoration],
      style: style,
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      padding: EdgeInsets.zero,
      scrollController: null,
      paintBackgrounds: false,
    ).paint(canvas, size);
    final image = await recorder.endRecording().toImage(200, 40);
    addTearDown(image.dispose);
    final bytes =
        await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    expect(bytes, isNotNull);

    final textPainter = TextPainter(
      text: const TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: size.width);
    final box = textPainter
        .getBoxesForSelection(
            const TextSelection(baseOffset: 1, extentOffset: 4))
        .single
        .toRect();
    final x = box.center.dx.floor();
    final backgroundY = box.center.dy.floor();
    final underlineY = (box.bottom - decoration.underlineWidth / 2).floor();
    final backgroundOffset = (backgroundY * 200 + x) * 4;
    final underlineOffset = (underlineY * 200 + x) * 4;
    expect(bytes!.getUint8(backgroundOffset), 0xE5);
    expect(bytes.getUint8(backgroundOffset + 1), 0x39);
    expect(bytes.getUint8(underlineOffset + 2), 0xC0);
    expect(bytes.getUint8((30 * 200 + 180) * 4 + 3), 0);
    textPainter.dispose();
  });

  testWidgets(
    'RustTextInputField resolves document decorations against its input window',
    (tester) async {
      final doc = _bootstrap.core!.openDoc(9755, 'header\nneedle\nfooter');
      addTearDown(doc.close);
      final window = RustTextInputWindow.open(
        doc,
        startUtf16: 7,
        maxWindowUtf16: 64,
      );
      final background = EditorRangeDecoration(
        documentVersion: window.version,
        startUtf16: 5,
        endUtf16: 10,
        backgroundColor: const Color(0x407F7FFF),
      );
      final underline = EditorRangeDecoration(
        documentVersion: window.version,
        startUtf16: 9,
        endUtf16: 13,
        underlineColor: const Color(0xFFFFC107),
      );
      const fontFallback = ['Fixture Mono', 'Fixture CJK'];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RustTextInputField(
              inputWindow: window,
              fontFamilyFallback: fontFallback,
              rangeDecorations: [background, underline],
              showIndentGuides: false,
              wordWrap: true,
            ),
          ),
        ),
      );
      await tester.pump();

      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.style.fontFamilyFallback, fontFallback);
      final backgroundFinder = find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter is EditorRangeDecorationPainter &&
            (widget.painter! as EditorRangeDecorationPainter).paintBackgrounds,
      );
      expect(backgroundFinder, findsOneWidget);
      final painter = tester.widget<CustomPaint>(backgroundFinder).painter!
          as EditorRangeDecorationPainter;
      expect(painter.style.fontFamilyFallback, fontFallback);
      expect(painter.windowStartUtf16, 7);
      final resolved = resolveEditorRangeDecorations(
        decorations: painter.decorations,
        windowVersion: painter.windowVersion,
        windowStartUtf16: painter.windowStartUtf16,
        windowLengthUtf16: painter.text.length,
      );
      expect(resolved.map((item) => item.range), [
        const TextSelection(baseOffset: 0, extentOffset: 3),
        const TextSelection(baseOffset: 2, extentOffset: 6),
      ]);
      expect(tester.takeException(), isNull);
    },
    skip: _bootstrap.skip != null,
  );

  testWidgets(
    'Rust token TextSpans are version-gated and preserve IME composition',
    (tester) async {
      final doc = _bootstrap.core!.openDoc(9756, 'prefix\nfn main() {}\n');
      addTearDown(doc.close);
      final window = RustTextInputWindow.open(
        doc,
        startUtf16: 7,
        maxWindowUtf16: 64,
      );
      const keywordColor = Color(0xFFCC66DD);
      const functionColor = Color(0xFF66CCDD);
      const tokens = <Map<String, Object?>>[
        {'start_utf16': 7, 'end_utf16': 9, 'kind': 'keyword'},
        {'start_utf16': 10, 'end_utf16': 14, 'kind': 'function'},
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RustTextInputField(
              inputWindow: window,
              syntaxTokens: tokens,
              syntaxVersion: window.version,
              syntaxTokenColor: (kind) =>
                  kind == 'keyword' ? keywordColor : functionColor,
              showLineNumbers: false,
              showIndentGuides: false,
            ),
          ),
        ),
      );
      await tester.pump();

      var editable = tester.widget<EditableText>(find.byType(EditableText));
      final context = tester.element(find.byType(EditableText));
      final highlighted = editable.controller.buildTextSpan(
        context: context,
        style: editable.style,
        withComposing: false,
      );
      final spans = highlighted.children!.whereType<TextSpan>().toList();
      expect(
        spans.any(
            (span) => span.text == 'fn' && span.style?.color == keywordColor),
        isTrue,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RustTextInputField(
              inputWindow: window,
              syntaxTokens: tokens,
              syntaxVersion: window.version + 1,
              syntaxTokenColor: (kind) =>
                  kind == 'keyword' ? keywordColor : functionColor,
              showLineNumbers: false,
              showIndentGuides: false,
            ),
          ),
        ),
      );
      await tester.pump();
      editable = tester.widget<EditableText>(find.byType(EditableText));
      final stale = editable.controller.buildTextSpan(
        context: tester.element(find.byType(EditableText)),
        style: editable.style,
        withComposing: false,
      );
      expect(stale.toPlainText(), window.text);
      expect(stale.children, isNull);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RustTextInputField(
              inputWindow: window,
              syntaxTokens: tokens,
              syntaxVersion: window.version,
              syntaxTokenColor: (kind) =>
                  kind == 'keyword' ? keywordColor : functionColor,
              showLineNumbers: false,
              showIndentGuides: false,
            ),
          ),
        ),
      );
      await tester.pump();
      editable = tester.widget<EditableText>(find.byType(EditableText));
      final originalValue = editable.controller.value;
      final pendingValue = originalValue.copyWith(
        text: '${originalValue.text}pending',
        selection: TextSelection.collapsed(
          offset: originalValue.text.length + 'pending'.length,
        ),
        composing: TextRange.empty,
      );
      editable.controller.value = pendingValue;
      final pendingSpan = editable.controller.buildTextSpan(
        context: tester.element(find.byType(EditableText)),
        style: editable.style,
        withComposing: false,
      );
      expect(pendingSpan.children, isNull);

      editable.controller.value = editable.controller.value.copyWith(
        text: originalValue.text,
        selection: originalValue.selection,
        composing: const TextRange(start: 3, end: 7),
      );
      final composing = editable.controller.buildTextSpan(
        context: tester.element(find.byType(EditableText)),
        style: editable.style,
        withComposing: true,
      );
      final composingSpans = composing.children!.whereType<TextSpan>().toList();
      expect(
        composingSpans.any((span) =>
            span.text == 'main' &&
            span.style?.color == functionColor &&
            span.style?.decoration == TextDecoration.underline),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
    skip: _bootstrap.skip != null,
  );

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

      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.style.fontFamilyFallback, editorFontFamilyFallbacks);
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
