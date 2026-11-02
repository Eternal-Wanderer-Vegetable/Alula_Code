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

  group('external plain-text drops', () {
    test('normalizes line endings and keeps Unicode insert undoable', () {
      const text = 'x\r\n😀\ry';
      final plan = planEditorExternalPlainTextDrop(
        targetDocumentId: 12,
        targetDocumentVersion: 5,
        currentDocumentId: 12,
        currentDocumentVersion: 5,
        targetDocumentLengthUtf16: 4,
        targetOffsetUtf16: 3,
        text: text,
      );

      expect(plan, isNotNull);
      expect(plan!.plainText, 'x\n😀\ny');
      expect(plan.caretAfterInsertUtf16, 9);
      final inserted = applyTextOps('A😀B', plan.forwardOperations);
      expect(inserted, 'A😀x\n😀\nyB');
      expect(inserted.length, plan.resultLengthUtf16);
      expect(applyTextOps(inserted, plan.inverseOperations), 'A😀B');
    });

    test('rejects stale, out-of-range, empty, invalid, and oversized text', () {
      EditorExternalTextDropPlan? plan({
        int documentId = 12,
        int documentVersion = 5,
        int currentVersion = 5,
        int documentLength = 4,
        int offset = 2,
        String text = 'ok',
      }) =>
          planEditorExternalPlainTextDrop(
            targetDocumentId: documentId,
            targetDocumentVersion: documentVersion,
            currentDocumentId: 12,
            currentDocumentVersion: currentVersion,
            targetDocumentLengthUtf16: documentLength,
            targetOffsetUtf16: offset,
            text: text,
          );

      expect(plan(documentId: 13), isNull);
      expect(plan(documentVersion: 4), isNull);
      expect(plan(offset: 5), isNull);
      expect(plan(text: ''), isNull);
      expect(plan(text: String.fromCharCode(0xD800)), isNull);
      expect(
        plan(text: List<String>.filled(maxEditorTextDragUtf16 + 1, 'x').join()),
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

  group('cross-document text drag copy', () {
    const source = EditorTextDragSelection(
      documentId: 11,
      documentVersion: 8,
      startUtf16: 2,
      endUtf16: 7,
    );
    const request = EditorTextDragDropRequest(
      payload: EditorTextDragPayload(
        selection: source,
        selectedText: 'alpha',
        token: 44,
      ),
      targetDocumentId: 22,
      targetDocumentVersion: 10,
      targetOffsetUtf16: 3,
      operation: EditorTextDropOperation.copy,
    );

    test('plans a bounded emoji-safe insertion with inverse operations', () {
      final plan = planEditorCrossDocumentTextCopy(
        request: request,
        currentSourceDocumentId: 11,
        currentSourceDocumentVersion: 8,
        sourceDocumentLengthUtf16: '🙂alpha'.length,
        currentSourceText: 'alpha',
        currentTargetDocumentId: 22,
        currentTargetDocumentVersion: 10,
        targetDocumentLengthUtf16: 'B🙂C'.length,
      );

      expect(plan, isNotNull);
      expect(
        applyTextOps('B🙂C', plan!.forward),
        'B🙂alphaC',
      );
      expect(plan.afterCaretUtf16, 8);
      expect(plan.resultLengthUtf16, 'B🙂alphaC'.length);
      expect(applyTextOps('B🙂alphaC', plan.inverse), 'B🙂C');
    });

    test('rejects stale, same-document, move, and malformed source snapshots',
        () {
      EditorTextDragEditPlan? plan({
        EditorTextDragDropRequest value = request,
        int sourceId = 11,
        int sourceVersion = 8,
        int sourceLength = 7,
        String sourceText = 'alpha',
        int targetId = 22,
        int targetVersion = 10,
        int targetLength = 4,
        int targetOffset = 3,
      }) =>
          planEditorCrossDocumentTextCopy(
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

      expect(plan(sourceVersion: 9), isNull);
      expect(plan(sourceText: 'other'), isNull);
      expect(plan(sourceId: 12), isNull);
      expect(plan(targetVersion: 11), isNull);
      expect(plan(targetOffset: 5), isNull);
      expect(plan(targetId: 11), isNull);
      expect(
        plan(
          value: const EditorTextDragDropRequest(
            payload: EditorTextDragPayload(
              selection: source,
              selectedText: 'alpha',
              token: 44,
            ),
            targetDocumentId: 22,
            targetDocumentVersion: 10,
            targetOffsetUtf16: 3,
            operation: EditorTextDropOperation.move,
          ),
        ),
        isNull,
      );
      expect(
        plan(
          value: const EditorTextDragDropRequest(
            payload: EditorTextDragPayload(
              selection: source,
              selectedText: '\u{D800}',
              token: 44,
            ),
            targetDocumentId: 22,
            targetDocumentVersion: 10,
            targetOffsetUtf16: 3,
            operation: EditorTextDropOperation.copy,
          ),
        ),
        isNull,
      );
    });

    test('copies through Rust without changing the source document', () {
      const sourceText = 'left 😀beta right';
      const targetText = 'target 🙂';
      final sourceDoc = _coreBootstrap.core!.openDoc(97611, sourceText);
      final targetDoc = _coreBootstrap.core!.openDoc(97612, targetText);
      addTearDown(sourceDoc.close);
      addTearDown(targetDoc.close);
      const selectedText = 'beta';
      final start = sourceText.indexOf(selectedText);
      final actualRequest = EditorTextDragDropRequest(
        payload: EditorTextDragPayload(
          selection: EditorTextDragSelection(
            documentId: sourceDoc.id,
            documentVersion: sourceDoc.version,
            startUtf16: start,
            endUtf16: start + selectedText.length,
          ),
          selectedText: selectedText,
          token: 45,
        ),
        targetDocumentId: targetDoc.id,
        targetDocumentVersion: targetDoc.version,
        targetOffsetUtf16: targetText.length,
        operation: EditorTextDropOperation.copy,
      );
      final sourceRange = sourceDoc.readRange(
        start,
        maxLenUtf16: selectedText.length,
      );
      final plan = planEditorCrossDocumentTextCopy(
        request: actualRequest,
        currentSourceDocumentId: sourceDoc.id,
        currentSourceDocumentVersion: sourceRange.version,
        sourceDocumentLengthUtf16: sourceRange.totalUtf16Length,
        currentSourceText: sourceRange.text,
        currentTargetDocumentId: targetDoc.id,
        currentTargetDocumentVersion: targetDoc.version,
        targetDocumentLengthUtf16: targetText.length,
      );

      expect(plan, isNotNull);
      targetDoc.applyWith(actualRequest.targetDocumentVersion, plan!.forward);
      expect(sourceDoc.resync().content, sourceText);
      expect(targetDoc.resync().content, '$targetText$selectedText');
      targetDoc.applyWith(targetDoc.version, plan.inverse);
      expect(targetDoc.resync().content, targetText);
    }, skip: _coreBootstrap.skip);
  });
}
