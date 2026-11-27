import 'package:alula_app/workbench/diagnostic_navigation_peek.dart';
import 'package:flutter_test/flutter_test.dart';

const outer = <String, Object?>{
  '_documentId': 3,
  'documentVersion': 1,
  'line': 0,
  'character': 35,
  'endLine': 0,
  'endCharacter': 114,
  'severity': 1,
  'source': 'rustc',
  'code': 'E0308',
  'message': 'expected bool, found i32',
};
const anchor = (line: 0, character: 67);
final inner = <String, Object?>{
  ...outer,
  'character': 59,
  'endCharacter': 85,
  'message': 'expected bool, found i64',
};

void main() {
  test('narrower range covering the original anchor refreshes in place', () {
    final initial = DiagnosticNavigationSnapshot(outer, anchor: anchor);
    final updated = initial.reconcile([inner]);

    expect(updated.diagnostic, same(inner));
    expect(updated.isStale, isFalse);
    expect(updated.heightInEditorLines, initial.heightInEditorLines);
  });

  test('off-anchor range keeps the last message stale and can recover', () {
    final initial = DiagnosticNavigationSnapshot(outer, anchor: anchor);
    final current = initial.reconcile([inner]);
    final outside = {...outer, 'character': 87, 'endCharacter': 113};
    final stale = current.reconcile([outside]);
    expect(stale.diagnostic, same(inner));
    expect(stale.isStale, isTrue);

    final recovered = {...inner, 'message': 'expected bool, found u64'};
    final live = stale.reconcile([recovered]);
    expect(live.diagnostic, same(recovered));
    expect(live.isStale, isFalse);
    expect(live.heightInEditorLines, stale.heightInEditorLines);
  });

  test('exact and same-range matches take precedence over overlaps', () {
    final initial = DiagnosticNavigationSnapshot(outer, anchor: anchor);
    final updatedOuter = {...outer, 'message': 'new same-range message'};
    final otherOverlap = {...inner, 'character': 61};
    expect(initial.reconcile([inner, updatedOuter]).diagnostic,
        same(updatedOuter));
    expect(initial.reconcile([updatedOuter, inner]).diagnostic,
        same(updatedOuter));
    expect(initial.reconcile([inner, otherOverlap, outer]), same(initial));
  });

  test('overlapping candidates must agree to replace the open diagnostic', () {
    final initial = DiagnosticNavigationSnapshot(outer, anchor: anchor);
    final otherOverlap = {...inner, 'character': 61};
    final stale = initial.reconcile([otherOverlap, inner]);
    expect(stale.isStale, isTrue);
    expect(stale.diagnostic, same(outer));

    final duplicate = initial.reconcile([
      inner,
      {...inner}
    ]);
    expect(duplicate.isStale, isFalse);
    expect(duplicate.diagnostic, same(inner));
  });

  test('bounds are inclusive across lines and for a point diagnostic', () {
    final spanning = {...outer, 'endLine': 2, 'endCharacter': 5};
    final initial =
        DiagnosticNavigationSnapshot(spanning, anchor: (line: 1, character: 4));
    final multiline = {...inner, 'endLine': 1, 'endCharacter': 4};
    final point = {
      ...inner,
      'line': 1,
      'character': 4,
      'endLine': 1,
      'endCharacter': 4,
    };
    expect(initial.reconcile([multiline]).diagnostic, same(multiline));
    expect(initial.reconcile([point]).diagnostic, same(point));
  });

  test('invalid positions, versions and marker identities do not refresh', () {
    final initial = DiagnosticNavigationSnapshot(outer, anchor: anchor);
    final rejected = <Map<String, Object?>>[
      {...inner, 'character': -1},
      {...inner, 'endLine': -1},
      {...inner, 'endCharacter': null},
      {...inner, 'character': 80, 'endCharacter': 60},
      {...inner, '_documentId': 5},
      {...inner, 'documentVersion': 2},
      {...inner, 'code': 'E0061'},
      {...inner, 'source': 'other'},
    ];
    expect(initial.reconcile(rejected).isStale, isTrue);
    expect(
        DiagnosticNavigationSnapshot(outer).reconcile([inner]).isStale, isTrue);
  });
}
