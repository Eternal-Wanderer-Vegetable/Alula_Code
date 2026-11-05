import 'package:alula_app/editor/navigation_history.dart';
import 'package:flutter_test/flutter_test.dart';

NavigationLocation _location(
  String name, {
  int documentId = 1,
  String group = 'editor',
  int line = 0,
  int character = 0,
  int version = 1,
}) =>
    NavigationLocation(
      uri: name.startsWith('file:')
          ? name
          : name.startsWith('/')
              ? 'file://$name'
              : null,
      path: name.startsWith('/') ? name : null,
      documentId: documentId,
      groupRegion: group,
      line: line,
      character: character,
      version: version,
    );

void main() {
  test('back and forward preserve locations and branch after a new jump', () {
    final history = NavigationHistory();
    final first = _location('file:///workspace/main.rs', character: 2);
    final second = _location('file:///workspace/lib.rs', group: 'editor-2');
    final third = _location('file:///workspace/other.rs', line: 3);
    final branch = _location('file:///workspace/new.rs', line: 9);

    history.recordNavigation(first, second);
    history.recordNavigation(second, third);
    expect(history.goBack(third)?.uri, second.uri);
    expect(history.goBack(second)?.uri, first.uri);
    expect(history.canGoBack, isFalse);
    expect(history.goForward(first)?.uri, second.uri);
    history.recordNavigation(second, branch);
    expect(history.canGoForward, isFalse);
    expect(history.goBack(branch)?.uri, second.uri);
  });

  test('closed named files remain reopenable; closed untitled docs are pruned',
      () {
    final history = NavigationHistory();
    final named = _location('/workspace/main.rs', documentId: 10);
    final otherNamed = _location('/workspace/other.rs', documentId: 12);
    final untitled = _location('untitled', documentId: 11);
    history.recordNavigation(named, otherNamed);
    history.closeDocument(12);
    expect(history.goBack(otherNamed)?.canReopen, isTrue);

    history.recordEdit(untitled);
    history.closeDocument(11);
    expect(history.lastEdit, isNull);
  });

  test('navigation and edit stacks have fixed bounds', () {
    final history =
        NavigationHistory(maxNavigationEntries: 4, maxEditEntries: 2);
    var previous = _location('file:///workspace/0.rs');
    for (var i = 1; i < 7; i++) {
      final next = _location('file:///workspace/$i.rs');
      history.recordNavigation(previous, next);
      history.recordEdit(next);
      previous = next;
    }
    expect(history.canGoBack, isTrue);
    expect(history.lastEdit?.uri, 'file:///workspace/6.rs');
    expect(history.goBack(previous)?.uri, 'file:///workspace/5.rs');
  });
}
