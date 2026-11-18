import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'git_cli.dart';

typedef _GitRow = ({GitStatusEntry entry, bool staged});
typedef _GitIdentity = ({String path, bool staged});

/// Basic SCM resource navigation. Hover never changes the keyboard target.
class GitChangesList extends StatefulWidget {
  const GitChangesList({
    super.key,
    required this.entries,
    required this.onOpen,
    required this.onStage,
    required this.onUnstage,
  });

  final List<GitStatusEntry> entries;
  final Future<void> Function(GitStatusEntry entry,
      {required bool preserveFocus}) onOpen;
  final Future<void> Function(String path) onStage;
  final Future<void> Function(String path) onUnstage;

  @override
  State<GitChangesList> createState() => _GitChangesListState();
}

class _GitChangesListState extends State<GitChangesList> {
  static const _rowHeight = 48.0;
  static const _headerHeight = 24.0;
  final _focus = FocusNode(debugLabel: 'git-changes-list');
  final _scroll = ScrollController();
  _GitIdentity? _focused;
  _GitIdentity? _selected;

  // Preserve the existing panel's single-row treatment of mixed index/worktree
  // changes. Separate rows for both sides are outside basic list navigation.
  List<_GitRow> get _rows => _rowsFor(widget.entries);

  List<_GitRow> _rowsFor(List<GitStatusEntry> entries) => [
        for (final entry in entries.where((e) => e.hasStagedChanges))
          (entry: entry, staged: true),
        for (final entry in entries.where((e) => !e.hasStagedChanges))
          (entry: entry, staged: false),
      ];

  double? _focusOffset(List<_GitRow> rows, _GitIdentity? focus) {
    final index = rows.indexWhere((row) => _identity(row) == focus);
    if (index < 0) return null;
    final stagedCount = rows.where((row) => row.staged).length;
    return index * _rowHeight +
        _headerHeight +
        (stagedCount > 0 && index >= stagedCount ? _headerHeight : 0);
  }

  _GitIdentity _identity(_GitRow row) =>
      (path: row.entry.path, staged: row.staged);

  @override
  void didUpdateWidget(covariant GitChangesList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousOffset = _focusOffset(_rowsFor(oldWidget.entries), _focused);
    final rows = _rows;
    _GitIdentity? retained(_GitIdentity? identity) {
      if (identity == null) return null;
      final index = rows.indexWhere((row) => row.entry.path == identity.path);
      return index < 0 ? null : _identity(rows[index]);
    }

    _focused = retained(_focused);
    _selected = retained(_selected);
    if (_focused != null &&
        _focus.hasFocus &&
        previousOffset != _focusOffset(rows, _focused)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _revealSelection();
      });
    }
  }

  bool get _hasModifiers {
    final keyboard = HardwareKeyboard.instance;
    return keyboard.isAltPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isShiftPressed;
  }

  void _select(_GitRow row, {bool focusList = false, bool select = false}) {
    final identity = _identity(row);
    if (_focused != identity || (select && _selected != identity)) {
      setState(() {
        _focused = identity;
        if (select) _selected = identity;
      });
    }
    if (focusList) _focus.requestFocus();
    _revealSelection();
    // Varied-extent slivers refine maxScrollExtent after laying out a distant
    // section. Correct the initial estimated clamp once that layout completes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _revealSelection();
    });
  }

  void _revealSelection() {
    if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) return;
    final top = _focusOffset(_rows, _focused);
    if (top == null) return;
    final position = _scroll.position;
    final bottom = top + _rowHeight;
    final target = top < position.pixels
        ? top
        : bottom > position.pixels + position.viewportDimension
            ? bottom - position.viewportDimension
            : position.pixels;
    _scroll.jumpTo(target.clamp(0.0, position.maxScrollExtent));
  }

  Future<void> _open(_GitRow row, {required bool preserveFocus}) {
    _select(row, focusList: !_focus.hasFocus, select: true);
    return widget.onOpen(row.entry, preserveFocus: preserveFocus);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (_hasModifiers || (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final rows = _rows;
    if (rows.isEmpty) return KeyEventResult.ignored;
    final index = rows.indexWhere((row) => _identity(row) == _focused);
    final key = event.logicalKey;
    int next;
    if (key == LogicalKeyboardKey.arrowDown) {
      next = index < 0 ? 0 : (index + 1).clamp(0, rows.length - 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      next = index < 0 ? 0 : (index - 1).clamp(0, rows.length - 1);
    } else if (key == LogicalKeyboardKey.home) {
      next = 0;
    } else if (key == LogicalKeyboardKey.end) {
      next = rows.length - 1;
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space) {
      if (index < 0) return KeyEventResult.ignored;
      if (event is KeyDownEvent) {
        unawaited(
            _open(rows[index], preserveFocus: key == LogicalKeyboardKey.space));
      }
      return KeyEventResult.handled;
    } else {
      return KeyEventResult.ignored;
    }
    _select(rows[next], focusList: true);
    return KeyEventResult.handled;
  }

  Future<void> _runAction(_GitRow row) => row.staged
      ? widget.onUnstage(row.entry.path)
      : widget.onStage(row.entry.path);

  Widget _tile(_GitRow row) {
    final entry = row.entry;
    final name = p.posix.basename(entry.path.replaceAll('\\', '/'));
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        key: ValueKey('git-${row.staged ? 's' : 'w'}-${entry.path}'),
        dense: true,
        selected: _identity(row) == _selected,
        selectedTileColor: const Color(0xFF29343F),
        hoverColor: const Color(0xFF222A33),
        leading: Text(entry.code,
            style: TextStyle(
                fontSize: 11,
                color: entry.isUntracked
                    ? Colors.greenAccent
                    : row.staged
                        ? Colors.lightGreenAccent
                        : Colors.orangeAccent)),
        title: Text(name,
            style: const TextStyle(fontSize: 12),
            overflow: TextOverflow.ellipsis),
        subtitle: entry.origPath == null
            ? null
            : Text(
                '${p.posix.basename(entry.origPath!.replaceAll('\\', '/'))} → $name',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
        onFocusChange: (focused) {
          if (focused) _select(row);
        },
        onTap: () => unawaited(_open(row, preserveFocus: true)),
        trailing: Focus(
          canRequestFocus: false,
          onFocusChange: (focused) {
            if (focused) _select(row);
          },
          onKeyEvent: (node, event) {
            if (_hasModifiers ||
                (event is! KeyDownEvent && event is! KeyRepeatEvent) ||
                (event.logicalKey != LogicalKeyboardKey.enter &&
                    event.logicalKey != LogicalKeyboardKey.space)) {
              return KeyEventResult.ignored;
            }
            if (event is KeyDownEvent) unawaited(_runAction(row));
            return KeyEventResult.handled;
          },
          child: IconButton(
            key: ValueKey('git-action-${row.staged ? 's' : 'w'}-${entry.path}'),
            tooltip: row.staged ? '取消暂存' : '暂存',
            onPressed: () => unawaited(_runAction(row)),
            icon: Icon(row.staged ? Icons.remove : Icons.add,
                size: 15, color: Colors.grey.shade400),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final stagedCount = rows.where((row) => row.staged).length;
    final hasSecondHeader = stagedCount > 0 && stagedCount < rows.length;
    int rowIndex(int item) =>
        item - 1 - (hasSecondHeader && item > stagedCount + 1 ? 1 : 0);
    bool isHeader(int item) =>
        item == 0 || (hasSecondHeader && item == stagedCount + 1);
    return Focus(
      key: const ValueKey('git-changes-list-focus'),
      focusNode: _focus,
      onKeyEvent: _onKeyEvent,
      child: ListView.builder(
        key: const ValueKey('git-changes-list'),
        controller: _scroll,
        padding: EdgeInsets.zero,
        itemCount:
            rows.isEmpty ? 0 : rows.length + 1 + (hasSecondHeader ? 1 : 0),
        itemExtentBuilder: (index, dimensions) =>
            isHeader(index) ? _headerHeight : _rowHeight,
        findChildIndexCallback: (key) {
          if (key is! ValueKey<_GitIdentity>) return null;
          final index = rows.indexWhere((row) => _identity(row) == key.value);
          return index < 0
              ? null
              : index + 1 + (hasSecondHeader && index >= stagedCount ? 1 : 0);
        },
        itemBuilder: (context, index) {
          if (isHeader(index)) {
            final staged = index == 0 && stagedCount > 0;
            final count = staged ? stagedCount : rows.length - stagedCount;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('${staged ? '暂存的更改' : '更改'}（$count）',
                    style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            );
          }
          final row = rows[rowIndex(index)];
          return SizedBox(
            key: ValueKey<_GitIdentity>(_identity(row)),
            height: _rowHeight,
            child: Semantics(
              key: ValueKey(
                  'git-focus-${row.staged ? 's' : 'w'}-${row.entry.path}'),
              focused: _identity(row) == _focused,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _identity(row) == _focused
                        ? const Color(0xFF007FD4)
                        : Colors.transparent,
                  ),
                ),
                child: _tile(row),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }
}
