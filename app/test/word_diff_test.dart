import 'dart:convert';
import 'dart:math' as math;

import 'package:alula_app/editor/word_diff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('computeWordDiff', () {
    test('returns no ranges for equal text and exact changed spans otherwise',
        () {
      expect(computeWordDiff('same', 'same').hunks, isEmpty);
      expect(
        computeWordDiff('fooBar', 'fooBaz').hunks,
        const [
          WordDiffHunk(
            originalStartUtf16: 5,
            originalEndUtf16: 6,
            modifiedStartUtf16: 5,
            modifiedEndUtf16: 6,
          ),
        ],
      );
    });

    test('expands low-similarity edits to their paired ASCII words', () {
      expect(
        computeWordDiff('foo', 'far').hunks,
        const [
          WordDiffHunk(
            originalStartUtf16: 0,
            originalEndUtf16: 3,
            modifiedStartUtf16: 0,
            modifiedEndUtf16: 3,
          ),
        ],
      );
    });

    test('keeps high-similarity character edits local', () {
      expect(
        computeWordDiff('fooBar', 'fooBaz').hunks.single.originalLength,
        1,
      );
      expect(
        computeWordDiff('fooBar', 'fooBaz').hunks.single.modifiedLength,
        1,
      );
    });

    test('does not expand equal neighboring words across punctuation', () {
      expect(
        computeWordDiff('foo,bar', 'foo;bar').hunks,
        const [
          WordDiffHunk(
            originalStartUtf16: 3,
            originalEndUtf16: 4,
            modifiedStartUtf16: 3,
            modifiedEndUtf16: 4,
          ),
        ],
      );
      expect(
        computeWordDiff('foo,bar', 'foo,baz').hunks,
        const [
          WordDiffHunk(
            originalStartUtf16: 6,
            originalEndUtf16: 7,
            modifiedStartUtf16: 6,
            modifiedEndUtf16: 7,
          ),
        ],
      );
    });

    test('preserves UTF-16 offsets and never splits an Emoji surrogate pair',
        () {
      expect(
        computeWordDiff('😀', '😃').hunks,
        const [
          WordDiffHunk(
            originalStartUtf16: 0,
            originalEndUtf16: 2,
            modifiedStartUtf16: 0,
            modifiedEndUtf16: 2,
          ),
        ],
      );
      final inserted = computeWordDiff('', '😀').hunks.single;
      expect(inserted.originalStartUtf16, 0);
      expect(inserted.originalEndUtf16, 0);
      expect(inserted.modifiedStartUtf16, 0);
      expect(inserted.modifiedEndUtf16, 2);
    });

    test('preserves BOM and reports CRLF changes at UTF-16 offsets', () {
      expect(
        computeWordDiff('\uFEFFa\r\nb', '\uFEFFa\nb').hunks,
        const [
          WordDiffHunk(
            originalStartUtf16: 2,
            originalEndUtf16: 3,
            modifiedStartUtf16: 2,
            modifiedEndUtf16: 2,
          ),
        ],
      );
      expect(
        computeWordDiff('\uFEFFold', '\uFEFFnew')
            .hunks
            .first
            .originalStartUtf16,
        1,
      );
    });

    test('keeps repeated-character alignments deterministic', () {
      const before = 'aaabaaa';
      const after = 'aabaaac';
      final first = computeWordDiff(before, after);
      final second = computeWordDiff(before, after);
      expect(first.hunks, second.hunks);
      _expectEqualGaps(before, after, first.hunks);
    });

    test('returns explicit whole-text fallbacks for input and work limits', () {
      final inputLimited = computeWordDiff(
        'abcdef',
        'xyz',
        options: const WordDiffOptions(maxInputCodeUnits: 5),
      );
      expect(inputLimited.fallbackReason, WordDiffFallbackReason.inputLimit);
      expect(
        inputLimited.hunks,
        const [
          WordDiffHunk(
            originalStartUtf16: 0,
            originalEndUtf16: 6,
            modifiedStartUtf16: 0,
            modifiedEndUtf16: 3,
          ),
        ],
      );

      final workLimited = computeWordDiff(
        'abc',
        'xyz',
        options: const WordDiffOptions(maxWork: 1),
      );
      expect(workLimited.fallbackReason, WordDiffFallbackReason.workLimit);

      final traceLimited = computeWordDiff(
        'abc',
        'xyz',
        options: const WordDiffOptions(maxTraceCells: 1),
      );
      expect(traceLimited.fallbackReason, WordDiffFallbackReason.workLimit);
    });

    test('random small pairs preserve every unchanged gap and valid range', () {
      final random = math.Random(0x17B94);
      const alphabet = <String>[
        'a',
        'b',
        'A',
        '1',
        ' ',
        ',',
        '\n',
        '_',
        'é',
        '😀',
      ];

      for (var sample = 0; sample < 200; sample++) {
        String makeText() {
          final length = random.nextInt(36);
          return List.generate(
            length,
            (_) => alphabet[random.nextInt(alphabet.length)],
          ).join();
        }

        final original = makeText();
        final modified = makeText();
        final result = computeWordDiff(original, modified);
        expect(result.fallbackReason, isNull, reason: 'sample $sample');
        _expectEqualGaps(
          original,
          modified,
          result.hunks,
          reason: 'sample $sample (${original.length}/${modified.length}): '
              '${jsonEncode(original)} -> ${jsonEncode(modified)}; ${result.hunks}',
        );
        _expectSurrogateSafe(original, result.hunks, originalSide: true);
        _expectSurrogateSafe(modified, result.hunks, originalSide: false);
      }
    });
  });
}

void _expectEqualGaps(
  String original,
  String modified,
  List<WordDiffHunk> hunks, {
  String? reason,
}) {
  var originalOffset = 0;
  var modifiedOffset = 0;
  for (final hunk in hunks) {
    expect(
      hunk.originalStartUtf16,
      greaterThanOrEqualTo(originalOffset),
      reason: reason,
    );
    expect(
      hunk.modifiedStartUtf16,
      greaterThanOrEqualTo(modifiedOffset),
      reason: reason,
    );
    expect(hunk.originalEndUtf16, lessThanOrEqualTo(original.length));
    expect(hunk.modifiedEndUtf16, lessThanOrEqualTo(modified.length));
    expect(
      original.substring(originalOffset, hunk.originalStartUtf16),
      modified.substring(modifiedOffset, hunk.modifiedStartUtf16),
      reason: reason,
    );
    originalOffset = hunk.originalEndUtf16;
    modifiedOffset = hunk.modifiedEndUtf16;
  }
  expect(
    original.substring(originalOffset),
    modified.substring(modifiedOffset),
    reason: reason,
  );
}

void _expectSurrogateSafe(
  String text,
  List<WordDiffHunk> hunks, {
  required bool originalSide,
}) {
  for (final hunk in hunks) {
    final start =
        originalSide ? hunk.originalStartUtf16 : hunk.modifiedStartUtf16;
    final end = originalSide ? hunk.originalEndUtf16 : hunk.modifiedEndUtf16;
    if (start > 0 && start < text.length) {
      expect(
        _isSurrogateBoundary(text, start),
        isFalse,
        reason: 'start offset $start splits a surrogate pair',
      );
    }
    if (end > 0 && end < text.length) {
      expect(
        _isSurrogateBoundary(text, end),
        isFalse,
        reason: 'end offset $end splits a surrogate pair',
      );
    }
  }
}

bool _isSurrogateBoundary(String text, int offset) {
  final before = text.codeUnitAt(offset - 1);
  final after = text.codeUnitAt(offset);
  return before >= 0xD800 &&
      before <= 0xDBFF &&
      after >= 0xDC00 &&
      after <= 0xDFFF;
}
