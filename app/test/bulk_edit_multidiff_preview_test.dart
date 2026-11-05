import 'dart:async';

import 'package:alula_app/editor/bulk_edit_multidiff_preview.dart';
import 'package:alula_app/editor/bulk_edit_multidiff_projection.dart';
import 'package:alula_app/editor/diff_view_model.dart';
import 'package:alula_app/editor/workspace_edit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders ordered resources and switches the paired diff',
      (tester) async {
    final projection = _projection();
    final before = _projectionInputs(projection);
    await _openPreview(tester, projection);

    expect(find.text('重构预览'), findsOneWidget);
    expect(find.byKey(const ValueKey('bulk-multidiff-resource-0')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('bulk-multidiff-resource-1')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('bulk-multidiff-resource-2')),
        findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('bulk-multidiff-selected-resource')),
          )
          .data,
      'b.dart',
    );
    expect(
      projection.resources.map((resource) => resource.uri),
      [
        'file:///workspace/b.dart',
        'file:///workspace/a.dart',
        'file:///workspace/new-file.txt'
      ],
    );
    expect(
      projection.resources[0].diff.rows
          .any((row) => row.kind == DiffViewRowKind.deleted),
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('bulk-multidiff-resource-1')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('bulk-multidiff-selected-resource')),
          )
          .data,
      'a.dart',
    );
    final original = tester.widget<SelectableText>(
      find.byKey(const ValueKey('bulk-multidiff-original-text-0')),
    );
    final modified = tester.widget<SelectableText>(
      find.byKey(const ValueKey('bulk-multidiff-modified-text-0')),
    );
    expect(original.textSpan!.toPlainText(), 'old value');
    expect(modified.textSpan!.toPlainText(), 'new value');
    expect(
      original.textSpan!.children!.any(
        (span) => span.style?.backgroundColor != null,
      ),
      isTrue,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('bulk-multidiff-original-line-0')),
          )
          .data,
      '1',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('bulk-multidiff-modified-line-0')),
          )
          .data,
      '1',
    );

    await tester.tap(find.byKey(const ValueKey('bulk-multidiff-resource-2')));
    await tester.pumpAndSettle();
    expect(
      projection.resources[2].diff.rows.first.kind,
      DiffViewRowKind.inserted,
    );
    expect(
      tester
          .widget<SelectableText>(
            find.byKey(const ValueKey('bulk-multidiff-modified-text-0')),
          )
          .textSpan!
          .toPlainText(),
      'created',
    );

    await tester.tap(find.byKey(const ValueKey('bulk-multidiff-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bulk-multidiff-dialog')), findsNothing);
    expect(_projectionInputs(projection), before);
  });

  testWidgets('supports keyboard resource navigation and Escape close',
      (tester) async {
    final projection = _projection();
    final before = _projectionInputs(projection);
    await _openPreview(tester, projection);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('bulk-multidiff-selected-resource')),
          )
          .data,
      'a.dart',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bulk-multidiff-dialog')), findsNothing);
    expect(_projectionInputs(projection), before);
  });

  testWidgets('uses a compact layout and exposes resource semantics',
      (tester) async {
    tester.view.physicalSize = const Size(620, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final projection = _projection();
    await _openPreview(tester, projection);

    expect(find.byKey(const ValueKey('bulk-multidiff-resource-heading')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('bulk-multidiff-selected-resource')),
        findsOneWidget);
    expect(
      find.bySemanticsLabel('b.dart, 1 selected text edits'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('preserves Unicode UTF-16 edits and CRLF rows', (tester) async {
    final projection = BulkEditMultiDiffProjection(
      selectedEdit: WorkspaceEdit([
        _document('file:///workspace/unicode.txt', 3, [
          _textEdit(0, 1, 0, 3, '🧪'),
        ]),
      ]),
      snapshots: const [
        WorkspaceDocumentSnapshot(
          id: 15,
          uri: 'file:///workspace/unicode.txt',
          version: 3,
          text: 'a🙂\r\nnext\r\n',
        ),
      ],
    );

    await _openPreview(tester, projection);

    final row = projection.resources.single.diff.rows.first;
    expect(row.kind, DiffViewRowKind.modified);
    expect(row.originalText, 'a🙂\r');
    expect(row.modifiedText, 'a🧪\r');
    expect(row.originalLineNumber, 1);
    expect(row.modifiedLineNumber, 1);
    expect(row.wordChanges, isNotEmpty);
    final rowSemantics = tester.widget<Semantics>(
      find.byKey(const ValueKey('bulk-multidiff-row-semantics-0')),
    );
    expect(rowSemantics.properties.label, '已修改，原始行 1，预览行 1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('lazily builds rows near the per-resource row ceiling',
      (tester) async {
    final projection = _nearRowLimitProjection();
    expect(projection.resources, hasLength(1));
    expect(projection.resources[0].diff.rows, hasLength(8192));
    await _openPreview(tester, projection);

    expect(
      find.byKey(const ValueKey('bulk-multidiff-row-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bulk-multidiff-row-8191')),
      findsNothing,
    );
    final builtRows = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
                'bulk-multidiff-row-',
              ),
    );
    expect(builtRows.evaluate().length, lessThan(80));
  });
}

Future<void> _openPreview(
  WidgetTester tester,
  BulkEditMultiDiffProjection projection,
) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            key: const ValueKey('open-bulk-multidiff'),
            onPressed: () => unawaited(showBulkEditMultiDiffPreview(
              context: context,
              projection: projection,
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.byKey(const ValueKey('open-bulk-multidiff')));
  await tester.pumpAndSettle();
}

BulkEditMultiDiffProjection _projection() => BulkEditMultiDiffProjection(
      selectedEdit: WorkspaceEdit([
        _document('file:///workspace/b.dart', 2, [
          _textEdit(1, 0, 2, 0, ''),
        ]),
        _document('file:///workspace/a.dart', 4, [
          _textEdit(0, 0, 0, 3, 'new'),
        ]),
        _document('file:///workspace/new-file.txt', 1, [
          _textEdit(0, 0, 0, 0, 'created\n'),
        ]),
      ], transactionId: 'visual-preview'),
      snapshots: const [
        WorkspaceDocumentSnapshot(
          id: 10,
          uri: 'file:///workspace/a.dart',
          version: 4,
          text: 'old value\n',
        ),
        WorkspaceDocumentSnapshot(
          id: 11,
          uri: 'file:///workspace/b.dart',
          version: 2,
          text: 'keep\nremove\n',
        ),
        WorkspaceDocumentSnapshot(
          id: 12,
          uri: 'file:///workspace/new-file.txt',
          version: 1,
          text: '',
        ),
      ],
    );

BulkEditMultiDiffProjection _nearRowLimitProjection() {
  const lineCount = 8192;
  final linesA = List<String>.generate(lineCount, (index) => 'a-line-$index');
  final textA = linesA.join('\n');
  return BulkEditMultiDiffProjection(
    selectedEdit: WorkspaceEdit([
      _document('file:///workspace/large-a.txt', 8, [
        _textEdit(
          lineCount - 1,
          0,
          lineCount - 1,
          linesA.last.length,
          'changed-a-last-line',
        ),
      ]),
    ]),
    snapshots: [
      WorkspaceDocumentSnapshot(
        id: 13,
        uri: 'file:///workspace/large-a.txt',
        version: 8,
        text: textA,
      ),
    ],
  );
}

WorkspaceDocumentEdit _document(
  String uri,
  int version,
  List<WorkspaceTextEdit> edits,
) =>
    WorkspaceDocumentEdit(uri: uri, version: version, edits: edits);

WorkspaceTextEdit _textEdit(
  int startLine,
  int startColumn,
  int endLine,
  int endColumn,
  String newText,
) =>
    WorkspaceTextEdit(
      range: WorkspaceTextRange(
        start: WorkspaceTextPosition(startLine, startColumn),
        end: WorkspaceTextPosition(endLine, endColumn),
      ),
      newText: newText,
    );

List<Object> _projectionInputs(BulkEditMultiDiffProjection projection) => [
      for (final resource in projection.resources) ...[
        resource.uri,
        resource.documentId,
        resource.baseVersion,
        resource.originalText,
        resource.modifiedText,
        for (final edit in resource.edits)
          [
            edit.range.start.line,
            edit.range.start.character,
            edit.range.end.line,
            edit.range.end.character,
            edit.newText,
          ],
      ],
    ];
