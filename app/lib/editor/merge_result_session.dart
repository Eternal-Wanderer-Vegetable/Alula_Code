import 'dart:collection';

import '../bridge/alula_core.dart';

const int maxMergeSessionInputUtf8Bytes = 8 * 1024 * 1024;
const int _maxMergeResolutionSnapshots = 32;
const int _maxMergeResolutionSnapshotConflicts = 1024;
const int _maxMergeResolutionSnapshotCombinationCodeUnits = 8 * 1024 * 1024;

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
    required Map<int, String> combinationCandidates,
  })  : _sessionToken = sessionToken,
        operations = List.unmodifiable(operations),
        resolutions = UnmodifiableMapView(resolutions),
        combinationCandidates = UnmodifiableMapView(combinationCandidates);

  final Object _sessionToken;
  final int generation;
  final int baseVersion;
  final List<TextOp> operations;
  final AlulaMergeProjection projection;
  final Map<int, AlulaMergeSide> resolutions;
  final Map<int, String> combinationCandidates;
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

class _MergeResolutionSnapshot {
  _MergeResolutionSnapshot({
    required Map<int, AlulaMergeSide> resolutions,
    required Map<int, String> combinationCandidates,
  })  : resolutions = UnmodifiableMapView(Map.of(resolutions)),
        combinationCandidates =
            UnmodifiableMapView(Map.of(combinationCandidates)),
        combinationCandidateCodeUnits = combinationCandidates.values.fold<int>(
          0,
          (total, candidate) {
            const saturated =
                _maxMergeResolutionSnapshotCombinationCodeUnits + 1;
            if (total >= saturated || candidate.length >= saturated - total) {
              return saturated;
            }
            return total + candidate.length;
          },
        );

  final Map<int, AlulaMergeSide> resolutions;
  final Map<int, String> combinationCandidates;
  final int combinationCandidateCodeUnits;
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
    _resolutionHistory.add(_MergeResolutionSnapshot(
      resolutions: const {},
      combinationCandidates: const {},
    ));
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
  Map<int, String> _combinationCandidates = const {};
  Map<int, AlulaMergeSide> _savedResolutions = const {};
  Map<int, String> _savedCombinationCandidates = const {};
  final List<_MergeResolutionSnapshot> _resolutionHistory = [];
  int _resolutionHistoryCombinationCodeUnits = 0;
  int _projectedVersion;
  int _generation = 0;
  bool _disposed = false;
  bool _externallyChanged = false;

  bool get isDisposed => _disposed;

  /// Manual result edits can leave the frozen projection's UTF-16 ranges stale.
  bool get hasStaleConflictRanges => _externallyChanged;
  int get generation => _generation;
  String get baseText {
    _ensureActive();
    return _base!;
  }

  String get input1Text {
    _ensureActive();
    return _input1!;
  }

  String get input2Text {
    _ensureActive();
    return _input2!;
  }

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
    final nextCombinationCandidates =
        Map<int, String>.of(_combinationCandidates)..remove(conflictId);
    final nextProjection = _project(
      nextResolutions,
      combinationCandidates: nextCombinationCandidates,
    );
    return _planProjection(
      nextProjection,
      nextResolutions,
      nextCombinationCandidates,
      [_replacementFor(conflict, side)],
    );
  }

  MergeResultEditPlan planAcceptAll(AlulaMergeSide side) {
    _assertCurrentResult();
    final nextResolutions = <int, AlulaMergeSide>{};
    final replacements = <_MergeReplacement>[];
    for (final conflict in _currentProjection.conflicts) {
      if (conflict.isCombination) continue;
      nextResolutions[conflict.id] = side;
      if (_resolutions[conflict.id] == side) continue;
      replacements.add(_replacementFor(conflict, side));
    }
    final nextCombinationCandidates =
        Map<int, String>.of(_combinationCandidates);
    return _planProjection(
      _project(
        nextResolutions,
        combinationCandidates: nextCombinationCandidates,
      ),
      nextResolutions,
      nextCombinationCandidates,
      replacements,
    );
  }

  /// Plans the Code-OSS smart-combination action without mutating session or
  /// Rust document state. A null candidate leaves that conflict untouched.
  /// If any bounded FFI request fails, no partial plan is returned.
  MergeResultEditPlan? planAcceptAllCombinations() {
    _assertCurrentResult();
    final nextResolutions = Map<int, AlulaMergeSide>.of(_resolutions);
    final nextCombinationCandidates =
        Map<int, String>.of(_combinationCandidates);
    final replacements = <_MergeReplacement>[];

    for (final conflict in _currentProjection.conflicts) {
      if (conflict.isCombination ||
          _resolutions[conflict.id] == AlulaMergeSide.input1) {
        continue;
      }
      final candidate = _mergeApi.combinationCandidate(
        base: conflict.baseText,
        input1: conflict.input1Text,
        input2: conflict.input2Text,
      );
      if (candidate == null) continue;

      nextResolutions.remove(conflict.id);
      nextCombinationCandidates[conflict.id] = candidate;
      replacements.add(_MergeReplacement(
        start: conflict.resultStartUtf16,
        end: conflict.resultEndUtf16,
        text: candidate,
      ));
    }

    if (replacements.isEmpty) return null;
    final nextProjection = _project(
      nextResolutions,
      combinationCandidates: nextCombinationCandidates,
    );
    return _planProjection(
      nextProjection,
      nextResolutions,
      nextCombinationCandidates,
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
    _combinationCandidates = Map.unmodifiable(plan.combinationCandidates);
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
      for (final snapshot in _resolutionHistory.reversed) {
        final candidate = _project(
          snapshot.resolutions,
          combinationCandidates: snapshot.combinationCandidates,
        );
        if (candidate.result != current.content) continue;
        _projection = candidate;
        _resolutions = snapshot.resolutions;
        _combinationCandidates = snapshot.combinationCandidates;
        _projectedVersion = current.version;
        _externallyChanged = false;
        _generation++;
        return true;
      }
    }

    _resolutions = const {};
    _combinationCandidates = const {};
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
        _combinationCandidates = Map.unmodifiable(_savedCombinationCandidates);
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
    _combinationCandidates = const {};
    _savedResolutions = const {};
    _savedCombinationCandidates = const {};
    _resolutionHistory.clear();
    _resolutionHistoryCombinationCodeUnits = 0;
    _externallyChanged = false;
    _generation++;
  }

  void _rememberSavedResult(String result) {
    _savedResult = result;
    if (result == _currentProjection.result) {
      _savedProjection = _currentProjection;
      _savedResolutions = Map.unmodifiable(_resolutions);
      _savedCombinationCandidates = Map.unmodifiable(_combinationCandidates);
    }
  }

  void _rememberResolutionSnapshot() {
    if (_resolutionHistory.isNotEmpty &&
        _sameSnapshot(
          _resolutionHistory.last,
          _resolutions,
          _combinationCandidates,
        )) {
      return;
    }
    final conflictCount = _currentProjection.conflictCount;
    if (conflictCount > _maxMergeResolutionSnapshotConflicts) {
      _clearResolutionHistory();
      _addResolutionSnapshot(_MergeResolutionSnapshot(
        resolutions: const {},
        combinationCandidates: const {},
      ));
      _addResolutionSnapshot(_MergeResolutionSnapshot(
        resolutions: _resolutions,
        combinationCandidates: _combinationCandidates,
      ));
      return;
    }
    _addResolutionSnapshot(_MergeResolutionSnapshot(
      resolutions: _resolutions,
      combinationCandidates: _combinationCandidates,
    ));
  }

  void _clearResolutionHistory() {
    _resolutionHistory.clear();
    _resolutionHistoryCombinationCodeUnits = 0;
  }

  void _addResolutionSnapshot(_MergeResolutionSnapshot snapshot) {
    _resolutionHistory.add(snapshot);
    _resolutionHistoryCombinationCodeUnits +=
        snapshot.combinationCandidateCodeUnits;
    while (_resolutionHistory.length > 2 &&
        (_resolutionHistory.length > _maxMergeResolutionSnapshots ||
            _resolutionHistoryCombinationCodeUnits >
                _maxMergeResolutionSnapshotCombinationCodeUnits)) {
      // Preserve the original unresolved projection and the current state.
      final removed = _resolutionHistory.removeAt(1);
      _resolutionHistoryCombinationCodeUnits -=
          removed.combinationCandidateCodeUnits;
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

  bool _sameSnapshot(
    _MergeResolutionSnapshot snapshot,
    Map<int, AlulaMergeSide> resolutions,
    Map<int, String> combinationCandidates,
  ) =>
      _sameResolutions(snapshot.resolutions, resolutions) &&
      _sameCombinationCandidates(
        snapshot.combinationCandidates,
        combinationCandidates,
      );

  bool _sameCombinationCandidates(
    Map<int, String> left,
    Map<int, String> right,
  ) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (right[entry.key] != entry.value) return false;
    }
    return true;
  }

  AlulaMergeProjection _project(
    Map<int, AlulaMergeSide> resolutions, {
    Map<int, String> combinationCandidates = const {},
  }) {
    final projection = _mergeApi.project(
      base: _base!,
      input1: _input1!,
      input2: _input2!,
      resolutions: resolutions,
    );
    if (combinationCandidates.isEmpty) return projection;
    if (combinationCandidates.length > projection.unresolvedConflictCount) {
      throw const MergeResultSessionException(
        MergeResultSessionErrorCode.projectionMismatch,
        'Combination candidates exceed the unresolved conflict count',
      );
    }

    final candidates = Map<int, String>.of(combinationCandidates);
    final conflicts = <AlulaMergeConflict>[];
    final replacements = <_MergeReplacement>[];
    var shift = 0;
    for (final conflict in projection.conflicts) {
      final candidate = candidates.remove(conflict.id);
      final start = conflict.resultStartUtf16 + shift;
      if (candidate == null) {
        conflicts.add(AlulaMergeConflict(
          id: conflict.id,
          baseStartLine: conflict.baseStartLine,
          baseEndLineExclusive: conflict.baseEndLineExclusive,
          resultStartUtf16: start,
          resultEndUtf16: conflict.resultEndUtf16 + shift,
          baseText: conflict.baseText,
          input1Text: conflict.input1Text,
          input2Text: conflict.input2Text,
          resolution: conflict.resolution,
        ));
        continue;
      }
      if (conflict.resolution != null) {
        throw MergeResultSessionException(
          MergeResultSessionErrorCode.projectionMismatch,
          'Conflict ${conflict.id} is both side-resolved and combined',
        );
      }

      replacements.add(_MergeReplacement(
        start: conflict.resultStartUtf16,
        end: conflict.resultEndUtf16,
        text: candidate,
      ));
      conflicts.add(AlulaMergeConflict(
        id: conflict.id,
        baseStartLine: conflict.baseStartLine,
        baseEndLineExclusive: conflict.baseEndLineExclusive,
        resultStartUtf16: start,
        resultEndUtf16: start + candidate.length,
        baseText: conflict.baseText,
        input1Text: conflict.input1Text,
        input2Text: conflict.input2Text,
        resolution: null,
        isCombination: true,
      ));
      shift += candidate.length -
          (conflict.resultEndUtf16 - conflict.resultStartUtf16);
    }
    if (candidates.isNotEmpty) {
      throw MergeResultSessionException(
        MergeResultSessionErrorCode.unknownConflict,
        'Unknown merge combination conflict ids ${candidates.keys}',
      );
    }
    final normalized = _normalizeReplacements(
      replacements,
      projection.result.length,
    );
    return AlulaMergeProjection(
      result: _applyReplacements(projection.result, normalized),
      conflictCount: projection.conflictCount,
      unresolvedConflictCount:
          projection.unresolvedConflictCount - combinationCandidates.length,
      conflicts: conflicts,
    );
  }

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
    Map<int, String> nextCombinationCandidates,
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
      combinationCandidates: nextCombinationCandidates,
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
