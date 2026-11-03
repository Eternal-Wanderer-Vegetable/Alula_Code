/// Bounded projection of a parsed unified patch into aligned source columns.
///
/// The projection keeps the parser's source-line objects and never copies
/// source text. Consecutive removed/added rows pair by ordinal position, with
/// any excess rows left blank on the opposite side.
library;

import 'git_diff_patch.dart';

enum GitDiffSideBySideRowKind { metadata, hunk, context, changed, marker }

enum GitDiffSideBySideFallbackReason {
  unsupportedPatch,
  rowLimit,
  alignmentInvariant,
}

class GitDiffSideBySideOptions {
  const GitDiffSideBySideOptions({this.maxRows = 16384}) : assert(maxRows > 0);

  final int maxRows;
}

class GitDiffSideBySideRow {
  const GitDiffSideBySideRow({
    required this.rowIndex,
    required this.kind,
    this.originalLine,
    this.modifiedLine,
    this.fullWidthLine,
  });

  final int rowIndex;
  final GitDiffSideBySideRowKind kind;
  final GitDiffPatchLine? originalLine;
  final GitDiffPatchLine? modifiedLine;

  /// Hunk, metadata, and no-newline marker rows span both columns.
  final GitDiffPatchLine? fullWidthLine;
}

class GitDiffSideBySideResult {
  const GitDiffSideBySideResult._({
    required this.rows,
    this.fallbackReason,
  });

  final List<GitDiffSideBySideRow> rows;
  final GitDiffSideBySideFallbackReason? fallbackReason;

  bool get canRender => fallbackReason == null;
}

/// Projects parsed patch rows without recomputing a diff or truncating input.
///
/// Context, hunk, and metadata rows terminate replacement blocks. A no-newline
/// marker stays in its block so it cannot prevent the matching old/new rows
/// from aligning; it is emitted full-width immediately after the pair it
/// follows. The output count never exceeds the input patch row count.
GitDiffSideBySideResult computeGitDiffSideBySideRows(
  GitDiffPatchResult patch, {
  GitDiffSideBySideOptions options = const GitDiffSideBySideOptions(),
}) {
  GitDiffSideBySideResult fallback(GitDiffSideBySideFallbackReason reason) =>
      GitDiffSideBySideResult._(rows: const [], fallbackReason: reason);

  if (!patch.canRender) {
    return fallback(GitDiffSideBySideFallbackReason.unsupportedPatch);
  }
  if (patch.lines.length > options.maxRows) {
    return fallback(GitDiffSideBySideFallbackReason.rowLimit);
  }

  final rows = <GitDiffSideBySideRow>[];
  var inputIndex = 0;

  void append(
    GitDiffSideBySideRowKind kind, {
    GitDiffPatchLine? originalLine,
    GitDiffPatchLine? modifiedLine,
    GitDiffPatchLine? fullWidthLine,
  }) {
    rows.add(GitDiffSideBySideRow(
      rowIndex: rows.length,
      kind: kind,
      originalLine: originalLine,
      modifiedLine: modifiedLine,
      fullWidthLine: fullWidthLine,
    ));
  }

  while (inputIndex < patch.lines.length) {
    final line = patch.lines[inputIndex];
    switch (line.kind) {
      case GitDiffPatchLineKind.context:
        append(
          GitDiffSideBySideRowKind.context,
          originalLine: line,
          modifiedLine: line,
        );
        inputIndex++;
        break;
      case GitDiffPatchLineKind.removed:
      case GitDiffPatchLineKind.added:
        final end = _changedBlockEnd(patch.lines, inputIndex);
        _appendChangedBlock(patch.lines, inputIndex, end, append);
        inputIndex = end;
        break;
      case GitDiffPatchLineKind.metadata:
        append(
          GitDiffSideBySideRowKind.metadata,
          fullWidthLine: line,
        );
        inputIndex++;
        break;
      case GitDiffPatchLineKind.hunk:
        append(
          GitDiffSideBySideRowKind.hunk,
          fullWidthLine: line,
        );
        inputIndex++;
        break;
      case GitDiffPatchLineKind.marker:
        append(
          GitDiffSideBySideRowKind.marker,
          fullWidthLine: line,
        );
        inputIndex++;
        break;
    }
  }

  if (rows.length > options.maxRows ||
      !_preservesSourceOrder(patch.lines, rows)) {
    return fallback(rows.length > options.maxRows
        ? GitDiffSideBySideFallbackReason.rowLimit
        : GitDiffSideBySideFallbackReason.alignmentInvariant);
  }

  return GitDiffSideBySideResult._(rows: List.unmodifiable(rows));
}

int _changedBlockEnd(List<GitDiffPatchLine> lines, int start) {
  var end = start;
  while (end < lines.length) {
    final kind = lines[end].kind;
    if (kind != GitDiffPatchLineKind.removed &&
        kind != GitDiffPatchLineKind.added &&
        kind != GitDiffPatchLineKind.marker) {
      break;
    }
    end++;
  }
  return end;
}

void _appendChangedBlock(
  List<GitDiffPatchLine> lines,
  int start,
  int end,
  void Function(
    GitDiffSideBySideRowKind kind, {
    GitDiffPatchLine? originalLine,
    GitDiffPatchLine? modifiedLine,
    GitDiffPatchLine? fullWidthLine,
  }) append,
) {
  final removed = <GitDiffPatchLine>[];
  final added = <GitDiffPatchLine>[];
  final markersAfterPair = <int, List<GitDiffPatchLine>>{};

  for (var index = start; index < end; index++) {
    final line = lines[index];
    switch (line.kind) {
      case GitDiffPatchLineKind.removed:
        removed.add(line);
        break;
      case GitDiffPatchLineKind.added:
        added.add(line);
        break;
      case GitDiffPatchLineKind.marker:
        final pairIndex = _max(removed.length, added.length);
        markersAfterPair.putIfAbsent(pairIndex, () => []).add(line);
        break;
      case GitDiffPatchLineKind.metadata:
      case GitDiffPatchLineKind.hunk:
      case GitDiffPatchLineKind.context:
        // The block end is computed before this method is called.
        break;
    }
  }

  final pairCount = _max(removed.length, added.length);
  for (var pairIndex = 0; pairIndex <= pairCount; pairIndex++) {
    for (final marker in markersAfterPair[pairIndex] ?? const []) {
      append(
        GitDiffSideBySideRowKind.marker,
        fullWidthLine: marker,
      );
    }
    if (pairIndex == pairCount) continue;
    append(
      GitDiffSideBySideRowKind.changed,
      originalLine: pairIndex < removed.length ? removed[pairIndex] : null,
      modifiedLine: pairIndex < added.length ? added[pairIndex] : null,
    );
  }
}

bool _preservesSourceOrder(
  List<GitDiffPatchLine> input,
  List<GitDiffSideBySideRow> output,
) {
  final expectedOriginal = <int>[];
  final expectedModified = <int>[];
  final expectedFullWidth = <int>[];
  for (final line in input) {
    switch (line.kind) {
      case GitDiffPatchLineKind.context:
        expectedOriginal.add(line.rowIndex);
        expectedModified.add(line.rowIndex);
        break;
      case GitDiffPatchLineKind.removed:
        expectedOriginal.add(line.rowIndex);
        break;
      case GitDiffPatchLineKind.added:
        expectedModified.add(line.rowIndex);
        break;
      case GitDiffPatchLineKind.metadata:
      case GitDiffPatchLineKind.hunk:
      case GitDiffPatchLineKind.marker:
        expectedFullWidth.add(line.rowIndex);
        break;
    }
  }

  final actualOriginal = <int>[];
  final actualModified = <int>[];
  final actualFullWidth = <int>[];
  for (final row in output) {
    if (row.fullWidthLine case final fullWidthLine?) {
      actualFullWidth.add(fullWidthLine.rowIndex);
      continue;
    }
    if (row.originalLine case final originalLine?) {
      actualOriginal.add(originalLine.rowIndex);
    }
    if (row.modifiedLine case final modifiedLine?) {
      actualModified.add(modifiedLine.rowIndex);
    }
  }
  return _sameIndexes(expectedOriginal, actualOriginal) &&
      _sameIndexes(expectedModified, actualModified) &&
      _sameIndexes(expectedFullWidth, actualFullWidth);
}

int _max(int first, int second) => first > second ? first : second;

bool _sameIndexes(List<int> expected, List<int> actual) {
  if (expected.length != actual.length) return false;
  for (var index = 0; index < expected.length; index++) {
    if (expected[index] != actual[index]) return false;
  }
  return true;
}
