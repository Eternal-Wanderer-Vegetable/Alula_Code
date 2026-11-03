import 'dart:io';

import 'package:alula_app/editor/find_replace_history.dart';
import 'package:alula_app/workbench/find_history_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late FindReplaceHistoryStore store;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('alula-find-history-store-');
    store = FindReplaceHistoryStore(directory: '${temp.path}/history');
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('persists independent bounded histories per workspace', () {
    expect(
      store.save('/workspace/a', find: ['needle'], replace: ['token']),
      isTrue,
    );
    expect(store.load('/workspace/a').find, ['needle']);
    expect(store.load('/workspace/a').replace, ['token']);
    expect(store.load('/workspace/b').find, isEmpty);

    expect(store.save('/workspace/a', find: ['new', 'needle']), isTrue);
    expect(store.load('/workspace/a').find, ['new', 'needle']);
    expect(store.load('/workspace/a').replace, ['token']);
  });

  test('malformed journal falls back to empty history', () {
    store.save('/workspace/a', find: ['needle']);
    final record = Directory('${temp.path}/history')
        .listSync()
        .whereType<File>()
        .singleWhere((file) => file.path.endsWith('.json'));
    record.writeAsStringSync('{invalid');

    expect(store.load('/workspace/a').find, isEmpty);
  });

  test('caps the list and ignores entries above the UTF-16 length limit', () {
    final tooLong = 'x' * (maxFindReplaceHistoryEntryUtf16 + 1);
    final entries = [
      tooLong,
      ...List<String>.generate(101, (index) => 'q$index'),
    ];
    expect(store.save('/workspace/a', find: entries), isTrue);
    final loaded = store.load('/workspace/a').find;
    expect(loaded, hasLength(maxFindReplaceHistoryEntries));
    expect(loaded.first, 'q1');
    expect(loaded.last, 'q100');
  });

  test('caps retained workspaces', () {
    for (var index = 0; index < maxFindHistoryWorkspaceRecords + 1; index++) {
      expect(store.save('/workspace/$index', find: ['q$index']), isTrue);
    }
    final records = Directory('${temp.path}/history')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.json'));
    expect(records.length, lessThanOrEqualTo(maxFindHistoryWorkspaceRecords));
    expect(store.load('/workspace/$maxFindHistoryWorkspaceRecords').find,
        ['q$maxFindHistoryWorkspaceRecords']);
  });
}
