// Code-OSS default indentation helpers for the workbench edit commands.
// Offsets supplied by callers remain UTF-16 offsets; these helpers only
// inspect a single already-bounded line prefix.
import 'package:characters/characters.dart';

int indentationVisibleColumn(String text, {int tabSize = 4}) {
  if (tabSize < 1 || tabSize > 32) {
    throw RangeError.range(tabSize, 1, 32, 'tabSize');
  }
  var column = 0;
  for (final grapheme in text.characters) {
    final rune = grapheme.runes.first;
    if (rune == 0x09) {
      column += tabSize - column % tabSize;
    } else {
      column += _isFullWidthCodePoint(rune) || _isEmojiImprecise(rune) ? 2 : 1;
    }
  }
  return column;
}

/// Text inserted by Tab at a caret or over a partial single-line selection.
String indentationTabText(
  String prefix, {
  int tabSize = 4,
  int indentSize = 4,
  bool insertSpaces = true,
}) {
  if (!insertSpaces) return '\t';
  _validateIndentSize(indentSize);
  final column = indentationVisibleColumn(prefix, tabSize: tabSize);
  final count = indentSize - column % indentSize;
  return ' ' * count;
}

/// The new leading whitespace for a line-indent or line-outdent command.
/// Returns null when an outdent has no indentation to remove.
String? shiftLineIndentation(
  String line, {
  required bool outdent,
  int tabSize = 4,
  int indentSize = 4,
  bool insertSpaces = true,
}) {
  _validateIndentSize(indentSize);
  final prefixLength = leadingIndentLength(line);
  if (outdent && prefixLength == 0) return null;

  final step = insertSpaces ? indentSize : tabSize;
  if (step < 1 || step > 32) {
    throw RangeError.range(step, 1, 32, 'tabSize/indentSize');
  }
  final column = indentationVisibleColumn(
    line.substring(0, prefixLength),
    tabSize: tabSize,
  );
  final target = outdent
      ? ((column - 1).clamp(0, column) ~/ step) * step
      : (column ~/ step + 1) * step;
  return indentationString(target,
      tabSize: tabSize, insertSpaces: insertSpaces);
}

int leadingIndentLength(String line) {
  var offset = 0;
  while (offset < line.length) {
    final unit = line.codeUnitAt(offset);
    if (unit != 0x20 && unit != 0x09) break;
    offset++;
  }
  return offset;
}

String indentationString(
  int visibleColumns, {
  int tabSize = 4,
  bool insertSpaces = true,
}) {
  if (visibleColumns <= 0) return '';
  return insertSpaces
      ? ' ' * visibleColumns
      : '\t' * (visibleColumns ~/ tabSize);
}

void _validateIndentSize(int indentSize) {
  if (indentSize < 1 || indentSize > 32) {
    throw RangeError.range(indentSize, 1, 32, 'indentSize');
  }
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
