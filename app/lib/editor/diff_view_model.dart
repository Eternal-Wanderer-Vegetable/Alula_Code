/// Bounded ordered diff rows composed from the line and word diff models.
///
/// This module projects complete source lines for a future renderer. It does
/// not paint UI, load workspace files, or change either document.
library;

import 'line_diff.dart';
import 'word_diff.dart';

enum DiffViewRowKind { unchanged, modified, inserted, deleted }

enum DiffViewFallbackReason {
  inputLimit,
  lineDiffLimit,
  rowLimit,
  alignmentInvariant,
}

enum DiffInlineFallbackReason {
  aggregateInputLimit,
  aggregateWorkLimit,
  wordInputLimit,
  wordWorkLimit,
  wordAlignmentInvariant,
}

class DiffViewModelOptions {
  const DiffViewModelOptions({
    this.lineDiffOptions = const LineDiffOptions(),
    this.wordDiffOptions = const WordDiffOptions(),
    this.maxInputCodeUnits = 2000000,
    this.maxRows = 16384,
    this.maxAggregateWordInputCodeUnits = 262144,
    this.maxAggregateWordWork = 2000000,
  })  : assert(maxRows > 0),
        assert(maxAggregateWordInputCodeUnits >= 0),
        assert(maxAggregateWordWork >= 0);

  final LineDiffOptions lineDiffOptions;
  final WordDiffOptions wordDiffOptions;

  /// Caps the combined UTF-16 input even when both texts are identical and
  /// the line diff model can otherwise return its equality fast path.
  final int maxInputCodeUnits;

  /// Caps the unified row list. A row-limit fallback returns no partial rows
  /// and keeps the complete source strings on [DiffViewModelResult].
  final int maxRows;

  /// Caps the sum of both sides of every computed per-line word diff.
  final int maxAggregateWordInputCodeUnits;

  /// Caps the sum of the per-line Myers work budgets reserved by this model.
  final int maxAggregateWordWork;
}

class DiffViewRow {
  const DiffViewRow({
    required this.rowIndex,
    required this.kind,
    required this.originalLineNumber,
    required this.modifiedLineNumber,
    required this.originalText,
    required this.modifiedText,
    this.wordChanges = const [],
    this.inlineFallbackReason,
  });

  /// Zero-based index in the unified output row list.
  final int rowIndex;

  final DiffViewRowKind kind;

  /// Source line numbers are 1-based; a missing side is an insertion or
  /// deletion row. Source text excludes LF but retains any preceding CR.
  final int? originalLineNumber;
  final int? modifiedLineNumber;
  final String? originalText;
  final String? modifiedText;

  /// Zero-based, end-exclusive UTF-16 ranges relative to the paired lines.
  /// The list contains a full-line range when [inlineFallbackReason] is set.
  final List<WordDiffHunk> wordChanges;

  /// A changed pair still has a complete row when inline ranges exceed a
  /// budget; the renderer can highlight the complete line in that case.
  final DiffInlineFallbackReason? inlineFallbackReason;
}

class DiffViewModelResult {
  DiffViewModelResult._({
    required this.originalText,
    required this.modifiedText,
    required this.rows,
    required this.lineDiff,
    this.fallbackReason,
  });

  /// The complete immutable inputs, retained even when row projection falls
  /// back so a caller can choose a whole-text presentation.
  final String originalText;
  final String modifiedText;
  final List<DiffViewRow> rows;
  final LineDiffResult lineDiff;
  final DiffViewFallbackReason? fallbackReason;

  bool get isApproximate =>
      fallbackReason != null ||
      lineDiff.isApproximate ||
      rows.any((row) => row.inlineFallbackReason != null);
}

/// Composes line alignment and per-line word ranges into ordered diff rows.
///
/// Replacement lines within each line hunk are paired by source order. Any
/// excess lines remain one-sided insertions/deletions. The line and word
/// models retain their own explicit fallback reasons; this function never
/// truncates either source string or emits a partial row list on row overflow.
DiffViewModelResult computeDiffViewModel(
  String originalText,
  String modifiedText, {
  DiffViewModelOptions options = const DiffViewModelOptions(),
}) {
  final lineDiff = computeLineDiff(
    originalText,
    modifiedText,
    options: options.lineDiffOptions,
  );
  final inputLimit = _minimum(
    options.maxInputCodeUnits,
    options.lineDiffOptions.maxInputCodeUnits,
  );
  if (originalText.length + modifiedText.length > inputLimit) {
    return _modelFallback(
      originalText,
      modifiedText,
      lineDiff,
      DiffViewFallbackReason.inputLimit,
    );
  }
  if (lineDiff.fallbackReason == LineDiffFallbackReason.inputLimit) {
    return _modelFallback(
      originalText,
      modifiedText,
      lineDiff,
      DiffViewFallbackReason.lineDiffLimit,
    );
  }

  if (lineDiff.originalLineCount > options.lineDiffOptions.maxLinesPerSide ||
      lineDiff.modifiedLineCount > options.lineDiffOptions.maxLinesPerSide) {
    return _modelFallback(
      originalText,
      modifiedText,
      lineDiff,
      DiffViewFallbackReason.lineDiffLimit,
    );
  }

  if (lineDiff.originalLineCount + lineDiff.modifiedLineCount >
      options.maxRows) {
    return _modelFallback(
      originalText,
      modifiedText,
      lineDiff,
      DiffViewFallbackReason.rowLimit,
    );
  }

  final originalLines = originalText.split('\n');
  final modifiedLines = modifiedText.split('\n');
  if (originalLines.length != lineDiff.originalLineCount ||
      modifiedLines.length != lineDiff.modifiedLineCount ||
      !_validHunkSequence(lineDiff, originalLines, modifiedLines,
          options.lineDiffOptions.ignoreTrimWhitespace)) {
    return _modelFallback(
      originalText,
      modifiedText,
      lineDiff,
      DiffViewFallbackReason.alignmentInvariant,
    );
  }

  final changedPairCount = _countChangedPairs(
    lineDiff,
    originalLines,
    modifiedLines,
    options.lineDiffOptions.ignoreTrimWhitespace,
  );
  if (changedPairCount == null) {
    return _modelFallback(
      originalText,
      modifiedText,
      lineDiff,
      DiffViewFallbackReason.alignmentInvariant,
    );
  }

  final budget = _InlineWordBudget(
    inputCodeUnits: options.maxAggregateWordInputCodeUnits,
    work: options.maxAggregateWordWork,
    changedPairs: changedPairCount,
  );
  final rows = <DiffViewRow>[];
  var originalLine = 1;
  var modifiedLine = 1;

  for (final hunk in lineDiff.hunks) {
    _appendEqualRows(
      rows,
      originalLines,
      modifiedLines,
      originalLine,
      hunk.originalStartLine,
      modifiedLine,
      hunk.modifiedStartLine,
    );

    final pairedCount =
        _minimum(hunk.originalLineCount, hunk.modifiedLineCount);
    for (var index = 0; index < pairedCount; index++) {
      final originalNumber = hunk.originalStartLine + index;
      final modifiedNumber = hunk.modifiedStartLine + index;
      rows.add(_pairedRow(
        rowIndex: rows.length,
        originalLineNumber: originalNumber,
        modifiedLineNumber: modifiedNumber,
        originalText: originalLines[originalNumber - 1],
        modifiedText: modifiedLines[modifiedNumber - 1],
        ignoreTrimWhitespace: options.lineDiffOptions.ignoreTrimWhitespace,
        wordDiffOptions: options.wordDiffOptions,
        budget: budget,
      ));
    }

    for (var index = pairedCount; index < hunk.originalLineCount; index++) {
      final number = hunk.originalStartLine + index;
      rows.add(DiffViewRow(
        rowIndex: rows.length,
        kind: DiffViewRowKind.deleted,
        originalLineNumber: number,
        modifiedLineNumber: null,
        originalText: originalLines[number - 1],
        modifiedText: null,
      ));
    }
    for (var index = pairedCount; index < hunk.modifiedLineCount; index++) {
      final number = hunk.modifiedStartLine + index;
      rows.add(DiffViewRow(
        rowIndex: rows.length,
        kind: DiffViewRowKind.inserted,
        originalLineNumber: null,
        modifiedLineNumber: number,
        originalText: null,
        modifiedText: modifiedLines[number - 1],
      ));
    }

    originalLine = hunk.originalEndLineExclusive;
    modifiedLine = hunk.modifiedEndLineExclusive;
  }

  _appendEqualRows(
    rows,
    originalLines,
    modifiedLines,
    originalLine,
    originalLines.length + 1,
    modifiedLine,
    modifiedLines.length + 1,
  );

  if (!_validRows(
    rows,
    originalLines,
    modifiedLines,
    options.lineDiffOptions.ignoreTrimWhitespace,
  )) {
    return _modelFallback(
      originalText,
      modifiedText,
      lineDiff,
      DiffViewFallbackReason.alignmentInvariant,
    );
  }

  return DiffViewModelResult._(
    originalText: originalText,
    modifiedText: modifiedText,
    rows: List.unmodifiable(rows),
    lineDiff: lineDiff,
  );
}

DiffViewModelResult _modelFallback(
  String originalText,
  String modifiedText,
  LineDiffResult lineDiff,
  DiffViewFallbackReason reason,
) =>
    DiffViewModelResult._(
      originalText: originalText,
      modifiedText: modifiedText,
      rows: const [],
      lineDiff: lineDiff,
      fallbackReason: reason,
    );

void _appendEqualRows(
  List<DiffViewRow> rows,
  List<String> originalLines,
  List<String> modifiedLines,
  int originalStart,
  int originalEndExclusive,
  int modifiedStart,
  int modifiedEndExclusive,
) {
  for (var offset = 0;
      offset < originalEndExclusive - originalStart;
      offset++) {
    final originalNumber = originalStart + offset;
    final modifiedNumber = modifiedStart + offset;
    rows.add(DiffViewRow(
      rowIndex: rows.length,
      kind: DiffViewRowKind.unchanged,
      originalLineNumber: originalNumber,
      modifiedLineNumber: modifiedNumber,
      originalText: originalLines[originalNumber - 1],
      modifiedText: modifiedLines[modifiedNumber - 1],
    ));
  }
}

DiffViewRow _pairedRow({
  required int rowIndex,
  required int originalLineNumber,
  required int modifiedLineNumber,
  required String originalText,
  required String modifiedText,
  required bool ignoreTrimWhitespace,
  required WordDiffOptions wordDiffOptions,
  required _InlineWordBudget budget,
}) {
  if (_linesEquivalent(originalText, modifiedText, ignoreTrimWhitespace)) {
    return DiffViewRow(
      rowIndex: rowIndex,
      kind: DiffViewRowKind.unchanged,
      originalLineNumber: originalLineNumber,
      modifiedLineNumber: modifiedLineNumber,
      originalText: originalText,
      modifiedText: modifiedText,
    );
  }

  final pairInput = originalText.length + modifiedText.length;
  budget.changedPairs--;
  if (pairInput > budget.inputCodeUnits) {
    return _wholeLineFallback(
      rowIndex,
      originalLineNumber,
      modifiedLineNumber,
      originalText,
      modifiedText,
      DiffInlineFallbackReason.aggregateInputLimit,
    );
  }
  if (budget.work <= 0) {
    return _wholeLineFallback(
      rowIndex,
      originalLineNumber,
      modifiedLineNumber,
      originalText,
      modifiedText,
      DiffInlineFallbackReason.aggregateWorkLimit,
    );
  }

  final remainingPairs = budget.changedPairs + 1;
  final reservedWork = _minimum(
    _maximum(0, wordDiffOptions.maxWork),
    _maximum(1, budget.work ~/ remainingPairs),
  );
  budget.work -= reservedWork;
  budget.inputCodeUnits -= pairInput;

  final wordResult = computeWordDiff(
    originalText,
    modifiedText,
    options: WordDiffOptions(
      maxInputCodeUnits: _minimum(
        wordDiffOptions.maxInputCodeUnits,
        pairInput,
      ),
      maxTraceCells: wordDiffOptions.maxTraceCells,
      maxWork: reservedWork,
    ),
  );
  final fallbackReason = _inlineFallbackReason(wordResult.fallbackReason);
  return DiffViewRow(
    rowIndex: rowIndex,
    kind: DiffViewRowKind.modified,
    originalLineNumber: originalLineNumber,
    modifiedLineNumber: modifiedLineNumber,
    originalText: originalText,
    modifiedText: modifiedText,
    wordChanges: List.unmodifiable(wordResult.hunks),
    inlineFallbackReason: fallbackReason,
  );
}

DiffViewRow _wholeLineFallback(
  int rowIndex,
  int originalLineNumber,
  int modifiedLineNumber,
  String originalText,
  String modifiedText,
  DiffInlineFallbackReason reason,
) =>
    DiffViewRow(
      rowIndex: rowIndex,
      kind: DiffViewRowKind.modified,
      originalLineNumber: originalLineNumber,
      modifiedLineNumber: modifiedLineNumber,
      originalText: originalText,
      modifiedText: modifiedText,
      wordChanges: List.unmodifiable([
        WordDiffHunk(
          originalStartUtf16: 0,
          originalEndUtf16: originalText.length,
          modifiedStartUtf16: 0,
          modifiedEndUtf16: modifiedText.length,
        ),
      ]),
      inlineFallbackReason: reason,
    );

DiffInlineFallbackReason? _inlineFallbackReason(
  WordDiffFallbackReason? reason,
) {
  switch (reason) {
    case null:
      return null;
    case WordDiffFallbackReason.inputLimit:
      return DiffInlineFallbackReason.wordInputLimit;
    case WordDiffFallbackReason.workLimit:
      return DiffInlineFallbackReason.wordWorkLimit;
    case WordDiffFallbackReason.alignmentInvariant:
      return DiffInlineFallbackReason.wordAlignmentInvariant;
  }
}

int? _countChangedPairs(
  LineDiffResult lineDiff,
  List<String> originalLines,
  List<String> modifiedLines,
  bool ignoreTrimWhitespace,
) {
  var count = 0;
  for (final hunk in lineDiff.hunks) {
    final pairedCount =
        _minimum(hunk.originalLineCount, hunk.modifiedLineCount);
    for (var index = 0; index < pairedCount; index++) {
      final original = originalLines[hunk.originalStartLine + index - 1];
      final modified = modifiedLines[hunk.modifiedStartLine + index - 1];
      if (!_linesEquivalent(original, modified, ignoreTrimWhitespace)) count++;
    }
  }
  return count;
}

bool _validHunkSequence(
  LineDiffResult lineDiff,
  List<String> originalLines,
  List<String> modifiedLines,
  bool ignoreTrimWhitespace,
) {
  var originalCursor = 1;
  var modifiedCursor = 1;
  for (final hunk in lineDiff.hunks) {
    if (hunk.originalStartLine < originalCursor ||
        hunk.modifiedStartLine < modifiedCursor ||
        hunk.originalEndLineExclusive < hunk.originalStartLine ||
        hunk.modifiedEndLineExclusive < hunk.modifiedStartLine ||
        hunk.originalEndLineExclusive > originalLines.length + 1 ||
        hunk.modifiedEndLineExclusive > modifiedLines.length + 1 ||
        hunk.originalStartLine - originalCursor !=
            hunk.modifiedStartLine - modifiedCursor) {
      return false;
    }
    for (var offset = 0;
        offset < hunk.originalStartLine - originalCursor;
        offset++) {
      if (!_linesEquivalent(
        originalLines[originalCursor + offset - 1],
        modifiedLines[modifiedCursor + offset - 1],
        ignoreTrimWhitespace,
      )) {
        return false;
      }
    }
    originalCursor = hunk.originalEndLineExclusive;
    modifiedCursor = hunk.modifiedEndLineExclusive;
  }
  if (originalLines.length + 1 - originalCursor !=
      modifiedLines.length + 1 - modifiedCursor) {
    return false;
  }
  for (var offset = 0;
      offset < originalLines.length + 1 - originalCursor;
      offset++) {
    if (!_linesEquivalent(
      originalLines[originalCursor + offset - 1],
      modifiedLines[modifiedCursor + offset - 1],
      ignoreTrimWhitespace,
    )) {
      return false;
    }
  }
  return true;
}

bool _validRows(
  List<DiffViewRow> rows,
  List<String> originalLines,
  List<String> modifiedLines,
  bool ignoreTrimWhitespace,
) {
  var originalLine = 1;
  var modifiedLine = 1;
  for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
    final row = rows[rowIndex];
    if (row.rowIndex != rowIndex) return false;
    if (row.originalLineNumber != null) {
      if (row.originalLineNumber != originalLine ||
          row.originalText != originalLines[originalLine - 1]) {
        return false;
      }
      originalLine++;
    } else if (row.originalText != null) {
      return false;
    }
    if (row.modifiedLineNumber != null) {
      if (row.modifiedLineNumber != modifiedLine ||
          row.modifiedText != modifiedLines[modifiedLine - 1]) {
        return false;
      }
      modifiedLine++;
    } else if (row.modifiedText != null) {
      return false;
    }

    switch (row.kind) {
      case DiffViewRowKind.unchanged:
        if (row.originalText == null ||
            row.modifiedText == null ||
            !_linesEquivalent(
              row.originalText!,
              row.modifiedText!,
              ignoreTrimWhitespace,
            ) ||
            row.wordChanges.isNotEmpty ||
            row.inlineFallbackReason != null) {
          return false;
        }
      case DiffViewRowKind.modified:
        if (row.originalText == null ||
            row.modifiedText == null ||
            _linesEquivalent(
              row.originalText!,
              row.modifiedText!,
              ignoreTrimWhitespace,
            ) ||
            row.wordChanges.isEmpty) {
          return false;
        }
      case DiffViewRowKind.inserted:
        if (row.originalText != null || row.modifiedText == null) return false;
      case DiffViewRowKind.deleted:
        if (row.originalText == null || row.modifiedText != null) return false;
    }

    var originalEnd = 0;
    var modifiedEnd = 0;
    for (final wordChange in row.wordChanges) {
      if (wordChange.originalStartUtf16 < originalEnd ||
          wordChange.modifiedStartUtf16 < modifiedEnd ||
          wordChange.originalEndUtf16 < wordChange.originalStartUtf16 ||
          wordChange.modifiedEndUtf16 < wordChange.modifiedStartUtf16 ||
          wordChange.originalEndUtf16 > (row.originalText?.length ?? 0) ||
          wordChange.modifiedEndUtf16 > (row.modifiedText?.length ?? 0)) {
        return false;
      }
      originalEnd = wordChange.originalEndUtf16;
      modifiedEnd = wordChange.modifiedEndUtf16;
    }
  }
  return originalLine == originalLines.length + 1 &&
      modifiedLine == modifiedLines.length + 1;
}

bool _linesEquivalent(
        String original, String modified, bool ignoreTrimWhitespace) =>
    ignoreTrimWhitespace
        ? original.trim() == modified.trim()
        : original == modified;

int _minimum(int left, int right) => left < right ? left : right;

int _maximum(int left, int right) => left > right ? left : right;

class _InlineWordBudget {
  _InlineWordBudget({
    required this.inputCodeUnits,
    required this.work,
    required this.changedPairs,
  });

  int inputCodeUnits;
  int work;
  int changedPairs;
}
