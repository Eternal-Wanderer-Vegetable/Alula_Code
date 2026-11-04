import 'dart:collection';

import '../bridge/alula_core.dart';

const int maxMergeSessionInputUtf8Bytes = 8 * 1024 * 1024;
const int _maxMergeResolutionSnapshots = 32;
const int _maxMergeResolutionSnapshotConflicts = 1024;

enum MergeResultSessionErrorCode {
  disposed,
  inputTooLarge,
  initialResultMismatch,
  staleResult,
  stalePlan,
  unknownConflict,
  invalidConflictRanges,
  projectionMismatch,
}

class MergeResultSessionException implements Exception {
  const MergeResultSessionException(this.code, this.detail);

  final MergeResultSessionErrorCode code;
  final String detail;

  @override
  String toString() => 'MergeResultSessionException($code): $detail';
}

enum MergeResultCloseAction {
  save,
  discard,
  close,
  closeWithConflicts,
  cancel,
}

enum MergeResultCloseOutcome {
  closed,
  cancelled,
  saveFailed,
  resultChangedDuringSave,
  revertFailed,
  invalidAction,
}

enum MergeResultSaveLabel { save, saveWithConflicts }

class MergeResultClosePrompt {
  MergeResultClosePrompt({
    required this.isDirty,
    required this.unresolvedConflictCount,
    required Set<MergeResultCloseAction> actions,
  }) : actions = UnmodifiableSetView(actions);

  final bool isDirty;
  final int unresolvedConflictCount;
  final Set<MergeResultCloseAction> actions;

  MergeResultSaveLabel? get saveLabel =>
      actions.contains(MergeResultCloseAction.save)
          ? unresolvedConflictCount > 0
              ? MergeResultSaveLabel.saveWithConflicts
              : MergeResultSaveLabel.save
          : null;
}

class MergeResultEditPlan {
  MergeResultEditPlan._({
    required Object sessionToken,
    required this.generation,
    required this.baseVersion,
    required List<TextOp> operations,
    required this.projection,
    required Map<int, AlulaMergeSide> resolutions,
  })  : _sessionToken = sessionToken,
        operations = List.unmodifiable(operations),
        resolutions = UnmodifiableMapView(resolutions);

  final Object _sessionToken;
  final int generation;
  final int baseVersion;
  final List<TextOp> operations;
  final AlulaMergeProjection projection;
  final Map<int, AlulaMergeSide> resolutions;
}

class _MergeReplacement {
  const _MergeReplacement({
    required this.start,
    required this.end,
    required this.text,
  });

  final int start;
  final int end;
  final String text;
}

/// Stateful merge inputs and conflict choices bound to one Rust result document.
/// The session plans edits; its owner applies them through the document's normal
/// undo/sibling-view path and then calls [applyPlan].
class MergeResultSession {
  MergeResultSession._({
    required AlulaMergeApi mergeApi,
    required AlulaDoc resultDocument,
    required String base,
    required String input1,
    required String input2,
    required AlulaMergeProjection projection,
    required int projectedVersion,
  })  : _mergeApi = mergeApi,
        _resultDocument = resultDocument,
        _base = base,
        _input1 = input1,
        _input2 = input2,
        _projection = projection,
        _savedProjection = projection,
        _savedResult = projection.result,
        _projectedVersion = projectedVersion {
    _resolutionHistory.add(const {});
  }

  factory MergeResultSession.open({
    required AlulaMergeApi mergeApi,
    required AlulaDoc resultDocument,
    required String base,
    required String input1,
    required String input2,
  }) {
    final byteLength =
        _utf8Length(base) + _utf8Length(input1) + _utf8Length(input2);
    if (byteLength > maxMergeSessionInputUtf8Bytes) {
      throw const MergeResultSessionException(
        MergeResultSessionErrorCode.inputTooLarge,
        'Frozen merge inputs exceed the 8 MiB session limit',
      );
    }

    final projection = mergeApi.project(
      base: base,
      input1: input1,
      input2: input2,
    );
    final current = resultDocument.resync();
    if (current.content != projection.result) {
      throw const MergeResultSessionException(
        MergeResultSessionErrorCode.initialResultMismatch,
        'The Rust result document does not match the initial merge projection',
      );
    }
    return MergeResultSession._(
      mergeApi: mergeApi,
      resultDocument: resultDocument,
      base: base,
      input1: input1,
      input2: input2,
      projection: projection,
      projectedVersion: current.version,
    );
  }

  final Object _sessionToken = Object();
  final AlulaMergeApi _mergeApi;
  AlulaDoc? _resultDocument;
  String? _base;
  String? _input1;
  String? _input2;
  AlulaMergeProjection? _projection;
  AlulaMergeProjection? _savedProjection;
  String? _savedResult;
  Map<int, AlulaMergeSide> _resolutions = const {};
  Map<int, AlulaMergeSide> _savedResolutions = const {};
  final List<Map<int, AlulaMergeSide>> _resolutionHistory = [];
  int _projectedVersion;
  int _generation = 0;
  bool _disposed = false;
  bool _externallyChanged = false;

  bool get isDisposed => _disposed;
  int get generation => _generation;
  int get unresolvedConflictCount => _externallyChanged
      ? conflictCount
      : _currentProjection.unresolvedConflictCount;
  int get conflictCount => _currentProjection.conflictCount;
  List<AlulaMergeConflict> get conflicts => _currentProjection.conflicts;
  Map<int, AlulaMergeSide> get resolutions => UnmodifiableMapView(_resolutions);
  AlulaMergeProjection get projection => _currentProjection;
  String get latestSavedResult {
    _ensureActive();
    return _savedResult!;
  }

  bool get isDirty => _requireResultDocument().isDirty;

  AlulaMergeProjection get _currentProjection {
    _ensureActive();
    return _projection!;
  }

  AlulaDoc _requireResultDocument() {
    _ensureActive();
    return _resultDocument!;
  }

  MergeResultEditPlan planResolveConflict(int conflictId, AlulaMergeSide side) {
    _assertCurrentResult();
    final conflict = _currentProjection.conflicts
        .where((candidate) => candidate.id == conflictId)
        .firstOrNull;
    if (conflict == null) {
      throw MergeResultSessionException(
        MergeResultSessionErrorCode.unknownConflict,
        'Unknown merge conflict id $conflictId',
      );
    }

    final nextResolutions = Map<int, AlulaMergeSide>.of(_resolutions)
      ..[conflictId] = side;
    final nextProjection = _project(nextResolutions);
    return _planProjection(
      nextProjection,
      nextResolutions,
      [_replacementFor(conflict, side)],
    );
  }

  MergeResultEditPlan planAcceptAll(AlulaMergeSide side) {
    _assertCurrentResult();
    final nextResolutions = <int, AlulaMergeSide>{
      for (final conflict in _currentProjection.conflicts) conflict.id: side,
    };
    final replacements = [
      for (final conflict in _currentProjection.conflicts)
        _replacementFor(conflict, side),
    ];
    return _planProjection(
      _project(nextResolutions),
      nextResolutions,
      replacements,
    );
  }

  /// Commits session state after the host has applied [plan.operations] through
  /// the normal Rust document edit and undo path.
  void applyPlan(MergeResultEditPlan plan, {required int appliedVersion}) {
    _ensureActive();
    _validatePlanIdentity(plan);
    final current = _requireResultDocument().resync();
    if (current.version != appliedVersion ||
        current.content != plan.projection.result) {
      throw const MergeResultSessionException(
        MergeResultSessionErrorCode.projectionMismatch,
        'The committed Rust document does not match the planned projection',
      );
    }
    _projection = plan.projection;
    _resolutions = Map.unmodifiable(plan.resolutions);
    _projectedVersion = current.version;
    _externallyChanged = false;
    _rememberResolutionSnapshot();
    _generation++;
  }

  /// Checks that [plan] still targets the current Rust result before the host
  /// starts applying its operations.
  void validatePlan(MergeResultEditPlan plan) {
    _ensureActive();
    _validatePlanIdentity(plan);
    _assertCurrentResult();
  }

  /// Reconciles the merge model with the Rust-owned document after undo/redo
  /// or when a host observes an out-of-session edit. Text matching a retained
  /// projection restores its conflict choices; unknown text invalidates them.
  bool reconcileCurrentResult({bool allowKnownProjectionRestore = true}) {
    _ensureActive();
    final current = _requireResultDocument().resync();
    if (current.content == _currentProjection.result && !_externallyChanged) {
      if (current.version != _projectedVersion) {
        _projectedVersion = current.version;
        _generation++;
      }
      _externallyChanged = false;
      return true;
    }

    if (allowKnownProjectionRestore) {
      for (final resolutions in _resolutionHistory.reversed) {
        final candidate = _project(resolutions);
        if (candidate.result != current.content) continue;
        _projection = candidate;
        _resolutions = resolutions;
        _projectedVersion = current.version;
        _externallyChanged = false;
        _generation++;
        return true;
      }
    }

    _resolutions = const {};
    _projectedVersion = current.version;
    _externallyChanged = true;
    _generation++;
    return false;
  }

  /// Records the current projection after the host has completed an atomic
  /// save and advanced the Rust document savepoint.
  void recordSavepoint() {
    final document = _requireResultDocument();
    if (document.isDirty) {
      throw const MergeResultSessionException(
        MergeResultSessionErrorCode.projectionMismatch,
        'The result document savepoint has not been advanced',
      );
    }
    _rememberSavedResult(document.resync().content);
  }

  MergeResultClosePrompt get closePrompt {
    _ensureActive();
    reconcileCurrentResult();
    final document = _requireResultDocument();
    final current = document.resync();
    final matchesProjection = current.version == _projectedVersion &&
        current.content == _currentProjection.result;
    final dirty = document.isDirty;
    // External/manual edits invalidate side-choice certainty. Keep every
    // conflict unresolved until a later session-aware edit path can reconcile
    // its ranges; never let stale state advertise a clean merge.
    final unresolved = matchesProjection
        ? unresolvedConflictCount
        : _currentProjection.conflictCount;
    final actions = dirty
        ? const {
            MergeResultCloseAction.save,
            MergeResultCloseAction.discard,
            MergeResultCloseAction.cancel,
          }
        : unresolved > 0
            ? const {
                MergeResultCloseAction.closeWithConflicts,
                MergeResultCloseAction.cancel,
              }
            : const {MergeResultCloseAction.close};
    return MergeResultClosePrompt(
      isDirty: dirty,
      unresolvedConflictCount: unresolved,
      actions: actions,
    );
  }

  /// `save` must return true only after its atomic disk write succeeds.
  /// `revert` must restore the latest saved result and its Rust savepoint.
  Future<MergeResultCloseOutcome> finishClose(
    MergeResultCloseAction action, {
    required Future<bool> Function() save,
    required Future<bool> Function() revert,
    required Future<void> Function() closeResultDocument,
  }) async {
    final prompt = closePrompt;
    if (!prompt.actions.contains(action)) {
      return MergeResultCloseOutcome.invalidAction;
    }
    if (action == MergeResultCloseAction.cancel) {
      return MergeResultCloseOutcome.cancelled;
    }

    final document = _requireResultDocument();
    if (action == MergeResultCloseAction.save) {
      final beforeVersion = document.resync().version;
      if (!await save()) return MergeResultCloseOutcome.saveFailed;
      final afterSave = document.resync();
      if (afterSave.version != beforeVersion) {
        return MergeResultCloseOutcome.resultChangedDuringSave;
      }
      document.markSaved();
      if (document.isDirty) return MergeResultCloseOutcome.saveFailed;
      _rememberSavedResult(afterSave.content);
    } else if (action == MergeResultCloseAction.discard) {
      if (!await revert()) return MergeResultCloseOutcome.revertFailed;
      final reverted = document.resync();
      if (document.isDirty || reverted.content != _savedResult) {
        return MergeResultCloseOutcome.revertFailed;
      }
      if (reverted.content == _savedProjection?.result) {
        _projection = _savedProjection;
        _resolutions = Map.unmodifiable(_savedResolutions);
        _externallyChanged = false;
      }
      _projectedVersion = reverted.version;
      _generation++;
    }

    await closeResultDocument();
    dispose();
    return MergeResultCloseOutcome.closed;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _resultDocument = null;
    _base = null;
    _input1 = null;
    _input2 = null;
    _projection = null;
    _savedProjection = null;
    _savedResult = null;
    _resolutions = const {};
    _savedResolutions = const {};
    _resolutionHistory.clear();
    _externallyChanged = false;
    _generation++;
  }

  void _rememberSavedResult(String result) {
    _savedResult = result;
    if (result == _currentProjection.result) {
      _savedProjection = _currentProjection;
      _savedResolutions = Map.unmodifiable(_resolutions);
    }
  }

  void _rememberResolutionSnapshot() {
    if (_resolutionHistory.isNotEmpty &&
        _sameResolutions(_resolutionHistory.last, _resolutions)) {
      return;
    }
    final conflictCount = _currentProjection.conflictCount;
    if (conflictCount > _maxMergeResolutionSnapshotConflicts) {
      _resolutionHistory
        ..clear()
        ..add(const {})
        ..add(_resolutions);
      return;
    }
    _resolutionHistory.add(_resolutions);
    while (_resolutionHistory.length > _maxMergeResolutionSnapshots) {
      // Preserve the original unresolved projection for a complete undo.
      _resolutionHistory.removeAt(1);
    }
  }

  bool _sameResolutions(
    Map<int, AlulaMergeSide> left,
    Map<int, AlulaMergeSide> right,
  ) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (right[entry.key] != entry.value) return false;
    }
    return true;
  }

  AlulaMergeProjection _project(Map<int, AlulaMergeSide> resolutions) =>
      _mergeApi.project(
        base: _base!,
        input1: _input1!,
        input2: _input2!,
        resolutions: resolutions,
      );

  void _validatePlanIdentity(MergeResultEditPlan plan) {
    if (!identical(plan._sessionToken, _sessionToken) ||
        plan.generation != _generation ||
        plan.baseVersion != _projectedVersion) {
      throw const MergeResultSessionException(
        MergeResultSessionErrorCode.stalePlan,
        'The merge result changed after this edit plan was created',
      );
    }
  }

  MergeResultEditPlan _planProjection(
    AlulaMergeProjection nextProjection,
    Map<int, AlulaMergeSide> nextResolutions,
    List<_MergeReplacement> replacements,
  ) {
    final currentText = _currentProjection.result;
    final normalized = _normalizeReplacements(
      replacements,
      currentText.length,
    );
    final predicted = _applyReplacements(currentText, normalized);
    if (predicted != nextProjection.result) {
      throw const MergeResultSessionException(
        MergeResultSessionErrorCode.projectionMismatch,
        'Conflict ranges do not reconstruct the next Rust projection',
      );
    }
    return MergeResultEditPlan._(
      sessionToken: _sessionToken,
      generation: _generation,
      baseVersion: _projectedVersion,
      operations: _operationsFor(normalized),
      projection: nextProjection,
      resolutions: nextResolutions,
    );
  }

  _MergeReplacement _replacementFor(
    AlulaMergeConflict conflict,
    AlulaMergeSide side,
  ) =>
      _MergeReplacement(
        start: conflict.resultStartUtf16,
        end: conflict.resultEndUtf16,
        text: switch (side) {
          AlulaMergeSide.input1 => conflict.input1Text,
          AlulaMergeSide.input2 => conflict.input2Text,
        },
      );

  List<_MergeReplacement> _normalizeReplacements(
    List<_MergeReplacement> replacements,
    int textLength,
  ) {
    final indexed = replacements.indexed.toList()
      ..sort((a, b) {
        final byStart = a.$2.start.compareTo(b.$2.start);
        if (byStart != 0) return byStart;
        final byEnd = a.$2.end.compareTo(b.$2.end);
        return byEnd != 0 ? byEnd : a.$1.compareTo(b.$1);
      });
    final ordered = indexed.map((entry) => entry.$2).toList();
    final normalized = <_MergeReplacement>[];
    var previousEnd = 0;
    for (var index = 0; index < ordered.length;) {
      final first = ordered[index];
      if (first.start < previousEnd ||
          first.start < 0 ||
          first.end < first.start ||
          first.end > textLength) {
        throw const MergeResultSessionException(
          MergeResultSessionErrorCode.invalidConflictRanges,
          'Merge conflict ranges overlap or fall outside the current result',
        );
      }
      if (first.start == first.end) {
        final text = StringBuffer();
        var next = index;
        while (next < ordered.length &&
            ordered[next].start == first.start &&
            ordered[next].end == first.end) {
          text.write(ordered[next].text);
          next++;
        }
        normalized.add(_MergeReplacement(
          start: first.start,
          end: first.end,
          text: text.toString(),
        ));
        index = next;
      } else {
        normalized.add(first);
        index++;
      }
      previousEnd = normalized.last.end;
    }
    return normalized;
  }

  String _applyReplacements(
    String text,
    List<_MergeReplacement> replacements,
  ) {
    final output = StringBuffer();
    var cursor = 0;
    for (final replacement in replacements) {
      output.write(text.substring(cursor, replacement.start));
      output.write(replacement.text);
      cursor = replacement.end;
    }
    output.write(text.substring(cursor));
    return output.toString();
  }

  List<TextOp> _operationsFor(List<_MergeReplacement> replacements) {
    final operations = <TextOp>[];
    for (final replacement in replacements.reversed) {
      if (replacement.end > replacement.start) {
        operations.add(TextOp.delete(
          replacement.start,
          replacement.end - replacement.start,
        ));
      }
      if (replacement.text.isNotEmpty) {
        operations.add(TextOp.insert(replacement.start, replacement.text));
      }
    }
    return List.unmodifiable(operations);
  }

  void _assertCurrentResult() {
    final current = _requireResultDocument().resync();
    if (current.version != _projectedVersion ||
        current.content != _currentProjection.result) {
      throw const MergeResultSessionException(
        MergeResultSessionErrorCode.staleResult,
        'The Rust result document changed outside this merge session',
      );
    }
  }

  void _ensureActive() {
    if (_disposed ||
        _resultDocument == null ||
        _base == null ||
        _input1 == null ||
        _input2 == null ||
        _projection == null) {
      throw const MergeResultSessionException(
        MergeResultSessionErrorCode.disposed,
        'The merge result session has been disposed',
      );
    }
  }
}

int _utf8Length(String text) {
  var bytes = 0;
  for (final rune in text.runes) {
    bytes += rune <= 0x7f
        ? 1
        : rune <= 0x7ff
            ? 2
            : rune <= 0xffff
                ? 3
                : 4;
    if (bytes > maxMergeSessionInputUtf8Bytes) return bytes;
  }
  return bytes;
}
