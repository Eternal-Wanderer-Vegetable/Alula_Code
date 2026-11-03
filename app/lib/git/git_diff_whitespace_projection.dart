/// Bounded Git-patch projection using the editor's default trim-whitespace
/// diff semantics.
library;

import '../editor/diff_view_model.dart';
import '../editor/line_diff.dart';
import '../editor/word_diff.dart';
import 'git_diff_patch.dart';
import 'git_diff_word_highlights.dart';

enum GitDiffProjectionRowKind {
  metadata,
  hunk,
  context,
  changed,
  inserted,
  deleted,
  marker,
}

enum GitDiffProjectionFallbackReason {
  unsupportedPatch,
  inputLimit,
  sourceRowLimit,
  rowLimit,
  modelFallback,
  sourceMapping,
  markerMapping,
}

class GitDiffProjectionOptions {
  const GitDiffProjectionOptions({
    this.maxModelInputCodeUnits = 2000000,
    this.maxModelSourceRows = 16384,
    this.maxRows = 16384,
    this.maxLineDiffTraceCells = 2000000,
    this.maxLineDiffWork = 4000000,
    this.maxWordInputCodeUnits = 262144,
    this.maxWordWork = 2000000,
  })  : assert(maxModelInputCodeUnits >= 0),
        assert(maxModelSourceRows > 0),
        assert(maxRows > 0),
        assert(maxLineDiffTraceCells >= 0),
        assert(maxLineDiffWork >= 0),
        assert(maxWordInputCodeUnits >= 0),
        assert(maxWordWork >= 0);

  /// Caps the combined old/new hunk text materialized by the projection.
  final int maxModelInputCodeUnits;

  /// Caps source lines copied into the bounded diff model, counting both sides.
  final int maxModelSourceRows;

  /// Caps projected aligned rows and inline rows.
  final int maxRows;

  /// Aggregate Myers trace and step budgets divided across parsed hunks.
  final int maxLineDiffTraceCells;
  final int maxLineDiffWork;

  /// Aggregate inline word-diff budgets divided across parsed hunks.
  final int maxWordInputCodeUnits;
  final int maxWordWork;
}

class GitDiffProjectionRow {
  const GitDiffProjectionRow({
    required this.rowIndex,
    required this.kind,
    this.originalLine,
    this.modifiedLine,
    this.fullWidthLine,
    this.originalWordChanges = const [],
    this.modifiedWordChanges = const [],
    this.trimWhitespaceEquivalent = false,
  });

  /// Index in the aligned projection, including hunk and metadata rows.
  final int rowIndex;
  final GitDiffProjectionRowKind kind;
  final GitDiffPatchLine? originalLine;
  final GitDiffPatchLine? modifiedLine;
  final GitDiffPatchLine? fullWidthLine;
  final List<GitDiffWordRange> originalWordChanges;
  final List<GitDiffWordRange> modifiedWordChanges;

  /// True when Code-OSS considers the line pair equal after trimming its ends.
  final bool trimWhitespaceEquivalent;
}

class GitDiffProjectionInlineRow {
  const GitDiffProjectionInlineRow({
    required this.line,
    this.wordChanges = const [],
  });

  final GitDiffPatchLine line;
  final List<GitDiffWordRange> wordChanges;
}

class GitDiffProjectionChange {
  const GitDiffProjectionChange({
    required this.firstRowIndex,
    required this.inlineRowIndex,
    required this.sideBySideRowIndex,
    this.originalLineNumber,
    this.modifiedLineNumber,
  });

  /// Original patch-source row used to preserve the existing navigation API.
  final int firstRowIndex;

  /// Row to reveal in the inline list after whitespace-equivalent rows fold.
  final int inlineRowIndex;

  /// Row to reveal in the aligned list.
  final int sideBySideRowIndex;

  final int? originalLineNumber;
  final int? modifiedLineNumber;
}

class GitDiffProjectionResult {
  const GitDiffProjectionResult._({
    required this.rows,
    required this.inlineRows,
    required this.changes,
    this.fallbackReason,
  });

  final List<GitDiffProjectionRow> rows;
  final List<GitDiffProjectionInlineRow> inlineRows;
  final List<GitDiffProjectionChange> changes;
  final GitDiffProjectionFallbackReason? fallbackReason;

  bool get canRender => fallbackReason == null;
}

/// Projects every text hunk independently, preserving its source rows and
/// falling back to the complete raw patch if parsing, budgets, or mappings fail.
///
/// The line and word alignment semantics come from [computeDiffViewModel],
/// whose default `LineDiffOptions` match Code-OSS `ignoreTrimWhitespace: true`.
GitDiffProjectionResult projectGitDiffPatchIgnoringTrimWhitespace(
  GitDiffPatchResult patch, {
  GitDiffProjectionOptions options = const GitDiffProjectionOptions(),
}) {
  GitDiffProjectionResult fallback(GitDiffProjectionFallbackReason reason) =>
      GitDiffProjectionResult._(
        rows: const [],
        inlineRows: const [],
        changes: const [],
        fallbackReason: reason,
      );

  if (!patch.canRender) {
    return fallback(GitDiffProjectionFallbackReason.unsupportedPatch);
  }
  if (patch.lines.length > options.maxRows) {
    return fallback(GitDiffProjectionFallbackReason.rowLimit);
  }

  final segments = _segments(patch.lines);
  if (segments == null) {
    return fallback(GitDiffProjectionFallbackReason.sourceMapping);
  }

  final hunks = [
    for (final segment in segments)
      if (segment.hunk != null) segment.hunk!
  ];
  var modelInputCodeUnits = 0;
  var modelSourceRows = 0;
  for (final hunk in hunks) {
    modelInputCodeUnits += hunk.modelInputCodeUnits;
    modelSourceRows += hunk.originalLines.length + hunk.modifiedLines.length;
    if (modelInputCodeUnits > options.maxModelInputCodeUnits) {
      return fallback(GitDiffProjectionFallbackReason.inputLimit);
    }
    if (modelSourceRows > options.maxModelSourceRows) {
      return fallback(GitDiffProjectionFallbackReason.sourceRowLimit);
    }
  }

  final diffHunks = [
    for (final hunk in hunks)
      if (hunk.originalLines.isNotEmpty && hunk.modifiedLines.isNotEmpty) hunk,
  ];
  final lineTraceBudgets = _divideBudget(
    options.maxLineDiffTraceCells,
    diffHunks.length,
  );
  final lineWorkBudgets = _divideBudget(
    options.maxLineDiffWork,
    diffHunks.length,
  );
  final wordInputBudgets = _divideBudget(
    options.maxWordInputCodeUnits,
    diffHunks.length,
  );
  final wordWorkBudgets = _divideBudget(options.maxWordWork, diffHunks.length);
  var diffHunkIndex = 0;

  final pendingRows = <_PendingProjectionRow>[];
  for (final segment in segments) {
    final fullWidthLine = segment.fullWidthLine;
    if (fullWidthLine != null) {
      final kind = switch (fullWidthLine.kind) {
        GitDiffPatchLineKind.metadata => GitDiffProjectionRowKind.metadata,
        GitDiffPatchLineKind.hunk => GitDiffProjectionRowKind.hunk,
        GitDiffPatchLineKind.marker => GitDiffProjectionRowKind.marker,
        _ => null,
      };
      if (kind == null) {
        return fallback(GitDiffProjectionFallbackReason.sourceMapping);
      }
      pendingRows.add(_PendingProjectionRow(
        kind: kind,
        fullWidthLine: fullWidthLine,
      ));
      continue;
    }

    final hunk = segment.hunk!;
    pendingRows.add(_PendingProjectionRow(
      kind: GitDiffProjectionRowKind.hunk,
      fullWidthLine: hunk.header,
    ));
    final localRows = <_PendingProjectionRow>[];
    final originalRowBySourceIndex = <int, int>{};
    final modifiedRowBySourceIndex = <int, int>{};

    if (hunk.originalLines.isEmpty || hunk.modifiedLines.isEmpty) {
      final isInsertion = hunk.originalLines.isEmpty;
      final source = isInsertion ? hunk.modifiedLines : hunk.originalLines;
      for (final sourceLine in source) {
        final displayLine = _displayLine(
          sourceLine,
          kind: isInsertion
              ? GitDiffPatchLineKind.added
              : GitDiffPatchLineKind.removed,
          text: sourceLine.text,
        );
        final rowIndex = localRows.length;
        localRows.add(_PendingProjectionRow(
          kind: isInsertion
              ? GitDiffProjectionRowKind.inserted
              : GitDiffProjectionRowKind.deleted,
          originalLine: isInsertion ? null : displayLine,
          modifiedLine: isInsertion ? displayLine : null,
        ));
        (isInsertion
            ? modifiedRowBySourceIndex
            : originalRowBySourceIndex)[sourceLine.rowIndex] = rowIndex;
      }
    } else {
      final model = computeDiffViewModel(
        hunk.originalText,
        hunk.modifiedText,
        options: DiffViewModelOptions(
          lineDiffOptions: LineDiffOptions(
            ignoreTrimWhitespace: true,
            maxInputCodeUnits: hunk.modelInputCodeUnits,
            maxLinesPerSide:
                _max(hunk.originalLines.length, hunk.modifiedLines.length),
            maxTraceCells: lineTraceBudgets[diffHunkIndex],
            maxWork: lineWorkBudgets[diffHunkIndex],
          ),
          maxInputCodeUnits: hunk.modelInputCodeUnits,
          maxRows: hunk.originalLines.length + hunk.modifiedLines.length,
          maxAggregateWordInputCodeUnits: wordInputBudgets[diffHunkIndex],
          maxAggregateWordWork: wordWorkBudgets[diffHunkIndex],
        ),
      );
      diffHunkIndex++;
      if (model.fallbackReason != null || model.isApproximate) {
        return fallback(GitDiffProjectionFallbackReason.modelFallback);
      }

      final originalSeen = List<bool>.filled(hunk.originalLines.length, false);
      final modifiedSeen = List<bool>.filled(hunk.modifiedLines.length, false);
      for (final viewRow in model.rows) {
        final originalSource = _lineAt(
          hunk.originalLines,
          viewRow.originalLineNumber,
        );
        final modifiedSource = _lineAt(
          hunk.modifiedLines,
          viewRow.modifiedLineNumber,
        );
        if (viewRow.originalLineNumber != null && originalSource == null ||
            viewRow.modifiedLineNumber != null && modifiedSource == null) {
          return fallback(GitDiffProjectionFallbackReason.sourceMapping);
        }
        if (viewRow.originalLineNumber case final lineNumber?) {
          final index = lineNumber - 1;
          if (index < 0 || originalSeen[index]) {
            return fallback(GitDiffProjectionFallbackReason.sourceMapping);
          }
          originalSeen[index] = true;
        }
        if (viewRow.modifiedLineNumber case final lineNumber?) {
          final index = lineNumber - 1;
          if (index < 0 || modifiedSeen[index]) {
            return fallback(GitDiffProjectionFallbackReason.sourceMapping);
          }
          modifiedSeen[index] = true;
        }

        final rowIndex = localRows.length;
        final kind = switch (viewRow.kind) {
          DiffViewRowKind.unchanged => GitDiffProjectionRowKind.context,
          DiffViewRowKind.modified => GitDiffProjectionRowKind.changed,
          DiffViewRowKind.inserted => GitDiffProjectionRowKind.inserted,
          DiffViewRowKind.deleted => GitDiffProjectionRowKind.deleted,
        };
        final originalLine = originalSource == null
            ? null
            : _displayLine(
                originalSource,
                kind: kind == GitDiffProjectionRowKind.context
                    ? GitDiffPatchLineKind.context
                    : GitDiffPatchLineKind.removed,
                text: viewRow.originalText!,
              );
        final modifiedLine = modifiedSource == null
            ? null
            : _displayLine(
                modifiedSource,
                kind: kind == GitDiffProjectionRowKind.context
                    ? GitDiffPatchLineKind.context
                    : GitDiffPatchLineKind.added,
                text: viewRow.modifiedText!,
              );
        localRows.add(_PendingProjectionRow(
          kind: kind,
          originalLine: originalLine,
          modifiedLine: modifiedLine,
          originalWordChanges: _wordRanges(viewRow.wordChanges, original: true),
          modifiedWordChanges:
              _wordRanges(viewRow.wordChanges, original: false),
          trimWhitespaceEquivalent: kind == GitDiffProjectionRowKind.context &&
              viewRow.originalText != viewRow.modifiedText,
        ));
        if (originalSource != null) {
          originalRowBySourceIndex[originalSource.rowIndex] = rowIndex;
        }
        if (modifiedSource != null) {
          modifiedRowBySourceIndex[modifiedSource.rowIndex] = rowIndex;
        }
      }
      if (originalSeen.any((seen) => !seen) ||
          modifiedSeen.any((seen) => !seen)) {
        return fallback(GitDiffProjectionFallbackReason.sourceMapping);
      }
    }

    final markersAfterRow = <int, List<GitDiffPatchLine>>{};
    var previousMarkerTarget = -1;
    for (final marker in hunk.markers) {
      final originalTarget = marker.originalSourceRowIndex == null
          ? null
          : originalRowBySourceIndex[marker.originalSourceRowIndex];
      final modifiedTarget = marker.modifiedSourceRowIndex == null
          ? null
          : modifiedRowBySourceIndex[marker.modifiedSourceRowIndex];
      if (marker.originalSourceRowIndex != null && originalTarget == null ||
          marker.modifiedSourceRowIndex != null && modifiedTarget == null ||
          originalTarget != null &&
              modifiedTarget != null &&
              originalTarget != modifiedTarget) {
        return fallback(GitDiffProjectionFallbackReason.markerMapping);
      }
      final target = originalTarget ?? modifiedTarget;
      if (target == null || target < previousMarkerTarget) {
        return fallback(GitDiffProjectionFallbackReason.markerMapping);
      }
      previousMarkerTarget = target;
      markersAfterRow.putIfAbsent(target, () => []).add(marker.line);
    }

    for (var index = 0; index < localRows.length; index++) {
      pendingRows.add(localRows[index]);
      for (final marker in markersAfterRow[index] ?? const []) {
        pendingRows.add(_PendingProjectionRow(
          kind: GitDiffProjectionRowKind.marker,
          fullWidthLine: marker,
        ));
      }
    }
  }

  if (pendingRows.length > options.maxRows) {
    return fallback(GitDiffProjectionFallbackReason.rowLimit);
  }
  final rows = [
    for (var index = 0; index < pendingRows.length; index++)
      pendingRows[index].toRow(index),
  ];

  final orderedInlineRows = <_OrderedInlineRow>[];
  final inlineIndexBySourceRow = <int, int>{};
  var inlineOrder = 0;
  void addInlineRow(int sourceRowIndex, GitDiffProjectionInlineRow row) {
    orderedInlineRows.add(_OrderedInlineRow(
      sourceRowIndex: sourceRowIndex,
      order: inlineOrder++,
      row: row,
    ));
  }

  for (final row in rows) {
    switch (row.kind) {
      case GitDiffProjectionRowKind.metadata:
      case GitDiffProjectionRowKind.hunk:
      case GitDiffProjectionRowKind.marker:
        final line = row.fullWidthLine!;
        addInlineRow(line.rowIndex, GitDiffProjectionInlineRow(line: line));
      case GitDiffProjectionRowKind.context:
        final originalLine = row.originalLine;
        final modifiedLine = row.modifiedLine;
        if (originalLine == null || modifiedLine == null) {
          return fallback(GitDiffProjectionFallbackReason.sourceMapping);
        }
        addInlineRow(
            modifiedLine.rowIndex,
            GitDiffProjectionInlineRow(
              line: GitDiffPatchLine(
                rowIndex: modifiedLine.rowIndex,
                kind: GitDiffPatchLineKind.context,
                text: modifiedLine.text,
                originalLineNumber: originalLine.originalLineNumber,
                modifiedLineNumber: modifiedLine.modifiedLineNumber,
              ),
            ));
      case GitDiffProjectionRowKind.changed:
        final originalLine = row.originalLine;
        final modifiedLine = row.modifiedLine;
        if (originalLine == null || modifiedLine == null) {
          return fallback(GitDiffProjectionFallbackReason.sourceMapping);
        }
        addInlineRow(
            originalLine.rowIndex,
            GitDiffProjectionInlineRow(
              line: originalLine,
              wordChanges: row.originalWordChanges,
            ));
        addInlineRow(
            modifiedLine.rowIndex,
            GitDiffProjectionInlineRow(
              line: modifiedLine,
              wordChanges: row.modifiedWordChanges,
            ));
      case GitDiffProjectionRowKind.inserted:
        final line = row.modifiedLine;
        if (line == null) {
          return fallback(GitDiffProjectionFallbackReason.sourceMapping);
        }
        addInlineRow(line.rowIndex, GitDiffProjectionInlineRow(line: line));
      case GitDiffProjectionRowKind.deleted:
        final line = row.originalLine;
        if (line == null) {
          return fallback(GitDiffProjectionFallbackReason.sourceMapping);
        }
        addInlineRow(line.rowIndex, GitDiffProjectionInlineRow(line: line));
    }
  }
  orderedInlineRows.sort((first, second) {
    final sourceOrder = first.sourceRowIndex.compareTo(second.sourceRowIndex);
    return sourceOrder != 0 ? sourceOrder : first.order.compareTo(second.order);
  });
  final inlineRows = <GitDiffProjectionInlineRow>[];
  for (final orderedRow in orderedInlineRows) {
    inlineIndexBySourceRow[orderedRow.sourceRowIndex] = inlineRows.length;
    inlineRows.add(orderedRow.row);
  }
  if (inlineRows.length > options.maxRows) {
    return fallback(GitDiffProjectionFallbackReason.rowLimit);
  }

  final changes = _changes(rows, inlineIndexBySourceRow);
  return GitDiffProjectionResult._(
    rows: List.unmodifiable(rows),
    inlineRows: List.unmodifiable(inlineRows),
    changes: List.unmodifiable(changes),
  );
}

List<GitDiffProjectionChange> _changes(
  List<GitDiffProjectionRow> rows,
  Map<int, int> inlineIndexBySourceRow,
) {
  final changes = <GitDiffProjectionChange>[];
  int? firstRowIndex;
  int? inlineRowIndex;
  int? sideBySideRowIndex;
  int? originalLineNumber;
  int? modifiedLineNumber;

  void finish() {
    final sourceRowIndex = firstRowIndex;
    if (sourceRowIndex != null) {
      changes.add(GitDiffProjectionChange(
        firstRowIndex: sourceRowIndex,
        inlineRowIndex: inlineRowIndex!,
        sideBySideRowIndex: sideBySideRowIndex!,
        originalLineNumber: originalLineNumber,
        modifiedLineNumber: modifiedLineNumber,
      ));
    }
    firstRowIndex = null;
    inlineRowIndex = null;
    sideBySideRowIndex = null;
    originalLineNumber = null;
    modifiedLineNumber = null;
  }

  for (final row in rows) {
    switch (row.kind) {
      case GitDiffProjectionRowKind.changed:
      case GitDiffProjectionRowKind.inserted:
      case GitDiffProjectionRowKind.deleted:
        if (firstRowIndex == null) {
          final sourceLine = row.originalLine ?? row.modifiedLine!;
          firstRowIndex = sourceLine.rowIndex;
          inlineRowIndex = inlineIndexBySourceRow[sourceLine.rowIndex];
          sideBySideRowIndex = row.rowIndex;
          originalLineNumber = row.originalLine?.originalLineNumber;
          modifiedLineNumber = row.modifiedLine?.modifiedLineNumber;
        }
      case GitDiffProjectionRowKind.marker:
        // A marker stays attached to the surrounding change block.
        break;
      case GitDiffProjectionRowKind.metadata:
      case GitDiffProjectionRowKind.hunk:
      case GitDiffProjectionRowKind.context:
        finish();
    }
  }
  finish();
  return changes;
}

List<_PatchSegment>? _segments(List<GitDiffPatchLine> lines) {
  final segments = <_PatchSegment>[];
  var index = 0;
  while (index < lines.length) {
    final line = lines[index];
    if (line.kind != GitDiffPatchLineKind.hunk) {
      if (line.kind != GitDiffPatchLineKind.metadata &&
          line.kind != GitDiffPatchLineKind.marker) {
        return null;
      }
      segments.add(_PatchSegment.fullWidth(line));
      index++;
      continue;
    }

    final header = line;
    index++;
    final body = <GitDiffPatchLine>[];
    while (index < lines.length &&
        lines[index].kind != GitDiffPatchLineKind.hunk &&
        lines[index].kind != GitDiffPatchLineKind.metadata) {
      body.add(lines[index]);
      index++;
    }
    final hunk = _PatchHunk.create(header, body);
    if (hunk == null) return null;
    segments.add(_PatchSegment.hunk(hunk));
  }
  return segments;
}

class _PatchSegment {
  const _PatchSegment.fullWidth(this.fullWidthLine) : hunk = null;
  const _PatchSegment.hunk(this.hunk) : fullWidthLine = null;

  final GitDiffPatchLine? fullWidthLine;
  final _PatchHunk? hunk;
}

class _PatchHunk {
  _PatchHunk._({
    required this.header,
    required this.originalLines,
    required this.modifiedLines,
    required this.markers,
  })  : originalText = originalLines.map((line) => line.text).join('\n'),
        modifiedText = modifiedLines.map((line) => line.text).join('\n');

  final GitDiffPatchLine header;
  final List<GitDiffPatchLine> originalLines;
  final List<GitDiffPatchLine> modifiedLines;
  final List<_MarkerAnchor> markers;
  final String originalText;
  final String modifiedText;

  int get modelInputCodeUnits => originalText.length + modifiedText.length;

  static _PatchHunk? create(
    GitDiffPatchLine header,
    List<GitDiffPatchLine> body,
  ) {
    final originalLines = <GitDiffPatchLine>[];
    final modifiedLines = <GitDiffPatchLine>[];
    final markers = <_MarkerAnchor>[];
    GitDiffPatchLine? previousSourceLine;
    for (final line in body) {
      switch (line.kind) {
        case GitDiffPatchLineKind.context:
          originalLines.add(line);
          modifiedLines.add(line);
          previousSourceLine = line;
        case GitDiffPatchLineKind.removed:
          originalLines.add(line);
          previousSourceLine = line;
        case GitDiffPatchLineKind.added:
          modifiedLines.add(line);
          previousSourceLine = line;
        case GitDiffPatchLineKind.marker:
          if (previousSourceLine == null) return null;
          markers.add(_MarkerAnchor(
            line: line,
            originalSourceRowIndex:
                previousSourceLine.kind == GitDiffPatchLineKind.added
                    ? null
                    : previousSourceLine.rowIndex,
            modifiedSourceRowIndex:
                previousSourceLine.kind == GitDiffPatchLineKind.removed
                    ? null
                    : previousSourceLine.rowIndex,
          ));
        case GitDiffPatchLineKind.metadata:
        case GitDiffPatchLineKind.hunk:
          return null;
      }
    }
    return _PatchHunk._(
      header: header,
      originalLines: List.unmodifiable(originalLines),
      modifiedLines: List.unmodifiable(modifiedLines),
      markers: List.unmodifiable(markers),
    );
  }
}

class _MarkerAnchor {
  const _MarkerAnchor({
    required this.line,
    required this.originalSourceRowIndex,
    required this.modifiedSourceRowIndex,
  });

  final GitDiffPatchLine line;
  final int? originalSourceRowIndex;
  final int? modifiedSourceRowIndex;
}

class _PendingProjectionRow {
  const _PendingProjectionRow({
    required this.kind,
    this.originalLine,
    this.modifiedLine,
    this.fullWidthLine,
    this.originalWordChanges = const [],
    this.modifiedWordChanges = const [],
    this.trimWhitespaceEquivalent = false,
  });

  final GitDiffProjectionRowKind kind;
  final GitDiffPatchLine? originalLine;
  final GitDiffPatchLine? modifiedLine;
  final GitDiffPatchLine? fullWidthLine;
  final List<GitDiffWordRange> originalWordChanges;
  final List<GitDiffWordRange> modifiedWordChanges;
  final bool trimWhitespaceEquivalent;

  GitDiffProjectionRow toRow(int rowIndex) => GitDiffProjectionRow(
        rowIndex: rowIndex,
        kind: kind,
        originalLine: originalLine,
        modifiedLine: modifiedLine,
        fullWidthLine: fullWidthLine,
        originalWordChanges: List.unmodifiable(originalWordChanges),
        modifiedWordChanges: List.unmodifiable(modifiedWordChanges),
        trimWhitespaceEquivalent: trimWhitespaceEquivalent,
      );
}

class _OrderedInlineRow {
  const _OrderedInlineRow({
    required this.sourceRowIndex,
    required this.order,
    required this.row,
  });

  final int sourceRowIndex;
  final int order;
  final GitDiffProjectionInlineRow row;
}

GitDiffPatchLine _displayLine(
  GitDiffPatchLine source, {
  required GitDiffPatchLineKind kind,
  required String text,
}) =>
    GitDiffPatchLine(
      rowIndex: source.rowIndex,
      kind: kind,
      text: text,
      originalLineNumber: source.originalLineNumber,
      modifiedLineNumber: source.modifiedLineNumber,
    );

GitDiffPatchLine? _lineAt(List<GitDiffPatchLine> lines, int? lineNumber) {
  if (lineNumber == null || lineNumber <= 0 || lineNumber > lines.length) {
    return null;
  }
  return lines[lineNumber - 1];
}

List<GitDiffWordRange> _wordRanges(
  List<WordDiffHunk> hunks, {
  required bool original,
}) =>
    List.unmodifiable([
      for (final hunk in hunks)
        if ((original
            ? hunk.originalEndUtf16 > hunk.originalStartUtf16
            : hunk.modifiedEndUtf16 > hunk.modifiedStartUtf16))
          GitDiffWordRange(
            startUtf16:
                original ? hunk.originalStartUtf16 : hunk.modifiedStartUtf16,
            endUtf16: original ? hunk.originalEndUtf16 : hunk.modifiedEndUtf16,
          ),
    ]);

List<int> _divideBudget(int total, int parts) {
  if (parts == 0) return const [];
  final quotient = total ~/ parts;
  final remainder = total % parts;
  return List.unmodifiable([
    for (var index = 0; index < parts; index++)
      quotient + (index < remainder ? 1 : 0),
  ]);
}

int _max(int first, int second) => first > second ? first : second;
