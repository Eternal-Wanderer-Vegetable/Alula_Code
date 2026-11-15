import 'dart:io';

import 'package:alula_app/workbench/command_history.dart';
import 'package:alula_app/workbench/command_history_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandHistory', () {
    test('records most recent first, dedupes and bounds the list', () {
      final history = CommandHistory();
      for (var i = 0; i < maxCommandHistoryEntries + 5; i++) {
        history.record('cmd.$i');
      }
      expect(history.length, maxCommandHistoryEntries);
      expect(history.commandIds.first, 'cmd.${maxCommandHistoryEntries + 4}');
      expect(history.commandIds.contains('cmd.0'), isFalse, reason: '最旧的记录被裁剪');

      history.record('cmd.10');
      expect(history.length, maxCommandHistoryEntries);
      expect(history.commandIds.first, 'cmd.10');
      expect(history.commandIds.where((id) => id == 'cmd.10').length, 1,
          reason: '重复记录只保留一份并前移');
    });

    test('ignores empty and oversized command ids', () {
      final history = CommandHistory();
      history.record('');
      history.record('x' * (maxCommandHistoryEntryLength + 1));
      expect(history.isEmpty, isTrue);
      history.record('a' * maxCommandHistoryEntryLength);
      expect(history.length, 1);
    });

    test('order puts history first and keeps the remaining order', () {
      final history = CommandHistory(commandIds: const ['b', 'missing', 'a']);
      expect(
        history.order(const ['a', 'b', 'c', 'd']),
        ['b', 'a', 'c', 'd'],
      );
    });

    test('json round-trip filters invalid entries', () {
      final history = CommandHistory.fromJson({
        'version': 1,
        'entries': [
          'valid.one',
          42,
          '',
          'x' * (maxCommandHistoryEntryLength + 1),
          'valid.two',
          'valid.one',
        ],
      });
      expect(history.commandIds, ['valid.one', 'valid.two']);

      final restored = CommandHistory.fromJson(history.toJson());
      expect(restored.commandIds, history.commandIds);

      expect(CommandHistory.fromJson(null).isEmpty, isTrue);
      expect(CommandHistory.fromJson({'version': 1}).isEmpty, isTrue);
      expect(sanitizeCommandHistoryEntries('nope'), isEmpty);
    });
  });

  group('CommandHistoryStore', () {
    late Directory temp;
    late String path;
    late CommandHistoryStore store;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('alula_cmd_history');
      path = '${temp.path.replaceAll(r'\', '/')}/command-history';
      store = CommandHistoryStore(path: path);
    });

    tearDown(() async {
      if (temp.existsSync()) await temp.delete(recursive: true);
    });

    test('round-trips the MRU order', () {
      final history = CommandHistory(commandIds: const ['cmd.a', 'cmd.b']);
      expect(store.save(history), isTrue);
      expect(File(path).existsSync(), isTrue);
      expect(store.load().commandIds, ['cmd.a', 'cmd.b']);
    });

    test('missing file loads as empty history', () {
      expect(store.load().isEmpty, isTrue);
    });

    test('corrupted or foreign payload falls back to empty history', () {
      File(path).writeAsStringSync('{not json');
      expect(store.load().isEmpty, isTrue);

      SessionStore(path: path).save({
        'format': 'alula-find-history',
        'version': 1,
        'workspace': 'workspace:test',
      });
      expect(store.load().isEmpty, isTrue, reason: '其它 journal 格式不被当成命令历史');

      SessionStore(path: path).save({
        'format': 'alula-command-history',
        'version': 2,
        'entries': ['cmd.a'],
      });
      expect(store.load().isEmpty, isTrue, reason: '未知版本回退空历史');

      SessionStore(path: path).save({
        'format': 'alula-command-history',
        'version': 1,
        'entries': ['cmd.a', 7, ''],
      });
      expect(store.load().commandIds, ['cmd.a'], reason: '非法条目被过滤，合法条目保留');
    });

    test('oversized journal is treated as corrupt', () {
      File(path).writeAsStringSync('x' * (maxCommandHistoryRecordBytes + 1));
      expect(store.load().isEmpty, isTrue);
    });
  });
}
