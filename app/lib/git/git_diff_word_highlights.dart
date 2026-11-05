/// Bounded word-level ranges for paired source rows in a Git unified patch.
library;

import '../editor/word_diff.dart';
import 'git_diff_patch.dart';

enum GitDiffPatchWordFallbackReason {
  pairLimit,
  aggregateInputLimit,
  aggregateWorkLimit,
  wordInputLimit,
  wordWorkLimit,
  wordAlignmentInvariant,
}

class GitDiffPatchWordOptions {
  const GitDiffPatchWordOptions({
    this.maxPairs = 8192,
    this.maxAggregateInputCodeUnits = 262144,
    this.maxAggregateWork = 2000000,
    this.maxTraceCellsPerPair = 1000000,
    this.maxWordWorkPerPair = 2000000,
  })  : assert(maxPairs > 0),
        assert(maxAggregateInputCodeUnits >= 0),
        assert(maxAggregateWork >= 0),
        assert(maxTraceCellsPerPair >= 0),
        assert(maxWordWorkPerPair >= 0);

  /// Maximum number of removed/added line pairs visited.
  final int maxPairs;

  /// Maximum combined UTF-16 input across pairs sent to the word diff.
  final int maxAggregateInputCodeUnits;

  /// Maximum sum of per-pair word-diff work reservations.
  final int maxAggregateWork;

  /// Temporary Myers trace cap for each sequential pair computation.
  final int maxTraceCellsPerPair;

  /// Maximum work reservation for any one paired line.
  final int maxWordWorkPerPair;
}

class GitDiffWordRange {
  const GitDiffWordRange({
    required this.startUtf16,
    required this.endUtf16,
  });

  final int startUtf16;
  final int endUtf16;
}

class GitDiffPatchWordLineChanges {
  GitDiffPatchWordLineChanges._({
    required this.ranges,
    this.fallbackReason,
  });

  /// Zero-based, end-exclusive UTF-16 ranges for this patch row.
  final List<GitDiffWordRange> ranges;
  final GitDiffPatchWordFallbackReason? fallbackReason;
}

class GitDiffPatchWordResult {
  GitDiffPatchWordResult._({
    required this.linesByRowIndex,
    required this.pairedCount,
    required this.computedPairCount,
    required this.fallbackPairCount,
  });

  /// Only paired removed/added rows appear in this map.
  final Map<int, GitDiffPatchWordLineChanges> linesByRowIndex;
  final int pairedCount;
  final int computedPairCount;
  final int fallbackPairCount;

  GitDiffPatchWordLineChanges? changesForRow(int rowIndex) =>
      linesByRowIndex[rowIndex];
}

/// Pairs deletions and additions by order inside each contiguous change block.
///
/// Context, hunk headers, and metadata break a block. Git's no-newline marker
/// remains inside its surrounding block so an EOF replacement still pairs.
/// Unmatched rows remain one-sided and receive no inline ranges.
GitDiffPatchWordResult computeGitDiffPatchWordChanges(
  GitDiffPatchResult patch, {
  GitDiffPatchWordOptions options = const GitDiffPatchWordOptions(),
}) {
  final blocks = <_GitDiffPatchChangeBlock>[];
  _GitDiffPatchChangeBlock? block;
  for (final line in patch.lines) {
    switch (line.kind) {
      case GitDiffPatchLineKind.removed:
        block ??= _GitDiffPatchChangeBlock();
        block.removed.add(line);
      case GitDiffPatchLineKind.added:
        block ??= _GitDiffPatchChangeBlock();
        block.added.add(line);
      case GitDiffPatchLineKind.marker:
        break;
      case GitDiffPatchLineKind.metadata:
      case GitDiffPatchLineKind.hunk:
      case GitDiffPatchLineKind.context:
        block = null;
    }
    if (block != null && (blocks.isEmpty || !identical(blocks.last, block))) {
      blocks.add(block);
    }
  }

  var pairedCount = 0;
  for (final changeBlock in blocks) {
    final count = _minimum(
      changeBlock.removed.length,
      changeBlock.added.length,
    );
    pairedCount += count;
  }

  final linesByRowIndex = <int, GitDiffPatchWordLineChanges>{};
  final pairBudget = _minimum(pairedCount, options.maxPairs);
  var pairIndex = 0;
  var remainingInput = options.maxAggregateInputCodeUnits;
  var remainingWork = options.maxAggregateWork;
  var computedPairCount = 0;
  var fallbackPairCount = 0;

  for (final changeBlock in blocks) {
    final count = _minimum(
      changeBlock.removed.length,
      changeBlock.added.length,
    );
    for (var offset = 0; offset < count; offset++) {
      final removed = changeBlock.removed[offset];
      final added = changeBlock.added[offset];
      final pairInput = removed.text.length + added.text.length;
      GitDiffPatchWordFallbackReason? forcedFallback;

      if (pairIndex >= options.maxPairs) {
        forcedFallback = GitDiffPatchWordFallbackReason.pairLimit;
      } else if (pairInput > remainingInput) {
        forcedFallback = GitDiffPatchWordFallbackReason.aggregateInputLimit;
      }

      WordDiffResult? wordResult;
      if (forcedFallback == null) {
        final remainingPairs = pairBudget - pairIndex;
        final reservedWork = remainingPairs <= 0
            ? 0
            : _minimum(
                options.maxWordWorkPerPair,
                remainingWork ~/ remainingPairs,
              );
        if (reservedWork <= 0) {
          forcedFallback = GitDiffPatchWordFallbackReason.aggregateWorkLimit;
        } else {
          remainingInput -= pairInput;
          remainingWork -= reservedWork;
          wordResult = computeWordDiff(
            removed.text,
            added.text,
            options: WordDiffOptions(
              maxInputCodeUnits: pairInput,
              maxTraceCells: options.maxTraceCellsPerPair,
              maxWork: reservedWork,
            ),
          );
        }
      }

      final fallbackReason =
          forcedFallback ?? _wordFallbackReason(wordResult?.fallbackReason);
      final removedRanges = fallbackReason == null
          ? _originalRanges(wordResult!.hunks)
          : _wholeLineRange(removed.text);
      final addedRanges = fallbackReason == null
          ? _modifiedRanges(wordResult!.hunks)
          : _wholeLineRange(added.text);
      linesByRowIndex[removed.rowIndex] = GitDiffPatchWordLineChanges._(
        ranges: List.unmodifiable(removedRanges),
        fallbackReason: fallbackReason,
      );
      linesByRowIndex[added.rowIndex] = GitDiffPatchWordLineChanges._(
        ranges: List.unmodifiable(addedRanges),
        fallbackReason: fallbackReason,
      );

      if (fallbackReason == null) {
        computedPairCount++;
      } else {
        fallbackPairCount++;
      }
      pairIndex++;
    }
  }

  return GitDiffPatchWordResult._(
    linesByRowIndex: Map.unmodifiable(linesByRowIndex),
    pairedCount: pairedCount,
    computedPairCount: computedPairCount,
    fallbackPairCount: fallbackPairCount,
  );
}

class _GitDiffPatchChangeBlock {
  final removed = <GitDiffPatchLine>[];
  final added = <GitDiffPatchLine>[];
}

List<GitDiffWordRange> _originalRanges(List<WordDiffHunk> hunks) => [
      for (final hunk in hunks)
        if (hunk.originalEndUtf16 > hunk.originalStartUtf16)
          GitDiffWordRange(
            startUtf16: hunk.originalStartUtf16,
            endUtf16: hunk.originalEndUtf16,
          ),
    ];

List<GitDiffWordRange> _modifiedRanges(List<WordDiffHunk> hunks) => [
      for (final hunk in hunks)
        if (hunk.modifiedEndUtf16 > hunk.modifiedStartUtf16)
          GitDiffWordRange(
            startUtf16: hunk.modifiedStartUtf16,
            endUtf16: hunk.modifiedEndUtf16,
          ),
    ];

List<GitDiffWordRange> _wholeLineRange(String text) => text.isEmpty
    ? const []
    : [GitDiffWordRange(startUtf16: 0, endUtf16: text.length)];

GitDiffPatchWordFallbackReason? _wordFallbackReason(
  WordDiffFallbackReason? reason,
) {
  switch (reason) {
    case null:
      return null;
    case WordDiffFallbackReason.inputLimit:
      return GitDiffPatchWordFallbackReason.wordInputLimit;
    case WordDiffFallbackReason.workLimit:
      return GitDiffPatchWordFallbackReason.wordWorkLimit;
    case WordDiffFallbackReason.alignmentInvariant:
      return GitDiffPatchWordFallbackReason.wordAlignmentInvariant;
  }
}

int _minimum(int first, int second) => first < second ? first : second;
