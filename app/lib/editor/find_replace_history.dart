/// Find and replace query history behavior aligned with Code-OSS 1.145.0.
const int maxFindReplaceHistoryEntries = 100;
const int maxFindReplaceHistoryEntryUtf16 = 524288;

enum FindReplaceHistoryScope { never, workspace }

class FindReplaceHistoryConfiguration {
  const FindReplaceHistoryConfiguration({
    this.findScope = FindReplaceHistoryScope.workspace,
    this.replaceScope = FindReplaceHistoryScope.workspace,
  });

  final FindReplaceHistoryScope findScope;
  final FindReplaceHistoryScope replaceScope;

  factory FindReplaceHistoryConfiguration.fromSettings(
    Map<String, Object?> settings,
  ) {
    FindReplaceHistoryScope parse(String key) => settings[key] == 'never'
        ? FindReplaceHistoryScope.never
        : FindReplaceHistoryScope.workspace;

    return FindReplaceHistoryConfiguration(
      findScope: parse('editor.find.history'),
      replaceScope: parse('editor.find.replaceHistory'),
    );
  }
}

/// A bounded MRU navigator. Entries are ordered oldest to newest; Up walks
/// backward and Down returns to the value that was being typed before browsing.
class FindReplaceHistoryNavigator {
  FindReplaceHistoryNavigator({Iterable<String> entries = const []}) {
    replaceEntries(entries);
  }

  List<String> _entries = <String>[];
  int _cursor = 0;
  String? _draft;

  List<String> get entries => List<String>.unmodifiable(_entries);

  void replaceEntries(Iterable<String> entries) {
    _entries = _boundedDistinctEntries(entries);
    _cursor = _entries.length;
    _draft = null;
  }

  /// Adds a nonempty query and promotes duplicates to the newest position.
  /// Returns true when the MRU order changed.
  bool record(String value) {
    if (value.isEmpty || value.length > maxFindReplaceHistoryEntryUtf16) {
      return false;
    }
    final previousIndex = _entries.indexOf(value);
    final alreadyNewest = previousIndex == _entries.length - 1;
    if (previousIndex >= 0) _entries.removeAt(previousIndex);
    _entries.add(value);
    if (_entries.length > maxFindReplaceHistoryEntries) {
      _entries.removeAt(0);
    }
    _cursor = _entries.length;
    _draft = value;
    return previousIndex < 0 || !alreadyNewest;
  }

  /// Marks a user edit as the new draft and leaves history browsing mode.
  void noteEdit(String value) {
    _cursor = _entries.length;
    _draft = value;
  }

  String? previous(String currentValue) {
    if (_entries.isEmpty) return null;
    if (_cursor == _entries.length) _draft = currentValue;
    if (_cursor == 0) return _entries.first;
    _cursor--;
    return _entries[_cursor];
  }

  String? next() {
    if (_entries.isEmpty || _cursor >= _entries.length) return null;
    _cursor++;
    if (_cursor == _entries.length) return _draft ?? '';
    return _entries[_cursor];
  }
}

List<String> _boundedDistinctEntries(Iterable<String> entries) {
  final recent = <String>[];
  for (final value in entries) {
    if (value.isEmpty || value.length > maxFindReplaceHistoryEntryUtf16) {
      continue;
    }
    recent.remove(value);
    recent.add(value);
    if (recent.length > maxFindReplaceHistoryEntries) recent.removeAt(0);
  }
  return recent;
}
