/// Versioned, checksummed session journal with recoverable same-directory writes.
///
/// The payload is streamed to disk so a dirty document above the former 2M UTF-16
/// limit does not require a second full-size JSON string in memory. A previous
/// verified journal and a complete temporary journal are considered during load.
library;

import 'dart:convert';
import 'dart:io';

enum SessionLoadStatus {
  notFound,
  loaded,
  legacy,
  recoveredFromBackup,
  recoveredFromTemporary,
  invalid,
  unsupportedVersion,
}

class SessionStore {
  SessionStore({String? path, void Function()? afterTemporaryJournalFlushed})
      : _overridePath = path,
        _afterTemporaryJournalFlushed = afterTemporaryJournalFlushed;

  static const _formatKey = '_alulaJournal';
  static const _formatName = 'alula-session';
  static const _formatVersion = 1;

  final String? _overridePath;
  final void Function()? _afterTemporaryJournalFlushed;

  int? _lastGeneration;
  bool _mainIsValid = false;

  SessionLoadStatus lastLoadStatus = SessionLoadStatus.notFound;
  String? lastSaveError;

  String resolvePath() {
    if (_overridePath != null) return _overridePath;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    return '$home/.alula/session.json';
  }

  Map<String, Object?>? tryLoad() {
    final paths = _journalPaths();
    final present = paths.where((file) => file.existsSync()).toList();
    if (present.isEmpty) {
      _lastGeneration = 0;
      _mainIsValid = false;
      lastLoadStatus = SessionLoadStatus.notFound;
      return null;
    }

    final candidates = <_JournalCandidate>[];
    var sawUnsupportedVersion = false;
    for (final file in present) {
      final result = _readCandidate(file);
      if (result.candidate != null) {
        candidates.add(result.candidate!);
      } else if (result.status == SessionLoadStatus.unsupportedVersion) {
        sawUnsupportedVersion = true;
      }
    }
    if (candidates.isEmpty) {
      _lastGeneration = 0;
      _mainIsValid = false;
      lastLoadStatus = sawUnsupportedVersion
          ? SessionLoadStatus.unsupportedVersion
          : SessionLoadStatus.invalid;
      return null;
    }

    candidates.sort((a, b) {
      final generationOrder = b.generation.compareTo(a.generation);
      if (generationOrder != 0) return generationOrder;
      return _sourcePriority(b.file).compareTo(_sourcePriority(a.file));
    });
    final selected = candidates.first;
    _lastGeneration = candidates
        .map((candidate) => candidate.generation)
        .reduce((a, b) => a > b ? a : b);
    final main = paths.first;
    _mainIsValid =
        candidates.any((candidate) => candidate.file.path == main.path);
    lastLoadStatus = switch (selected.source) {
      _JournalSource.main =>
        selected.legacy ? SessionLoadStatus.legacy : SessionLoadStatus.loaded,
      _JournalSource.backup => SessionLoadStatus.recoveredFromBackup,
      _JournalSource.temporary => SessionLoadStatus.recoveredFromTemporary,
    };
    return selected.payload;
  }

  /// Writes a complete new generation and returns whether it became the primary.
  /// The old primary is copied to `.bak`; a flushed `.tmp` is also recoverable if
  /// the process exits before the rename finishes.
  bool save(Map<String, Object?> data) {
    RandomAccessFile? handle;
    try {
      final main = File(resolvePath());
      main.parent.createSync(recursive: true);
      if (_lastGeneration == null) _refreshGenerationFromDisk();
      final generation = (_lastGeneration ?? 0) + 1;
      final backup = File('${main.path}.bak');
      final backupTemporary = File('${backup.path}.tmp');
      final temporary = File('${main.path}.tmp');

      final envelope = <String, Object?>{
        _formatKey: _formatName,
        'version': _formatVersion,
        'generation': generation,
        'checksum': _checksum(data),
        'payload': data,
      };
      handle = temporary.openSync(mode: FileMode.write);
      _encodeJsonToSink(envelope, _RandomAccessFileSink(handle));
      handle.flushSync();
      handle.closeSync();
      handle = null;

      _afterTemporaryJournalFlushed?.call();

      if (_mainIsValid && main.existsSync()) {
        main.copySync(backupTemporary.path);
        final backupHandle = backupTemporary.openSync(mode: FileMode.append);
        backupHandle.flushSync();
        backupHandle.closeSync();
        if (backup.existsSync()) backup.deleteSync();
        backupTemporary.renameSync(backup.path);
      }

      temporary.renameSync(main.path);
      _lastGeneration = generation;
      _mainIsValid = true;
      lastSaveError = null;
      return true;
    } catch (error) {
      try {
        handle?.closeSync();
      } catch (_) {
        // Keep the original failure as the reported cause.
      }
      lastSaveError = error.toString();
      return false;
    }
  }

  List<File> _journalPaths() {
    final main = File(resolvePath());
    return [
      main,
      File('${main.path}.bak'),
      File('${main.path}.tmp'),
    ];
  }

  void _refreshGenerationFromDisk() {
    var maxGeneration = 0;
    _mainIsValid = false;
    for (final file in _journalPaths()) {
      final result = _readCandidate(file);
      final candidate = result.candidate;
      if (candidate == null) continue;
      if (candidate.generation > maxGeneration) {
        maxGeneration = candidate.generation;
      }
      if (file.path == resolvePath()) _mainIsValid = true;
    }
    _lastGeneration = maxGeneration;
  }

  _CandidateRead _readCandidate(File file) {
    if (!file.existsSync()) return const _CandidateRead.absent();
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return const _CandidateRead.invalid();
      final raw = Map<String, Object?>.from(decoded);
      if (!raw.containsKey(_formatKey)) {
        return _CandidateRead.valid(
          _JournalCandidate(
            file: file,
            payload: raw,
            generation: 0,
            legacy: true,
          ),
        );
      }
      if (raw[_formatKey] != _formatName) {
        return const _CandidateRead.invalid();
      }
      if (raw['version'] != _formatVersion) {
        return const _CandidateRead.unsupportedVersion();
      }
      final payloadRaw = raw['payload'];
      if (payloadRaw is! Map || raw['checksum'] is! String) {
        return const _CandidateRead.invalid();
      }
      final payload = Map<String, Object?>.from(payloadRaw);
      if (raw['checksum'] != _checksum(payload)) {
        return const _CandidateRead.invalid();
      }
      final generationRaw = raw['generation'];
      if (generationRaw is! num || generationRaw < 1) {
        return const _CandidateRead.invalid();
      }
      return _CandidateRead.valid(
        _JournalCandidate(
          file: file,
          payload: payload,
          generation: generationRaw.toInt(),
          legacy: false,
        ),
      );
    } catch (_) {
      return const _CandidateRead.invalid();
    }
  }

  _JournalSource _sourceOf(File file) {
    final main = resolvePath();
    if (file.path == main) return _JournalSource.main;
    if (file.path == '$main.bak') return _JournalSource.backup;
    return _JournalSource.temporary;
  }

  int _sourcePriority(File file) => switch (_sourceOf(file)) {
        _JournalSource.main => 3,
        _JournalSource.temporary => 2,
        _JournalSource.backup => 1,
      };

  static String _checksum(Object? value) {
    final sink = _Fnv1aSink();
    _encodeJsonToSink(value, sink);
    return sink.value.toRadixString(16).padLeft(8, '0');
  }

  static void _encodeJsonToSink(Object? value, Sink<List<int>> sink) {
    final encoder = JsonUtf8Encoder().startChunkedConversion(sink);
    encoder.add(value);
    encoder.close();
  }
}

enum _JournalSource { main, backup, temporary }

class _JournalCandidate {
  const _JournalCandidate({
    required this.file,
    required this.payload,
    required this.generation,
    required this.legacy,
  });

  final File file;
  final Map<String, Object?> payload;
  final int generation;
  final bool legacy;

  _JournalSource get source {
    if (file.path.endsWith('.bak')) return _JournalSource.backup;
    if (file.path.endsWith('.tmp')) return _JournalSource.temporary;
    return _JournalSource.main;
  }
}

class _CandidateRead {
  const _CandidateRead.valid(this.candidate) : status = null;
  const _CandidateRead.absent()
      : candidate = null,
        status = null;
  const _CandidateRead.invalid()
      : candidate = null,
        status = SessionLoadStatus.invalid;
  const _CandidateRead.unsupportedVersion()
      : candidate = null,
        status = SessionLoadStatus.unsupportedVersion;

  final _JournalCandidate? candidate;
  final SessionLoadStatus? status;
}

class _Fnv1aSink implements Sink<List<int>> {
  int value = 0x811c9dc5;

  @override
  void add(List<int> chunk) {
    for (final byte in chunk) {
      value = ((value ^ byte) * 0x01000193) & 0xffffffff;
    }
  }

  @override
  void close() {}
}

class _RandomAccessFileSink implements Sink<List<int>> {
  const _RandomAccessFileSink(this.file);

  final RandomAccessFile file;

  @override
  void add(List<int> chunk) => file.writeFromSync(chunk);

  @override
  void close() {}
}
