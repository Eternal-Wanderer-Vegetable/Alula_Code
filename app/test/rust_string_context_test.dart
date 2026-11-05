import 'package:alula_app/editor/rust_string_context.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tokens = <Map<String, Object?>>[
    {'start_utf16': 0, 'end_utf16': 2, 'kind': 'keyword'},
    {'start_utf16': 4, 'end_utf16': 9, 'kind': 'string'},
    {'start_utf16': 12, 'end_utf16': 16, 'kind': 'string.special'},
  ];

  test('string lookup uses UTF-16 token boundaries', () {
    RustStringContext at(int offset) => rustStringContextAt(
          tokens: tokens,
          tokenVersion: 7,
          documentVersion: 7,
          offsetUtf16: offset,
        );

    expect(at(3), RustStringContext.outside);
    expect(at(4), RustStringContext.outside);
    expect(at(5), RustStringContext.inside);
    expect(at(8), RustStringContext.inside);
    expect(at(9), RustStringContext.outside);
    expect(at(14), RustStringContext.inside);
    expect(at(16), RustStringContext.outside);
  });

  test('stale or malformed token snapshots return unknown', () {
    expect(
      rustStringContextAt(
        tokens: tokens,
        tokenVersion: 6,
        documentVersion: 7,
        offsetUtf16: 5,
      ),
      RustStringContext.unknown,
    );
    expect(
      rustStringContextAt(
        tokens: const [
          {'start_utf16': 1, 'kind': 'string'},
        ],
        tokenVersion: 7,
        documentVersion: 7,
        offsetUtf16: 2,
      ),
      RustStringContext.unknown,
    );
  });

  test('UTF-16 offsets after an emoji do not split the preceding token', () {
    const afterEmoji = <Map<String, Object?>>[
      {'start_utf16': 2, 'end_utf16': 7, 'kind': 'string'},
    ];

    expect(
      rustStringContextAt(
        tokens: afterEmoji,
        tokenVersion: 1,
        documentVersion: 1,
        offsetUtf16: 3,
      ),
      RustStringContext.inside,
    );
  });
}
