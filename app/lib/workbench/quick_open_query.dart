import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show TextRange;

import 'package:path/path.dart' as p;

import 'tree_fuzzy_score.dart';

/// A file query with an optional one-based position or selection.
class QuickOpenQuery {
  const QuickOpenQuery(
    this.pathQuery, {
    this.line,
    this.column,
    this.endLine,
    this.endColumn,
  });

  final String pathQuery;
  final int? line;
  final int? column;
  final int? endLine;
  final int? endColumn;
}

final _fileLocationSuffix = RegExp(
  r'\s?[#:(](?:line )?([0-9]*)(?:[#:,]([0-9]*))?'
  r'(?:-([0-9]*)(?:[#:,]([0-9]*))?)?\)?:?$',
);

/// Parses a Quick Open file position, preserving a Windows drive colon.
QuickOpenQuery parseQuickOpenQuery(String input) {
  final text = input.trim();
  final match = _fileLocationSuffix.firstMatch(text);
  if (match == null ||
      (match.start == 1 && RegExp(r'^[a-zA-Z]:').hasMatch(text))) {
    return QuickOpenQuery(text);
  }

  final lineText = match[1]!;
  final columnText = match[2] ?? '';
  final endLineText = match[3] ?? '';
  final endColumnText = match[4] ?? '';
  if (lineText.isEmpty) {
    if (match[3] != null) return QuickOpenQuery(text);
    return QuickOpenQuery(text.substring(0, match.start), line: 1);
  }

  final line = int.tryParse(lineText);
  final column = int.tryParse(columnText);
  final endLine = int.tryParse(endLineText);
  final endColumn = int.tryParse(endColumnText);
  if (line == null ||
      (columnText.isNotEmpty && column == null) ||
      (endLineText.isNotEmpty && endLine == null) ||
      (endColumnText.isNotEmpty && endColumn == null)) {
    return QuickOpenQuery(text);
  }

  int? oneBased(int? coordinate) => coordinate == 0 ? 1 : coordinate;
  return QuickOpenQuery(
    text.substring(0, match.start),
    line: oneBased(line),
    column: oneBased(column),
    endLine: oneBased(endLine),
    endColumn: endLine == null ? null : oneBased(endColumn),
  );
}

/// The parent directory shown beside a Quick Open file result.
String? quickOpenDirectoryLabel(
  String path, {
  String? workspace,
  String? userHome,
}) {
  final directory = p.normalize(p.dirname(p.absolute(path)));
  final comparedDirectory =
      Platform.isMacOS ? directory.toLowerCase() : directory;

  String? relativeDirectory(String root) {
    final parent = p.normalize(p.absolute(root));
    final comparedRoot = Platform.isMacOS ? parent.toLowerCase() : parent;
    if (p.equals(comparedRoot, comparedDirectory)) return '';
    if (!p.isWithin(comparedRoot, comparedDirectory)) return null;
    return p.joinAll(p.split(directory).skip(p.split(parent).length));
  }

  if (workspace != null) {
    final relative = relativeDirectory(workspace);
    if (relative != null) return relative.isEmpty ? null : relative;
  }
  if (!Platform.isWindows && userHome != null && userHome.isNotEmpty) {
    final relative = relativeDirectory(userHome);
    if (relative != null && relative.isNotEmpty) return p.join('~', relative);
  }
  if (Platform.isWindows && directory.length > 1 && directory[1] == ':') {
    return '${directory[0].toUpperCase()}${directory.substring(1)}';
  }
  return directory;
}

/// Highlight ranges for the visible columns of Quick Open file rows.
class QuickOpenFileHighlighter {
  QuickOpenFileHighlighter(String pathQuery)
      : _pattern = QuickOpenSearch._native(pathQuery) {
    _terms =
        _pattern == '.' ? const [] : QuickOpenSearch._prepareTerms(_pattern);
  }

  final String _pattern;
  late final List<_QuickOpenTerm> _terms;

  ({List<TextRange> label, List<TextRange> description}) find({
    required String path,
    required String label,
    required String? description,
  }) {
    if (p.isAbsolute(_pattern) && p.equals(p.normalize(_pattern), path)) {
      return (
        label: [TextRange(start: 0, end: label.length)],
        description: description == null
            ? const []
            : [TextRange(start: 0, end: description.length)],
      );
    }

    final preferLabel = !_pattern.contains(p.separator);
    final labelMatches = <TextRange>[];
    final descriptionMatches = <TextRange>[];
    final directory = description ?? '';
    final prefix = directory.isEmpty || directory.endsWith(p.separator)
        ? directory
        : '$directory${p.separator}';
    final fullLabel = '$prefix$label';
    for (final term in _terms) {
      if (preferLabel || prefix.isEmpty) {
        final matches = _matches(term, label);
        if (matches != null) {
          labelMatches.addAll(matches);
          continue;
        }
      }
      if (prefix.isEmpty) continue;
      final matches = _matches(term, fullLabel);
      if (matches == null) continue;
      for (final match in matches) {
        if (match.start < directory.length) {
          descriptionMatches.add(TextRange(
            start: match.start,
            end: math.min(match.end, directory.length),
          ));
        }
        if (match.end > prefix.length) {
          labelMatches.add(TextRange(
            start: math.max(0, match.start - prefix.length),
            end: match.end - prefix.length,
          ));
        }
      }
    }
    return (
      label: _mergeRanges(label, labelMatches),
      description: _mergeRanges(directory, descriptionMatches),
    );
  }

  static List<TextRange>? _matches(_QuickOpenTerm term, String value) {
    final exact = term.exactLowercase;
    if (exact != null) {
      final start = value.toLowerCase().indexOf(exact);
      if (start < 0) return null;
      return [TextRange(start: start, end: start + exact.length)];
    }
    final matches = treeFuzzyScore(term.text, value)?.matches;
    return matches
        ?.map((range) => TextRange(
              start: _sourceOffset(value, range.start, end: false),
              end: _sourceOffset(value, range.end, end: true),
            ))
        .toList();
  }

  // The fuzzy scorer uses JavaScript folding. A dotted capital I occupies
  // two units after folding and both units refer to the same original letter.
  static int _sourceOffset(String value, int offset, {required bool end}) {
    var expanded = 0;
    for (var i = value.indexOf('\u0130');
        i >= 0 && i + expanded < offset;
        i = value.indexOf('\u0130', i + 1)) {
      if (end && i + expanded + 1 == offset) break;
      expanded++;
    }
    return offset - expanded;
  }

  static List<TextRange> _mergeRanges(String value, List<TextRange> matches) {
    if (matches.isEmpty) return const [];
    matches.sort((a, b) => a.start.compareTo(b.start));
    final ranges = <TextRange>[];
    for (final match in matches) {
      // The scorer can stop between the two code units of a character at
      // its scoring limit. Keep the whole character in a single text span.
      final start =
          _splitsSurrogate(value, match.start) ? match.start - 1 : match.start;
      final end =
          _splitsSurrogate(value, match.end) ? match.end + 1 : match.end;
      if (ranges.isNotEmpty && start <= ranges.last.end) {
        ranges[ranges.length - 1] = TextRange(
          start: ranges.last.start,
          end: math.max(ranges.last.end, end),
        );
      } else {
        ranges.add(TextRange(start: start, end: end));
      }
    }
    return ranges;
  }

  static bool _splitsSurrogate(String value, int offset) =>
      offset > 0 &&
      offset < value.length &&
      (value.codeUnitAt(offset - 1) & 0xfc00) == 0xd800 &&
      (value.codeUnitAt(offset) & 0xfc00) == 0xdc00;
}

typedef QuickOpenMatch = ({String path, bool recent});

typedef _QuickOpenTerm = ({String text, String? exactLowercase});

/// Asynchronous Quick Open search with bounded result storage and no index.
///
/// Pages partition matching files in discovery order (MRU, direct path, then
/// directory traversal); filesystem matches within a page are fuzzy-ranked.
/// Each call rescans to its page, so later pages never require retaining all
/// earlier paths. Stable filesystem contents and recentPaths give stable pages.
/// Links are not traversed, and `.git` directories are excluded before descent.
/// Filesystem failures and the 128-directory depth limit are explicit errors.
/// Cancelled or superseded calls complete with an empty list, including when an
/// outstanding filesystem operation subsequently fails.
class QuickOpenSearch {
  static const pageSize = 200;
  static const maxDirectoryDepth = 128;
  static final _scoringMarkers = RegExp(r'[*…\s"]');

  int _generation = 0;
  bool hasMore = false;

  void cancel() => _generation++;

  Future<List<String>> search(String root, String query,
      {List<String> recentPaths = const [], int page = 0}) async {
    final matches = await searchMatches(
      root,
      query,
      recentPaths: recentPaths,
      page: page,
    );
    return [for (final match in matches) match.path];
  }

  Future<List<QuickOpenMatch>> searchMatches(
    String root,
    String query, {
    List<String> recentPaths = const [],
    int page = 0,
    bool includeFileResults = true,
    Set<String> excludedPaths = const {},
    void Function(List<QuickOpenMatch>)? onRecentMatches,
  }) async {
    if (page < 0) {
      throw ArgumentError.value(page, 'page', 'Must be nonnegative');
    }
    final generation = ++_generation;
    hasMore = false;
    bool current() => generation == _generation;
    final rootPath = p.normalize(p.absolute(_native(root)));
    final pathQuery = _native(parseQuickOpenQuery(query).pathQuery);
    final pattern = pathQuery == '.' ? '' : pathQuery;
    final terms = _prepareTerms(pattern);
    final allowScoredMatches = pattern.isEmpty || terms.isNotEmpty;
    final recentKeys = {
      for (final path in excludedPaths) _key(p.normalize(_native(path))),
    };
    final results = <({QuickOpenMatch match, int? score})>[];
    var skip = page * pageSize;

    bool add(String path, int? score, {bool recent = false}) {
      if (skip > 0) {
        skip--;
      } else if (results.length < pageSize) {
        results.add((match: (path: path, recent: recent), score: score));
      } else {
        hasMore = true;
        return true;
      }
      return false;
    }

    List<QuickOpenMatch> finish() {
      if (!current()) return [];
      // MRU and exact paths retain priority and input order. Sorting only the
      // bounded filesystem page leaves every matching file reachable by paging.
      final preferred = results.where((entry) => entry.score == null);
      final ranked = results.where((entry) => entry.score != null).toList()
        ..sort((a, b) {
          final score = b.score!.compareTo(a.score!);
          return score != 0 ? score : a.match.path.compareTo(b.match.path);
        });
      return [...preferred, ...ranked].map((entry) => entry.match).toList();
    }

    try {
      // Resolve exact paths before traversing the workspace, including paths
      // outside it. All returned paths are normalized, native and absolute.
      final directPath = !includeFileResults || pattern.isEmpty
          ? null
          : p.normalize(
              p.isAbsolute(pattern) ? pattern : p.join(rootPath, pattern));
      for (final recent in recentPaths) {
        if (!current()) return [];
        final native = _native(recent);
        final path = p.normalize(
            p.isAbsolute(native) ? native : p.join(rootPath, native));
        final key = _key(path);
        if (!recentKeys.add(key)) continue;
        if (key != (directPath == null ? null : _key(directPath)) &&
            (!allowScoredMatches || _score(terms, path, rootPath) == null)) {
          continue;
        }
        final exists = await File(path).exists();
        if (!current()) return [];
        if (exists && add(path, null, recent: true)) return finish();
      }

      if (!includeFileResults) return finish();
      if (results.isNotEmpty && current()) onRecentMatches?.call(finish());

      final directExists =
          directPath != null && await File(directPath).exists();
      if (!current()) return [];

      final directKey = directPath == null ? null : _key(directPath);
      if (directExists && !recentKeys.contains(directKey)) {
        if (add(directPath, null)) return finish();
      }
      // Absolute queries resolve directly; they need not open the workspace.
      if (!allowScoredMatches || p.isAbsolute(pattern)) return finish();

      await for (final path in _walk(rootPath, 0, generation)) {
        if (!current()) return [];
        final key = _key(path);
        if (recentKeys.contains(key) || (directExists && key == directKey)) {
          continue;
        }
        final score = _score(terms, path, rootPath);
        if (score != null && add(path, score)) return finish();
      }
      return finish();
    } catch (_) {
      if (!current()) return [];
      rethrow;
    }
  }

  Stream<String> _walk(String directory, int depth, int generation) async* {
    if (generation != _generation) return;
    if (depth > maxDirectoryDepth) {
      throw FileSystemException(
          'Quick Open directory depth exceeds $maxDirectoryDepth', directory);
    }
    await for (final entity in Directory(directory).list(followLinks: false)) {
      if (generation != _generation) return;
      if (entity is Directory) {
        if (p.basename(entity.path) == '.git') continue;
        yield* _walk(entity.path, depth + 1, generation);
      } else if (entity is File) {
        yield p.normalize(entity.path);
      }
    }
  }

  static String _native(String path) =>
      path.replaceAll('\\', p.separator).replaceAll('/', p.separator);

  static String _key(String path) =>
      Platform.isWindows ? path.toLowerCase() : path;

  static bool _isQuoted(String value) =>
      value.length > 1 && value.startsWith('"') && value.endsWith('"');

  static List<_QuickOpenTerm> _prepareTerms(String pattern) {
    final terms = <_QuickOpenTerm>[];
    for (final part in pattern.split(' ')) {
      var text = part.replaceAll(_scoringMarkers, '');
      if (text.length > 1 && text.endsWith('#')) {
        text = text.substring(0, text.length - 1);
      }
      if (text.isEmpty) continue;
      terms.add((
        text: text,
        exactLowercase: _isQuoted(part) ? text.toLowerCase() : null,
      ));
    }
    if (terms.length == 1 &&
        terms.single.exactLowercase == null &&
        _isQuoted(pattern)) {
      final text = terms.single.text;
      terms[0] = (text: text, exactLowercase: text.toLowerCase());
    }
    return terms;
  }

  static int? _scoreTerm(_QuickOpenTerm term, String candidate) {
    final exact = term.exactLowercase;
    if (exact != null && !candidate.toLowerCase().contains(exact)) return null;
    final score = treeFuzzyScore(term.text, candidate)?.score;
    // The substring check also covers matches past the fuzzy score's window.
    return score ?? (exact == null ? null : 0);
  }

  static int? _score(List<_QuickOpenTerm> terms, String path, String root) {
    if (terms.isEmpty) return 0;
    final name = p.basename(path);
    final relative = p.relative(path, from: root);
    var total = 0;
    for (final term in terms) {
      var score = _scoreTerm(term, name);
      final pathScore = _scoreTerm(term, relative);
      if (pathScore != null && (score == null || pathScore > score)) {
        score = pathScore;
      }
      if (score == null) return null;
      total += score;
    }
    return total;
  }
}
