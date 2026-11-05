import 'dart:math' as math;

import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/editor/occurrence_search.dart';
import 'package:flutter_test/flutter_test.dart';

TextRangeRead _readTextRange(String text, int startUtf16,
    {required int maxLenUtf16}) {
  var end = math.min(text.length, startUtf16 + maxLenUtf16);
  if (end < text.length &&
      end > startUtf16 &&
      _isHighSurrogate(text.codeUnitAt(end - 1)) &&
      _isLowSurrogate(text.codeUnitAt(end))) {
    end--;
  }
  if (end == startUtf16 &&
      end < text.length - 1 &&
      _isHighSurrogate(text.codeUnitAt(end)) &&
      _isLowSurrogate(text.codeUnitAt(end + 1))) {
    end += 2;
  }
  return TextRangeRead(
    version: 1,
    totalUtf16Length: text.length,
    lineCount: 1,
    startUtf16: startUtf16,
    endUtf16: end,
    startLine: 0,
    startCharacter: startUtf16,
    text: text.substring(startUtf16, end),
  );
}

bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

void main() {
  test('finds matches that cross a bounded range with UTF-16 offsets', () {
    const prefix = '\uFEFF🦊\r\n';
    final filler = List.filled(
      maxDocReadRangeUtf16 - 1 - prefix.length,
      'x',
    ).join();
    final text = '$prefix${filler}cat\r\n🦊cat';
    final expected = [text.indexOf('cat'), text.lastIndexOf('cat')];
    final requestedLengths = <int>[];

    final actual = findTextOccurrenceOffsets(
      needle: 'cat',
      totalUtf16Length: text.length,
      readRange: (start, {required maxLenUtf16}) {
        requestedLengths.add(maxLenUtf16);
        return _readTextRange(text, start, maxLenUtf16: maxLenUtf16);
      },
    ).toList();

    expect(expected.first, maxDocReadRangeUtf16 - 1);
    expect(actual, expected);
    expect(requestedLengths,
        everyElement(lessThanOrEqualTo(maxDocReadRangeUtf16)));
  });

  test('respects range bounds, non-overlap, and stops at the requested count',
      () {
    const text = 'aaaaa -- aa';
    final matches = findTextOccurrenceOffsets(
      needle: 'aa',
      totalUtf16Length: text.length,
      startUtf16: 1,
      endUtf16: 5,
      maxMatches: 2,
      readRange: (start, {required maxLenUtf16}) =>
          _readTextRange(text, start, maxLenUtf16: maxLenUtf16),
    ).toList();

    expect(matches, [1, 3]);
  });

  test('does not read later pages after reaching the match limit', () {
    final text = List.filled(maxDocReadRangeUtf16 * 4, 'x').join();
    var reads = 0;

    final matches = findTextOccurrenceOffsets(
      needle: 'x',
      totalUtf16Length: text.length,
      maxMatches: 3,
      readRange: (start, {required maxLenUtf16}) {
        reads++;
        return _readTextRange(text, start, maxLenUtf16: maxLenUtf16);
      },
    ).toList();

    expect(matches, [0, 1, 2]);
    expect(reads, 1);
  });
}
