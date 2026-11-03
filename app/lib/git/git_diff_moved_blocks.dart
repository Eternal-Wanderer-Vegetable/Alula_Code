/// Conservative moved-block matching for bounded Git unified patches.
///
/// This model recognizes exact blocks moved between hunks. It intentionally
/// leaves similarity matching and unchanged-line move detection to later
/// slices, and never changes the parsed patch or its source rows.
library;

import 'git_diff_patch.dart';

const int _hardMaxInputCodeUnits = 2000000;
const int _hardMaxRows = 16384;
const int _hardMaxCandidateTextWork = 4000000;
const int _minimumLineCount = 3;
const int _minimumTextCodeUnits = 15;
const int _minimumSubstantialLineCodeUnits = 2;
const int _minimumSubstantialLineCount = 2;

enum GitDiffMovedBlocksFallbackReason {
  unsupportedPatch,
  inputLimit,
  rowLimit,
  candidateWorkLimit,
  sourceMapping,
}

class GitDiffMovedBlocksOptions {
  const GitDiffMovedBlocksOptions({
    this.maxInputCodeUnits = _hardMaxInputCodeUnits,
    this.maxRows = _hardMaxRows,
    this.maxCandidateTextWork = _hardMaxCandidateTextWork,
  })  : assert(maxInputCodeUnits >= 0),
        assert(maxRows > 0),
        assert(maxCandidateTextWork >= 0);

  /// Includes patch prefixes and line separators, before parsing.
  final int maxInputCodeUnits;
  final int maxRows;

  /// Work is charged for each UTF-16 code unit in a deletion/insertion run
  /// considered for matching.
  final int maxCandidateTextWork;
}

class GitDiffMovedBlock {
  const GitDiffMovedBlock({
    required this.fileIndex,
    required this.originalStartLineNumber,
    required this.originalEndLineNumberExclusive,
    required this.modifiedStartLineNumber,
    required this.modifiedEndLineNumberExclusive,
    required this.originalStartPatchRow,
    required this.originalEndPatchRowExclusive,
    required this.modifiedStartPatchRow,
    required this.modifiedEndPatchRowExclusive,
  });

  /// Zero-based file index in patch order.
  final int fileIndex;

  /// Source ranges use 1-based line numbers and an exclusive end.
  final int originalStartLineNumber;
  final int originalEndLineNumberExclusive;
  final int modifiedStartLineNumber;
  final int modifiedEndLineNumberExclusive;

  /// Source patch row ranges use zero-based indexes and an exclusive end.
  final int originalStartPatchRow;
  final int originalEndPatchRowExclusive;
  final int modifiedStartPatchRow;
  final int modifiedEndPatchRowExclusive;

  int get lineCount => originalEndLineNumberExclusive - originalStartLineNumber;
}

class GitDiffMovedBlocksResult {
  GitDiffMovedBlocksResult._({
    required Iterable<GitDiffMovedBlock> blocks,
    this.fallbackReason,
  }) : blocks = List.unmodifiable(blocks);

  final List<GitDiffMovedBlock> blocks;
  final GitDiffMovedBlocksFallbackReason? fallbackReason;

  bool get canAnalyze => fallbackReason == null;
}

/// Finds unique, trim-equivalent deletion/insertion blocks in different hunks.
///
/// Candidate matching is indexed by a canonical key, so it does not compare
/// every deletion with every insertion. Ambiguous duplicate blocks are left
/// unmatched. On any resource or mapping failure the result is all-or-nothing.
GitDiffMovedBlocksResult computeGitDiffMovedBlocks(
  String unifiedPatch, {
  GitDiffMovedBlocksOptions options = const GitDiffMovedBlocksOptions(),
}) {
  GitDiffMovedBlocksResult fallback(
    GitDiffMovedBlocksFallbackReason reason,
  ) =>
      GitDiffMovedBlocksResult._(blocks: const [], fallbackReason: reason);

  final maxInputCodeUnits = _clampInt(
    options.maxInputCodeUnits,
    0,
    _hardMaxInputCodeUnits,
  );
  final maxRows = _clampInt(options.maxRows, 1, _hardMaxRows);
  final maxCandidateTextWork = _clampInt(
    options.maxCandidateTextWork,
    0,
    _hardMaxCandidateTextWork,
  );

  if (unifiedPatch.length > maxInputCodeUnits) {
    return fallback(GitDiffMovedBlocksFallbackReason.inputLimit);
  }

  final parsed = parseGitDiffPatch(
    unifiedPatch,
    options: GitDiffPatchOptions(
      maxInputCodeUnits: maxInputCodeUnits,
      maxRows: maxRows,
    ),
  );
  if (!parsed.canRender) {
    final reason = switch (parsed.fallbackReason) {
      GitDiffPatchFallbackReason.inputLimit =>
        GitDiffMovedBlocksFallbackReason.inputLimit,
      GitDiffPatchFallbackReason.rowLimit =>
        GitDiffMovedBlocksFallbackReason.rowLimit,
      GitDiffPatchFallbackReason.malformed ||
      GitDiffPatchFallbackReason.noTextHunks ||
      null =>
        GitDiffMovedBlocksFallbackReason.unsupportedPatch,
    };
    return fallback(reason);
  }
  if (parsed.lines.length > maxRows) {
    return fallback(GitDiffMovedBlocksFallbackReason.rowLimit);
  }

  final candidates = <_GitDiffMovedBlockKey, _GitDiffMovedBlockGroup>{};
  var fileIndex = -1;
  var hunkIndex = -1;
  var candidateTextWork = 0;
  GitDiffMovedBlocksFallbackReason? failure;
  _GitDiffMovedBlockCandidateBuilder? builder;

  void flushCandidate() {
    final current = builder;
    builder = null;
    if (current == null || failure != null) return;
    if (!_hasValidSourceMapping(current)) {
      failure = GitDiffMovedBlocksFallbackReason.sourceMapping;
      return;
    }
    if (current.lines.length < _minimumLineCount) return;

    final normalizedLines = <String>[];
    var normalizedTextCodeUnits = 0;
    var substantialLineCount = 0;
    for (final line in current.lines) {
      candidateTextWork += line.text.length + 1;
      if (candidateTextWork > maxCandidateTextWork) {
        failure = GitDiffMovedBlocksFallbackReason.candidateWorkLimit;
        return;
      }
      final normalized = line.text.trim();
      normalizedLines.add(normalized);
      normalizedTextCodeUnits += normalized.length;
      if (normalized.length >= _minimumSubstantialLineCodeUnits) {
        substantialLineCount++;
      }
    }
    normalizedTextCodeUnits += normalizedLines.length - 1;
    if (normalizedTextCodeUnits < _minimumTextCodeUnits ||
        substantialLineCount < _minimumSubstantialLineCount) {
      return;
    }

    final key = _GitDiffMovedBlockKey(
      current.fileIndex,
      normalizedLines.join('\n'),
    );
    final group = candidates.putIfAbsent(
      key,
      _GitDiffMovedBlockGroup.new,
    );
    if (current.kind == GitDiffPatchLineKind.removed) {
      group.deletions.add(current.toCandidate());
    } else {
      group.insertions.add(current.toCandidate());
    }
  }

  for (final line in parsed.lines) {
    if (line.kind == GitDiffPatchLineKind.metadata &&
        line.text.startsWith('diff --git ')) {
      flushCandidate();
      if (failure != null) break;
      fileIndex++;
      hunkIndex = -1;
      continue;
    }
    if (line.kind == GitDiffPatchLineKind.hunk) {
      flushCandidate();
      if (failure != null) break;
      if (fileIndex < 0) fileIndex = 0;
      hunkIndex++;
      continue;
    }
    if (line.kind == GitDiffPatchLineKind.removed ||
        line.kind == GitDiffPatchLineKind.added) {
      if (fileIndex < 0) fileIndex = 0;
      if (hunkIndex < 0) {
        failure = GitDiffMovedBlocksFallbackReason.sourceMapping;
        break;
      }
      if (builder != null &&
          (builder!.kind != line.kind ||
              builder!.fileIndex != fileIndex ||
              builder!.hunkIndex != hunkIndex)) {
        flushCandidate();
        if (failure != null) break;
      }
      builder ??= _GitDiffMovedBlockCandidateBuilder(
        fileIndex: fileIndex,
        hunkIndex: hunkIndex,
        kind: line.kind,
      );
      builder!.lines.add(line);
      continue;
    }
    flushCandidate();
    if (failure != null) break;
  }
  flushCandidate();
  if (failure != null) return fallback(failure!);

  final blocks = <GitDiffMovedBlock>[];
  for (final group in candidates.entries) {
    if (group.value.deletions.length != 1 ||
        group.value.insertions.length != 1) {
      continue;
    }
    final deletion = group.value.deletions.single;
    final insertion = group.value.insertions.single;
    if (deletion.hunkIndex == insertion.hunkIndex) continue;
    if (deletion.lines.length != insertion.lines.length) {
      return fallback(GitDiffMovedBlocksFallbackReason.sourceMapping);
    }
    blocks.add(GitDiffMovedBlock(
      fileIndex: deletion.fileIndex,
      originalStartLineNumber: deletion.startLineNumber,
      originalEndLineNumberExclusive:
          deletion.startLineNumber + deletion.lines.length,
      modifiedStartLineNumber: insertion.startLineNumber,
      modifiedEndLineNumberExclusive:
          insertion.startLineNumber + insertion.lines.length,
      originalStartPatchRow: deletion.lines.first.rowIndex,
      originalEndPatchRowExclusive: deletion.lines.last.rowIndex + 1,
      modifiedStartPatchRow: insertion.lines.first.rowIndex,
      modifiedEndPatchRowExclusive: insertion.lines.last.rowIndex + 1,
    ));
  }

  blocks.sort((a, b) {
    final fileOrder = a.fileIndex.compareTo(b.fileIndex);
    if (fileOrder != 0) return fileOrder;
    final oldOrder = a.originalStartPatchRow.compareTo(b.originalStartPatchRow);
    if (oldOrder != 0) return oldOrder;
    return a.modifiedStartPatchRow.compareTo(b.modifiedStartPatchRow);
  });
  if (!_hasNonOverlappingMovedBlocks(blocks)) {
    return fallback(GitDiffMovedBlocksFallbackReason.sourceMapping);
  }
  return GitDiffMovedBlocksResult._(blocks: blocks);
}

class _GitDiffMovedBlockCandidateBuilder {
  _GitDiffMovedBlockCandidateBuilder({
    required this.fileIndex,
    required this.hunkIndex,
    required this.kind,
  });

  final int fileIndex;
  final int hunkIndex;
  final GitDiffPatchLineKind kind;
  final List<GitDiffPatchLine> lines = [];

  _GitDiffMovedBlockCandidate toCandidate() => _GitDiffMovedBlockCandidate(
        fileIndex: fileIndex,
        hunkIndex: hunkIndex,
        lines: List.unmodifiable(lines),
        startLineNumber: kind == GitDiffPatchLineKind.removed
            ? lines.first.originalLineNumber!
            : lines.first.modifiedLineNumber!,
      );
}

class _GitDiffMovedBlockCandidate {
  const _GitDiffMovedBlockCandidate({
    required this.fileIndex,
    required this.hunkIndex,
    required this.lines,
    required this.startLineNumber,
  });

  final int fileIndex;
  final int hunkIndex;
  final List<GitDiffPatchLine> lines;
  final int startLineNumber;
}

class _GitDiffMovedBlockGroup {
  final List<_GitDiffMovedBlockCandidate> deletions = [];
  final List<_GitDiffMovedBlockCandidate> insertions = [];
}

class _GitDiffMovedBlockKey {
  const _GitDiffMovedBlockKey(this.fileIndex, this.normalizedText);

  final int fileIndex;
  final String normalizedText;

  @override
  bool operator ==(Object other) =>
      other is _GitDiffMovedBlockKey &&
      other.fileIndex == fileIndex &&
      other.normalizedText == normalizedText;

  @override
  int get hashCode => Object.hash(fileIndex, normalizedText);
}

int _clampInt(int value, int minimum, int maximum) {
  if (value < minimum) return minimum;
  if (value > maximum) return maximum;
  return value;
}

bool _hasValidSourceMapping(_GitDiffMovedBlockCandidateBuilder candidate) {
  if (candidate.fileIndex < 0 ||
      candidate.hunkIndex < 0 ||
      candidate.lines.isEmpty) {
    return false;
  }
  final first = candidate.lines.first;
  final startLineNumber = candidate.kind == GitDiffPatchLineKind.removed
      ? first.originalLineNumber
      : first.modifiedLineNumber;
  if (startLineNumber == null || startLineNumber < 1) return false;
  for (var index = 0; index < candidate.lines.length; index++) {
    final line = candidate.lines[index];
    if (line.rowIndex != first.rowIndex + index ||
        line.kind != candidate.kind) {
      return false;
    }
    if (candidate.kind == GitDiffPatchLineKind.removed) {
      if (line.originalLineNumber != startLineNumber + index ||
          line.modifiedLineNumber != null) {
        return false;
      }
    } else if (line.modifiedLineNumber != startLineNumber + index ||
        line.originalLineNumber != null) {
      return false;
    }
  }
  return true;
}

bool _hasNonOverlappingMovedBlocks(List<GitDiffMovedBlock> blocks) {
  final byFile = <int, List<GitDiffMovedBlock>>{};
  for (final block in blocks) {
    byFile.putIfAbsent(block.fileIndex, () => []).add(block);
  }

  bool nonOverlapping(
    List<GitDiffMovedBlock> ranges,
    int Function(GitDiffMovedBlock) start,
    int Function(GitDiffMovedBlock) end,
  ) {
    ranges.sort((a, b) => start(a).compareTo(start(b)));
    for (var index = 1; index < ranges.length; index++) {
      if (start(ranges[index]) < end(ranges[index - 1])) return false;
    }
    return true;
  }

  for (final ranges in byFile.values) {
    if (!nonOverlapping(
          ranges,
          (block) => block.originalStartLineNumber,
          (block) => block.originalEndLineNumberExclusive,
        ) ||
        !nonOverlapping(
          ranges,
          (block) => block.modifiedStartLineNumber,
          (block) => block.modifiedEndLineNumberExclusive,
        )) {
      return false;
    }
  }
  return true;
}
