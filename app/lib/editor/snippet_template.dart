import 'package:path/path.dart' as path;

import 'snippet_variable_transform.dart';

/// A bounded TextMate snippet template expansion for the editor.
///
/// Offsets use Dart string indices, which are UTF-16 code units and therefore
/// match the editor's Rust FFI protocol.
class SnippetChoice {
  SnippetChoice(Iterable<String> options)
      : options = List.unmodifiable(options);

  final List<String> options;
}

class SnippetPlaceholderRange {
  const SnippetPlaceholderRange({
    required this.index,
    required this.startUtf16,
    required this.endUtf16,
    this.choice,
    this.occurrenceId = 0,
    this.ancestorOccurrenceIds = const [],
    this.transform,
  });

  /// Positive indices are visited in ascending order; zero is the final stop.
  final int index;
  final int startUtf16;
  final int endUtf16;
  final SnippetChoice? choice;
  final int occurrenceId;
  final List<int> ancestorOccurrenceIds;
  final SnippetVariableTransform? transform;

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

const int maxSnippetClipboardUtf16 = 256 * 1024;

/// Returns the clipboard snippet variable when it contains text.
///
/// Code-OSS leaves an empty clipboard variable unresolved so a variable's
/// default can be used. The parser applies that fallback only to `CLIPBOARD`;
/// other unresolved variables keep Alula's existing literal-preservation
/// behavior.
Map<String, String> snippetClipboardVariables(String? clipboardText) {
  if (clipboardText == null || clipboardText.isEmpty) return const {};
  return {'CLIPBOARD': clipboardText};
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
/// variable reference. Escaped variables, transform replacement text, and
/// text inside another variable's default value are not references because
/// the snippet parser keeps them literal.
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

    if (cursor < units.length && units[cursor] == 0x2f) {
      final transformEnd = _skipSnippetVariableTransform(units, cursor);
      if (transformEnd >= 0) {
        if (matches) return true;
        offset = transformEnd;
      } else {
        offset = _skipMalformedSnippetVariableTransform(units, cursor);
      }
      continue;
    }

    // Leave malformed references literal; valid transforms are handled above.
    offset++;
  }
  return false;
}

int _skipSnippetVariableTransform(List<int> units, int slashOffset) {
  var cursor = slashOffset + 1;
  for (var section = 0; section < 2; section++) {
    var formatExpressionDepth = 0;
    while (cursor < units.length) {
      final unit = units[cursor];
      if (unit == 0x5c && cursor + 1 < units.length) {
        cursor += 2;
        continue;
      }
      if (section == 1 &&
          unit == 0x24 &&
          cursor + 1 < units.length &&
          units[cursor + 1] == 0x7b) {
        formatExpressionDepth++;
        cursor += 2;
        continue;
      }
      if (section == 1 && unit == 0x7d && formatExpressionDepth > 0) {
        formatExpressionDepth--;
        cursor++;
        continue;
      }
      if (unit == 0x2f && formatExpressionDepth == 0) break;
      cursor++;
    }
    if (cursor >= units.length) return -1;
    cursor++;
  }

  while (cursor < units.length && units[cursor] != 0x7d) {
    cursor++;
  }
  return cursor < units.length ? cursor + 1 : -1;
}

int _skipMalformedSnippetVariableTransform(List<int> units, int slashOffset) {
  var cursor = slashOffset + 1;
  var nestedVariableDepth = 0;
  while (cursor < units.length) {
    final unit = units[cursor];
    if (unit == 0x5c && cursor + 1 < units.length) {
      cursor += 2;
      continue;
    }
    if (unit == 0x24 &&
        cursor + 1 < units.length &&
        units[cursor + 1] == 0x7b) {
      nestedVariableDepth++;
      cursor += 2;
      continue;
    }
    if (unit == 0x7d) {
      cursor++;
      if (nestedVariableDepth == 0) return cursor;
      nestedVariableDepth--;
      continue;
    }
    cursor++;
  }
  return cursor;
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

/// Parses the bounded TextMate placeholder subset used by snippet sessions.
///
/// Supported forms are `$1`, `${1}`, `${1:default}`, `$0`, and the
/// `$TM_SELECTED_TEXT`, `$TM_FILENAME`, `$TM_FILENAME_BASE`, `$TM_DIRECTORY`,
/// `$TM_DIRECTORY_BASE`, `$TM_FILEPATH`, `$RELATIVE_FILEPATH`,
/// `$TM_LINE_INDEX`, `$TM_LINE_NUMBER`, `$WORKSPACE_NAME`, and
/// `$WORKSPACE_FOLDER`
/// variables, plus `$TM_CURRENT_LINE` and `$TM_CURRENT_WORD` when supplied by
/// the workbench, and `$CLIPBOARD` when the system clipboard has text.
/// `\$`, `\}`, and `\\` escape their following character. Unknown variables
/// are kept verbatim. Positive-index choices support `${1|one,two|}` and
/// TextMate's `\,`, `\|`, and `\\` choice escapes. Placeholder defaults can
/// contain nested placeholders up to a fixed depth. Variable transforms are
/// evaluated in a bounded worker; placeholder transforms remain unsupported
/// and fail explicitly instead of producing a partial edit.
Future<SnippetExpansion> expandSnippetTemplate(
  String template, {
  Map<String, String> variables = const {},
  bool insertFinalTabstop = true,
  int maxTemplateUtf16 = 64 * 1024,
  int maxExpandedUtf16 = 256 * 1024,
  int maxPlaceholderOccurrences = 512,
  int maxTabstopIndex = 10000,
  int maxChoiceOptions = 256,
}) async {
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
    maxChoiceOptions: maxChoiceOptions,
    maxNestingDepth: 32,
  );
  return parser.parse();
}

class _SnippetSegment {
  const _SnippetSegment.text(this.text)
      : index = null,
        defaultSegments = null,
        choice = null,
        transform = null,
        variableTransform = null;

  const _SnippetSegment.placeholder(
    this.index,
    this.defaultSegments, {
    this.choice,
    this.transform,
  })  : text = null,
        variableTransform = null;

  const _SnippetSegment.variableTransform(this.variableTransform)
      : text = null,
        index = null,
        defaultSegments = null,
        choice = null,
        transform = null;

  final String? text;
  final int? index;
  final SnippetChoice? choice;
  final SnippetVariableTransform? variableTransform;
  final SnippetVariableTransform? transform;

  /// `null` means a mirror; an empty list is an explicit empty default.
  final List<_SnippetSegment>? defaultSegments;
}

class _SnippetTemplateParser {
  _SnippetTemplateParser(
    this.template, {
    required this.variables,
    required this.insertFinalTabstop,
    required this.maxExpandedUtf16,
    required this.maxPlaceholderOccurrences,
    required this.maxTabstopIndex,
    required this.maxChoiceOptions,
    required this.maxNestingDepth,
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
  final int maxChoiceOptions;
  final int maxNestingDepth;
  int _offset = 0;

  Future<SnippetExpansion> parse() async {
    final segments = _parseSequence(stopAtClose: false, nestingDepth: 0);
    if (_countPlaceholders(segments) > maxPlaceholderOccurrences) {
      throw SnippetTemplateException(
        'placeholder count exceeds the limit',
        _offset,
      );
    }
    try {
      return _render(await _resolveVariableTransforms(segments));
    } on SnippetVariableTransformException catch (error) {
      throw SnippetTemplateException(error.message, error.offsetUtf16);
    }
  }

  Future<List<_SnippetSegment>> _resolveVariableTransforms(
    List<_SnippetSegment> segments,
  ) async {
    final transforms = <SnippetVariableTransform>[];
    void collect(List<_SnippetSegment> current) {
      for (final segment in current) {
        final transform = segment.variableTransform;
        if (transform != null) transforms.add(transform);
        final children = segment.defaultSegments;
        if (children != null) collect(children);
      }
    }

    collect(segments);
    if (transforms.isEmpty) return segments;
    final transformedText = await applySnippetVariableTransforms(transforms);
    var transformIndex = 0;
    List<_SnippetSegment> replace(List<_SnippetSegment> current) => [
          for (final segment in current)
            if (segment.variableTransform != null)
              _SnippetSegment.text(transformedText[transformIndex++])
            else if (segment.defaultSegments != null)
              _SnippetSegment.placeholder(
                segment.index!,
                replace(segment.defaultSegments!),
                choice: segment.choice,
                transform: segment.transform,
              )
            else
              segment,
        ];

    return replace(segments);
  }

  int _countPlaceholders(List<_SnippetSegment> segments) {
    var count = 0;
    for (final segment in segments) {
      if (segment.index != null) count++;
      final children = segment.defaultSegments;
      if (children != null) count += _countPlaceholders(children);
    }
    return count;
  }

  List<_SnippetSegment> _parseSequence({
    required bool stopAtClose,
    required int nestingDepth,
  }) {
    final segments = <_SnippetSegment>[];
    final literal = StringBuffer();
    void flushLiteral() {
      if (literal.isEmpty) return;
      segments.add(_SnippetSegment.text(literal.toString()));
      literal.clear();
    }

    while (_offset < _units.length) {
      final unit = _units[_offset];
      if (stopAtClose && unit == _closeBrace) break;
      if (unit == _backslash && _offset + 1 < _units.length) {
        final escaped = _units[_offset + 1];
        if (_isEscapable(escaped)) {
          literal.writeCharCode(escaped);
          _offset += 2;
          continue;
        }
      }
      if (unit == _dollar) {
        final placeholder = _parsePlaceholder(nestingDepth: nestingDepth);
        if (placeholder != null) {
          flushLiteral();
          segments.add(placeholder);
          continue;
        }
        final variable = _parseVariable();
        if (variable != null) {
          flushLiteral();
          segments.add(variable);
          continue;
        }
      }
      literal.writeCharCode(unit);
      _offset++;
    }
    flushLiteral();
    return segments;
  }

  bool _isEscapable(int unit) =>
      unit == _dollar || unit == _closeBrace || unit == _backslash;

  _SnippetSegment? _parsePlaceholder({required int nestingDepth}) {
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
    if (marker == _pipe) {
      if (index == 0) return null;
      final parsedChoice = _parseChoice(cursor + 1);
      if (parsedChoice == null) return null;
      _offset = parsedChoice.endOffset;
      return _SnippetSegment.placeholder(
        index,
        [_SnippetSegment.text(parsedChoice.choice.options.first)],
        choice: parsedChoice.choice,
      );
    }
    if (marker == _slash) {
      try {
        final parsed = _parseVariableTransform(
          cursor + 1,
          start: start,
          value: '',
          usePlaceholderNoMatchSemantics: true,
        );
        _offset = parsed.endOffset;
        return _SnippetSegment.placeholder(
          index,
          null,
          transform: parsed.transform,
        );
      } on SnippetTemplateException catch (error) {
        if (error.message != 'unterminated variable transform') rethrow;
        return null;
      }
    }
    if (marker != _colon) return null;

    if (nestingDepth >= maxNestingDepth) {
      throw SnippetTemplateException(
        'placeholder nesting exceeds the limit',
        start,
      );
    }
    _offset = cursor + 1;
    final defaultSegments = _parseSequence(
      stopAtClose: true,
      nestingDepth: nestingDepth + 1,
    );
    if (_offset >= _units.length || _units[_offset] != _closeBrace) {
      // An incomplete `${n:...` is ordinary text in TextMate snippets.
      _offset = start;
      return null;
    }
    _offset++;
    return _SnippetSegment.placeholder(index, defaultSegments);
  }

  _ParsedSnippetChoice? _parseChoice(int cursor) {
    final options = <String>[];
    var option = StringBuffer();
    var optionCount = 0;
    while (cursor < _units.length) {
      final unit = _units[cursor];
      if (unit == _backslash) {
        if (cursor + 1 >= _units.length) return null;
        final escaped = _units[cursor + 1];
        if (escaped == _backslash || escaped == _pipe || escaped == 0x2c) {
          option.writeCharCode(escaped);
          cursor += 2;
        } else {
          option.writeCharCode(unit);
          cursor++;
        }
        continue;
      }
      if (unit == 0x2c) {
        if (option.isEmpty) return null;
        optionCount++;
        if (optionCount <= maxChoiceOptions) options.add(option.toString());
        option = StringBuffer();
        cursor++;
        continue;
      }
      if (unit == _pipe) {
        if (option.isEmpty ||
            cursor + 1 >= _units.length ||
            _units[cursor + 1] != _closeBrace) {
          return null;
        }
        optionCount++;
        if (optionCount > maxChoiceOptions) {
          throw SnippetTemplateException(
            'choice option count exceeds the limit',
            cursor,
          );
        }
        options.add(option.toString());
        return _ParsedSnippetChoice(SnippetChoice(options), cursor + 2);
      }
      option.writeCharCode(unit);
      cursor++;
    }
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
    String? defaultValue;
    if (braced) {
      if (cursor < _units.length && _units[cursor] == _closeBrace) {
        cursor++;
      } else if (cursor < _units.length && _units[cursor] == _colon) {
        cursor++;
        final value = StringBuffer();
        var closed = false;
        while (cursor < _units.length) {
          final unit = _units[cursor];
          if (unit == _backslash && cursor + 1 < _units.length) {
            final escaped = _units[cursor + 1];
            if (_isEscapable(escaped)) {
              value.writeCharCode(escaped);
              cursor += 2;
              continue;
            }
          }
          if (unit == _closeBrace) {
            cursor++;
            closed = true;
            break;
          }
          value.writeCharCode(unit);
          cursor++;
        }
        if (!closed) return null;
        defaultValue = value.toString();
      } else if (cursor < _units.length && _units[cursor] == _slash) {
        final parsed = _parseVariableTransform(
          cursor + 1,
          start: start,
          value: variables[name] ?? '',
        );
        _offset = parsed.endOffset;
        return _SnippetSegment.variableTransform(parsed.transform);
      } else {
        // Leave malformed expressions untouched for a later parity slice.
        return null;
      }
    }

    final value = variables[name];
    _offset = cursor;
    if (name == 'CLIPBOARD' && (value == null || value.isEmpty)) {
      return _SnippetSegment.text(defaultValue ?? '');
    }
    return _SnippetSegment.text(value ?? template.substring(start, cursor));
  }

  _ParsedVariableTransform _parseVariableTransform(
    int cursor, {
    required int start,
    required String value,
    bool usePlaceholderNoMatchSemantics = false,
  }) {
    final regex = _readTransformSection(cursor, start: start);
    final format = _readTransformSection(
      regex.endOffset,
      start: start,
      formatSection: true,
    );
    cursor = format.endOffset;
    final options = StringBuffer();
    while (cursor < _units.length && _units[cursor] != _closeBrace) {
      options.writeCharCode(_units[cursor]);
      cursor++;
    }
    if (cursor >= _units.length) {
      throw SnippetTemplateException('unterminated variable transform', start);
    }
    return _ParsedVariableTransform(
      SnippetVariableTransform(
        value: value,
        pattern: regex.value,
        format: format.value,
        options: options.toString(),
        offsetUtf16: start,
        applyFormatWhenNoMatch: usePlaceholderNoMatchSemantics &&
            snippetTransformHasElseBranch(format.value),
      ),
      cursor + 1,
    );
  }

  _ParsedTransformSection _readTransformSection(
    int cursor, {
    required int start,
    bool formatSection = false,
  }) {
    final value = StringBuffer();
    var formatExpressionDepth = 0;
    while (cursor < _units.length) {
      final unit = _units[cursor];
      if (formatSection &&
          unit == _dollar &&
          cursor + 1 < _units.length &&
          _units[cursor + 1] == _openBrace) {
        formatExpressionDepth++;
        value.writeCharCode(unit);
        value.writeCharCode(_units[cursor + 1]);
        cursor += 2;
        continue;
      }
      if (unit == _slash && formatExpressionDepth == 0) {
        return _ParsedTransformSection(value.toString(), cursor + 1);
      }
      if (unit == _backslash && cursor + 1 < _units.length) {
        final escaped = _units[cursor + 1];
        if (escaped == _slash || escaped == _backslash) {
          value.writeCharCode(escaped);
          cursor += 2;
          continue;
        }
        if (formatSection && (escaped == _dollar || escaped == _closeBrace)) {
          value
            ..writeCharCode(unit)
            ..writeCharCode(escaped);
          cursor += 2;
          continue;
        }
      }
      if (formatSection && unit == _closeBrace && formatExpressionDepth > 0) {
        formatExpressionDepth--;
      }
      value.writeCharCode(unit);
      cursor++;
    }
    throw SnippetTemplateException('unterminated variable transform', start);
  }

  bool _isVariableStart(int unit) =>
      (unit >= 0x41 && unit <= 0x5a) ||
      (unit >= 0x61 && unit <= 0x7a) ||
      unit == 0x5f;

  bool _isVariablePart(int unit) => _isVariableStart(unit) || _isDigit(unit);

  bool _isDigit(int unit) => unit >= _zero && unit <= _nine;

  SnippetExpansion _render(List<_SnippetSegment> segments) {
    final defaults = <int, List<_SnippetSegment>>{};
    void collectDefaults(List<_SnippetSegment> children) {
      for (final segment in children) {
        final transform = segment.variableTransform;
        if (transform != null) {
          throw SnippetTemplateException(
            'unresolved snippet variable transform',
            transform.offsetUtf16,
          );
        }
        final index = segment.index;
        final value = segment.defaultSegments;
        if (index != null && index != 0 && value != null && value.isNotEmpty) {
          defaults.putIfAbsent(index, () => value);
        }
        if (value != null) collectDefaults(value);
      }
    }

    collectDefaults(segments);

    final output = StringBuffer();
    final placeholders = <SnippetPlaceholderRange>[];
    var outputOffset = 0;
    var nextOccurrenceId = 1;
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

    void renderSegments(
      List<_SnippetSegment> children, {
      List<int> ancestors = const [],
      Set<int> expandingDefaults = const {},
    }) {
      for (final segment in children) {
        final index = segment.index;
        if (index == null) {
          append(segment.text!);
          continue;
        }

        if (placeholders.length >= maxPlaceholderOccurrences) {
          throw SnippetTemplateException(
            'rendered placeholder count exceeds the limit',
            _offset,
          );
        }
        final start = outputOffset;
        final ownDefault = segment.defaultSegments;
        final selectedDefault = index == 0 || expandingDefaults.contains(index)
            ? ownDefault ?? const <_SnippetSegment>[]
            : defaults[index] ?? ownDefault ?? const <_SnippetSegment>[];
        final occurrenceId = nextOccurrenceId++;
        renderSegments(
          selectedDefault,
          ancestors: [...ancestors, occurrenceId],
          expandingDefaults: {...expandingDefaults, index},
        );
        placeholders.add(SnippetPlaceholderRange(
          index: index,
          startUtf16: start,
          endUtf16: outputOffset,
          choice: segment.choice,
          occurrenceId: occurrenceId,
          ancestorOccurrenceIds: List.unmodifiable(ancestors),
          transform: segment.transform,
        ));
      }
    }

    renderSegments(segments);
    placeholders.sort((left, right) {
      final byStart = left.startUtf16.compareTo(right.startUtf16);
      if (byStart != 0) return byStart;
      return right.endUtf16.compareTo(left.endUtf16);
    });
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

class _ParsedSnippetChoice {
  const _ParsedSnippetChoice(this.choice, this.endOffset);

  final SnippetChoice choice;
  final int endOffset;
}

class _ParsedTransformSection {
  const _ParsedTransformSection(this.value, this.endOffset);

  final String value;
  final int endOffset;
}

class _ParsedVariableTransform {
  const _ParsedVariableTransform(this.transform, this.endOffset);

  final SnippetVariableTransform transform;
  final int endOffset;
}
