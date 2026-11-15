/// Bounded, application-level recent file and workspace history (LAY-19b).
///
/// The journal sits beside the session journal and uses its atomic, checksummed
/// envelope. Paths are absolute, deduplicated per kind, and kept most-recent
/// first. Missing paths are pruned asynchronously by [pruneMissingPaths].
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'session_store.dart';

const int maxRecentHistoryEntriesPerKind = 50;
const int maxRecentHistoryPathLength = 2048;
const int maxRecentHistoryRecordBytes = 512 * 1024;

enum RecentHistoryKind { file, workspace }

class RecentHistoryEntry {
  const RecentHistoryEntry({required this.path, required this.kind});

  final String path;
  final RecentHistoryKind kind;

  String get label => p.basename(path);

  @override
  bool operator ==(Object other) =>
      other is RecentHistoryEntry &&
      other.kind == kind &&
      _pathKey(other.path) == _pathKey(path);

  @override
  int get hashCode => Object.hash(kind, _pathKey(path));
}

class RecentHistorySnapshot {
  const RecentHistorySnapshot({
    this.files = const <RecentHistoryEntry>[],
    this.workspaces = const <RecentHistoryEntry>[],
  });

  final List<RecentHistoryEntry> files;
  final List<RecentHistoryEntry> workspaces;

  bool get isEmpty => files.isEmpty && workspaces.isEmpty;
}

class RecentHistoryStore {
  RecentHistoryStore({required this.path});

  /// Journal path. Workbench derives this from `SessionStore.resolvePath()`.
  final String path;

  RecentHistorySnapshot load() {
    if (_hasOversizedJournal()) return const RecentHistorySnapshot();
    final data = SessionStore(path: path).tryLoad();
    if (data == null ||
        data['format'] != 'alula-recent-history' ||
        data['version'] != 1) {
      return const RecentHistorySnapshot();
    }
    return RecentHistorySnapshot(
      files: _readEntries(data['files'], RecentHistoryKind.file),
      workspaces: _readEntries(data['workspaces'], RecentHistoryKind.workspace),
    );
  }

  bool recordFile(String path) => _record(path, RecentHistoryKind.file);

  bool recordWorkspace(String path) =>
      _record(path, RecentHistoryKind.workspace);

  bool remove(RecentHistoryEntry entry) {
    final current = load();
    final files = current.files.where((item) => item != entry).toList();
    final workspaces =
        current.workspaces.where((item) => item != entry).toList();
    if (files.length == current.files.length &&
        workspaces.length == current.workspaces.length) {
      return true;
    }
    return _save(RecentHistorySnapshot(files: files, workspaces: workspaces));
  }

  /// Removes paths that disappeared or changed to the wrong filesystem kind.
  /// Access errors retain the entry so a transient permission issue does not
  /// erase useful history.
  Future<RecentHistorySnapshot> pruneMissingPaths() async {
    final current = load();
    final missingFiles =
        await _missingPaths(current.files, RecentHistoryKind.file);
    final missingWorkspaces =
        await _missingPaths(current.workspaces, RecentHistoryKind.workspace);

    // Re-read after asynchronous filesystem checks so an item opened while the
    // scan was running is retained and the latest MRU ordering is preserved.
    final latest = load();
    final files = latest.files
        .where((entry) => !missingFiles.contains(_pathKey(entry.path)))
        .toList();
    final workspaces = latest.workspaces
        .where((entry) => !missingWorkspaces.contains(_pathKey(entry.path)))
        .toList();
    final result = RecentHistorySnapshot(files: files, workspaces: workspaces);
    if (files.length != latest.files.length ||
        workspaces.length != latest.workspaces.length) {
      _save(result);
    }
    return result;
  }

  bool _record(String rawPath, RecentHistoryKind kind) {
    final normalized = _normalizePath(rawPath);
    if (normalized == null) return false;

    // An oversized stale journal must not make every future load fall back to
    // empty even after a successful replacement write.
    if (_hasOversizedJournal()) _deleteJournal();
    final current = load();
    final files = current.files.toList();
    final workspaces = current.workspaces.toList();
    final target = kind == RecentHistoryKind.file ? files : workspaces;
    target.removeWhere((entry) => _pathKey(entry.path) == _pathKey(normalized));
    target.insert(0, RecentHistoryEntry(path: normalized, kind: kind));
    if (target.length > maxRecentHistoryEntriesPerKind) {
      target.removeRange(maxRecentHistoryEntriesPerKind, target.length);
    }
    return _save(RecentHistorySnapshot(files: files, workspaces: workspaces));
  }

  Future<Set<String>> _missingPaths(
    List<RecentHistoryEntry> entries,
    RecentHistoryKind expectedKind,
  ) async {
    final missing = <String>{};
    for (final entry in entries) {
      try {
        final type = await FileSystemEntity.type(entry.path, followLinks: true);
        final expectedType = expectedKind == RecentHistoryKind.file
            ? FileSystemEntityType.file
            : FileSystemEntityType.directory;
        if (type != expectedType) missing.add(_pathKey(entry.path));
      } on FileSystemException {
        // Retain paths when the filesystem cannot answer because of access or
        // transient I/O errors.
      }
    }
    return missing;
  }

  List<RecentHistoryEntry> _readEntries(
    Object? raw,
    RecentHistoryKind kind,
  ) {
    if (raw is! List) return const <RecentHistoryEntry>[];
    final entries = <RecentHistoryEntry>[];
    final keys = <String>{};
    for (final value in raw) {
      if (value is! String) continue;
      final normalized = _normalizePath(value);
      if (normalized == null) continue;
      final key = _pathKey(normalized);
      if (!keys.add(key)) continue;
      entries.add(RecentHistoryEntry(path: normalized, kind: kind));
      if (entries.length == maxRecentHistoryEntriesPerKind) break;
    }
    return entries;
  }

  bool _save(RecentHistorySnapshot snapshot) {
    final files = snapshot.files
        .where((entry) => entry.kind == RecentHistoryKind.file)
        .take(maxRecentHistoryEntriesPerKind)
        .map((entry) => entry.path)
        .toList();
    final workspaces = snapshot.workspaces
        .where((entry) => entry.kind == RecentHistoryKind.workspace)
        .take(maxRecentHistoryEntriesPerKind)
        .map((entry) => entry.path)
        .toList();
    final payload = <String, Object?>{
      'format': 'alula-recent-history',
      'version': 1,
      'files': files,
      'workspaces': workspaces,
    };
    while (utf8.encode(jsonEncode(payload)).length >
            maxRecentHistoryRecordBytes * 3 ~/ 4 &&
        (files.isNotEmpty || workspaces.isNotEmpty)) {
      if (files.length >= workspaces.length && files.isNotEmpty) {
        files.removeLast();
      } else {
        workspaces.removeLast();
      }
    }
    if (_hasOversizedJournal()) _deleteJournal();
    return SessionStore(path: path).save(payload);
  }

  bool _hasOversizedJournal() {
    for (final file in _journalFiles()) {
      try {
        if (file.existsSync() &&
            file.lengthSync() > maxRecentHistoryRecordBytes) {
          return true;
        }
      } on FileSystemException {
        return true;
      }
    }
    return false;
  }

  void _deleteJournal() {
    for (final file in _journalFiles()) {
      try {
        if (file.existsSync()) file.deleteSync();
      } on FileSystemException {
        // A failed cleanup remains a safe read fallback and the write reports
        // its own result to the caller.
      }
    }
  }

  List<File> _journalFiles() => [
        File(path),
        File('$path.bak'),
        File('$path.tmp'),
      ];
}

String? _normalizePath(String path) {
  if (path.isEmpty ||
      path.length > maxRecentHistoryPathLength ||
      path.contains('\u0000')) {
    return null;
  }
  try {
    final normalized = p.normalize(p.absolute(path));
    return normalized.length <= maxRecentHistoryPathLength ? normalized : null;
  } on Object {
    return null;
  }
}

String _pathKey(String path) => Platform.isWindows ? path.toLowerCase() : path;
