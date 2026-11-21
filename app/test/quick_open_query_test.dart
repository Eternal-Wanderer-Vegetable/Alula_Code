import 'dart:io';

import 'package:alula_app/workbench/quick_open_query.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('parseQuickOpenQuery', () {
    test('parses one-based colon line and column suffixes', () {
      final query = parseQuickOpenQuery('  lib/main.dart:12:7  ');
      expect(query.pathQuery, 'lib/main.dart');
      expect(query.line, 12);
      expect(query.column, 7);
      final lineOnly = parseQuickOpenQuery('file.dart:19');
      expect(lineOnly.pathQuery, 'file.dart');
      expect(lineOnly.line, 19);
      expect(lineOnly.column, isNull);
      final zero = parseQuickOpenQuery('file:0:0');
      expect(zero.line, 1);
      expect(zero.column, 1);
    });

    test('preserves Windows drives, UNC paths and other colons', () {
      for (final path in [
        r'C:\src\main.dart',
        'C:/src/main.dart',
        'C:',
        'C:12'
      ]) {
        final query = parseQuickOpenQuery(path);
        expect(query.pathQuery, path);
        expect(query.line, isNull);
        expect(query.column, isNull);
      }
      for (final path in [
        r'C:\src\main.dart',
        'C:/src/main.dart',
        r'\\server\share\main.dart',
        'dir:with:colons/file.dart',
        '😀/文件.dart',
      ]) {
        final query = parseQuickOpenQuery('$path:23:4');
        expect(query.pathQuery, path);
        expect(query.line, 23);
        expect(query.column, 4);
      }
    });

    test('leaves plain and invalid suffixes intact', () {
      for (final input in ['', 'plain', 'file:abc', 'file:12:abc', 'file:-2']) {
        final query = parseQuickOpenQuery(input);
        expect(query.pathQuery, input);
        expect(query.line, isNull);
        expect(query.column, isNull);
      }
    });
  });

  group('QuickOpenSearch', () {
    late Directory root;
    late QuickOpenSearch search;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('alula-quick-open-');
      search = QuickOpenSearch();
    });

    tearDown(() async {
      search.cancel();
      await root.delete(recursive: true);
    });

    Future<String> file(String relative) async {
      final entry = File(p.join(root.path, relative));
      await entry.parent.create(recursive: true);
      await entry.writeAsString('');
      return p.normalize(entry.path);
    }

    test('all 431 files are reachable through bounded, disjoint pages',
        () async {
      final expected = <String>{};
      for (var i = 0; i < 431; i++) {
        expected.add(await file('dir${i % 3}/item_$i.txt'));
      }
      final first = await search.search(root.path, 'itm');
      final second = await search.search(root.path, 'itm', page: 1);
      final third = await search.search(root.path, 'itm', page: 2);
      final fourth = await search.search(root.path, 'itm', page: 3);
      expect(first, hasLength(200));
      expect(second, hasLength(200));
      expect(third, hasLength(31));
      expect(fourth, isEmpty);
      final all = [...first, ...second, ...third];
      expect(all.toSet(), expected);
      expect(all.toSet(), hasLength(all.length));
      // A skipped-page request must work without a preceding page-zero scan.
      expect(await QuickOpenSearch().search(root.path, 'itm', page: 2), third);
    });

    test('next-page state uses actual lookahead at the exact page boundary',
        () async {
      for (var i = 0; i < QuickOpenSearch.pageSize; i++) {
        await file('item-$i.txt');
      }
      expect(await search.search(root.path, 'item'), hasLength(200));
      expect(search.hasMore, isFalse);
      await file('item-extra.txt');
      expect(await search.search(root.path, 'item'), hasLength(200));
      expect(search.hasMore, isTrue);
      expect(await search.search(root.path, 'item', page: 1), hasLength(1));
      expect(search.hasMore, isFalse);
    });

    test('resolves absolute files outside even an unavailable root', () async {
      final path = await file('outside.dart');
      final result =
          await search.search(p.join(root.path, 'missing-root'), '$path:15:3');
      expect(result, [path]);
      expect(await search.search(root.path, path, page: 1), isEmpty);
      expect(await search.search(root.path, p.join(root.path, 'absent.dart')),
          isEmpty);
    });

    test('resolves relative paths and normalizes both separators', () async {
      final path = await file('lib/sub/main.dart');
      expect(
          await search.search(root.path, r'.\lib\sub\main.dart:7:2'), [path]);
      expect(await search.search(root.path, './lib/sub/main.dart'), [path]);
    });

    test('matches filename and relative path fuzzily without case sensitivity',
        () async {
      final main = await file('lib/widgets/QuickOpenWidget.dart');
      await file('lib/unrelated.txt');
      expect(await search.search(root.path, 'QOW'), [main]);
      expect(await search.search(root.path, 'LW/QOW'), [main]);
      expect(await search.search(root.path, r'lw\qow'), [main]);
      expect(await search.search(root.path, 'nonmatching'), isEmpty);
    });

    test('MRU preserves order, deduplicates normalized paths, skips missing',
        () async {
      final first = await file('one.dart');
      final second = await file('sub/two.dart');
      final third = await file('three.dart');
      final recent = [
        second,
        'sub/two.dart',
        first,
        p.join(root.path, '.', 'one.dart'),
        'missing.dart',
      ];
      expect(await search.search(root.path, '', recentPaths: recent),
          [second, first, third]);
      expect(
          await search.search(root.path, 'tw', recentPaths: recent), [second]);
      expect(await search.search(root.path, 'one.dart', recentPaths: recent),
          [first]);
    });

    test('MRU and direct paths do not duplicate across page boundaries',
        () async {
      final recent = <String>[];
      for (var i = 0; i < 205; i++) {
        recent.add(await file('item$i.txt'));
      }
      final first = await search.search(root.path, '', recentPaths: recent);
      final second =
          await search.search(root.path, '', recentPaths: recent, page: 1);
      expect(first, recent.take(200).toList());
      expect(second, recent.skip(200).toList());
    });

    test('excludes .git before descending and does not follow directory links',
        () async {
      final visible = await file('src/visible.txt');
      await file('.git/hidden.txt');
      await file('nested/.git/also-hidden.txt');
      expect(await search.search(root.path, ''), [visible]);
      // Creating symlinks needs a privilege on Windows. Exercise the link
      // invariant on platforms that allow them without elevated permissions.
      if (!Platform.isWindows) {
        await Link(p.join(root.path, 'cycle')).create(root.path);
        await Link(p.join(root.path, 'file-link')).create(visible);
        expect(await search.search(root.path, ''), [visible]);
      }
    });

    test('reports inaccessible roots and invalid pages explicitly', () async {
      await expectLater(search.search(p.join(root.path, 'absent'), ''),
          throwsA(isA<FileSystemException>()));
      await expectLater(search.search(root.path, '', page: -1),
          throwsA(isA<ArgumentError>()));
    });

    test('cancel discards pending results, and a later call still works',
        () async {
      final path = await file('new.dart');
      final pending = search.search(root.path, 'dart');
      search.cancel();
      expect(await pending, isEmpty);
      expect(await search.search(root.path, 'new'), [path]);
    });

    test('cancels an asynchronous directory scan', () async {
      for (var i = 0; i < 300; i++) {
        await file('item$i.txt');
      }
      // An empty query enters Directory.list without a direct File.exists.
      final pending = search.search(root.path, '');
      await Future<void>.delayed(Duration.zero);
      search.cancel();
      expect(await pending, isEmpty);
      expect(await search.search(root.path, 'item299.txt'),
          contains(p.join(root.path, 'item299.txt')));
    });

    test('reports the directory depth cap instead of silently truncating',
        () async {
      // Directory.list on Windows needs an extended-length path to reach
      // 129 nested levels rather than failing first at legacy MAX_PATH.
      if (Platform.isWindows) root = Directory(r'\\?\' + root.path);
      await file('${List.filled(129, 'd').join('/')}/leaf.txt');
      await expectLater(
          search.search(root.path, ''),
          throwsA(isA<FileSystemException>().having((error) => error.message,
              'message', contains('depth exceeds 128'))));
    });

    test('only the newest concurrent query returns results', () async {
      await file('old.dart');
      final newestPath = await file('new.dart');
      final old = search.search(root.path, 'old');
      final newest = search.search(root.path, 'new');
      expect(await old, isEmpty);
      expect(await newest, [newestPath]);
    });

    test('does not retain file results between calls', () async {
      final previous = await file('previous.dart');
      expect(await search.search(root.path, ''), [previous]);
      await File(previous).delete();
      final next = await file('next.dart');
      expect(await search.search(root.path, ''), [next]);
    });
  });
}
