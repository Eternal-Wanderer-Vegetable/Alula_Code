/// Bounded UTF-16 character diff ranges with Code-OSS-style word expansion.
///
/// This module returns text offsets only. It does not compute line alignment
/// or render an inline/side-by-side diff view.
library;

enum WordDiffFallbackReason { inputLimit, workLimit, alignmentInvariant }

class WordDiffOptions {
  const WordDiffOptions({
    this.maxInputCodeUnits = 262144,
    this.maxTraceCells = 1000000,
    this.maxWork = 2000000,
  });

  /// Maximum combined UTF-16 code units across both texts.
  final int maxInputCodeUnits;

  /// Maximum copied Myers frontier history cells.
  final int maxTraceCells;

  /// Maximum total bounded-search and word-expansion operations.
  final int maxWork;
}

class WordDiffHunk {
  const WordDiffHunk({
    required this.originalStartUtf16,
    required this.originalEndUtf16,
    required this.modifiedStartUtf16,
    required this.modifiedEndUtf16,
  });

  /// Zero-based, end-exclusive UTF-16 offsets in the original text.
  final int originalStartUtf16;
  final int originalEndUtf16;

  /// Zero-based, end-exclusive UTF-16 offsets in the modified text.
  final int modifiedStartUtf16;
  final int modifiedEndUtf16;

  int get originalLength => originalEndUtf16 - originalStartUtf16;

  int get modifiedLength => modifiedEndUtf16 - modifiedStartUtf16;

  @override
  bool operator ==(Object other) =>
      other is WordDiffHunk &&
      originalStartUtf16 == other.originalStartUtf16 &&
      originalEndUtf16 == other.originalEndUtf16 &&
      modifiedStartUtf16 == other.modifiedStartUtf16 &&
      modifiedEndUtf16 == other.modifiedEndUtf16;

  @override
  int get hashCode => Object.hash(originalStartUtf16, originalEndUtf16,
      modifiedStartUtf16, modifiedEndUtf16);

  @override
  String toString() =>
      'WordDiffHunk(original: [$originalStartUtf16, $originalEndUtf16), '
      'modified: [$modifiedStartUtf16, $modifiedEndUtf16))';
}

class WordDiffResult {
  WordDiffResult._({
    required this.hunks,
    required this.originalCodeUnits,
    required this.modifiedCodeUnits,
    this.fallbackReason,
  });

  final List<WordDiffHunk> hunks;
  final int originalCodeUnits;
  final int modifiedCodeUnits;
  final WordDiffFallbackReason? fallbackReason;

  bool get isApproximate => fallbackReason != null;
}

/// Computes changed character ranges, expanding small edits to whole ASCII
/// words when the remaining equal characters cover less than two thirds of
/// the paired words, matching the pinned Code-OSS default heuristic.
///
/// All offsets are UTF-16 code units. Output ranges are adjusted outward if a
/// boundary would split a surrogate pair. If an input or work budget is
/// exhausted, one explicit whole-text hunk is returned.
WordDiffResult computeWordDiff(
  String originalText,
  String modifiedText, {
  WordDiffOptions options = const WordDiffOptions(),
}) {
  final originalLength = originalText.length;
  final modifiedLength = modifiedText.length;
  if (originalText == modifiedText) {
    return WordDiffResult._(
      hunks: const [],
      originalCodeUnits: originalLength,
      modifiedCodeUnits: modifiedLength,
    );
  }

  if (originalLength + modifiedLength > options.maxInputCodeUnits ||
      options.maxTraceCells < 1 ||
      options.maxWork < 1) {
    return _wholeTextFallback(
      originalLength,
      modifiedLength,
      options.maxInputCodeUnits < 0 ||
              originalLength + modifiedLength > options.maxInputCodeUnits
          ? WordDiffFallbackReason.inputLimit
          : WordDiffFallbackReason.workLimit,
    );
  }

  final original = originalText.codeUnits;
  final modified = modifiedText.codeUnits;
  final search = _myersOperations(
    original,
    modified,
    maxTraceCells: options.maxTraceCells,
    maxWork: options.maxWork,
  );
  if (search == null) {
    return _wholeTextFallback(
      originalLength,
      modifiedLength,
      WordDiffFallbackReason.workLimit,
    );
  }

  // Count the backtracked operation stream and its two linear projections
  // (changed ranges and equal mappings) against the same work budget.
  final postSearchWork = search.work + (search.operations.length * 3);
  if (postSearchWork > options.maxWork) {
    return _wholeTextFallback(
      originalLength,
      modifiedLength,
      WordDiffFallbackReason.workLimit,
    );
  }

  final ranges = _operationsToRanges(search.operations);
  if (ranges.isEmpty) {
    return _wholeTextFallback(
      originalLength,
      modifiedLength,
      WordDiffFallbackReason.alignmentInvariant,
    );
  }
  final expanded = _expandSmallWordChanges(
    original,
    modified,
    search.operations,
    ranges,
    maxWork: options.maxWork - postSearchWork,
  );
  if (expanded == null) {
    return _wholeTextFallback(
      originalLength,
      modifiedLength,
      WordDiffFallbackReason.workLimit,
    );
  }

  final safeRanges = _expandSurrogateBoundaries(
    expanded,
    original,
    modified,
  );
  final alignedRanges = _repairUnequalGaps(safeRanges, original, modified);
  final hunks = alignedRanges.map((range) => range.toHunk()).toList();
  if (!_preservesEqualGaps(original, modified, hunks) ||
      !_hasSafeSurrogateBoundaries(original, modified, hunks)) {
    return _wholeTextFallback(
      originalLength,
      modifiedLength,
      WordDiffFallbackReason.alignmentInvariant,
    );
  }
  return WordDiffResult._(
    hunks: List.unmodifiable(hunks),
    originalCodeUnits: originalLength,
    modifiedCodeUnits: modifiedLength,
  );
}

WordDiffResult _wholeTextFallback(
  int originalLength,
  int modifiedLength,
  WordDiffFallbackReason reason,
) =>
    WordDiffResult._(
      hunks: List.unmodifiable([
        WordDiffHunk(
          originalStartUtf16: 0,
          originalEndUtf16: originalLength,
          modifiedStartUtf16: 0,
          modifiedEndUtf16: modifiedLength,
        ),
      ]),
      originalCodeUnits: originalLength,
      modifiedCodeUnits: modifiedLength,
      fallbackReason: reason,
    );

enum _CharEdit { equal, delete, insert }

class _MyersSearchResult {
  const _MyersSearchResult(this.operations, this.work);

  final List<_CharEdit> operations;
  final int work;
}

class _RangePair {
  const _RangePair(this.originalStart, this.originalEnd, this.modifiedStart,
      this.modifiedEnd);

  final int originalStart;
  final int originalEnd;
  final int modifiedStart;
  final int modifiedEnd;

  int get originalLength => originalEnd - originalStart;

  int get modifiedLength => modifiedEnd - modifiedStart;

  WordDiffHunk toHunk() => WordDiffHunk(
        originalStartUtf16: originalStart,
        originalEndUtf16: originalEnd,
        modifiedStartUtf16: modifiedStart,
        modifiedEndUtf16: modifiedEnd,
      );

  @override
  bool operator ==(Object other) =>
      other is _RangePair &&
      originalStart == other.originalStart &&
      originalEnd == other.originalEnd &&
      modifiedStart == other.modifiedStart &&
      modifiedEnd == other.modifiedEnd;

  @override
  int get hashCode =>
      Object.hash(originalStart, originalEnd, modifiedStart, modifiedEnd);
}

class _EqualMapping {
  const _EqualMapping(this.originalStart, this.originalEnd, this.modifiedStart);

  final int originalStart;
  final int originalEnd;
  final int modifiedStart;

  int get modifiedEnd => modifiedStart + originalEnd - originalStart;
}

class _WordSpan {
  const _WordSpan(this.start, this.end);

  final int start;
  final int end;
}

class _WorkBudget {
  _WorkBudget(this.remaining);

  int remaining;
  bool exceeded = false;

  bool use() {
    if (remaining <= 0) {
      exceeded = true;
      return false;
    }
    remaining--;
    return true;
  }
}

_MyersSearchResult? _myersOperations(
  List<int> original,
  List<int> modified, {
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
    if (traceCells > maxTraceCells - frontier.length) return null;
    trace.add(List<int>.of(frontier, growable: false));
    traceCells += frontier.length;

    for (var diagonal = -distance; diagonal <= distance; diagonal += 2) {
      if (work >= maxWork) return null;
      work++;
      final index = offset + diagonal;
      var x = diagonal == -distance ||
              (diagonal != distance &&
                  frontier[index - 1] < frontier[index + 1])
          ? frontier[index + 1]
          : frontier[index - 1] + 1;
      var y = x - diagonal;
      while (x < n && y < m) {
        if (work >= maxWork) return null;
        work++;
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
      return _MyersSearchResult(
        _backtrack(trace, n, m, offset),
        work,
      );
    }
  }
  return null;
}

List<_CharEdit> _backtrack(
  List<List<int>> trace,
  int originalLength,
  int modifiedLength,
  int offset,
) {
  var x = originalLength;
  var y = modifiedLength;
  final reversed = <_CharEdit>[];

  for (var distance = trace.length - 1; distance >= 0; distance--) {
    if (distance == 0) {
      while (x > 0 && y > 0) {
        reversed.add(_CharEdit.equal);
        x--;
        y--;
      }
      break;
    }
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
      reversed.add(_CharEdit.equal);
      x--;
      y--;
    }
    if (x == previousX) {
      reversed.add(_CharEdit.insert);
      y--;
    } else {
      reversed.add(_CharEdit.delete);
      x--;
    }
  }

  while (x > 0 && y > 0) {
    reversed.add(_CharEdit.equal);
    x--;
    y--;
  }
  while (x > 0) {
    reversed.add(_CharEdit.delete);
    x--;
  }
  while (y > 0) {
    reversed.add(_CharEdit.insert);
    y--;
  }
  return reversed.reversed.toList(growable: false);
}

List<_RangePair> _operationsToRanges(List<_CharEdit> operations) {
  final ranges = <_RangePair>[];
  var originalOffset = 0;
  var modifiedOffset = 0;
  var operationIndex = 0;

  while (operationIndex < operations.length) {
    if (operations[operationIndex] == _CharEdit.equal) {
      while (operationIndex < operations.length &&
          operations[operationIndex] == _CharEdit.equal) {
        originalOffset++;
        modifiedOffset++;
        operationIndex++;
      }
      continue;
    }

    final originalStart = originalOffset;
    final modifiedStart = modifiedOffset;
    while (operationIndex < operations.length &&
        operations[operationIndex] != _CharEdit.equal) {
      if (operations[operationIndex] == _CharEdit.delete) {
        originalOffset++;
      } else {
        modifiedOffset++;
      }
      operationIndex++;
    }
    ranges.add(_RangePair(
      originalStart,
      originalOffset,
      modifiedStart,
      modifiedOffset,
    ));
  }
  return ranges;
}

List<_EqualMapping> _equalMappings(List<_CharEdit> operations) {
  final mappings = <_EqualMapping>[];
  var originalOffset = 0;
  var modifiedOffset = 0;
  var operationIndex = 0;

  while (operationIndex < operations.length) {
    if (operations[operationIndex] == _CharEdit.equal) {
      final originalStart = originalOffset;
      final modifiedStart = modifiedOffset;
      while (operationIndex < operations.length &&
          operations[operationIndex] == _CharEdit.equal) {
        originalOffset++;
        modifiedOffset++;
        operationIndex++;
      }
      mappings.add(
        _EqualMapping(originalStart, originalOffset, modifiedStart),
      );
    } else {
      if (operations[operationIndex] == _CharEdit.delete) {
        originalOffset++;
      } else {
        modifiedOffset++;
      }
      operationIndex++;
    }
  }
  return mappings;
}

List<_RangePair>? _expandSmallWordChanges(
  List<int> original,
  List<int> modified,
  List<_CharEdit> operations,
  List<_RangePair> ranges, {
  required int maxWork,
}) {
  if (ranges.isEmpty) return ranges;
  final equalMappings = _equalMappings(operations);
  final budget = _WorkBudget(maxWork);
  final originalWords = _allWordSpans(original, budget);
  final modifiedWords = _allWordSpans(modified, budget);
  if (originalWords == null || modifiedWords == null) return null;
  final candidates = <_RangePair>{};
  final checkedPairs = <_RangePair>{};

  for (final range in ranges) {
    final neighbors = <(int, int)>[];
    if (range.originalStart > 0 && range.modifiedStart > 0) {
      neighbors.add((range.originalStart - 1, range.modifiedStart - 1));
    }
    if (range.originalEnd < original.length &&
        range.modifiedEnd < modified.length) {
      neighbors.add((range.originalEnd, range.modifiedEnd));
    }

    for (final (originalOffset, modifiedOffset) in neighbors) {
      if (!budget.use()) return null;
      final originalWord =
          _wordContaining(originalWords, originalOffset, budget);
      final modifiedWord =
          _wordContaining(modifiedWords, modifiedOffset, budget);
      if (budget.exceeded) return null;
      if (originalWord == null || modifiedWord == null) continue;
      final pair = _RangePair(
        originalWord.start,
        originalWord.end,
        modifiedWord.start,
        modifiedWord.end,
      );
      if (!checkedPairs.add(pair)) continue;
      final wordsEqual = _rangesEqual(
        original,
        pair.originalStart,
        pair.originalEnd,
        modified,
        pair.modifiedStart,
        pair.modifiedEnd,
        budget,
      );
      if (budget.exceeded) return null;
      if (!wordsEqual) candidates.add(pair);
    }
  }

  final additional = <_RangePair>[];
  for (final candidate in candidates) {
    var equalCharacters = 0;
    for (final mapping in equalMappings) {
      if (!budget.use()) return null;
      final delta = mapping.modifiedStart - mapping.originalStart;
      final start = _max3(
        mapping.originalStart,
        candidate.originalStart,
        candidate.modifiedStart - delta,
      );
      final end = _min3(
        mapping.originalEnd,
        candidate.originalEnd,
        candidate.modifiedEnd - delta,
      );
      if (end > start) equalCharacters += end - start;
    }

    // Code-OSS expands only when equal characters cover less than two thirds
    // of the paired word lengths: 3 * equal < original + modified.
    if (3 * equalCharacters <
        candidate.originalLength + candidate.modifiedLength) {
      additional.add(candidate);
    }
  }

  return _mergeRanges([...ranges, ...additional]);
}

bool _rangesEqual(
  List<int> original,
  int originalStart,
  int originalEnd,
  List<int> modified,
  int modifiedStart,
  int modifiedEnd,
  _WorkBudget budget,
) {
  if (originalEnd - originalStart != modifiedEnd - modifiedStart) return false;
  for (var offset = 0; offset < originalEnd - originalStart; offset++) {
    if (!budget.use() ||
        original[originalStart + offset] != modified[modifiedStart + offset]) {
      return false;
    }
  }
  return true;
}

List<_WordSpan>? _allWordSpans(List<int> text, _WorkBudget budget) {
  final spans = <_WordSpan>[];
  var offset = 0;
  while (offset < text.length) {
    if (!budget.use()) return null;
    if (!_isAsciiWordChar(text[offset])) {
      offset++;
      continue;
    }
    final start = offset++;
    while (offset < text.length && _isAsciiWordChar(text[offset])) {
      if (!budget.use()) return null;
      offset++;
    }
    spans.add(_WordSpan(start, offset));
  }
  return spans;
}

_WordSpan? _wordContaining(
  List<_WordSpan> spans,
  int offset,
  _WorkBudget budget,
) {
  var low = 0;
  var high = spans.length - 1;
  while (low <= high) {
    if (!budget.use()) return null;
    final middle = low + ((high - low) ~/ 2);
    final span = spans[middle];
    if (offset < span.start) {
      high = middle - 1;
    } else if (offset >= span.end) {
      low = middle + 1;
    } else {
      return span;
    }
  }
  return null;
}

bool _isAsciiWordChar(int codeUnit) =>
    (codeUnit >= 0x61 && codeUnit <= 0x7A) ||
    (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
    (codeUnit >= 0x30 && codeUnit <= 0x39);

List<_RangePair> _expandSurrogateBoundaries(
  List<_RangePair> ranges,
  List<int> original,
  List<int> modified,
) {
  final expanded = ranges.map((range) {
    final originalStart = _safeStart(original, range.originalStart);
    final originalEnd = _safeEnd(original, range.originalEnd);
    final modifiedStart = _safeStart(modified, range.modifiedStart);
    final modifiedEnd = _safeEnd(modified, range.modifiedEnd);
    return _RangePair(
      originalStart,
      originalEnd,
      modifiedStart,
      modifiedEnd,
    );
  });
  return _mergeRanges(expanded.toList());
}

List<_RangePair> _repairUnequalGaps(
  List<_RangePair> ranges,
  List<int> original,
  List<int> modified,
) {
  if (ranges.isEmpty) return ranges;
  final result = <_RangePair>[];

  for (var range in _mergeRanges(List.of(ranges))) {
    if (result.isEmpty) {
      if (!_slicesEqual(
        original,
        0,
        range.originalStart,
        modified,
        0,
        range.modifiedStart,
      )) {
        range = _RangePair(
          0,
          range.originalEnd,
          0,
          range.modifiedEnd,
        );
      }
      result.add(range);
      continue;
    }

    var previous = result.last;
    if (!_slicesEqual(
      original,
      previous.originalEnd,
      range.originalStart,
      modified,
      previous.modifiedEnd,
      range.modifiedStart,
    )) {
      result.removeLast();
      range = _unionRanges(previous, range);
    }

    while (result.isNotEmpty) {
      previous = result.last;
      if (range.originalStart <= previous.originalEnd ||
          range.modifiedStart <= previous.modifiedEnd) {
        result.removeLast();
        range = _unionRanges(previous, range);
      } else {
        break;
      }
    }
    result.add(range);
  }

  final last = result.last;
  if (!_slicesEqual(
    original,
    last.originalEnd,
    original.length,
    modified,
    last.modifiedEnd,
    modified.length,
  )) {
    result[result.length - 1] = _RangePair(
      last.originalStart,
      original.length,
      last.modifiedStart,
      modified.length,
    );
  }
  return result;
}

_RangePair _unionRanges(_RangePair a, _RangePair b) => _RangePair(
      _min(a.originalStart, b.originalStart),
      _max(a.originalEnd, b.originalEnd),
      _min(a.modifiedStart, b.modifiedStart),
      _max(a.modifiedEnd, b.modifiedEnd),
    );

bool _slicesEqual(
  List<int> original,
  int originalStart,
  int originalEnd,
  List<int> modified,
  int modifiedStart,
  int modifiedEnd,
) {
  final length = originalEnd - originalStart;
  if (length != modifiedEnd - modifiedStart) return false;
  for (var offset = 0; offset < length; offset++) {
    if (original[originalStart + offset] != modified[modifiedStart + offset]) {
      return false;
    }
  }
  return true;
}

bool _preservesEqualGaps(
  List<int> original,
  List<int> modified,
  List<WordDiffHunk> hunks,
) {
  var originalOffset = 0;
  var modifiedOffset = 0;
  for (final hunk in hunks) {
    final originalStart = hunk.originalStartUtf16;
    final modifiedStart = hunk.modifiedStartUtf16;
    final originalEnd = hunk.originalEndUtf16;
    final modifiedEnd = hunk.modifiedEndUtf16;
    if (originalStart < originalOffset ||
        modifiedStart < modifiedOffset ||
        originalEnd < originalStart ||
        modifiedEnd < modifiedStart ||
        originalEnd > original.length ||
        modifiedEnd > modified.length ||
        !_slicesEqual(
          original,
          originalOffset,
          originalStart,
          modified,
          modifiedOffset,
          modifiedStart,
        )) {
      return false;
    }
    originalOffset = originalEnd;
    modifiedOffset = modifiedEnd;
  }
  return _slicesEqual(
    original,
    originalOffset,
    original.length,
    modified,
    modifiedOffset,
    modified.length,
  );
}

bool _hasSafeSurrogateBoundaries(
  List<int> original,
  List<int> modified,
  List<WordDiffHunk> hunks,
) {
  for (final hunk in hunks) {
    if (!_isSafeSurrogateBoundary(original, hunk.originalStartUtf16) ||
        !_isSafeSurrogateBoundary(original, hunk.originalEndUtf16) ||
        !_isSafeSurrogateBoundary(modified, hunk.modifiedStartUtf16) ||
        !_isSafeSurrogateBoundary(modified, hunk.modifiedEndUtf16)) {
      return false;
    }
  }
  return true;
}

bool _isSafeSurrogateBoundary(List<int> text, int offset) =>
    offset <= 0 ||
    offset >= text.length ||
    !_isHighSurrogate(text[offset - 1]) ||
    !_isLowSurrogate(text[offset]);

int _safeStart(List<int> text, int offset) => offset > 0 &&
        offset < text.length &&
        _isHighSurrogate(text[offset - 1]) &&
        _isLowSurrogate(text[offset])
    ? offset - 1
    : offset;

int _safeEnd(List<int> text, int offset) => offset > 0 &&
        offset < text.length &&
        _isHighSurrogate(text[offset - 1]) &&
        _isLowSurrogate(text[offset])
    ? offset + 1
    : offset;

bool _isHighSurrogate(int codeUnit) => codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

bool _isLowSurrogate(int codeUnit) => codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;

List<_RangePair> _mergeRanges(List<_RangePair> ranges) {
  if (ranges.length < 2) return ranges;
  ranges.sort((a, b) {
    final byOriginal = a.originalStart.compareTo(b.originalStart);
    return byOriginal != 0
        ? byOriginal
        : a.modifiedStart.compareTo(b.modifiedStart);
  });

  final merged = <_RangePair>[];
  for (final range in ranges) {
    if (merged.isEmpty) {
      merged.add(range);
      continue;
    }
    final previous = merged.last;
    if (range.originalStart <= previous.originalEnd ||
        range.modifiedStart <= previous.modifiedEnd) {
      merged[merged.length - 1] = _RangePair(
        _min(previous.originalStart, range.originalStart),
        _max(previous.originalEnd, range.originalEnd),
        _min(previous.modifiedStart, range.modifiedStart),
        _max(previous.modifiedEnd, range.modifiedEnd),
      );
    } else {
      merged.add(range);
    }
  }
  return merged;
}

int _max(int a, int b) => a > b ? a : b;

int _min3(int a, int b, int c) => _min(_min(a, b), c);

int _max3(int a, int b, int c) => _max(_max(a, b), c);

int _min(int a, int b) => a < b ? a : b;
