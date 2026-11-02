import 'package:path/path.dart' as path;

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

/// Returns the built-in filename variables for a named document.
///
/// Untitled documents resolve both variables to the empty string. A leading
/// dot is not treated as an extension separator, matching Code-OSS behavior.
Map<String, String> snippetFilenameVariables(String? filename) {
  final value = filename ?? '';
  final extensionStart = value.lastIndexOf('.');
  final baseName =
      extensionStart <= 0 ? value : value.substring(0, extensionStart);
  return {'TM_FILENAME': value, 'TM_FILENAME_BASE': baseName};
}

/// Returns the local path variables for a named document.
///
/// Labels use the host path style, normalize separators, lowercase a Windows
/// drive letter like Code-OSS, and abbreviate paths under [userHome] on
/// non-Windows hosts. Untitled documents resolve to empty strings.
Map<String, String> snippetDocumentPathVariables(
  String? filePath, {
  required bool windows,
  String? userHome,
}) {
  if (filePath == null || filePath.isEmpty) {
    return const {
      'TM_DIRECTORY': '',
      'TM_DIRECTORY_BASE': '',
      'TM_FILEPATH': '',
    };
  }

  final context = path.Context(
    style: windows ? path.Style.windows : path.Style.posix,
  );
  final normalizedPath = context.normalize(filePath);
  final directory = context.dirname(normalizedPath);
  final hasDirectory = directory != '.';
  final pathLabel = _snippetPathLabel(
    normalizedPath,
    context: context,
    windows: windows,
    userHome: userHome,
  );
  final directoryLabel = hasDirectory
      ? _snippetPathLabel(
          directory,
          context: context,
          windows: windows,
          userHome: userHome,
        )
      : '';

  return {
    'TM_DIRECTORY': directoryLabel,
    'TM_DIRECTORY_BASE': hasDirectory && context.dirname(directory) != directory
        ? context.basename(directory)
        : '',
    'TM_FILEPATH': pathLabel,
  };
}

/// Returns Code-OSS's built-in workspace variables for the opened folder.
///
/// Alula currently supports one workspace folder, so its name is the root
/// folder basename and its folder value is the normalized absolute path.
/// Unlike document path labels, workspace folders are not abbreviated to `~`.
Map<String, String> snippetWorkspaceVariables(
  String? workspaceRoot, {
  required bool windows,
}) {
  if (workspaceRoot == null || workspaceRoot.isEmpty) {
    return const {
      'WORKSPACE_NAME': '',
      'WORKSPACE_FOLDER': '',
    };
  }

  final context = path.Context(
    style: windows ? path.Style.windows : path.Style.posix,
  );
  final normalizedRoot = context.normalize(workspaceRoot);
  return {
    'WORKSPACE_NAME': context.basename(normalizedRoot),
    'WORKSPACE_FOLDER': _snippetPathLabel(
      normalizedRoot,
      context: context,
      windows: windows,
    ),
  };
}

/// Returns Code-OSS's built-in relative filepath variable for a document.
///
/// A file inside [workspaceRoot] is labeled relative to that root, without a
/// root-name prefix. Files outside the root (or with no root) use the same
/// normalized absolute label as `TM_FILEPATH`. Untitled documents are empty.
Map<String, String> snippetRelativeFilePathVariables(
  String? filePath,
  String? workspaceRoot, {
  required bool windows,
  String? userHome,
}) {
  if (filePath == null || filePath.isEmpty) {
    return const {'RELATIVE_FILEPATH': ''};
  }

  final context = path.Context(
    style: windows ? path.Style.windows : path.Style.posix,
  );
  final normalizedFile = context.normalize(filePath);
  final normalizedRoot = workspaceRoot == null || workspaceRoot.isEmpty
      ? null
      : context.normalize(workspaceRoot);
  if (normalizedRoot != null) {
    final fileForComparison =
        windows ? normalizedFile.toLowerCase() : normalizedFile;
    final rootForComparison =
        windows ? normalizedRoot.toLowerCase() : normalizedRoot;
    if (fileForComparison == rootForComparison) {
      return const {'RELATIVE_FILEPATH': ''};
    }

    final separator = context.separator;
    final rootPrefix = normalizedRoot.endsWith(separator)
        ? normalizedRoot
        : '$normalizedRoot$separator';
    final prefixForComparison = windows ? rootPrefix.toLowerCase() : rootPrefix;
    if (fileForComparison.startsWith(prefixForComparison)) {
      final relativePath = context.normalize(
        normalizedFile.substring(rootPrefix.length),
      );
      return {'RELATIVE_FILEPATH': relativePath};
    }
  }

  return {
    'RELATIVE_FILEPATH': _snippetPathLabel(
      normalizedFile,
      context: context,
      windows: windows,
      userHome: userHome,
    ),
  };
}

/// Returns the zero-based and one-based line variables for a document line.
Map<String, String> snippetLineVariables(int zeroBasedLine) {
  if (zeroBasedLine < 0) {
    throw RangeError.value(
      zeroBasedLine,
      'zeroBasedLine',
      'must be non-negative',
    );
  }
  return {
    'TM_LINE_INDEX': '$zeroBasedLine',
    'TM_LINE_NUMBER': '${zeroBasedLine + 1}',
  };
}

/// Returns the current logical line variable without reparsing its contents.
Map<String, String> snippetCurrentLineVariables(String currentLine) => {
      'TM_CURRENT_LINE': currentLine,
    };

const int snippetCurrentWordContextUtf16 = 1000;
final RegExp _snippetDefaultWordDefinition = RegExp(
  r'''(-?\d*\.\d\w*)|([^\`\~\!\@\#\$\%\^\&\*\(\)\-\=\+\[\{\]\}\\\|\;\:\'\"\,\.\<\>\/\?\s]+)''',
);

/// Returns Code-OSS's default word at [zeroBasedColumnUtf16].
///
/// Alula does not yet expose per-language `wordPattern` configuration, so
/// this uses the default word definition. The search window matches the
/// bounded 1000-code-unit context used by Code-OSS for long lines.
Map<String, String> snippetCurrentWordVariables(
  String lineContext,
  int zeroBasedColumnUtf16,
) {
  if (zeroBasedColumnUtf16 < 0 || zeroBasedColumnUtf16 > lineContext.length) {
    throw RangeError.range(
      zeroBasedColumnUtf16,
      0,
      lineContext.length,
      'zeroBasedColumnUtf16',
    );
  }

  var text = lineContext;
  var textOffset = 0;
  if (text.length > snippetCurrentWordContextUtf16) {
    const halfContext = snippetCurrentWordContextUtf16 ~/ 2;
    var start = zeroBasedColumnUtf16 + 1 - halfContext;
    if (start < 0) {
      start = 0;
    } else {
      textOffset = start;
    }
    var end = zeroBasedColumnUtf16 + 1 + halfContext;
    if (end > text.length) end = text.length;
    text = text.substring(start, end);
  }

  final position = zeroBasedColumnUtf16 - textOffset;
  for (final match in _snippetDefaultWordDefinition.allMatches(text)) {
    if (match.start <= position && position <= match.end) {
      return {'TM_CURRENT_WORD': match.group(0)!};
    }
  }
  return const {};
}

/// Reports whether [template] contains a syntactically recognized [name]
/// variable reference. Escaped variables and text inside another variable's
/// default value are not references because the snippet parser keeps both
/// literal.
bool snippetTemplateUsesVariable(String template, String name) {
  final units = template.codeUnits;
  var offset = 0;
  while (offset < units.length) {
    final unit = units[offset];
    if (unit == 0x5c &&
        offset + 1 < units.length &&
        _isSnippetEscape(units[offset + 1])) {
      offset += 2;
      continue;
    }
    if (unit != 0x24) {
      offset++;
      continue;
    }

    var cursor = offset + 1;
    var braced = false;
    if (cursor < units.length && units[cursor] == 0x7b) {
      braced = true;
      cursor++;
    }
    if (cursor >= units.length || !_isSnippetVariableStart(units[cursor])) {
      offset++;
      continue;
    }

    final nameStart = cursor++;
    while (cursor < units.length && _isSnippetVariablePart(units[cursor])) {
      cursor++;
    }
    final matches =
        String.fromCharCodes(units.sublist(nameStart, cursor)) == name;
    if (!braced) {
      if (matches) return true;
      offset = cursor;
      continue;
    }

    if (cursor < units.length && units[cursor] == 0x7d) {
      if (matches) return true;
      offset = cursor + 1;
      continue;
    }
    if (cursor < units.length && units[cursor] == 0x3a) {
      cursor++;
      var closed = false;
      while (cursor < units.length) {
        if (units[cursor] == 0x5c &&
            cursor + 1 < units.length &&
            _isSnippetEscape(units[cursor + 1])) {
          cursor += 2;
          continue;
        }
        if (units[cursor] == 0x7d) {
          cursor++;
          closed = true;
          break;
        }
        cursor++;
      }
      if (closed) {
        if (matches) return true;
        offset = cursor;
        continue;
      }
    }

    // Malformed and transformed variables are not resolved by this parser.
    offset++;
  }
  return false;
}

bool _isSnippetEscape(int unit) => unit == 0x24 || unit == 0x7d || unit == 0x5c;

bool _isSnippetVariableStart(int unit) =>
    (unit >= 0x41 && unit <= 0x5a) ||
    (unit >= 0x61 && unit <= 0x7a) ||
    unit == 0x5f;

bool _isSnippetVariablePart(int unit) =>
    _isSnippetVariableStart(unit) || (unit >= 0x30 && unit <= 0x39);

String _snippetPathLabel(
  String value, {
  required path.Context context,
  required bool windows,
  String? userHome,
}) {
  final label = context.normalize(value);
  if (windows) {
    return label.replaceFirstMapped(
      RegExp(r'^([A-Z]):'),
      (match) => '${match[1]!.toLowerCase()}:',
    );
  }

  if (userHome == null || userHome.isEmpty) return label;
  final normalizedHome = context.normalize(userHome);
  if (label == normalizedHome) return '~';
  final homePrefix = normalizedHome == '/' ? '/' : '$normalizedHome/';
  if (!label.startsWith(homePrefix)) return label;
  if (normalizedHome == '/') return '~/${label.substring(1)}';
  return '~${label.substring(normalizedHome.length)}';
}

/// Parses the basic TextMate placeholder subset used by snippet sessions.
///
/// Supported forms are `$1`, `${1}`, `${1:default}`, `$0`, and the
/// `$TM_SELECTED_TEXT`, `$TM_FILENAME`, `$TM_FILENAME_BASE`, `$TM_DIRECTORY`,
/// `$TM_DIRECTORY_BASE`, `$TM_FILEPATH`, `$RELATIVE_FILEPATH`,
/// `$TM_LINE_INDEX`, `$TM_LINE_NUMBER`, `$WORKSPACE_NAME`, and
/// `$WORKSPACE_FOLDER`
/// variables, plus `$TM_CURRENT_LINE` and `$TM_CURRENT_WORD` when supplied by
/// the workbench.
/// `\$`, `\}`, and `\\` escape their following character. Unknown variables
/// are kept verbatim. Choice, transform, and nested-placeholder syntax is kept
/// for later parity slices; unsupported choice/transform forms fail explicitly
/// instead of producing a partial edit.
SnippetExpansion expandSnippetTemplate(
  String template, {
  Map<String, String> variables = const {},
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
    variables: variables,
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
    required this.variables,
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
  final Map<String, String> variables;
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
        final variable = _parseVariable();
        if (variable != null) {
          flushLiteral();
          _segments.add(variable);
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

  _SnippetSegment? _parseVariable() {
    final start = _offset;
    var cursor = start + 1;
    var braced = false;
    if (cursor < _units.length && _units[cursor] == _openBrace) {
      braced = true;
      cursor++;
    }
    if (cursor >= _units.length || !_isVariableStart(_units[cursor])) {
      return null;
    }

    final nameStart = cursor++;
    while (cursor < _units.length && _isVariablePart(_units[cursor])) {
      cursor++;
    }
    final name = String.fromCharCodes(_units.sublist(nameStart, cursor));
    if (braced) {
      if (cursor < _units.length && _units[cursor] == _closeBrace) {
        cursor++;
      } else if (cursor < _units.length && _units[cursor] == _colon) {
        cursor++;
        var closed = false;
        while (cursor < _units.length) {
          final unit = _units[cursor];
          if (unit == _backslash && cursor + 1 < _units.length) {
            final escaped = _units[cursor + 1];
            if (_isEscapable(escaped)) {
              cursor += 2;
              continue;
            }
          }
          if (unit == _closeBrace) {
            cursor++;
            closed = true;
            break;
          }
          cursor++;
        }
        if (!closed) return null;
      } else if (cursor < _units.length && _units[cursor] == _slash) {
        throw SnippetTemplateException(
          'variable transforms are not supported yet',
          start,
        );
      } else {
        // Leave malformed expressions untouched for a later parity slice.
        return null;
      }
    }

    final value = variables[name];
    _offset = cursor;
    return _SnippetSegment.text(value ?? template.substring(start, cursor));
  }

  bool _isVariableStart(int unit) =>
      (unit >= 0x41 && unit <= 0x5a) ||
      (unit >= 0x61 && unit <= 0x7a) ||
      unit == 0x5f;

  bool _isVariablePart(int unit) => _isVariableStart(unit) || _isDigit(unit);

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
