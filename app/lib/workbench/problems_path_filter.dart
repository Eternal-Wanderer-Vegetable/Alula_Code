import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

enum ProblemsPathMatch { neutral, included, excluded }

/// File patterns in the Problems query, compiled once for all open documents.
final class ProblemsPathFilter {
  ProblemsPathFilter(String query) {
    for (final token in _splitPatterns(query)) {
      final pattern = token.trim();
      final excluded = pattern.startsWith('!');
      final target = excluded ? _excludes : _includes;
      final value = (excluded ? pattern.replaceFirst(_negation, '') : pattern)
          .replaceFirst(_leadingSlash, '');
      if (value.isEmpty) continue;
      final suffix = value.startsWith('.') ? '*$value' : value;
      try {
        target.add(Glob(
          '**/$suffix',
          context: p.posix,
          recursive: true,
          caseSensitive: true,
        ));
      } on FormatException {
        // Malformed glob syntax can still be used in a plain text query.
      }
    }
  }

  static final _negation = RegExp(r'^!+');
  static final _leadingSlash = RegExp(r'^/+');
  final List<Glob> _includes = [];
  final List<Glob> _excludes = [];

  bool get isEmpty => _includes.isEmpty && _excludes.isEmpty;

  ProblemsPathMatch match(String filePath) {
    final path = filePath.replaceAll('\\', '/').replaceFirst(_leadingSlash, '');
    for (final glob in _excludes) {
      if (glob.matches(path)) return ProblemsPathMatch.excluded;
    }
    for (final glob in _includes) {
      if (glob.matches(path)) return ProblemsPathMatch.included;
    }
    return ProblemsPathMatch.neutral;
  }

  static Iterable<String> _splitPatterns(String query) sync* {
    var start = 0;
    var inBraces = false;
    var inBrackets = false;
    for (var i = 0; i < query.length; i++) {
      switch (query[i]) {
        case '{':
          inBraces = true;
        case '}':
          inBraces = false;
        case '[':
          inBrackets = true;
        case ']':
          inBrackets = false;
        case ',' when !inBraces && !inBrackets:
          yield query.substring(start, i);
          start = i + 1;
      }
    }
    yield query.substring(start);
  }
}
