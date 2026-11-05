import 'dart:io';

import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/editor/merge_result_session.dart';
import 'package:flutter_test/flutter_test.dart';

class _AcceptBootstrap {
  _AcceptBootstrap() {
    try {
      core = AlulaCore.load();
    } catch (error) {
      skip = 'alula_core is unavailable; build it first ($error)';
    }
  }

  AlulaCore? core;
  String? skip;
}

final _bootstrap = _AcceptBootstrap();
var _nextDocumentId = 790000;

({AlulaDoc document, MergeResultSession session}) _openSession({
  required String base,
  required String input1,
  required String input2,
}) {
  final core = _bootstrap.core!;
  final projection = core.merge.project(
    base: base,
    input1: input1,
    input2: input2,
  );
  final document = core.openDoc(_nextDocumentId++, projection.result);
  try {
    return (
      document: document,
      session: MergeResultSession.open(
        mergeApi: core.merge,
        resultDocument: document,
        base: base,
        input1: input1,
        input2: input2,
      ),
    );
  } catch (_) {
    document.close();
    rethrow;
  }
}

void main() {
  test(
      'unresolved conflicts require explicit confirmation without side effects',
      () async {
    final opened = _openSession(
      base: 'old\n',
      input1: 'left\n',
      input2: 'right\n',
    );
    final document = opened.document;
    final session = opened.session;
    var saveCalls = 0;
    var closeCalls = 0;
    try {
      final before = document.resync();
      final outcome = await session.finishAccept(
        confirmedWithConflicts: false,
        save: () async {
          saveCalls++;
          return true;
        },
        closeResultDocument: () async => closeCalls++,
      );
      expect(outcome, MergeResultCloseOutcome.cancelled);
      expect(document.resync().content, before.content);
      expect(document.resync().version, before.version);
      expect(session.isDisposed, isFalse);
      expect(session.isDirty, isFalse);
      expect(saveCalls, 0);
      expect(closeCalls, 0);
    } finally {
      if (!session.isDisposed) session.dispose();
      document.close();
    }
  }, skip: _bootstrap.skip);

  test('confirmed completion saves the result before closing the session',
      () async {
    final opened = _openSession(
      base: 'old\n',
      input1: 'left\n',
      input2: 'right\n',
    );
    final document = opened.document;
    final session = opened.session;
    final directory =
        await Directory.systemTemp.createTemp('alula-merge-accept-');
    final path = '${directory.path}${Platform.pathSeparator}result.txt';
    var closeCalls = 0;
    try {
      final expected = document.resync().content;
      final outcome = await session.finishAccept(
        confirmedWithConflicts: true,
        save: () async {
          document.saveFile(path);
          return true;
        },
        closeResultDocument: () async {
          expect(session.latestSavedResult, expected);
          expect(document.isDirty, isFalse);
          closeCalls++;
          document.close();
        },
      );
      expect(outcome, MergeResultCloseOutcome.closed);
      expect(await File(path).readAsString(), expected);
      expect(session.isDisposed, isTrue);
      expect(closeCalls, 1);
    } finally {
      if (!session.isDisposed) session.dispose();
      if (closeCalls == 0) document.close();
      await directory.delete(recursive: true);
    }
  }, skip: _bootstrap.skip);

  test('zero-conflict completion needs no confirmation and saves dirty text',
      () async {
    final opened = _openSession(
      base: 'same\n',
      input1: 'same\n',
      input2: 'same\n',
    );
    final document = opened.document;
    final session = opened.session;
    final directory =
        await Directory.systemTemp.createTemp('alula-merge-accept-');
    final path = '${directory.path}${Platform.pathSeparator}result.txt';
    var saveCalls = 0;
    var closeCalls = 0;
    try {
      expect(session.unresolvedConflictCount, 0);
      document.apply([const TextOp.insert(5, 'edited')]);
      final expected = document.resync().content;
      final outcome = await session.finishAccept(
        confirmedWithConflicts: false,
        save: () async {
          saveCalls++;
          document.saveFile(path);
          return true;
        },
        closeResultDocument: () async {
          closeCalls++;
          document.close();
        },
      );
      expect(outcome, MergeResultCloseOutcome.closed);
      expect(saveCalls, 1);
      expect(closeCalls, 1);
      expect(await File(path).readAsString(), expected);
      expect(session.isDisposed, isTrue);
    } finally {
      if (!session.isDisposed) session.dispose();
      if (closeCalls == 0) document.close();
      await directory.delete(recursive: true);
    }
  }, skip: _bootstrap.skip);

  test('save failure and result changes during save leave the session active',
      () async {
    final opened = _openSession(
      base: 'old\n',
      input1: 'left\n',
      input2: 'right\n',
    );
    final document = opened.document;
    final session = opened.session;
    final directory =
        await Directory.systemTemp.createTemp('alula-merge-accept-');
    final path = '${directory.path}${Platform.pathSeparator}result.txt';
    var closeCalls = 0;
    try {
      final failed = await session.finishAccept(
        confirmedWithConflicts: true,
        save: () async => false,
        closeResultDocument: () async => closeCalls++,
      );
      expect(failed, MergeResultCloseOutcome.saveFailed);
      expect(session.isDisposed, isFalse);
      expect(closeCalls, 0);

      final changed = await session.finishAccept(
        confirmedWithConflicts: true,
        save: () async {
          document.apply([const TextOp.insert(0, 'changed ')]);
          document.saveFile(path);
          return true;
        },
        closeResultDocument: () async => closeCalls++,
      );
      expect(changed, MergeResultCloseOutcome.resultChangedDuringSave);
      expect(session.isDisposed, isFalse);
      expect(closeCalls, 0);
    } finally {
      if (!session.isDisposed) session.dispose();
      document.close();
      await directory.delete(recursive: true);
    }
  }, skip: _bootstrap.skip);
}
