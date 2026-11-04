// Real Dart -> C ABI -> Rust merge projection round-trip.
import 'dart:convert';

import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/bridge/alula_ffi.dart';
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

void main() {
  test('Dart ABI guard accepts v38 and rejects an older native library', () {
    AlulaCore.validateAbiVersion(38);
    expect(() => AlulaCore.validateAbiVersion(37), throwsStateError);
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
}
