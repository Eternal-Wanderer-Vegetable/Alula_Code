import 'package:flutter/foundation.dart';

import 'editor_rendering.dart';

const int maxEditorFoldSymbols = 4096;

@immutable
class EditorDocumentLineRange {
  const EditorDocumentLineRange({
    required this.startLine,
    required this.endLineExclusive,
  });

  /// Zero-based first hidden document line.
  final int startLine;

  /// Zero-based exclusive end of the hidden document lines.
  final int endLineExclusive;

  @override
  bool operator ==(Object other) =>
      other is EditorDocumentLineRange &&
      startLine == other.startLine &&
      endLineExclusive == other.endLineExclusive;

  @override
  int get hashCode => Object.hash(startLine, endLineExclusive);
}

typedef EditorFoldRangesChanged = void Function(
  int documentId,
  int documentVersion,
  List<EditorDocumentLineRange> ranges,
);

List<EditorDocumentLineRange> normalizeEditorDocumentLineRanges(
  Iterable<EditorDocumentLineRange> ranges, {
  required int documentLineCount,
}) {
  if (documentLineCount < 1) {
    throw RangeError.value(documentLineCount, 'documentLineCount');
  }
  final sorted = ranges
      .map((range) => EditorDocumentLineRange(
            startLine: range.startLine.clamp(0, documentLineCount).toInt(),
            endLineExclusive:
                range.endLineExclusive.clamp(0, documentLineCount).toInt(),
          ))
      .where((range) => range.endLineExclusive > range.startLine)
      .toList()
    ..sort((a, b) {
      final byStart = a.startLine.compareTo(b.startLine);
      return byStart != 0
          ? byStart
          : a.endLineExclusive.compareTo(b.endLineExclusive);
    });
  if (sorted.isEmpty) return const [];

  final merged = <EditorDocumentLineRange>[];
  var start = sorted.first.startLine;
  var end = sorted.first.endLineExclusive;
  for (final range in sorted.skip(1)) {
    if (range.startLine <= end) {
      if (range.endLineExclusive > end) end = range.endLineExclusive;
      continue;
    }
    merged.add(EditorDocumentLineRange(
      startLine: start,
      endLineExclusive: end,
    ));
    start = range.startLine;
    end = range.endLineExclusive;
  }
  merged.add(EditorDocumentLineRange(
    startLine: start,
    endLineExclusive: end,
  ));
  return List.unmodifiable(merged);
}

@immutable
class EditorDocumentLineProjection {
  EditorDocumentLineProjection({
    required this.documentLineCount,
    Iterable<EditorDocumentLineRange> hiddenRanges = const [],
  }) : hiddenRanges = normalizeEditorDocumentLineRanges(
          hiddenRanges,
          documentLineCount: documentLineCount,
        );

  final int documentLineCount;
  final List<EditorDocumentLineRange> hiddenRanges;

  int get visibleLineCount =>
      documentLineCount -
      hiddenRanges.fold<int>(
        0,
        (count, range) => count + range.endLineExclusive - range.startLine,
      );

  /// Maps hidden lines onto their visible header row.
  int documentLineToVisibleLine(int documentLine) {
    final line = documentLine.clamp(0, documentLineCount - 1).toInt();
    var hiddenBefore = 0;
    for (final range in hiddenRanges) {
      if (line < range.startLine) return line - hiddenBefore;
      if (line < range.endLineExclusive) {
        return (range.startLine - hiddenBefore - 1).clamp(0, documentLineCount);
      }
      hiddenBefore += range.endLineExclusive - range.startLine;
    }
    return (line - hiddenBefore).clamp(0, documentLineCount).toInt();
  }

  /// Maps a visible row to its source line. The exclusive end boundary is
  /// accepted so callers can project the bottom edge of a visible viewport.
  int visibleLineToDocumentBoundary(int visibleLine) {
    final line = visibleLine.clamp(0, visibleLineCount).toInt();
    var hiddenBefore = 0;
    for (final range in hiddenRanges) {
      final visibleStart = range.startLine - hiddenBefore;
      if (line < visibleStart) return line + hiddenBefore;
      hiddenBefore += range.endLineExclusive - range.startLine;
    }
    return (line + hiddenBefore).clamp(0, documentLineCount).toInt();
  }

  int visibleLineToDocumentLine(int visibleLine) {
    if (visibleLineCount <= 1) return 0;
    return visibleLineToDocumentBoundary(
      visibleLine.clamp(0, visibleLineCount - 1).toInt(),
    );
  }

  int visibleLineCountInRange({
    required int startLine,
    required int endLineExclusive,
  }) {
    final start = startLine.clamp(0, documentLineCount).toInt();
    final end = endLineExclusive.clamp(start, documentLineCount).toInt();
    var hidden = 0;
    for (final range in hiddenRanges) {
      final overlapStart = range.startLine > start ? range.startLine : start;
      final overlapEnd =
          range.endLineExclusive < end ? range.endLineExclusive : end;
      if (overlapEnd > overlapStart) hidden += overlapEnd - overlapStart;
    }
    return end - start - hidden;
  }
}

@immutable
class EditorFoldSymbol {
  const EditorFoldSymbol({
    required this.kind,
    required this.name,
    required this.startUtf16,
    required this.line,
    required this.endLine,
  });

  final String kind;
  final String name;
  final int startUtf16;
  final int line;
  final int endLine;

  String get key => '$kind:$startUtf16:$name';

  static EditorFoldSymbol? fromMap(Map<String, Object?> value) {
    final kind = value['kind'];
    final name = value['name'];
    final startUtf16 = value['start_utf16'];
    final line = value['line'];
    final endLine = value['end_line'];
    if (kind is! String ||
        name is! String ||
        startUtf16 is! num ||
        line is! num ||
        endLine is! num) {
      return null;
    }
    final parsedStart = startUtf16.toInt();
    final parsedLine = line.toInt();
    final parsedEndLine = endLine.toInt();
    if (parsedStart < 0 || parsedLine < 1 || parsedEndLine <= parsedLine) {
      return null;
    }
    return EditorFoldSymbol(
      kind: kind,
      name: name,
      startUtf16: parsedStart,
      line: parsedLine,
      endLine: parsedEndLine,
    );
  }
}

@immutable
class EditorFoldRange {
  const EditorFoldRange({
    required this.symbol,
    required this.headerLineIndex,
    required this.hiddenStartUtf16,
    required this.hiddenEndUtf16,
    required this.hiddenLineIndices,
  });

  final EditorFoldSymbol symbol;
  final int headerLineIndex;
  final int hiddenStartUtf16;
  final int hiddenEndUtf16;
  final List<int> hiddenLineIndices;
}

@immutable
class EditorFoldLayout {
  const EditorFoldLayout({
    required this.foldableByLine,
    required this.foldRangesByLine,
    required this.collapsedRanges,
    required this.hiddenLineIndices,
  });

  const EditorFoldLayout.empty()
      : foldableByLine = const {},
        foldRangesByLine = const {},
        collapsedRanges = const [],
        hiddenLineIndices = const {};

  final Map<int, EditorFoldSymbol> foldableByLine;
  final Map<int, EditorFoldRange> foldRangesByLine;
  final List<EditorFoldRange> collapsedRanges;
  final Set<int> hiddenLineIndices;

  Set<int> get foldableLineIndices => foldableByLine.keys.toSet();

  Set<int> get collapsedLineIndices => {
        for (final range in collapsedRanges) range.headerLineIndex,
      };
}

/// Maps Rust's 1-based syntax scopes onto this bounded text window.
///
/// Folded lines remain in the TextSpan, so every Flutter selection and IME
/// offset stays in the same UTF-16 coordinate system as the Rust document.
EditorFoldLayout buildEditorFoldLayout({
  required String text,
  required int firstDocumentLine,
  required List<EditorFoldSymbol> symbols,
  required Set<String> collapsedKeys,
}) {
  if (firstDocumentLine < 0) {
    throw RangeError.value(firstDocumentLine, 'firstDocumentLine');
  }
  final lines = editorLogicalLines(text);
  if (lines.isEmpty || text.isEmpty || symbols.isEmpty) {
    return const EditorFoldLayout.empty();
  }
  final firstLine = firstDocumentLine + 1;
  final lastLine = firstLine + lines.length - 1;
  final candidates = symbols
      .where((symbol) => symbol.endLine >= firstLine && symbol.line <= lastLine)
      .toList()
    ..sort((a, b) {
      final byStart = a.line.compareTo(b.line);
      if (byStart != 0) return byStart;
      final byEnd = b.endLine.compareTo(a.endLine);
      if (byEnd != 0) return byEnd;
      return a.startUtf16.compareTo(b.startUtf16);
    });

  final visibleFolds = <int, EditorFoldSymbol>{};
  final foldRanges = <int, EditorFoldRange>{};
  final collapsed = <EditorFoldRange>[];
  final hiddenLines = <int>{};
  var processed = 0;
  for (final symbol in candidates) {
    if (++processed > maxEditorFoldSymbols) break;
    final headerIndex = symbol.line - firstLine;
    final firstHiddenIndex = (headerIndex + 1).clamp(0, lines.length).toInt();
    final lastHiddenIndex =
        (symbol.endLine - firstLine).clamp(-1, lines.length - 1).toInt();
    if (firstHiddenIndex > lastHiddenIndex) continue;

    final headerIsVisible = headerIndex >= 0 && headerIndex < lines.length;
    final hiddenStart = lines[firstHiddenIndex].startUtf16;
    final finalHiddenLine = lines[lastHiddenIndex];
    var hiddenEnd = finalHiddenLine.endUtf16;
    if (hiddenEnd < text.length && text.codeUnitAt(hiddenEnd) == 0x0A) {
      hiddenEnd++;
    }
    if (hiddenEnd <= hiddenStart) continue;
    final rangeLines = List<int>.generate(
      lastHiddenIndex - firstHiddenIndex + 1,
      (offset) => firstHiddenIndex + offset,
      growable: false,
    );
    final range = EditorFoldRange(
      symbol: symbol,
      headerLineIndex: headerIsVisible ? headerIndex : -1,
      hiddenStartUtf16: hiddenStart,
      hiddenEndUtf16: hiddenEnd,
      hiddenLineIndices: rangeLines,
    );
    if (headerIsVisible && !hiddenLines.contains(headerIndex)) {
      visibleFolds.putIfAbsent(headerIndex, () => symbol);
      foldRanges.putIfAbsent(headerIndex, () => range);
    }
    if (!collapsedKeys.contains(symbol.key) ||
        (headerIsVisible && hiddenLines.contains(headerIndex))) {
      continue;
    }
    collapsed.add(range);
    hiddenLines.addAll(rangeLines);
  }

  return EditorFoldLayout(
    foldableByLine: Map.unmodifiable(visibleFolds),
    foldRangesByLine: Map.unmodifiable(foldRanges),
    collapsedRanges: List.unmodifiable(collapsed),
    hiddenLineIndices: Set.unmodifiable(hiddenLines),
  );
}
