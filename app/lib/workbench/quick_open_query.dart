import 'dart:io';

import 'package:path/path.dart' as p;

import 'tree_fuzzy_score.dart';

/// A file query with an optional one-based navigation suffix.
class QuickOpenQuery {
  const QuickOpenQuery(this.pathQuery, {this.line, this.column});

  final String pathQuery;
  final int? line;
  final int? column;
}

/// Parses `filename:line[:column]`, preserving a Windows drive colon.
/// Zero line/column values are clamped to one, as navigation is one-based.
QuickOpenQuery parseQuickOpenQuery(String input) {
  final text = input.trim();
  final match = RegExp(r'^(.*?):([0-9]+)(?::([0-9]+))?$').firstMatch(text);
  if (match == null ||
      (match.group(1)!.length == 1 && RegExp(r'^[a-zA-Z]:').hasMatch(text))) {
    return QuickOpenQuery(text);
  }
  final line = int.tryParse(match.group(2)!);
  final column = match.group(3) == null ? null : int.tryParse(match.group(3)!);
  if (line == null || (match.group(3) != null && column == null)) {
    return QuickOpenQuery(text);
  }
  return QuickOpenQuery(match.group(1)!,
      line: line < 1 ? 1 : line,
      column: column == null ? null : (column < 1 ? 1 : column));
}

typedef QuickOpenMatch = ({String path, bool recent});

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
    final recentKeys = <String>{};
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
            _score(pattern, path, rootPath) == null) {
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
      if (p.isAbsolute(pattern)) return finish();

      await for (final path in _walk(rootPath, 0, generation)) {
        if (!current()) return [];
        final key = _key(path);
        if (recentKeys.contains(key) || (directExists && key == directKey)) {
          continue;
        }
        final score = _score(pattern, path, rootPath);
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

  static int? _score(String pattern, String path, String root) {
    if (pattern.isEmpty) return 0;
    final nameScore = treeFuzzyScore(pattern, p.basename(path))?.score;
    final pathScore =
        treeFuzzyScore(pattern, p.relative(path, from: root))?.score;
    if (nameScore == null) return pathScore;
    if (pathScore == null) return nameScore;
    return nameScore > pathScore ? nameScore : pathScore;
  }
}
