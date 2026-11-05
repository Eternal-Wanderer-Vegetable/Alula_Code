import 'package:alula_app/editor/bulk_edit_preview.dart';
import 'package:alula_app/editor/workspace_edit.dart';
import 'package:flutter_test/flutter_test.dart';

WorkspaceTextEdit _edit(String newText, {int line = 0}) => WorkspaceTextEdit(
      range: WorkspaceTextRange(
        start: WorkspaceTextPosition(line, 0),
        end: WorkspaceTextPosition(line, 1),
      ),
      newText: newText,
    );

void main() {
  test('starts selected and preserves input order and transaction metadata',
      () {
    final session = BulkEditPreviewSession(
      WorkspaceEdit(
        [
          WorkspaceDocumentEdit(
            uri: 'file:///a.dart',
            version: 7,
            edits: [_edit('first'), _edit('second', line: 1)],
          ),
          WorkspaceDocumentEdit(
            uri: 'file:///b.dart',
            edits: [_edit('third')],
          ),
        ],
        transactionId: 'tx-20a',
      ),
    );

    expect(session.selectionState, BulkEditPreviewSelectionState.all);
    expect(session.selectedEditCount, 3);
    expect(session.documents.map((document) => document.uri), [
      'file:///a.dart',
      'file:///b.dart',
    ]);
    expect(
      session.documents.first.selectionState,
      BulkEditPreviewSelectionState.all,
    );

    session.setEditSelected(0, 1, false);
    final filtered = session.toWorkspaceEdit();
    expect(filtered.transactionId, 'tx-20a');
    expect(filtered.documents.map((document) => document.uri), [
      'file:///a.dart',
      'file:///b.dart',
    ]);
    expect(filtered.documents[0].version, 7);
    expect(filtered.documents[0].edits.map((edit) => edit.newText), ['first']);
    expect(filtered.documents[1].version, isNull);
    expect(filtered.documents[1].edits.single.newText, 'third');
  });

  test('keeps duplicate text edits independently selectable', () {
    final duplicate = _edit('same');
    final session = BulkEditPreviewSession(
      WorkspaceEdit([
        WorkspaceDocumentEdit(
          uri: 'file:///repeat.txt',
          edits: [duplicate, duplicate],
        ),
      ]),
    );

    expect(session.setEditSelected(0, 1, false), isTrue);
    expect(session.setEditSelected(0, 1, false), isFalse);
    expect(session.selectedEditCount, 1);
    expect(session.selectionState, BulkEditPreviewSelectionState.some);
    expect(session.toWorkspaceEdit().documents.single.edits, hasLength(1));
    expect(session.toWorkspaceEdit().documents.single.edits.single.newText,
        'same');
  });

  test('document selection, inversion, and global selection revise once', () {
    final session = BulkEditPreviewSession(
      WorkspaceEdit([
        WorkspaceDocumentEdit(
          uri: 'file:///a.txt',
          edits: [_edit('a'), _edit('b', line: 1)],
        ),
        WorkspaceDocumentEdit(uri: 'file:///b.txt', edits: [_edit('c')]),
      ]),
    );

    expect(session.setDocumentSelected(0, false), isTrue);
    expect(session.revision, 1);
    expect(session.selectionStateForDocument(0),
        BulkEditPreviewSelectionState.none);
    expect(session.selectionState, BulkEditPreviewSelectionState.some);
    expect(session.setDocumentSelected(0, false), isFalse);
    expect(session.revision, 1);

    expect(session.invertDocumentSelection(0), isTrue);
    expect(session.revision, 2);
    expect(session.selectedEditCount, 3);
    expect(session.invertDocumentSelection(0), isTrue);
    expect(session.revision, 3);
    expect(session.selectedEditCount, 1);

    expect(session.clearAll(), isTrue);
    expect(session.revision, 4);
    expect(session.clearAll(), isFalse);
    expect(session.revision, 4);
    expect(session.selectionState, BulkEditPreviewSelectionState.none);
    expect(session.selectAll(), isTrue);
    expect(session.revision, 5);
    expect(session.selectAll(), isFalse);
    expect(session.revision, 5);
  });

  test('freezes mutable source lists and returns unmodifiable edit lists', () {
    final sourceEdits = [_edit('original')];
    final sourceDocuments = [
      WorkspaceDocumentEdit(uri: 'file:///a.txt', edits: sourceEdits),
    ];
    final session = BulkEditPreviewSession(WorkspaceEdit(sourceDocuments));
    sourceEdits
      ..clear()
      ..add(_edit('mutated'));
    sourceDocuments.clear();

    final filtered = session.toWorkspaceEdit();
    expect(filtered.documents, hasLength(1));
    expect(filtered.documents.single.edits.single.newText, 'original');
    expect(() => filtered.documents.add(filtered.documents.single),
        throwsUnsupportedError);
    expect(
      () => filtered.documents.single.edits.add(_edit('another')),
      throwsUnsupportedError,
    );
    expect(() => session.documents.clear(), throwsUnsupportedError);
    expect(
        () => session.documents.single.edits.clear(), throwsUnsupportedError);
  });

  test('rejects empty previews, duplicate resources, and empty selection', () {
    expect(
      () => BulkEditPreviewSession(const WorkspaceEdit([])),
      throwsA(isA<BulkEditPreviewException>()),
    );
    expect(
      () => BulkEditPreviewSession(
        WorkspaceEdit([
          WorkspaceDocumentEdit(uri: 'file:///same.txt', edits: [_edit('a')]),
          WorkspaceDocumentEdit(uri: 'file:///same.txt', edits: [_edit('b')]),
        ]),
      ),
      throwsA(isA<BulkEditPreviewException>()),
    );

    final session = BulkEditPreviewSession(
      WorkspaceEdit([
        WorkspaceDocumentEdit(uri: 'file:///a.txt', edits: [_edit('a')]),
      ]),
    );
    session.clearAll();
    expect(
      session.toWorkspaceEdit,
      throwsA(isA<BulkEditPreviewException>()),
    );
  });

  test('rejects out-of-range selection indexes', () {
    final session = BulkEditPreviewSession(
      WorkspaceEdit([
        WorkspaceDocumentEdit(uri: 'file:///a.txt', edits: [_edit('a')]),
      ]),
    );
    expect(() => session.setDocumentSelected(1, false), throwsRangeError);
    expect(() => session.isEditSelected(0, 1), throwsRangeError);
  });

  test('enforces document and text-edit count limits without truncating', () {
    final atDocumentLimit = [
      for (var index = 0; index < BulkEditPreviewSession.maxDocuments; index++)
        WorkspaceDocumentEdit(uri: 'file:///$index.txt', edits: const []),
    ];
    expect(
      BulkEditPreviewSession(WorkspaceEdit(atDocumentLimit)).documents,
      hasLength(BulkEditPreviewSession.maxDocuments),
    );
    expect(
      () => BulkEditPreviewSession(
        WorkspaceEdit([
          ...atDocumentLimit,
          WorkspaceDocumentEdit(uri: 'file:///overflow.txt', edits: const []),
        ]),
      ),
      throwsA(isA<BulkEditPreviewException>()),
    );

    final repeated = _edit('x');
    final atEditLimit = List<WorkspaceTextEdit>.filled(
      BulkEditPreviewSession.maxEdits,
      repeated,
    );
    expect(
      BulkEditPreviewSession(
        WorkspaceEdit([
          WorkspaceDocumentEdit(uri: 'file:///many.txt', edits: atEditLimit),
        ]),
      ).editCount,
      BulkEditPreviewSession.maxEdits,
    );
    expect(
      () => BulkEditPreviewSession(
        WorkspaceEdit([
          WorkspaceDocumentEdit(
            uri: 'file:///many.txt',
            edits: [...atEditLimit, repeated],
          ),
        ]),
      ),
      throwsA(isA<BulkEditPreviewException>()),
    );
  });

  test('counts UTF-8 bytes and rejects malformed UTF-16', () {
    final exactlyAtLimit = List<String>.filled(
      BulkEditPreviewSession.maxInputUtf8Bytes - 1,
      'a',
    ).join();
    expect(
      BulkEditPreviewSession(
        WorkspaceEdit([
          WorkspaceDocumentEdit(
            uri: 'u',
            edits: [_edit(exactlyAtLimit)],
          ),
        ]),
      ).editCount,
      1,
    );
    expect(
      () => BulkEditPreviewSession(
        WorkspaceEdit([
          WorkspaceDocumentEdit(
            uri: 'u',
            edits: [_edit('${exactlyAtLimit}a')],
          ),
        ]),
      ),
      throwsA(isA<BulkEditPreviewException>()),
    );

    expect(
      BulkEditPreviewSession(
        WorkspaceEdit([
          WorkspaceDocumentEdit(uri: 'file:///😀.txt', edits: [_edit('é🚀')]),
        ]),
      ).editCount,
      1,
    );
    expect(
      () => BulkEditPreviewSession(
        WorkspaceEdit([
          WorkspaceDocumentEdit(
            uri: 'file:///a.txt',
            edits: [_edit(String.fromCharCode(0xD800))],
          ),
        ]),
      ),
      throwsA(isA<BulkEditPreviewException>()),
    );
  });
}
