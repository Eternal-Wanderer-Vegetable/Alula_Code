/// The close operation selected from an editor tab or editor group.
enum EditorTabCloseOperation {
  close,
  closeOthers,
  closeToLeft,
  closeToRight,
  closeSaved,
}

/// Resolves tab-close candidates in the clicked editor group's current order.
class EditorTabClosePolicy {
  const EditorTabClosePolicy._();

  static List<int> candidates({
    required List<int> documentIds,
    required int targetId,
    required Set<int> stickyDocumentIds,
    required Set<int> cleanDocumentIds,
    required EditorTabCloseOperation action,
  }) {
    final targetIndex = documentIds.indexOf(targetId);
    if (targetIndex < 0) return const [];

    final result = <int>[];
    for (var index = 0; index < documentIds.length; index++) {
      final id = documentIds[index];
      final sticky = stickyDocumentIds.contains(id);
      final shouldClose = switch (action) {
        EditorTabCloseOperation.close => id == targetId,
        EditorTabCloseOperation.closeOthers => index != targetIndex && !sticky,
        EditorTabCloseOperation.closeToLeft => index < targetIndex && !sticky,
        EditorTabCloseOperation.closeToRight => index > targetIndex && !sticky,
        EditorTabCloseOperation.closeSaved =>
          !sticky && cleanDocumentIds.contains(id),
      };
      if (shouldClose) result.add(id);
    }
    return List.unmodifiable(result);
  }
}
