import 'dart:io' show Platform;

/// Input needed to derive a default editor-tab label.
class EditorTabLabelInput {
  const EditorTabLabelInput({required this.name, this.path});

  final String name;
  final String? path;
}

/// Produces group-local default labels with the shortest distinguishing path.
class EditorTabLabelPolicy {
  const EditorTabLabelPolicy._();

  static List<String> labelsFor(
    List<EditorTabLabelInput> documents, {
    bool? caseSensitive,
  }) {
    if (documents.isEmpty) return const [];

    final sensitive = caseSensitive ?? !Platform.isWindows;
    String key(String value) => sensitive ? value : value.toLowerCase();

    final labels = documents.map((document) => document.name).toList();
    final collisions = <String, List<int>>{};
    for (var index = 0; index < documents.length; index++) {
      collisions.putIfAbsent(key(documents[index].name), () => []).add(index);
    }

    for (final indices
        in collisions.values.where((group) => group.length > 1)) {
      final paths = <int, _TabLabelPath?>{
        for (final index in indices)
          index: _TabLabelPath.parse(documents[index].path),
      };
      final depths = <int, int>{for (final index in indices) index: 0};
      final maximumDepth = indices.fold<int>(
        0,
        (maximum, index) => maxOf(maximum, paths[index]?.maxDepth ?? 0),
      );

      // Increase suffixes only while two current labels still collide. This
      // leaves already distinguished labels at their shortest useful depth.
      for (var step = 0; step < maximumDepth; step++) {
        final duplicates = <String, List<int>>{};
        for (final index in indices) {
          final suffix = paths[index]?.suffixAt(depths[index]!);
          final label = suffix == null
              ? documents[index].name
              : '${documents[index].name} — $suffix';
          duplicates.putIfAbsent(key(label), () => []).add(index);
        }

        var advanced = false;
        for (final group
            in duplicates.values.where((items) => items.length > 1)) {
          for (final index in group) {
            final path = paths[index];
            if (path != null && depths[index]! < path.maxDepth) {
              depths[index] = depths[index]! + 1;
              advanced = true;
            }
          }
        }
        if (!advanced) break;
      }

      for (final index in indices) {
        final suffix = paths[index]?.suffixAt(depths[index]!);
        if (suffix != null) {
          labels[index] = '${documents[index].name} — $suffix';
        }
      }
    }

    return List.unmodifiable(labels);
  }

  static int maxOf(int first, int second) => first > second ? first : second;
}

class _TabLabelPath {
  const _TabLabelPath({required this.root, required this.parents});

  final String? root;
  final List<String> parents;

  int get maxDepth => parents.length + (root == null ? 0 : 1);

  String? suffixAt(int depth) {
    if (depth <= 0 || depth > maxDepth) return null;
    if (depth <= parents.length) {
      return parents.skip(parents.length - depth).join('/');
    }
    final root = this.root;
    if (root == null) return null;
    if (parents.isEmpty) return root;
    return root == '/'
        ? '$root${parents.join('/')}'
        : '$root/${parents.join('/')}';
  }

  static _TabLabelPath? parse(String? rawPath) {
    if (rawPath == null || rawPath.trim().isEmpty) return null;

    final path = rawPath.replaceAll('\\', '/');
    String? root;
    String remainder;
    if (path.startsWith('//')) {
      final segments = _normalizeSegments(path.substring(2), rooted: true);
      if (segments.isEmpty) return null;
      final server = segments.removeAt(0);
      if (segments.isNotEmpty) {
        root = '//$server/${segments.removeAt(0)}';
      } else {
        root = '//$server';
      }
      remainder = segments.join('/');
    } else if (RegExp(r'^[A-Za-z]:/').hasMatch(path)) {
      root = path.substring(0, 2);
      remainder = path.substring(3);
    } else if (path.startsWith('/')) {
      root = '/';
      remainder = path.substring(1);
    } else {
      remainder = path;
    }

    final segments = _normalizeSegments(remainder, rooted: root != null);
    if (segments.isEmpty) return null;
    return _TabLabelPath(
      root: root,
      parents: List.unmodifiable(segments.take(segments.length - 1)),
    );
  }

  static List<String> _normalizeSegments(
    String path, {
    required bool rooted,
  }) {
    final result = <String>[];
    for (final segment in path.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (result.isNotEmpty && result.last != '..') {
          result.removeLast();
        } else if (!rooted) {
          result.add(segment);
        }
        continue;
      }
      result.add(segment);
    }
    return result;
  }
}
