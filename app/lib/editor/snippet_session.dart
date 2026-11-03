import 'package:flutter/services.dart';

import '../bridge/alula_core.dart';
import 'snippet_template.dart';

/// Tracks one active snippet's tabstops in absolute document UTF-16 offsets.
class SnippetSession {
  SnippetSession(
    SnippetExpansion expansion, {
    required int documentOffsetUtf16,
    required this.version,
    this.lineLeadingWhitespace = '',
  })  : _tabstopOrder = expansion.tabstopOrder,
        _rangesByIndex = _groupRanges(expansion, documentOffsetUtf16),
        _currentIndex = expansion.tabstopOrder.first;

  final List<int> _tabstopOrder;
  final Map<int, List<SnippetPlaceholderRange>> _rangesByIndex;
  int _currentIndex;

  /// The Rust document version whose coordinates these ranges describe.
  int version;

  /// Whitespace before the snippet on its initial line, used by multiline
  /// placeholder transforms to align continuation lines.
  final String lineLeadingWhitespace;

  int get currentTabstop => _currentIndex;
  bool get isAtFinalTabstop => _currentIndex == 0;
  bool get canMoveNext =>
      _tabstopOrder.indexOf(_currentIndex) < _tabstopOrder.length - 1;
  bool get canMovePrevious => _tabstopOrder.indexOf(_currentIndex) > 0;

  List<SnippetPlaceholderRange> get currentRanges =>
      List.unmodifiable(_rangesByIndex[_currentIndex] ?? const []);

  /// The active occurrence's choice, when the first range is a TextMate choice.
  SnippetPlaceholderRange? get activeChoiceRange {
    final ranges = currentRanges;
    if (ranges.isEmpty || ranges.first.choice == null) return null;
    return ranges.first;
  }

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
  /// By default each placeholder in the active group must receive the same
  /// edit. Placeholder transforms may set [allowPartialActiveGroup] because
  /// each transformed mirror can produce a different replacement. An edit
  /// crossing a placeholder boundary still rejects the session.
  bool applyOperations(
    List<TextOp> operations, {
    required int nextVersion,
    bool allowPartialActiveGroup = false,
  }) {
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
        final isAncestorOfActive = !isActiveGroup &&
            currentRanges.any(
              (active) => active.ancestorOccurrenceIds.contains(
                range.occurrenceId,
              ),
            );
        final isDescendantOfActive = !isActiveGroup &&
            currentRanges.any(
              (active) =>
                  active.occurrenceId != range.occurrenceId &&
                  range.ancestorOccurrenceIds.contains(active.occurrenceId),
            );
        if (isAncestorOfActive || isDescendantOfActive) {
          final nestedRange = _trackNestedRange(
            range,
            edits,
            includeBoundaryInsertions: isAncestorOfActive,
          );
          if (nestedRange == null) return false;
          ranges.add(nestedRange);
          continue;
        }
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
        if (isActiveGroup && !touched && !allowPartialActiveGroup) {
          return false;
        }
        if (touched) touchedActiveRanges++;
        final start = range.startUtf16 + shiftBefore;
        final end = range.endUtf16 + shiftBefore + deltaInside;
        if (start < 0 || end < start) return false;
        ranges.add(SnippetPlaceholderRange(
          index: range.index,
          startUtf16: start,
          endUtf16: end,
          choice: range.choice,
          occurrenceId: range.occurrenceId,
          ancestorOccurrenceIds: range.ancestorOccurrenceIds,
          transform: range.transform,
        ));
      }
      updated[entry.key] = ranges;
    }

    if (allowPartialActiveGroup
        ? touchedActiveRanges == 0
        : touchedActiveRanges != currentRanges.length) {
      return false;
    }
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
            choice: range.choice,
            occurrenceId: range.occurrenceId,
            ancestorOccurrenceIds: range.ancestorOccurrenceIds,
            transform: range.transform,
          ));
    }
    return result;
  }
}

SnippetPlaceholderRange? _trackNestedRange(
  SnippetPlaceholderRange range,
  List<_SnippetEditBatch> edits, {
  required bool includeBoundaryInsertions,
}) {
  final isEmpty = range.startUtf16 == range.endUtf16;
  final start = _transformOffsetThroughEdits(
    range.startUtf16,
    edits,
    rightAffinity: !includeBoundaryInsertions,
  );
  final end = _transformOffsetThroughEdits(
    range.endUtf16,
    edits,
    rightAffinity: includeBoundaryInsertions || isEmpty,
  );
  if (start < 0 || end < start) return null;
  return SnippetPlaceholderRange(
    index: range.index,
    startUtf16: start,
    endUtf16: end,
    choice: range.choice,
    occurrenceId: range.occurrenceId,
    ancestorOccurrenceIds: range.ancestorOccurrenceIds,
    transform: range.transform,
  );
}

int _transformOffsetThroughEdits(
  int offset,
  List<_SnippetEditBatch> edits, {
  required bool rightAffinity,
}) {
  var shiftBefore = 0;
  for (final edit in edits) {
    final start = edit.offsetUtf16;
    final end = edit.deleteEndUtf16;
    final delta = edit.insertedUtf16 - edit.deletedUtf16;
    if (offset < start) break;
    if (offset > end || (offset == end && end > start)) {
      shiftBefore += delta;
      continue;
    }
    if (start == end) {
      return offset + shiftBefore + (rightAffinity ? edit.insertedUtf16 : 0);
    }
    if (offset == end) {
      return start + shiftBefore + edit.insertedUtf16;
    }
    return start + shiftBefore + (rightAffinity ? edit.insertedUtf16 : 0);
  }
  return offset + shiftBefore;
}

class _SnippetEditBatch {
  _SnippetEditBatch(this.offsetUtf16);

  final int offsetUtf16;
  int deletedUtf16 = 0;
  int insertedUtf16 = 0;

  int get deleteEndUtf16 => offsetUtf16 + deletedUtf16;
}
