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

      _replaceDocument(doc, unresolvedResult);
      expect(session.reconcileCurrentResult(), isTrue);
      expect(session.unresolvedConflictCount, 1);

      _replaceDocument(doc, plan.projection.result);
      expect(session.reconcileCurrentResult(), isTrue);
      expect(session.unresolvedConflictCount, 0);

      _replaceDocument(doc, 'manual result\n');
      expect(
        session.reconcileCurrentResult(allowKnownProjectionRestore: false),
        isFalse,
      );
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
