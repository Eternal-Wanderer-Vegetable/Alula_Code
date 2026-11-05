typedef ClipboardTokenColor = String Function(String kind);

const int maxClipboardHtmlUtf16 = 64 * 1024 - 1;
const int maxClipboardHtmlTokens = 10000;
const int maxClipboardHtmlOutputChars = 1024 * 1024;

/// Builds the HTML fragment used for a syntax-highlighted editor copy.
///
/// Token offsets and selection offsets use Rust's UTF-16 document coordinate
/// system. Large selections or unusually dense token ranges fall back to plain
/// text instead of growing an unbounded HTML string.
String? buildRichTextClipboardHtml({
  required String text,
  required int selectionStartUtf16,
  required String languageId,
  required List<Map<String, Object?>> tokens,
  required ClipboardTokenColor colorForToken,
  String foreground = '#D4D4D4',
  String background = '#1E1E1E',
}) {
  if (languageId == 'plaintext' ||
      text.length >= maxClipboardHtmlUtf16 ||
      selectionStartUtf16 < 0) {
    return null;
  }

  final selectionEndUtf16 = selectionStartUtf16 + text.length;
  var low = 0;
  var high = tokens.length;
  while (low < high) {
    final middle = (low + high) >> 1;
    final end = _tokenOffset(tokens[middle], 'end_utf16');
    if (end != null && end <= selectionStartUtf16) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }

  final overlappingTokens = <({int start, int end, String color})>[];
  for (var index = low; index < tokens.length; index++) {
    final token = tokens[index];
    final start = _tokenOffset(token, 'start_utf16');
    final end = _tokenOffset(token, 'end_utf16');
    if (start == null || end == null || start >= selectionEndUtf16) break;
    if (end <= start || end <= selectionStartUtf16) continue;
    overlappingTokens.add((
      start: start < selectionStartUtf16 ? selectionStartUtf16 : start,
      end: end > selectionEndUtf16 ? selectionEndUtf16 : end,
      color: colorForToken((token['kind'] as String?) ?? ''),
    ));
    if (overlappingTokens.length > maxClipboardHtmlTokens) return null;
  }

  final body = StringBuffer();
  var tokenIndex = 0;
  var absoluteOffset = selectionStartUtf16;
  final lines = text.split('\n');
  for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
    final line = lines[lineIndex];
    if (line.isEmpty) {
      body.write('<br>');
    } else {
      final lineEnd = absoluteOffset + line.length;
      var cursor = absoluteOffset;
      while (tokenIndex < overlappingTokens.length &&
          overlappingTokens[tokenIndex].end <= cursor) {
        tokenIndex++;
      }
      var currentTokenIndex = tokenIndex;
      while (currentTokenIndex < overlappingTokens.length) {
        final token = overlappingTokens[currentTokenIndex];
        if (token.start >= lineEnd) break;
        final tokenStart = token.start < cursor ? cursor : token.start;
        final tokenEnd = token.end > lineEnd ? lineEnd : token.end;
        if (tokenStart > cursor) {
          body.write(_escapeHtml(text.substring(
            cursor - selectionStartUtf16,
            tokenStart - selectionStartUtf16,
          )));
        }
        if (tokenEnd > tokenStart) {
          body
            ..write('<span style="color:')
            ..write(_safeCssColor(token.color))
            ..write(';">')
            ..write(_escapeHtml(text.substring(
              tokenStart - selectionStartUtf16,
              tokenEnd - selectionStartUtf16,
            )))
            ..write('</span>');
          cursor = tokenEnd;
        }
        currentTokenIndex++;
      }
      if (cursor < lineEnd) {
        body.write(_escapeHtml(text.substring(
          cursor - selectionStartUtf16,
          lineEnd - selectionStartUtf16,
        )));
      }
      tokenIndex = currentTokenIndex;
    }
    absoluteOffset += line.length;
    if (lineIndex + 1 < lines.length) {
      body.write('\n');
      absoluteOffset++;
    }
    if (body.length > maxClipboardHtmlOutputChars) return null;
  }

  return '<div style="color:${_safeCssColor(foreground)};'
      'background-color:${_safeCssColor(background)};'
      'font-family:monospace;font-size:14px;line-height:20px;'
      'white-space:pre;tab-size:4;">${body.toString()}</div>';
}

int? _tokenOffset(Map<String, Object?> token, String key) {
  final value = token[key];
  return value is num ? value.toInt() : null;
}

String _escapeHtml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

String _safeCssColor(String value) {
  final normalized = value.toUpperCase();
  return RegExp(r'^#[0-9A-F]{6}$').hasMatch(normalized)
      ? normalized
      : '#D4D4D4';
}
