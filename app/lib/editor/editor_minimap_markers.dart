import 'package:flutter/material.dart';

import '../search/search_service.dart';

const int maxEditorMinimapMarkers = 512;

enum EditorMinimapMarkerKind { error, warning, information, hint, search }

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
  required bool enabled,
  int maxMarkers = maxEditorMinimapMarkers,
}) {
  final limit = maxMarkers.clamp(0, maxEditorMinimapMarkers).toInt();
  if (!enabled || limit == 0) return const [];

  final hasSelectedSearchHit = selectedSearchHit != null &&
      selectedSearchHit.line > 0 &&
      selectedSearchDocumentId == documentId &&
      selectedSearchDocumentVersion == documentVersion;
  final diagnosticLimit = limit - (hasSelectedSearchHit ? 1 : 0);
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
