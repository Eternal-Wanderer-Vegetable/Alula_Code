/// 查找/替换纯逻辑（feat-010）。
///
/// Dart String 索引天然是 UTF-16 code unit 偏移，与 FFI 协议口径一致；
/// 本模块不做跨代理对特判（查询落在代理对内部不可能按整字符命中），
/// Emoji 用例由单测锁定。
library;

import 'dart:async';
import 'dart:isolate';

import 'unicode_case_mapping.dart';

class TextMatch {
  const TextMatch(this.start, this.end);

  /// UTF-16 code unit 偏移（含头不含尾）。
  final int start;
  final int end;

  int get length => end - start;
}

/// A half-open search range in original document UTF-16 code units.
class TextMatchScope {
  const TextMatchScope(this.start, this.end);

  final int start;
  final int end;
}

/// Code-OSS caps selection-seeded Find text strictly below 512 Ki UTF-16
/// code units so opening Find cannot copy an unbounded selection into its
/// query field.
const int maxFindSelectionSeedUtf16 = 524288;

bool isFindSelectionSeedLengthSupported(int lengthUtf16) =>
    lengthUtf16 > 0 && lengthUtf16 < maxFindSelectionSeedUtf16;

/// Clips scopes to the document and merges overlapping (but not adjacent)
/// ranges so a match is never duplicated across overlapping selections.
List<TextMatchScope> normalizeTextMatchScopes(
  Iterable<TextMatchScope> scopes,
  int textLength,
) {
  final ordered = scopes
      .map((scope) => TextMatchScope(
            scope.start.clamp(0, textLength).toInt(),
            scope.end.clamp(0, textLength).toInt(),
          ))
      .where((scope) => scope.end > scope.start)
      .toList()
    ..sort((left, right) => left.start.compareTo(right.start));
  if (ordered.length < 2) return List.unmodifiable(ordered);

  final merged = <TextMatchScope>[ordered.first];
  for (final scope in ordered.skip(1)) {
    final previous = merged.last;
    if (scope.start < previous.end) {
      merged[merged.length - 1] = TextMatchScope(
        previous.start,
        scope.end > previous.end ? scope.end : previous.end,
      );
    } else {
      merged.add(scope);
    }
  }
  return List.unmodifiable(merged);
}

/// Captures non-empty editor selections as search scopes. A trailing line
/// ending is omitted when the selection ends at column 1 on the next line.
List<TextMatchScope> findScopesFromSelections(
  String text,
  Iterable<TextMatchScope> selections,
) {
  final scopes = <TextMatchScope>[];
  for (final selection in selections) {
    var start =
        selection.start < selection.end ? selection.start : selection.end;
    var end = selection.start < selection.end ? selection.end : selection.start;
    start = start.clamp(0, text.length).toInt();
    end = end.clamp(0, text.length).toInt();
    if (end <= start) continue;
    if (text.codeUnitAt(end - 1) == 0x0A) {
      end--;
      if (end > start && text.codeUnitAt(end - 1) == 0x0D) end--;
    }
    if (end > start) scopes.add(TextMatchScope(start, end));
  }
  return normalizeTextMatchScopes(scopes, text.length);
}

class FindMatchesResult {
  const FindMatchesResult(this.matches);

  final List<TextMatch> matches;
}

class FindMatchSelectionPlan {
  const FindMatchSelectionPlan({
    required this.matches,
    required this.truncated,
  });

  final List<TextMatch> matches;
  final bool truncated;
}

/// Selects at most [maxMatches] results and puts an already selected match
/// first so the editor can retain it as the primary selection.
FindMatchSelectionPlan buildFindMatchSelectionPlan({
  required List<TextMatch> matches,
  required int maxMatches,
  TextMatch? preferredMatch,
}) {
  if (maxMatches < 1) {
    throw ArgumentError.value(maxMatches, 'maxMatches', 'must be positive');
  }
  if (matches.isEmpty) {
    return const FindMatchSelectionPlan(matches: [], truncated: false);
  }

  final preferredIndex = preferredMatch == null
      ? -1
      : matches.indexWhere((match) =>
          match.start == preferredMatch.start &&
          match.end == preferredMatch.end);
  final selected = <TextMatch>[];
  if (preferredIndex >= 0) selected.add(matches[preferredIndex]);
  for (var index = 0;
      index < matches.length && selected.length < maxMatches;
      index++) {
    if (index != preferredIndex) selected.add(matches[index]);
  }
  return FindMatchSelectionPlan(
    matches: List.unmodifiable(selected),
    truncated: matches.length > selected.length,
  );
}

/// Bounded result from regex search. A timeout or invalid expression is
/// returned as data so the find widget can report it without throwing.
class FindRegexMatchesResult {
  const FindRegexMatchesResult({
    this.matches = const [],
    this.error,
    this.timedOut = false,
    this.truncated = false,
    this.cancelled = false,
  });

  final List<TextMatch> matches;
  final String? error;
  final bool timedOut;
  final bool truncated;
  final bool cancelled;
}

/// Result of a bounded regex replacement. All replacements are prepared in a
/// worker so a pathological expression cannot block the editor isolate.
class ReplaceRegexMatchesResult {
  const ReplaceRegexMatchesResult({
    this.newText,
    this.count = 0,
    this.caretOffset,
    this.error,
    this.timedOut = false,
    this.truncated = false,
    this.cancelled = false,
  });

  final String? newText;
  final int count;
  final int? caretOffset;
  final String? error;
  final bool timedOut;
  final bool truncated;
  final bool cancelled;
}

const int maxFindRegexPatternUtf16 = 1000;
const int maxFindRegexMatches = 19999;
const int maxRegexReplaceOutputUtf16 = 64 * 1024 * 1024;
const Duration findRegexMatchTimeout = Duration(milliseconds: 750);

/// Builds one replacement in a bounded isolate. When [targetStart] is set,
/// only the match at that original UTF-16 offset is replaced.
Future<ReplaceRegexMatchesResult> replaceRegexMatches(
  String text,
  String pattern,
  String replacement, {
  bool caseSensitive = false,
  bool wholeWord = false,
  bool preserveCase = false,
  List<TextMatchScope>? scopes,
  int? targetStart,
  Duration timeout = findRegexMatchTimeout,
  Future<void>? cancelSignal,
}) async {
  if (pattern.isEmpty) return ReplaceRegexMatchesResult(newText: text);
  if (pattern.length > maxFindRegexPatternUtf16) {
    return const ReplaceRegexMatchesResult(error: '正则表达式超过长度限制');
  }
  final normalizedScopes =
      scopes == null ? null : normalizeTextMatchScopes(scopes, text.length);
  if (normalizedScopes != null && normalizedScopes.isEmpty) {
    return ReplaceRegexMatchesResult(newText: text);
  }

  final replyPort = ReceivePort();
  Isolate? worker;
  try {
    worker = await Isolate.spawn<List<Object?>>(
      _replaceRegexWorker,
      <Object?>[
        replyPort.sendPort,
        text,
        pattern,
        replacement,
        caseSensitive,
        wholeWord,
        normalizedScopes
            ?.map((scope) => <int>[scope.start, scope.end])
            .toList(growable: false),
        targetStart,
        preserveCase,
      ],
      errorsAreFatal: true,
    );
    final response = await Future.any<Object?>([
      replyPort.first.timeout(timeout),
      if (cancelSignal != null)
        cancelSignal.then((_) => const _FindRegexCancelled()),
    ]);
    if (response is _FindRegexCancelled) {
      return const ReplaceRegexMatchesResult(cancelled: true);
    }
    if (response is! Map<Object?, Object?> || response['ok'] != true) {
      final error = response is Map<Object?, Object?>
          ? response['error'] as String? ?? '正则替换失败'
          : '正则替换工作线程返回无效结果';
      return ReplaceRegexMatchesResult(error: error);
    }
    if (response['truncated'] == true) {
      return const ReplaceRegexMatchesResult(
        error: '正则替换命中数超过上限，未修改文档',
        truncated: true,
      );
    }
    final newText = response['newText'];
    final count = response['count'];
    final caretOffset = response['caretOffset'];
    if (newText is! String ||
        count is! int ||
        (caretOffset != null && caretOffset is! int)) {
      return const ReplaceRegexMatchesResult(error: '正则替换结果无效');
    }
    return ReplaceRegexMatchesResult(
      newText: newText,
      count: count,
      caretOffset: caretOffset as int?,
    );
  } on TimeoutException {
    return const ReplaceRegexMatchesResult(error: '正则替换超时', timedOut: true);
  } catch (error) {
    return ReplaceRegexMatchesResult(error: '正则替换失败: $error');
  } finally {
    worker?.kill(priority: Isolate.immediate);
    replyPort.close();
  }
}

/// Runs regex matching off the UI isolate. The worker is terminated on
/// timeout, and the returned ranges always use original UTF-16 offsets.
Future<FindRegexMatchesResult> findRegexMatches(
  String text,
  String pattern, {
  bool caseSensitive = false,
  bool wholeWord = false,
  List<TextMatchScope>? scopes,
  Duration timeout = findRegexMatchTimeout,
  Future<void>? cancelSignal,
}) async {
  if (pattern.isEmpty) return const FindRegexMatchesResult();
  if (pattern.length > maxFindRegexPatternUtf16) {
    return const FindRegexMatchesResult(error: '正则表达式超过长度限制');
  }
  final normalizedScopes =
      scopes == null ? null : normalizeTextMatchScopes(scopes, text.length);
  if (normalizedScopes != null && normalizedScopes.isEmpty) {
    return const FindRegexMatchesResult();
  }

  final replyPort = ReceivePort();
  Isolate? worker;
  try {
    worker = await Isolate.spawn<List<Object?>>(
      _findRegexWorker,
      <Object?>[
        replyPort.sendPort,
        text,
        pattern,
        caseSensitive,
        wholeWord,
        normalizedScopes
            ?.map((scope) => <int>[scope.start, scope.end])
            .toList(growable: false),
      ],
      errorsAreFatal: true,
    );
    final response = await Future.any<Object?>([
      replyPort.first.timeout(timeout),
      if (cancelSignal != null)
        cancelSignal.then((_) => const _FindRegexCancelled()),
    ]);
    if (response is _FindRegexCancelled) {
      return const FindRegexMatchesResult(cancelled: true);
    }
    if (response is! Map<Object?, Object?> || response['ok'] != true) {
      final error = response is Map<Object?, Object?>
          ? response['error'] as String? ?? '正则查找失败'
          : '正则查找工作线程返回无效结果';
      return FindRegexMatchesResult(error: error);
    }
    final rawMatches = response['matches'];
    if (rawMatches is! List<Object?>) {
      return const FindRegexMatchesResult(error: '正则查找结果无效');
    }
    final matches = <TextMatch>[];
    for (final raw in rawMatches) {
      if (raw is! List<Object?> ||
          raw.length != 2 ||
          raw[0] is! int ||
          raw[1] is! int) {
        return const FindRegexMatchesResult(error: '正则查找范围无效');
      }
      matches.add(TextMatch(raw[0]! as int, raw[1]! as int));
    }
    return FindRegexMatchesResult(
      matches: List<TextMatch>.unmodifiable(matches),
      truncated: response['truncated'] == true,
    );
  } on TimeoutException {
    return const FindRegexMatchesResult(error: '正则查找超时', timedOut: true);
  } catch (error) {
    return FindRegexMatchesResult(error: '正则查找失败: $error');
  } finally {
    worker?.kill(priority: Isolate.immediate);
    replyPort.close();
  }
}

class _FindRegexCancelled {
  const _FindRegexCancelled();
}

void _findRegexWorker(List<Object?> message) {
  final replyPort = message[0]! as SendPort;
  final text = message[1]! as String;
  final pattern = message[2]! as String;
  final caseSensitive = message[3]! as bool;
  final wholeWord = message[4]! as bool;
  final rawScopes = message[5] as List<Object?>?;
  final scopes = rawScopes
      ?.whereType<List<Object?>>()
      .where((range) => range.length == 2 && range[0] is int && range[1] is int)
      .map((range) => TextMatchScope(
            range[0]! as int,
            range[1]! as int,
          ))
      .toList(growable: false);
  try {
    final regex = RegExp(
      pattern,
      caseSensitive: caseSensitive,
      multiLine: true,
      unicode: true,
    );
    final matches = <List<int>>[];
    var truncated = false;

    void addMatch(int start, int end) {
      if (scopes != null && !_isWithinFindScopes(scopes, start, end)) return;
      if (wholeWord && !_isWholeWordRange(text, start, end)) return;
      if (matches.length == maxFindRegexMatches) {
        truncated = true;
        return;
      }
      matches.add(<int>[start, end]);
    }

    if (_isMultilineRegexSource(pattern)) {
      final normalized = _normalizeFindLineEndings(text);
      final offsetMapper = _FindOriginalOffsetMapper(text);
      for (final match in regex.allMatches(normalized)) {
        final start = offsetMapper.toOriginal(match.start);
        final end = offsetMapper.toOriginal(match.end);
        addMatch(start, end);
        if (truncated) break;
      }
    } else {
      var lineStart = 0;
      while (lineStart <= text.length) {
        var lineEnd = lineStart;
        while (lineEnd < text.length &&
            text.codeUnitAt(lineEnd) != 0x0A &&
            text.codeUnitAt(lineEnd) != 0x0D) {
          lineEnd++;
        }
        final line = text.substring(lineStart, lineEnd);
        for (final match in regex.allMatches(line)) {
          addMatch(lineStart + match.start, lineStart + match.end);
          if (truncated) break;
        }
        if (truncated || lineEnd == text.length) break;
        lineStart = lineEnd + 1;
        if (text.codeUnitAt(lineEnd) == 0x0D &&
            lineStart < text.length &&
            text.codeUnitAt(lineStart) == 0x0A) {
          lineStart++;
        }
      }
    }
    replyPort.send(<String, Object?>{
      'ok': true,
      'matches': matches,
      'truncated': truncated,
    });
  } catch (error) {
    replyPort.send(<String, Object?>{'ok': false, 'error': '$error'});
  }
}

void _replaceRegexWorker(List<Object?> message) {
  final replyPort = message[0]! as SendPort;
  final text = message[1]! as String;
  final pattern = message[2]! as String;
  final replacement = message[3]! as String;
  final caseSensitive = message[4]! as bool;
  final wholeWord = message[5]! as bool;
  final rawScopes = message[6] as List<Object?>?;
  final targetStart = message[7] as int?;
  final preserveCase = message[8]! as bool;
  final scopes = rawScopes
      ?.whereType<List<Object?>>()
      .where((range) => range.length == 2 && range[0] is int && range[1] is int)
      .map((range) => TextMatchScope(
            range[0]! as int,
            range[1]! as int,
          ))
      .toList(growable: false);

  try {
    final regex = RegExp(
      pattern,
      caseSensitive: caseSensitive,
      multiLine: true,
      unicode: true,
    );
    final replacePattern = _RegexReplacePattern.parse(replacement);
    if (targetStart != null) {
      bool replaceTarget(RegExpMatch match, int start, int end) {
        if (start != targetStart ||
            scopes != null && !_isWithinFindScopes(scopes, start, end) ||
            wholeWord && !_isWholeWordRange(text, start, end)) {
          return false;
        }
        final inserted = replacePattern.expand(
          match,
          preserveCase: preserveCase,
        );
        final newText = text.replaceRange(start, end, inserted);
        if (newText.length > maxRegexReplaceOutputUtf16) {
          throw const _RegexReplaceOutputLimit();
        }
        replyPort.send(<String, Object?>{
          'ok': true,
          'newText': newText,
          'count': 1,
          'caretOffset': start + inserted.length,
        });
        return true;
      }

      if (_isMultilineRegexSource(pattern)) {
        final normalized = _normalizeFindLineEndings(text);
        final offsetMapper = _FindOriginalOffsetMapper(text);
        for (final match in regex.allMatches(normalized)) {
          final start = offsetMapper.toOriginal(match.start);
          final end = offsetMapper.toOriginal(match.end);
          if (replaceTarget(match, start, end)) return;
        }
      } else {
        var lineStart = 0;
        while (lineStart <= text.length) {
          var lineEnd = lineStart;
          while (lineEnd < text.length &&
              text.codeUnitAt(lineEnd) != 0x0A &&
              text.codeUnitAt(lineEnd) != 0x0D) {
            lineEnd++;
          }
          final line = text.substring(lineStart, lineEnd);
          for (final match in regex.allMatches(line)) {
            if (replaceTarget(
              match,
              lineStart + match.start,
              lineStart + match.end,
            )) {
              return;
            }
          }
          if (lineEnd == text.length) break;
          lineStart = lineEnd + 1;
          if (text.codeUnitAt(lineEnd) == 0x0D &&
              lineStart < text.length &&
              text.codeUnitAt(lineStart) == 0x0A) {
            lineStart++;
          }
        }
      }
      replyPort.send(<String, Object?>{
        'ok': true,
        'newText': text,
        'count': 0,
      });
      return;
    }

    final output = StringBuffer();
    var outputLength = 0;
    var cursor = 0;
    var count = 0;
    var truncated = false;

    void write(String value) {
      if (outputLength + value.length > maxRegexReplaceOutputUtf16) {
        throw const _RegexReplaceOutputLimit();
      }
      output.write(value);
      outputLength += value.length;
    }

    void addMatch(RegExpMatch match, int start, int end) {
      if (scopes != null && !_isWithinFindScopes(scopes, start, end)) return;
      if (wholeWord && !_isWholeWordRange(text, start, end)) return;
      if (count == maxFindRegexMatches) {
        truncated = true;
        return;
      }
      write(text.substring(cursor, start));
      write(replacePattern.expand(match, preserveCase: preserveCase));
      cursor = end;
      count++;
    }

    if (_isMultilineRegexSource(pattern)) {
      final normalized = _normalizeFindLineEndings(text);
      final offsetMapper = _FindOriginalOffsetMapper(text);
      for (final match in regex.allMatches(normalized)) {
        addMatch(
          match,
          offsetMapper.toOriginal(match.start),
          offsetMapper.toOriginal(match.end),
        );
        if (truncated) break;
      }
    } else {
      var lineStart = 0;
      while (lineStart <= text.length) {
        var lineEnd = lineStart;
        while (lineEnd < text.length &&
            text.codeUnitAt(lineEnd) != 0x0A &&
            text.codeUnitAt(lineEnd) != 0x0D) {
          lineEnd++;
        }
        final line = text.substring(lineStart, lineEnd);
        for (final match in regex.allMatches(line)) {
          addMatch(match, lineStart + match.start, lineStart + match.end);
          if (truncated) break;
        }
        if (truncated || lineEnd == text.length) break;
        lineStart = lineEnd + 1;
        if (text.codeUnitAt(lineEnd) == 0x0D &&
            lineStart < text.length &&
            text.codeUnitAt(lineStart) == 0x0A) {
          lineStart++;
        }
      }
    }
    if (truncated) {
      replyPort.send(<String, Object?>{'ok': true, 'truncated': true});
      return;
    }
    if (count == 0) {
      replyPort.send(<String, Object?>{
        'ok': true,
        'newText': text,
        'count': 0,
      });
      return;
    }
    write(text.substring(cursor));
    replyPort.send(<String, Object?>{
      'ok': true,
      'newText': output.toString(),
      'count': count,
    });
  } on _RegexReplaceOutputLimit {
    replyPort.send(<String, Object?>{
      'ok': false,
      'error': '正则替换结果超过 64 Mi UTF-16 上限，未修改文档',
    });
  } catch (error) {
    replyPort.send(<String, Object?>{'ok': false, 'error': '$error'});
  }
}

class _RegexReplaceOutputLimit implements Exception {
  const _RegexReplaceOutputLimit();
}

class _RegexReplacePattern {
  _RegexReplacePattern(this._pieces);

  final List<_RegexReplacePiece> _pieces;

  bool get hasReplacementPatterns =>
      _pieces.any((piece) => piece.matchIndex != null);

  static _RegexReplacePattern parse(String source) {
    final pieces = <_RegexReplacePiece>[];
    final literal = StringBuffer();
    final caseOps = <int>[];

    void flushLiteral() {
      if (literal.isEmpty) return;
      pieces.add(_RegexReplacePiece.staticValue(literal.toString()));
      literal.clear();
    }

    void emitMatch(int index) {
      flushLiteral();
      pieces.add(_RegexReplacePiece.matchIndex(index, List.of(caseOps)));
      caseOps.clear();
    }

    for (var index = 0; index < source.length; index++) {
      final unit = source.codeUnitAt(index);
      if (unit == 0x5C) {
        if (index + 1 == source.length) {
          literal.writeCharCode(unit);
          break;
        }
        final next = source.codeUnitAt(++index);
        switch (next) {
          case 0x5C:
            literal.writeCharCode(0x5C);
          case 0x6E:
            literal.write('\n');
          case 0x74:
            literal.write('\t');
          case 0x75: // \u: uppercase the next code unit of the next capture.
          case 0x55: // \U: uppercase all remaining capture code units.
          case 0x6C: // \l: lowercase the next code unit of the next capture.
          case 0x4C: // \L: lowercase all remaining capture code units.
            caseOps.add(next);
          default:
            literal
              ..writeCharCode(0x5C)
              ..writeCharCode(next);
        }
        continue;
      }
      if (unit != 0x24 || index + 1 == source.length) {
        literal.writeCharCode(unit);
        continue;
      }

      final next = source.codeUnitAt(index + 1);
      if (next == 0x24) {
        literal.writeCharCode(0x24);
        index++;
        continue;
      }
      if (next == 0x26 || next == 0x30) {
        emitMatch(0);
        index++;
        continue;
      }
      if (next >= 0x31 && next <= 0x39) {
        var matchIndex = next - 0x30;
        index++;
        if (index + 1 < source.length) {
          final second = source.codeUnitAt(index + 1);
          if (second >= 0x30 && second <= 0x39) {
            matchIndex = matchIndex * 10 + second - 0x30;
            index++;
          }
        }
        emitMatch(matchIndex);
        continue;
      }
      literal.writeCharCode(unit);
    }
    flushLiteral();
    return _RegexReplacePattern(List.unmodifiable(pieces));
  }

  String expand(RegExpMatch match, {bool preserveCase = false}) {
    final output = StringBuffer();
    for (final piece in _pieces) {
      if (piece.staticValue != null) {
        output.write(piece.staticValue);
        continue;
      }
      final matchIndex = piece.matchIndex!;
      final hasMatchIndex = matchIndex <= match.groupCount;
      final value = hasMatchIndex ? match.group(matchIndex) : null;
      output.write(
        !hasMatchIndex
            ? '\$$matchIndex'
            : _applyRegexCaseOps(value ?? '', piece.caseOps),
      );
    }
    final expanded = output.toString();
    return preserveCase && !hasReplacementPatterns
        ? buildPreserveCaseReplacement(match.group(0) ?? '', expanded)
        : expanded;
  }
}

class _RegexReplacePiece {
  const _RegexReplacePiece._(this.staticValue, this.matchIndex, this.caseOps);

  factory _RegexReplacePiece.staticValue(String value) =>
      _RegexReplacePiece._(value, null, const []);

  factory _RegexReplacePiece.matchIndex(int index, List<int> caseOps) =>
      _RegexReplacePiece._(null, index, List.unmodifiable(caseOps));

  final String? staticValue;
  final int? matchIndex;
  final List<int> caseOps;
}

String _applyRegexCaseOps(String value, List<int> caseOps) {
  if (caseOps.isEmpty || value.isEmpty) return value;
  final output = StringBuffer();
  var opIndex = 0;
  for (final unit in value.codeUnits) {
    if (opIndex == caseOps.length) {
      output.writeCharCode(unit);
      continue;
    }
    final character = String.fromCharCode(unit);
    switch (caseOps[opIndex]) {
      case 0x55: // \U
        output.write(character.toUpperCase());
      case 0x75: // \u
        output.write(character.toUpperCase());
        opIndex++;
      case 0x4C: // \L
        output.write(character.toLowerCase());
      case 0x6C: // \l
        output.write(character.toLowerCase());
        opIndex++;
      default:
        output.write(character);
    }
  }
  return output.toString();
}

bool _isMultilineRegexSource(String pattern) {
  var escaped = false;
  var inCharacterClass = false;
  for (final unit in pattern.codeUnits) {
    if (escaped) {
      if (!inCharacterClass && (unit == 0x6E || unit == 0x72 || unit == 0x57)) {
        return true;
      }
      escaped = false;
      continue;
    }
    if (unit == 0x5C) {
      escaped = true;
    } else if (unit == 0x5B) {
      inCharacterClass = true;
    } else if (unit == 0x5D) {
      inCharacterClass = false;
    } else if (!inCharacterClass && (unit == 0x0A || unit == 0x0D)) {
      return true;
    }
  }
  return false;
}

String _normalizeFindLineEndings(String text) {
  final normalized = StringBuffer();
  var index = 0;
  while (index < text.length) {
    final unit = text.codeUnitAt(index);
    if (unit == 0x0D) {
      final end = index +
          (index + 1 < text.length && text.codeUnitAt(index + 1) == 0x0A
              ? 2
              : 1);
      normalized.write('\n');
      index = end;
    } else {
      normalized.writeCharCode(unit);
      index++;
    }
  }
  return normalized.toString();
}

/// Converts monotonically increasing normalized offsets without retaining an
/// O(document length) offset table (which is expensive for large files).
class _FindOriginalOffsetMapper {
  _FindOriginalOffsetMapper(this.original);

  final String original;
  int _normalizedOffset = 0;
  int _originalOffset = 0;

  int toOriginal(int targetOffset) {
    while (_normalizedOffset < targetOffset) {
      final unit = original.codeUnitAt(_originalOffset);
      if (unit == 0x0D &&
          _originalOffset + 1 < original.length &&
          original.codeUnitAt(_originalOffset + 1) == 0x0A) {
        _originalOffset += 2;
      } else {
        _originalOffset++;
      }
      _normalizedOffset++;
    }
    return _originalOffset;
  }
}

/// 非重叠顺序查找全部命中；[query] 为空返回空列表。
List<TextMatch> findMatches(
  String text,
  String query, {
  bool caseSensitive = false,
  bool wholeWord = false,
  List<TextMatchScope>? scopes,
}) {
  if (query.isEmpty) return const [];
  final searchScopes = scopes == null
      ? [TextMatchScope(0, text.length)]
      : normalizeTextMatchScopes(scopes, text.length);
  if (searchScopes.isEmpty) return const [];
  final out = <TextMatch>[];
  if (caseSensitive) {
    for (final scope in searchScopes) {
      var offset = text.indexOf(query, scope.start);
      while (offset >= 0 && offset < scope.end) {
        final end = offset + query.length;
        if (end > scope.end) break;
        if (!wholeWord || _isWholeWordRange(text, offset, end)) {
          out.add(TextMatch(offset, end));
        }
        offset = text.indexOf(query, end);
      }
    }
    return out;
  }

  // Matching against a lowercased copy can shift UTF-16 offsets when Unicode
  // lowercasing expands a character (for example U+0130). RegExp reports
  // ranges in the original string while preserving literal, non-overlapping
  // matching semantics.
  final literal = RegExp(RegExp.escape(query), caseSensitive: false);
  for (final scope in searchScopes) {
    for (final match in literal.allMatches(text, scope.start)) {
      if (match.start >= scope.end) break;
      if (match.end > scope.end) break;
      final start = match.start;
      final end = match.end;
      if (!wholeWord || _isWholeWordRange(text, start, end)) {
        out.add(TextMatch(start, end));
      }
    }
  }
  return out;
}

bool _isWithinFindScopes(
  List<TextMatchScope> scopes,
  int start,
  int end,
) {
  var low = 0;
  var high = scopes.length;
  while (low < high) {
    final middle = (low + high) >> 1;
    final scope = scopes[middle];
    if (start < scope.start) {
      high = middle;
    } else if (start > scope.end || (start == scope.end && end > start)) {
      low = middle + 1;
    } else {
      return end <= scope.end;
    }
  }
  return false;
}

const _defaultFindWordSeparators = r"""`~!@#$%^&*()-=+[{]}\|;:'",.<>/?""";
final _findWhitespace = RegExp(r'\s');

bool _isWholeWordRange(String text, int start, int end) =>
    _isFindWordStart(text, start) && _isFindWordEnd(text, end);

bool _isFindWordStart(String text, int offset) =>
    offset <= 0 || _isFindWordSeparator(text.substring(offset - 1, offset));

bool _isFindWordEnd(String text, int offset) =>
    offset >= text.length ||
    _isFindWordSeparator(text.substring(offset, offset + 1));

bool _isFindWordSeparator(String codeUnit) =>
    codeUnit == '\uFEFF' ||
    _defaultFindWordSeparators.contains(codeUnit) ||
    _findWhitespace.hasMatch(codeUnit);

/// Returns the first index whose ordered, non-overlapping match ends after
/// [offsetUtf16]. This lets bounded editor views skip matches before their
/// window without scanning or copying the full result list.
int firstTextMatchEndingAfter(List<TextMatch> matches, int offsetUtf16) {
  var low = 0;
  var high = matches.length;
  while (low < high) {
    final middle = (low + high) >> 1;
    if (matches[middle].end <= offsetUtf16) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

class ReplaceAllResult {
  const ReplaceAllResult(this.newText, this.count);

  final String newText;
  final int count;
}

/// 全部替换：按命中位置从后向前替换（避免偏移漂移与包含关系误替换）。
ReplaceAllResult replaceAllMatches(
  String text,
  String query,
  String replacement, {
  bool caseSensitive = false,
  bool wholeWord = false,
  bool preserveCase = false,
  List<TextMatchScope>? scopes,
}) {
  final matches = findMatches(
    text,
    query,
    caseSensitive: caseSensitive,
    wholeWord: wholeWord,
    scopes: scopes,
  );
  if (matches.isEmpty) return ReplaceAllResult(text, 0);
  final buf = StringBuffer();
  var cursor = 0;
  for (final m in matches) {
    buf
      ..write(text.substring(cursor, m.start))
      ..write(preserveCase
          ? buildPreserveCaseReplacement(
              text.substring(m.start, m.end),
              replacement,
            )
          : replacement);
    cursor = m.end;
  }
  buf.write(text.substring(cursor));
  return ReplaceAllResult(buf.toString(), matches.length);
}

/// Applies the Code-OSS Preserve Case transformation to one static value.
/// Regex templates with captures are intentionally handled by their explicit
/// capture and case-operation syntax instead.
String buildPreserveCaseReplacement(String source, String replacement) {
  if (source.isEmpty || replacement.isEmpty) return replacement;

  List<String> splitSegments(String value, int separator) {
    final segments = <String>[];
    var start = 0;
    for (var index = 0; index < value.length; index++) {
      if (value.codeUnitAt(index) != separator) continue;
      segments.add(value.substring(start, index));
      start = index + 1;
    }
    segments.add(value.substring(start));
    return segments;
  }

  final sourceHasHyphen = source.contains('-');
  final replacementHasHyphen = replacement.contains('-');
  final sourceHasUnderscore = source.contains('_');
  final replacementHasUnderscore = replacement.contains('_');
  if (sourceHasHyphen &&
      replacementHasHyphen &&
      !sourceHasUnderscore &&
      !replacementHasUnderscore &&
      sourceHasHyphen == replacementHasHyphen) {
    final sourceSegments = splitSegments(source, 0x2D);
    final replacementSegments = splitSegments(replacement, 0x2D);
    if (sourceSegments.length == replacementSegments.length) {
      return List<String>.generate(
        sourceSegments.length,
        (index) => buildPreserveCaseReplacement(
          sourceSegments[index],
          replacementSegments[index],
        ),
        growable: false,
      ).join('-');
    }
  }
  if (sourceHasUnderscore &&
      replacementHasUnderscore &&
      !sourceHasHyphen &&
      !replacementHasHyphen &&
      sourceHasUnderscore == replacementHasUnderscore) {
    final sourceSegments = splitSegments(source, 0x5F);
    final replacementSegments = splitSegments(replacement, 0x5F);
    if (sourceSegments.length == replacementSegments.length) {
      return List<String>.generate(
        sourceSegments.length,
        (index) => buildPreserveCaseReplacement(
          sourceSegments[index],
          replacementSegments[index],
        ),
        growable: false,
      ).join('_');
    }
  }

  if (unicodeFullUppercase(source) == source) {
    return unicodeFullUppercase(replacement);
  }
  if (unicodeFullLowercase(source) == source) {
    return unicodeFullLowercase(replacement);
  }

  final sourceFirst = String.fromCharCode(source.codeUnitAt(0));
  final replacementFirst = String.fromCharCode(replacement.codeUnitAt(0));
  if (unicodeFullLowercase(sourceFirst) != sourceFirst) {
    return '${unicodeFullUppercase(replacementFirst)}${replacement.substring(1)}';
  }
  if (unicodeFullLowercase(sourceFirst) == sourceFirst) {
    return '${unicodeFullLowercase(replacementFirst)}${replacement.substring(1)}';
  }
  return replacement;
}

/// 查找下一个命中（从 [from] 起环形）；无命中返回 null。
TextMatch? findNext(List<TextMatch> matches, int from, {bool wrap = true}) {
  for (final m in matches) {
    if (m.start >= from) return m;
  }
  if (wrap && matches.isNotEmpty) return matches.first;
  return null;
}

/// 查找上一个命中（从 [from] 前起环形）；无命中返回 null。
TextMatch? findPrevious(List<TextMatch> matches, int from, {bool wrap = true}) {
  for (var i = matches.length - 1; i >= 0; i--) {
    if (matches[i].end <= from) return matches[i];
  }
  if (wrap && matches.isNotEmpty) return matches.last;
  return null;
}
