/// A restorable editor location. Positions use zero-based UTF-16 line/column.
class NavigationLocation {
  const NavigationLocation({
    required this.uri,
    required this.path,
    required this.documentId,
    required this.groupRegion,
    required this.line,
    required this.character,
    required this.version,
  });

  final String? uri;
  final String? path;
  final int documentId;
  final String groupRegion;
  final int line;
  final int character;
  final int version;

  bool get canReopen => path != null && uri != null;

  bool samePosition(NavigationLocation other) {
    final sameDocument = uri != null || other.uri != null
        ? uri == other.uri
        : documentId == other.documentId;
    return sameDocument &&
        groupRegion == other.groupRegion &&
        line == other.line &&
        character == other.character;
  }
}

/// Bounded back/forward and last-edit stacks for the workbench.
class NavigationHistory {
  NavigationHistory(
      {this.maxNavigationEntries = 128, this.maxEditEntries = 128})
      : assert(maxNavigationEntries > 1),
        assert(maxEditEntries > 0);

  final int maxNavigationEntries;
  final int maxEditEntries;
  final List<NavigationLocation> _entries = [];
  final List<NavigationLocation> _editEntries = [];
  int _cursor = -1;

  bool get canGoBack => _cursor > 0;
  bool get canGoForward => _cursor >= 0 && _cursor + 1 < _entries.length;

  void recordNavigation(
    NavigationLocation from,
    NavigationLocation to,
  ) {
    if (from.samePosition(to)) return;
    if (_cursor < 0) {
      _entries.add(from);
      _cursor = 0;
    } else {
      _entries[_cursor] = from;
    }
    if (_cursor + 1 < _entries.length) {
      _entries.removeRange(_cursor + 1, _entries.length);
    }
    _entries.add(to);
    _cursor = _entries.length - 1;
    _trimNavigationEntries();
  }

  NavigationLocation? goBack(NavigationLocation current) {
    if (!canGoBack) return null;
    _entries[_cursor] = current;
    _cursor--;
    return _entries[_cursor];
  }

  NavigationLocation? goForward(NavigationLocation current) {
    if (!canGoForward) return null;
    _entries[_cursor] = current;
    _cursor++;
    return _entries[_cursor];
  }

  void recordEdit(NavigationLocation location) {
    if (_editEntries.isNotEmpty && _editEntries.last.samePosition(location)) {
      return;
    }
    _editEntries.add(location);
    if (_editEntries.length > maxEditEntries) {
      _editEntries.removeAt(0);
    }
  }

  NavigationLocation? get lastEdit =>
      _editEntries.isEmpty ? null : _editEntries.last;

  /// Untitled buffers cannot be reopened after their final view closes.
  /// Named-file history is kept so navigation can reopen it from disk.
  void closeDocument(int documentId) {
    _editEntries.removeWhere(
      (location) => location.path == null && location.documentId == documentId,
    );
    for (var index = _entries.length - 1; index >= 0; index--) {
      final location = _entries[index];
      if (location.path != null || location.documentId != documentId) continue;
      _entries.removeAt(index);
      if (index <= _cursor) _cursor--;
    }
    if (_cursor >= _entries.length) _cursor = _entries.length - 1;
  }

  void _trimNavigationEntries() {
    final excess = _entries.length - maxNavigationEntries;
    if (excess <= 0) return;
    _entries.removeRange(0, excess);
    _cursor = (_cursor - excess).clamp(0, _entries.length - 1);
  }
}
