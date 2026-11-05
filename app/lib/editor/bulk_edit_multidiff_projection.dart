/// Bounded, immutable before/after projections for text-only Bulk Edit previews.
///
/// This module does not mutate documents, read files, or render a Multi Diff UI.
library;

import 'dart:math' as math;

import 'diff_view_model.dart';
import 'line_diff.dart';
import 'word_diff.dart';
import 'workspace_edit.dart';

class BulkEditMultiDiffException implements Exception {
  const BulkEditMultiDiffException(this.message);

  final String message;

  @override
  String toString() => 'BulkEditMultiDiffException: $message';
}

/// Per-projection limits. Callers may lower, but never raise, the hard caps.
class BulkEditMultiDiffLimits {
  const BulkEditMultiDiffLimits({
    this.maxResources = BulkEditMultiDiffProjection.maxResources,
    this.maxAggregateUtf16CodeUnits =
        BulkEditMultiDiffProjection.maxAggregateUtf16CodeUnits,
    this.maxAggregateLines = BulkEditMultiDiffProjection.maxAggregateLines,
    this.maxAggregateRows = BulkEditMultiDiffProjection.maxAggregateRows,
    this.maxAggregateLineWork =
        BulkEditMultiDiffProjection.maxAggregateLineWork,
    this.maxAggregateLineTraceCells =
        BulkEditMultiDiffProjection.maxAggregateLineTraceCells,
    this.maxAggregateWordInputCodeUnits =
        BulkEditMultiDiffProjection.maxAggregateWordInputCodeUnits,
    this.maxAggregateWordWork =
        BulkEditMultiDiffProjection.maxAggregateWordWork,
    this.maxAggregateWordTraceCells =
        BulkEditMultiDiffProjection.maxAggregateWordTraceCells,
  });

  final int maxResources;
  final int maxAggregateUtf16CodeUnits;
  final int maxAggregateLines;
  final int maxAggregateRows;
  final int maxAggregateLineWork;
  final int maxAggregateLineTraceCells;
  final int maxAggregateWordInputCodeUnits;
  final int maxAggregateWordWork;
  final int maxAggregateWordTraceCells;
}

class BulkEditMultiDiffResource {
  const BulkEditMultiDiffResource({
    required this.documentId,
    required this.uri,
    required this.baseVersion,
    required this.edits,
    required this.originalText,
    required this.modifiedText,
    required this.diff,
  });

  final int documentId;
  final String uri;
  final int baseVersion;
  final List<WorkspaceTextEdit> edits;
  final String originalText;
  final String modifiedText;
  final DiffViewModelResult diff;
}

/// An all-or-nothing, frozen Multi Diff projection of the selected edits.
class BulkEditMultiDiffProjection {
  factory BulkEditMultiDiffProjection({
    required WorkspaceEdit selectedEdit,
    required List<WorkspaceDocumentSnapshot> snapshots,
    BulkEditMultiDiffLimits limits = const BulkEditMultiDiffLimits(),
  }) {
    _validateLimits(limits);
    if (selectedEdit.documents.isEmpty) {
      throw const BulkEditMultiDiffException(
        'The Multi Diff preview has no selected documents.',
      );
    }
    if (selectedEdit.documents.length > limits.maxResources) {
      throw const BulkEditMultiDiffException(
        'The Multi Diff preview exceeds the resource limit.',
      );
    }
    if (snapshots.length != selectedEdit.documents.length) {
      throw const BulkEditMultiDiffException(
        'Provide exactly one snapshot for every selected resource.',
      );
    }

    final selectedUris = <String>{};
    for (final document in selectedEdit.documents) {
      if (!selectedUris.add(document.uri)) {
        throw BulkEditMultiDiffException(
          'The selected edit has a duplicate URI: ${document.uri}',
        );
      }
    }

    final snapshotsByUri = <String, WorkspaceDocumentSnapshot>{};
    for (final snapshot in snapshots) {
      if (!selectedUris.contains(snapshot.uri)) {
        throw BulkEditMultiDiffException(
          'The snapshot is not selected for preview: ${snapshot.uri}',
        );
      }
      if (snapshotsByUri.containsKey(snapshot.uri)) {
        throw BulkEditMultiDiffException(
          'The preview has a duplicate snapshot: ${snapshot.uri}',
        );
      }
      snapshotsByUri[snapshot.uri] = snapshot;
    }

    final orderedSnapshots = <WorkspaceDocumentSnapshot>[];
    var beforeUnits = 0;
    var insertedUnits = 0;
    var beforeLines = 0;
    var insertedLineFeeds = 0;
    for (final document in selectedEdit.documents) {
      final snapshot = snapshotsByUri[document.uri];
      if (snapshot == null) {
        throw BulkEditMultiDiffException(
          'No snapshot exists for ${document.uri}.',
        );
      }
      if (document.version != null && document.version != snapshot.version) {
        throw BulkEditMultiDiffException(
          'The selected edit is stale for ${document.uri}.',
        );
      }

      beforeUnits = _boundedAdd(
        beforeUnits,
        snapshot.text.length,
        limits.maxAggregateUtf16CodeUnits ~/ 2,
        'The Multi Diff preview exceeds its conservative UTF-16 input limit.',
      );
      final lineCount = _countLines(
        snapshot.text,
        const LineDiffOptions().maxLinesPerSide,
      );
      if (lineCount > const LineDiffOptions().maxLinesPerSide) {
        throw BulkEditMultiDiffException(
          'A selected resource exceeds the per-side line limit: ${document.uri}',
        );
      }
      beforeLines = _boundedAdd(
        beforeLines,
        lineCount,
        limits.maxAggregateLines ~/ 2,
        'The Multi Diff preview exceeds its conservative line limit.',
      );

      for (final edit in document.edits) {
        insertedUnits = _boundedAdd(
          insertedUnits,
          edit.newText.length,
          limits.maxAggregateUtf16CodeUnits - beforeUnits * 2,
          'The Multi Diff preview exceeds its conservative UTF-16 input limit.',
        );
        insertedLineFeeds = _boundedAdd(
          insertedLineFeeds,
          _countLineFeeds(edit.newText, limits.maxAggregateLines),
          limits.maxAggregateLines - beforeLines * 2,
          'The Multi Diff preview exceeds its conservative line limit.',
        );
      }
      orderedSnapshots.add(snapshot);
    }

    final conservativeUtf16 = beforeUnits * 2 + insertedUnits;
    if (conservativeUtf16 > limits.maxAggregateUtf16CodeUnits) {
      throw const BulkEditMultiDiffException(
        'The Multi Diff preview exceeds its conservative UTF-16 input limit.',
      );
    }
    final conservativeLines = beforeLines * 2 + insertedLineFeeds;
    if (conservativeLines > limits.maxAggregateLines) {
      throw const BulkEditMultiDiffException(
        'The Multi Diff preview exceeds its conservative line limit.',
      );
    }

    final frozenEdit = _freezeWorkspaceEdit(selectedEdit);
    final WorkspaceEditPlan plan;
    try {
      plan = const WorkspaceEditPlanner().plan(frozenEdit, orderedSnapshots);
    } on WorkspaceEditException catch (error) {
      throw BulkEditMultiDiffException(error.message);
    }
    final planByUri = {
      for (final document in plan.documents) document.uri: document,
    };

    final projectedTexts = <({
      WorkspaceDocumentEdit edit,
      WorkspaceDocumentSnapshot snapshot,
      String modified,
      int originalLines,
      int modifiedLines,
    })>[];
    var actualUtf16 = 0;
    var actualLines = 0;
    var anyTextChange = false;
    for (var index = 0; index < frozenEdit.documents.length; index++) {
      final edit = frozenEdit.documents[index];
      final snapshot = orderedSnapshots[index];
      final planned = planByUri[edit.uri];
      final modified = planned?.after ?? snapshot.text;
      final originalLines =
          _countLines(snapshot.text, limits.maxAggregateLines);
      final modifiedLines = _countLines(modified, limits.maxAggregateLines);
      if (originalLines > const LineDiffOptions().maxLinesPerSide ||
          modifiedLines > const LineDiffOptions().maxLinesPerSide) {
        throw BulkEditMultiDiffException(
          'A projected resource exceeds the per-side line limit: ${edit.uri}',
        );
      }
      actualUtf16 = _boundedAdd(
        actualUtf16,
        snapshot.text.length + modified.length,
        limits.maxAggregateUtf16CodeUnits,
        'The Multi Diff preview exceeds its UTF-16 input limit.',
      );
      actualLines = _boundedAdd(
        actualLines,
        originalLines + modifiedLines,
        limits.maxAggregateLines,
        'The Multi Diff preview exceeds its line limit.',
      );
      anyTextChange |= snapshot.text != modified;
      projectedTexts.add((
        edit: edit,
        snapshot: snapshot,
        modified: modified,
        originalLines: originalLines,
        modifiedLines: modifiedLines,
      ));
    }
    if (!anyTextChange) {
      throw const BulkEditMultiDiffException(
        'The selected edits do not change any resource.',
      );
    }

    final inputWeights = [
      for (final resource in projectedTexts)
        resource.snapshot.text.length + resource.modified.length,
    ];
    final lineWork = _allocateBudget(
      limits.maxAggregateLineWork,
      inputWeights,
    );
    final lineTraceCells = _allocateBudget(
      limits.maxAggregateLineTraceCells,
      inputWeights,
    );
    final rows = _allocateBudget(
      limits.maxAggregateRows,
      [
        for (final resource in projectedTexts)
          resource.originalLines + resource.modifiedLines,
      ],
    );
    final wordInput = _allocateBudget(
      limits.maxAggregateWordInputCodeUnits,
      inputWeights,
    );
    final wordWork = _allocateBudget(
      limits.maxAggregateWordWork,
      inputWeights,
    );
    final wordTraceCells = _allocateBudget(
      limits.maxAggregateWordTraceCells,
      inputWeights,
    );

    final resources = <BulkEditMultiDiffResource>[];
    var aggregateRows = 0;
    for (var index = 0; index < projectedTexts.length; index++) {
      final resource = projectedTexts[index];
      final pairInputUnits =
          resource.snapshot.text.length + resource.modified.length;
      final diff = computeDiffViewModel(
        resource.snapshot.text,
        resource.modified,
        options: DiffViewModelOptions(
          lineDiffOptions: LineDiffOptions(
            maxInputCodeUnits: math.max(1, pairInputUnits),
            maxLinesPerSide: math.min(
              const LineDiffOptions().maxLinesPerSide,
              math.max(resource.originalLines, resource.modifiedLines),
            ),
            maxTraceCells: lineTraceCells[index],
            maxWork: lineWork[index],
          ),
          wordDiffOptions: WordDiffOptions(
            maxInputCodeUnits: wordInput[index],
            maxTraceCells: wordTraceCells[index],
            maxWork: wordWork[index],
          ),
          maxInputCodeUnits: math.max(1, pairInputUnits),
          maxRows: rows[index],
          maxAggregateWordInputCodeUnits: wordInput[index],
          maxAggregateWordWork: wordWork[index],
        ),
      );
      if (diff.isApproximate) {
        throw BulkEditMultiDiffException(
          'A resource diff exceeded its budget: ${resource.edit.uri}',
        );
      }
      aggregateRows = _boundedAdd(
        aggregateRows,
        diff.rows.length,
        limits.maxAggregateRows,
        'The Multi Diff preview exceeds its row limit.',
      );
      resources.add(
        BulkEditMultiDiffResource(
          documentId: resource.snapshot.id,
          uri: resource.edit.uri,
          baseVersion: resource.snapshot.version,
          edits: resource.edit.edits,
          originalText: resource.snapshot.text,
          modifiedText: resource.modified,
          diff: diff,
        ),
      );
    }

    return BulkEditMultiDiffProjection._(
      transactionId: selectedEdit.transactionId,
      resources: List.unmodifiable(resources),
    );
  }

  const BulkEditMultiDiffProjection._({
    required this.transactionId,
    required this.resources,
  });

  static const int maxResources = 128;
  static const int maxAggregateUtf16CodeUnits = 2000000;
  static const int maxAggregateLines = 32768;
  static const int maxAggregateRows = 16384;
  static const int maxAggregateLineWork = 4000000;
  static const int maxAggregateLineTraceCells = 2000000;
  static const int maxAggregateWordInputCodeUnits = 262144;
  static const int maxAggregateWordWork = 2000000;
  static const int maxAggregateWordTraceCells = 1000000;

  final String? transactionId;
  final List<BulkEditMultiDiffResource> resources;

  static void _validateLimits(BulkEditMultiDiffLimits limits) {
    final values = <(int, int, String)>[
      (limits.maxResources, maxResources, 'resource'),
      (
        limits.maxAggregateUtf16CodeUnits,
        maxAggregateUtf16CodeUnits,
        'UTF-16 input',
      ),
      (limits.maxAggregateLines, maxAggregateLines, 'line'),
      (limits.maxAggregateRows, maxAggregateRows, 'row'),
      (limits.maxAggregateLineWork, maxAggregateLineWork, 'line work'),
      (
        limits.maxAggregateLineTraceCells,
        maxAggregateLineTraceCells,
        'line trace-cell',
      ),
      (
        limits.maxAggregateWordInputCodeUnits,
        maxAggregateWordInputCodeUnits,
        'word input',
      ),
      (limits.maxAggregateWordWork, maxAggregateWordWork, 'word work'),
      (
        limits.maxAggregateWordTraceCells,
        maxAggregateWordTraceCells,
        'word trace-cell',
      ),
    ];
    for (final (value, ceiling, label) in values) {
      if (value < 0 || value > ceiling || (label == 'resource' && value == 0)) {
        throw BulkEditMultiDiffException(
          'The configured $label limit must be between '
          '${label == 'resource' ? 1 : 0} and $ceiling.',
        );
      }
    }
  }

  static int _boundedAdd(
    int current,
    int addition,
    int limit,
    String message,
  ) {
    if (addition < 0 || current > limit || addition > limit - current) {
      throw BulkEditMultiDiffException(message);
    }
    return current + addition;
  }

  static int _countLines(String text, int stopAfter) {
    var lines = 1;
    for (var index = 0; index < text.length; index++) {
      if (text.codeUnitAt(index) != 0x0A) continue;
      lines++;
      if (lines > stopAfter) return lines;
    }
    return lines;
  }

  static int _countLineFeeds(String text, int stopAfter) {
    var lineFeeds = 0;
    for (var index = 0; index < text.length; index++) {
      if (text.codeUnitAt(index) != 0x0A) continue;
      lineFeeds++;
      if (lineFeeds > stopAfter) return lineFeeds;
    }
    return lineFeeds;
  }

  static List<int> _allocateBudget(int total, List<int> weights) {
    final active = [
      for (var index = 0; index < weights.length; index++)
        if (weights[index] > 0) index,
    ];
    if (active.isEmpty) return List<int>.filled(weights.length, 0);
    if (total < active.length) {
      throw const BulkEditMultiDiffException(
        'The aggregate diff budget is too small for the selected resources.',
      );
    }

    final totalWeight = active.fold<int>(
      0,
      (sum, index) => sum + weights[index],
    );
    final remaining = total - active.length;
    final result = List<int>.filled(weights.length, 0);
    var allocated = 0;
    for (final index in active) {
      final share = 1 + (remaining * weights[index] ~/ totalWeight);
      result[index] = share;
      allocated += share;
    }
    var remainder = total - allocated;
    while (remainder > 0) {
      final index = active.reduce(
        (left, right) => weights[left] >= weights[right] ? left : right,
      );
      result[index]++;
      remainder--;
    }
    return result;
  }

  static WorkspaceEdit _freezeWorkspaceEdit(WorkspaceEdit source) =>
      WorkspaceEdit(
        List.unmodifiable([
          for (final document in source.documents)
            WorkspaceDocumentEdit(
              uri: document.uri,
              version: document.version,
              edits: List.unmodifiable([
                for (final edit in document.edits)
                  WorkspaceTextEdit(
                    range: WorkspaceTextRange(
                      start: WorkspaceTextPosition(
                        edit.range.start.line,
                        edit.range.start.character,
                      ),
                      end: WorkspaceTextPosition(
                        edit.range.end.line,
                        edit.range.end.character,
                      ),
                    ),
                    newText: edit.newText,
                  ),
              ]),
            ),
        ]),
        transactionId: source.transactionId,
      );
}
