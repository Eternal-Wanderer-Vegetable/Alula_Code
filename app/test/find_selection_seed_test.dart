import 'package:alula_app/editor/find_replace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Find selection seed length follows the strict UTF-16 limit', () {
    expect(isFindSelectionSeedLengthSupported(0), isFalse);
    expect(isFindSelectionSeedLengthSupported(1), isTrue);
    expect(isFindSelectionSeedLengthSupported(524287), isTrue);
    expect(isFindSelectionSeedLengthSupported(524288), isFalse);
    expect(isFindSelectionSeedLengthSupported(524289), isFalse);
  });

  test('default Find word pattern includes edge positions and float tokens',
      () {
    expect(defaultFindWordAtPosition('foo.bar', 0), 'foo');
    expect(defaultFindWordAtPosition('foo.bar', 3), 'foo');
    expect(defaultFindWordAtPosition('foo.bar', 4), 'bar');
    expect(defaultFindWordAtPosition('-12.5e3 + next', 4), '-12.5e3');
    expect(defaultFindWordAtPosition('  only  ', 3), 'only');
    expect(defaultFindWordAtPosition('  only  ', 5), 'only');
    expect(defaultFindWordAtPosition('  +  ', 2), isNull);
    expect(defaultFindWordAtPosition('foo', -1), isNull);
    expect(defaultFindWordAtPosition('foo', 4), isNull);
  });

  test('default Find word offsets remain UTF-16 across supplementary text', () {
    const text = '🍁alpha';
    expect(text.length, 7);
    expect(defaultFindWordAtPosition(text, 4), '🍁alpha');
  });
}
