import 'package:alula_app/workbench/diagnostic_navigation_peek.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const original = <String, Object?>{
  '_documentId': 5,
  'documentVersion': 8,
  'line': 2,
  'character': 10,
  'endLine': 2,
  'endCharacter': 16,
  'severity': 2,
  'source': 'rustc',
  'code': 'deprecated',
  'message': '旧消息',
};
final longer = <String, Object?>{
  ...original,
  'message': '新消息\n第二行\n第三行',
};

void main() {
  test('a unique equal-range publication preserves the open slot height', () {
    final initial = DiagnosticNavigationSnapshot(original);
    expect(
        initial.reconcile([
          {...original}
        ]),
        same(initial));

    final refreshed = initial.reconcile([
      longer,
      {...longer}
    ]);
    expect(refreshed.diagnostic, same(longer));
    expect(refreshed.isStale, isFalse);
    expect(refreshed.heightInEditorLines, initial.heightInEditorLines);
  });

  test('withdrawal preserves the last message and uses its current height', () {
    final refreshed =
        DiagnosticNavigationSnapshot(original).reconcile([longer]);
    final stale = refreshed.reconcile([]);
    expect(stale.diagnostic, same(longer));
    expect(stale.isStale, isTrue);
    expect(stale.heightInEditorLines, 6);
    expect(stale.reconcile([]), same(stale));

    final restored = stale.reconcile([original]);
    expect(restored.diagnostic, same(original));
    expect(restored.isStale, isFalse);
    expect(restored.heightInEditorLines, 6);
    expect(DiagnosticNavigationSnapshot(original).heightInEditorLines, 4);
  });

  test('stale detail accepts a fresh publication of the exact last marker', () {
    final stale = DiagnosticNavigationSnapshot(original).reconcile([]);
    final restored = stale.reconcile([
      {...original}
    ]);
    expect(restored.isStale, isFalse);
    expect(restored.diagnostic, original);
  });

  test('other files, versions, ranges and ambiguous rows stay stale', () {
    final initial = DiagnosticNavigationSnapshot(original);
    final otherMarkers = <Map<String, Object?>>[
      {...longer, '_documentId': 6},
      {...longer, 'documentVersion': 9},
      {...longer, 'line': 1},
      {...longer, 'endCharacter': 17},
      {...longer, 'severity': 1},
      {...longer, 'source': 'external'},
      {...longer, 'code': 'other'},
    ];
    expect(initial.reconcile(otherMarkers).isStale, isTrue);

    final overlapping = [
      ...otherMarkers,
      longer,
      {...original, 'message': '另一条'}
    ];
    final ambiguous = initial.reconcile(overlapping);
    expect(ambiguous.isStale, isTrue);
    expect(ambiguous.diagnostic, same(original));
    expect(initial.reconcile([...overlapping, original]), same(initial));
  });

  testWidgets('stale state is visible and exposed to accessibility',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DiagnosticNavigationPeek(
            fileName: 'lib.rs',
            ordinal: 1,
            total: 1,
            severity: 2,
            message: '诊断消息',
            onClose: () {},
            isStale: true,
          ),
        ),
      ));

      expect(find.text('诊断消息'), findsOneWidget);
      expect(find.text('已过期 · 1 / 1'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('已过期，警告，lib.rs')), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });
}
