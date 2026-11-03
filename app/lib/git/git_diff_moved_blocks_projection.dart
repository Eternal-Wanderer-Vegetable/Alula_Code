/// Maps bounded moved-block source rows into the aligned side-by-side view.
library;

import 'git_diff_moved_blocks.dart';
import 'git_diff_patch.dart';
import 'git_diff_whitespace_projection.dart';

const int _hardMaxProjectedRows = 16384;

enum GitDiffMovedBlocksProjectionFallbackReason {
  moveModelUnavailable,
  projectionUnavailable,
  rowLimit,
  sourceRowMissing,
  sourceRowDuplicate,
  sourceRangeMismatch,
  nonContiguousRows,
  overlappingRanges,
}

class GitDiffProjectedMovedBlock {
  const GitDiffProjectedMovedBlock({
    required this.block,
    required this.originalStartRowIndex,
    required this.originalEndRowIndexExclusive,
    required this.modifiedStartRowIndex,
    required this.modifiedEndRowIndexExclusive,
  });

  final GitDiffMovedBlock block;

  /// Zero-based indexes in [GitDiffProjectionResult.rows], end-exclusive.
  final int originalStartRowIndex;
  final int originalEndRowIndexExclusive;
  final int modifiedStartRowIndex;
  final int modifiedEndRowIndexExclusive;
}

class GitDiffMovedBlocksProjectionResult {
  GitDiffMovedBlocksProjectionResult._({
    required Iterable<GitDiffProjectedMovedBlock> blocks,
    this.fallbackReason,
  }) : blocks = List.unmodifiable(blocks);

  final List<GitDiffProjectedMovedBlock> blocks;
  final GitDiffMovedBlocksProjectionFallbackReason? fallbackReason;

  bool get canRender => fallbackReason == null;
}

/// Projects every source line of every move into the side-by-side row list.
///
/// Any missing, duplicate, mismatched, non-contiguous, or overlapping source
/// mapping disables all moved-block presentation. This prevents partial or
/// misdirected decorations over the underlying patch.
GitDiffMovedBlocksProjectionResult projectGitDiffMovedBlocks(
  GitDiffMovedBlocksResult movedBlocks,
  GitDiffPatchResult patch,
  GitDiffProjectionResult projection,
) {
  GitDiffMovedBlocksProjectionResult fallback(
    GitDiffMovedBlocksProjectionFallbackReason reason,
  ) =>
      GitDiffMovedBlocksProjectionResult._(
        blocks: const [],
        fallbackReason: reason,
      );

  if (!movedBlocks.canAnalyze) {
    return fallback(
      GitDiffMovedBlocksProjectionFallbackReason.moveModelUnavailable,
    );
  }
  if (!projection.canRender) {
    return fallback(
      GitDiffMovedBlocksProjectionFallbackReason.projectionUnavailable,
    );
  }
  if (!patch.canRender) {
    return fallback(
      GitDiffMovedBlocksProjectionFallbackReason.projectionUnavailable,
    );
  }
  if (patch.lines.length > _hardMaxProjectedRows ||
      projection.rows.length > _hardMaxProjectedRows ||
      movedBlocks.blocks.length > _hardMaxProjectedRows) {
    return fallback(GitDiffMovedBlocksProjectionFallbackReason.rowLimit);
  }

  final originalViewRowByPatchRow = <int, int>{};
  final modifiedViewRowByPatchRow = <int, int>{};
  for (var viewRowIndex = 0;
      viewRowIndex < projection.rows.length;
      viewRowIndex++) {
    final row = projection.rows[viewRowIndex];
    final originalLine = row.originalLine;
    if (originalLine != null &&
        originalViewRowByPatchRow.containsKey(originalLine.rowIndex)) {
      return fallback(
        GitDiffMovedBlocksProjectionFallbackReason.sourceRowDuplicate,
      );
    }
    if (originalLine != null) {
      originalViewRowByPatchRow[originalLine.rowIndex] = viewRowIndex;
    }

    final modifiedLine = row.modifiedLine;
    if (modifiedLine != null &&
        modifiedViewRowByPatchRow.containsKey(modifiedLine.rowIndex)) {
      return fallback(
        GitDiffMovedBlocksProjectionFallbackReason.sourceRowDuplicate,
      );
    }
    if (modifiedLine != null) {
      modifiedViewRowByPatchRow[modifiedLine.rowIndex] = viewRowIndex;
    }
  }

  final projected = <GitDiffProjectedMovedBlock>[];
  final usedOriginalRows = <int>{};
  final usedModifiedRows = <int>{};
  final usedAllRows = <int>{};

  for (final block in movedBlocks.blocks) {
    final lineCount = block.lineCount;
    if (lineCount <= 0 ||
        block.originalEndLineNumberExclusive - block.originalStartLineNumber !=
            lineCount ||
        block.modifiedEndLineNumberExclusive - block.modifiedStartLineNumber !=
            lineCount ||
        block.originalEndPatchRowExclusive - block.originalStartPatchRow !=
            lineCount ||
        block.modifiedEndPatchRowExclusive - block.modifiedStartPatchRow !=
            lineCount) {
      return fallback(
        GitDiffMovedBlocksProjectionFallbackReason.sourceRangeMismatch,
      );
    }

    final originalStart =
        originalViewRowByPatchRow[block.originalStartPatchRow];
    final modifiedStart =
        modifiedViewRowByPatchRow[block.modifiedStartPatchRow];
    if (originalStart == null || modifiedStart == null) {
      return fallback(
        GitDiffMovedBlocksProjectionFallbackReason.sourceRowMissing,
      );
    }

    for (var offset = 0; offset < lineCount; offset++) {
      final originalPatchRow = block.originalStartPatchRow + offset;
      final modifiedPatchRow = block.modifiedStartPatchRow + offset;
      if (originalPatchRow < 0 ||
          originalPatchRow >= patch.lines.length ||
          modifiedPatchRow < 0 ||
          modifiedPatchRow >= patch.lines.length) {
        return fallback(
          GitDiffMovedBlocksProjectionFallbackReason.sourceRangeMismatch,
        );
      }
      final originalViewRow = originalViewRowByPatchRow[originalPatchRow];
      final modifiedViewRow = modifiedViewRowByPatchRow[modifiedPatchRow];
      if (originalViewRow == null || modifiedViewRow == null) {
        return fallback(
          GitDiffMovedBlocksProjectionFallbackReason.sourceRowMissing,
        );
      }
      if (originalViewRow != originalStart + offset ||
          modifiedViewRow != modifiedStart + offset) {
        return fallback(
          GitDiffMovedBlocksProjectionFallbackReason.nonContiguousRows,
        );
      }

      final originalLine = projection.rows[originalViewRow].originalLine;
      final modifiedLine = projection.rows[modifiedViewRow].modifiedLine;
      final sourceOriginalLine = patch.lines[originalPatchRow];
      final sourceModifiedLine = patch.lines[modifiedPatchRow];
      if (originalLine == null ||
          modifiedLine == null ||
          !_sameSourceLine(sourceOriginalLine, originalLine) ||
          !_sameSourceLine(sourceModifiedLine, modifiedLine) ||
          originalLine.rowIndex != originalPatchRow ||
          modifiedLine.rowIndex != modifiedPatchRow ||
          originalLine.kind != GitDiffPatchLineKind.removed ||
          modifiedLine.kind != GitDiffPatchLineKind.added ||
          originalLine.originalLineNumber !=
              block.originalStartLineNumber + offset ||
          modifiedLine.modifiedLineNumber !=
              block.modifiedStartLineNumber + offset) {
        return fallback(
          GitDiffMovedBlocksProjectionFallbackReason.sourceRangeMismatch,
        );
      }

      if (originalViewRow == modifiedViewRow ||
          !usedOriginalRows.add(originalViewRow) ||
          !usedModifiedRows.add(modifiedViewRow) ||
          !usedAllRows.add(originalViewRow) ||
          !usedAllRows.add(modifiedViewRow)) {
        return fallback(
          GitDiffMovedBlocksProjectionFallbackReason.overlappingRanges,
        );
      }
    }

    projected.add(GitDiffProjectedMovedBlock(
      block: block,
      originalStartRowIndex: originalStart,
      originalEndRowIndexExclusive: originalStart + lineCount,
      modifiedStartRowIndex: modifiedStart,
      modifiedEndRowIndexExclusive: modifiedStart + lineCount,
    ));
  }

  return GitDiffMovedBlocksProjectionResult._(blocks: projected);
}

bool _sameSourceLine(GitDiffPatchLine source, GitDiffPatchLine projected) =>
    source.rowIndex == projected.rowIndex &&
    source.kind == projected.kind &&
    source.text == projected.text &&
    source.originalLineNumber == projected.originalLineNumber &&
    source.modifiedLineNumber == projected.modifiedLineNumber;
