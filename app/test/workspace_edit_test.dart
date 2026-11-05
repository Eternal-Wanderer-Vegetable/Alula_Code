import 'package:alula_app/editor/workspace_edit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const planner = WorkspaceEditPlanner();

  test('plans unsorted UTF-16 edits across CRLF and LF documents', () {
    const text = 'a🚀\r\n中\nz';
    const edit = WorkspaceEdit([
      WorkspaceDocumentEdit(
        uri: 'file:///a.txt',
        version: 4,
        edits: [
          WorkspaceTextEdit(
            range: WorkspaceTextRange(
              start: WorkspaceTextPosition(1, 0),
              end: WorkspaceTextPosition(1, 1),
            ),
            newText: '文',
          ),
          WorkspaceTextEdit(
            range: WorkspaceTextRange(
              start: WorkspaceTextPosition(0, 1),
              end: WorkspaceTextPosition(0, 3),
            ),
            newText: '🛰️',
          ),
        ],
      ),
      WorkspaceDocumentEdit(
        uri: 'file:///b.txt',
        edits: [
          WorkspaceTextEdit(
            range: WorkspaceTextRange(
              start: WorkspaceTextPosition(0, 0),
              end: WorkspaceTextPosition(0, 1),
            ),
            newText: 'Beta',
          ),
        ],
      ),
    ]);

    final plan = planner.plan(edit, const [
      WorkspaceDocumentSnapshot(
        id: 1,
        uri: 'file:///a.txt',
        version: 4,
        text: text,
      ),
      WorkspaceDocumentSnapshot(
        id: 2,
        uri: 'file:///b.txt',
        version: 2,
        text: 'A',
      ),
    ]);

    expect(plan.documents[0].after, 'a🛰️\r\n文\nz');
    expect(plan.documents[0].baseVersion, 4);
    expect(
      plan.documents[0].ops.map((op) => op.toJson()).toList(),
      [
        {'type': 'delete', 'offset_utf16': 5, 'len_utf16': 1},
        {'type': 'insert', 'offset_utf16': 5, 'text': '文'},
        {'type': 'delete', 'offset_utf16': 1, 'len_utf16': 2},
        {'type': 'insert', 'offset_utf16': 1, 'text': '🛰️'},
      ],
    );
    expect(plan.documents[1].after, 'Beta');
    expect(plan.transactionId, startsWith('workspace-'));
    expect(mapWorkspaceEditOffset(0, plan.documents[0].ops), 0);
    expect(mapWorkspaceEditOffset(4, plan.documents[0].ops), 5);
  });

  test('rejects stale, unopened, read-only, and empty changes', () {
    const snapshot = WorkspaceDocumentSnapshot(
      id: 1,
      uri: 'file:///a.txt',
      version: 2,
      text: 'abc',
    );
    WorkspaceDocumentEdit makeDocument(
            {int? version, String uri = 'file:///a.txt'}) =>
        WorkspaceDocumentEdit(
          uri: uri,
          version: version,
          edits: const [
            WorkspaceTextEdit(
              range: WorkspaceTextRange(
                start: WorkspaceTextPosition(0, 0),
                end: WorkspaceTextPosition(0, 1),
              ),
              newText: 'x',
            ),
          ],
        );

    expect(
      () => planner.plan(WorkspaceEdit([makeDocument(version: 1)]), [snapshot]),
      throwsA(isA<WorkspaceEditException>()),
    );
    expect(
      () => planner.plan(
          WorkspaceEdit([makeDocument(uri: 'file:///missing')]), [snapshot]),
      throwsA(isA<WorkspaceEditException>()),
    );
    expect(
      () => planner.plan(
        WorkspaceEdit([makeDocument()]),
        [
          const WorkspaceDocumentSnapshot(
            id: 1,
            uri: 'file:///a.txt',
            version: 2,
            text: 'abc',
            writable: false,
          ),
        ],
      ),
      throwsA(isA<WorkspaceEditException>()),
    );
    expect(
      () => planner.plan(
        const WorkspaceEdit([
          WorkspaceDocumentEdit(uri: 'file:///a.txt', edits: []),
        ]),
        [snapshot],
      ),
      throwsA(isA<WorkspaceEditException>()),
    );
  });

  test('rejects overlapping and same-position insertions', () {
    const snapshot = WorkspaceDocumentSnapshot(
      id: 1,
      uri: 'file:///a.txt',
      version: 1,
      text: 'abcd',
    );
    WorkspaceTextEdit range(int start, int end, String value) =>
        WorkspaceTextEdit(
          range: WorkspaceTextRange(
            start: WorkspaceTextPosition(0, start),
            end: WorkspaceTextPosition(0, end),
          ),
          newText: value,
        );
    for (final edits in [
      [range(0, 3, 'x'), range(2, 4, 'y')],
      [range(1, 1, 'x'), range(1, 1, 'y')],
    ]) {
      expect(
        () => planner.plan(
          WorkspaceEdit(
              [WorkspaceDocumentEdit(uri: snapshot.uri, edits: edits)]),
          [snapshot],
        ),
        throwsA(isA<WorkspaceEditException>()),
      );
    }
  });

  test('rejects invalid LSP line, character, and surrogate boundaries', () {
    const snapshot = WorkspaceDocumentSnapshot(
      id: 1,
      uri: 'file:///a.txt',
      version: 1,
      text: 'a🚀\r\nb',
    );
    WorkspaceEdit makeEdit(
            WorkspaceTextPosition start, WorkspaceTextPosition end) =>
        WorkspaceEdit([
          WorkspaceDocumentEdit(
            uri: snapshot.uri,
            edits: [
              WorkspaceTextEdit(
                range: WorkspaceTextRange(start: start, end: end),
                newText: 'x',
              ),
            ],
          ),
        ]);
    for (final edit in [
      makeEdit(
          const WorkspaceTextPosition(4, 0), const WorkspaceTextPosition(4, 0)),
      makeEdit(
          const WorkspaceTextPosition(0, 4), const WorkspaceTextPosition(0, 4)),
      makeEdit(
          const WorkspaceTextPosition(0, 2), const WorkspaceTextPosition(0, 3)),
      makeEdit(
          const WorkspaceTextPosition(1, 1), const WorkspaceTextPosition(1, 0)),
    ]) {
      expect(
        () => planner.plan(edit, [snapshot]),
        throwsA(isA<WorkspaceEditException>()),
      );
    }
  });
}
