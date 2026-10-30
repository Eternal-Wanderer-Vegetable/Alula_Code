import 'package:flutter/foundation.dart';

import 'editor_rendering.dart';

const int maxEditorFoldSymbols = 4096;

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
