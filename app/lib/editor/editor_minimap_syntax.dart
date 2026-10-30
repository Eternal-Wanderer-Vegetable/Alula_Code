import 'package:flutter/material.dart';

import '../bridge/alula_core.dart';

const int maxEditorMinimapSyntaxSegments = 8192;

@immutable
class EditorMinimapSyntaxSegment {
  const EditorMinimapSyntaxSegment({
    required this.line,
    required this.startUtf16,
    required this.endUtf16,
    required this.color,
  })  : assert(line >= 0),
        assert(startUtf16 >= 0),
        assert(endUtf16 > startUtf16);

  final int line;
  final int startUtf16;
  final int endUtf16;
  final Color color;

  @override
  bool operator ==(Object other) =>
      other is EditorMinimapSyntaxSegment &&
      other.line == line &&
      other.startUtf16 == startUtf16 &&
      other.endUtf16 == endUtf16 &&
      other.color == color;

  @override
  int get hashCode => Object.hash(line, startUtf16, endUtf16, color);
}

/// Clips document-absolute syntax ranges to the sampled minimap prefixes.
/// Both the scanned text and returned paint commands have fixed upper bounds.
List<EditorMinimapSyntaxSegment> buildEditorMinimapSyntaxSegments({
  required DocumentMinimapSample sample,
  required List<Map<String, Object?>> tokens,
  required int tokenVersion,
  required Color Function(String kind) colorForKind,
  bool enabled = true,
  int maxSegments = maxEditorMinimapSyntaxSegments,
}) {
  final limit = maxSegments.clamp(0, maxEditorMinimapSyntaxSegments).toInt();
  if (!enabled ||
      limit == 0 ||
      tokens.isEmpty ||
      tokenVersion != sample.version ||
      sample.lines.isEmpty) {
    return const [];
  }

  const candidateLimit =
      maxDocMinimapSampleLines * maxDocMinimapLineSampleUtf16;
  final segments = <EditorMinimapSyntaxSegment>[];
  for (final line in sample.lines) {
    final lineStart = line.startUtf16;
    final lineEnd = lineStart + line.text.length;
    if (lineEnd <= lineStart) continue;

    var low = 0;
    var high = tokens.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      final end = _minimapTokenInt(tokens[middle]['end_utf16']) ?? 0;
      if (end <= lineStart) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }

    for (var index = low; index < tokens.length; index++) {
      final token = tokens[index];
      final absoluteStart = _minimapTokenInt(token['start_utf16']);
      final absoluteEnd = _minimapTokenInt(token['end_utf16']);
      if (absoluteStart == null || absoluteEnd == null) continue;
      if (absoluteStart >= lineEnd) break;
      if (absoluteEnd <= absoluteStart || absoluteEnd <= lineStart) continue;

      final start =
          (absoluteStart > lineStart ? absoluteStart : lineStart) - lineStart;
      final end = (absoluteEnd < lineEnd ? absoluteEnd : lineEnd) - lineStart;
      if (start >= end) continue;
      final color = colorForKind((token['kind'] as String?) ?? '');
      final previous = segments.isEmpty ? null : segments.last;
      if (previous != null &&
          previous.line == line.line &&
          previous.color == color &&
          previous.endUtf16 >= start) {
        segments[segments.length - 1] = EditorMinimapSyntaxSegment(
          line: line.line,
          startUtf16: previous.startUtf16,
          endUtf16: end > previous.endUtf16 ? end : previous.endUtf16,
          color: color,
        );
        continue;
      }
      if (segments.length >= candidateLimit) break;
      segments.add(
        EditorMinimapSyntaxSegment(
          line: line.line,
          startUtf16: start,
          endUtf16: end,
          color: color,
        ),
      );
    }
    if (segments.length >= candidateLimit) break;
  }
  if (segments.length <= limit) return List.unmodifiable(segments);

  final sampleCount = limit;
  return List.unmodifiable(
    List<EditorMinimapSyntaxSegment>.generate(
      sampleCount,
      (index) => segments[sampleCount == 1
          ? segments.length ~/ 2
          : index * (segments.length - 1) ~/ (sampleCount - 1)],
      growable: false,
    ),
  );
}

int? _minimapTokenInt(Object? value) => value is num ? value.toInt() : null;
