/// Bounded parser for Git's unified text diff format.
///
/// Unsupported patches are returned as an explicit fallback rather than a
/// partially parsed list. The caller retains the complete original patch.
library;

enum GitDiffPatchLineKind {
  metadata,
  hunk,
  context,
  added,
  removed,
  marker,
}

enum GitDiffPatchFallbackReason {
  inputLimit,
  rowLimit,
  malformed,
  noTextHunks,
}

class GitDiffPatchOptions {
  const GitDiffPatchOptions({
    this.maxInputCodeUnits = 2000000,
    this.maxRows = 16384,
  })  : assert(maxInputCodeUnits >= 0),
        assert(maxRows > 0);

  final int maxInputCodeUnits;
  final int maxRows;
}

class GitDiffPatchLine {
  const GitDiffPatchLine({
    required this.rowIndex,
    required this.kind,
    required this.text,
    this.originalLineNumber,
    this.modifiedLineNumber,
  });

  final int rowIndex;
  final GitDiffPatchLineKind kind;

  /// The patch content without its unified-diff prefix for source rows.
  /// Metadata, hunk headers, and no-newline markers keep their full text.
  final String text;
  final int? originalLineNumber;
  final int? modifiedLineNumber;
}

class GitDiffPatchResult {
  const GitDiffPatchResult._({
    required this.lines,
    required this.hasTextHunks,
    this.fallbackReason,
  });

  final List<GitDiffPatchLine> lines;
  final bool hasTextHunks;
  final GitDiffPatchFallbackReason? fallbackReason;

  bool get canRender => fallbackReason == null && hasTextHunks;
}

final RegExp _hunkHeader = RegExp(
  r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(?:.*)\r?$',
);

/// Parses a unified diff without allocating a list for every patch line.
///
/// Input and emitted rows are capped. On malformed or unsupported input the
/// result contains no rows, allowing the caller to show the untouched patch.
GitDiffPatchResult parseGitDiffPatch(
  String patch, {
  GitDiffPatchOptions options = const GitDiffPatchOptions(),
}) {
  GitDiffPatchResult fallback(GitDiffPatchFallbackReason reason) =>
      GitDiffPatchResult._(
        lines: const [],
        hasTextHunks: false,
        fallbackReason: reason,
      );

  if (patch.length > options.maxInputCodeUnits) {
    return fallback(GitDiffPatchFallbackReason.inputLimit);
  }
  if (patch.isEmpty) {
    return fallback(GitDiffPatchFallbackReason.noTextHunks);
  }

  final lines = <GitDiffPatchLine>[];
  var hasTextHunks = false;
  var inHunk = false;
  var originalLine = 0;
  var modifiedLine = 0;
  var originalRemaining = 0;
  var modifiedRemaining = 0;

  bool addLine(
    GitDiffPatchLineKind kind,
    String text, {
    int? originalNumber,
    int? modifiedNumber,
  }) {
    if (lines.length >= options.maxRows) return false;
    lines.add(GitDiffPatchLine(
      rowIndex: lines.length,
      kind: kind,
      text: text,
      originalLineNumber: originalNumber,
      modifiedLineNumber: modifiedNumber,
    ));
    return true;
  }

  var start = 0;
  while (start < patch.length) {
    final newline = patch.indexOf('\n', start);
    final end = newline < 0 ? patch.length : newline;
    final line = patch.substring(start, end);
    start = newline < 0 ? patch.length : newline + 1;

    if (line.startsWith('@@')) {
      if (inHunk && (originalRemaining != 0 || modifiedRemaining != 0)) {
        return fallback(GitDiffPatchFallbackReason.malformed);
      }
      final match = _hunkHeader.firstMatch(line);
      if (match == null) return fallback(GitDiffPatchFallbackReason.malformed);
      final oldStart = int.tryParse(match.group(1)!);
      final oldCount = int.tryParse(match.group(2) ?? '1');
      final newStart = int.tryParse(match.group(3)!);
      final newCount = int.tryParse(match.group(4) ?? '1');
      if (oldStart == null ||
          oldCount == null ||
          newStart == null ||
          newCount == null) {
        return fallback(GitDiffPatchFallbackReason.malformed);
      }
      if (oldCount > options.maxRows || newCount > options.maxRows) {
        return fallback(GitDiffPatchFallbackReason.rowLimit);
      }
      const maxLineNumber = 0x7fffffff;
      if (oldStart > maxLineNumber - options.maxRows ||
          newStart > maxLineNumber - options.maxRows) {
        return fallback(GitDiffPatchFallbackReason.malformed);
      }
      if (!addLine(GitDiffPatchLineKind.hunk, line)) {
        return fallback(GitDiffPatchFallbackReason.rowLimit);
      }
      hasTextHunks = true;
      inHunk = true;
      originalLine = oldStart;
      modifiedLine = newStart;
      originalRemaining = oldCount;
      modifiedRemaining = newCount;
      continue;
    }

    if (!inHunk) {
      if (!addLine(GitDiffPatchLineKind.metadata, line)) {
        return fallback(GitDiffPatchFallbackReason.rowLimit);
      }
      continue;
    }

    if (line.startsWith(r'\ No newline at end of file')) {
      if (!addLine(GitDiffPatchLineKind.marker, line)) {
        return fallback(GitDiffPatchFallbackReason.rowLimit);
      }
      continue;
    }

    if (originalRemaining == 0 && modifiedRemaining == 0) {
      if (line.startsWith(' ') ||
          line.startsWith('+') ||
          line.startsWith('-')) {
        return fallback(GitDiffPatchFallbackReason.malformed);
      }
      inHunk = false;
      if (!addLine(GitDiffPatchLineKind.metadata, line)) {
        return fallback(GitDiffPatchFallbackReason.rowLimit);
      }
      continue;
    }

    if (line.isEmpty) return fallback(GitDiffPatchFallbackReason.malformed);
    switch (line.codeUnitAt(0)) {
      case 0x20: // context
        if (originalRemaining == 0 || modifiedRemaining == 0) {
          return fallback(GitDiffPatchFallbackReason.malformed);
        }
        if (!addLine(
          GitDiffPatchLineKind.context,
          line.substring(1),
          originalNumber: originalLine,
          modifiedNumber: modifiedLine,
        )) {
          return fallback(GitDiffPatchFallbackReason.rowLimit);
        }
        originalLine++;
        modifiedLine++;
        originalRemaining--;
        modifiedRemaining--;
      case 0x2B: // addition
        if (modifiedRemaining == 0) {
          return fallback(GitDiffPatchFallbackReason.malformed);
        }
        if (!addLine(
          GitDiffPatchLineKind.added,
          line.substring(1),
          modifiedNumber: modifiedLine,
        )) {
          return fallback(GitDiffPatchFallbackReason.rowLimit);
        }
        modifiedLine++;
        modifiedRemaining--;
      case 0x2D: // deletion
        if (originalRemaining == 0) {
          return fallback(GitDiffPatchFallbackReason.malformed);
        }
        if (!addLine(
          GitDiffPatchLineKind.removed,
          line.substring(1),
          originalNumber: originalLine,
        )) {
          return fallback(GitDiffPatchFallbackReason.rowLimit);
        }
        originalLine++;
        originalRemaining--;
      default:
        return fallback(GitDiffPatchFallbackReason.malformed);
    }
  }

  if (inHunk && (originalRemaining != 0 || modifiedRemaining != 0)) {
    return fallback(GitDiffPatchFallbackReason.malformed);
  }
  if (!hasTextHunks) {
    return fallback(GitDiffPatchFallbackReason.noTextHunks);
  }
  return GitDiffPatchResult._(lines: lines, hasTextHunks: true);
}
