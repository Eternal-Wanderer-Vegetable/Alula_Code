import 'package:alula_app/workbench/editor_tab_mru_policy.dart';
import 'package:flutter_test/flutter_test.dart';

class _Doc {
  const _Doc(this.id);

  final int id;
}

void main() {
  test('orders open editors by MRU and appends unseen tabs in tab order', () {
    const docs = [_Doc(10), _Doc(20), _Doc(30), _Doc(40)];

    final ordered = EditorTabMruPolicy.order<_Doc>(
      tabs: docs,
      recentDocumentIds: const [30, 10],
      documentId: (doc) => doc.id,
    );

    expect(ordered.map((doc) => doc.id), [30, 10, 20, 40]);
  });

  test('ignores stale IDs and duplicate MRU entries', () {
    const docs = [_Doc(10), _Doc(20), _Doc(30)];

    final ordered = EditorTabMruPolicy.order<_Doc>(
      tabs: docs,
      recentDocumentIds: const [30, 99, 30, 10, 99],
      documentId: (doc) => doc.id,
    );

    expect(ordered.map((doc) => doc.id), [30, 10, 20]);
  });

  test('returns an immutable empty, single, or current-tab result', () {
    expect(
      EditorTabMruPolicy.order<_Doc>(
        tabs: const [],
        recentDocumentIds: const [99],
        documentId: (doc) => doc.id,
      ),
      isEmpty,
    );
    expect(
      EditorTabMruPolicy.order<_Doc>(
        tabs: const [_Doc(10)],
        recentDocumentIds: const [],
        documentId: (doc) => doc.id,
      ).map((doc) => doc.id),
      [10],
    );
    expect(
      () => EditorTabMruPolicy.order<_Doc>(
        tabs: const [_Doc(10)],
        recentDocumentIds: const [],
        documentId: (doc) => doc.id,
      ).add(const _Doc(20)),
      throwsUnsupportedError,
    );
  });
}
