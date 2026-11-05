// Real Dart -> C ABI -> Rust merge projection round-trip.
import 'dart:convert';

import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/bridge/alula_ffi.dart';
import 'package:alula_app/bridge/alula_merge.dart';
import 'package:flutter_test/flutter_test.dart';

class _MergeBootstrap {
  final AlulaCore? core;
  final AlulaFfi? ffi;
  final String? error;

  _MergeBootstrap._(this.core, this.ffi, this.error);

  factory _MergeBootstrap() {
    try {
      return _MergeBootstrap._(
        AlulaCore.load(),
        AlulaFfi(loadAlulaCore()),
        null,
      );
    } catch (error) {
      return _MergeBootstrap._(null, null, 'alula_core 未构建：$error');
    }
  }
}

final _MergeBootstrap _bootstrap = _MergeBootstrap();
final String? _skip = _bootstrap.error;

void _expectConflictSlicesMatchResult(AlulaMergeProjection projection) {
  var previousEndUtf16 = 0;
  for (final conflict in projection.conflicts) {
    expect(conflict.resultStartUtf16, greaterThanOrEqualTo(previousEndUtf16));
    expect(conflict.resultEndUtf16,
        greaterThanOrEqualTo(conflict.resultStartUtf16));
    expect(
        conflict.resultEndUtf16, lessThanOrEqualTo(projection.result.length));
    final contribution = switch (conflict.resolution) {
      AlulaMergeSide.input1 => conflict.input1Text,
      AlulaMergeSide.input2 => conflict.input2Text,
      null => conflict.baseText,
    };
    expect(
      projection.result.substring(
        conflict.resultStartUtf16,
        conflict.resultEndUtf16,
      ),
      contribution,
    );
    previousEndUtf16 = conflict.resultEndUtf16;
  }
}

void main() {
  test('Dart ABI guard accepts v40 and rejects v39', () {
    AlulaCore.validateAbiVersion(40);
    expect(() => AlulaCore.validateAbiVersion(39), throwsStateError);
  });

  test('real FFI projection reports unresolved and accepted conflicts', () {
    final core = _bootstrap.core!;
    final unresolved = core.merge.project(
      base: 'a\nm\nz\n',
      input1: 'A\nm\nUP1\n',
      input2: 'B\nm\nDOWN2\n',
    );
    expect(unresolved.result, 'a\nm\nz\n');
    expect(unresolved.conflictCount, 2);
    expect(unresolved.unresolvedConflictCount, 2);
    expect(unresolved.conflicts.first.baseStartLine, 0);
    expect(unresolved.conflicts.first.baseEndLineExclusive, 1);
    _expectConflictSlicesMatchResult(unresolved);

    final resolved = core.merge.project(
      base: 'a\nm\nz\n',
      input1: 'A\nm\nUP1\n',
      input2: 'B\nm\nDOWN2\n',
      acceptAll: AlulaMergeSide.input1,
      resolutions: const {1: AlulaMergeSide.input2},
    );
    expect(resolved.result, 'A\nm\nDOWN2\n');
    expect(resolved.unresolvedConflictCount, 0);
    expect(resolved.conflicts[0].resolution, AlulaMergeSide.input1);
    expect(resolved.conflicts[1].resolution, AlulaMergeSide.input2);
    _expectConflictSlicesMatchResult(resolved);
  }, skip: _skip);

  test('real FFI result ranges shift with Unicode choices and allow deletion',
      () {
    final core = _bootstrap.core!;
    const base = '\u{feff}😀\r\nold\r\nmiddle\rold2\n';
    const input1 = '\u{feff}😀\r\nlonger 🦊\r\nmiddle\rours2\n';
    const input2 = '\u{feff}😀\r\nincoming\r\nmiddle\rother2';

    final unresolved = core.merge.project(
      base: base,
      input1: input1,
      input2: input2,
    );
    expect(unresolved.conflicts, hasLength(2));
    expect(unresolved.conflicts[0].resultStartUtf16, 5);
    expect(unresolved.conflicts[0].resultEndUtf16, 10);
    expect(unresolved.conflicts[1].resultStartUtf16, 17);
    expect(unresolved.conflicts[1].resultEndUtf16, 22);
    _expectConflictSlicesMatchResult(unresolved);

    final firstResolved = core.merge.project(
      base: base,
      input1: input1,
      input2: input2,
      resolutions: const {0: AlulaMergeSide.input1},
    );
    expect(firstResolved.conflicts[1].resultStartUtf16, 23);
    expect(firstResolved.conflicts[1].resultEndUtf16, 28);
    _expectConflictSlicesMatchResult(firstResolved);

    final bothResolved = core.merge.project(
      base: base,
      input1: input1,
      input2: input2,
      resolutions: const {
        0: AlulaMergeSide.input1,
        1: AlulaMergeSide.input2,
      },
    );
    expect(bothResolved.result, '\u{feff}😀\r\nlonger 🦊\r\nmiddle\rother2');
    expect(bothResolved.conflicts[1].resultStartUtf16, 23);
    expect(bothResolved.conflicts[1].resultEndUtf16, 29);
    _expectConflictSlicesMatchResult(bothResolved);

    final deletion = core.merge.project(
      base: 'prefix\nremoved\nsuffix\n',
      input1: 'prefix\nsuffix\n',
      input2: 'prefix\nchanged\nsuffix\n',
      resolutions: const {0: AlulaMergeSide.input1},
    );
    expect(deletion.result, 'prefix\nsuffix\n');
    expect(deletion.conflicts.single.resultStartUtf16, 7);
    expect(deletion.conflicts.single.resultEndUtf16, 7);
    _expectConflictSlicesMatchResult(deletion);

    final insertion = core.merge.project(
      base: 'before\nafter\n',
      input1: 'before\nours\nafter\n',
      input2: 'before\ntheirs\nafter\n',
    );
    expect(insertion.conflicts.single.baseStartLine, 1);
    expect(insertion.conflicts.single.baseEndLineExclusive, 1);
    expect(insertion.conflicts.single.resultStartUtf16, 7);
    expect(insertion.conflicts.single.resultEndUtf16, 7);
    _expectConflictSlicesMatchResult(insertion);

    final acceptedInsertion = core.merge.project(
      base: 'before\nafter\n',
      input1: 'before\nours\nafter\n',
      input2: 'before\ntheirs\nafter\n',
      resolutions: const {0: AlulaMergeSide.input2},
    );
    expect(acceptedInsertion.result, 'before\ntheirs\nafter\n');
    expect(acceptedInsertion.conflicts.single.resultStartUtf16, 7);
    expect(acceptedInsertion.conflicts.single.resultEndUtf16, 14);
    _expectConflictSlicesMatchResult(acceptedInsertion);
  }, skip: _skip);

  test('real FFI projection preserves BOM, emoji, CRLF, CR and final newline',
      () {
    final projection = _bootstrap.core!.merge.project(
      base: '\u{feff}🦊\r\nbase\rend\n',
      input1: '\u{feff}🦊\r\nours\rend\n',
      input2: '\u{feff}🦊\r\nbase\rtheirs\n',
    );
    expect(projection.result, '\u{feff}🦊\r\nours\rtheirs\n');
    expect(projection.conflicts, isEmpty);

    final noFinalNewline = _bootstrap.core!.merge.project(
      base: 'base',
      input1: 'left',
      input2: 'right',
      resolutions: const {0: AlulaMergeSide.input2},
    );
    expect(noFinalNewline.result, 'right');
  }, skip: _skip);

  test('real FFI combination candidate returns a complete non-overlapping edit',
      () {
    final candidate = _bootstrap.core!.merge.combinationCandidate(
      base: 'left=0\nright=0\n',
      input1: 'left=1\nright=0\n',
      input2: 'left=0\nright=2\n',
    );
    expect(candidate, 'left=1\nright=2\n');

    final overlap = _bootstrap.core!.merge.combinationCandidate(
      base: 'value=0\n',
      input1: 'value=1\n',
      input2: 'value=2\n',
    );
    expect(overlap, isNull);

    final unchanged = _bootstrap.core!.merge.combinationCandidate(
      base: 'base',
      input1: 'changed',
      input2: 'base',
    );
    expect(unchanged, isNull);
  }, skip: _skip);

  test('real FFI combination candidate preserves BOM and mixed line endings',
      () {
    final candidate = _bootstrap.core!.merge.combinationCandidate(
      base: '\u{feff}🦊\r\nleft=0\rright=0\nend=0',
      input1: '\u{feff}🦊\r\nleft=1\rright=0\nend=0',
      input2: '\u{feff}🦊\r\nleft=0\rright=2\nend=0',
    );
    expect(candidate, '\u{feff}🦊\r\nleft=1\rright=2\nend=0');
  }, skip: _skip);

  test('real FFI combination candidate reports bounded input and parse errors',
      () {
    final ffi = _bootstrap.ffi!;
    final malformed = jsonDecode(ffi.mergeCombinationCandidateJson('{')) as Map;
    expect(malformed['ok'], false);
    expect((malformed['error'] as Map)['code'], 'InvalidArgument');

    final unknownField = jsonDecode(ffi.mergeCombinationCandidateJson(
      '{"base":"a","input1":"b","input2":"c","extra":true}',
    )) as Map;
    expect(unknownField['ok'], false);
    expect((unknownField['error'] as Map)['code'], 'InvalidArgument');

    expect(
      () => _bootstrap.core!.merge.combinationCandidate(
        base: 'x'.padRight(2 * 1024 * 1024 + 1, 'x'),
        input1: '',
        input2: '',
      ),
      throwsA(
        isA<AlulaMergeException>().having(
          (error) => error.code,
          'code',
          'MergeCombinationLimit',
        ),
      ),
    );
  }, skip: _skip);

  test('typed combination candidate response rejects malformed envelopes', () {
    expect(
      () => AlulaMergeCombinationCandidateResponse.fromJson({'ok': true}),
      throwsFormatException,
    );
    expect(
      () => AlulaMergeCombinationCandidateResponse.fromJson({
        'ok': true,
        'candidateText': 42,
      }),
      throwsFormatException,
    );
    expect(
      () => AlulaMergeCombinationCandidateResponse.fromJson({
        'ok': false,
        'error': {'code': 'MergeCombinationLimit', 'detail': null},
      }),
      throwsA(isA<AlulaMergeException>()),
    );
  });

  test('real FFI reports malformed and unknown-conflict requests', () {
    final ffi = _bootstrap.ffi!;
    final malformed = jsonDecode(ffi.mergeProjectJson('{')) as Map;
    expect(malformed['ok'], false);
    expect((malformed['error'] as Map)['code'], 'InvalidArgument');

    expect(
      () => _bootstrap.core!.merge.project(
        base: 'base',
        input1: 'left',
        input2: 'right',
        resolutions: const {9: AlulaMergeSide.input1},
      ),
      throwsA(
        isA<AlulaMergeException>().having(
          (error) => error.code,
          'code',
          'UnknownConflict',
        ),
      ),
    );
  }, skip: _skip);

  test('typed projection rejects conflict ranges that do not match result', () {
    expect(
      () => AlulaMergeProjection.fromJson({
        'result': 'result',
        'conflictCount': 1,
        'unresolvedConflictCount': 1,
        'conflicts': [
          {
            'id': 0,
            'baseStartLine': 0,
            'baseEndLineExclusive': 1,
            'resultStartUtf16': 0,
            'resultEndUtf16': 1,
            'baseText': 'wrong',
            'input1Text': 'left',
            'input2Text': 'right',
            'resolution': null,
          },
        ],
      }),
      throwsFormatException,
    );
  });
}
