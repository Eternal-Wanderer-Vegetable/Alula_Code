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
}
