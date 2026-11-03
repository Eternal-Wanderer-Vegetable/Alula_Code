import 'dart:math';

import 'package:alula_app/editor/line_diff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('computeLineDiff', () {
    test('identical text has no hunks', () {
      final result = computeLineDiff('one\ntwo\n', 'one\ntwo\n');

      expect(result.hunks, isEmpty);
      expect(result.originalLineCount, 3);
      expect(result.modifiedLineCount, 3);
      expect(result.isApproximate, isFalse);
    });

    test('returns separated replacement and insertion hunks', () {
      final result = computeLineDiff(
        'one\ntwo\nthree',
        'one\nTWO\nthree\nfour',
        options: const LineDiffOptions(ignoreTrimWhitespace: false),
      );

      expect(
        result.hunks,
        const [
          LineDiffHunk(
            originalStartLine: 2,
            originalEndLineExclusive: 3,
            modifiedStartLine: 2,
            modifiedEndLineExclusive: 3,
          ),
          LineDiffHunk(
            originalStartLine: 4,
            originalEndLineExclusive: 4,
            modifiedStartLine: 4,
            modifiedEndLineExclusive: 5,
          ),
        ],
      );
    });

    test('represents a deletion with an empty modified range', () {
      final result = computeLineDiff('a\nb\nc', 'a\nc');

      expect(
        result.hunks,
        const [
          LineDiffHunk(
            originalStartLine: 2,
            originalEndLineExclusive: 3,
            modifiedStartLine: 2,
            modifiedEndLineExclusive: 2,
          ),
        ],
      );
    });

    test('keeps repeated lines deterministic and exposes only changed spans',
        () {
      const original = 'same\nsame\nkeep\nsame';
      const modified = 'same\nkeep\nsame\nnew';
      const options = LineDiffOptions(ignoreTrimWhitespace: false);
      final first = computeLineDiff(original, modified, options: options);
      final second = computeLineDiff(original, modified, options: options);

      expect(first.hunks, second.hunks);
      _expectValidLineAlignment(original, modified, first);
    });

    test('ignores leading and trailing whitespace by default', () {
      final ignored = computeLineDiff('  value  \nnext', 'value\nnext');
      final compared = computeLineDiff(
        '  value  \nnext',
        'value\nnext',
        options: const LineDiffOptions(ignoreTrimWhitespace: false),
      );

      expect(ignored.hunks, isEmpty);
      expect(compared.hunks, hasLength(1));
      expect(compared.hunks.single.originalStartLine, 1);
      expect(compared.hunks.single.originalEndLineExclusive, 2);
    });

    test('keeps BOM, emoji, and CRLF line boundaries intact', () {
      const original = '\uFEFFone\r\n😊 old\r\nlast';
      const modified = '\uFEFFone\r\n😊 new\r\nlast';
      final result = computeLineDiff(
        original,
        modified,
        options: const LineDiffOptions(ignoreTrimWhitespace: false),
      );

      expect(
        result.hunks,
        const [
          LineDiffHunk(
            originalStartLine: 2,
            originalEndLineExclusive: 3,
            modifiedStartLine: 2,
            modifiedEndLineExclusive: 3,
          ),
        ],
      );
    });

    test('handles empty text and final newline as separate line shapes', () {
      final inserted = computeLineDiff('', 'new');
      final finalNewline = computeLineDiff('one', 'one\n');

      expect(inserted.originalLineCount, 1);
      expect(inserted.modifiedLineCount, 1);
      expect(inserted.hunks, hasLength(1));
      expect(finalNewline.hunks, hasLength(1));
      expect(finalNewline.hunks.single.originalLineCount, 0);
      expect(finalNewline.hunks.single.modifiedLineCount, 1);
    });

    test('returns an explicit coarse hunk at the work bound', () {
      final result = computeLineDiff(
        'a\nb\nc',
        'x\ny\nz',
        options: const LineDiffOptions(maxWork: 0),
      );

      expect(result.isApproximate, isTrue);
      expect(result.fallbackReason, LineDiffFallbackReason.workLimit);
      expect(result.hunks, hasLength(1));
      expect(result.hunks.single.originalStartLine, 1);
      expect(result.hunks.single.originalEndLineExclusive, 4);
      expect(result.hunks.single.modifiedStartLine, 1);
      expect(result.hunks.single.modifiedEndLineExclusive, 4);
    });

    test('returns an explicit coarse hunk before splitting oversized input',
        () {
      final result = computeLineDiff(
        'one\ntwo',
        'one\nTWO',
        options: const LineDiffOptions(maxLinesPerSide: 1),
      );
      final oversizedText = computeLineDiff(
        'ab',
        'cd',
        options: const LineDiffOptions(maxInputCodeUnits: 3),
      );

      expect(result.fallbackReason, LineDiffFallbackReason.inputLimit);
      expect(result.isApproximate, isTrue);
      expect(result.hunks, hasLength(1));
      expect(result.originalLineCount, 2);
      expect(result.modifiedLineCount, 2);
      expect(oversizedText.fallbackReason, LineDiffFallbackReason.inputLimit);
      expect(oversizedText.hunks, hasLength(1));
    });

    test('randomized small inputs preserve every unchanged alignment gap', () {
      final random = Random(0x17a);
      const pool = ['a', 'b', 'same', '', '😊', 'x\r'];
      const options = LineDiffOptions(ignoreTrimWhitespace: false);
      for (var iteration = 0; iteration < 300; iteration++) {
        List<String> makeLines() => List.generate(
              random.nextInt(9),
              (_) => pool[random.nextInt(pool.length)],
            );
        final original = makeLines().join('\n');
        final modified = makeLines().join('\n');
        final result = computeLineDiff(original, modified, options: options);

        expect(result.isApproximate, isFalse);
        _expectValidLineAlignment(original, modified, result);
      }
    });
  });
}

void _expectValidLineAlignment(
  String originalText,
  String modifiedText,
  LineDiffResult result,
) {
  final original = originalText.split('\n');
  final modified = modifiedText.split('\n');
  var originalCursor = 0;
  var modifiedCursor = 0;

  for (final hunk in result.hunks) {
    final originalStart = hunk.originalStartLine - 1;
    final originalEnd = hunk.originalEndLineExclusive - 1;
    final modifiedStart = hunk.modifiedStartLine - 1;
    final modifiedEnd = hunk.modifiedEndLineExclusive - 1;
    expect(originalStart, greaterThanOrEqualTo(originalCursor));
    expect(modifiedStart, greaterThanOrEqualTo(modifiedCursor));
    expect(originalEnd, greaterThanOrEqualTo(originalStart));
    expect(modifiedEnd, greaterThanOrEqualTo(modifiedStart));

    final originalGapLength = originalStart - originalCursor;
    final modifiedGapLength = modifiedStart - modifiedCursor;
    expect(originalGapLength, modifiedGapLength);
    for (var offset = 0; offset < originalGapLength; offset++) {
      expect(
        original[originalCursor + offset],
        modified[modifiedCursor + offset],
      );
    }
    expect(originalEnd > originalStart || modifiedEnd > modifiedStart, isTrue);
    originalCursor = originalEnd;
    modifiedCursor = modifiedEnd;
  }

  expect(original.length - originalCursor, modified.length - modifiedCursor);
  for (var offset = 0; offset < original.length - originalCursor; offset++) {
    expect(
      original[originalCursor + offset],
      modified[modifiedCursor + offset],
    );
  }
}
