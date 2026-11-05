import 'package:flutter_test/flutter_test.dart';
import 'package:alula_app/git/git_diff_moved_blocks.dart';

void main() {
  const movedLines = [
    '  final firstValue = 1; ',
    '\tfinal secondValue = 2;\t',
    'final thirdValue = 3;',
  ];

  test('matches one trim-equivalent block moved between hunks', () {
    final result = computeGitDiffMovedBlocks(_splitHunkPatch(
      oldLines: movedLines,
      newLines: [
        'final firstValue = 1;',
        'final secondValue = 2;',
        'final thirdValue = 3;',
      ],
    ));

    expect(result.canAnalyze, isTrue);
    expect(result.fallbackReason, isNull);
    expect(result.blocks, hasLength(1));
    final block = result.blocks.single;
    expect(block.fileIndex, 0);
    expect(block.lineCount, 3);
    expect(block.originalStartLineNumber, 10);
    expect(block.originalEndLineNumberExclusive, 13);
    expect(block.modifiedStartLineNumber, 41);
    expect(block.modifiedEndLineNumberExclusive, 44);
    expect(block.originalStartPatchRow, 5);
    expect(block.originalEndPatchRowExclusive, 8);
    expect(block.modifiedStartPatchRow, 11);
    expect(block.modifiedEndPatchRowExclusive, 14);
  });

  test('does not match a deletion and insertion in the same hunk', () {
    final result = computeGitDiffMovedBlocks(_sameHunkPatch(movedLines));

    expect(result.canAnalyze, isTrue);
    expect(result.blocks, isEmpty);
  });

  test('leaves duplicate block candidates unmatched as ambiguous', () {
    final result = computeGitDiffMovedBlocks(_ambiguousPatch(movedLines));

    expect(result.canAnalyze, isTrue);
    expect(result.blocks, isEmpty);
  });

  test('does not match identical text across different files', () {
    final result = computeGitDiffMovedBlocks(_crossFilePatch(movedLines));

    expect(result.canAnalyze, isTrue);
    expect(result.blocks, isEmpty);
  });

  test('requires identical internal whitespace', () {
    final changedInternalWhitespace = [
      'final firstValue  = 1;',
      'final secondValue = 2;',
      'final thirdValue = 3;',
    ];
    final result = computeGitDiffMovedBlocks(_splitHunkPatch(
      oldLines: movedLines,
      newLines: changedInternalWhitespace,
    ));

    expect(result.canAnalyze, isTrue);
    expect(result.blocks, isEmpty);
  });

  test('rejects blocks below line and text quality thresholds', () {
    final tooFewLines = computeGitDiffMovedBlocks(_splitHunkPatch(
      oldLines: const ['final firstValue = 1;', 'final secondValue = 2;'],
      newLines: const ['final firstValue = 1;', 'final secondValue = 2;'],
    ));
    final tooLittleText = computeGitDiffMovedBlocks(_splitHunkPatch(
      oldLines: const ['a', 'b', 'c'],
      newLines: const ['a', 'b', 'c'],
    ));

    expect(tooFewLines.blocks, isEmpty);
    expect(tooLittleText.blocks, isEmpty);
  });

  test('uses UTF-16 line and patch-row ranges for Unicode content', () {
    const unicodeLines = [
      'final emoji = "😀";',
      'final symbol = "雪";',
      'final label = "名字";',
    ];
    final result = computeGitDiffMovedBlocks(_splitHunkPatch(
      oldLines: unicodeLines,
      newLines: unicodeLines,
    ));

    expect(result.canAnalyze, isTrue);
    expect(result.blocks, hasLength(1));
    expect(result.blocks.single.lineCount, 3);
  });

  test('returns no partial moves when patch input exceeds the cap', () {
    final result = computeGitDiffMovedBlocks(
      _splitHunkPatch(oldLines: movedLines, newLines: movedLines),
      options: const GitDiffMovedBlocksOptions(maxInputCodeUnits: 8),
    );

    expect(result.canAnalyze, isFalse);
    expect(result.fallbackReason, GitDiffMovedBlocksFallbackReason.inputLimit);
    expect(result.blocks, isEmpty);
  });

  test('returns no partial moves when patch rows exceed the cap', () {
    final result = computeGitDiffMovedBlocks(
      _splitHunkPatch(oldLines: movedLines, newLines: movedLines),
      options: const GitDiffMovedBlocksOptions(maxRows: 4),
    );

    expect(result.canAnalyze, isFalse);
    expect(result.fallbackReason, GitDiffMovedBlocksFallbackReason.rowLimit);
    expect(result.blocks, isEmpty);
  });

  test('returns no partial moves when candidate text work exceeds the cap', () {
    final result = computeGitDiffMovedBlocks(
      _splitHunkPatch(oldLines: movedLines, newLines: movedLines),
      options: const GitDiffMovedBlocksOptions(maxCandidateTextWork: 2),
    );

    expect(result.canAnalyze, isFalse);
    expect(
      result.fallbackReason,
      GitDiffMovedBlocksFallbackReason.candidateWorkLimit,
    );
    expect(result.blocks, isEmpty);
  });

  test('returns no partial moves for malformed or metadata-only patches', () {
    final malformed = computeGitDiffMovedBlocks('@@ malformed @@');
    final metadataOnly = computeGitDiffMovedBlocks(
      'diff --git a/a.txt b/a.txt\nindex 000..111 100644',
    );

    expect(malformed.canAnalyze, isFalse);
    expect(malformed.blocks, isEmpty);
    expect(metadataOnly.canAnalyze, isFalse);
    expect(metadataOnly.blocks, isEmpty);
  });

  test('rejects non-positive source line mappings', () {
    final result = computeGitDiffMovedBlocks([
      'diff --git a/lib/move.dart b/lib/move.dart',
      '--- a/lib/move.dart',
      '+++ b/lib/move.dart',
      '@@ -0,3 +1,0 @@',
      ...movedLines.map((line) => '-$line'),
      '@@ -20,0 +30,3 @@',
      ...movedLines.map((line) => '+$line'),
    ].join('\n'));

    expect(result.canAnalyze, isFalse);
    expect(
        result.fallbackReason, GitDiffMovedBlocksFallbackReason.sourceMapping);
    expect(result.blocks, isEmpty);
  });

  test('does not let callers raise the absolute input limit', () {
    final oversizedPatch = List<String>.filled(2000001, 'x').join();
    final result = computeGitDiffMovedBlocks(
      oversizedPatch,
      options: const GitDiffMovedBlocksOptions(maxInputCodeUnits: 3000000),
    );

    expect(result.canAnalyze, isFalse);
    expect(result.fallbackReason, GitDiffMovedBlocksFallbackReason.inputLimit);
    expect(result.blocks, isEmpty);
  });
}

String _splitHunkPatch({
  required List<String> oldLines,
  required List<String> newLines,
}) {
  return [
    'diff --git a/lib/move.dart b/lib/move.dart',
    'index 1111111..2222222 100644',
    '--- a/lib/move.dart',
    '+++ b/lib/move.dart',
    '@@ -10,${oldLines.length + 1} +2,1 @@',
    ...oldLines.map((line) => '-$line'),
    ' keep-before',
    '@@ -30,1 +40,${newLines.length + 1} @@',
    ' keep-after',
    ...newLines.map((line) => '+$line'),
  ].join('\n');
}

String _sameHunkPatch(List<String> lines) => [
      'diff --git a/lib/move.dart b/lib/move.dart',
      '--- a/lib/move.dart',
      '+++ b/lib/move.dart',
      '@@ -10,${lines.length} +40,${lines.length} @@',
      ...lines.map((line) => '-$line'),
      ...lines.map((line) => '+$line'),
    ].join('\n');

String _ambiguousPatch(List<String> lines) => [
      'diff --git a/lib/move.dart b/lib/move.dart',
      '--- a/lib/move.dart',
      '+++ b/lib/move.dart',
      '@@ -1,${lines.length} +0,0 @@',
      ...lines.map((line) => '-$line'),
      '@@ -10,${lines.length} +0,0 @@',
      ...lines.map((line) => '-$line'),
      '@@ -20,0 +30,${lines.length} @@',
      ...lines.map((line) => '+$line'),
    ].join('\n');

String _crossFilePatch(List<String> lines) => [
      'diff --git a/lib/old.dart b/lib/old.dart',
      '--- a/lib/old.dart',
      '+++ b/lib/old.dart',
      '@@ -1,${lines.length} +0,0 @@',
      ...lines.map((line) => '-$line'),
      'diff --git a/lib/new.dart b/lib/new.dart',
      '--- a/lib/new.dart',
      '+++ b/lib/new.dart',
      '@@ -0,0 +1,${lines.length} @@',
      ...lines.map((line) => '+$line'),
    ].join('\n');
