import 'package:alula_app/editor/find_replace_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FindReplaceHistoryConfiguration', () {
    test('defaults to workspace history and accepts never settings', () {
      const defaults = FindReplaceHistoryConfiguration();
      expect(defaults.findScope, FindReplaceHistoryScope.workspace);
      expect(defaults.replaceScope, FindReplaceHistoryScope.workspace);

      final configured = FindReplaceHistoryConfiguration.fromSettings({
        'editor.find.history': 'never',
        'editor.find.replaceHistory': 'workspace',
      });
      expect(configured.findScope, FindReplaceHistoryScope.never);
      expect(configured.replaceScope, FindReplaceHistoryScope.workspace);
    });

    test('unknown setting values keep the workspace default', () {
      final configured = FindReplaceHistoryConfiguration.fromSettings({
        'editor.find.history': 'global',
        'editor.find.replaceHistory': false,
      });
      expect(configured.findScope, FindReplaceHistoryScope.workspace);
      expect(configured.replaceScope, FindReplaceHistoryScope.workspace);
    });
  });

  group('FindReplaceHistoryNavigator', () {
    test('Up and Down browse newest first and restore the typed draft', () {
      final history = FindReplaceHistoryNavigator(entries: ['old', 'new']);

      expect(history.previous('draft'), 'new');
      expect(history.previous('new'), 'old');
      expect(history.previous('old'), 'old');
      expect(history.next(), 'new');
      expect(history.next(), 'draft');
      expect(history.next(), isNull);
    });

    test('duplicate queries move to the newest position', () {
      final history = FindReplaceHistoryNavigator(entries: ['one', 'two']);
      expect(history.record('one'), isTrue);
      expect(history.entries, ['two', 'one']);
      expect(history.record('one'), isFalse);
      expect(history.entries, ['two', 'one']);
    });

    test('history is capped at 100 bounded UTF-16 queries', () {
      final history = FindReplaceHistoryNavigator(
        entries: List<String>.generate(101, (index) => 'q$index'),
      );
      expect(history.entries, hasLength(maxFindReplaceHistoryEntries));
      expect(history.entries.first, 'q1');
      expect(history.entries.last, 'q100');

      expect(history.record('🙂' * maxFindReplaceHistoryEntryUtf16), isFalse);
      expect(history.record(''), isFalse);
      expect(history.entries, hasLength(maxFindReplaceHistoryEntries));
    });
  });
}
