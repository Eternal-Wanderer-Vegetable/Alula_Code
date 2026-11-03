/// 查找/替换纯逻辑（feat-010）。
///
/// Dart String 索引天然是 UTF-16 code unit 偏移，与 FFI 协议口径一致；
/// 本模块不做跨代理对特判（查询落在代理对内部不可能按整字符命中），
/// Emoji 用例由单测锁定。
library;

class TextMatch {
  const TextMatch(this.start, this.end);

  /// UTF-16 code unit 偏移（含头不含尾）。
  final int start;
  final int end;

  int get length => end - start;
}

class FindMatchesResult {
  const FindMatchesResult(this.matches);

  final List<TextMatch> matches;
}

/// 非重叠顺序查找全部命中；[query] 为空返回空列表。
List<TextMatch> findMatches(
  String text,
  String query, {
  bool caseSensitive = false,
  bool wholeWord = false,
}) {
  if (query.isEmpty) return const [];
  final out = <TextMatch>[];
  if (caseSensitive) {
    var offset = text.indexOf(query);
    while (offset >= 0) {
      final end = offset + query.length;
      if (!wholeWord || _isWholeWordRange(text, offset, end)) {
        out.add(TextMatch(offset, end));
      }
      offset = text.indexOf(query, end);
    }
    return out;
  }

  // Matching against a lowercased copy can shift UTF-16 offsets when Unicode
  // lowercasing expands a character (for example U+0130). RegExp reports
  // ranges in the original string while preserving literal, non-overlapping
  // matching semantics.
  final literal = RegExp(RegExp.escape(query), caseSensitive: false);
  for (final match in literal.allMatches(text)) {
    final start = match.start;
    final end = match.end;
    if (!wholeWord || _isWholeWordRange(text, start, end)) {
      out.add(TextMatch(start, end));
    }
  }
  return out;
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
}) {
  final matches = findMatches(
    text,
    query,
    caseSensitive: caseSensitive,
    wholeWord: wholeWord,
  );
  if (matches.isEmpty) return ReplaceAllResult(text, 0);
  final buf = StringBuffer();
  var cursor = 0;
  for (final m in matches) {
    buf
      ..write(text.substring(cursor, m.start))
      ..write(replacement);
    cursor = m.end;
  }
  buf.write(text.substring(cursor));
  return ReplaceAllResult(buf.toString(), matches.length);
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
