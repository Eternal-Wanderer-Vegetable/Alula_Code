/// Stable ordering for a single editor group's open documents.
class EditorTabMruPolicy {
  const EditorTabMruPolicy._();

  /// Places still-open [recentDocumentIds] first, then keeps unseen tabs in
  /// their existing order. Duplicate and stale MRU IDs are ignored.
  static List<T> order<T>({
    required Iterable<T> tabs,
    required Iterable<int> recentDocumentIds,
    required int Function(T) documentId,
  }) {
    final tabsById = <int, T>{};
    for (final tab in tabs) {
      tabsById.putIfAbsent(documentId(tab), () => tab);
    }

    final ordered = <T>[];
    final seen = <int>{};
    for (final id in recentDocumentIds) {
      final tab = tabsById[id];
      if (tab != null && seen.add(id)) ordered.add(tab);
    }
    for (final entry in tabsById.entries) {
      if (seen.add(entry.key)) ordered.add(entry.value);
    }
    return List<T>.unmodifiable(ordered);
  }
}
