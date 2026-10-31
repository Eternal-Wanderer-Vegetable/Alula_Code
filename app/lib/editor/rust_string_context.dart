/// Whether a UTF-16 caret position is inside a Rust string token.
enum RustStringContext { outside, inside, unknown }

/// Checks a current Tree-sitter snapshot without scanning its token list.
///
/// Tokens are sorted and non-overlapping. A missing or stale snapshot returns
/// [RustStringContext.unknown], so callers can avoid applying token-sensitive
/// editing behavior to an unverified document version.
RustStringContext rustStringContextAt({
  required List<Map<String, Object?>> tokens,
  required int tokenVersion,
  required int documentVersion,
  required int offsetUtf16,
}) {
  if (tokenVersion != documentVersion || offsetUtf16 < 0) {
    return RustStringContext.unknown;
  }

  var low = 0;
  var high = tokens.length;
  while (low < high) {
    final middle = low + ((high - low) >> 1);
    final end = tokens[middle]['end_utf16'];
    if (end is! int) return RustStringContext.unknown;
    if (end <= offsetUtf16) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }

  if (low == tokens.length) return RustStringContext.outside;
  final token = tokens[low];
  final start = token['start_utf16'];
  final end = token['end_utf16'];
  final kind = token['kind'];
  if (start is! int || end is! int || kind is! String) {
    return RustStringContext.unknown;
  }
  if (start < offsetUtf16 && offsetUtf16 < end && kind.startsWith('string')) {
    return RustStringContext.inside;
  }
  return RustStringContext.outside;
}
