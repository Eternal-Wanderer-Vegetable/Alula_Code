/// A bounded TextMate snippet template expansion for the editor.
///
/// Offsets use Dart string indices, which are UTF-16 code units and therefore
/// match the editor's Rust FFI protocol.
class SnippetPlaceholderRange {
  const SnippetPlaceholderRange({
    required this.index,
    required this.startUtf16,
    required this.endUtf16,
  });

  /// Positive indices are visited in ascending order; zero is the final stop.
  final int index;
  final int startUtf16;
  final int endUtf16;

  int get lengthUtf16 => endUtf16 - startUtf16;
}

class SnippetExpansion {
  SnippetExpansion(
      {required this.text, required List<SnippetPlaceholderRange> placeholders})
      : placeholders = List.unmodifiable(placeholders);

  final String text;
  final List<SnippetPlaceholderRange> placeholders;

  List<int> get tabstopOrder {
    final indices =
        placeholders.map((placeholder) => placeholder.index).toSet();
    final positive = indices.where((index) => index > 0).toList()..sort();
    if (indices.contains(0)) positive.add(0);
    return List.unmodifiable(positive);
  }

  List<SnippetPlaceholderRange> rangesFor(int index) => List.unmodifiable(
        placeholders.where((placeholder) => placeholder.index == index),
      );
}

class SnippetTemplateException implements Exception {
  const SnippetTemplateException(this.message, this.offsetUtf16);

  final String message;
  final int offsetUtf16;

  @override
  String toString() =>
      'SnippetTemplateException($message at UTF-16 $offsetUtf16)';
}

/// Parses the basic TextMate placeholder subset used by snippet sessions.
///
/// Supported forms are `$1`, `${1}`, `${1:default}`, and `$0`. `\$`, `\}`,
/// and `\\` escape their following character. Choice, variable, transform, and
/// nested-placeholder syntax is kept for later parity slices; unsupported
/// choice/transform forms fail explicitly instead of producing a partial edit.
SnippetExpansion expandSnippetTemplate(
  String template, {
  bool insertFinalTabstop = true,
  int maxTemplateUtf16 = 64 * 1024,
  int maxExpandedUtf16 = 256 * 1024,
  int maxPlaceholderOccurrences = 512,
  int maxTabstopIndex = 10000,
}) {
  if (template.length > maxTemplateUtf16) {
    throw const SnippetTemplateException('template exceeds the size limit', 0);
  }

  final parser = _SnippetTemplateParser(
    template,
    insertFinalTabstop: insertFinalTabstop,
    maxExpandedUtf16: maxExpandedUtf16,
    maxPlaceholderOccurrences: maxPlaceholderOccurrences,
    maxTabstopIndex: maxTabstopIndex,
  );
  return parser.parse();
}

class _SnippetSegment {
  const _SnippetSegment.text(this.text)
      : index = null,
        defaultText = null;

  const _SnippetSegment.placeholder(this.index, this.defaultText) : text = null;

  final String? text;
  final int? index;

  /// `null` means a mirror; an empty string is an explicit empty default.
  final String? defaultText;
}

class _SnippetTemplateParser {
  _SnippetTemplateParser(
    this.template, {
    required this.insertFinalTabstop,
    required this.maxExpandedUtf16,
    required this.maxPlaceholderOccurrences,
    required this.maxTabstopIndex,
  }) : _units = template.codeUnits;

  static const int _dollar = 0x24;
  static const int _backslash = 0x5c;
  static const int _openBrace = 0x7b;
  static const int _closeBrace = 0x7d;
  static const int _colon = 0x3a;
  static const int _pipe = 0x7c;
  static const int _slash = 0x2f;
  static const int _zero = 0x30;
  static const int _nine = 0x39;

  final String template;
  final List<int> _units;
  final bool insertFinalTabstop;
  final int maxExpandedUtf16;
  final int maxPlaceholderOccurrences;
  final int maxTabstopIndex;
  final List<_SnippetSegment> _segments = [];
  int _offset = 0;
  int _placeholderCount = 0;

  SnippetExpansion parse() {
    final literal = StringBuffer();
    void flushLiteral() {
      if (literal.isEmpty) return;
      _segments.add(_SnippetSegment.text(literal.toString()));
      literal.clear();
    }

    while (_offset < _units.length) {
      final unit = _units[_offset];
      if (unit == _backslash && _offset + 1 < _units.length) {
        final escaped = _units[_offset + 1];
        if (_isEscapable(escaped)) {
          literal.writeCharCode(escaped);
          _offset += 2;
          continue;
        }
      }
      if (unit == _dollar) {
        final placeholder = _parsePlaceholder();
        if (placeholder != null) {
          flushLiteral();
          _segments.add(placeholder);
          _placeholderCount++;
          if (_placeholderCount > maxPlaceholderOccurrences) {
            throw SnippetTemplateException(
              'placeholder count exceeds the limit',
              _offset,
            );
          }
          continue;
        }
      }
      literal.writeCharCode(unit);
      _offset++;
    }
    flushLiteral();
    return _render();
  }

  bool _isEscapable(int unit) =>
      unit == _dollar || unit == _closeBrace || unit == _backslash;

  _SnippetSegment? _parsePlaceholder() {
    final start = _offset;
    var cursor = start + 1;
    var braced = false;
    if (cursor < _units.length && _units[cursor] == _openBrace) {
      braced = true;
      cursor++;
    }
    if (cursor >= _units.length || !_isDigit(_units[cursor])) return null;

    final indexStart = cursor;
    while (cursor < _units.length && _isDigit(_units[cursor])) {
      cursor++;
    }
    final index =
        int.parse(String.fromCharCodes(_units.sublist(indexStart, cursor)));
    if (index > maxTabstopIndex) {
      throw SnippetTemplateException('tabstop index exceeds the limit', start);
    }

    if (!braced) {
      _offset = cursor;
      return _SnippetSegment.placeholder(index, null);
    }
    if (cursor >= _units.length) return null;

    final marker = _units[cursor];
    if (marker == _closeBrace) {
      _offset = cursor + 1;
      return _SnippetSegment.placeholder(index, null);
    }
    if (marker == _pipe || marker == _slash) {
      throw SnippetTemplateException(
        marker == _pipe
            ? 'choice placeholders are not supported yet'
            : 'transforms are not supported yet',
        start,
      );
    }
    if (marker != _colon) return null;

    cursor++;
    final defaultText = StringBuffer();
    while (cursor < _units.length) {
      final unit = _units[cursor];
      if (unit == _backslash && cursor + 1 < _units.length) {
        final escaped = _units[cursor + 1];
        if (_isEscapable(escaped)) {
          defaultText.writeCharCode(escaped);
          cursor += 2;
          continue;
        }
      }
      if (unit == _closeBrace) {
        _offset = cursor + 1;
        return _SnippetSegment.placeholder(index, defaultText.toString());
      }
      if (unit == _dollar && cursor + 1 < _units.length) {
        final next = _units[cursor + 1];
        if (_isDigit(next) || next == _openBrace) {
          throw SnippetTemplateException(
            'nested placeholders are not supported yet',
            cursor,
          );
        }
      }
      defaultText.writeCharCode(unit);
      cursor++;
    }
    // An incomplete `${n:...` is ordinary text in TextMate snippets.
    return null;
  }

  bool _isDigit(int unit) => unit >= _zero && unit <= _nine;

  SnippetExpansion _render() {
    final defaults = <int, String>{};
    for (final segment in _segments) {
      final index = segment.index;
      final value = segment.defaultText;
      if (index != null && index != 0 && value != null && value.isNotEmpty) {
        defaults.putIfAbsent(index, () => value);
      }
    }

    final output = StringBuffer();
    final placeholders = <SnippetPlaceholderRange>[];
    var outputOffset = 0;
    void append(String value) {
      if (outputOffset + value.length > maxExpandedUtf16) {
        throw SnippetTemplateException(
          'expanded snippet exceeds the size limit',
          _offset,
        );
      }
      output.write(value);
      outputOffset += value.length;
    }

    for (final segment in _segments) {
      final index = segment.index;
      if (index == null) {
        append(segment.text!);
        continue;
      }
      final start = outputOffset;
      final ownDefault = segment.defaultText;
      final value =
          index == 0 ? ownDefault ?? '' : defaults[index] ?? ownDefault ?? '';
      append(value);
      placeholders.add(SnippetPlaceholderRange(
        index: index,
        startUtf16: start,
        endUtf16: outputOffset,
      ));
    }
    if (insertFinalTabstop &&
        placeholders.isNotEmpty &&
        placeholders.every((placeholder) => placeholder.index != 0)) {
      placeholders.add(SnippetPlaceholderRange(
        index: 0,
        startUtf16: outputOffset,
        endUtf16: outputOffset,
      ));
    }
    return SnippetExpansion(
      text: output.toString(),
      placeholders: placeholders,
    );
  }
}
