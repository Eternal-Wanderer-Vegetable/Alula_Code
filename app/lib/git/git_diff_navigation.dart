/// Change targets for keyboard and toolbar navigation in a parsed Git patch.
library;

import 'git_diff_patch.dart';

class GitDiffPatchChange {
  const GitDiffPatchChange({
    required this.firstRowIndex,
    this.originalLineNumber,
    this.modifiedLineNumber,
  });

  /// Row used to reveal this change in the inline patch and aligned view.
  final int firstRowIndex;
  final int? originalLineNumber;
  final int? modifiedLineNumber;
}

/// Returns one target for every contiguous added/removed patch block.
///
/// A no-newline marker belongs to the surrounding change block. Context,
/// hunk, and file metadata rows terminate the block. Unsupported patches have
/// no navigable targets, so callers can keep the original patch fallback.
List<GitDiffPatchChange> computeGitDiffPatchChanges(
  GitDiffPatchResult patch,
) {
  if (!patch.canRender) return const [];

  final changes = <GitDiffPatchChange>[];
  int? firstRowIndex;
  int? originalLineNumber;
  int? modifiedLineNumber;

  void finishChange() {
    final rowIndex = firstRowIndex;
    if (rowIndex != null) {
      changes.add(GitDiffPatchChange(
        firstRowIndex: rowIndex,
        originalLineNumber: originalLineNumber,
        modifiedLineNumber: modifiedLineNumber,
      ));
    }
    firstRowIndex = null;
    originalLineNumber = null;
    modifiedLineNumber = null;
  }

  for (final line in patch.lines) {
    switch (line.kind) {
      case GitDiffPatchLineKind.added:
        firstRowIndex ??= line.rowIndex;
        modifiedLineNumber ??= line.modifiedLineNumber;
        break;
      case GitDiffPatchLineKind.removed:
        firstRowIndex ??= line.rowIndex;
        originalLineNumber ??= line.originalLineNumber;
        break;
      case GitDiffPatchLineKind.marker:
        // Keep the block open across a no-newline marker.
        break;
      case GitDiffPatchLineKind.metadata:
      case GitDiffPatchLineKind.hunk:
      case GitDiffPatchLineKind.context:
        finishChange();
        break;
    }
  }
  finishChange();

  return List.unmodifiable(changes);
}
