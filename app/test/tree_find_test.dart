import 'dart:io';

import 'package:alula_app/workbench/tree_find.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/file_paths.dart';

void main() {
  test('find matches fuzzy or contiguous labels including Unicode', () {
    expect(matchesTreeFind('mrs', 'main.rs', fuzzy: true), isTrue);
    expect(matchesTreeFind('mrs', 'main.rs', fuzzy: false), isFalse);
    expect(matchesTreeFind('MAIN', 'main.rs', fuzzy: false), isTrue);
    expect(matchesTreeFind('😀文', '😀中文.txt', fuzzy: true), isTrue);
    expect(matchesTreeFind('42', 'file-42.rs', fuzzy: false), isTrue);
  });

  test('highlight ranges are UTF-16 offsets of the matched characters', () {
    final fuzzy = treeFindMatchRanges('mrs', 'main.rs', fuzzy: true)!;
    expect(fuzzy.map((range) => (range.start, range.end)), [(0, 1), (5, 7)]);
    final unicode = treeFindMatchRanges('😀文', '😀中文.txt', fuzzy: true)!;
    expect(unicode.map((range) => (range.start, range.end)), [(0, 2), (3, 4)]);
    expect(
        treeFindLabel('mrs', 'main.rs', fuzzy: true).toPlainText(), 'main.rs');
  });

  test('query history restores drafts and clears across workspaces', () {
    final controller = TreeFindController();
    controller.setQuery('first');
    controller.rememberQuery();
    controller.setQuery('second');
    controller.rememberQuery();
    controller.setQuery('draft');
    expect(controller.navigateHistory(previous: true), isTrue);
    expect(controller.query, 'second');
    expect(controller.navigateHistory(previous: true), isTrue);
    expect(controller.query, 'first');
    expect(controller.navigateHistory(previous: false), isTrue);
    expect(controller.query, 'second');
    expect(controller.navigateHistory(previous: false), isTrue);
    expect(controller.query, 'draft');
    expect(controller.navigateHistory(previous: false), isFalse);
    controller.workspaceChanged(null);
    expect(controller.navigateHistory(previous: true), isFalse);
    controller.dispose();
  });

  test('filter finds unloaded descendants and close remembers only the query',
      () async {
    final temp = await Directory.systemTemp.createTemp('tree-find');
    final nested =
        await Directory('${temp.path}/nested/deep').create(recursive: true);
    final file = await File('${nested.path}/main.rs').writeAsString('😀\r\n');
    final controller = TreeFindController();
    addTearDown(() async {
      controller.dispose();
      await temp.delete(recursive: true);
    });
    controller.open(temp.path);
    expect(controller.filter, isFalse);
    expect(controller.fuzzy, isTrue);
    controller.toggleFilter();
    controller.setQuery('mrs');
    while (controller.loading) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(controller.paths, [nativeTestPath(file.path)]);
    controller.close();
    expect(controller.paths, isEmpty);
    expect(controller.query, isEmpty);
    controller.open(temp.path);
    expect(controller.input.text, 'mrs');
    controller.workspaceChanged(null);
    expect(controller.isOpen, isFalse);
    expect(controller.paths, isEmpty);
  });

  test('closing an in-flight search rejects stale results', () async {
    final temp = await Directory.systemTemp.createTemp('tree-find-cancel');
    for (var i = 0; i < 40; i++) {
      File('${temp.path}/note-$i.txt').writeAsStringSync('');
    }
    final controller = TreeFindController();
    controller.open(temp.path);
    controller.toggleFilter();
    controller.setQuery('note');
    controller.close();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(controller.paths, isEmpty);
    expect(controller.loading, isFalse);
    expect(controller.hasMore, isFalse);
    controller.dispose();
    await temp.delete(recursive: true);
  });

  test('unreadable root reports an error instead of keeping pending state',
      () async {
    final temp = await Directory.systemTemp.createTemp('tree-find-error');
    final controller = TreeFindController();
    controller.open('${temp.path}/missing');
    controller.toggleFilter();
    controller.setQuery('note');
    for (var i = 0; i < 100 && controller.loading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(controller.error, isNotNull);
    expect(controller.loading, isFalse);
    expect(controller.paths, isEmpty);
    controller.dispose();
    await temp.delete(recursive: true);
  });

  test('folder matches exclude git internals before traversal', () async {
    final temp = await Directory.systemTemp.createTemp('tree-find-folders');
    final directory = await Directory('${temp.path}/matching-folder').create();
    await Directory('${temp.path}/.git').create();
    await File('${temp.path}/.git/matching-secret').writeAsString('');
    final controller = TreeFindController();
    controller.open(temp.path);
    controller.toggleFilter();
    controller.setQuery('matching');
    for (var i = 0; i < 100 && controller.loading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(controller.paths, [nativeTestPath(directory.path)]);
    expect(controller.entries.single.isDirectory, isTrue);
    controller.dispose();
    await temp.delete(recursive: true);
  });

  test('UTF-16 query limit never splits a surrogate pair or hides truncation',
      () {
    final controller = TreeFindController();
    controller.setQuery('${'x' * 255}😀');
    expect(controller.query, 'x' * 255);
    expect(controller.input.text, controller.query);
    controller.dispose();
  });

  test('exactly one page does not offer a destructive empty next page',
      () async {
    final temp = await Directory.systemTemp.createTemp('tree-find-exact-page');
    for (var i = 0; i < TreeFindController.pageSize; i++) {
      File('${temp.path}/note-$i.txt').writeAsStringSync('');
    }
    final controller = TreeFindController();
    controller.open(temp.path);
    controller.toggleFilter();
    controller.setQuery('note');
    for (var i = 0; i < 100 && controller.loading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(controller.paths, hasLength(TreeFindController.pageSize));
    expect(controller.hasMore, isFalse);
    await controller.loadMore();
    expect(controller.paths, hasLength(TreeFindController.pageSize));
    controller.dispose();
    await temp.delete(recursive: true);
  });

  test('paging bounds retained paths and keeps later matches reachable',
      () async {
    final temp = await Directory.systemTemp.createTemp('tree-find-pages');
    for (var i = 0; i < TreeFindController.pageSize + 3; i++) {
      File('${temp.path}/match-$i.txt').writeAsStringSync('');
    }
    final controller = TreeFindController();
    addTearDown(() async {
      controller.dispose();
      await temp.delete(recursive: true);
    });
    controller.open(temp.path);
    controller.toggleFilter();
    controller.setQuery('match');
    while (controller.loading) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(controller.paths, hasLength(TreeFindController.pageSize));
    expect(controller.hasMore, isTrue);
    final firstPage = controller.paths.toSet();
    await controller.loadMore();
    expect(controller.paths, hasLength(3));
    expect(firstPage.intersection(controller.paths.toSet()), isEmpty);
    expect(controller.hasMore, isFalse);
    expect(File('${temp.path}/match-0.txt').readAsStringSync(), isEmpty);
  });
}
