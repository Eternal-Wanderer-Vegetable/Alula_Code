import 'dart:convert';
import 'dart:io';

import '../editor/find_replace_history.dart';
import 'session_store.dart';

const int maxFindHistoryWorkspaceRecords = 16;
const int maxFindHistoryRecordBytes = 2 * 1024 * 1024;

class FindReplaceHistorySnapshot {
  const FindReplaceHistorySnapshot({
    this.find = const [],
    this.replace = const [],
  });

  final List<String> find;
  final List<String> replace;
}

/// Workspace-isolated, recoverable find/replace history storage.
///
/// The store keeps one bounded journal per workspace. Only the active
/// workspace is loaded into memory by the workbench; old records are pruned
/// after writes so the cache remains bounded across many opened folders.
class FindReplaceHistoryStore {
  FindReplaceHistoryStore({required this.directory});

  final String directory;

  FindReplaceHistorySnapshot load(String? workspaceRoot) {
    final identity = workspaceIdentity(workspaceRoot);
    final path = _pathFor(identity);
    final payload = _readPayload(path);
    if (payload == null || payload['workspace'] != identity) {
      return const FindReplaceHistorySnapshot();
    }
    final snapshot = FindReplaceHistorySnapshot(
      find: _readEntries(payload['find']),
      replace: _readEntries(payload['replace']),
    );
    final main = File(path);
    if (main.existsSync()) {
      try {
        main.setLastModifiedSync(DateTime.now());
      } on FileSystemException {
        // History remains usable if the cache's access time cannot be updated.
      }
    }
    return snapshot;
  }

  /// Updates only the supplied histories. A null field preserves the prior
  /// persisted value, which lets a `never` setting stop writes without erasing
  /// history that belongs to the other input.
  bool save(
    String? workspaceRoot, {
    List<String>? find,
    List<String>? replace,
  }) {
    if (find == null && replace == null) return true;
    final identity = workspaceIdentity(workspaceRoot);
    final path = _pathFor(identity);
    if (_hasOversizedJournal(path)) _deleteJournal(path);
    final existing = _readPayload(path);
    if (existing != null &&
        existing['workspace'] is String &&
        existing['workspace'] != identity) {
      return false;
    }
    final payload = <String, Object?>{
      'format': 'alula-find-history',
      'version': 1,
      'workspace': identity,
      'find': find == null
          ? _readEntries(existing?['find'])
          : _boundedEntries(find),
      'replace': replace == null
          ? _readEntries(existing?['replace'])
          : _boundedEntries(replace),
    };
    _fitRecord(payload);
    final saved = SessionStore(path: path).save(payload);
    if (saved) _pruneOldRecords(path);
    return saved;
  }

  static String workspaceIdentity(String? workspaceRoot) {
    if (workspaceRoot == null || workspaceRoot.isEmpty) {
      return 'empty-workspace';
    }
    var normalized = workspaceRoot.replaceAll('\\', '/');
    while (normalized.length > 1 &&
        normalized.endsWith('/') &&
        !RegExp(r'^[a-zA-Z]:/$').hasMatch(normalized)) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (Platform.isWindows) normalized = normalized.toLowerCase();
    return 'workspace:$normalized';
  }

  String _pathFor(String identity) {
    final root = Directory(directory).absolute.path;
    return '$root${Platform.pathSeparator}${_stableHash(identity)}.json';
  }

  Map<String, Object?>? _readPayload(String path) {
    if (_hasOversizedJournal(path)) return null;
    final data = SessionStore(path: path).tryLoad();
    if (data == null ||
        data['format'] != 'alula-find-history' ||
        data['version'] != 1) {
      return null;
    }
    return data;
  }

  bool _hasOversizedJournal(String path) {
    for (final file in [
      File(path),
      File('$path.bak'),
      File('$path.tmp'),
    ]) {
      try {
        if (file.existsSync() &&
            file.lengthSync() > maxFindHistoryRecordBytes) {
          return true;
        }
      } on FileSystemException {
        return true;
      }
    }
    return false;
  }

  void _deleteJournal(String path) {
    for (final file in [
      File(path),
      File('$path.bak'),
      File('$path.tmp'),
    ]) {
      try {
        if (file.existsSync()) file.deleteSync();
      } on FileSystemException {
        // A later write will report the concrete filesystem error.
      }
    }
  }

  List<String> _readEntries(Object? raw) {
    if (raw is! List) return const [];
    final entries = raw
        .whereType<String>()
        .where((entry) =>
            entry.isNotEmpty && entry.length <= maxFindReplaceHistoryEntryUtf16)
        .toList(growable: false);
    return entries.length <= maxFindReplaceHistoryEntries
        ? entries
        : entries.sublist(entries.length - maxFindReplaceHistoryEntries);
  }

  List<String> _boundedEntries(Iterable<String> entries) {
    final accepted = <String>[];
    for (final entry in entries) {
      if (entry.isEmpty || entry.length > maxFindReplaceHistoryEntryUtf16) {
        continue;
      }
      accepted.remove(entry);
      accepted.add(entry);
      if (accepted.length > maxFindReplaceHistoryEntries) {
        accepted.removeAt(0);
      }
    }
    return accepted;
  }

  void _fitRecord(Map<String, Object?> payload) {
    final find = payload['find']! as List<String>;
    final replace = payload['replace']! as List<String>;
    while (utf8.encode(jsonEncode(payload)).length >
            maxFindHistoryRecordBytes * 3 ~/ 4 &&
        (find.isNotEmpty || replace.isNotEmpty)) {
      if (find.length >= replace.length && find.isNotEmpty) {
        find.removeAt(0);
      } else {
        replace.removeAt(0);
      }
    }
  }

  void _pruneOldRecords(String currentPath) {
    final root = Directory(directory);
    if (!root.existsSync()) return;
    final records = <File>[];
    for (final entity in root.listSync(followLinks: false)) {
      if (entity is File && entity.path.endsWith('.json')) records.add(entity);
    }
    if (records.length <= maxFindHistoryWorkspaceRecords) return;
    records.sort((a, b) {
      try {
        return a.lastModifiedSync().compareTo(b.lastModifiedSync());
      } on FileSystemException {
        return 0;
      }
    });
    var remaining = records.length;
    for (final file in records) {
      if (remaining <= maxFindHistoryWorkspaceRecords) break;
      if (file.path == currentPath) continue;
      _deleteJournal(file.path);
      remaining--;
    }
  }

  String _stableHash(String value) {
    final mask = BigInt.parse('ffffffffffffffff', radix: 16);
    var hash = BigInt.parse('cbf29ce484222325', radix: 16);
    for (final byte in utf8.encode(value)) {
      hash ^= BigInt.from(byte);
      hash = (hash * BigInt.from(0x100000001b3)) & mask;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
