import 'diff_view_model.dart';

/// One line hunk projected to absolute UTF-16 ranges on both diff sides.
class DiffRevertRange {
  const DiffRevertRange({
    required this.hunkIndex,
    required this.originalStartUtf16,
    required this.originalEndUtf16,
    required this.modifiedStartUtf16,
    required this.modifiedEndUtf16,
  });

  final int hunkIndex;
  final int originalStartUtf16;
  final int originalEndUtf16;
  final int modifiedStartUtf16;
  final int modifiedEndUtf16;
}

/// Returns one toolbar row for each exact changed hunk.
Map<int, int> diffRevertToolbarRows(DiffViewModelResult diff) {
  if (diff.isApproximate) return const {};
  final rows = <int, int>{};
  for (var hunkIndex = 0; hunkIndex < diff.lineDiff.hunks.length; hunkIndex++) {
    final hunk = diff.lineDiff.hunks[hunkIndex];
    for (final row in diff.rows) {
      final originalLine = row.originalLineNumber;
      final modifiedLine = row.modifiedLineNumber;
      final isHunkRow = (originalLine != null &&
              originalLine >= hunk.originalStartLine &&
              originalLine < hunk.originalEndLineExclusive) ||
          (modifiedLine != null &&
              modifiedLine >= hunk.modifiedStartLine &&
              modifiedLine < hunk.modifiedEndLineExclusive);
      if (isHunkRow) {
        rows[row.rowIndex] = hunkIndex;
        break;
      }
    }
  }
  return Map.unmodifiable(rows);
}

/// Converts selected exact line hunks into original/modified UTF-16 ranges.
///
/// An invalid hunk or approximate diff rejects the entire request. The caller
/// can then submit all returned edits in one version-checked Rust transaction.
List<DiffRevertRange> diffRevertRanges(
  DiffViewModelResult diff,
  Iterable<int> hunkIndices,
) {
  if (diff.isApproximate) return const [];
  final indices = hunkIndices.toSet().toList()..sort();
  if (indices.isEmpty ||
      indices.any((i) => i < 0 || i >= diff.lineDiff.hunks.length)) {
    return const [];
  }

  final ranges = <DiffRevertRange>[];
  var previousOriginalEnd = -1;
  var previousModifiedEnd = -1;
  for (final hunkIndex in indices) {
    final hunk = diff.lineDiff.hunks[hunkIndex];
    final originalStart =
        _lineOffset(diff.originalText, hunk.originalStartLine);
    final originalEnd =
        _lineOffset(diff.originalText, hunk.originalEndLineExclusive);
    final modifiedStart =
        _lineOffset(diff.modifiedText, hunk.modifiedStartLine);
    final modifiedEnd =
        _lineOffset(diff.modifiedText, hunk.modifiedEndLineExclusive);
    if (originalStart > originalEnd ||
        modifiedStart > modifiedEnd ||
        originalEnd > diff.originalText.length ||
        modifiedEnd > diff.modifiedText.length ||
        (previousOriginalEnd >= 0 && originalStart < previousOriginalEnd) ||
        (previousModifiedEnd >= 0 && modifiedStart < previousModifiedEnd)) {
      return const [];
    }
    previousOriginalEnd = originalEnd;
    previousModifiedEnd = modifiedEnd;

    ranges.add(DiffRevertRange(
      hunkIndex: hunkIndex,
      originalStartUtf16: originalStart,
      originalEndUtf16: originalEnd,
      modifiedStartUtf16: modifiedStart,
      modifiedEndUtf16: modifiedEnd,
    ));
  }
  return List.unmodifiable(ranges);
}

/// Finds changed line hunks intersecting a modified-side UTF-16 selection.
/// A collapsed selection represents the caret's logical line.
List<int> diffHunksIntersectingModifiedSelection(
  DiffViewModelResult diff, {
  required int selectionStartUtf16,
  required int selectionEndUtf16,
}) {
  if (diff.isApproximate) return const [];
  final text = diff.modifiedText;
  final start = selectionStartUtf16.clamp(0, text.length).toInt();
  final end = selectionEndUtf16.clamp(0, text.length).toInt();
  final lower = start < end ? start : end;
  final upper = start < end ? end : start;
  final startLine = _lineAtOffset(text, lower);
  final endLineExclusive = lower == upper
      ? startLine + 1
      : _isLineStart(text, upper)
          ? _lineAtOffset(text, upper)
          : _lineAtOffset(text, upper) + 1;

  final matches = <int>[];
  for (var i = 0; i < diff.lineDiff.hunks.length; i++) {
    final hunk = diff.lineDiff.hunks[i];
    final overlaps = hunk.modifiedLineCount == 0
        ? hunk.modifiedStartLine >= startLine &&
            hunk.modifiedStartLine < endLineExclusive
        : hunk.modifiedStartLine < endLineExclusive &&
            hunk.modifiedEndLineExclusive > startLine;
    if (overlaps) matches.add(i);
  }
  return List.unmodifiable(matches);
}

int _lineOffset(String text, int oneBasedLine) {
  if (oneBasedLine <= 1) return 0;
  var line = 1;
  for (var offset = 0; offset < text.length; offset++) {
    if (text.codeUnitAt(offset) == 0x0A) {
      line++;
      if (line == oneBasedLine) return offset + 1;
    }
  }
  return text.length;
}

int _lineAtOffset(String text, int offset) {
  var line = 1;
  for (var i = 0; i < offset; i++) {
    if (text.codeUnitAt(i) == 0x0A) line++;
  }
  return line;
}

bool _isLineStart(String text, int offset) =>
    offset == 0 || text.codeUnitAt(offset - 1) == 0x0A;
