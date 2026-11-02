import 'package:flutter/services.dart';

import '../bridge/alula_core.dart';
import 'snippet_template.dart';

/// Tracks one active snippet's tabstops in absolute document UTF-16 offsets.
class SnippetSession {
  SnippetSession(
    SnippetExpansion expansion, {
    required int documentOffsetUtf16,
    required this.version,
  })  : _tabstopOrder = expansion.tabstopOrder,
        _rangesByIndex = _groupRanges(expansion, documentOffsetUtf16),
        _currentIndex = expansion.tabstopOrder.first;

  final List<int> _tabstopOrder;
  final Map<int, List<SnippetPlaceholderRange>> _rangesByIndex;
  int _currentIndex;

  /// The Rust document version whose coordinates these ranges describe.
  int version;

  int get currentTabstop => _currentIndex;
  bool get isAtFinalTabstop => _currentIndex == 0;
  bool get canMoveNext =>
      _tabstopOrder.indexOf(_currentIndex) < _tabstopOrder.length - 1;
  bool get canMovePrevious => _tabstopOrder.indexOf(_currentIndex) > 0;

  List<SnippetPlaceholderRange> get currentRanges =>
      List.unmodifiable(_rangesByIndex[_currentIndex] ?? const []);

  List<TextSelection> get currentSelections => [
        for (final range in currentRanges)
          TextSelection(
            baseOffset: range.startUtf16,
            extentOffset: range.endUtf16,
          ),
      ];

  bool moveNext() {
    if (!canMoveNext) return false;
    _currentIndex = _tabstopOrder[_tabstopOrder.indexOf(_currentIndex) + 1];
    return true;
  }

  bool movePrevious() {
    if (!canMovePrevious) return false;
    _currentIndex = _tabstopOrder[_tabstopOrder.indexOf(_currentIndex) - 1];
    return true;
  }

  /// Builds equivalent edits for every mirror from one primary input edit.
  ///
  /// The Rust input diff can combine disjoint mirror edits into a larger
  /// replacement span. This plan retains the precise per-placeholder edits
  /// from Flutter's primary input event so text between mirrors stays intact
  /// in the tracked ranges.
  List<TextOp>? operationsForMirroredEdit({
    required TextSelection primarySelection,
    required int editStartUtf16,
    required int deletedUtf16,
    required String insertedText,
  }) {
    final ranges = currentRanges;
    final primaryRangeIndex = ranges.indexWhere((range) =>
        primarySelection.start >= range.startUtf16 &&
        primarySelection.end <= range.endUtf16);
    if (primaryRangeIndex < 0) return null;

    final primaryRange = ranges[primaryRangeIndex];
    final relativeStart = editStartUtf16 - primaryRange.startUtf16;
    if (relativeStart < 0 ||
        relativeStart + deletedUtf16 > primaryRange.lengthUtf16) {
      return null;
    }

    final operations = <TextOp>[];
    for (final range in ranges) {
      final start = range.startUtf16 + relativeStart;
      if (relativeStart + deletedUtf16 > range.lengthUtf16) return null;
      if (deletedUtf16 > 0) {
        operations.add(TextOp.delete(start, deletedUtf16));
      }
      if (insertedText.isNotEmpty) {
        operations.add(TextOp.insert(start, insertedText));
      }
    }
    return List.unmodifiable(operations);
  }

  /// Mirrors a manual selection or caret move to all linked placeholders.
  /// Returns `null` when the primary selection is outside the active tabstop.
  List<TextSelection>? mirrorSelection(TextSelection primary) {
    final ranges = currentRanges;
    final selected = ranges.indexWhere((range) {
      return primary.start >= range.startUtf16 && primary.end <= range.endUtf16;
    });
    if (selected < 0) return null;

    final anchor = ranges[selected];
    final relativeBase = primary.baseOffset - anchor.startUtf16;
    final relativeExtent = primary.extentOffset - anchor.startUtf16;
    final result = <TextSelection>[];
    for (var index = 0; index < ranges.length; index++) {
      if (index == selected) continue;
      final range = ranges[index];
      if (relativeBase < 0 ||
          relativeExtent < 0 ||
          relativeBase > range.lengthUtf16 ||
          relativeExtent > range.lengthUtf16) {
        return null;
      }
      result.add(TextSelection(
        baseOffset: range.startUtf16 + relativeBase,
        extentOffset: range.startUtf16 + relativeExtent,
        affinity: primary.affinity,
        isDirectional: primary.isDirectional,
      ));
    }
    return result;
  }

  /// Applies a committed Rust input batch to tracked placeholder ranges.
  ///
  /// Each placeholder in the active group must receive the same edit. If an
  /// edit crosses a placeholder boundary or misses a mirror, the session is
  /// rejected so a later Tab cannot navigate to stale document offsets.
  bool applyOperations(List<TextOp> operations, {required int nextVersion}) {
    if (operations.isEmpty) {
      version = nextVersion;
      return true;
    }

    final grouped = <int, _SnippetEditBatch>{};
    for (final operation in operations) {
      final batch = grouped.putIfAbsent(
        operation.offsetUtf16,
        () => _SnippetEditBatch(operation.offsetUtf16),
      );
      if (operation.type == OpType.insert) {
        batch.insertedUtf16 += operation.text!.length;
      } else {
        batch.deletedUtf16 += operation.lenUtf16!;
      }
    }
    final edits = grouped.values.toList()
      ..sort((left, right) => left.offsetUtf16.compareTo(right.offsetUtf16));
    for (var index = 1; index < edits.length; index++) {
      if (edits[index].offsetUtf16 < edits[index - 1].deleteEndUtf16) {
        return false;
      }
    }

    var touchedActiveRanges = 0;
    final updated = <int, List<SnippetPlaceholderRange>>{};
    for (final entry in _rangesByIndex.entries) {
      final ranges = <SnippetPlaceholderRange>[];
      for (final range in entry.value) {
        var shiftBefore = 0;
        var deltaInside = 0;
        var touched = false;
        final isActiveGroup = entry.key == _currentIndex;
        for (final edit in edits) {
          final editDelta = edit.insertedUtf16 - edit.deletedUtf16;
          if (isActiveGroup &&
              edit.offsetUtf16 >= range.startUtf16 &&
              edit.offsetUtf16 <= range.endUtf16 &&
              edit.deleteEndUtf16 <= range.endUtf16) {
            deltaInside += editDelta;
            touched = true;
          } else if (edit.deleteEndUtf16 <= range.startUtf16 &&
              edit.offsetUtf16 <= range.startUtf16) {
            shiftBefore += editDelta;
          } else if (!isActiveGroup &&
              edit.offsetUtf16 == range.startUtf16 &&
              edit.deletedUtf16 == 0) {
            // An insertion at an inactive placeholder's leading edge belongs
            // to the preceding edit; keep that placeholder after the text.
            shiftBefore += editDelta;
          } else if (edit.offsetUtf16 >= range.endUtf16) {
            // The edit follows this placeholder.
          } else {
            return false;
          }
        }
        if (isActiveGroup && !touched) return false;
        if (touched) touchedActiveRanges++;
        final start = range.startUtf16 + shiftBefore;
        final end = range.endUtf16 + shiftBefore + deltaInside;
        if (start < 0 || end < start) return false;
        ranges.add(SnippetPlaceholderRange(
          index: range.index,
          startUtf16: start,
          endUtf16: end,
        ));
      }
      updated[entry.key] = ranges;
    }

    if (touchedActiveRanges != currentRanges.length) return false;
    _rangesByIndex
      ..clear()
      ..addAll(updated);
    version = nextVersion;
    return true;
  }

  static Map<int, List<SnippetPlaceholderRange>> _groupRanges(
    SnippetExpansion expansion,
    int documentOffsetUtf16,
  ) {
    final result = <int, List<SnippetPlaceholderRange>>{};
    for (final range in expansion.placeholders) {
      result.putIfAbsent(range.index, () => []).add(SnippetPlaceholderRange(
            index: range.index,
            startUtf16: documentOffsetUtf16 + range.startUtf16,
            endUtf16: documentOffsetUtf16 + range.endUtf16,
          ));
    }
    return result;
  }
}

class _SnippetEditBatch {
  _SnippetEditBatch(this.offsetUtf16);

  final int offsetUtf16;
  int deletedUtf16 = 0;
  int insertedUtf16 = 0;

  int get deleteEndUtf16 => offsetUtf16 + deletedUtf16;
}
