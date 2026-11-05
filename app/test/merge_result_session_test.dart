import 'dart:io';

import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/editor/merge_result_session.dart';
import 'package:flutter_test/flutter_test.dart';

class _SessionBootstrap {
  _SessionBootstrap() {
    try {
      core = AlulaCore.load();
    } catch (error) {
      skip = 'alula_core is unavailable; build it first ($error)';
    }
  }

  AlulaCore? core;
  String? skip;
}

final _bootstrap = _SessionBootstrap();
var _nextDocumentId = 780000;

({AlulaDoc document, MergeResultSession session}) _openSession({
  required String base,
  required String input1,
  required String input2,
  String? result,
}) {
  final projection = _bootstrap.core!.merge.project(
    base: base,
    input1: input1,
    input2: input2,
  );
  final doc = _bootstrap.core!.openDoc(
    _nextDocumentId++,
    result ?? projection.result,
  );
  try {
    return (
      document: doc,
      session: MergeResultSession.open(
        mergeApi: _bootstrap.core!.merge,
        resultDocument: doc,
        base: base,
        input1: input1,
        input2: input2,
      ),
    );
  } catch (_) {
    doc.close();
    rethrow;
  }
}

void _applyPlan(
    AlulaDoc document, MergeResultSession session, MergeResultEditPlan plan) {
  final version = document.applyWith(plan.baseVersion, plan.operations);
  session.applyPlan(plan, appliedVersion: version);
}

void _replaceDocument(AlulaDoc document, String replacement) {
  final current = document.resync();
  final length = current.content.codeUnits.length;
  final ops = <TextOp>[
    if (length > 0) TextOp.delete(0, length),
    if (replacement.isNotEmpty) TextOp.insert(0, replacement),
  ];
  document.applyWith(current.version, ops);
}

void main() {
  test('exposes immutable input snapshots only while the session is active',
      () {
    const base = 'base 😀\r\n';
    const input1 = 'input one\n';
    const input2 = 'input two\n';
    final opened = _openSession(base: base, input1: input1, input2: input2);
    try {
      expect(opened.session.baseText, base);
      expect(opened.session.input1Text, input1);
      expect(opened.session.input2Text, input2);
      _replaceDocument(opened.document, 'different result');
      expect(opened.session.baseText, base);
      expect(opened.session.input1Text, input1);
      expect(opened.session.input2Text, input2);
    } finally {
      opened.session.dispose();
      opened.document.close();
    }
    expect(() => opened.session.baseText,
        throwsA(isA<MergeResultSessionException>()));
    expect(() => opened.session.input1Text,
        throwsA(isA<MergeResultSessionException>()));
    expect(() => opened.session.input2Text,
        throwsA(isA<MergeResultSessionException>()));
  }, skip: _bootstrap.skip);

  test('opens only when Rust result matches the frozen input projection', () {
    const base = 'base\n';
    const input1 = 'left\n';
    const input2 = 'right\n';
    final doc = _bootstrap.core!.openDoc(_nextDocumentId++, 'not the result');
    try {
      expect(
        () => MergeResultSession.open(
          mergeApi: _bootstrap.core!.merge,
          resultDocument: doc,
          base: base,
          input1: input1,
          input2: input2,
        ),
        throwsA(isA<MergeResultSessionException>().having(
          (error) => error.code,
          'code',
          MergeResultSessionErrorCode.initialResultMismatch,
        )),
      );
    } finally {
      doc.close();
    }
  }, skip: _bootstrap.skip);

  test(
      'resolves one conflict using Rust UTF-16 ranges with BOM, emoji and CRLF',
      () {
    const base = '\u{feff}😀\r\nold\r\nmiddle\r\n';
    const input1 = '\u{feff}😀\r\nlonger 🦊\r\nmiddle\r\n';
    const input2 = '\u{feff}😀\r\nincoming\r\nmiddle\r\n';
    final opened = _openSession(base: base, input1: input1, input2: input2);
    final doc = opened.document;
    final session = opened.session;
    try {
      expect(session.conflictCount, 1);
      final conflict = session.conflicts.single;
      expect(conflict.resultStartUtf16, 5);
      expect(conflict.resultEndUtf16, 10);

      final plan = session.planResolveConflict(
        conflict.id,
        AlulaMergeSide.input1,
      );
      _applyPlan(doc, session, plan);

      expect(doc.resync().content, input1);
      expect(session.unresolvedConflictCount, 0);
      expect(session.conflicts.single.resolution, AlulaMergeSide.input1);
      expect(session.conflicts.single.resultStartUtf16, 5);
      expect(session.conflicts.single.resultEndUtf16, 16);
      expect(session.isDirty, isTrue);
    } finally {
      session.dispose();
      doc.close();
    }
  }, skip: _bootstrap.skip);

  test('accepts all conflicts and preserves a missing final newline', () {
    const base = 'a\nm\nz';
    const input1 = 'A\nm\nours';
    const input2 = 'B\nm\ntheirs';
    final opened = _openSession(base: base, input1: input1, input2: input2);
    final doc = opened.document;
    final session = opened.session;
    try {
      expect(session.planAcceptAllCombinations(), isNull);
      expect(doc.resync().content, base);
      expect(session.conflictCount, 2);
      _applyPlan(
        doc,
        session,
        session.planAcceptAll(AlulaMergeSide.input2),
      );

      expect(doc.resync().content, input2);
      expect(session.unresolvedConflictCount, 0);
      expect(
        session.resolutions.values,
        everyElement(AlulaMergeSide.input2),
      );
    } finally {
      session.dispose();
      doc.close();
    }
  }, skip: _bootstrap.skip);

  test('accepts smart combinations and shifts later UTF-16 conflict ranges',
      () {
    const base = '\u{feff}😀\r\nleft=0; right=0\r\nmiddle\r\np=0; q=0';
    const input1 = '\u{feff}😀\r\nlong-left=1; right=0\r\nmiddle\r\np=1; q=0';
    const input2 = '\u{feff}😀\r\nleft=0; long-right=2\r\nmiddle\r\np=0; q=2';
    final opened = _openSession(base: base, input1: input1, input2: input2);
    final doc = opened.document;
    final session = opened.session;
    try {
      expect(session.conflicts, hasLength(2));
      final originalConflicts = List<AlulaMergeConflict>.of(session.conflicts);
      final candidates = [
        for (final conflict in originalConflicts)
          _bootstrap.core!.merge.combinationCandidate(
            base: conflict.baseText,
            input1: conflict.input1Text,
            input2: conflict.input2Text,
          )!,
      ];
      final plan = session.planAcceptAllCombinations();
      expect(plan, isNotNull);
      _applyPlan(doc, session, plan!);

      expect(
        doc.resync().content,
        '\u{feff}😀\r\nlong-left=1; long-right=2\r\nmiddle\r\np=1; q=2',
      );
      expect(session.unresolvedConflictCount, 0);
      expect(session.conflicts.map((conflict) => conflict.isCombination),
          everyElement(isTrue));
      expect(session.conflicts.map((conflict) => conflict.resolution),
          everyElement(isNull));
      expect(session.conflicts.first.resultStartUtf16,
          originalConflicts.first.resultStartUtf16);
      expect(
        session.conflicts[1].resultStartUtf16,
        originalConflicts[1].resultStartUtf16 +
            candidates.first.length -
            (originalConflicts.first.resultEndUtf16 -
                originalConflicts.first.resultStartUtf16),
      );
      for (var index = 0; index < session.conflicts.length; index++) {
        final conflict = session.conflicts[index];
        expect(
          doc
              .resync()
              .content
              .substring(conflict.resultStartUtf16, conflict.resultEndUtf16),
          candidates[index],
        );
      }

      _replaceDocument(doc, base);
      expect(session.reconcileCurrentResult(), isTrue);
      expect(session.unresolvedConflictCount, 2);
      expect(session.conflicts.map((conflict) => conflict.isCombination),
          everyElement(isFalse));

      _replaceDocument(doc, plan.projection.result);
      expect(session.reconcileCurrentResult(), isTrue);
      expect(session.unresolvedConflictCount, 0);
      expect(session.conflicts.map((conflict) => conflict.isCombination),
          everyElement(isTrue));
    } finally {
      session.dispose();
      doc.close();
    }
  }, skip: _bootstrap.skip);

  test('smart combination skips conflicts already accepted from Input 1', () {
    const base = 'left=0; right=0\nkeep\nother=0; value=0\n';
    const input1 = 'left=1; right=0\nkeep\nother=1; value=0\n';
    const input2 = 'left=0; right=2\nkeep\nother=0; value=2\n';
    final opened = _openSession(base: base, input1: input1, input2: input2);
    final doc = opened.document;
    final session = opened.session;
    try {
      expect(session.conflicts, hasLength(2));
      final firstId = session.conflicts.first.id;
      _applyPlan(
        doc,
        session,
        session.planResolveConflict(firstId, AlulaMergeSide.input1),
      );
      final plan = session.planAcceptAllCombinations();
      expect(plan, isNotNull);
      expect(plan!.combinationCandidates.keys, isNot(contains(firstId)));
      _applyPlan(doc, session, plan);

      expect(session.conflicts.first.resolution, AlulaMergeSide.input1);
      expect(session.conflicts.first.isCombination, isFalse);
      expect(session.conflicts.last.isCombination, isTrue);
      expect(session.unresolvedConflictCount, 0);
    } finally {
      session.dispose();
      doc.close();
    }
  }, skip: _bootstrap.skip);

  test('smart combination upgrades an Input 2 choice when append is disabled',
      () {
    const base = 'left=0; right=0\nkeep\nother=0; value=0\n';
    const input1 = 'left=1; right=0\nkeep\nother=1; value=0\n';
    const input2 = 'left=0; right=2\nkeep\nother=0; value=2\n';
    final opened = _openSession(base: base, input1: input1, input2: input2);
    final doc = opened.document;
    final session = opened.session;
    try {
      final firstId = session.conflicts.first.id;
      _applyPlan(
        doc,
        session,
        session.planResolveConflict(firstId, AlulaMergeSide.input2),
      );
      final plan = session.planAcceptAllCombinations();
      expect(plan, isNotNull);
      expect(plan!.combinationCandidates.keys, contains(firstId));
      _applyPlan(doc, session, plan);

      expect(session.conflicts.first.isCombination, isTrue);
      expect(session.conflicts.first.resolution, isNull);
      expect(
          doc.resync().content,
          input1
              .replaceFirst('left=1; right=0', 'left=1; right=2')
              .replaceFirst('other=1; value=0', 'other=1; value=2'));
      expect(session.unresolvedConflictCount, 0);
    } finally {
      session.dispose();
      doc.close();
    }
  }, skip: _bootstrap.skip);

  test('combines eligible conflicts and leaves overlapping edits unresolved',
      () {
    const base = 'left=0; right=0\nkeep\nvalue=0\n';
    const input1 = 'left=1; right=0\nkeep\nvalue=1\n';
    const input2 = 'left=0; right=2\nkeep\nvalue=2\n';
    final opened = _openSession(base: base, input1: input1, input2: input2);
    final doc = opened.document;
    final session = opened.session;
    try {
      expect(session.conflicts, hasLength(2));
      final firstId = session.conflicts.first.id;
      final plan = session.planAcceptAllCombinations();
      expect(plan, isNotNull);
      expect(plan!.combinationCandidates.keys, [firstId]);
      _applyPlan(doc, session, plan);

      expect(doc.resync().content, 'left=1; right=2\nkeep\nvalue=0\n');
      expect(session.conflicts.first.isCombination, isTrue);
      expect(session.conflicts.last.isCombination, isFalse);
      expect(session.conflicts.last.resolution, isNull);
      expect(session.unresolvedConflictCount, 1);
    } finally {
      session.dispose();
      doc.close();
    }
  }, skip: _bootstrap.skip);

  test('smart combination replaces a zero-width conflict contribution', () {
    const base = 'head\ntail\n';
    const input1 = 'head\nours\ntail\n';
    const input2 = 'head\ntheirs\ntail\n';
    final opened = _openSession(base: base, input1: input1, input2: input2);
    final doc = opened.document;
    final session = opened.session;
    try {
      expect(session.conflicts, hasLength(1));
      expect(session.conflicts.single.resultStartUtf16,
          session.conflicts.single.resultEndUtf16);
      final plan = session.planAcceptAllCombinations();
      expect(plan, isNotNull);
      _applyPlan(doc, session, plan!);

      expect(doc.resync().content, 'head\nours\ntheirs\ntail\n');
      final conflict = session.conflicts.single;
      expect(conflict.isCombination, isTrue);
      expect(conflict.resolution, isNull);
      expect(
        doc
            .resync()
            .content
            .substring(conflict.resultStartUtf16, conflict.resultEndUtf16),
        'ours\ntheirs\n',
      );
      expect(session.unresolvedConflictCount, 0);
    } finally {
      session.dispose();
      doc.close();
    }
  }, skip: _bootstrap.skip);

  test('fails the complete combination plan when one candidate exceeds limits',
      () {
    const smallBase = 'left=0; right=0';
    const smallInput1 = 'left=1; right=0';
    const smallInput2 = 'left=0; right=2';
    final largeBase = '${'a' * 720000}\n';
    final largeInput1 = 'X${'a' * 719999}\n';
    final largeInput2 = '${'a' * 719999}Y\n';
    final base = '$smallBase\nkeep\n$largeBase';
    final input1 = '$smallInput1\nkeep\n$largeInput1';
    final input2 = '$smallInput2\nkeep\n$largeInput2';
    final opened = _openSession(base: base, input1: input1, input2: input2);
    final doc = opened.document;
    final session = opened.session;
    final originalVersion = doc.resync().version;
    try {
      expect(session.conflicts, hasLength(2));
      expect(
        () => session.planAcceptAllCombinations(),
        throwsA(isA<AlulaMergeException>()),
      );
      expect(doc.resync().content, base);
      expect(doc.resync().version, originalVersion);
      expect(session.unresolvedConflictCount, 2);
      expect(session.resolutions, isEmpty);
      expect(session.conflicts.map((conflict) => conflict.isCombination),
          everyElement(isFalse));
    } finally {
      session.dispose();
      doc.close();
    }
  }, skip: _bootstrap.skip);

  test('keeps large repeated combination history reconcilable', () {
    final middle = '${'a' * 300000}|MIDDLE|${'b' * 300000}';
    final base = 'START=$middle|END\n';
    final input1 = 'BEGIN=$middle|END\n';
    final input2 = 'START=$middle|FINISH\n';
    final opened = _openSession(base: base, input1: input1, input2: input2);
    final doc = opened.document;
    final session = opened.session;
    try {
      expect(session.conflicts, hasLength(1));
      for (var cycle = 0; cycle < 20; cycle++) {
        final combination = session.planAcceptAllCombinations();
        expect(combination, isNotNull);
        _applyPlan(doc, session, combination!);
        _applyPlan(
          doc,
          session,
          session.planResolveConflict(
            session.conflicts.single.id,
            AlulaMergeSide.input2,
          ),
        );
      }

      expect(doc.resync().content, input2);
      _replaceDocument(doc, base);
      expect(session.reconcileCurrentResult(), isTrue);
      expect(session.unresolvedConflictCount, 1);
      _replaceDocument(doc, input2);
      expect(session.reconcileCurrentResult(), isTrue);
      expect(session.resolutions.values, [AlulaMergeSide.input2]);
      expect(session.unresolvedConflictCount, 0);
    } finally {
      session.dispose();
      doc.close();
    }
  }, skip: _bootstrap.skip);

  test('accepts zero-width insertion and deletion contributions', () {
    const insertionBase = '\u{feff}😀\r\nbefore\nafter\n';
    const insertionInput1 = '\u{feff}😀\r\nbefore\nours\nafter\n';
    const insertionInput2 = '\u{feff}😀\r\nbefore\ntheirs\nafter\n';
    final insertion = _openSession(
      base: insertionBase,
      input1: insertionInput1,
      input2: insertionInput2,
    );
    try {
      expect(insertion.session.conflicts.single.resultStartUtf16, 12);
      expect(insertion.session.conflicts.single.resultEndUtf16, 12);
      _applyPlan(
        insertion.document,
        insertion.session,
        insertion.session.planAcceptAll(AlulaMergeSide.input2),
      );
      expect(insertion.document.resync().content, insertionInput2);
      expect(insertion.session.conflicts.single.resultStartUtf16, 12);
      expect(insertion.session.conflicts.single.resultEndUtf16, 19);
    } finally {
      insertion.session.dispose();
      insertion.document.close();
    }

    const deletionBase = 'prefix\nremoved\nsuffix\n';
    const deletionInput1 = 'prefix\nsuffix\n';
    const deletionInput2 = 'prefix\nchanged\nsuffix\n';
    final deletion = _openSession(
      base: deletionBase,
      input1: deletionInput1,
      input2: deletionInput2,
    );
    try {
      _applyPlan(
        deletion.document,
        deletion.session,
        deletion.session.planAcceptAll(AlulaMergeSide.input1),
      );
      expect(deletion.document.resync().content, deletionInput1);
      expect(deletion.session.unresolvedConflictCount, 0);
    } finally {
      deletion.session.dispose();
      deletion.document.close();
    }
  }, skip: _bootstrap.skip);

  test('rejects stale plans and external Rust document mutations', () {
    final opened = _openSession(
      base: 'base\n',
      input1: 'left\n',
      input2: 'right\n',
    );
    final doc = opened.document;
    final session = opened.session;
    try {
      final first = session.planAcceptAll(AlulaMergeSide.input1);
      final stale = session.planAcceptAll(AlulaMergeSide.input2);
      _applyPlan(doc, session, first);
      expect(
        () => session.applyPlan(stale, appliedVersion: doc.version),
        throwsA(isA<MergeResultSessionException>().having(
          (error) => error.code,
          'code',
          MergeResultSessionErrorCode.stalePlan,
        )),
      );

      final beforeExternalMutation =
          session.planAcceptAll(AlulaMergeSide.input2);
      doc.apply([const TextOp.insert(0, 'external ')]);
      expect(
        () => session.validatePlan(beforeExternalMutation),
        throwsA(isA<MergeResultSessionException>().having(
          (error) => error.code,
          'code',
          MergeResultSessionErrorCode.staleResult,
        )),
      );
      expect(
        () => session.planAcceptAll(AlulaMergeSide.input2),
        throwsA(isA<MergeResultSessionException>().having(
          (error) => error.code,
          'code',
          MergeResultSessionErrorCode.staleResult,
        )),
      );
    } finally {
      session.dispose();
      doc.close();
    }
  }, skip: _bootstrap.skip);

  test('reconciles undo, redo, and manual result edits conservatively', () {
    final opened = _openSession(
      base: 'head\nold\ntail\n',
      input1: 'head\nours\ntail\n',
      input2: 'head\ntheirs\ntail\n',
    );
    final doc = opened.document;
    final session = opened.session;
    final unresolvedResult = session.projection.result;
    try {
      final plan = session.planResolveConflict(
        session.conflicts.single.id,
        AlulaMergeSide.input1,
      );
      _applyPlan(doc, session, plan);
      expect(session.unresolvedConflictCount, 0);
      expect(session.hasStaleConflictRanges, isFalse);

      _replaceDocument(doc, unresolvedResult);
      expect(session.reconcileCurrentResult(), isTrue);
      expect(session.unresolvedConflictCount, 1);
      expect(session.hasStaleConflictRanges, isFalse);

      _replaceDocument(doc, plan.projection.result);
      expect(session.reconcileCurrentResult(), isTrue);
      expect(session.unresolvedConflictCount, 0);

      _replaceDocument(doc, 'manual result\n');
      expect(
        session.reconcileCurrentResult(allowKnownProjectionRestore: false),
        isFalse,
      );
      expect(session.hasStaleConflictRanges, isTrue);
      expect(session.unresolvedConflictCount, session.conflictCount);
      expect(
          session.closePrompt.unresolvedConflictCount, session.conflictCount);
    } finally {
      session.dispose();
      doc.close();
    }
  }, skip: _bootstrap.skip);

  test('dirty unresolved close saves with conflicts and marks its savepoint',
      () async {
    final opened = _openSession(
      base: 'base\n',
      input1: 'left\n',
      input2: 'right\n',
    );
    final doc = opened.document;
    final session = opened.session;
    final directory = await Directory.systemTemp.createTemp('alula-merge-');
    final path = '${directory.path}${Platform.pathSeparator}result.txt';
    var closeCalls = 0;
    try {
      doc.apply([const TextOp.insert(5, 'manual ')]);
      expect(session.closePrompt.unresolvedConflictCount, 1);
      expect(session.closePrompt.saveLabel,
          MergeResultSaveLabel.saveWithConflicts);

      final failed = await session.finishClose(
        MergeResultCloseAction.save,
        save: () async => false,
        revert: () async => false,
        closeResultDocument: () async {
          closeCalls++;
        },
      );
      expect(failed, MergeResultCloseOutcome.saveFailed);
      expect(session.isDisposed, isFalse);
      expect(session.isDirty, isTrue);
      expect(closeCalls, 0);

      final saved = await session.finishClose(
        MergeResultCloseAction.save,
        save: () async {
          doc.saveFile(path);
          return true;
        },
        revert: () async => false,
        closeResultDocument: () async {
          expect(session.latestSavedResult, 'base\nmanual ');
          closeCalls++;
          doc.close();
        },
      );
      expect(saved, MergeResultCloseOutcome.closed);
      expect(await File(path).readAsString(), 'base\nmanual ');
      expect(session.isDisposed, isTrue);
      expect(closeCalls, 1);
    } finally {
      if (!session.isDisposed) session.dispose();
      if (closeCalls == 0) doc.close();
      await directory.delete(recursive: true);
    }
  }, skip: _bootstrap.skip);

  test(
      'discard requires a successful revert to the saved result; cancel is inert',
      () async {
    const base = 'base\n';
    const input1 = 'left\n';
    const input2 = 'right\n';
    final opened = _openSession(base: base, input1: input1, input2: input2);
    final doc = opened.document;
    final session = opened.session;
    var closeCalls = 0;
    final savedResult = session.latestSavedResult;
    try {
      _applyPlan(
        doc,
        session,
        session.planAcceptAll(AlulaMergeSide.input1),
      );
      final cancelled = await session.finishClose(
        MergeResultCloseAction.cancel,
        save: () async => fail('cancel must not save'),
        revert: () async => fail('cancel must not revert'),
        closeResultDocument: () async {
          closeCalls++;
        },
      );
      expect(cancelled, MergeResultCloseOutcome.cancelled);
      expect(session.isDirty, isTrue);

      final revertedWithoutCleanSavepoint = await session.finishClose(
        MergeResultCloseAction.discard,
        save: () async => false,
        revert: () async => true,
        closeResultDocument: () async {
          closeCalls++;
        },
      );
      expect(
          revertedWithoutCleanSavepoint, MergeResultCloseOutcome.revertFailed);
      expect(session.isDisposed, isFalse);

      final discarded = await session.finishClose(
        MergeResultCloseAction.discard,
        save: () async => false,
        revert: () async {
          _replaceDocument(doc, savedResult);
          doc.setSavepoint(savedResult);
          return true;
        },
        closeResultDocument: () async {
          expect(doc.isDirty, isFalse);
          closeCalls++;
          doc.close();
        },
      );
      expect(discarded, MergeResultCloseOutcome.closed);
      expect(closeCalls, 1);
      expect(session.isDisposed, isTrue);
    } finally {
      if (!session.isDisposed) session.dispose();
      if (closeCalls == 0) doc.close();
    }
  }, skip: _bootstrap.skip);

  test('clean unresolved results require explicit close-with-conflicts',
      () async {
    final opened = _openSession(
      base: 'base\n',
      input1: 'left\n',
      input2: 'right\n',
    );
    final doc = opened.document;
    final session = opened.session;
    try {
      expect(session.isDirty, isFalse);
      expect(session.closePrompt.unresolvedConflictCount, 1);
      expect(
        session.closePrompt.actions,
        containsAll({
          MergeResultCloseAction.closeWithConflicts,
          MergeResultCloseAction.cancel,
        }),
      );
      expect(
        session.closePrompt.actions,
        isNot(contains(MergeResultCloseAction.close)),
      );

      final outcome = await session.finishClose(
        MergeResultCloseAction.closeWithConflicts,
        save: () async => false,
        revert: () async => false,
        closeResultDocument: () async => doc.close(),
      );
      expect(outcome, MergeResultCloseOutcome.closed);
      expect(session.isDisposed, isTrue);
    } finally {
      if (!session.isDisposed) {
        session.dispose();
        doc.close();
      }
    }
  }, skip: _bootstrap.skip);

  test('clean resolved results close directly; disposed sessions reject access',
      () async {
    final opened = _openSession(
      base: 'base\n',
      input1: 'left\n',
      input2: 'right\n',
    );
    final doc = opened.document;
    final session = opened.session;
    try {
      _applyPlan(
        doc,
        session,
        session.planAcceptAll(AlulaMergeSide.input1),
      );
      doc.markSaved();
      expect(session.closePrompt.actions, {MergeResultCloseAction.close});

      final outcome = await session.finishClose(
        MergeResultCloseAction.close,
        save: () async => false,
        revert: () async => false,
        closeResultDocument: () async => doc.close(),
      );
      expect(outcome, MergeResultCloseOutcome.closed);
      expect(session.isDisposed, isTrue);
      expect(
        () => session.projection,
        throwsA(isA<MergeResultSessionException>().having(
          (error) => error.code,
          'code',
          MergeResultSessionErrorCode.disposed,
        )),
      );
    } finally {
      if (!session.isDisposed) {
        session.dispose();
        doc.close();
      }
    }
  }, skip: _bootstrap.skip);
}
