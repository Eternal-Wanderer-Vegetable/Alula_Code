import 'package:alula_app/editor/text_drag_drop.dart';
import 'package:alula_app/bridge/alula_core.dart';
import 'package:flutter_test/flutter_test.dart';

class _CoreBootstrap {
  _CoreBootstrap() {
    try {
      core = AlulaCore.load();
    } on Object catch (error) {
      skip = 'alula_core is unavailable; build it first ($error)';
    }
  }

  AlulaCore? core;
  String? skip;
}

final _coreBootstrap = _CoreBootstrap();

String applyTextOps(String text, List<TextOp> operations) {
  var value = text;
  for (final operation in operations) {
    switch (operation.type) {
      case OpType.insert:
        value = value.replaceRange(
          operation.offsetUtf16,
          operation.offsetUtf16,
          operation.text!,
        );
      case OpType.delete:
        value = value.replaceRange(
          operation.offsetUtf16,
          operation.offsetUtf16 + operation.lenUtf16!,
          '',
        );
    }
  }
  return value;
}

void main() {
  group('editor text drag metadata', () {
    test('encodes a bounded selection and rejects malformed local data', () {
      const payload = EditorTextDragSelection(
        documentId: 7,
        documentVersion: 12,
        startUtf16: 4,
        endUtf16: 9,
      );

      expect(
        EditorTextDragSelection.tryParseLocalData(payload.toLocalData()),
        payload,
      );
      expect(EditorTextDragSelection.tryParseLocalData(null), isNull);
      expect(
        EditorTextDragSelection.tryParseLocalData({'kind': 'foreign'}),
        isNull,
      );
      expect(
        EditorTextDragSelection.tryParseLocalData({
          ...payload.toLocalData(),
          'endUtf16': 3,
        }),
        isNull,
      );
      expect(
        EditorTextDragSelection.tryParseLocalData({
          ...payload.toLocalData(),
          'endUtf16': maxEditorTextDragUtf16 + 5,
        }),
        isNull,
      );
    });

    test('round trips bounded local text and rejects payload mismatches', () {
      const payload = EditorTextDragPayload(
        selection: EditorTextDragSelection(
          documentId: 7,
          documentVersion: 12,
          startUtf16: 4,
          endUtf16: 6,
        ),
        selectedText: '😀',
        token: 31,
      );

      expect(
        EditorTextDragPayload.tryParseLocalData(payload.toLocalData()),
        isNotNull,
      );
      expect(
        EditorTextDragPayload.tryParseLocalData(payload.toLocalData())!
            .selectedText,
        '😀',
      );
      expect(
        EditorTextDragPayload.tryParseLocalData({
          ...payload.toLocalData(),
          'selectedText': 'x',
        }),
        isNull,
      );
      expect(
        EditorTextDragPayload.tryParseLocalData({
          ...payload.toLocalData(),
          'token': 0,
        }),
        isNull,
      );
    });
  });

  group('same-document drag edits', () {
    test('moves text before its source with emoji-safe UTF-16 offsets', () {
      const sourceText = 'A😀BC';
      const payload = EditorTextDragSelection(
        documentId: 3,
        documentVersion: 8,
        startUtf16: 3,
        endUtf16: 4,
      );
      final plan = planSameDocumentTextDrag(
        source: payload,
        targetDocumentId: 3,
        targetDocumentVersion: 8,
        targetDocumentLengthUtf16: sourceText.length,
        targetOffsetUtf16: 0,
        selectedText: 'B',
        operation: EditorTextDropOperation.move,
      );

      expect(plan, isNotNull);
      final moved = applyTextOps(sourceText, plan!.forward);
      expect(moved, 'BA😀C');
      expect(moved.length, sourceText.length);
      expect(applyTextOps(moved, plan.inverse), sourceText);
      expect(plan.afterCaretUtf16, 1);
    });

    test('moves a CRLF and Unicode selection after its original range', () {
      const sourceText = 'alpha\r\nβeta😀z';
      final start = sourceText.indexOf('βeta');
      const selected = 'βeta';
      final payload = EditorTextDragSelection(
        documentId: 4,
        documentVersion: 19,
        startUtf16: start,
        endUtf16: start + selected.length,
      );
      final plan = planSameDocumentTextDrag(
        source: payload,
        targetDocumentId: 4,
        targetDocumentVersion: 19,
        targetDocumentLengthUtf16: sourceText.length,
        targetOffsetUtf16: sourceText.length,
        selectedText: selected,
        operation: EditorTextDropOperation.move,
      );

      expect(plan, isNotNull);
      final moved = applyTextOps(sourceText, plan!.forward);
      expect(moved, 'alpha\r\n😀zβeta');
      expect(applyTextOps(moved, plan.inverse), sourceText);
      expect(plan.resultLengthUtf16, sourceText.length);
    });

    test('copies at a selection boundary and undo removes only the copy', () {
      const sourceText = 'a😀bc';
      const payload = EditorTextDragSelection(
        documentId: 9,
        documentVersion: 5,
        startUtf16: 1,
        endUtf16: 3,
      );
      final plan = planSameDocumentTextDrag(
        source: payload,
        targetDocumentId: 9,
        targetDocumentVersion: 5,
        targetDocumentLengthUtf16: sourceText.length,
        targetOffsetUtf16: 3,
        selectedText: '😀',
        operation: EditorTextDropOperation.copy,
      );

      expect(plan, isNotNull);
      final copied = applyTextOps(sourceText, plan!.forward);
      expect(copied, 'a😀😀bc');
      expect(applyTextOps(copied, plan.inverse), sourceText);
      expect(plan.resultLengthUtf16, sourceText.length + 2);
    });

    test('rejects stale, cross-document, invalid, and oversized drops', () {
      const source = EditorTextDragSelection(
        documentId: 1,
        documentVersion: 2,
        startUtf16: 1,
        endUtf16: 2,
      );
      EditorTextDragEditPlan? plan({
        EditorTextDragSelection payload = source,
        int targetDocumentId = 1,
        int targetVersion = 2,
        int length = 4,
        int target = 0,
        String selected = 'b',
      }) =>
          planSameDocumentTextDrag(
            source: payload,
            targetDocumentId: targetDocumentId,
            targetDocumentVersion: targetVersion,
            targetDocumentLengthUtf16: length,
            targetOffsetUtf16: target,
            selectedText: selected,
            operation: EditorTextDropOperation.move,
          );

      expect(plan(targetVersion: 3), isNull);
      expect(plan(targetDocumentId: 2), isNull);
      expect(plan(target: 5), isNull);
      expect(plan(selected: 'wrong'), isNull);
      expect(
        plan(
          payload: const EditorTextDragSelection(
            documentId: 1,
            documentVersion: 2,
            startUtf16: 1,
            endUtf16: maxEditorTextDragUtf16 + 2,
          ),
          length: maxEditorTextDragUtf16 + 3,
          selected: List<String>.filled(maxEditorTextDragUtf16 + 1, 'x').join(),
        ),
        isNull,
      );
    });

    test('drops inside a source selection and move-to-boundary are no-ops', () {
      const source = EditorTextDragSelection(
        documentId: 2,
        documentVersion: 4,
        startUtf16: 1,
        endUtf16: 4,
      );
      for (final target in [1, 2, 3, 4]) {
        expect(
          planSameDocumentTextDrag(
            source: source,
            targetDocumentId: 2,
            targetDocumentVersion: 4,
            targetDocumentLengthUtf16: 6,
            targetOffsetUtf16: target,
            selectedText: 'bcd',
            operation: EditorTextDropOperation.move,
          ),
          isNull,
        );
      }
      expect(
        planSameDocumentTextDrag(
          source: source,
          targetDocumentId: 2,
          targetDocumentVersion: 4,
          targetDocumentLengthUtf16: 6,
          targetOffsetUtf16: 2,
          selectedText: 'bcd',
          operation: EditorTextDropOperation.copy,
        ),
        isNull,
      );
    });

    test('applies and undoes a BOM CRLF emoji move through the Rust FFI', () {
      const original = '\u{FEFF}left\r\n🦊beta\r\nright';
      final doc = _coreBootstrap.core!.openDoc(97581, original);
      addTearDown(doc.close);
      const selected = 'beta';
      final start = original.indexOf(selected);
      final plan = planSameDocumentTextDrag(
        source: EditorTextDragSelection(
          documentId: doc.id,
          documentVersion: doc.version,
          startUtf16: start,
          endUtf16: start + selected.length,
        ),
        targetDocumentId: doc.id,
        targetDocumentVersion: doc.version,
        targetDocumentLengthUtf16: original.length,
        targetOffsetUtf16: 0,
        selectedText: selected,
        operation: EditorTextDropOperation.move,
      );

      expect(plan, isNotNull);
      doc.applyWith(doc.version, plan!.forward);
      expect(doc.resync().content, 'beta\u{FEFF}left\r\n🦊\r\nright');
      doc.applyWith(doc.version, plan.inverse);
      expect(doc.resync().content, original);
    }, skip: _coreBootstrap.skip);
  });
}
