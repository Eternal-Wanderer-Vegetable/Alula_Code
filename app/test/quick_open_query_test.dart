import 'dart:io';

import 'package:alula_app/workbench/quick_open_query.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('Quick Open file highlights', () {
    Map<String, List<String>> highlighted(
      String query,
      String label, {
      String? description,
      String? path,
    }) {
      final matches = QuickOpenFileHighlighter(
        parseQuickOpenQuery(query).pathQuery,
      ).find(
        path: path ?? p.absolute(label),
        label: label,
        description: description,
      );
      return {
        'name': [
          for (final r in matches.label) label.substring(r.start, r.end)
        ],
        'directory': [
          for (final r in matches.description)
            description!.substring(r.start, r.end),
        ],
      };
    }

    test('prefers the name and merges repeated terms in both columns', () {
      final directory = p.join('lib', 'needle');
      expect(
          highlighted('nee lib nee*', 'needle.dart', description: directory), {
        'name': ['nee'],
        'directory': ['lib']
      });
      expect(highlighted('ndl', 'needle.dart', description: directory), {
        'name': ['n', 'dl'],
        'directory': <String>[]
      });
      expect(highlighted('.', 'needle.dart', description: directory),
          {'name': <String>[], 'directory': <String>[]});
    });

    test('highlights a qualified query on both sides of the visible separator',
        () {
      final directory = p.join('lib', 'deep');
      expect(
        highlighted('lib/deep/needle:2:3', 'needle.dart',
            description: directory),
        {
          'name': ['needle'],
          'directory': [directory]
        },
      );
      final exact = p.absolute('outside', 'needle.dart');
      final parent = p.dirname(exact);
      expect(
        highlighted('$exact:2:3', 'needle.dart',
            description: parent, path: exact),
        {
          'name': ['needle.dart'],
          'directory': [parent]
        },
      );
    });

    test('uses contiguous matches for quotes beyond the fuzzy window', () {
      expect(highlighted('"fix"', 'fizz_fix.dart'), {
        'name': ['fix'],
        'directory': <String>[]
      });
      expect(highlighted('"nd"', 'needle.dart'),
          {'name': <String>[], 'directory': <String>[]});
      expect(highlighted('"fix"', 'a' * 150 + 'fix.dart'), {
        'name': ['fix'],
        'directory': <String>[]
      });
    });

    test('maps case expansion and leaves surrogate pairs intact', () {
      expect(highlighted('z', 'İ😀z.dart'), {
        'name': ['z'],
        'directory': <String>[]
      });
      expect(highlighted('\u0307', 'İ😀z.dart'), {
        'name': ['İ'],
        'directory': <String>[]
      });
      final prefix = 'a' * 127 + '😀';
      expect(highlighted(prefix, '$prefix.dart'), {
        'name': [prefix],
        'directory': <String>[]
      });
    });
  });

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

    test('recognizes file positions and ranges with the reference separators',
        () {
      const path = r'C:\projects\文件 (draft)\notes.txt';
      for (final suffix in [
        '#20#3-40,5',
        '(20,3-40,5)',
        ' (20,3-40,5)',
        ':line 20:3-40:5',
      ]) {
        final query = parseQuickOpenQuery('$path$suffix');
        expect(query.pathQuery, path);
        expect(query.line, 20);
        expect(query.column, 3);
        expect(query.endLine, 40);
        expect(query.endColumn, 5);
      }

      final lineRange = parseQuickOpenQuery('file.txt:20-40');
      expect(lineRange.column, isNull);
      expect(lineRange.endLine, 40);
      expect(lineRange.endColumn, isNull);
      for (final suffix in [':8:', '#8-', ' (8,)', ':line 8']) {
        final query = parseQuickOpenQuery('file.txt$suffix');
        expect(query.pathQuery, 'file.txt');
        expect(query.line, 8);
        expect(query.column, isNull);
        expect(query.endLine, isNull);
      }
      for (final suffix in [':', '#']) {
        final query = parseQuickOpenQuery('file.txt$suffix');
        expect(query.pathQuery, 'file.txt');
        expect(query.line, 1);
        expect(query.column, isNull);
      }
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

  test('Quick Open describes the parent relative to its workspace or home', () {
    final parent = p.normalize(Directory.systemTemp.path);
    final workspace = p.join(parent, 'Workspace');
    final nested = p.join(workspace, 'Lib', 'Nested', 'code.txt');
    final outside = p.join(parent, 'Workspace-other', 'other.txt');

    expect(
        quickOpenDirectoryLabel(p.join(workspace, 'file.txt'),
            workspace: workspace),
        isNull);
    expect(quickOpenDirectoryLabel(nested, workspace: workspace),
        p.join('Lib', 'Nested'));
    expect(quickOpenDirectoryLabel(outside, workspace: workspace),
        p.dirname(outside));
    expect(quickOpenDirectoryLabel(nested), p.dirname(nested));
    expect(
      quickOpenDirectoryLabel(outside, workspace: workspace, userHome: parent),
      Platform.isWindows ? p.dirname(outside) : p.join('~', 'Workspace-other'),
    );
    expect(
        quickOpenDirectoryLabel(p.join(parent, 'home.txt'),
            workspace: workspace, userHome: parent),
        parent);

    final differentlyCasedWorkspace = p.join(parent, 'WORKSPACE');
    expect(
      quickOpenDirectoryLabel(nested, workspace: differentlyCasedWorkspace),
      Platform.isWindows || Platform.isMacOS
          ? p.join('Lib', 'Nested')
          : p.dirname(nested),
    );
    if (Platform.isWindows) {
      expect(quickOpenDirectoryLabel(r'c:\other\file.txt'), r'C:\other');
    }
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

    test('prefers filename prefixes, then filename matches, then paths',
        () async {
      final pathMatch = await file('needle/plain.txt');
      final insideName = await file('src/part-needle-note.txt');
      final longPrefix = await file('pkg/needle-custom-description.txt');
      final shortPrefix = await file('pkg/needle-a.txt');
      expect(await search.search(root.path, 'needle'),
          [shortPrefix, longPrefix, insideName, pathMatch]);
      expect(
        await search.search(root.path, 'needle', recentPaths: [pathMatch]),
        [pathMatch, shortPrefix, longPrefix, insideName],
      );
      expect(await search.search(root.path, 'needle/plain'), [pathMatch]);
      expect(await search.search(root.path, pathMatch), [pathMatch]);
    });

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

    test('requires every search term across filename and relative path',
        () async {
      final match = await file('engine/line-parser.txt');
      final recentMatch = await file('engine/config-parser.txt');
      final filenameOnly = await file('archive/line-parser.txt');
      final directoryOnly = await file('engine/status.txt');

      expect(await search.search(root.path, 'PARSER egn'),
          unorderedEquals([match, recentMatch]));
      expect(await search.search(root.path, 'parser engine absent'), isEmpty);

      final early = <List<QuickOpenMatch>>[];
      final results = await search.searchMatches(
        root.path,
        'ENGINE   parser:2:3',
        recentPaths: [filenameOnly, recentMatch, directoryOnly],
        onRecentMatches: early.add,
      );
      expect(early, [
        [(path: recentMatch, recent: true)],
      ]);
      expect(results, [
        (path: recentMatch, recent: true),
        (path: match, recent: false),
      ]);

      final literal = await file('engine tools/line parser.txt');
      expect(await search.search(root.path, 'engine tools/line parser.txt'),
          [literal]);
    });

    test('only a closed quoted term requires contiguous characters', () async {
      final exact = await file('engine/line-parser.txt');
      final fuzzy = await file('engine/p-a-r-s-e-r.txt');
      final otherDirectory = await file('archive/line-parser.txt');
      final recent = [fuzzy, exact];

      expect(
          await search.search(root.path, 'engine "parser', recentPaths: recent),
          [fuzzy, exact]);
      expect(
          await search.search(root.path, 'engine "PARSER":2:3',
              recentPaths: recent),
          [exact]);
      expect(await search.search(root.path, '" parser "'),
          unorderedEquals([exact, otherDirectory]));
      expect(
          await search.search(root.path, '""', recentPaths: recent), isEmpty);
    });

    test('quoted path terms can match beyond the fuzzy scoring window',
        () async {
      final path = await file('a' * 135 + '/engine-marker/source.txt');
      expect(await search.search(root.path, '"engine-marker"'), [path]);
    });

    test('normalizes file query markers while retaining literal paths',
        () async {
      final matching = await file('engine/parse-driver.txt');
      await file('engine/log.txt');
      await file('archive/parse-driver.txt');

      expect(
          await search.search(root.path, 'ENG…INE parse-*driver#'), [matching]);
      expect(await search.search(root.path, 'engi\tne "parse-*driver#"'),
          [matching]);
      expect(await search.search(root.path, '*… \t'), isEmpty);

      final literal = await file('engine tools/version…#');
      await file('engine tools/version-info.txt');
      final results =
          await search.search(root.path, 'engine tools/version…#:1:2');
      expect(results.first, literal);
      expect(results.where((path) => path == literal), hasLength(1));
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

    test('recent-only results skip file probing and workspace traversal',
        () async {
      final recent = await file('recent.txt');
      final unopened = await file('unopened.txt');
      final missingRoot = p.join(root.path, 'missing-root');
      final hits = await search.searchMatches(
        missingRoot,
        '',
        recentPaths: [recent, p.join(root.path, 'stale.txt')],
        includeFileResults: false,
      );
      expect(hits, [(path: recent, recent: true)]);
      expect(search.hasMore, isFalse);
      expect(
        await search.searchMatches(
          root.path,
          unopened,
          includeFileResults: false,
        ),
        isEmpty,
      );
    });

    test('publishes recent matches before walking the workspace', () async {
      final recent = await file('needle-recent.txt');
      final lateFile = p.join(root.path, 'needle-workspace.txt');
      final partial = <QuickOpenMatch>[];
      final matches = await search.searchMatches(
        root.path,
        'needle',
        recentPaths: [recent],
        onRecentMatches: (recentMatches) {
          partial.addAll(recentMatches);
          File(lateFile).writeAsStringSync('made after the recent result');
        },
      );
      expect(partial, [(path: recent, recent: true)]);
      expect(matches, [
        (path: recent, recent: true),
        (path: lateFile, recent: false),
      ]);
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
