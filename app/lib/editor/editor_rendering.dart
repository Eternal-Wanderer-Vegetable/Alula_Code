import 'package:flutter/material.dart';

import '../bridge/alula_core.dart';

enum EditorWhitespaceMode { none, trailing, all }

@immutable
class EditorDocumentLinePosition {
  const EditorDocumentLinePosition({
    required this.firstLineNumber,
    required this.lineCount,
  });

  final int firstLineNumber;
  final int lineCount;
}

/// Finds the logical line containing a Rust-owned absolute UTF-16 offset.
/// The binary search asks Rust for line starts and never reads document text.
EditorDocumentLinePosition resolveEditorDocumentLinePosition(
  AlulaDoc document,
  int offsetUtf16,
) {
  if (offsetUtf16 < 0) {
    throw RangeError.value(offsetUtf16, 'offsetUtf16', 'must be non-negative');
  }
  final metadata = document.lineOffset(0);
  if (offsetUtf16 > metadata.totalUtf16Length) {
    throw RangeError.value(
      offsetUtf16,
      'offsetUtf16',
      'must not exceed ${metadata.totalUtf16Length}',
    );
  }
  var lower = 0;
  var upper = metadata.lineCount;
  while (lower < upper) {
    final middle = lower + (upper - lower) ~/ 2;
    if (document.lineOffset(middle).offsetUtf16 <= offsetUtf16) {
      lower = middle + 1;
    } else {
      upper = middle;
    }
  }
  return EditorDocumentLinePosition(
    firstLineNumber: (lower - 1).clamp(0, metadata.lineCount - 1).toInt(),
    lineCount: metadata.lineCount,
  );
}

@immutable
class EditorLogicalLine {
  const EditorLogicalLine({
    required this.startUtf16,
    required this.endUtf16,
    required this.contentEndUtf16,
  });

  final int startUtf16;
  final int endUtf16;
  final int contentEndUtf16;
}

/// Splits a bounded editor window into logical lines while retaining UTF-16
/// offsets. CRLF is treated as one line break and a final newline adds an
/// empty final line, matching the text input layout.
List<EditorLogicalLine> editorLogicalLines(String text) {
  final lines = <EditorLogicalLine>[];
  var start = 0;
  for (var offset = 0; offset < text.length; offset++) {
    if (text.codeUnitAt(offset) != 0x0A) continue;
    final contentEnd = offset > start && text.codeUnitAt(offset - 1) == 0x0D
        ? offset - 1
        : offset;
    lines.add(EditorLogicalLine(
      startUtf16: start,
      endUtf16: offset,
      contentEndUtf16: contentEnd,
    ));
    start = offset + 1;
  }
  lines.add(EditorLogicalLine(
    startUtf16: start,
    endUtf16: text.length,
    contentEndUtf16: text.length,
  ));
  return List.unmodifiable(lines);
}

List<int> editorIndentGuideOffsets(
  String text,
  EditorLogicalLine line, {
  int tabSize = 4,
}) {
  if (tabSize < 1) throw ArgumentError.value(tabSize, 'tabSize');
  final offsets = <int>[];
  var column = 0;
  var nextGuideColumn = tabSize;
  for (var offset = line.startUtf16; offset < line.contentEndUtf16; offset++) {
    final codeUnit = text.codeUnitAt(offset);
    if (codeUnit == 0x20) {
      column++;
    } else if (codeUnit == 0x09) {
      column += tabSize - column % tabSize;
    } else {
      break;
    }
    while (column >= nextGuideColumn) {
      offsets.add(offset + 1);
      nextGuideColumn += tabSize;
    }
  }
  return List.unmodifiable(offsets);
}

List<int> editorWhitespaceOffsets(
  String text,
  EditorLogicalLine line,
  EditorWhitespaceMode mode,
) {
  if (mode == EditorWhitespaceMode.none) return const [];
  var trailingStart = line.contentEndUtf16;
  while (trailingStart > line.startUtf16) {
    final codeUnit = text.codeUnitAt(trailingStart - 1);
    if (codeUnit != 0x20 && codeUnit != 0x09) break;
    trailingStart--;
  }
  final offsets = <int>[];
  for (var offset = line.startUtf16; offset < line.contentEndUtf16; offset++) {
    final codeUnit = text.codeUnitAt(offset);
    if (codeUnit != 0x20 && codeUnit != 0x09) continue;
    if (mode == EditorWhitespaceMode.all || offset >= trailingStart) {
      offsets.add(offset);
    }
  }
  return List.unmodifiable(offsets);
}

double editorGutterWidth({
  required int lineCount,
  required TextStyle style,
  required TextScaler textScaler,
  required TextDirection textDirection,
}) {
  final numberPainter = TextPainter(
    text: TextSpan(text: '$lineCount', style: style),
    textDirection: textDirection,
    textScaler: textScaler,
  )..layout();
  final width = numberPainter.width + 16;
  numberPainter.dispose();
  return width.clamp(30, 112).toDouble();
}

/// Measures the bounded input window as one unwrapped line block.
///
/// TextField still owns multiline editing; this width is applied by the outer
/// horizontal viewport instead of setting maxLines to one (which would filter
/// line breaks from EditableText input).
double editorUnwrappedTextWidth({
  required String text,
  required TextStyle style,
  required TextScaler textScaler,
  required TextDirection textDirection,
  EdgeInsets padding = EdgeInsets.zero,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: textDirection,
    textScaler: textScaler,
  )..layout();
  // Keep room for EditableText's caret, selection handles, and decoration
  // insets so the final grapheme does not wrap at the measured edge.
  final width = painter.width + padding.horizontal + 24;
  painter.dispose();
  return width;
}

class EditorGutterPainter extends CustomPainter {
  EditorGutterPainter({
    required this.text,
    required this.firstLineNumber,
    required this.style,
    required this.textDirection,
    required this.textScaler,
    required this.padding,
    required this.textWidth,
    required this.scrollController,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.dividerColor,
  }) : super(repaint: scrollController);

  final String text;
  final int firstLineNumber;
  final TextStyle style;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final EdgeInsets padding;
  final double textWidth;
  final ScrollController? scrollController;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color dividerColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(backgroundColor, BlendMode.src);
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
      textWidthBasis: TextWidthBasis.parent,
    )..layout(
        maxWidth: (textWidth - padding.horizontal)
            .clamp(1, double.infinity)
            .toDouble(),
      );
    final scrollY =
        scrollController?.hasClients == true ? scrollController!.offset : 0.0;
    final lineHeight = textPainter.preferredLineHeight;
    final numberStyle = style.copyWith(color: foregroundColor, fontSize: 11);
    final lines = editorLogicalLines(text);
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final caret = textPainter.getOffsetForCaret(
        TextPosition(offset: line.startUtf16),
        Rect.fromLTWH(0, 0, 1.5, lineHeight),
      );
      final numberPainter = TextPainter(
        text: TextSpan(
          text: '${firstLineNumber + index + 1}',
          style: numberStyle,
        ),
        textDirection: textDirection,
        textScaler: textScaler,
        textWidthBasis: TextWidthBasis.parent,
      )..layout(maxWidth: size.width);
      final top = padding.top +
          caret.dy +
          (lineHeight - numberPainter.height) / 2 -
          scrollY;
      if (top + numberPainter.height >= 0 && top <= size.height) {
        numberPainter.paint(
          canvas,
          Offset(size.width - 8 - numberPainter.width, top),
        );
      }
      numberPainter.dispose();
    }
    canvas.drawLine(
      Offset(size.width - 0.5, 0),
      Offset(size.width - 0.5, size.height),
      Paint()
        ..color = dividerColor
        ..strokeWidth = 1,
    );
    textPainter.dispose();
  }

  @override
  bool shouldRepaint(covariant EditorGutterPainter oldDelegate) =>
      oldDelegate.text != text ||
      oldDelegate.firstLineNumber != firstLineNumber ||
      oldDelegate.style != style ||
      oldDelegate.textDirection != textDirection ||
      oldDelegate.textScaler != textScaler ||
      oldDelegate.padding != padding ||
      oldDelegate.textWidth != textWidth ||
      oldDelegate.scrollController != scrollController ||
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.foregroundColor != foregroundColor ||
      oldDelegate.dividerColor != dividerColor;
}

class EditorTextDecorationPainter extends CustomPainter {
  EditorTextDecorationPainter({
    required this.text,
    required this.style,
    required this.textDirection,
    required this.textScaler,
    required this.padding,
    required this.scrollController,
    required this.showIndentGuides,
    required this.tabSize,
    required this.whitespaceMode,
    required this.guideColor,
    required this.whitespaceColor,
  }) : super(repaint: scrollController);

  final String text;
  final TextStyle style;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final EdgeInsets padding;
  final ScrollController? scrollController;
  final bool showIndentGuides;
  final int tabSize;
  final EditorWhitespaceMode whitespaceMode;
  final Color guideColor;
  final Color whitespaceColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (!showIndentGuides && whitespaceMode == EditorWhitespaceMode.none) {
      return;
    }
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
      textWidthBasis: TextWidthBasis.parent,
    )..layout(
        maxWidth: (size.width - padding.horizontal)
            .clamp(1, double.infinity)
            .toDouble(),
      );
    final scrollY =
        scrollController?.hasClients == true ? scrollController!.offset : 0.0;
    final origin = Offset(padding.left, padding.top - scrollY);
    final lineHeight = painter.preferredLineHeight;
    final lines = editorLogicalLines(text);
    final guidePaint = Paint()
      ..color = guideColor
      ..strokeWidth = 1;
    final whitespacePaint = Paint()
      ..color = whitespaceColor
      ..strokeWidth = 1;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final lineStart = painter.getOffsetForCaret(
        TextPosition(offset: line.startUtf16),
        Rect.fromLTWH(0, 0, 1.5, lineHeight),
      );
      final lineEnd = painter.getOffsetForCaret(
        TextPosition(offset: line.endUtf16),
        Rect.fromLTWH(0, 0, 1.5, lineHeight),
      );
      final top = lineStart.dy;
      final bottom = lineEnd.dy + lineHeight;
      if (showIndentGuides) {
        for (final offset in editorIndentGuideOffsets(
          text,
          line,
          tabSize: tabSize,
        )) {
          final guide = painter.getOffsetForCaret(
            TextPosition(offset: offset),
            Rect.fromLTWH(0, 0, 1.5, lineHeight),
          );
          canvas.drawLine(
            origin + Offset(guide.dx, top),
            origin + Offset(guide.dx, bottom),
            guidePaint,
          );
        }
      }
      for (final offset
          in editorWhitespaceOffsets(text, line, whitespaceMode)) {
        final start = painter.getOffsetForCaret(
          TextPosition(offset: offset),
          Rect.fromLTWH(0, 0, 1.5, lineHeight),
        );
        final end = painter.getOffsetForCaret(
          TextPosition(offset: offset + 1),
          Rect.fromLTWH(0, 0, 1.5, lineHeight),
        );
        final marker = origin +
            Offset((start.dx + end.dx) / 2, start.dy + lineHeight * 0.58);
        canvas.drawCircle(marker, 1.15, whitespacePaint);
      }
    }
    canvas.restore();
    painter.dispose();
  }

  @override
  bool shouldRepaint(covariant EditorTextDecorationPainter oldDelegate) =>
      oldDelegate.text != text ||
      oldDelegate.style != style ||
      oldDelegate.textDirection != textDirection ||
      oldDelegate.textScaler != textScaler ||
      oldDelegate.padding != padding ||
      oldDelegate.scrollController != scrollController ||
      oldDelegate.showIndentGuides != showIndentGuides ||
      oldDelegate.tabSize != tabSize ||
      oldDelegate.whitespaceMode != whitespaceMode ||
      oldDelegate.guideColor != guideColor ||
      oldDelegate.whitespaceColor != whitespaceColor;
}
