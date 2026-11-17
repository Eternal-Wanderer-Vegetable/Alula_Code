import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'tree_fuzzy_score.dart';

class TreeFindEntry {
  const TreeFindEntry(this.path, {required this.isDirectory});
  final String path;
  final bool isDirectory;
}

/// One asynchronous cursor and one bounded result page per tree. Closing keeps
/// the query, not the workspace results or a background directory scan.
class TreeFindController extends ChangeNotifier {
  static const pageSize = 200;
  static const maxQueryLength = 256;
  static const maxDirectoryDepth = 128;

  final input = TextEditingController();
  final inputFocus = FocusNode(debugLabel: 'tree-find-input');
  bool isOpen = false;
  bool filter = false;
  bool fuzzy = true;
  bool loading = false;
  bool hasMore = false;
  String query = '';
  String? error;
  final List<TreeFindEntry> entries = [];
  List<String> get paths => entries.map((entry) => entry.path).toList();
  String? _root;
  String _previousQuery = '';
  final List<String> _history = [];
  int _historyIndex = -1;
  String _historyDraft = '';
  StreamIterator<TreeFindEntry>? _iterator;
  TreeFindEntry? _lookahead;
  int _generation = 0;
  bool _disposed = false;

  bool matches(String name) => matchesTreeFind(query, name, fuzzy: fuzzy);

  void open(String? root) {
    _root = root;
    if (!isOpen) {
      isOpen = true;
      input.text = _previousQuery;
      setQuery(input.text);
    }
    input.selection =
        TextSelection(baseOffset: 0, extentOffset: input.text.length);
    notifyListeners();
  }

  void close() {
    rememberQuery();
    _previousQuery = query;
    isOpen = false;
    query = '';
    input.clear();
    _cancel();
    entries.clear();
    error = null;
    notifyListeners();
  }

  void workspaceChanged(String? root) {
    _root = root;
    close();
    _previousQuery = '';
    _history.clear();
    _historyIndex = -1;
    _historyDraft = '';
  }

  void rememberQuery() {
    if (query.isEmpty) return;
    _history.remove(query);
    _history.insert(0, query);
    if (_history.length > 20) _history.removeLast();
    _historyIndex = -1;
  }

  bool navigateHistory({required bool previous}) {
    if (previous) {
      if (_history.isEmpty || _historyIndex + 1 >= _history.length) {
        return false;
      }
      if (_historyIndex < 0) _historyDraft = query;
      _historyIndex++;
      setQuery(_history[_historyIndex]);
    } else {
      if (_historyIndex < 0) return false;
      _historyIndex--;
      setQuery(_historyIndex < 0 ? _historyDraft : _history[_historyIndex]);
    }
    input.selection =
        TextSelection(baseOffset: 0, extentOffset: input.text.length);
    return true;
  }

  void setQuery(String value) {
    var end = value.length.clamp(0, maxQueryLength);
    if (end < value.length &&
        end > 0 &&
        value.codeUnitAt(end - 1) >= 0xD800 &&
        value.codeUnitAt(end - 1) <= 0xDBFF) {
      end--;
    }
    query = value.substring(0, end);
    if (input.text != query) {
      input.value = TextEditingValue(
          text: query,
          selection: TextSelection.collapsed(offset: query.length));
    }
    _restart();
  }

  void toggleFilter() {
    filter = !filter;
    _restart();
  }

  void toggleFuzzy() {
    fuzzy = !fuzzy;
    _restart();
  }

  void _cancel() {
    _generation++;
    final iterator = _iterator;
    _iterator = null;
    _lookahead = null;
    if (iterator != null) unawaited(iterator.cancel());
    loading = false;
    hasMore = false;
  }

  Stream<TreeFindEntry> _walk(String root, int generation) async* {
    Future<bool> current() async => !_disposed && generation == _generation;
    Stream<TreeFindEntry> visit(String directory, int depth) async* {
      if (depth > maxDirectoryDepth) {
        throw const FileSystemException('目录深度超过 128 层，请打开较小的工作区');
      }
      await for (final entity
          in Directory(directory).list(followLinks: false)) {
        if (!await current()) return;
        if (entity is Directory && p.basename(entity.path) == '.git') continue;
        final type = entity is Link
            ? await FileSystemEntity.type(entity.path)
            : entity is Directory
                ? FileSystemEntityType.directory
                : FileSystemEntityType.file;
        if (!await current()) return;
        if (type == FileSystemEntityType.notFound) continue;
        yield TreeFindEntry(entity.path,
            isDirectory: type == FileSystemEntityType.directory);
        if (entity is Directory) {
          try {
            yield* visit(entity.path, depth + 1);
          } on FileSystemException catch (failure) {
            if (await current()) {
              error = '部分目录未搜索：${failure.message}';
            }
          }
        }
      }
    }

    yield* visit(root, 0);
  }

  void _restart() {
    _cancel();
    entries.clear();
    error = null;
    final root = _root;
    if (isOpen && filter && query.isNotEmpty && root != null) {
      _iterator = StreamIterator(_walk(root, _generation));
      hasMore = true;
      unawaited(loadMore());
    }
    notifyListeners();
  }

  Future<void> loadMore() async {
    final iterator = _iterator;
    if (loading || iterator == null || !hasMore) return;
    final generation = _generation;
    final pattern = query;
    final fuzzyMatch = fuzzy;
    loading = true;
    notifyListeners();
    final page = <TreeFindEntry>[];
    if (_lookahead != null) {
      page.add(_lookahead!);
      _lookahead = null;
    }
    try {
      while (await iterator.moveNext()) {
        if (_disposed || generation != _generation) return;
        final entry = iterator.current;
        if (!matchesTreeFind(pattern, p.basename(entry.path),
            fuzzy: fuzzyMatch)) {
          continue;
        }
        if (page.length == pageSize) {
          _lookahead = entry;
          break;
        }
        page.add(entry);
        if (page.length == pageSize) {
          entries
            ..clear()
            ..addAll(page);
          notifyListeners();
        }
      }
      if (_disposed || generation != _generation) return;
      entries
        ..clear()
        ..addAll(page);
      hasMore = _lookahead != null;
      if (!hasMore) {
        _iterator = null;
        await iterator.cancel();
      }
    } on FileSystemException catch (failure) {
      if (_disposed || generation != _generation) return;
      error = failure.message;
      entries
        ..clear()
        ..addAll(page);
      hasMore = false;
      _iterator = null;
      await iterator.cancel();
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel();
    entries.clear();
    input.dispose();
    inputFocus.dispose();
    super.dispose();
  }
}

bool matchesTreeFind(String query, String name, {required bool fuzzy}) =>
    treeFindMatchRanges(query, name, fuzzy: fuzzy) != null;

/// Ranges refer to the original label in UTF-16, including case-fold expansions.
List<TextRange>? treeFindMatchRanges(String query, String name,
    {required bool fuzzy}) {
  final pattern = query.toLowerCase();
  if (pattern.isEmpty) return const [];
  if (fuzzy) {
    return treeFuzzyScore(query, name)
        ?.matches
        .map((match) => TextRange(start: match.start, end: match.end))
        .toList();
  }
  final folded = StringBuffer();
  final starts = <int>[];
  final ends = <int>[];
  var sourceOffset = 0;
  for (final rune in name.runes) {
    final character = String.fromCharCode(rune);
    final lower = character.toLowerCase();
    folded.write(lower);
    for (var i = 0; i < lower.length; i++) {
      starts.add(sourceOffset);
      ends.add(sourceOffset + character.length);
    }
    sourceOffset += character.length;
  }
  final text = folded.toString();
  final start = text.indexOf(pattern);
  if (start < 0) return null;
  return [
    TextRange(start: starts[start], end: ends[start + pattern.length - 1])
  ];
}

TextSpan treeFindLabel(String query, String name, {required bool fuzzy}) {
  final matches = treeFindMatchRanges(query, name, fuzzy: fuzzy);
  if (matches == null || matches.isEmpty) return TextSpan(text: name);
  final spans = <TextSpan>[];
  var offset = 0;
  for (final match in matches) {
    if (match.start > offset) {
      spans.add(TextSpan(text: name.substring(offset, match.start)));
    }
    spans.add(TextSpan(
        text: name.substring(match.start, match.end),
        style: const TextStyle(
            color: Color(0xFF2AAFFF), fontWeight: FontWeight.bold)));
    offset = match.end;
  }
  if (offset < name.length) spans.add(TextSpan(text: name.substring(offset)));
  return TextSpan(children: spans);
}

class TreeFindBar extends StatelessWidget {
  const TreeFindBar(
      {super.key,
      required this.controller,
      required this.onClose,
      required this.onReturnToTree});
  final TreeFindController controller;
  final VoidCallback onClose;
  final VoidCallback onReturnToTree;

  @override
  Widget build(BuildContext context) => Focus(
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            onClose();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            controller.navigateHistory(previous: true);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
              controller.navigateHistory(previous: false)) {
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.arrowDown) {
            controller.rememberQuery();
            onReturnToTree();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Align(
            alignment: Alignment.topRight,
            child: Container(
              key: const ValueKey('tree-find-bar'),
              constraints: const BoxConstraints(maxWidth: 208),
              margin: const EdgeInsets.only(left: 6, right: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF252526),
                border: Border.all(color: const Color(0xFF454545)),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(4)),
              ),
              padding: const EdgeInsets.all(3),
              child: SizedBox(
                  height: 23,
                  child: Row(children: [
                    Expanded(
                        child: TextField(
                      key: const ValueKey('tree-find-input'),
                      controller: controller.input,
                      focusNode: controller.inputFocus,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.zero),
                          hintText: '查找',
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 4, vertical: 2)),
                      onChanged: controller.setQuery,
                    )),
                    _toggle('tree-find-filter', '筛选', Icons.filter_alt_outlined,
                        controller.filter, controller.toggleFilter),
                    _toggle('tree-find-fuzzy', '模糊匹配', Icons.text_fields,
                        controller.fuzzy, controller.toggleFuzzy),
                    SizedBox(
                        width: 24,
                        height: 20,
                        child: IconButton(
                            key: const ValueKey('tree-find-close'),
                            padding: EdgeInsets.zero,
                            tooltip: '关闭查找',
                            iconSize: 16,
                            onPressed: onClose,
                            icon: const Icon(Icons.close))),
                  ])),
            ),
          ),
          if (controller.filter && controller.query.isNotEmpty)
            Semantics(
                liveRegion: true,
                child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    child: Text(
                      controller.error != null
                          ? '查找失败：${controller.error}'
                          : controller.loading
                              ? '正在查找…'
                              : controller.entries.isEmpty
                                  ? '没有结果'
                                  : '本页 ${controller.entries.length} 个结果',
                      style: const TextStyle(fontSize: 11),
                    ))),
          if (controller.hasMore && !controller.loading)
            TextButton(
                key: const ValueKey('tree-find-more'),
                onPressed: controller.loadMore,
                child: const Text('下一页结果')),
        ]),
      );

  Widget _toggle(String key, String label, IconData icon, bool selected,
          VoidCallback run) =>
      Semantics(
          label: label,
          toggled: selected,
          child: SizedBox(
              width: 22,
              height: 20,
              child: IconButton(
                  key: ValueKey(key),
                  tooltip: label,
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  color: selected ? Colors.lightBlueAccent : null,
                  onPressed: run,
                  icon: Icon(icon))));
}
