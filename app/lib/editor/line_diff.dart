/// Bounded line-diff model for the editor's text comparison view.
///
/// Ranges are 1-based line numbers with an exclusive end, matching VS Code's
/// `LineRange` contract. An insertion/deletion has an empty range on one side.
/// This module computes line alignment only; it does not produce word ranges
/// or render a diff view.
library;

enum LineDiffFallbackReason { inputLimit, workLimit }

class LineDiffOptions {
  const LineDiffOptions({
    this.ignoreTrimWhitespace = true,
    this.maxInputCodeUnits = 2000000,
    this.maxLinesPerSide = 8192,
    this.maxTraceCells = 2000000,
    this.maxWork = 4000000,
  });

  /// Like `diffEditor.ignoreTrimWhitespace`, ignore leading/trailing
  /// whitespace when aligning lines. Internal whitespace remains significant.
  final bool ignoreTrimWhitespace;

  /// Bounds splitting/copying the compared texts before line arrays are made.
  final int maxInputCodeUnits;

  /// Bounds per-document line arrays.
  final int maxLinesPerSide;

  /// Bounds copied Myers frontier history (frontier slots, not bytes).
  final int maxTraceCells;

  /// Bounds frontier and equality work for pathological high-distance inputs.
  final int maxWork;
}

class LineDiffHunk {
  const LineDiffHunk({
    required this.originalStartLine,
    required this.originalEndLineExclusive,
    required this.modifiedStartLine,
    required this.modifiedEndLineExclusive,
  });

  final int originalStartLine;
  final int originalEndLineExclusive;
  final int modifiedStartLine;
  final int modifiedEndLineExclusive;

  int get originalLineCount => originalEndLineExclusive - originalStartLine;

  int get modifiedLineCount => modifiedEndLineExclusive - modifiedStartLine;

  @override
  bool operator ==(Object other) =>
      other is LineDiffHunk &&
      originalStartLine == other.originalStartLine &&
      originalEndLineExclusive == other.originalEndLineExclusive &&
      modifiedStartLine == other.modifiedStartLine &&
      modifiedEndLineExclusive == other.modifiedEndLineExclusive;

  @override
  int get hashCode => Object.hash(originalStartLine, originalEndLineExclusive,
      modifiedStartLine, modifiedEndLineExclusive);

  @override
  String toString() =>
      'LineDiffHunk(original: [$originalStartLine, $originalEndLineExclusive), '
      'modified: [$modifiedStartLine, $modifiedEndLineExclusive))';
}

class LineDiffResult {
  LineDiffResult._({
    required this.hunks,
    required this.originalLineCount,
    required this.modifiedLineCount,
    this.fallbackReason,
  });

  final List<LineDiffHunk> hunks;
  final int originalLineCount;
  final int modifiedLineCount;
  final LineDiffFallbackReason? fallbackReason;

  bool get isApproximate => fallbackReason != null;
}

/// Computes changed line ranges using a Myers shortest-edit-path alignment.
///
/// The default whitespace and line-diff strategy follows the pinned Code-OSS
/// `DefaultLinesDiffComputer`: trimmed lines are used for line alignment, then
/// refinements can be added by a later slice. When any configured input/work
/// bound is reached, this returns one whole-document hunk with an explicit
/// [LineDiffFallbackReason] instead of allocating without bound or stalling.
LineDiffResult computeLineDiff(
  String originalText,
  String modifiedText, {
  LineDiffOptions options = const LineDiffOptions(),
}) {
  final originalLineCount = _countLines(originalText);
  final modifiedLineCount = _countLines(modifiedText);
  if (originalText == modifiedText) {
    return LineDiffResult._(
      hunks: const [],
      originalLineCount: originalLineCount,
      modifiedLineCount: modifiedLineCount,
    );
  }

  if (originalText.length + modifiedText.length > options.maxInputCodeUnits ||
      originalLineCount > options.maxLinesPerSide ||
      modifiedLineCount > options.maxLinesPerSide) {
    return _wholeDocumentFallback(
      originalLineCount,
      modifiedLineCount,
      LineDiffFallbackReason.inputLimit,
    );
  }

  final originalLines = originalText.split('\n');
  final modifiedLines = modifiedText.split('\n');
  final originalKeys = _alignmentKeys(originalLines, options);
  final modifiedKeys = _alignmentKeys(modifiedLines, options);
  final operations = _myersOperations(
    originalKeys,
    modifiedKeys,
    maxTraceCells: options.maxTraceCells,
    maxWork: options.maxWork,
  );
  if (operations == null) {
    return _wholeDocumentFallback(
      originalLineCount,
      modifiedLineCount,
      LineDiffFallbackReason.workLimit,
    );
  }

  return LineDiffResult._(
    hunks: List.unmodifiable(_operationsToHunks(operations)),
    originalLineCount: originalLineCount,
    modifiedLineCount: modifiedLineCount,
  );
}

int _countLines(String text) {
  var lines = 1;
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x0A) lines++;
  }
  return lines;
}

List<String> _alignmentKeys(List<String> lines, LineDiffOptions options) =>
    options.ignoreTrimWhitespace
        ? lines.map((line) => line.trim()).toList(growable: false)
        : lines;

LineDiffResult _wholeDocumentFallback(
  int originalLineCount,
  int modifiedLineCount,
  LineDiffFallbackReason reason,
) {
  return LineDiffResult._(
    hunks: List.unmodifiable([
      LineDiffHunk(
        originalStartLine: 1,
        originalEndLineExclusive: originalLineCount + 1,
        modifiedStartLine: 1,
        modifiedEndLineExclusive: modifiedLineCount + 1,
      ),
    ]),
    originalLineCount: originalLineCount,
    modifiedLineCount: modifiedLineCount,
    fallbackReason: reason,
  );
}

enum _LineEdit { equal, delete, insert }

/// Returns null when the deterministic memory/work budgets are exhausted.
List<_LineEdit>? _myersOperations(
  List<String> original,
  List<String> modified, {
  required int maxTraceCells,
  required int maxWork,
}) {
  final n = original.length;
  final m = modified.length;
  final maxDistance = n + m;
  final offset = maxDistance + 1;
  final frontier = List<int>.filled((maxDistance * 2) + 3, 0);
  final trace = <List<int>>[];
  var traceCells = 0;
  var work = 0;
  var reachedEnd = false;

  for (var distance = 0; distance <= maxDistance; distance++) {
    if (traceCells + frontier.length > maxTraceCells) return null;
    trace.add(List<int>.of(frontier, growable: false));
    traceCells += frontier.length;

    for (var diagonal = -distance; diagonal <= distance; diagonal += 2) {
      if (++work > maxWork) return null;
      final index = offset + diagonal;
      var x = diagonal == -distance ||
              (diagonal != distance &&
                  frontier[index - 1] < frontier[index + 1])
          ? frontier[index + 1]
          : frontier[index - 1] + 1;
      var y = x - diagonal;
      while (x < n && y < m) {
        if (++work > maxWork) return null;
        if (original[x] != modified[y]) break;
        x++;
        y++;
      }
      frontier[index] = x;
      if (x >= n && y >= m) {
        reachedEnd = true;
        break;
      }
    }

    if (reachedEnd) {
      return _backtrack(trace, n, m, offset);
    }
  }
  return null;
}

List<_LineEdit> _backtrack(
  List<List<int>> trace,
  int originalLength,
  int modifiedLength,
  int offset,
) {
  var x = originalLength;
  var y = modifiedLength;
  final reversed = <_LineEdit>[];

  for (var distance = trace.length - 1; distance >= 0; distance--) {
    final frontier = trace[distance];
    final diagonal = x - y;
    final previousDiagonal = diagonal == -distance ||
            (diagonal != distance &&
                frontier[offset + diagonal - 1] <
                    frontier[offset + diagonal + 1])
        ? diagonal + 1
        : diagonal - 1;
    final previousX = frontier[offset + previousDiagonal];
    final previousY = previousX - previousDiagonal;

    while (x > previousX && y > previousY) {
      reversed.add(_LineEdit.equal);
      x--;
      y--;
    }
    if (distance == 0) break;

    if (x == previousX) {
      reversed.add(_LineEdit.insert);
      y--;
    } else {
      reversed.add(_LineEdit.delete);
      x--;
    }
  }

  while (x > 0 && y > 0) {
    reversed.add(_LineEdit.equal);
    x--;
    y--;
  }
  while (x > 0) {
    reversed.add(_LineEdit.delete);
    x--;
  }
  while (y > 0) {
    reversed.add(_LineEdit.insert);
    y--;
  }
  return reversed.reversed.toList(growable: false);
}

List<LineDiffHunk> _operationsToHunks(List<_LineEdit> operations) {
  final hunks = <LineDiffHunk>[];
  var originalLine = 0;
  var modifiedLine = 0;
  int? hunkOriginalStart;
  int? hunkModifiedStart;

  void finishHunk() {
    final originalStart = hunkOriginalStart;
    final modifiedStart = hunkModifiedStart;
    if (originalStart == null || modifiedStart == null) return;
    hunks.add(
      LineDiffHunk(
        originalStartLine: originalStart + 1,
        originalEndLineExclusive: originalLine + 1,
        modifiedStartLine: modifiedStart + 1,
        modifiedEndLineExclusive: modifiedLine + 1,
      ),
    );
    hunkOriginalStart = null;
    hunkModifiedStart = null;
  }

  for (final operation in operations) {
    if (operation == _LineEdit.equal) {
      finishHunk();
      originalLine++;
      modifiedLine++;
      continue;
    }
    hunkOriginalStart ??= originalLine;
    hunkModifiedStart ??= modifiedLine;
    if (operation == _LineEdit.delete) {
      originalLine++;
    } else {
      modifiedLine++;
    }
  }
  finishHunk();
  return hunks;
}
