import 'package:flutter/services.dart';

import '../bridge/alula_core.dart';
import 'text_diff.dart';

final RegExp _markCharacter = RegExp(r'^\p{M}$', unicode: true);

/// A text edit produced by the primary Flutter caret, mirrored to every
/// secondary selection before the bounded input window is sent to Rust.
class MultiSelectionEditResult {
  const MultiSelectionEditResult({
    required this.value,
    required this.selections,
    required this.changed,
  });

  final TextEditingValue value;
  final List<TextSelection> selections;
  final bool changed;
}

/// Flutter input formatter that mirrors ordinary typing/deletion to secondary
/// carets while preserving the platform client's primary selection.
class MultiSelectionTextInputFormatter extends TextInputFormatter {
  MultiSelectionTextInputFormatter({
    required this.additionalSelections,
    required this.onSelectionsChanged,
    this.onSelectionChanged,
    this.onCrossWindowTextInput,
    this.onTextChanged,
  });

  final List<TextSelection> Function() additionalSelections;
  final ValueChanged<List<TextSelection>> onSelectionsChanged;
  final void Function(TextEditingValue oldValue, TextEditingValue newValue)?
      onSelectionChanged;
  final TextEditingValue? Function(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  )? onCrossWindowTextInput;
  final void Function(
    TextEditingValue oldValue,
    TextEditingValue newValue,
    TextEditingValue formattedValue,
  )? onTextChanged;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
      return newValue;
    }
    if (oldValue.text == newValue.text &&
        oldValue.selection != newValue.selection) {
      onSelectionChanged?.call(oldValue, newValue);
      return newValue;
    }
    final textChanged = oldValue.text != newValue.text;
    if (textChanged) {
      final crossWindowValue = onCrossWindowTextInput?.call(oldValue, newValue);
      if (crossWindowValue != null) return crossWindowValue;
    }
    final result = applyMultiSelectionEdit(
      oldValue: oldValue,
      newValue: newValue,
      additionalSelections: additionalSelections(),
    );
    if (textChanged) onTextChanged?.call(oldValue, newValue, result.value);
    if (result.changed) onSelectionsChanged(result.selections);
    return result.value;
  }
}

/// Applies one Flutter text-input change to a normalized selection set.
/// Offsets are UTF-16 code units, matching Flutter and the Rust FFI contract.
MultiSelectionEditResult applyMultiSelectionEdit({
  required TextEditingValue oldValue,
  required TextEditingValue newValue,
  required List<TextSelection> additionalSelections,
}) {
  if (additionalSelections.isEmpty ||
      oldValue.text == newValue.text ||
      newValue.composing.isValid && !newValue.composing.isCollapsed) {
    return MultiSelectionEditResult(
      value: newValue,
      selections: List.unmodifiable(additionalSelections),
      changed: false,
    );
  }

  final localOps = diffToOps(oldValue.text, newValue.text);
  if (localOps.isEmpty) {
    return MultiSelectionEditResult(
      value: newValue,
      selections: List.unmodifiable(additionalSelections),
      changed: false,
    );
  }

  final start = localOps.first.offsetUtf16;
  final deletedLength = localOps
      .where((op) => op.type == OpType.delete)
      .fold<int>(0, (sum, op) => sum + (op.lenUtf16 ?? 0));
  final inserted = localOps
      .where((op) => op.type == OpType.insert)
      .map((op) => op.text ?? '')
      .join();
  final primaryRange = _SelectionRange(
    start,
    start + deletedLength,
    primary: true,
  );
  final backwardsDelete = oldValue.selection.isCollapsed &&
      deletedLength > 0 &&
      start < oldValue.selection.extentOffset;
  final edits = <_SelectionRange>[primaryRange];

  for (final selection in additionalSelections) {
    final base = _clamp(selection.baseOffset, oldValue.text.length);
    final extent = _clamp(selection.extentOffset, oldValue.text.length);
    final low = base < extent ? base : extent;
    final high = base < extent ? extent : base;
    if (low != high) {
      edits.add(_SelectionRange(low, high));
    } else if (oldValue.selection.isCollapsed && deletedLength > 0) {
      final caret = low;
      final deleteStart = backwardsDelete
          ? _previousGraphemeBoundary(oldValue.text, caret)
          : caret;
      final deleteEnd =
          backwardsDelete ? caret : _nextGraphemeBoundary(oldValue.text, caret);
      edits.add(_SelectionRange(deleteStart, deleteEnd));
    } else {
      edits.add(_SelectionRange(low, low));
    }
  }

  final merged = _mergeEditRanges(edits);
  var transformed = oldValue.text;
  for (final edit in merged.reversed) {
    transformed = transformed.replaceRange(edit.start, edit.end, inserted);
  }

  var shiftBeforePrimary = 0;
  _SelectionRange? primaryEdit;
  for (final edit in merged) {
    if (edit.primary) {
      primaryEdit = edit;
      break;
    }
    if (edit.end <= primaryRange.start) {
      shiftBeforePrimary += inserted.length - (edit.end - edit.start);
    }
  }
  final primaryCaret =
      (primaryEdit?.start ?? start) + shiftBeforePrimary + inserted.length;

  var shift = 0;
  final mapped = <(int, bool)>[];
  for (final edit in merged) {
    final newStart = edit.start + shift;
    mapped.add((newStart + inserted.length, edit.primary));
    shift += inserted.length - (edit.end - edit.start);
  }
  final additional = mapped
      .where((entry) => !entry.$2)
      .map((entry) => TextSelection.collapsed(offset: entry.$1))
      .toList();
  final value = newValue.copyWith(
    text: transformed,
    selection: TextSelection.collapsed(
      offset: primaryCaret.clamp(0, transformed.length).toInt(),
      affinity: newValue.selection.affinity,
    ),
    composing: TextRange.empty,
  );
  return MultiSelectionEditResult(
    value: value,
    selections: List.unmodifiable(additional),
    changed: true,
  );
}

/// Applies a clipboard paste to a set of local UTF-16 selections.
///
/// When the clipboard has one line per selection, each line is inserted into
/// its corresponding selection. Otherwise the complete clipboard payload is
/// repeated at every selection, matching editor multi-cursor paste behavior.
/// The first selection is the primary selection and remains the platform
/// client's caret after the edit.
MultiSelectionEditResult applyDistributedMultiSelectionPaste({
  required TextEditingValue oldValue,
  required List<TextSelection> selections,
  required String clipboardText,
}) {
  final normalized = normalizeSelectionSet(selections);
  if (normalized.length < 2) {
    return MultiSelectionEditResult(
      value: oldValue,
      selections: const [],
      changed: false,
    );
  }

  final lines = clipboardText.split(RegExp(r'\r\n|\n|\r'));
  final distributeLines = lines.length == normalized.length;
  final edits = <_PasteRange>[];
  for (var index = 0; index < normalized.length; index++) {
    final selection = normalized[index];
    final base = _clamp(selection.baseOffset, oldValue.text.length);
    final extent = _clamp(selection.extentOffset, oldValue.text.length);
    edits.add(_PasteRange(
      base < extent ? base : extent,
      base < extent ? extent : base,
      distributeLines ? lines[index] : clipboardText,
      index == 0,
    ));
  }
  edits.sort((a, b) => a.start.compareTo(b.start));

  var text = oldValue.text;
  for (final edit in edits.reversed) {
    text = text.replaceRange(edit.start, edit.end, edit.text);
  }

  var shift = 0;
  var primaryCaret = 0;
  final secondaryCarets = <TextSelection>[];
  for (final edit in edits) {
    final caret = edit.start + shift + edit.text.length;
    if (edit.primary) {
      primaryCaret = caret;
    } else {
      secondaryCarets.add(TextSelection.collapsed(offset: caret));
    }
    shift += edit.text.length - (edit.end - edit.start);
  }

  return MultiSelectionEditResult(
    value: oldValue.copyWith(
      text: text,
      selection: TextSelection.collapsed(
        offset: primaryCaret.clamp(0, text.length).toInt(),
        affinity: oldValue.selection.affinity,
      ),
      composing: TextRange.empty,
    ),
    selections: List.unmodifiable(secondaryCarets),
    changed: text != oldValue.text,
  );
}

/// Merges duplicate or intersecting selections while keeping the primary first.
List<TextSelection> normalizeSelectionSet(List<TextSelection> selections) {
  if (selections.isEmpty) return const [];
  final entries = <_IndexedSelection>[];
  for (var i = 0; i < selections.length; i++) {
    final selection = selections[i];
    final low = selection.baseOffset < selection.extentOffset
        ? selection.baseOffset
        : selection.extentOffset;
    final high = selection.baseOffset < selection.extentOffset
        ? selection.extentOffset
        : selection.baseOffset;
    entries.add(_IndexedSelection(low, high, i == 0, selection));
  }
  entries.sort((a, b) =>
      a.start != b.start ? a.start.compareTo(b.start) : a.end.compareTo(b.end));
  final merged = <_IndexedSelection>[];
  for (final entry in entries) {
    if (merged.isEmpty) {
      merged.add(entry);
      continue;
    }
    final previous = merged.last;
    final duplicateCaret = previous.start == previous.end &&
        entry.start == entry.end &&
        previous.start == entry.start;
    final pointInsidePrevious = entry.start == entry.end &&
        entry.start >= previous.start &&
        entry.start <= previous.end;
    final previousPointInsideEntry = previous.start == previous.end &&
        previous.start >= entry.start &&
        previous.start <= entry.end;
    if (entry.start < previous.end ||
        duplicateCaret ||
        pointInsidePrevious ||
        previousPointInsideEntry) {
      final containsPrimary = previous.primary || entry.primary;
      final source = previous.primary ? previous.selection : entry.selection;
      final low = previous.start < entry.start ? previous.start : entry.start;
      final high = previous.end > entry.end ? previous.end : entry.end;
      merged[merged.length - 1] = _IndexedSelection(
        low,
        high,
        containsPrimary,
        TextSelection(
          baseOffset: source.baseOffset <= source.extentOffset ? low : high,
          extentOffset: source.baseOffset <= source.extentOffset ? high : low,
          affinity: source.affinity,
          isDirectional: source.isDirectional,
        ),
      );
    } else {
      merged.add(entry);
    }
  }
  final primary = merged.indexWhere((entry) => entry.primary);
  if (primary > 0) {
    final entry = merged.removeAt(primary);
    merged.insert(0, entry);
  }
  return List.unmodifiable(merged.map((entry) => entry.selection));
}

/// A rectangular selection expressed in UTF-16 line and column coordinates.
class ColumnSelectionState {
  const ColumnSelectionState({
    required this.anchorLine,
    required this.anchorColumn,
    required this.activeLine,
    required this.activeColumn,
  });

  final int anchorLine;
  final int anchorColumn;
  final int activeLine;
  final int activeColumn;

  ColumnSelectionState move({int lines = 0, int columns = 0}) =>
      ColumnSelectionState(
        anchorLine: anchorLine,
        anchorColumn: anchorColumn,
        activeLine: activeLine + lines,
        activeColumn: (activeColumn + columns).clamp(0, 0x7fffffff).toInt(),
      );
}

/// Bounded history for cursor/selection navigation, independent of text undo.
class SelectionHistory {
  SelectionHistory({this.capacity = 64});

  static const int maxSelectionsPerSnapshot = 512;
  static const int maxRetainedSelections = 4096;

  final int capacity;
  final List<List<TextSelection>> _undo = [];
  final List<List<TextSelection>> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void record(List<TextSelection> selectionSet) {
    if (selectionSet.length > maxSelectionsPerSnapshot) {
      clear();
      return;
    }
    final snapshot = List<TextSelection>.unmodifiable(selectionSet);
    if (_undo.isNotEmpty && _sameSet(_undo.last, snapshot)) return;
    _undo.add(snapshot);
    _redo.clear();
    _trim();
  }

  List<TextSelection>? undo(List<TextSelection> current) {
    if (_undo.isEmpty) return null;
    if (current.length <= maxSelectionsPerSnapshot) {
      _redo.add(List<TextSelection>.unmodifiable(current));
      _trim();
    }
    return _undo.removeLast();
  }

  List<TextSelection>? redo(List<TextSelection> current) {
    if (_redo.isEmpty) return null;
    if (current.length <= maxSelectionsPerSnapshot) {
      _undo.add(List<TextSelection>.unmodifiable(current));
      _trim();
    }
    return _redo.removeLast();
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }

  void _trim() {
    while (_undo.length > capacity || _redo.length > capacity) {
      if (_undo.isNotEmpty) {
        _undo.removeAt(0);
      } else {
        _redo.removeAt(0);
      }
    }
    int retained() => [
          ..._undo,
          ..._redo,
        ].fold<int>(0, (sum, state) => sum + state.length);
    while (retained() > maxRetainedSelections) {
      if (_undo.isNotEmpty) {
        _undo.removeAt(0);
      } else if (_redo.isNotEmpty) {
        _redo.removeAt(0);
      } else {
        break;
      }
    }
  }

  static bool _sameSet(List<TextSelection> a, List<TextSelection> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Builds one selection for each row in a rectangular range. The active row
/// is first so the platform input client retains a meaningful primary caret.
List<TextSelection> columnSelectionsForText(
  String text,
  ColumnSelectionState state,
) {
  final lines = _lineRanges(text);
  if (lines.isEmpty) return const [];
  final first = state.anchorLine.clamp(0, lines.length - 1).toInt();
  final last = state.activeLine.clamp(0, lines.length - 1).toInt();
  final lowLine = first < last ? first : last;
  final highLine = first < last ? last : first;
  final lowColumn = state.anchorColumn < state.activeColumn
      ? state.anchorColumn
      : state.activeColumn;
  final highColumn = state.anchorColumn < state.activeColumn
      ? state.activeColumn
      : state.anchorColumn;
  final selections = <(int, TextSelection)>[];
  for (var line = lowLine; line <= highLine; line++) {
    final range = lines[line];
    final start = _safeGraphemeBoundary(
      text,
      (range.$1 + lowColumn).clamp(range.$1, range.$2).toInt(),
      roundUp: false,
    );
    final end = lowColumn == highColumn
        ? start
        : _safeGraphemeBoundary(
            text,
            (range.$1 + highColumn).clamp(range.$1, range.$2).toInt(),
            roundUp: true,
          );
    selections.add((line, TextSelection(baseOffset: start, extentOffset: end)));
  }
  final activeIndex = selections.indexWhere((entry) => entry.$1 == last);
  if (activeIndex > 0) {
    final active = selections.removeAt(activeIndex);
    selections.insert(0, active);
  }
  return List.unmodifiable(selections.map((entry) => entry.$2));
}

/// Returns the line and UTF-16 column for a bounded-window offset.
(int, int) lineAndColumnAt(String text, int offset) {
  final clamped = _clamp(offset, text.length);
  final lines = _lineRanges(text);
  var line = 0;
  for (var i = 0; i < lines.length; i++) {
    if (clamped <= lines[i].$2 || i == lines.length - 1) {
      line = i;
      break;
    }
  }
  final start = lines[line].$1;
  return (line, (clamped - start).clamp(0, lines[line].$2 - start).toInt());
}

/// Returns the UTF-16 offset at [line]/[column], clamped to visible line text.
int lineOffsetAtColumn(String text, int line, int column) {
  final lines = _lineRanges(text);
  if (lines.isEmpty) return 0;
  final selectedLine = line.clamp(0, lines.length - 1).toInt();
  final range = lines[selectedLine];
  return _safeGraphemeBoundary(
    text,
    (range.$1 + column.clamp(0, range.$2 - range.$1)).toInt(),
    roundUp: false,
  );
}

/// Maps a UTF-16 offset from [before] into [after] through their single diff.
/// Offsets inside replaced text collapse to the replacement's end.
int mapOffsetThroughTextChange(String before, String after, int offset) {
  return mapOffsetsThroughTextChange(before, after, [offset]).first;
}

/// Maps many offsets through one bounded-window diff without recalculating it
/// for each secondary selection.
List<int> mapOffsetsThroughTextChange(
  String before,
  String after,
  List<int> offsets,
) {
  if (offsets.isEmpty) return const [];
  final ops = diffToOps(before, after);
  if (ops.isEmpty) {
    return List.unmodifiable(
        offsets.map((offset) => _clamp(offset, before.length)));
  }
  final start = ops.first.offsetUtf16;
  final deleted = ops
      .where((op) => op.type == OpType.delete)
      .fold<int>(0, (sum, op) => sum + (op.lenUtf16 ?? 0));
  final inserted = ops
      .where((op) => op.type == OpType.insert)
      .fold<int>(0, (sum, op) => sum + (op.text?.length ?? 0));
  return List.unmodifiable(offsets.map((offset) {
    final clamped = _clamp(offset, before.length);
    if (clamped <= start) return clamped;
    if (clamped >= start + deleted) {
      return (clamped + inserted - deleted).clamp(0, after.length).toInt();
    }
    return (start + inserted).clamp(0, after.length).toInt();
  }));
}

List<(int, int)> _lineRanges(String text) {
  final ranges = <(int, int)>[];
  var start = 0;
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) != 0x0A) continue;
    var contentEnd = i;
    if (contentEnd > start && text.codeUnitAt(contentEnd - 1) == 0x0D) {
      contentEnd--;
    }
    ranges.add((start, contentEnd));
    start = i + 1;
  }
  ranges.add((start, text.length));
  return ranges;
}

/// UTF-16 start/end pairs for each logical line, excluding CR in CRLF.
List<(int, int)> lineContentRangesForText(String text) =>
    List.unmodifiable(_lineRanges(text));

List<_SelectionRange> _mergeEditRanges(List<_SelectionRange> edits) {
  edits.sort((a, b) =>
      a.start != b.start ? a.start.compareTo(b.start) : a.end.compareTo(b.end));
  final merged = <_SelectionRange>[];
  for (final edit in edits) {
    if (merged.isEmpty) {
      merged.add(edit);
      continue;
    }
    final previous = merged.last;
    final sameInsertion = previous.start == previous.end &&
        edit.start == edit.end &&
        previous.start == edit.start;
    if (edit.start < previous.end || sameInsertion) {
      merged[merged.length - 1] = _SelectionRange(
        previous.start,
        previous.end > edit.end ? previous.end : edit.end,
        primary: previous.primary || edit.primary,
      );
    } else {
      merged.add(edit);
    }
  }
  return merged;
}

int _clamp(int value, int length) => value.clamp(0, length).toInt();

int _safeBoundary(String text, int offset, {required bool roundUp}) {
  if (offset <= 0 || offset >= text.length) return offset;
  final before = text.codeUnitAt(offset - 1);
  final after = text.codeUnitAt(offset);
  final splitsPair = before >= 0xD800 &&
      before <= 0xDBFF &&
      after >= 0xDC00 &&
      after <= 0xDFFF;
  return splitsPair && roundUp
      ? offset + 1
      : splitsPair
          ? offset - 1
          : offset;
}

int _safeGraphemeBoundary(String text, int offset, {required bool roundUp}) {
  var boundary = _safeBoundary(text, offset, roundUp: roundUp);
  if (roundUp) {
    while (boundary < text.length &&
        _isGraphemeExtender(_codePointAt(text, boundary))) {
      boundary = _nextScalarBoundary(text, boundary);
    }
  } else {
    while (boundary > 0 && _isGraphemeExtender(_codePointAt(text, boundary))) {
      boundary = _previousScalarBoundary(text, boundary);
    }
  }
  return boundary;
}

int previousGraphemeBoundary(String text, int offset) =>
    _previousGraphemeBoundary(text, offset);

int nextGraphemeBoundary(String text, int offset) =>
    _nextGraphemeBoundary(text, offset);

int _previousGraphemeBoundary(String text, int offset) {
  var start = _previousScalarBoundary(text, offset);
  while (start > 0) {
    final current = _codePointAt(text, start);
    final previous = _previousScalarBoundary(text, start);
    final previousCodePoint = _codePointAt(text, previous);
    if (_isGraphemeExtender(current) ||
        current == 0x200D ||
        previousCodePoint == 0x200D) {
      start = previousCodePoint == 0x200D
          ? _previousScalarBoundary(text, previous)
          : previous;
      continue;
    }
    if (_isRegionalIndicator(current) &&
        _isRegionalIndicator(previousCodePoint)) {
      start = previous;
    }
    break;
  }
  return start;
}

int _nextGraphemeBoundary(String text, int offset) {
  if (offset >= text.length) return text.length;
  var end = _nextScalarBoundary(text, offset);
  while (end < text.length) {
    final current = _codePointAt(text, end);
    final previous = _codePointAt(text, _previousScalarBoundary(text, end));
    if (_isGraphemeExtender(current) ||
        previous == 0x200D ||
        current == 0x200D) {
      end = current == 0x200D
          ? _nextScalarBoundary(text, end + 1)
          : _nextScalarBoundary(text, end);
      continue;
    }
    if (_isRegionalIndicator(previous) && _isRegionalIndicator(current)) {
      end = _nextScalarBoundary(text, end);
    }
    break;
  }
  return end;
}

int _previousScalarBoundary(String text, int offset) {
  var start = offset.clamp(0, text.length).toInt() - 1;
  if (start > 0 && _isLowSurrogate(text.codeUnitAt(start))) start--;
  return start.clamp(0, text.length).toInt();
}

int _nextScalarBoundary(String text, int offset) {
  var end = offset.clamp(0, text.length).toInt() + 1;
  if (end < text.length &&
      _isLowSurrogate(text.codeUnitAt(end)) &&
      _isHighSurrogate(text.codeUnitAt(end - 1))) {
    end++;
  }
  return end.clamp(0, text.length).toInt();
}

int _codePointAt(String text, int offset) {
  if (offset < 0 || offset >= text.length) return -1;
  final first = text.codeUnitAt(offset);
  if (_isHighSurrogate(first) &&
      offset + 1 < text.length &&
      _isLowSurrogate(text.codeUnitAt(offset + 1))) {
    return 0x10000 +
        ((first - 0xD800) << 10) +
        (text.codeUnitAt(offset + 1) - 0xDC00);
  }
  return first;
}

bool _isHighSurrogate(int value) => value >= 0xD800 && value <= 0xDBFF;
bool _isLowSurrogate(int value) => value >= 0xDC00 && value <= 0xDFFF;

bool _isGraphemeExtender(int codePoint) {
  if (codePoint < 0 || codePoint > 0x10FFFF) return false;
  final value = codePoint <= 0xFFFF
      ? String.fromCharCode(codePoint)
      : String.fromCharCodes([
          0xD800 + ((codePoint - 0x10000) >> 10),
          0xDC00 + ((codePoint - 0x10000) & 0x3FF),
        ]);
  return _markCharacter.hasMatch(value) ||
      codePoint == 0xFE0E ||
      codePoint == 0xFE0F ||
      (codePoint >= 0x1F3FB && codePoint <= 0x1F3FF);
}

bool _isRegionalIndicator(int codePoint) =>
    codePoint >= 0x1F1E6 && codePoint <= 0x1F1FF;

class _SelectionRange {
  const _SelectionRange(this.start, this.end, {this.primary = false});
  final int start;
  final int end;
  final bool primary;
}

class _PasteRange {
  const _PasteRange(this.start, this.end, this.text, this.primary);

  final int start;
  final int end;
  final String text;
  final bool primary;
}

class _IndexedSelection {
  const _IndexedSelection(this.start, this.end, this.primary, this.selection);
  final int start;
  final int end;
  final bool primary;
  final TextSelection selection;
}
