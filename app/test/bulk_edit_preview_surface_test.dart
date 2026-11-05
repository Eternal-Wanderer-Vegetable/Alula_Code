import 'dart:async';

import 'package:alula_app/editor/bulk_edit_preview_surface.dart';
import 'package:alula_app/editor/workspace_edit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('resource and edit selection filter the Multi Diff preview',
      (tester) async {
    final fixture = _fixture();
    var applyCalls = 0;
    await _open(tester, fixture, (selected) async {
      applyCalls++;
      return true;
    });

    await tester.tap(
      find.byKey(const ValueKey('bulk-edit-preview-edit-checkbox-0-1')),
    );
    await tester.tap(
      find.byKey(const ValueKey('bulk-edit-preview-resource-checkbox-1')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Checkbox>(
            find.byKey(
              const ValueKey('bulk-edit-preview-resource-checkbox-0'),
            ),
          )
          .value,
      isNull,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('bulk-edit-preview-selected-count')),
          )
          .data,
      '已选择 1 / 3 项',
    );

    await tester.tap(find.byKey(const ValueKey('bulk-edit-preview-preview')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(
            find.byKey(
              const ValueKey(
                'bulk-edit-preview-multidiff-selected-resource-count',
              ),
            ),
          )
          .data,
      '1 项更改 · v7',
    );
    expect(
      tester
          .widget<SelectableText>(
            find.byKey(
              const ValueKey(
                'bulk-edit-preview-multidiff-modified-text-0',
              ),
            ),
          )
          .textSpan!
          .toPlainText(),
      'ALPHA',
    );
    await tester.tap(
      find.byKey(const ValueKey('bulk-edit-preview-multidiff-close')),
    );
    await tester.pumpAndSettle();

    expect(applyCalls, 0);
    expect(fixture.edit.documents.first.edits, hasLength(2));
    expect(fixture.snapshots.first.text, 'alpha\nbeta\n');
  });

  testWidgets(
      'Apply passes only selected immutable edits and closes on success',
      (tester) async {
    final fixture = _fixture();
    final applied = <WorkspaceEdit>[];
    await _open(tester, fixture, (selected) async {
      applied.add(selected);
      return true;
    });

    await tester.tap(
      find.byKey(const ValueKey('bulk-edit-preview-edit-checkbox-0-1')),
    );
    await tester.tap(
      find.byKey(const ValueKey('bulk-edit-preview-resource-checkbox-1')),
    );
    await tester.tap(find.byKey(const ValueKey('bulk-edit-preview-apply')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('bulk-edit-preview-dialog')), findsNothing);
    expect(applied, hasLength(1));
    expect(applied.single.transactionId, 'bulk-transaction');
    expect(applied.single.documents, hasLength(1));
    expect(applied.single.documents.single.uri, 'file:///workspace/a.txt');
    expect(applied.single.documents.single.edits, hasLength(1));
    expect(
      applied.single.documents.single.edits.single.newText,
      'ALPHA',
    );
    expect(fixture.edit.documents.first.edits, hasLength(2));
    expect(fixture.snapshots.first.text, 'alpha\nbeta\n');
  });

  testWidgets('failed Apply stays open and Discard does not call Apply again',
      (tester) async {
    final fixture = _fixture();
    var applyCalls = 0;
    await _open(tester, fixture, (selected) async {
      applyCalls++;
      return false;
    });

    await tester.tap(find.byKey(const ValueKey('bulk-edit-preview-apply')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('bulk-edit-preview-dialog')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('bulk-edit-preview-error')), findsOneWidget);
    expect(applyCalls, 1);

    await tester.tap(find.byKey(const ValueKey('bulk-edit-preview-discard')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('bulk-edit-preview-dialog')), findsNothing);
    expect(applyCalls, 1);
  });

  testWidgets('Escape and empty selection discard without invoking Apply',
      (tester) async {
    final fixture = _fixture();
    var applyCalls = 0;
    await _open(tester, fixture, (selected) async {
      applyCalls++;
      return true;
    });

    await tester.tap(find.byKey(const ValueKey('bulk-edit-preview-clear-all')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('bulk-edit-preview-apply')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('bulk-edit-preview-preview')),
          )
          .onPressed,
      isNull,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('bulk-edit-preview-dialog')), findsNothing);
    expect(applyCalls, 0);
  });

  testWidgets('stale snapshot is rejected before Apply callback',
      (tester) async {
    final fixture = _fixture(staleFirstVersion: true);
    var applyCalls = 0;
    await _open(tester, fixture, (selected) async {
      applyCalls++;
      return true;
    });

    await tester.tap(find.byKey(const ValueKey('bulk-edit-preview-apply')));
    await tester.pumpAndSettle();

    expect(applyCalls, 0);
    expect(
        find.byKey(const ValueKey('bulk-edit-preview-dialog')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('bulk-edit-preview-error')), findsOneWidget);
  });

  testWidgets('resource inversion, semantics, Unicode and narrow layout',
      (tester) async {
    tester.view.physicalSize = const Size(560, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = _unicodeFixture();
    await _open(tester, fixture, (selected) async => true);

    final resourceSemantics = tester.widget<Semantics>(
      find.byKey(const ValueKey('bulk-edit-preview-resource-semantics-0')),
    );
    expect(resourceSemantics.properties.label, contains('a.txt'));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('bulk-edit-preview-invert-0')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('bulk-edit-preview-selected-count')),
          )
          .data,
      '已选择 0 / 1 项',
    );
    await tester
        .tap(find.byKey(const ValueKey('bulk-edit-preview-select-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bulk-edit-preview-preview')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SelectableText>(
            find.byKey(
              const ValueKey(
                'bulk-edit-preview-multidiff-modified-text-0',
              ),
            ),
          )
          .textSpan!
          .toPlainText(),
      'A🚀\r',
    );
    expect(find.byKey(const ValueKey('bulk-edit-preview-multidiff-dialog')),
        findsOneWidget);
  });
}

Future<void> _open(
  WidgetTester tester,
  _Fixture fixture,
  Future<bool> Function(WorkspaceEdit selected) onApply,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            key: const ValueKey('open-preview'),
            onPressed: () => unawaited(
              showBulkEditPreview(
                context: context,
                edit: fixture.edit,
                snapshots: fixture.snapshots,
                onApply: onApply,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-preview')));
  await tester.pumpAndSettle();
}

class _Fixture {
  const _Fixture(this.edit, this.snapshots);

  final WorkspaceEdit edit;
  final List<WorkspaceDocumentSnapshot> snapshots;
}

_Fixture _fixture({bool staleFirstVersion = false}) => _Fixture(
      WorkspaceEdit(
        [
          WorkspaceDocumentEdit(
            uri: 'file:///workspace/a.txt',
            version: staleFirstVersion ? 6 : 7,
            edits: [
              _replacement(0, 0, 5, 'ALPHA'),
              _replacement(1, 0, 4, 'BETA'),
            ],
          ),
          WorkspaceDocumentEdit(
            uri: 'file:///workspace/b.txt',
            version: 12,
            edits: [_replacement(0, 0, 5, 'GAMMA')],
          ),
        ],
        transactionId: 'bulk-transaction',
      ),
      const [
        WorkspaceDocumentSnapshot(
          id: 41,
          uri: 'file:///workspace/a.txt',
          version: 7,
          text: 'alpha\nbeta\n',
        ),
        WorkspaceDocumentSnapshot(
          id: 42,
          uri: 'file:///workspace/b.txt',
          version: 12,
          text: 'gamma\r\n',
        ),
      ],
    );

_Fixture _unicodeFixture() => const _Fixture(
      WorkspaceEdit([
        WorkspaceDocumentEdit(
          uri: 'file:///workspace/a.txt',
          version: 5,
          edits: [
            WorkspaceTextEdit(
              range: WorkspaceTextRange(
                start: WorkspaceTextPosition(0, 1),
                end: WorkspaceTextPosition(0, 3),
              ),
              newText: '🚀',
            ),
          ],
        ),
      ]),
      [
        WorkspaceDocumentSnapshot(
          id: 51,
          uri: 'file:///workspace/a.txt',
          version: 5,
          text: 'A😀\r\nkeep\r\n',
        ),
      ],
    );

WorkspaceTextEdit _replacement(int line, int start, int end, String text) =>
    WorkspaceTextEdit(
      range: WorkspaceTextRange(
        start: WorkspaceTextPosition(line, start),
        end: WorkspaceTextPosition(line, end),
      ),
      newText: text,
    );
