import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:alula_app/editor/diff_view_model.dart';
import 'package:alula_app/editor/line_diff.dart';
import 'package:alula_app/editor/word_diff.dart';

void main() {
  group('computeDiffViewModel', () {
    test('keeps unchanged lines and the final empty line', () {
      const text = 'alpha\nbeta\n';
      final result = computeDiffViewModel(text, text);

      expect(result.fallbackReason, isNull);
      expect(result.rows, hasLength(3));
      expect(result.rows.map((row) => row.kind),
          everyElement(DiffViewRowKind.unchanged));
      expect(result.rows.map((row) => row.originalLineNumber), [1, 2, 3]);
      expect(result.rows.map((row) => row.modifiedLineNumber), [1, 2, 3]);
      expect(result.rows.last.originalText, '');
      expect(result.rows.last.modifiedText, '');
    });

    test('pairs a replacement and attaches line-local UTF-16 word ranges', () {
      final result = computeDiffViewModel(
        'before\nkeep',
        'bother\nkeep',
      );

      expect(result.rows.map((row) => row.kind), [
        DiffViewRowKind.modified,
        DiffViewRowKind.unchanged,
      ]);
      final replacement = result.rows.first;
      expect(replacement.originalLineNumber, 1);
      expect(replacement.modifiedLineNumber, 1);
      expect(replacement.originalText, 'before');
      expect(replacement.modifiedText, 'bother');
      expect(replacement.wordChanges, isNotEmpty);
      _expectValidRanges(replacement);
      _expectCompleteMapping(result);
    });

    test('pairs 1:N replacements and keeps the extra line as an insertion', () {
      final result = computeDiffViewModel(
        'keep\nold\nend',
        'keep\nnew\nextra\nend',
      );

      expect(result.rows.map((row) => row.kind), [
        DiffViewRowKind.unchanged,
        DiffViewRowKind.modified,
        DiffViewRowKind.inserted,
        DiffViewRowKind.unchanged,
      ]);
      expect(result.rows[2].originalLineNumber, isNull);
      expect(result.rows[2].modifiedLineNumber, 3);
      expect(result.rows[2].modifiedText, 'extra');
      _expectCompleteMapping(result);
    });

    test('pairs N:1 replacements and keeps the extra line as a deletion', () {
      final result = computeDiffViewModel(
        'keep\nold1\nold2\nend',
        'keep\nnew\nend',
      );

      expect(result.rows.map((row) => row.kind), [
        DiffViewRowKind.unchanged,
        DiffViewRowKind.modified,
        DiffViewRowKind.deleted,
        DiffViewRowKind.unchanged,
      ]);
      expect(result.rows[2].originalLineNumber, 3);
      expect(result.rows[2].originalText, 'old2');
      expect(result.rows[2].modifiedLineNumber, isNull);
      _expectCompleteMapping(result);
    });

    test('preserves separated change hunks and source order', () {
      final result = computeDiffViewModel(
        'first\nold-a\nmiddle\nold-b\nlast',
        'first\nnew-a\nmiddle\nnew-b\nlast',
      );

      expect(result.lineDiff.hunks, hasLength(2));
      expect(result.rows.map((row) => row.kind), [
        DiffViewRowKind.unchanged,
        DiffViewRowKind.modified,
        DiffViewRowKind.unchanged,
        DiffViewRowKind.modified,
        DiffViewRowKind.unchanged,
      ]);
      _expectCompleteMapping(result);
    });

    test('preserves CRLF and BOM text while ranges remain surrogate-safe', () {
      final result = computeDiffViewModel(
        '\uFEFFalpha😀\r\nlast\r\n',
        '\uFEFFalpha😃\r\nlast\r\n',
      );

      expect(result.rows, hasLength(3));
      expect(result.rows.first.kind, DiffViewRowKind.modified);
      expect(result.rows.first.originalText, '\uFEFFalpha😀\r');
      expect(result.rows.first.modifiedText, '\uFEFFalpha😃\r');
      expect(result.rows[1].kind, DiffViewRowKind.unchanged);
      expect(result.rows.last.originalText, '');
      _expectValidRanges(result.rows.first);
      _expectCompleteMapping(result);
    });

    test('honors the line model whitespace policy and keeps source text', () {
      final ignored = computeDiffViewModel('  value  \nnext', 'value\nnext');
      expect(ignored.rows.first.kind, DiffViewRowKind.unchanged);
      expect(ignored.rows.first.originalText, '  value  ');
      expect(ignored.rows.first.modifiedText, 'value');

      final strict = computeDiffViewModel(
        '  value  \nnext',
        'value\nnext',
        options: const DiffViewModelOptions(
          lineDiffOptions: LineDiffOptions(ignoreTrimWhitespace: false),
        ),
      );
      expect(strict.rows.first.kind, DiffViewRowKind.modified);
      expect(strict.rows.first.wordChanges, isNotEmpty);
      _expectCompleteMapping(strict);
    });

    test('reports aggregate word input and work fallbacks per changed row', () {
      final inputLimited = computeDiffViewModel(
        'alpha\nstable',
        'omega\nstable',
        options: const DiffViewModelOptions(maxAggregateWordInputCodeUnits: 1),
      );
      final inputRow = inputLimited.rows.first;
      expect(inputRow.kind, DiffViewRowKind.modified);
      expect(inputRow.inlineFallbackReason,
          DiffInlineFallbackReason.aggregateInputLimit);
      expect(inputRow.wordChanges.single.originalStartUtf16, 0);
      expect(inputRow.wordChanges.single.originalEndUtf16, 5);
      expect(inputRow.wordChanges.single.modifiedEndUtf16, 5);
      expect(inputLimited.isApproximate, isTrue);
      _expectCompleteMapping(inputLimited);

      final workLimited = computeDiffViewModel(
        'alpha',
        'omega',
        options: const DiffViewModelOptions(maxAggregateWordWork: 0),
      );
      expect(workLimited.rows.single.inlineFallbackReason,
          DiffInlineFallbackReason.aggregateWorkLimit);
      _expectValidRanges(workLimited.rows.single);
    });

    test('reports per-line word fallback without dropping a changed row', () {
      final result = computeDiffViewModel(
        'alpha',
        'omega',
        options: const DiffViewModelOptions(
          wordDiffOptions: WordDiffOptions(maxWork: 0),
        ),
      );

      expect(result.fallbackReason, isNull);
      expect(result.rows.single.kind, DiffViewRowKind.modified);
      expect(result.rows.single.inlineFallbackReason,
          DiffInlineFallbackReason.wordWorkLimit);
      expect(result.rows.single.wordChanges.single.originalEndUtf16, 5);
      expect(result.isApproximate, isTrue);
      _expectCompleteMapping(result);
    });

    test('returns complete-text fallbacks instead of partial rows', () {
      final rowLimited = computeDiffViewModel(
        'a\nb',
        'a\nc',
        options: const DiffViewModelOptions(maxRows: 3),
      );
      expect(rowLimited.fallbackReason, DiffViewFallbackReason.rowLimit);
      expect(rowLimited.rows, isEmpty);
      expect(rowLimited.originalText, 'a\nb');
      expect(rowLimited.modifiedText, 'a\nc');

      final inputLimited = computeDiffViewModel(
        'same',
        'same',
        options: const DiffViewModelOptions(maxInputCodeUnits: 7),
      );
      expect(inputLimited.fallbackReason, DiffViewFallbackReason.inputLimit);
      expect(inputLimited.rows, isEmpty);
      expect(inputLimited.originalText, 'same');

      final lineLimited = computeDiffViewModel(
        'a\nb',
        'a\nc',
        options: const DiffViewModelOptions(
          lineDiffOptions: LineDiffOptions(maxLinesPerSide: 1),
        ),
      );
      expect(lineLimited.fallbackReason, DiffViewFallbackReason.lineDiffLimit);
      expect(lineLimited.lineDiff.isApproximate, isTrue);
      expect(lineLimited.rows, isEmpty);

      final identicalLineLimited = computeDiffViewModel(
        'a\nb',
        'a\nb',
        options: const DiffViewModelOptions(
          lineDiffOptions: LineDiffOptions(maxLinesPerSide: 1),
        ),
      );
      expect(identicalLineLimited.fallbackReason,
          DiffViewFallbackReason.lineDiffLimit);
      expect(identicalLineLimited.rows, isEmpty);
    });

    test('keeps coarse rows when line Myers work falls back', () {
      final result = computeDiffViewModel(
        'old-a\nold-b',
        'new-a\nnew-b',
        options: const DiffViewModelOptions(
          lineDiffOptions: LineDiffOptions(maxWork: 0),
        ),
      );

      expect(result.fallbackReason, isNull);
      expect(result.lineDiff.fallbackReason, LineDiffFallbackReason.workLimit);
      expect(result.rows, hasLength(2));
      expect(result.rows.map((row) => row.kind),
          everyElement(DiffViewRowKind.modified));
      expect(result.isApproximate, isTrue);
      _expectCompleteMapping(result);
    });

    test('seeded random inputs map every source line exactly once in order',
        () {
      final random = Random(0x17C);
      for (var sample = 0; sample < 200; sample++) {
        final original = _randomText(random);
        final modified = _randomText(random);
        final result = computeDiffViewModel(original, modified);

        expect(result.fallbackReason, isNull, reason: 'sample $sample');
        _expectCompleteMapping(result);
        for (final row in result.rows) {
          _expectValidRanges(row);
        }
      }
    });
  });
}

String _randomText(Random random) {
  final lineCount = random.nextInt(8);
  final lines = <String>[];
  for (var line = 0; line < lineCount; line++) {
    final length = random.nextInt(12);
    final units = List<int>.generate(
      length,
      (_) => 0x61 + random.nextInt(4),
      growable: false,
    );
    lines.add(String.fromCharCodes(units));
  }
  final text = lines.join('\n');
  return random.nextBool() ? '$text\n' : text;
}

void _expectCompleteMapping(DiffViewModelResult result) {
  if (result.fallbackReason != null) {
    expect(result.rows, isEmpty);
    expect(result.originalText, isNotEmpty);
    return;
  }
  final originalLines = result.originalText.split('\n');
  final modifiedLines = result.modifiedText.split('\n');
  final originalRows = result.rows
      .where((row) => row.originalLineNumber != null)
      .toList(growable: false);
  final modifiedRows = result.rows
      .where((row) => row.modifiedLineNumber != null)
      .toList(growable: false);
  expect(
    originalRows.map((row) => row.originalLineNumber),
    List<int>.generate(originalLines.length, (index) => index + 1),
  );
  expect(
    modifiedRows.map((row) => row.modifiedLineNumber),
    List<int>.generate(modifiedLines.length, (index) => index + 1),
  );
  expect(
    originalRows.map((row) => row.originalText),
    originalLines,
  );
  expect(
    modifiedRows.map((row) => row.modifiedText),
    modifiedLines,
  );
  expect(result.rows.map((row) => row.rowIndex),
      List<int>.generate(result.rows.length, (index) => index));
}

void _expectValidRanges(DiffViewRow row) {
  var previousOriginalEnd = 0;
  var previousModifiedEnd = 0;
  for (final hunk in row.wordChanges) {
    expect(hunk.originalStartUtf16, greaterThanOrEqualTo(previousOriginalEnd));
    expect(hunk.modifiedStartUtf16, greaterThanOrEqualTo(previousModifiedEnd));
    expect(
        hunk.originalEndUtf16, greaterThanOrEqualTo(hunk.originalStartUtf16));
    expect(
        hunk.modifiedEndUtf16, greaterThanOrEqualTo(hunk.modifiedStartUtf16));
    expect(hunk.originalEndUtf16,
        lessThanOrEqualTo(row.originalText?.length ?? 0));
    expect(hunk.modifiedEndUtf16,
        lessThanOrEqualTo(row.modifiedText?.length ?? 0));
    previousOriginalEnd = hunk.originalEndUtf16;
    previousModifiedEnd = hunk.modifiedEndUtf16;
  }
}
