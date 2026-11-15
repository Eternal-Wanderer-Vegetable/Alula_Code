import 'dart:io';

import 'package:alula_app/workbench/recent_history_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late String journalPath;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('alula_recent_history');
    journalPath = '${temp.path.replaceAll(r'\', '/')}/recent-history.json';
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  test('keeps a bounded MRU list per kind and restores it after restart', () {
    final store = RecentHistoryStore(path: journalPath);
    for (var index = 0; index < maxRecentHistoryEntriesPerKind + 1; index++) {
      expect(store.recordFile('${temp.path}/file-$index.dart'), isTrue);
      expect(store.recordWorkspace('${temp.path}/workspace-$index'), isTrue);
    }
    expect(store.recordFile('${temp.path}/file-10.dart'), isTrue);

    final restored = RecentHistoryStore(path: journalPath).load();
    expect(restored.files, hasLength(maxRecentHistoryEntriesPerKind));
    expect(restored.workspaces, hasLength(maxRecentHistoryEntriesPerKind));
    expect(restored.files.first.path, '${temp.path}/file-10.dart');
    expect(restored.files.where((entry) => entry.path.endsWith('file-10.dart')),
        hasLength(1));
    expect(restored.files.last.path, '${temp.path}/file-1.dart');
    expect(restored.workspaces.first.path,
        '${temp.path}/workspace-$maxRecentHistoryEntriesPerKind');
  });

  test('corrupt and oversized journals safely load as empty', () async {
    final journal = File(journalPath);
    await journal.writeAsString('{broken');
    expect(RecentHistoryStore(path: journalPath).load().isEmpty, isTrue);

    await journal.writeAsString('x' * (maxRecentHistoryRecordBytes + 1));
    expect(RecentHistoryStore(path: journalPath).load().isEmpty, isTrue);
  });

  test('prunes missing paths and paths whose filesystem kind changed',
      () async {
    final file = File('${temp.path}/note.txt')..writeAsStringSync('hello');
    final directory = Directory('${temp.path}/project')..createSync();
    final missing = '${temp.path}/missing.txt';
    final store = RecentHistoryStore(path: journalPath);
    store.recordFile(file.path);
    store.recordFile(missing);
    store.recordWorkspace(directory.path);
    store.recordWorkspace(file.path);

    final pruned = await store.pruneMissingPaths();
    expect(pruned.files.map((entry) => entry.path), [file.absolute.path]);
    expect(pruned.workspaces.map((entry) => entry.path),
        [directory.absolute.path]);

    final restored = RecentHistoryStore(path: journalPath).load();
    expect(restored.files, pruned.files);
    expect(restored.workspaces, pruned.workspaces);
  });
}
