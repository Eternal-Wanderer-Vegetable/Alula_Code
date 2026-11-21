import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/workbench/goto_position.dart';
import 'package:flutter_test/flutter_test.dart';

class _Bootstrap {
  _Bootstrap() {
    try {
      core = AlulaCore.load();
    } catch (error) {
      skip = 'alula_core is unavailable; build it first ($error)';
    }
  }

  AlulaCore? core;
  String? skip;
}

final _bootstrap = _Bootstrap();

void main() {
  test('resolves line, visible column, BOM, CRLF, tab, fullwidth, and emoji',
      () {
    final doc = _bootstrap.core!.openDoc(
      98731,
      '\uFEFFhead\r\n\t😀漢wide\r\nlast\n',
    );
    addTearDown(doc.close);

    expect(resolveGotoPosition(doc, ':1')!.offsetUtf16, 0);
    expect(resolveGotoPosition(doc, ':2:1')!.offsetUtf16, 7);
    expect(resolveGotoPosition(doc, ':2:5')!.offsetUtf16, 8);
    expect(resolveGotoPosition(doc, ':2:7')!.offsetUtf16, 10);
    expect(resolveGotoPosition(doc, ':2:-1')!.offsetUtf16, 14);
    expect(resolveGotoPosition(doc, ':2:999')!.offsetUtf16, 15);
    expect(resolveGotoPosition(doc, ':2:7')!.line, 1);
    expect(resolveGotoPosition(doc, ':2:7')!.column, 3);
  }, skip: _bootstrap.skip != null);

  test('preserves Code-OSS parseInt prefixes and negative lines', () {
    final doc = _bootstrap.core!.openDoc(98732, 'one\ntwo\nthree');
    addTearDown(doc.close);

    expect(resolveGotoPosition(doc, ':2junk:2tail')!.offsetUtf16, 5);
    expect(resolveGotoPosition(doc, ':-1')!.line, 2);
    expect(resolveGotoPosition(doc, ':-100')!.line, 0);
    expect(resolveGotoPosition(doc, ':2:missing')!.column, 0);
    expect(resolveGotoPosition(doc, ':'), isNull);
    expect(resolveGotoPosition(doc, ''), isNull);
    expect(
      () => resolveGotoPosition(doc, ':missing'),
      throwsA(isA<FormatException>()),
    );
  }, skip: _bootstrap.skip != null);

  test('resolves one-based and zero-based offsets from either end', () {
    final doc = _bootstrap.core!.openDoc(98733, 'a😀\nb');
    addTearDown(doc.close);

    expect(resolveGotoPosition(doc, '::1')!.offsetUtf16, 0);
    expect(resolveGotoPosition(doc, '::4')!.offsetUtf16, 3);
    expect(resolveGotoPosition(doc, '::-1')!.offsetUtf16, 5);
    expect(resolveGotoPosition(doc, '::999')!.offsetUtf16, 5);
    expect(
      resolveGotoPosition(doc, '::4', zeroBasedOffset: true)!.offsetUtf16,
      4,
    );
    expect(
      resolveGotoPosition(doc, '::-1', zeroBasedOffset: true)!.offsetUtf16,
      4,
    );
    expect(resolveGotoPosition(doc, '::4tail')!.offsetUtf16, 3);
  }, skip: _bootstrap.skip != null);

  test('long lines stream bounded chunks without losing tail positions', () {
    const length = maxDocReadRangeUtf16 + 17;
    final doc = _bootstrap.core!.openDoc(98734, '${'x' * length}😀z');
    addTearDown(doc.close);
    expect(resolveGotoPosition(doc, ':1:2')!.offsetUtf16, 1);
    expect(
        resolveGotoPosition(doc, ':1:${length + 3}')!.offsetUtf16, length + 2);
    expect(resolveGotoPosition(doc, ':1:-1')!.offsetUtf16, length + 2);
    expect(resolveGotoPosition(doc, ':1:9999999')!.offsetUtf16, length + 3);
  }, skip: _bootstrap.skip != null);
}
