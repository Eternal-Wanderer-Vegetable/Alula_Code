import 'package:alula_app/workbench/problems_table.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Problems rows keep file URI identity across document attachment', () {
    const marker = <String, Object?>{
      'file': 'shared 🦊#.rs',
      'line': 1,
      'character': 3,
      'endLine': 1,
      'endCharacter': 9,
      'severity': 1,
      'code': 'E0308',
      'source': 'rustc',
      'message': 'mismatched types',
    };
    const leftUri = 'file:///e:/workspace/left/shared%20%F0%9F%A6%8A%23.rs';
    const rightUri = 'file:///e:/workspace/right/shared%20%F0%9F%A6%8A%23.rs';
    final left = {...marker, '_resourceUri': leftUri};
    final right = {...marker, '_resourceUri': rightUri};

    final closed = ProblemsResultSelection.rowKeys([left, right]);
    final attached = ProblemsResultSelection.rowKeys([
      {...right, '_documentId': 5, 'documentVersion': 1},
      {...left, '_documentId': 9, 'documentVersion': 2},
    ]);
    expect(closed.first, isNot(closed.last));
    expect(attached, closed.reversed.toList());
    expect(
      ProblemsResultSelection.rowKeys([left, left, right]).toSet(),
      hasLength(3),
    );
  });
}
