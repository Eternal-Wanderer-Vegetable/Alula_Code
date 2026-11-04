import 'package:alula_app/editor/diff_revert_plan.dart';
import 'package:alula_app/editor/diff_view_model.dart';
import 'package:alula_app/editor/line_diff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('projects replacement hunk ranges in UTF-16 and retains CRLF', () {
    const original = '\uFEFFa\r\nfn 😀old\r\nz\r\n';
    const modified = '\uFEFFa\r\nfn 😀new\r\nz\r\n';
    final diff = computeDiffViewModel(original, modified);

    final ranges = diffRevertRanges(diff, [0]);

    expect(ranges, hasLength(1));
    expect(
      original.substring(
        ranges.single.originalStartUtf16,
        ranges.single.originalEndUtf16,
      ),
      'fn 😀old\r\n',
    );
    expect(
      modified.substring(
        ranges.single.modifiedStartUtf16,
        ranges.single.modifiedEndUtf16,
      ),
      'fn 😀new\r\n',
    );
  });

  test('maps insertion and deletion hunks including empty ranges', () {
    final insertion = computeDiffViewModel('a\nz', 'a\nnew\nz');
    final inserted = diffRevertRanges(insertion, [0]).single;
    expect(inserted.originalStartUtf16, inserted.originalEndUtf16);
    expect(
      insertion.modifiedText.substring(
        inserted.modifiedStartUtf16,
        inserted.modifiedEndUtf16,
      ),
      'new\n',
    );

    final deletion = computeDiffViewModel('a\ngone\nz', 'a\nz');
    final deleted = diffRevertRanges(deletion, [0]).single;
    expect(deleted.modifiedStartUtf16, deleted.modifiedEndUtf16);
    expect(
      deletion.originalText.substring(
        deleted.originalStartUtf16,
        deleted.originalEndUtf16,
      ),
      'gone\n',
    );
  });

  test('maps separate hunk toolbar rows and selection intersections', () {
    final diff = computeDiffViewModel('a\nb\nc\nd', 'a\nB\nc\nD');

    expect(diffRevertToolbarRows(diff), {1: 0, 3: 1});
    expect(
      diffHunksIntersectingModifiedSelection(
        diff,
        selectionStartUtf16: 2,
        selectionEndUtf16: 2,
      ),
      [0],
    );
    expect(
      diffHunksIntersectingModifiedSelection(
        diff,
        selectionStartUtf16: 2,
        selectionEndUtf16: 7,
      ),
      [0, 1],
    );
    expect(
      diffHunksIntersectingModifiedSelection(
        diff,
        selectionStartUtf16: 0,
        selectionEndUtf16: 1,
      ),
      isEmpty,
    );
  });

  test('deleted hunk at a line boundary belongs only to the following line',
      () {
    final diff = computeDiffViewModel('a\ngone\nz', 'a\nz');

    expect(
      diffHunksIntersectingModifiedSelection(
        diff,
        selectionStartUtf16: 0,
        selectionEndUtf16: 1,
      ),
      isEmpty,
    );
    expect(
      diffHunksIntersectingModifiedSelection(
        diff,
        selectionStartUtf16: 2,
        selectionEndUtf16: 2,
      ),
      [0],
    );
  });

  test(
      'rejects invalid selections atomically and falls back for approximate diff',
      () {
    final exact = computeDiffViewModel('a\nb', 'a\nB');
    expect(diffRevertRanges(exact, [0, 99]), isEmpty);

    final approximate = computeDiffViewModel(
      'a\nb',
      'a\nB',
      options: const DiffViewModelOptions(
        lineDiffOptions: LineDiffOptions(maxWork: 0),
      ),
    );
    expect(approximate.isApproximate, isTrue);
    expect(diffRevertRanges(approximate, [0]), isEmpty);
    expect(diffRevertToolbarRows(approximate), isEmpty);
    expect(
      diffHunksIntersectingModifiedSelection(
        approximate,
        selectionStartUtf16: 2,
        selectionEndUtf16: 3,
      ),
      isEmpty,
    );
  });
}
