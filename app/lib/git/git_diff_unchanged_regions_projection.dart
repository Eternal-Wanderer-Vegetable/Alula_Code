import 'git_diff_patch.dart';
import 'git_diff_whitespace_projection.dart';

enum GitDiffUnchangedRegionsFallbackReason {
  unsupportedPatch,
  rowLimit,
  sourceMapping,
}

class GitDiffUnchangedRegionsOptions {
  const GitDiffUnchangedRegionsOptions({
    this.contextLineCount = 3,
    this.minimumHiddenLineCount = 3,
    this.revealLineCount = 20,
    this.maxRows = 16384,
  })  : assert(contextLineCount >= 0),
        assert(minimumHiddenLineCount > 0),
        assert(revealLineCount > 0),
        assert(maxRows > 0);

  final int contextLineCount;
  final int minimumHiddenLineCount;
  final int revealLineCount;
  final int maxRows;
}

class GitDiffInlineDisplayRow {
  const GitDiffInlineDisplayRow.line(this.inlineRow)
      : unchangedRegionStartSourceRowIndex = null,
        hiddenLineCount = 0,
        totalHiddenLineCount = 0;

  const GitDiffInlineDisplayRow.collapsed({
    required this.unchangedRegionStartSourceRowIndex,
    required this.hiddenLineCount,
    required this.totalHiddenLineCount,
  }) : inlineRow = null;

  final GitDiffProjectionInlineRow? inlineRow;
  final int? unchangedRegionStartSourceRowIndex;

  /// Number of source context rows still hidden after any partial reveals.
  final int hiddenLineCount;

  /// Initial number of hidden rows in this unchanged region.
  final int totalHiddenLineCount;

  bool get isCollapsedRegion => inlineRow == null;
}

class GitDiffUnchangedRegionsProjectionResult {
  const GitDiffUnchangedRegionsProjectionResult._({
    required this.rows,
    required this.visibleInlineRowBySourceRow,
    required this.regionStartSourceRowIndices,
    this.fallbackReason,
  });

  final List<GitDiffInlineDisplayRow> rows;
  final Map<int, int> visibleInlineRowBySourceRow;
  final List<int> regionStartSourceRowIndices;
  final GitDiffUnchangedRegionsFallbackReason? fallbackReason;

  bool get canRender => fallbackReason == null;
}

/// Folds only source-mapped context rows between two changes in the same hunk.
///
/// The input [projection] remains authoritative for visible rows. If its
/// source-row mapping is incomplete, duplicated, reordered, or inconsistent,
/// this returns the original inline rows without folding any region.
GitDiffUnchangedRegionsProjectionResult projectGitDiffInlineUnchangedRegions(
  GitDiffPatchResult patch,
  GitDiffProjectionResult projection, {
  Map<int, int> revealedLineCountByRegionStart = const {},
  GitDiffUnchangedRegionsOptions options =
      const GitDiffUnchangedRegionsOptions(),
}) {
  GitDiffUnchangedRegionsProjectionResult fallback(
    GitDiffUnchangedRegionsFallbackReason reason,
  ) =>
      GitDiffUnchangedRegionsProjectionResult._(
        rows: List.unmodifiable([
          for (final row in projection.inlineRows)
            GitDiffInlineDisplayRow.line(row),
        ]),
        visibleInlineRowBySourceRow: const {},
        regionStartSourceRowIndices: const [],
        fallbackReason: reason,
      );

  if (!patch.canRender || !projection.canRender) {
    return fallback(
      GitDiffUnchangedRegionsFallbackReason.unsupportedPatch,
    );
  }
  if (patch.lines.length > options.maxRows ||
      projection.inlineRows.length > options.maxRows) {
    return fallback(GitDiffUnchangedRegionsFallbackReason.rowLimit);
  }

  final inlineIndexBySourceRow = <int, int>{};
  var previousSourceRow = -1;
  for (var inlineIndex = 0;
      inlineIndex < projection.inlineRows.length;
      inlineIndex++) {
    final displayLine = projection.inlineRows[inlineIndex].line;
    final sourceRow = displayLine.rowIndex;
    if (sourceRow <= previousSourceRow ||
        sourceRow < 0 ||
        sourceRow >= patch.lines.length ||
        inlineIndexBySourceRow.containsKey(sourceRow)) {
      return fallback(
        GitDiffUnchangedRegionsFallbackReason.sourceMapping,
      );
    }
    final sourceLine = patch.lines[sourceRow];
    if (sourceLine.rowIndex != sourceRow ||
        sourceLine.text != displayLine.text ||
        !_isCompatibleSourceKind(sourceLine.kind, displayLine.kind)) {
      return fallback(
        GitDiffUnchangedRegionsFallbackReason.sourceMapping,
      );
    }
    inlineIndexBySourceRow[sourceRow] = inlineIndex;
    previousSourceRow = sourceRow;
  }

  for (final sourceLine in patch.lines) {
    if (sourceLine.kind != GitDiffPatchLineKind.context) continue;
    final inlineIndex = inlineIndexBySourceRow[sourceLine.rowIndex];
    if (inlineIndex == null) {
      return fallback(
        GitDiffUnchangedRegionsFallbackReason.sourceMapping,
      );
    }
    final displayLine = projection.inlineRows[inlineIndex].line;
    if (displayLine.kind != GitDiffPatchLineKind.context ||
        displayLine.text != sourceLine.text) {
      return fallback(
        GitDiffUnchangedRegionsFallbackReason.sourceMapping,
      );
    }
  }

  final regions = _findUnchangedRegions(
    patch.lines,
    projection.inlineRows,
    inlineIndexBySourceRow,
    options,
  );
  if (regions == null) {
    return fallback(GitDiffUnchangedRegionsFallbackReason.sourceMapping);
  }

  final regionByInlineStart = <int, _UnchangedRegion>{
    for (final region in regions) region.inlineStartIndex: region,
  };
  final displayRows = <GitDiffInlineDisplayRow>[];
  final visibleRows = <int, int>{};
  var inlineIndex = 0;
  while (inlineIndex < projection.inlineRows.length) {
    final region = regionByInlineStart[inlineIndex];
    if (region == null) {
      final sourceRowIndex = projection.inlineRows[inlineIndex].line.rowIndex;
      visibleRows[sourceRowIndex] = displayRows.length;
      displayRows.add(
        GitDiffInlineDisplayRow.line(projection.inlineRows[inlineIndex]),
      );
      inlineIndex++;
      continue;
    }

    final revealedCount =
        (revealedLineCountByRegionStart[region.startSourceRowIndex] ?? 0)
            .clamp(0, region.rows.length)
            .toInt();
    for (var offset = 0; offset < revealedCount; offset++) {
      final row = region.rows[offset];
      visibleRows[row.line.rowIndex] = displayRows.length;
      displayRows.add(GitDiffInlineDisplayRow.line(row));
    }
    final hiddenCount = region.rows.length - revealedCount;
    if (hiddenCount > 0) {
      displayRows.add(GitDiffInlineDisplayRow.collapsed(
        unchangedRegionStartSourceRowIndex: region.startSourceRowIndex,
        hiddenLineCount: hiddenCount,
        totalHiddenLineCount: region.rows.length,
      ));
    }
    inlineIndex += region.rows.length;
  }

  return GitDiffUnchangedRegionsProjectionResult._(
    rows: List.unmodifiable(displayRows),
    visibleInlineRowBySourceRow: Map.unmodifiable(visibleRows),
    regionStartSourceRowIndices: List.unmodifiable([
      for (final region in regions) region.startSourceRowIndex,
    ]),
  );
}

List<_UnchangedRegion>? _findUnchangedRegions(
  List<GitDiffPatchLine> sourceLines,
  List<GitDiffProjectionInlineRow> inlineRows,
  Map<int, int> inlineIndexBySourceRow,
  GitDiffUnchangedRegionsOptions options,
) {
  final regions = <_UnchangedRegion>[];
  var cursor = 0;
  final requiredContextLength =
      options.contextLineCount * 2 + options.minimumHiddenLineCount;

  while (cursor < sourceLines.length) {
    if (sourceLines[cursor].kind != GitDiffPatchLineKind.hunk) {
      cursor++;
      continue;
    }

    final bodyStart = cursor + 1;
    var bodyEnd = bodyStart;
    while (bodyEnd < sourceLines.length &&
        sourceLines[bodyEnd].kind != GitDiffPatchLineKind.hunk &&
        sourceLines[bodyEnd].kind != GitDiffPatchLineKind.metadata) {
      bodyEnd++;
    }

    var rowIndex = bodyStart;
    while (rowIndex < bodyEnd) {
      if (sourceLines[rowIndex].kind != GitDiffPatchLineKind.context) {
        rowIndex++;
        continue;
      }
      final contextStart = rowIndex;
      while (rowIndex < bodyEnd &&
          sourceLines[rowIndex].kind == GitDiffPatchLineKind.context) {
        rowIndex++;
      }
      final contextEnd = rowIndex;
      final contextCount = contextEnd - contextStart;
      if (contextCount < requiredContextLength ||
          !_hasAdjacentChange(
            sourceLines,
            contextStart - 1,
            bodyStart,
            bodyEnd,
            -1,
          ) ||
          !_hasAdjacentChange(
            sourceLines,
            contextEnd,
            bodyStart,
            bodyEnd,
            1,
          )) {
        continue;
      }

      final hiddenStart = contextStart + options.contextLineCount;
      final hiddenEnd = contextEnd - options.contextLineCount;
      final hiddenRows = <GitDiffProjectionInlineRow>[];
      var expectedInlineStart = -1;
      for (var sourceIndex = hiddenStart;
          sourceIndex < hiddenEnd;
          sourceIndex++) {
        final inlineIndex = inlineIndexBySourceRow[sourceIndex];
        if (inlineIndex == null) return null;
        if (expectedInlineStart < 0) expectedInlineStart = inlineIndex;
        if (inlineIndex != expectedInlineStart + hiddenRows.length) return null;
        final row = inlineRows[inlineIndex];
        if (row.line.rowIndex != sourceIndex ||
            row.line.kind != GitDiffPatchLineKind.context ||
            row.line.text != sourceLines[sourceIndex].text) {
          return null;
        }
        hiddenRows.add(row);
      }
      if (hiddenRows.length < options.minimumHiddenLineCount) return null;
      regions.add(_UnchangedRegion(
        startSourceRowIndex: hiddenStart,
        inlineStartIndex: expectedInlineStart,
        rows: List.unmodifiable(hiddenRows),
      ));
    }

    cursor = bodyEnd;
  }
  return regions;
}

bool _hasAdjacentChange(
  List<GitDiffPatchLine> lines,
  int index,
  int start,
  int end,
  int direction,
) {
  while (index >= start &&
      index < end &&
      lines[index].kind == GitDiffPatchLineKind.marker) {
    index += direction;
  }
  if (index < start || index >= end) return false;
  return lines[index].kind == GitDiffPatchLineKind.added ||
      lines[index].kind == GitDiffPatchLineKind.removed;
}

bool _isCompatibleSourceKind(
  GitDiffPatchLineKind source,
  GitDiffPatchLineKind display,
) {
  if (source == display) return true;
  return (source == GitDiffPatchLineKind.added ||
          source == GitDiffPatchLineKind.removed) &&
      display == GitDiffPatchLineKind.context;
}

class _UnchangedRegion {
  const _UnchangedRegion({
    required this.startSourceRowIndex,
    required this.inlineStartIndex,
    required this.rows,
  });

  final int startSourceRowIndex;
  final int inlineStartIndex;
  final List<GitDiffProjectionInlineRow> rows;
}
