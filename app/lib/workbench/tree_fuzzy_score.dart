// Dart port of VS Code fuzzyScore/createMatches and isEmojiImprecise.
// Pinned source: microsoft/vscode 4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e
// src/vs/base/common/filters.ts#L503-L914 and strings.ts#L759-L767
// https://github.com/microsoft/vscode/blob/4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e/src/vs/base/common/filters.ts
//
// MIT License
// Copyright (c) 2015 - present Microsoft Corporation
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import 'dart:typed_data';

/// VS Code's score and merged, half-open UTF-16 match ranges in the label.
class TreeFuzzyScore {
  const TreeFuzzyScore._(this.score, this.matches);

  final int score;
  final List<({int start, int end})> matches;

  /// Projects matches onto whole characters in the original scored [word].
  List<({int start, int end})> matchesInSource(String word) {
    final ranges = <({int start, int end})>[];
    for (final match in matches) {
      var start = _sourceOffset(word, match.start, end: false);
      var end = _sourceOffset(word, match.end, end: true);
      if (splitsUtf16SurrogatePair(word, start)) start--;
      if (splitsUtf16SurrogatePair(word, end)) end++;
      if (ranges.isNotEmpty && start <= ranges.last.end) {
        final previous = ranges.last;
        ranges[ranges.length - 1] = (
          start: previous.start,
          end: end > previous.end ? end : previous.end
        );
      } else {
        ranges.add((start: start, end: end));
      }
    }
    return ranges;
  }
}

// The fuzzy scorer uses JavaScript folding. A dotted capital I occupies
// two units after folding and both units refer to the same original letter.
int _sourceOffset(String value, int offset, {required bool end}) {
  var expanded = 0;
  for (var i = value.indexOf('\u0130');
      i >= 0 && i + expanded < offset;
      i = value.indexOf('\u0130', i + 1)) {
    if (end && i + expanded + 1 == offset) break;
    expanded++;
  }
  return offset - expanded;
}

/// Whether the offset bisects a UTF-16 surrogate pair.
bool splitsUtf16SurrogatePair(String value, int offset) =>
    offset > 0 &&
    offset < value.length &&
    (value.codeUnitAt(offset - 1) & 0xfc00) == 0xd800 &&
    (value.codeUnitAt(offset) & 0xfc00) == 0xdc00;

const _maxLen = 128;
const _diagArrow = 1;
const _leftArrow = 2;
const _leftLeftArrow = 3;
const _noScore = -9007199254740991;

/// Scores [pattern] against [word] using the pinned VS Code tree fuzzy scorer.
///
/// Both start offsets are zero, `firstMatchCanBeWeak` and `boostFullMatch` are
/// true. Empty inputs or a missing subsequence return null. Like upstream, only
/// the first 128 UTF-16 code units participate, even across a surrogate pair.
/// The result retains upstream offsets (including any lowercase expansions).
///
/// Scratch storage is local to the call: three matrices, each at most 129x129,
/// and two 128-element arrays. Failed subsequences allocate no matrices; there
/// is no retained label cache or shared mutable scoring state.
TreeFuzzyScore? treeFuzzyScore(String pattern, String word) {
  final patternLen = pattern.length > _maxLen ? _maxLen : pattern.length;
  final wordLen = word.length > _maxLen ? _maxLen : word.length;
  if (patternLen == 0 || wordLen == 0 || patternLen > wordLen) return null;

  final patternLow = _toJavaScriptLowerCase(pattern);
  final wordLow = _toJavaScriptLowerCase(word);
  final minWordMatchPos = Uint8List(patternLen);
  final maxWordMatchPos = Uint8List(patternLen);
  var patternPos = 0;
  for (var wordPos = 0;
      patternPos < patternLen && wordPos < wordLen;
      wordPos++) {
    if (patternLow.codeUnitAt(patternPos) == wordLow.codeUnitAt(wordPos)) {
      minWordMatchPos[patternPos++] = wordPos;
    }
  }
  if (patternPos != patternLen) return null;

  patternPos = patternLen - 1;
  for (var wordPos = wordLen - 1; patternPos >= 0 && wordPos >= 0; wordPos--) {
    if (patternLow.codeUnitAt(patternPos) == wordLow.codeUnitAt(wordPos)) {
      maxWordMatchPos[patternPos--] = wordPos;
    }
  }

  final stride = wordLen + 1;
  final cells = (patternLen + 1) * stride;
  // Scores are bounded by 128 matched characters and gap penalties, so Int16
  // suffices; diagonal lengths and arrows fit in Uint8. At most 66,564 bytes.
  final table = Int16List(cells);
  final diag = Uint8List(cells);
  final arrows = Uint8List(cells);
  var row = 1;
  var column = 1;
  for (patternPos = 0; patternPos < patternLen; row++, patternPos++) {
    final minPos = minWordMatchPos[patternPos];
    final maxPos = maxWordMatchPos[patternPos];
    final nextMaxPos =
        patternPos + 1 < patternLen ? maxWordMatchPos[patternPos + 1] : wordLen;
    for (var wordPos = minPos; wordPos < nextMaxPos; wordPos++) {
      column = wordPos + 1;
      final cell = row * stride + column;
      final previousDiag = cell - stride - 1;
      final score = wordPos <= maxPos
          ? _characterScore(pattern, patternLow, patternPos, word, wordLow,
              wordPos, wordLen, diag[previousDiag] == 0)
          : _noScore;
      final canComeDiag = score != _noScore;
      final diagScore = canComeDiag ? score + table[previousDiag] : 0;
      final canComeLeft = wordPos > minPos;
      final leftScore =
          canComeLeft ? table[cell - 1] + (diag[cell - 1] > 0 ? -5 : 0) : 0;
      final canComeLeftLeft = wordPos > minPos + 1 && diag[cell - 1] > 0;
      final leftLeftScore =
          canComeLeftLeft ? table[cell - 2] + (diag[cell - 2] > 0 ? -5 : 0) : 0;
      // Preserve >= ties: left-left, then left, then diagonal. This chooses
      // earlier matches rather than greedily using the latest equal score.
      if (canComeLeftLeft &&
          (!canComeLeft || leftLeftScore >= leftScore) &&
          (!canComeDiag || leftLeftScore >= diagScore)) {
        table[cell] = leftLeftScore;
        arrows[cell] = _leftLeftArrow;
      } else if (canComeLeft && (!canComeDiag || leftScore >= diagScore)) {
        table[cell] = leftScore;
        arrows[cell] = _leftArrow;
      } else if (canComeDiag) {
        table[cell] = diagScore;
        arrows[cell] = _diagArrow;
        diag[cell] = diag[previousDiag] + 1;
      } else {
        throw StateError('Unreachable fuzzy score cell');
      }
      // All cells are visited once, so left/left-left diagonals are already 0.
    }
  }

  row--;
  var score = table[row * stride + column];
  var backwardsDiagLength = 0;
  var maxMatchColumn = 0;
  final positions = Uint8List(patternLen);
  while (row >= 1) {
    var diagColumn = column;
    do {
      final arrow = arrows[row * stride + diagColumn];
      if (arrow == _leftLeftArrow) {
        diagColumn -= 2;
      } else if (arrow == _leftArrow) {
        diagColumn--;
      } else {
        break;
      }
    } while (diagColumn >= 1);

    // Upstream backtracking can overturn the forward alignment in favor of a
    // longer contiguous suffix, unless the chosen diagonal is uppercase.
    if (backwardsDiagLength > 1 &&
        patternLow.codeUnitAt(row - 1) == wordLow.codeUnitAt(column - 1) &&
        !_isUpperCaseAt(diagColumn - 1, word, wordLow) &&
        backwardsDiagLength + 1 > diag[row * stride + diagColumn]) {
      diagColumn = column;
    }
    backwardsDiagLength = diagColumn == column ? backwardsDiagLength + 1 : 1;
    if (maxMatchColumn == 0) maxMatchColumn = diagColumn;
    row--;
    column = diagColumn - 1;
    positions[row] = column;
  }
  if (wordLen == patternLen) score += 2;
  score -= maxMatchColumn - patternLen;

  // createMatches: positions are ascending here; merge only adjacent units.
  final matches = <({int start, int end})>[];
  for (final pos in positions) {
    if (matches.isNotEmpty && matches.last.end == pos) {
      matches[matches.length - 1] = (start: matches.last.start, end: pos + 1);
    } else {
      matches.add((start: pos, end: pos + 1));
    }
  }
  return TreeFuzzyScore._(score, List.unmodifiable(matches));
}

String _toJavaScriptLowerCase(String value) {
  // JavaScript's String#toLowerCase uses Unicode Default Case Conversion,
  // whereas Dart's conversion differs for U+0130 and contextual final sigma.
  // Process code points so a UTF-16 surrogate pair is never split here.
  final runes = value.runes.toList();
  final lower = StringBuffer();
  for (var i = 0; i < runes.length; i++) {
    final rune = runes[i];
    if (rune == 0x0130) {
      // JS maps LATIN CAPITAL LETTER I WITH DOT ABOVE to i + combining dot.
      lower.write('i\u0307');
    } else if (rune == 0x03A3 && _isFinalSigma(runes, i)) {
      lower.write('\u03C2');
    } else {
      lower.write(String.fromCharCode(rune).toLowerCase());
    }
  }
  return lower.toString();
}

bool _isFinalSigma(List<int> runes, int index) {
  final cased = RegExp(r'\p{Cased}', unicode: true);
  final ignorable = RegExp(r'\p{Case_Ignorable}', unicode: true);
  var before = index - 1;
  while (
      before >= 0 && ignorable.hasMatch(String.fromCharCode(runes[before]))) {
    before--;
  }
  var after = index + 1;
  while (after < runes.length &&
      ignorable.hasMatch(String.fromCharCode(runes[after]))) {
    after++;
  }
  final precededByCased =
      before >= 0 && cased.hasMatch(String.fromCharCode(runes[before]));
  final followedByCased =
      after < runes.length && cased.hasMatch(String.fromCharCode(runes[after]));
  return precededByCased && !followedByCased;
}

int _characterScore(String pattern, String patternLow, int patternPos,
    String word, String wordLow, int wordPos, int wordLen, bool newMatchStart) {
  if (patternLow.codeUnitAt(patternPos) != wordLow.codeUnitAt(wordPos)) {
    return _noScore;
  }
  var score = 1;
  var isGapLocation = false;
  if (wordPos == patternPos) {
    score = pattern.codeUnitAt(patternPos) == word.codeUnitAt(wordPos) ? 7 : 5;
  } else if (_isUpperCaseAt(wordPos, word, wordLow) &&
      (wordPos == 0 || !_isUpperCaseAt(wordPos - 1, word, wordLow))) {
    score = pattern.codeUnitAt(patternPos) == word.codeUnitAt(wordPos) ? 7 : 5;
    isGapLocation = true;
  } else if (_isSeparatorAt(wordLow, wordPos) &&
      (wordPos == 0 || !_isSeparatorAt(wordLow, wordPos - 1))) {
    score = 5;
  } else if (_isSeparatorAt(wordLow, wordPos - 1) ||
      _isWhitespaceAt(wordLow, wordPos - 1)) {
    score = 5;
    isGapLocation = true;
  }
  if (!isGapLocation) {
    isGapLocation = _isUpperCaseAt(wordPos, word, wordLow) ||
        _isSeparatorAt(wordLow, wordPos - 1) ||
        _isWhitespaceAt(wordLow, wordPos - 1);
  }
  if (patternPos == 0) {
    if (wordPos > 0) score -= isGapLocation ? 3 : 5;
  } else if (newMatchStart) {
    score += isGapLocation ? 2 : 0;
  } else {
    score += isGapLocation ? 0 : 1;
  }
  if (wordPos + 1 == wordLen) score -= isGapLocation ? 3 : 5;
  return score;
}

bool _isUpperCaseAt(int pos, String word, String wordLow) =>
    word.codeUnitAt(pos) != wordLow.codeUnitAt(pos);

bool _isWhitespaceAt(String value, int index) =>
    index >= 0 &&
    index < value.length &&
    (value.codeUnitAt(index) == 32 || value.codeUnitAt(index) == 9);

bool _isSeparatorAt(String value, int index) {
  if (index < 0 || index >= value.length) return false;
  var code = value.codeUnitAt(index);
  // JS codePointAt combines a pair only at its high surrogate; a low surrogate
  // visited independently remains a code unit, exactly as the scoring loop does.
  if (code >= 0xD800 && code <= 0xDBFF && index + 1 < value.length) {
    final low = value.codeUnitAt(index + 1);
    if (low >= 0xDC00 && low <= 0xDFFF) {
      code = 0x10000 + ((code - 0xD800) << 10) + low - 0xDC00;
    }
  }
  return switch (code) {
    95 ||
    45 ||
    46 ||
    32 ||
    47 ||
    92 ||
    39 ||
    34 ||
    58 ||
    36 ||
    60 ||
    62 ||
    40 ||
    41 ||
    91 ||
    93 ||
    123 ||
    125 =>
      true,
    _ => _isEmojiImprecise(code),
  };
}

bool _isEmojiImprecise(int code) =>
    (code >= 0x1F1E6 && code <= 0x1F1FF) ||
    code == 8986 ||
    code == 8987 ||
    code == 9200 ||
    code == 9203 ||
    (code >= 9728 && code <= 10175) ||
    code == 11088 ||
    code == 11093 ||
    (code >= 127744 && code <= 128591) ||
    (code >= 128640 && code <= 128764) ||
    (code >= 128992 && code <= 129008) ||
    (code >= 129280 && code <= 129535) ||
    (code >= 129648 && code <= 129782);
