/// Unicode 16.0 unconditional full uppercase mappings absent from simple casing.
/// Source: https://www.unicode.org/Public/16.0.0/ucd/SpecialCasing.txt
///
/// UNICODE LICENSE V3 — COPYRIGHT AND PERMISSION NOTICE
/// Copyright © 1991-2024 Unicode, Inc.
/// Permission is hereby granted, free of charge, to any person obtaining a
/// copy of data files and any associated documentation (the "Data Files") or
/// software and any associated documentation (the "Software") to deal in the
/// Data Files or Software without restriction, including without limitation
/// the rights to use, copy, modify, merge, publish, distribute, and/or sell
/// copies of the Data Files or Software, and to permit persons to whom the
/// Data Files or Software are furnished to do so, provided that either (a)
/// this copyright and permission notice appear with all copies of the Data
/// Files or Software, or (b) this copyright and permission notice appear in
/// associated Documentation.
/// THE DATA FILES AND SOFTWARE ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
/// KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
/// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF
/// THIRD PARTY RIGHTS.
/// IN NO EVENT SHALL THE COPYRIGHT HOLDER OR HOLDERS INCLUDED IN THIS NOTICE
/// BE LIABLE FOR ANY CLAIM, OR ANY SPECIAL INDIRECT OR CONSEQUENTIAL DAMAGES,
/// OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
/// WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
/// ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THE DATA
/// FILES OR SOFTWARE.
/// Except as contained in this notice, the name of a copyright holder shall
/// not be used in advertising or otherwise to promote the sale, use or other
/// dealings in these Data Files or Software without prior written
/// authorization of the copyright holder.
const Map<int, List<int>> _fullUppercaseExpansions = <int, List<int>>{
  0x00DF: <int>[0x0053, 0x0053],
  0xFB00: <int>[0x0046, 0x0046],
  0xFB01: <int>[0x0046, 0x0049],
  0xFB02: <int>[0x0046, 0x004C],
  0xFB03: <int>[0x0046, 0x0046, 0x0049],
  0xFB04: <int>[0x0046, 0x0046, 0x004C],
  0xFB05: <int>[0x0053, 0x0054],
  0xFB06: <int>[0x0053, 0x0054],
  0x0587: <int>[0x0535, 0x0552],
  0xFB13: <int>[0x0544, 0x0546],
  0xFB14: <int>[0x0544, 0x0535],
  0xFB15: <int>[0x0544, 0x053B],
  0xFB16: <int>[0x054E, 0x0546],
  0xFB17: <int>[0x0544, 0x053D],
  0x0149: <int>[0x02BC, 0x004E],
  0x0390: <int>[0x0399, 0x0308, 0x0301],
  0x03B0: <int>[0x03A5, 0x0308, 0x0301],
  0x01F0: <int>[0x004A, 0x030C],
  0x1E96: <int>[0x0048, 0x0331],
  0x1E97: <int>[0x0054, 0x0308],
  0x1E98: <int>[0x0057, 0x030A],
  0x1E99: <int>[0x0059, 0x030A],
  0x1E9A: <int>[0x0041, 0x02BE],
  0x1F50: <int>[0x03A5, 0x0313],
  0x1F52: <int>[0x03A5, 0x0313, 0x0300],
  0x1F54: <int>[0x03A5, 0x0313, 0x0301],
  0x1F56: <int>[0x03A5, 0x0313, 0x0342],
  0x1FB6: <int>[0x0391, 0x0342],
  0x1FC6: <int>[0x0397, 0x0342],
  0x1FD2: <int>[0x0399, 0x0308, 0x0300],
  0x1FD3: <int>[0x0399, 0x0308, 0x0301],
  0x1FD6: <int>[0x0399, 0x0342],
  0x1FD7: <int>[0x0399, 0x0308, 0x0342],
  0x1FE2: <int>[0x03A5, 0x0308, 0x0300],
  0x1FE3: <int>[0x03A5, 0x0308, 0x0301],
  0x1FE4: <int>[0x03A1, 0x0313],
  0x1FE6: <int>[0x03A5, 0x0342],
  0x1FE7: <int>[0x03A5, 0x0308, 0x0342],
  0x1FF6: <int>[0x03A9, 0x0342],
  0x1F80: <int>[0x1F08, 0x0399],
  0x1F81: <int>[0x1F09, 0x0399],
  0x1F82: <int>[0x1F0A, 0x0399],
  0x1F83: <int>[0x1F0B, 0x0399],
  0x1F84: <int>[0x1F0C, 0x0399],
  0x1F85: <int>[0x1F0D, 0x0399],
  0x1F86: <int>[0x1F0E, 0x0399],
  0x1F87: <int>[0x1F0F, 0x0399],
  0x1F88: <int>[0x1F08, 0x0399],
  0x1F89: <int>[0x1F09, 0x0399],
  0x1F8A: <int>[0x1F0A, 0x0399],
  0x1F8B: <int>[0x1F0B, 0x0399],
  0x1F8C: <int>[0x1F0C, 0x0399],
  0x1F8D: <int>[0x1F0D, 0x0399],
  0x1F8E: <int>[0x1F0E, 0x0399],
  0x1F8F: <int>[0x1F0F, 0x0399],
  0x1F90: <int>[0x1F28, 0x0399],
  0x1F91: <int>[0x1F29, 0x0399],
  0x1F92: <int>[0x1F2A, 0x0399],
  0x1F93: <int>[0x1F2B, 0x0399],
  0x1F94: <int>[0x1F2C, 0x0399],
  0x1F95: <int>[0x1F2D, 0x0399],
  0x1F96: <int>[0x1F2E, 0x0399],
  0x1F97: <int>[0x1F2F, 0x0399],
  0x1F98: <int>[0x1F28, 0x0399],
  0x1F99: <int>[0x1F29, 0x0399],
  0x1F9A: <int>[0x1F2A, 0x0399],
  0x1F9B: <int>[0x1F2B, 0x0399],
  0x1F9C: <int>[0x1F2C, 0x0399],
  0x1F9D: <int>[0x1F2D, 0x0399],
  0x1F9E: <int>[0x1F2E, 0x0399],
  0x1F9F: <int>[0x1F2F, 0x0399],
  0x1FA0: <int>[0x1F68, 0x0399],
  0x1FA1: <int>[0x1F69, 0x0399],
  0x1FA2: <int>[0x1F6A, 0x0399],
  0x1FA3: <int>[0x1F6B, 0x0399],
  0x1FA4: <int>[0x1F6C, 0x0399],
  0x1FA5: <int>[0x1F6D, 0x0399],
  0x1FA6: <int>[0x1F6E, 0x0399],
  0x1FA7: <int>[0x1F6F, 0x0399],
  0x1FA8: <int>[0x1F68, 0x0399],
  0x1FA9: <int>[0x1F69, 0x0399],
  0x1FAA: <int>[0x1F6A, 0x0399],
  0x1FAB: <int>[0x1F6B, 0x0399],
  0x1FAC: <int>[0x1F6C, 0x0399],
  0x1FAD: <int>[0x1F6D, 0x0399],
  0x1FAE: <int>[0x1F6E, 0x0399],
  0x1FAF: <int>[0x1F6F, 0x0399],
  0x1FB3: <int>[0x0391, 0x0399],
  0x1FBC: <int>[0x0391, 0x0399],
  0x1FC3: <int>[0x0397, 0x0399],
  0x1FCC: <int>[0x0397, 0x0399],
  0x1FF3: <int>[0x03A9, 0x0399],
  0x1FFC: <int>[0x03A9, 0x0399],
  0x1FB2: <int>[0x1FBA, 0x0399],
  0x1FB4: <int>[0x0386, 0x0399],
  0x1FC2: <int>[0x1FCA, 0x0399],
  0x1FC4: <int>[0x0389, 0x0399],
  0x1FF2: <int>[0x1FFA, 0x0399],
  0x1FF4: <int>[0x038F, 0x0399],
  0x1FB7: <int>[0x0391, 0x0342, 0x0399],
  0x1FC7: <int>[0x0397, 0x0342, 0x0399],
  0x1FF7: <int>[0x03A9, 0x0342, 0x0399],
};

/// Unicode default full uppercase mapping, including one-to-many mappings.
String unicodeFullUppercase(String value) {
  final result = StringBuffer();
  for (final codePoint in value.runes) {
    final expansion = _fullUppercaseExpansions[codePoint];
    result.write(expansion == null
        ? String.fromCharCode(codePoint).toUpperCase()
        : String.fromCharCodes(expansion));
  }
  return result.toString();
}

final RegExp _caseIgnorableCategory =
    RegExp(r'[\p{Mn}\p{Me}\p{Cf}\p{Lm}\p{Sk}]', unicode: true);

/// Unicode default full lowercase mapping, including dotted I and final sigma.
String unicodeFullLowercase(String value) {
  final codePoints = value.runes.toList(growable: false);
  final result = StringBuffer();
  for (var index = 0; index < codePoints.length; index++) {
    final codePoint = codePoints[index];
    if (codePoint == 0x0130) {
      result.write('i\u0307');
    } else if (codePoint == 0x03A3) {
      result.write(_isFinalSigma(codePoints, index) ? '\u03C2' : '\u03C3');
    } else {
      result.write(String.fromCharCode(codePoint).toLowerCase());
    }
  }
  return result.toString();
}

bool _isFinalSigma(List<int> codePoints, int index) {
  var precedingCased = false;
  for (var cursor = index - 1; cursor >= 0; cursor--) {
    final codePoint = codePoints[cursor];
    if (_isCaseIgnorable(codePoint)) continue;
    precedingCased = _isCased(codePoint);
    break;
  }
  if (!precedingCased) return false;

  for (var cursor = index + 1; cursor < codePoints.length; cursor++) {
    final codePoint = codePoints[cursor];
    if (_isCaseIgnorable(codePoint)) continue;
    return !_isCased(codePoint);
  }
  return true;
}

bool _isCased(int codePoint) {
  final character = String.fromCharCode(codePoint);
  return unicodeFullUppercase(character) != character ||
      unicodeFullLowercase(character) != character;
}

bool _isCaseIgnorable(int codePoint) {
  if (codePoint == 0x0027 || codePoint == 0x00AD || codePoint == 0x2019) {
    return true;
  }
  return _caseIgnorableCategory.hasMatch(String.fromCharCode(codePoint));
}
