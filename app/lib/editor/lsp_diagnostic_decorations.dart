import 'package:flutter/material.dart';

import '../bridge/alula_core.dart';
import 'editor_rendering.dart';

/// Converts versioned LSP UTF-16 positions to document-absolute decorations.
/// Diagnostics outside the visible line interval are skipped before querying
/// Rust line metadata; resulting ranges are still clipped by the renderer.
List<EditorRangeDecoration> buildLspDiagnosticDecorations({
  required List<Map<String, Object?>> diagnostics,
  required int documentVersion,
  required int inputWindowVersion,
  required int windowStartUtf16,
  required int windowEndUtf16,
  required int totalUtf16Length,
  required int documentLineCount,
  required int firstVisibleLine,
  required int lastVisibleLine,
  required DocumentLineOffset Function(int line) lineOffset,
}) {
  if (documentVersion != inputWindowVersion ||
      windowStartUtf16 < 0 ||
      windowEndUtf16 < windowStartUtf16 ||
      totalUtf16Length < windowEndUtf16 ||
      documentLineCount < 1 ||
      firstVisibleLine < 0 ||
      lastVisibleLine < firstVisibleLine) {
    return const [];
  }

  final offsets = <int, DocumentLineOffset>{};
  DocumentLineOffset? offsetFor(int line) {
    if (line < 0 || line >= documentLineCount) return null;
    try {
      return offsets.putIfAbsent(line, () => lineOffset(line));
    } catch (_) {
      // LSP servers are external processes. Ignore malformed/out-of-date
      // positions rather than allowing one diagnostic to break editor build.
      return null;
    }
  }

  final decorations = <EditorRangeDecoration>[];
  for (final diagnostic in diagnostics) {
    final version = _diagnosticInt(diagnostic['documentVersion']);
    if (version != documentVersion) continue;

    final startLine = _diagnosticInt(diagnostic['line']);
    final startCharacter = _diagnosticInt(diagnostic['character']);
    final endLine = _diagnosticInt(diagnostic['endLine']);
    final endCharacter = _diagnosticInt(diagnostic['endCharacter']);
    if (startLine == null ||
        startCharacter == null ||
        endLine == null ||
        endCharacter == null ||
        startCharacter < 0 ||
        endCharacter < 0 ||
        endLine < startLine ||
        startLine > lastVisibleLine ||
        endLine < firstVisibleLine) {
      continue;
    }

    final startPosition = offsetFor(startLine);
    final endPosition =
        endLine == startLine ? startPosition : offsetFor(endLine);
    if (startPosition == null ||
        endPosition == null ||
        startPosition.version != documentVersion ||
        endPosition.version != documentVersion ||
        startPosition.line != startLine ||
        endPosition.line != endLine ||
        startPosition.totalUtf16Length != totalUtf16Length ||
        endPosition.totalUtf16Length != totalUtf16Length) {
      continue;
    }

    final startUtf16 = startPosition.offsetUtf16 + startCharacter;
    final endUtf16 = endPosition.offsetUtf16 + endCharacter;
    if (startUtf16 < 0 ||
        endUtf16 <= startUtf16 ||
        endUtf16 > totalUtf16Length ||
        endUtf16 <= windowStartUtf16 ||
        startUtf16 >= windowEndUtf16) {
      continue;
    }

    decorations.add(
      EditorRangeDecoration(
        documentVersion: documentVersion,
        startUtf16: startUtf16,
        endUtf16: endUtf16,
        underlineColor:
            _diagnosticColor(_diagnosticInt(diagnostic['severity'])),
        underlineWidth: 1.5,
      ),
    );
  }
  return List.unmodifiable(decorations);
}

int? _diagnosticInt(Object? value) => value is num ? value.toInt() : null;

Color _diagnosticColor(int? severity) => switch (severity) {
      1 => const Color(0xFFFF5370),
      2 => const Color(0xFFFFC107),
      4 => const Color(0xFF80CBC4),
      _ => const Color(0xFF42A5F5),
    };
