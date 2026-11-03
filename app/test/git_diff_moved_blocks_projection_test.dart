import 'package:flutter_test/flutter_test.dart';
import 'package:alula_app/git/git_diff_moved_blocks.dart';
import 'package:alula_app/git/git_diff_moved_blocks_projection.dart';
import 'package:alula_app/git/git_diff_patch.dart';
import 'package:alula_app/git/git_diff_whitespace_projection.dart';

void main() {
  const oldLines = [
    '  final firstValue = 1; ',
    '\tfinal secondValue = 2;\t',
    'final thirdValue = 3;',
  ];
  const newLines = [
    'final firstValue = 1;',
    'final secondValue = 2;',
    'final thirdValue = 3;',
  ];

  test('maps both moved source blocks into aligned projection rows', () {
    final patch = _splitHunkPatch(oldLines: oldLines, newLines: newLines);
    final moves = computeGitDiffMovedBlocks(patch);
    final projection = projectGitDiffPatchIgnoringTrimWhitespace(
      parseGitDiffPatch(patch),
    );

    final result = projectGitDiffMovedBlocks(
      moves,
      parseGitDiffPatch(patch),
      projection,
    );

    expect(result.canRender, isTrue);
    expect(result.fallbackReason, isNull);
    expect(result.blocks, hasLength(1));
    final projected = result.blocks.single;
    expect(projected.block, same(moves.blocks.single));
    expect(projected.originalStartRowIndex, 5);
    expect(projected.originalEndRowIndexExclusive, 8);
    expect(projected.modifiedStartRowIndex, 11);
    expect(projected.modifiedEndRowIndexExclusive, 14);
    for (var offset = 0; offset < 3; offset++) {
      final oldLine = projection
          .rows[projected.originalStartRowIndex + offset].originalLine!;
      final newLine = projection
          .rows[projected.modifiedStartRowIndex + offset].modifiedLine!;
      expect(oldLine.originalLineNumber, 10 + offset);
      expect(newLine.modifiedLineNumber, 41 + offset);
    }
  });

  test('suppresses every move when any source row is absent', () {
    final sourcePatch = _splitHunkPatch(oldLines: oldLines, newLines: newLines);
    final mappedPatch = _splitHunkPatch(
      oldLines: oldLines,
      newLines: const [
        'other first line;',
        'other second line;',
        'other third line;'
      ],
    );
    final moves = computeGitDiffMovedBlocks(sourcePatch);
    final projection = projectGitDiffPatchIgnoringTrimWhitespace(
      parseGitDiffPatch(mappedPatch),
    );

    final result = projectGitDiffMovedBlocks(
      moves,
      parseGitDiffPatch(sourcePatch),
      projection,
    );

    expect(result.canRender, isFalse);
    expect(
      result.fallbackReason,
      GitDiffMovedBlocksProjectionFallbackReason.sourceRangeMismatch,
    );
    expect(result.blocks, isEmpty);
  });

  test('returns no overlays when either upstream model fell back', () {
    final patch = _splitHunkPatch(oldLines: oldLines, newLines: newLines);
    final unavailableMoves = computeGitDiffMovedBlocks(
      patch,
      options: const GitDiffMovedBlocksOptions(maxInputCodeUnits: 1),
    );
    final validProjection = projectGitDiffPatchIgnoringTrimWhitespace(
      parseGitDiffPatch(patch),
    );
    final validMoves = computeGitDiffMovedBlocks(patch);
    final unavailableProjection = projectGitDiffPatchIgnoringTrimWhitespace(
      parseGitDiffPatch(patch),
      options: const GitDiffProjectionOptions(maxRows: 1),
    );

    final moveFallback = projectGitDiffMovedBlocks(
      unavailableMoves,
      parseGitDiffPatch(patch),
      validProjection,
    );
    final projectionFallback = projectGitDiffMovedBlocks(
      validMoves,
      parseGitDiffPatch(patch),
      unavailableProjection,
    );

    expect(moveFallback.canRender, isFalse);
    expect(
      moveFallback.fallbackReason,
      GitDiffMovedBlocksProjectionFallbackReason.moveModelUnavailable,
    );
    expect(moveFallback.blocks, isEmpty);
    expect(projectionFallback.canRender, isFalse);
    expect(
      projectionFallback.fallbackReason,
      GitDiffMovedBlocksProjectionFallbackReason.projectionUnavailable,
    );
    expect(projectionFallback.blocks, isEmpty);
  });

  test('keeps a valid empty move result renderable', () {
    final patch = _sameHunkPatch(oldLines);
    final noMoves = computeGitDiffMovedBlocks(patch);
    final projection = projectGitDiffPatchIgnoringTrimWhitespace(
      parseGitDiffPatch(patch),
    );

    final result = projectGitDiffMovedBlocks(
      noMoves,
      parseGitDiffPatch(patch),
      projection,
    );

    expect(result.canRender, isTrue);
    expect(result.blocks, isEmpty);
  });
}

String _splitHunkPatch({
  required List<String> oldLines,
  required List<String> newLines,
}) =>
    [
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

String _sameHunkPatch(List<String> lines) => [
      'diff --git a/lib/move.dart b/lib/move.dart',
      '--- a/lib/move.dart',
      '+++ b/lib/move.dart',
      '@@ -10,${lines.length} +40,${lines.length} @@',
      ...lines.map((line) => '-$line'),
      ...lines.map((line) => '+$line'),
    ].join('\n');
