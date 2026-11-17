// Go-to-line/column resolution follows the pinned Code-OSS parser.
//
// Source: src/vs/editor/contrib/quickAccess/browser/gotoLineQuickAccess.ts
// at 4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e, lines 156-242.
import 'package:characters/characters.dart';

import '../bridge/alula_core.dart';
import '../editor/indentation.dart';

/// A zero-based editor position resolved from Go To Line input.
class GotoPosition {
  const GotoPosition({
    required this.offsetUtf16,
    required this.line,
    required this.column,
  });

  final int offsetUtf16;
  final int line;
  final int column;
}

/// Resolves Code-OSS Go To Line input against the Rust-owned document.
///
/// [line] and [column] are zero-based. [column] is a UTF-16 column, while
/// input columns are visible columns, matching Code-OSS CursorColumns.
/// Empty input (or the initial `:` prompt) returns null. All document reads
/// stay bounded; this function never resynchronizes the full document.
GotoPosition? resolveGotoPosition(
  AlulaDoc doc,
  String input, {
  int tabSize = 4,
  bool zeroBasedOffset = false,
}) {
  if (tabSize < 1 || tabSize > 32) {
    throw const FormatException('Tab size must be between 1 and 32');
  }

  final value = input.trim();
  if (value.isEmpty || value == ':') return null;
  if (!value.startsWith(':')) {
    throw const FormatException('Enter a line number, for example :12:4');
  }

  final body = value.substring(1);
  if (body.startsWith(':')) {
    return _resolveOffset(
      doc,
      body.substring(1),
      zeroBasedOffset: zeroBasedOffset,
    );
  }
  return _resolveLine(doc, body, tabSize: tabSize);
}

GotoPosition? _resolveLine(AlulaDoc doc, String value, {required int tabSize}) {
  final parts = value.split(RegExp(r'[:,#]'));
  final parsedLine = _parseIntPrefix(parts.first.trim());
  if (parsedLine == null) {
    throw const FormatException('Enter a valid line number');
  }

  final metadata = doc.lineOffset(0);
  var lineNumber =
      parsedLine >= 0 ? parsedLine : metadata.lineCount + 1 + parsedLine;
  lineNumber = lineNumber.clamp(1, metadata.lineCount).toInt();
  final line = lineNumber - 1;
  final lineStart = doc.lineOffset(line).offsetUtf16;
  final boundary = doc.lineBoundary(lineStart);
  final lineLength = boundary.endUtf16 - boundary.startUtf16;
  final parsedColumn =
      parts.length >= 2 ? _parseIntPrefix(parts[1].trim()) : null;
  if (lineLength > maxDocReadRangeUtf16) {
    return _resolveLongLine(doc, line, boundary, parsedColumn ?? 1, tabSize);
  }
  final content = _readLineContent(doc, boundary, lineLength);

  // Code-OSS defaults a missing or non-numeric column to the first column.
  var visibleColumn = 1;
  if (parts.length >= 2) {
    final parsedColumn = _parseIntPrefix(parts[1].trim());
    if (parsedColumn != null) {
      final maxColumn = indentationVisibleColumn(content, tabSize: tabSize) + 1;
      visibleColumn =
          parsedColumn >= 0 ? parsedColumn : maxColumn + parsedColumn;
      visibleColumn = visibleColumn.clamp(1, maxColumn).toInt();
    }
  }

  final column = _columnFromVisibleColumn(
    content,
    visibleColumn - 1,
    tabSize: tabSize,
  );
  final position = doc.positionOffset(line, column);
  return GotoPosition(
    offsetUtf16: position.offsetUtf16,
    line: position.line,
    column: position.character,
  );
}

GotoPosition? _resolveOffset(
  AlulaDoc doc,
  String value, {
  required bool zeroBasedOffset,
}) {
  final parsedOffset = _parseIntPrefix(value.trim());
  if (parsedOffset == null) return null;

  final metadata = doc.lineOffset(0);
  var offset = parsedOffset;
  final reverse = offset < 0;
  if (!zeroBasedOffset) offset -= _sign(offset);
  if (reverse) offset += metadata.totalUtf16Length;
  offset = offset.clamp(0, metadata.totalUtf16Length).toInt();

  final line = _lineForOffset(doc, offset, metadata.lineCount);
  final lineStart = doc.lineOffset(line).offsetUtf16;
  DocumentPosition position;
  try {
    position = doc.positionOffset(line, offset - lineStart);
  } on AlulaException catch (error) {
    if (error.code != 'InvalidUtf16Offset' && error.code != 'InvalidOffset') {
      rethrow;
    }
    position =
        doc.positionOffset(line, (offset - lineStart - 1).clamp(0, offset));
  }
  return GotoPosition(
    offsetUtf16: position.offsetUtf16,
    line: position.line,
    column: position.character,
  );
}

GotoPosition _resolveLongLine(AlulaDoc doc, int line,
    DocumentLineBoundary boundary, int requested, int tabSize) {
  int scan({int? target}) {
    var offset = boundary.startUtf16;
    var visible = 0;
    while (offset < boundary.endUtf16) {
      final read = doc.readRange(offset,
          maxLenUtf16:
              (boundary.endUtf16 - offset).clamp(1, maxDocReadRangeUtf16));
      if (read.endUtf16 <= offset) {
        throw const FormatException('Could not read line');
      }
      final text = read.text.substring(offset - read.startUtf16);
      final graphemes = text.characters.toList();
      final finalChunk = read.endUtf16 >= boundary.endUtf16;
      final count = finalChunk ? graphemes.length : graphemes.length - 1;
      if (count < 1) {
        throw const FormatException(
            'A single grapheme exceeds the input budget');
      }
      for (final grapheme in graphemes.take(count)) {
        final next = _nextVisibleColumn(grapheme, visible, tabSize);
        if (target != null && next >= target) {
          return offset -
              boundary.startUtf16 +
              (next - target < target - visible ? grapheme.length : 0);
        }
        visible = next;
        offset += grapheme.length;
      }
    }
    return target == null ? visible : boundary.endUtf16 - boundary.startUtf16;
  }

  final maxColumn = requested < 0 ? scan() + 1 : null;
  final target = requested < 0
      ? (maxColumn! + requested).clamp(1, maxColumn)
      : requested.clamp(1, 0x7FFFFFFF);
  final column = target <= 1 ? 0 : scan(target: target - 1);
  final position = doc.positionOffset(line, column);
  return GotoPosition(
      offsetUtf16: position.offsetUtf16,
      line: position.line,
      column: position.character);
}

int _lineForOffset(AlulaDoc doc, int offset, int lineCount) {
  var lower = 0;
  var upper = lineCount;
  while (lower < upper) {
    final middle = lower + (upper - lower) ~/ 2;
    if (doc.lineOffset(middle).offsetUtf16 <= offset) {
      lower = middle + 1;
    } else {
      upper = middle;
    }
  }
  return (lower - 1).clamp(0, lineCount - 1).toInt();
}

String _readLineContent(
  AlulaDoc doc,
  DocumentLineBoundary boundary,
  int lineLength,
) {
  if (lineLength == 0) return '';
  if (lineLength > maxDocReadRangeUtf16) {
    throw const FormatException(
      'Cannot resolve a line longer than $maxDocReadRangeUtf16 UTF-16 units yet',
    );
  }
  final range = doc.readRange(
    boundary.startUtf16,
    maxLenUtf16: lineLength,
  );
  if (range.startUtf16 != boundary.startUtf16 ||
      range.endUtf16 < boundary.endUtf16) {
    throw const FormatException('Could not read the selected line');
  }
  return range.text;
}

/// Dart's int.tryParse is stricter than JavaScript parseInt. The pinned
/// provider accepts the numeric prefix and ignores trailing input.
int? _parseIntPrefix(String value) {
  final match = RegExp(r'^[+-]?\d+').firstMatch(value);
  return match == null ? null : int.tryParse(match.group(0)!);
}

int _sign(int value) => value < 0
    ? -1
    : value > 0
        ? 1
        : 0;

/// CursorColumns.columnFromVisibleColumn, retaining UTF-16 offsets.
int _columnFromVisibleColumn(
  String line,
  int visibleColumn, {
  required int tabSize,
}) {
  if (visibleColumn <= 0) return 0;

  var beforeVisible = 0;
  var beforeOffset = 0;
  for (final grapheme in line.characters) {
    final afterVisible = _nextVisibleColumn(
      grapheme,
      beforeVisible,
      tabSize,
    );
    final afterOffset = beforeOffset + grapheme.length;
    if (afterVisible >= visibleColumn) {
      final beforeDelta = visibleColumn - beforeVisible;
      final afterDelta = afterVisible - visibleColumn;
      return afterDelta < beforeDelta ? afterOffset : beforeOffset;
    }
    beforeVisible = afterVisible;
    beforeOffset = afterOffset;
  }
  return line.length;
}

int _nextVisibleColumn(String grapheme, int visibleColumn, int tabSize) {
  final rune = grapheme.runes.first;
  if (rune == 0x09) {
    return visibleColumn + tabSize - visibleColumn % tabSize;
  }
  return visibleColumn +
      (_isFullWidthCodePoint(rune) || _isEmojiImprecise(rune) ? 2 : 1);
}

bool _isFullWidthCodePoint(int rune) =>
    (rune >= 0x2E80 && rune <= 0xD7AF) ||
    (rune >= 0xF900 && rune <= 0xFAFF) ||
    (rune >= 0xFF01 && rune <= 0xFF5E) ||
    (rune >= 0xFFE0 && rune <= 0xFFE6);

bool _isEmojiImprecise(int rune) =>
    (rune >= 0x1F1E6 && rune <= 0x1F1FF) ||
    rune == 8986 ||
    rune == 8987 ||
    rune == 9200 ||
    rune == 9203 ||
    (rune >= 9728 && rune <= 10175) ||
    rune == 11088 ||
    rune == 11093 ||
    (rune >= 127744 && rune <= 128591) ||
    (rune >= 128640 && rune <= 128764) ||
    (rune >= 128992 && rune <= 129008) ||
    (rune >= 129280 && rune <= 129535) ||
    (rune >= 129648 && rune <= 129782);
