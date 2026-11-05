import 'package:flutter/material.dart';

import '../bridge/alula_core.dart';
import '../search/search_service.dart';
import 'editor_rendering.dart';

/// Builds decorations for one selected workspace-search result.
///
/// Ripgrep submatches are exact UTF-16 ranges. The git-grep fallback only
/// reports matching lines, so it decorates the whole line. Results are
/// discarded unless their document and bounded input window share a version.
List<EditorRangeDecoration> buildWorkspaceSearchDecorations({
  required SearchHit? hit,
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
  if (hit == null ||
      documentVersion != inputWindowVersion ||
      windowStartUtf16 < 0 ||
      windowEndUtf16 < windowStartUtf16 ||
      totalUtf16Length < windowEndUtf16 ||
      documentLineCount < 1 ||
      firstVisibleLine < 0 ||
      lastVisibleLine < firstVisibleLine) {
    return const [];
  }

  final line = hit.line - 1;
  if (line < firstVisibleLine ||
      line > lastVisibleLine ||
      line < 0 ||
      line >= documentLineCount ||
      hit.lineText.isEmpty) {
    return const [];
  }

  DocumentLineOffset offset;
  try {
    offset = lineOffset(line);
  } catch (_) {
    return const [];
  }
  if (offset.version != documentVersion ||
      offset.totalUtf16Length != totalUtf16Length ||
      offset.lineCount != documentLineCount ||
      offset.line != line ||
      offset.offsetUtf16 < 0 ||
      offset.offsetUtf16 > totalUtf16Length) {
    return const [];
  }

  final ranges = hit.matchRanges.isEmpty
      ? [SearchHitRange(startUtf16: 0, endUtf16: hit.lineText.length)]
      : hit.matchRanges;
  final decorations = <EditorRangeDecoration>[];
  for (final range in ranges) {
    if (range.startUtf16 < 0 ||
        range.endUtf16 <= range.startUtf16 ||
        range.endUtf16 > hit.lineText.length) {
      continue;
    }
    final start = offset.offsetUtf16 + range.startUtf16;
    final end = offset.offsetUtf16 + range.endUtf16;
    if (end > totalUtf16Length ||
        end <= windowStartUtf16 ||
        start >= windowEndUtf16) {
      continue;
    }
    decorations.add(
      EditorRangeDecoration(
        documentVersion: documentVersion,
        startUtf16: start,
        endUtf16: end,
        backgroundColor: const Color(0x553B82F6),
        borderColor: const Color(0xFF60A5FA),
      ),
    );
  }
  return List.unmodifiable(decorations);
}
