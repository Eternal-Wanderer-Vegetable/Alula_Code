import 'package:alula_app/workbench/editor_tab_close_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ids = [10, 20, 30, 40];
  const sticky = {20, 40};
  const clean = {10, 20, 30, 40};

  test('close keeps an explicitly targeted sticky tab eligible', () {
    expect(
      EditorTabClosePolicy.candidates(
        documentIds: ids,
        targetId: 20,
        stickyDocumentIds: sticky,
        cleanDocumentIds: clean,
        action: EditorTabCloseOperation.close,
      ),
      [20],
    );
  });

  test('close others preserves the target and every sticky tab', () {
    expect(
      EditorTabClosePolicy.candidates(
        documentIds: ids,
        targetId: 30,
        stickyDocumentIds: sticky,
        cleanDocumentIds: clean,
        action: EditorTabCloseOperation.closeOthers,
      ),
      [10],
    );
  });

  test('directional close uses current order and excludes sticky tabs', () {
    expect(
      EditorTabClosePolicy.candidates(
        documentIds: ids,
        targetId: 30,
        stickyDocumentIds: sticky,
        cleanDocumentIds: clean,
        action: EditorTabCloseOperation.closeToLeft,
      ),
      [10],
    );
    expect(
      EditorTabClosePolicy.candidates(
        documentIds: ids,
        targetId: 30,
        stickyDocumentIds: sticky,
        cleanDocumentIds: clean,
        action: EditorTabCloseOperation.closeToRight,
      ),
      [],
    );
  });

  test('close saved selects clean non-sticky tabs in the group', () {
    expect(
      EditorTabClosePolicy.candidates(
        documentIds: ids,
        targetId: 30,
        stickyDocumentIds: sticky,
        cleanDocumentIds: {10, 20, 40},
        action: EditorTabCloseOperation.closeSaved,
      ),
      [10],
    );
  });

  test('one-tab and stale targets have no directional or other candidates', () {
    expect(
      EditorTabClosePolicy.candidates(
        documentIds: const [10],
        targetId: 10,
        stickyDocumentIds: const {},
        cleanDocumentIds: const {10},
        action: EditorTabCloseOperation.closeToLeft,
      ),
      isEmpty,
    );
    expect(
      EditorTabClosePolicy.candidates(
        documentIds: ids,
        targetId: 99,
        stickyDocumentIds: sticky,
        cleanDocumentIds: clean,
        action: EditorTabCloseOperation.closeOthers,
      ),
      isEmpty,
    );
  });
}
