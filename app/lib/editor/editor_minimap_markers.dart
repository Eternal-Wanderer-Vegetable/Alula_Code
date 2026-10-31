import 'package:flutter/material.dart';

import 'find_replace.dart';
import '../search/search_service.dart';

const int maxEditorMinimapMarkers = 512;
const int maxEditorMinimapFindMarkers = 256;

enum EditorMinimapMarkerKind { error, warning, information, hint, search, find }

@immutable
class EditorMinimapMarker {
  const EditorMinimapMarker({
    required this.documentId,
    required this.documentVersion,
    required this.line,
    required this.kind,
  });

  final int documentId;
  final int documentVersion;

  /// Zero-based Rust/LSP logical line number.
  final int line;
  final EditorMinimapMarkerKind kind;

  Color get color => switch (kind) {
        EditorMinimapMarkerKind.error => const Color(0xFFFF5370),
        EditorMinimapMarkerKind.warning => const Color(0xFFFFC107),
        EditorMinimapMarkerKind.information => const Color(0xFF42A5F5),
        EditorMinimapMarkerKind.hint => const Color(0xFF80CBC4),
        EditorMinimapMarkerKind.search => const Color(0xFF60A5FA),
        EditorMinimapMarkerKind.find => const Color(0xFFF0C674),
      };

  @override
  bool operator ==(Object other) =>
      other is EditorMinimapMarker &&
      other.documentId == documentId &&
      other.documentVersion == documentVersion &&
      other.line == line &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(documentId, documentVersion, line, kind);
}

/// Builds a bounded overview from the already-published LSP diagnostics and
/// the currently selected workspace-search hit. Stale documents and versions
/// are rejected before they reach the painter.
List<EditorMinimapMarker> buildEditorMinimapMarkers({
  required int documentId,
  required int documentVersion,
  required List<Map<String, Object?>> diagnostics,
  required int? selectedSearchDocumentId,
  required int? selectedSearchDocumentVersion,
  required SearchHit? selectedSearchHit,
  List<int> findMatchLines = const [],
  int? findMatchesDocumentId,
  int? findMatchesDocumentVersion,
  required bool enabled,
  int maxMarkers = maxEditorMinimapMarkers,
}) {
  final limit = maxMarkers.clamp(0, maxEditorMinimapMarkers).toInt();
  if (!enabled || limit == 0) return const [];

  final hasSelectedSearchHit = selectedSearchHit != null &&
      selectedSearchHit.line > 0 &&
      selectedSearchDocumentId == documentId &&
      selectedSearchDocumentVersion == documentVersion;
  final hasCurrentFindMatches = findMatchesDocumentId == documentId &&
      findMatchesDocumentVersion == documentVersion &&
      findMatchLines.isNotEmpty;
  final findMarkerLimit = hasCurrentFindMatches
      ? findMatchLines.length
          .clamp(0, maxEditorMinimapFindMarkers)
          .clamp(0, limit - (hasSelectedSearchHit ? 1 : 0))
          .toInt()
      : 0;
  final diagnosticLimit =
      limit - findMarkerLimit - (hasSelectedSearchHit ? 1 : 0);
  final overviewMarkers = <EditorMinimapMarker>[];
  for (final diagnostic in diagnostics.take(4096)) {
    if (overviewMarkers.length >= diagnosticLimit) break;
    if (_markerInt(diagnostic['_documentId']) != documentId ||
        _markerInt(diagnostic['documentVersion']) != documentVersion) {
      continue;
    }
    final line = _markerInt(diagnostic['line']);
    if (line == null || line < 0) continue;
    final kind = switch (_markerInt(diagnostic['severity'])) {
      1 => EditorMinimapMarkerKind.error,
      2 => EditorMinimapMarkerKind.warning,
      4 => EditorMinimapMarkerKind.hint,
      _ => EditorMinimapMarkerKind.information,
    };
    overviewMarkers.add(
      EditorMinimapMarker(
        documentId: documentId,
        documentVersion: documentVersion,
        line: line,
        kind: kind,
      ),
    );
  }

  if (hasCurrentFindMatches) {
    for (final line in findMatchLines.take(findMarkerLimit)) {
      if (line < 0) continue;
      overviewMarkers.add(
        EditorMinimapMarker(
          documentId: documentId,
          documentVersion: documentVersion,
          line: line,
          kind: EditorMinimapMarkerKind.find,
        ),
      );
    }
  }

  if (hasSelectedSearchHit && overviewMarkers.length < limit) {
    overviewMarkers.add(
      EditorMinimapMarker(
        documentId: documentId,
        documentVersion: documentVersion,
        line: selectedSearchHit.line - 1,
        kind: EditorMinimapMarkerKind.search,
      ),
    );
  }
  return List.unmodifiable(overviewMarkers);
}

int? _markerInt(Object? value) => value is num ? value.toInt() : null;

/// Maps evenly sampled, ordered UTF-16 find matches to logical lines.
/// The result is bounded even when a document contains many occurrences.
List<int> buildEditorMinimapFindLines(
  String text,
  List<TextMatch> matches, {
  int maxMarkers = maxEditorMinimapFindMarkers,
}) {
  final count = maxMarkers.clamp(0, maxEditorMinimapFindMarkers).toInt();
  if (count == 0 || matches.isEmpty) return const [];

  final sampleCount = matches.length.clamp(0, count).toInt();
  final sampledIndices = List<int>.generate(
    sampleCount,
    (index) => sampleCount == 1
        ? 0
        : index * (matches.length - 1) ~/ (sampleCount - 1),
    growable: false,
  );
  final lines = <int>[];
  var cursor = 0;
  var line = 0;
  for (final index in sampledIndices) {
    final match = matches[index];
    if (match.start < cursor ||
        match.start < 0 ||
        match.end <= match.start ||
        match.end > text.length) {
      continue;
    }
    while (cursor < match.start) {
      if (text.codeUnitAt(cursor) == 0x0A) line++;
      cursor++;
    }
    lines.add(line);
  }
  return List.unmodifiable(lines);
}

double projectEditorMinimapMarkerY({
  required int line,
  required int lineCount,
  required double height,
}) {
  if (lineCount < 1 || height < 0) {
    throw ArgumentError('lineCount must be positive and height non-negative');
  }
  if (lineCount == 1) return 0;
  return line.clamp(0, lineCount - 1) / (lineCount - 1) * height;
}
