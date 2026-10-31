import 'package:flutter/foundation.dart';

/// Workbench context values used to decide whether commands are visible or
/// enabled. Expressions support identifiers, `!`, `&&`, `||`, `==`, `!=`, and
/// parentheses. Invalid expressions fail closed.
class ContextKeyService extends ChangeNotifier {
  final Map<String, Object?> _values = {};

  Object? operator [](String key) => _values[key];

  void setValue(String key, Object? value) {
    if (_values.containsKey(key) && _values[key] == value) return;
    _values[key] = value;
    notifyListeners();
  }

  void setValues(Map<String, Object?> values) {
    var changed = false;
    for (final entry in values.entries) {
      if (!_values.containsKey(entry.key) ||
          _values[entry.key] != entry.value) {
        _values[entry.key] = entry.value;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  bool matches(String? expression) {
    if (expression == null || expression.trim().isEmpty) return true;
    try {
      final parser = _ContextExpressionParser(expression, this);
      final result = parser.parse();
      return result == true && parser.isAtEnd;
    } on FormatException {
      return false;
    }
  }

  @override
  void dispose() {
    _values.clear();
    super.dispose();
  }
}

class _ContextExpressionParser {
  _ContextExpressionParser(String source, this.context)
      : _tokens = _tokenize(source);

  final ContextKeyService context;
  final List<String> _tokens;
  int _position = 0;

  bool get isAtEnd => _position == _tokens.length;

  Object? parse() {
    final value = _parseOr();
    if (!isAtEnd) throw const FormatException('Unexpected token');
    return value;
  }

  Object? _parseOr() {
    var value = _parseAnd();
    while (_match('||')) {
      final right = _parseAnd();
      value = _truthy(value) || _truthy(right);
    }
    return value;
  }

  Object? _parseAnd() {
    var value = _parseUnary();
    while (_match('&&')) {
      final right = _parseUnary();
      value = _truthy(value) && _truthy(right);
    }
    return value;
  }

  Object? _parseUnary() {
    if (_match('!')) return !_truthy(_parseUnary());
    if (_match('(')) {
      final value = _parseOr();
      if (!_match(')')) throw const FormatException('Missing )');
      return value;
    }
    final left = _parseValue();
    if (_match('==')) return left == _parseValue();
    if (_match('!=')) return left != _parseValue();
    return left;
  }

  Object? _parseValue() {
    if (isAtEnd) throw const FormatException('Missing value');
    final token = _tokens[_position++];
    if (token.startsWith('"')) {
      return token.substring(1, token.length - 1);
    }
    if (token == 'true') return true;
    if (token == 'false') return false;
    if (token == 'null') return null;
    if (RegExp(r'^\d+$').hasMatch(token)) return int.parse(token);
    if (const {'&&', '||', '==', '!=', ')', '('}.contains(token)) {
      throw const FormatException('Expected value');
    }
    return context[token];
  }

  bool _match(String token) {
    if (isAtEnd || _tokens[_position] != token) return false;
    _position++;
    return true;
  }

  static bool _truthy(Object? value) => switch (value) {
        null => false,
        bool b => b,
        num n => n != 0,
        String s => s.isNotEmpty,
        _ => true,
      };

  static List<String> _tokenize(String source) {
    source = source.trim();
    final tokens = <String>[];
    final matcher = RegExp(
      r'\s*(\&\&|\|\||==|!=|[!()]|"(?:\\.|[^"\\])*"|[A-Za-z_][A-Za-z0-9_.-]*|\d+)',
    );
    var offset = 0;
    while (offset < source.length) {
      final match = matcher.matchAsPrefix(source, offset);
      if (match == null) throw const FormatException('Invalid expression');
      tokens.add(match.group(1)!);
      offset = match.end;
    }
    return tokens;
  }
}
