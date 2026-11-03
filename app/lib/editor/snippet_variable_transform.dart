import 'dart:async';
import 'dart:isolate';

/// One variable transform captured while parsing a TextMate snippet.
class SnippetVariableTransform {
  const SnippetVariableTransform({
    required this.value,
    required this.pattern,
    required this.format,
    required this.options,
    required this.offsetUtf16,
  });

  final String value;
  final String pattern;
  final String format;
  final String options;
  final int offsetUtf16;
}

class SnippetVariableTransformException implements Exception {
  const SnippetVariableTransformException(this.message, this.offsetUtf16);

  final String message;
  final int offsetUtf16;

  @override
  String toString() =>
      'SnippetVariableTransformException($message at UTF-16 $offsetUtf16)';
}

const int maxSnippetVariableTransforms = 64;
const int maxSnippetVariableTransformPatternUtf16 = 512;
const int maxSnippetVariableTransformFormatUtf16 = 512;
const int maxSnippetVariableTransformInputUtf16 = 256 * 1024;
const int maxSnippetVariableTransformOutputUtf16 = 256 * 1024;
const Duration snippetVariableTransformTimeout = Duration(milliseconds: 750);

/// Evaluates snippet transforms in a short-lived isolate so a pathological
/// user snippet regex cannot block the workbench's UI isolate.
Future<List<String>> applySnippetVariableTransforms(
  List<SnippetVariableTransform> transforms,
) async {
  if (transforms.isEmpty) return const [];
  if (transforms.length > maxSnippetVariableTransforms) {
    throw SnippetVariableTransformException(
      'snippet transform count exceeds the limit',
      transforms[maxSnippetVariableTransforms].offsetUtf16,
    );
  }

  var totalInputUtf16 = 0;
  for (final transform in transforms) {
    if (transform.pattern.length > maxSnippetVariableTransformPatternUtf16 ||
        transform.format.length > maxSnippetVariableTransformFormatUtf16) {
      throw SnippetVariableTransformException(
        'snippet transform expression exceeds the size limit',
        transform.offsetUtf16,
      );
    }
    totalInputUtf16 += transform.value.length;
    if (totalInputUtf16 > maxSnippetVariableTransformInputUtf16) {
      throw SnippetVariableTransformException(
        'snippet transform input exceeds the size limit',
        transform.offsetUtf16,
      );
    }
  }

  final replyPort = ReceivePort();
  Isolate? worker;
  try {
    worker = await Isolate.spawn<List<Object?>>(
      _snippetVariableTransformWorker,
      <Object?>[
        replyPort.sendPort,
        <Map<String, Object?>>[
          for (final transform in transforms)
            <String, Object?>{
              'value': transform.value,
              'pattern': transform.pattern,
              'format': transform.format,
              'options': transform.options,
            },
        ],
      ],
      errorsAreFatal: true,
    );
    final response = await replyPort.first.timeout(
      snippetVariableTransformTimeout,
      onTimeout: () => throw TimeoutException(
        'snippet transform execution timed out',
      ),
    );
    if (response is! Map<Object?, Object?> || response['ok'] != true) {
      final index = response is Map<Object?, Object?>
          ? response['index'] as int? ?? 0
          : 0;
      final message = response is Map<Object?, Object?>
          ? response['error'] as String? ?? 'snippet transform failed'
          : 'snippet transform worker returned an invalid response';
      final safeIndex = index.clamp(0, transforms.length - 1).toInt();
      throw SnippetVariableTransformException(
        message,
        transforms[safeIndex].offsetUtf16,
      );
    }
    final values = response['values'];
    if (values is! List<Object?> || values.length != transforms.length) {
      throw SnippetVariableTransformException(
        'snippet transform worker returned an invalid response',
        transforms.first.offsetUtf16,
      );
    }
    return [
      for (final value in values)
        if (value is String) value else ''
    ];
  } on TimeoutException {
    throw SnippetVariableTransformException(
      'snippet transform execution timed out',
      transforms.first.offsetUtf16,
    );
  } catch (error) {
    if (error is SnippetVariableTransformException) rethrow;
    throw SnippetVariableTransformException(
      'snippet transform failed: $error',
      transforms.first.offsetUtf16,
    );
  } finally {
    worker?.kill(priority: Isolate.immediate);
    replyPort.close();
  }
}

void _snippetVariableTransformWorker(List<Object?> message) {
  final replyPort = message.first as SendPort;
  final jobs = message[1] as List<Object?>;
  final results = <String>[];
  var outputUtf16 = 0;
  for (var index = 0; index < jobs.length; index++) {
    try {
      final job = Map<String, Object?>.from(jobs[index]! as Map);
      final value = _replaceSnippetTransform(
        value: job['value']! as String,
        pattern: job['pattern']! as String,
        format: job['format']! as String,
        options: job['options']! as String,
      );
      outputUtf16 += value.length;
      if (outputUtf16 > maxSnippetVariableTransformOutputUtf16) {
        replyPort.send(<String, Object?>{
          'ok': false,
          'index': index,
          'error': 'snippet transform output exceeds the size limit',
        });
        return;
      }
      results.add(value);
    } catch (error) {
      replyPort.send(<String, Object?>{
        'ok': false,
        'index': index,
        'error': 'invalid snippet transform: $error',
      });
      return;
    }
  }
  replyPort.send(<String, Object?>{'ok': true, 'values': results});
}

String _replaceSnippetTransform({
  required String value,
  required String pattern,
  required String format,
  required String options,
}) {
  final seenOptions = <String>{};
  for (final optionUnit in options.codeUnits) {
    final option = String.fromCharCode(optionUnit);
    if (!'gimsu'.contains(option) || !seenOptions.add(option)) {
      throw FormatException('unsupported or duplicate regex option "$option"');
    }
  }
  final regex = RegExp(
    pattern,
    caseSensitive: !seenOptions.contains('i'),
    multiLine: seenOptions.contains('m'),
    dotAll: seenOptions.contains('s'),
    unicode: seenOptions.contains('u'),
  );

  final first = regex.firstMatch(value);
  if (first == null) return value;
  final matches = seenOptions.contains('g')
      ? regex.allMatches(value)
      : <RegExpMatch>[first];

  final output = StringBuffer();
  void append(String text) {
    if (output.length + text.length > maxSnippetVariableTransformOutputUtf16) {
      throw const FormatException('snippet transform output exceeds the limit');
    }
    output.write(text);
  }

  var cursor = 0;
  for (final match in matches) {
    if (match.start < cursor) continue;
    append(value.substring(cursor, match.start));
    append(_formatSnippetReplacement(
      format,
      match,
      maxOutputUtf16: maxSnippetVariableTransformOutputUtf16 - output.length,
    ));
    cursor = match.end;
  }
  append(value.substring(cursor));
  return output.toString();
}

String _formatSnippetReplacement(
  String format,
  RegExpMatch match, {
  required int maxOutputUtf16,
}) {
  final units = format.codeUnits;
  final output = StringBuffer();
  void append(String text) {
    if (output.length + text.length > maxOutputUtf16) {
      throw const FormatException('snippet transform output exceeds the limit');
    }
    output.write(text);
  }

  void appendCharCode(int value) {
    if (output.length >= maxOutputUtf16) {
      throw const FormatException('snippet transform output exceeds the limit');
    }
    output.writeCharCode(value);
  }

  var offset = 0;
  while (offset < units.length) {
    final unit = units[offset];
    if (unit == 0x5c && offset + 1 < units.length) {
      final escaped = units[offset + 1];
      if (escaped == 0x24 ||
          escaped == 0x7d ||
          escaped == 0x5c ||
          escaped == 0x2f) {
        appendCharCode(escaped);
        offset += 2;
        continue;
      }
    }
    if (unit != 0x24 || offset + 1 >= units.length) {
      appendCharCode(unit);
      offset++;
      continue;
    }
    var cursor = offset + 1;
    if (units[cursor] >= 0x30 && units[cursor] <= 0x39) {
      final groupStart = cursor;
      while (cursor < units.length &&
          units[cursor] >= 0x30 &&
          units[cursor] <= 0x39) {
        cursor++;
      }
      final group =
          int.parse(String.fromCharCodes(units.sublist(groupStart, cursor)));
      append(_snippetCapture(match, group) ?? '');
      offset = cursor;
      continue;
    }
    if (units[cursor] == 0x7b) {
      final close = _findFormatClose(units, cursor + 1);
      if (close >= 0) {
        final expression =
            String.fromCharCodes(units.sublist(cursor + 1, close));
        append(_formatSnippetExpression(
          expression,
          match,
          maxOutputUtf16: maxOutputUtf16 - output.length,
        ));
        offset = close + 1;
        continue;
      }
    }
    appendCharCode(unit);
    offset++;
  }
  return output.toString();
}

int _findFormatClose(List<int> units, int start) {
  for (var index = start; index < units.length; index++) {
    if (units[index] == 0x5c) {
      index++;
      continue;
    }
    if (units[index] == 0x7d) return index;
  }
  return -1;
}

String _formatSnippetExpression(
  String expression,
  RegExpMatch match, {
  required int maxOutputUtf16,
}) {
  String bounded(String value) {
    if (value.length > maxOutputUtf16) {
      throw const FormatException('snippet transform output exceeds the limit');
    }
    return value;
  }

  var cursor = 0;
  while (cursor < expression.length &&
      expression.codeUnitAt(cursor) >= 0x30 &&
      expression.codeUnitAt(cursor) <= 0x39) {
    cursor++;
  }
  if (cursor == 0) throw const FormatException('missing capture group index');
  final group = int.parse(expression.substring(0, cursor));
  final capture = _snippetCapture(match, group);
  if (cursor == expression.length) return bounded(capture ?? '');

  final suffix = expression.substring(cursor);
  if (suffix.startsWith(':/')) {
    if (capture == null) return '';
    return bounded(_applySnippetCaseFormat(capture, suffix.substring(2)));
  }
  if (suffix.startsWith(':+')) {
    return bounded(
      capture == null ? '' : _unescapeSnippetFormat(suffix.substring(2)),
    );
  }
  if (suffix.startsWith(':-')) {
    return bounded(capture ?? _unescapeSnippetFormat(suffix.substring(2)));
  }
  if (suffix.startsWith(':?')) {
    final branches = _splitSnippetConditional(suffix.substring(2));
    return bounded(
      _unescapeSnippetFormat(capture == null ? branches.$2 : branches.$1),
    );
  }
  if (suffix.startsWith(':')) {
    return bounded(capture ?? _unescapeSnippetFormat(suffix.substring(1)));
  }
  throw const FormatException('unsupported capture group format');
}

String? _snippetCapture(RegExpMatch match, int group) {
  if (group < 0 || group > match.groupCount) return null;
  return match.group(group);
}

(String, String) _splitSnippetConditional(String value) {
  for (var index = 0; index < value.length; index++) {
    if (value.codeUnitAt(index) == 0x5c) {
      index++;
      continue;
    }
    if (value.codeUnitAt(index) == 0x3a) {
      return (value.substring(0, index), value.substring(index + 1));
    }
  }
  throw const FormatException('conditional format requires both branches');
}

String _unescapeSnippetFormat(String value) {
  final output = StringBuffer();
  for (var index = 0; index < value.length; index++) {
    final unit = value.codeUnitAt(index);
    if (unit == 0x5c && index + 1 < value.length) {
      final next = value.codeUnitAt(index + 1);
      if (next == 0x5c || next == 0x24 || next == 0x7d || next == 0x2f) {
        output.writeCharCode(next);
        index++;
        continue;
      }
    }
    output.writeCharCode(unit);
  }
  return output.toString();
}

String _applySnippetCaseFormat(String value, String operation) {
  switch (operation) {
    case 'upcase':
      return value.toUpperCase();
    case 'downcase':
      return value.toLowerCase();
    case 'capitalize':
      if (value.isEmpty) return value;
      final runes = value.runes.toList(growable: false);
      return String.fromCharCode(runes.first).toUpperCase() +
          String.fromCharCodes(runes.skip(1));
    case 'camelcase':
      return _joinSnippetWords(value, separator: '', upperFirst: false);
    case 'pascalcase':
      return _joinSnippetWords(value, separator: '', upperFirst: true);
    case 'kebabcase':
      return _joinSnippetWords(value, separator: '-', upperFirst: false);
    case 'snakecase':
      return _joinSnippetWords(value, separator: '_', upperFirst: false);
    default:
      throw FormatException('unsupported case format "$operation"');
  }
}

String _joinSnippetWords(
  String value, {
  required String separator,
  required bool upperFirst,
}) {
  final runes = value.runes.toList(growable: false);
  final words = <String>[];
  var word = <int>[];
  void flushWord() {
    if (word.isEmpty) return;
    words.add(String.fromCharCodes(word));
    word = <int>[];
  }

  for (var index = 0; index < runes.length; index++) {
    final current = runes[index];
    final currentText = String.fromCharCode(current);
    if (!_isSnippetWordRune(currentText)) {
      flushWord();
      continue;
    }
    if (word.isNotEmpty) {
      final previousText = String.fromCharCode(word.last);
      final nextText =
          index + 1 < runes.length ? String.fromCharCode(runes[index + 1]) : '';
      final lowerToUpper =
          _isSnippetLower(previousText) && _isSnippetUpper(currentText);
      final acronymEnd = _isSnippetUpper(previousText) &&
          _isSnippetUpper(currentText) &&
          nextText.isNotEmpty &&
          _isSnippetLower(nextText);
      if (lowerToUpper || acronymEnd) flushWord();
    }
    word.add(current);
  }
  flushWord();

  final normalized = [for (final part in words) part.toLowerCase()];
  if (normalized.isEmpty) return '';
  if (separator.isNotEmpty) return normalized.join(separator);
  final output = StringBuffer();
  for (var index = 0; index < normalized.length; index++) {
    final part = normalized[index];
    if (index == 0 && !upperFirst) {
      output.write(part);
    } else {
      final runes = part.runes.toList(growable: false);
      if (runes.isNotEmpty) {
        output.write(String.fromCharCode(runes.first).toUpperCase());
        output.write(String.fromCharCodes(runes.skip(1)));
      }
    }
  }
  return output.toString();
}

bool _isSnippetWordRune(String value) => _snippetAlphanumeric.hasMatch(value);

bool _isSnippetUpper(String value) =>
    value.toUpperCase() == value && value.toLowerCase() != value;

bool _isSnippetLower(String value) =>
    value.toLowerCase() == value && value.toUpperCase() != value;

final RegExp _snippetAlphanumeric = RegExp(r'^[\p{L}\p{N}]$', unicode: true);
