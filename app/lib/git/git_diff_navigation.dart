/// Change targets for keyboard and toolbar navigation in a parsed Git patch.
library;

import 'git_diff_patch.dart';

/// A bounded bridge from workbench commands to the mounted Git diff view.
///
/// The view owns parsing, the current target index, and reveal behavior. This
/// object only forwards one requested direction to that mounted state.
class GitDiffPatchNavigationController {
  Object? _owner;
  void Function(int direction)? _navigateToChange;
  bool _canNavigate = false;

  bool get canNavigate => _canNavigate && _navigateToChange != null;

  void attach({
    required Object owner,
    required void Function(int direction) navigateToChange,
    required bool canNavigate,
  }) {
    _owner = owner;
    _navigateToChange = navigateToChange;
    _canNavigate = canNavigate;
  }

  void updateAvailability({required Object owner, required bool canNavigate}) {
    if (!identical(_owner, owner)) return;
    _canNavigate = canNavigate;
  }

  void detach({required Object owner}) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _navigateToChange = null;
    _canNavigate = false;
  }

  bool navigateNext() => _navigate(1);

  bool navigatePrevious() => _navigate(-1);

  bool _navigate(int direction) {
    if (!canNavigate) return false;
    _navigateToChange!(direction);
    return true;
  }
}

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
