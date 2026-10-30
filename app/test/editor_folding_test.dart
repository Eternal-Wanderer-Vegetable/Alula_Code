import 'package:alula_app/bridge/alula_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:alula_app/editor/editor_folding.dart';
import 'package:alula_app/editor/editor_rendering.dart';
import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/editor/rust_text_input_window.dart';

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
  group('buildEditorFoldLayout', () {
    const text =
        'fn outer() {\r\n  😀();\r\n  fn inner() {\r\n    act();\r\n  }\r\n}\r\nlast();\r\n';
    const outer = EditorFoldSymbol(
      kind: 'function',
      name: 'outer',
      startUtf16: 0,
      line: 1,
      endLine: 6,
    );
    const inner = EditorFoldSymbol(
      kind: 'function',
      name: 'inner',
      startUtf16: 25,
      line: 3,
      endLine: 5,
    );

    test('folds preserve the UTF-16 line ranges and hide nested controls', () {
      final layout = buildEditorFoldLayout(
        text: text,
        firstDocumentLine: 0,
        symbols: [outer, inner],
        collapsedKeys: {outer.key},
      );

      expect(layout.foldableLineIndices, {0});
      expect(layout.collapsedLineIndices, {0});
      expect(layout.hiddenLineIndices, {1, 2, 3, 4, 5});
      expect(layout.collapsedRanges.single.hiddenStartUtf16, 14);
      expect(layout.collapsedRanges.single.hiddenEndUtf16, 59);
    });

    test('nested regions remain independently foldable when the parent is open',
        () {
      final layout = buildEditorFoldLayout(
        text: text,
        firstDocumentLine: 0,
        symbols: [outer, inner],
        collapsedKeys: {inner.key},
      );

      expect(layout.foldableByLine.keys, {0, 2});
      expect(layout.collapsedLineIndices, {2});
      expect(layout.hiddenLineIndices, {3, 4});
    });

    test('a collapsed scope clips to a bounded window inside its body', () {
      const windowText = '    act();\r\n  }\r\n}\r\n';
      final layout = buildEditorFoldLayout(
        text: windowText,
        firstDocumentLine: 3,
        symbols: [outer],
        collapsedKeys: {outer.key},
      );

      expect(layout.foldableLineIndices, isEmpty);
      expect(layout.hiddenLineIndices, {0, 1, 2});
      expect(layout.collapsedRanges.single.headerLineIndex, -1);
    });

    test('document projection merges hidden rows and maps both directions', () {
      final projection = EditorDocumentLineProjection(
        documentLineCount: 14,
        hiddenRanges: const [
          EditorDocumentLineRange(startLine: 10, endLineExclusive: 12),
          EditorDocumentLineRange(startLine: 4, endLineExclusive: 8),
          EditorDocumentLineRange(startLine: 2, endLineExclusive: 5),
        ],
      );

      expect(
        projection.hiddenRanges,
        const [
          EditorDocumentLineRange(startLine: 2, endLineExclusive: 8),
          EditorDocumentLineRange(startLine: 10, endLineExclusive: 12),
        ],
      );
      expect(projection.visibleLineCount, 6);
      expect(
        List.generate(14, projection.documentLineToVisibleLine),
        [0, 1, 1, 1, 1, 1, 1, 1, 2, 3, 3, 3, 4, 5],
      );
      expect(
        List.generate(6, projection.visibleLineToDocumentLine),
        [0, 1, 8, 9, 12, 13],
      );
      expect(projection.visibleLineToDocumentBoundary(6), 14);
      expect(
        projection.visibleLineCountInRange(startLine: 1, endLineExclusive: 13),
        4,
      );
    });
  });

  testWidgets('Rust scope folding keeps source offsets and expands on caret',
      (tester) async {
    const text =
        'fn outer() {\n  fn inner() {\n    value();\n  }\n  after_inner();\n}\nfn after() {}\n';
    final doc = _bootstrap.core!.openDoc(21800, text);
    addTearDown(doc.close);
    final window = RustTextInputWindow.open(
      doc,
      startUtf16: 0,
      maxWindowUtf16: 256,
    );
    final fieldKey = GlobalKey<RustTextInputFieldState>();
    var reportedFoldRanges = const <EditorDocumentLineRange>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 240,
            child: RustTextInputField(
              key: fieldKey,
              inputWindow: window,
              enableCodeFolding: true,
              onFoldRangesChanged: (documentId, version, ranges) {
                reportedFoldRanges = ranges;
              },
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    final editableState = tester.state<EditableTextState>(
      find.byType(EditableText),
    );
    final afterOffset = text.indexOf('fn after');
    final beforeFoldTop = editableState.renderEditable
        .getLocalRectForCaret(TextPosition(offset: afterOffset))
        .top;
    final gutter = tester.getRect(
      find.byKey(const ValueKey<String>('rust-editor-gutter')),
    );
    final gutterPaintBefore = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('rust-editor-gutter')),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter! as EditorGutterPainter;
    expect(gutterPaintBefore.foldableLineIndices, contains(0));
    await tester.tapAt(Offset(gutter.left + 6, gutter.top + 10));
    await tester.pump();
    final gutterPaintAfter = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('rust-editor-gutter')),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter! as EditorGutterPainter;
    expect(gutterPaintAfter.collapsedLineIndices, {0});
    expect(gutterPaintAfter.hiddenLineIndices, {1, 2, 3, 4, 5});
    expect(
      reportedFoldRanges,
      const [EditorDocumentLineRange(startLine: 1, endLineExclusive: 6)],
    );

    final foldedTop = editableState.renderEditable
        .getLocalRectForCaret(TextPosition(offset: afterOffset))
        .top;
    expect(foldedTop, lessThan(beforeFoldTop - 20));
    expect(fieldKey.currentState!.editingValue.text, text);
    expect(doc.resync().content, text);

    fieldKey.currentState!.setSelection(
      TextSelection.collapsed(offset: text.indexOf('  fn inner')),
    );
    await tester.pump();
    final expandedTop = editableState.renderEditable
        .getLocalRectForCaret(TextPosition(offset: afterOffset))
        .top;
    expect(expandedTop, closeTo(beforeFoldTop, 1));
    expect(fieldKey.currentState!.editingValue.text, text);
    expect(reportedFoldRanges, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }, skip: _bootstrap.skip != null);
}
