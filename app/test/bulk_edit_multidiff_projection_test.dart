import 'package:alula_app/editor/bulk_edit_multidiff_projection.dart';
import 'package:alula_app/editor/diff_view_model.dart';
import 'package:alula_app/editor/workspace_edit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('projects selected resources in order with version and transaction id',
      () {
    final edit = WorkspaceEdit(
      [
        _document('file:///b.txt', 2, [
          _textEdit(0, 5, 8, 'new'),
        ]),
        _document('file:///a.txt', 4, [
          _textEdit(0, 0, 3, 'two'),
        ]),
      ],
      transactionId: 'bulk-7',
    );
    const snapshots = [
      WorkspaceDocumentSnapshot(
        id: 10,
        uri: 'file:///a.txt',
        version: 4,
        text: 'one\n',
      ),
      WorkspaceDocumentSnapshot(
        id: 11,
        uri: 'file:///b.txt',
        version: 2,
        text: 'keep old\n',
      ),
    ];

    final projection = BulkEditMultiDiffProjection(
      selectedEdit: edit,
      snapshots: snapshots,
    );

    expect(projection.transactionId, 'bulk-7');
    expect(projection.resources.map((resource) => resource.uri), [
      'file:///b.txt',
      'file:///a.txt',
    ]);
    expect(
        projection.resources.map((resource) => resource.documentId), [11, 10]);
    expect(
        projection.resources.map((resource) => resource.baseVersion), [2, 4]);
    expect(projection.resources.map((resource) => resource.originalText), [
      'keep old\n',
      'one\n',
    ]);
    expect(projection.resources.map((resource) => resource.modifiedText), [
      'keep new\n',
      'two\n',
    ]);
    expect(
      projection.resources.every((resource) => !resource.diff.isApproximate),
      isTrue,
    );
    expect(snapshots.map((snapshot) => snapshot.text), ['one\n', 'keep old\n']);
  });

  test('preserves BOM, CRLF, and UTF-16 edit boundaries in the projection', () {
    const before = '\uFEFFa🚀\r\nend\r\n';
    final projection = BulkEditMultiDiffProjection(
      selectedEdit: WorkspaceEdit([
        _document('file:///emoji.txt', 9, [
          _textEdit(0, 2, 4, '🛰️'),
        ]),
      ]),
      snapshots: const [
        WorkspaceDocumentSnapshot(
          id: 3,
          uri: 'file:///emoji.txt',
          version: 9,
          text: before,
        ),
      ],
    );

    final resource = projection.resources.single;
    expect(resource.originalText, before);
    expect(resource.modifiedText, '\uFEFFa🛰️\r\nend\r\n');
    expect(resource.diff.rows.first.kind, DiffViewRowKind.modified);
    expect(resource.diff.rows.first.originalText, '\uFEFFa🚀\r');
    expect(resource.diff.rows.first.modifiedText, '\uFEFFa🛰️\r');
  });

  test('includes selected resources only and rejects an all-no-op edit', () {
    final selected = BulkEditMultiDiffProjection(
      selectedEdit: WorkspaceEdit([
        _document('file:///selected.txt', 1, [
          _textEdit(0, 0, 3, 'new'),
        ]),
      ]),
      snapshots: const [
        WorkspaceDocumentSnapshot(
          id: 1,
          uri: 'file:///selected.txt',
          version: 1,
          text: 'old',
        ),
      ],
    );
    expect(selected.resources.map((resource) => resource.uri), [
      'file:///selected.txt',
    ]);

    expect(
      () => BulkEditMultiDiffProjection(
        selectedEdit: WorkspaceEdit([
          _document('file:///same.txt', 1, [
            _textEdit(0, 0, 3, 'old'),
          ]),
        ]),
        snapshots: const [
          WorkspaceDocumentSnapshot(
            id: 2,
            uri: 'file:///same.txt',
            version: 1,
            text: 'old',
          ),
        ],
      ),
      throwsA(isA<BulkEditMultiDiffException>()),
    );
  });

  test('freezes resource edits and exposes immutable projection lists', () {
    final edits = <WorkspaceTextEdit>[_textEdit(0, 0, 3, 'new')];
    final documents = <WorkspaceDocumentEdit>[
      _document('file:///a.txt', 1, edits),
    ];
    final projection = BulkEditMultiDiffProjection(
      selectedEdit: WorkspaceEdit(documents),
      snapshots: const [
        WorkspaceDocumentSnapshot(
          id: 1,
          uri: 'file:///a.txt',
          version: 1,
          text: 'old',
        ),
      ],
    );
    edits.clear();
    documents.clear();

    expect(projection.resources, hasLength(1));
    expect(projection.resources.single.edits.single.newText, 'new');
    expect(
      () => projection.resources.add(projection.resources.single),
      throwsUnsupportedError,
    );
    expect(
      () => projection.resources.single.edits.add(_textEdit(0, 0, 0, 'x')),
      throwsUnsupportedError,
    );
  });

  test('rejects missing, extra, duplicate, read-only, and stale snapshots', () {
    final edit = WorkspaceEdit([
      _document('file:///a.txt', 1, [_textEdit(0, 0, 3, 'new')]),
    ]);
    expect(
      () =>
          BulkEditMultiDiffProjection(selectedEdit: edit, snapshots: const []),
      throwsA(isA<BulkEditMultiDiffException>()),
    );
    expect(
      () => BulkEditMultiDiffProjection(
        selectedEdit: edit,
        snapshots: const [
          WorkspaceDocumentSnapshot(
            id: 1,
            uri: 'file:///a.txt',
            version: 1,
            text: 'old',
          ),
          WorkspaceDocumentSnapshot(
            id: 2,
            uri: 'file:///other.txt',
            version: 1,
            text: 'old',
          ),
        ],
      ),
      throwsA(isA<BulkEditMultiDiffException>()),
    );
    expect(
      () => BulkEditMultiDiffProjection(
        selectedEdit: WorkspaceEdit([
          _document('file:///a.txt', 1, [_textEdit(0, 0, 3, 'new')]),
          _document('file:///b.txt', 1, [_textEdit(0, 0, 3, 'new')]),
        ]),
        snapshots: const [
          WorkspaceDocumentSnapshot(
            id: 1,
            uri: 'file:///a.txt',
            version: 1,
            text: 'old',
          ),
          WorkspaceDocumentSnapshot(
            id: 2,
            uri: 'file:///a.txt',
            version: 1,
            text: 'old',
          ),
        ],
      ),
      throwsA(isA<BulkEditMultiDiffException>()),
    );
    expect(
      () => BulkEditMultiDiffProjection(
        selectedEdit: edit,
        snapshots: const [
          WorkspaceDocumentSnapshot(
            id: 1,
            uri: 'file:///a.txt',
            version: 1,
            text: 'old',
            writable: false,
          ),
        ],
      ),
      throwsA(isA<BulkEditMultiDiffException>()),
    );
    expect(
      () => BulkEditMultiDiffProjection(
        selectedEdit: WorkspaceEdit([
          _document('file:///a.txt', 2, [_textEdit(0, 0, 3, 'new')]),
        ]),
        snapshots: const [
          WorkspaceDocumentSnapshot(
            id: 1,
            uri: 'file:///a.txt',
            version: 1,
            text: 'old',
          ),
        ],
      ),
      throwsA(isA<BulkEditMultiDiffException>()),
    );
  });

  test('rejects duplicate edit resources, overlaps, and surrogate splits', () {
    expect(
      () => BulkEditMultiDiffProjection(
        selectedEdit: WorkspaceEdit([
          _document('file:///a.txt', 1, [_textEdit(0, 0, 1, 'x')]),
          _document('file:///a.txt', 1, [_textEdit(0, 0, 1, 'y')]),
        ]),
        snapshots: const [
          WorkspaceDocumentSnapshot(
            id: 1,
            uri: 'file:///a.txt',
            version: 1,
            text: 'old',
          ),
          WorkspaceDocumentSnapshot(
            id: 1,
            uri: 'file:///a.txt',
            version: 1,
            text: 'old',
          ),
        ],
      ),
      throwsA(isA<BulkEditMultiDiffException>()),
    );
    expect(
      () => BulkEditMultiDiffProjection(
        selectedEdit: WorkspaceEdit([
          _document('file:///a.txt', 1, [
            _textEdit(0, 0, 2, 'x'),
            _textEdit(0, 1, 3, 'y'),
          ]),
        ]),
        snapshots: const [
          WorkspaceDocumentSnapshot(
            id: 1,
            uri: 'file:///a.txt',
            version: 1,
            text: 'abcd',
          ),
        ],
      ),
      throwsA(isA<BulkEditMultiDiffException>()),
    );
    expect(
      () => BulkEditMultiDiffProjection(
        selectedEdit: WorkspaceEdit([
          _document('file:///a.txt', 1, [
            _textEdit(0, 2, 2, 'x'),
          ]),
        ]),
        snapshots: const [
          WorkspaceDocumentSnapshot(
            id: 1,
            uri: 'file:///a.txt',
            version: 1,
            text: 'a🚀b',
          ),
        ],
      ),
      throwsA(isA<BulkEditMultiDiffException>()),
    );
  });

  test('rejects every aggregate limit before exposing a partial projection',
      () {
    final oneDocumentEdit = WorkspaceEdit([
      _document('file:///a.txt', 1, [_textEdit(0, 0, 3, 'new')]),
    ]);
    const snapshot = WorkspaceDocumentSnapshot(
      id: 1,
      uri: 'file:///a.txt',
      version: 1,
      text: 'old',
    );
    for (final limits in [
      const BulkEditMultiDiffLimits(maxAggregateUtf16CodeUnits: 1),
      const BulkEditMultiDiffLimits(maxAggregateLines: 1),
      const BulkEditMultiDiffLimits(maxAggregateRows: 1),
      const BulkEditMultiDiffLimits(maxAggregateLineWork: 1),
      const BulkEditMultiDiffLimits(maxAggregateLineTraceCells: 1),
      const BulkEditMultiDiffLimits(maxAggregateWordInputCodeUnits: 0),
      const BulkEditMultiDiffLimits(maxAggregateWordWork: 1),
      const BulkEditMultiDiffLimits(maxAggregateWordTraceCells: 1),
    ]) {
      expect(
        () => BulkEditMultiDiffProjection(
          selectedEdit: oneDocumentEdit,
          snapshots: const [snapshot],
          limits: limits,
        ),
        throwsA(isA<BulkEditMultiDiffException>()),
      );
    }
  });

  test('rejects too many resources and caller limits above hard ceilings', () {
    final twoDocuments = WorkspaceEdit([
      _document('file:///a.txt', 1, [_textEdit(0, 0, 3, 'new')]),
      _document('file:///b.txt', 1, [_textEdit(0, 0, 3, 'new')]),
    ]);
    const snapshots = [
      WorkspaceDocumentSnapshot(
        id: 1,
        uri: 'file:///a.txt',
        version: 1,
        text: 'old',
      ),
      WorkspaceDocumentSnapshot(
        id: 2,
        uri: 'file:///b.txt',
        version: 1,
        text: 'old',
      ),
    ];
    expect(
      () => BulkEditMultiDiffProjection(
        selectedEdit: twoDocuments,
        snapshots: snapshots,
        limits: const BulkEditMultiDiffLimits(maxResources: 1),
      ),
      throwsA(isA<BulkEditMultiDiffException>()),
    );
    expect(
      () => BulkEditMultiDiffProjection(
        selectedEdit: twoDocuments,
        snapshots: snapshots,
        limits: const BulkEditMultiDiffLimits(maxResources: 129),
      ),
      throwsA(isA<BulkEditMultiDiffException>()),
    );
  });
}

WorkspaceDocumentEdit _document(
  String uri,
  int version,
  List<WorkspaceTextEdit> edits,
) =>
    WorkspaceDocumentEdit(uri: uri, version: version, edits: edits);

WorkspaceTextEdit _textEdit(
  int line,
  int start,
  int end,
  String newText,
) =>
    WorkspaceTextEdit(
      range: WorkspaceTextRange(
        start: WorkspaceTextPosition(line, start),
        end: WorkspaceTextPosition(line, end),
      ),
      newText: newText,
    );
