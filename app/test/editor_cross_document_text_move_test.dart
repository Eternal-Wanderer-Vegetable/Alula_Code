import 'package:alula_app/editor/text_drag_drop.dart';
import 'package:alula_app/bridge/alula_core.dart';
import 'package:flutter_test/flutter_test.dart';

String _applyTextOps(String text, List<TextOp> operations) {
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
  group('cross-document text drag move', () {
    const source = EditorTextDragSelection(
      documentId: 61,
      documentVersion: 7,
      startUtf16: 2,
      endUtf16: 7,
    );
    const request = EditorTextDragDropRequest(
      payload: EditorTextDragPayload(
        selection: source,
        selectedText: 'alpha',
        token: 71,
      ),
      targetDocumentId: 62,
      targetDocumentVersion: 9,
      targetOffsetUtf16: 3,
      operation: EditorTextDropOperation.move,
    );

    test('plans deletion and insertion with inverse UTF-16 operations', () {
      final plan = planEditorCrossDocumentTextMove(
        request: request,
        currentSourceDocumentId: 61,
        currentSourceDocumentVersion: 7,
        sourceDocumentLengthUtf16: '🙂alpha!'.length,
        currentSourceText: 'alpha',
        currentTargetDocumentId: 62,
        currentTargetDocumentVersion: 9,
        targetDocumentLengthUtf16: 'B🙂C'.length,
      );

      expect(plan, isNotNull);
      expect(_applyTextOps('🙂alpha!', plan!.sourceForwardOperations), '🙂!');
      expect(_applyTextOps('B🙂C', plan.targetForwardOperations), 'B🙂alphaC');
      expect(plan.sourceCaretUtf16, 2);
      expect(plan.targetCaretUtf16, 8);
      expect(plan.sourceResultLengthUtf16, '🙂!'.length);
      expect(plan.targetResultLengthUtf16, 'B🙂alphaC'.length);
      expect(
        _applyTextOps('🙂!', plan.sourceInverseOperations),
        '🙂alpha!',
      );
      expect(
        _applyTextOps('B🙂alphaC', plan.targetInverseOperations),
        'B🙂C',
      );
    });

    test('rejects stale, mismatched, same-document, and copy requests', () {
      EditorCrossDocumentTextMovePlan? plan({
        EditorTextDragDropRequest value = request,
        int sourceId = 61,
        int sourceVersion = 7,
        int sourceLength = 8,
        String sourceText = 'alpha',
        int targetId = 62,
        int targetVersion = 9,
        int targetLength = 5,
        int targetOffset = 3,
      }) =>
          planEditorCrossDocumentTextMove(
            request: EditorTextDragDropRequest(
              payload: value.payload,
              targetDocumentId: value.targetDocumentId,
              targetDocumentVersion: value.targetDocumentVersion,
              targetOffsetUtf16: targetOffset,
              operation: value.operation,
            ),
            currentSourceDocumentId: sourceId,
            currentSourceDocumentVersion: sourceVersion,
            sourceDocumentLengthUtf16: sourceLength,
            currentSourceText: sourceText,
            currentTargetDocumentId: targetId,
            currentTargetDocumentVersion: targetVersion,
            targetDocumentLengthUtf16: targetLength,
          );

      expect(plan(sourceVersion: 8), isNull);
      expect(plan(sourceText: 'other'), isNull);
      expect(plan(sourceId: 63), isNull);
      expect(plan(targetVersion: 10), isNull);
      expect(plan(targetId: 61), isNull);
      expect(plan(targetOffset: 6), isNull);
      expect(plan(sourceLength: 6), isNull);
      expect(
        plan(
          value: const EditorTextDragDropRequest(
            payload: EditorTextDragPayload(
              selection: source,
              selectedText: 'alpha',
              token: 71,
            ),
            targetDocumentId: 62,
            targetDocumentVersion: 9,
            targetOffsetUtf16: 3,
            operation: EditorTextDropOperation.copy,
          ),
        ),
        isNull,
      );
    });

    test('rejects malformed UTF-16 payloads', () {
      const malformedRequest = EditorTextDragDropRequest(
        payload: EditorTextDragPayload(
          selection: EditorTextDragSelection(
            documentId: 61,
            documentVersion: 7,
            startUtf16: 2,
            endUtf16: 3,
          ),
          selectedText: '\u{D800}',
          token: 72,
        ),
        targetDocumentId: 62,
        targetDocumentVersion: 9,
        targetOffsetUtf16: 3,
        operation: EditorTextDropOperation.move,
      );
      EditorCrossDocumentTextMovePlan? run(EditorTextDragDropRequest value) =>
          planEditorCrossDocumentTextMove(
            request: value,
            currentSourceDocumentId: 61,
            currentSourceDocumentVersion: 7,
            sourceDocumentLengthUtf16: 8,
            currentSourceText: value.payload.selectedText,
            currentTargetDocumentId: 62,
            currentTargetDocumentVersion: 9,
            targetDocumentLengthUtf16: 5,
          );

      expect(run(malformedRequest), isNull);
    });
  });
}
