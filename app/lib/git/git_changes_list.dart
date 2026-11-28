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
  final _viewportKey = GlobalKey();
  _GitIdentity? _focused;
  final Set<_GitIdentity> _selected = {};
  _GitIdentity? _anchor;
  LogicalKeyboardKey? _contextMenuKeyDown;
  bool _contextMenuOpen = false;
  final Set<void Function(List<GitStatusEntry>)> _openMenuInvalidators = {};

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
    for (final invalidate in _openMenuInvalidators.toList()) {
      invalidate(widget.entries);
    }
    final rows = _rows;
    _GitIdentity? retained(_GitIdentity? identity) {
      if (identity == null) return null;
      final index = rows.indexWhere((row) => row.entry.path == identity.path);
      return index < 0 ? null : _identity(rows[index]);
    }

    _focused = retained(_focused);
    _anchor = retained(_anchor);
    final selectedPaths = _selected.map((identity) => identity.path).toSet();
    _selected
      ..clear()
      ..addAll(rows
          .where((row) => selectedPaths.contains(row.entry.path))
          .map(_identity));
    if (_focused != null &&
        _focus.hasFocus &&
        previousOffset != _focusOffset(rows, _focused)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _revealSelection();
      });
    }
  }

  bool get _hasAlt => HardwareKeyboard.instance.isAltPressed;

  bool get _hasToggleModifier => switch (Theme.of(context).platform) {
        TargetPlatform.macOS => HardwareKeyboard.instance.isMetaPressed,
        _ => HardwareKeyboard.instance.isControlPressed,
      };

  bool get _hasUnsupportedModifiers =>
      _hasAlt ||
      (Theme.of(context).platform == TargetPlatform.macOS
          ? HardwareKeyboard.instance.isControlPressed
          : HardwareKeyboard.instance.isMetaPressed);

  bool get _hasModifiers =>
      _hasAlt ||
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed ||
      HardwareKeyboard.instance.isShiftPressed;

  void _select(
    _GitRow row, {
    bool focusList = false,
    bool select = false,
    bool preserveSelection = false,
    bool updateAnchor = true,
  }) {
    final identity = _identity(row);
    final selectedChanged = select &&
        (!_selected.contains(identity) ||
            (!preserveSelection && _selected.length != 1));
    if (_focused != identity ||
        selectedChanged ||
        (updateAnchor && _anchor != identity)) {
      setState(() {
        _focused = identity;
        if (select) {
          if (!preserveSelection) {
            _selected
              ..clear()
              ..add(identity);
          } else {
            _selected.add(identity);
          }
        }
        if (updateAnchor) _anchor = identity;
      });
    }
    if (focusList) _focus.requestFocus();
    _revealSelection();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _revealSelection();
    });
  }

  void _onModifiedTap(_GitRow row) {
    final rows = _rows;
    final identity = _identity(row);
    final index =
        rows.indexWhere((candidate) => _identity(candidate) == identity);
    final currentFocus = _focused;
    if (index < 0) return;
    if (HardwareKeyboard.instance.isShiftPressed) {
      final anchor = _anchor ?? currentFocus ?? identity;
      final anchorIndex =
          rows.indexWhere((candidate) => _identity(candidate) == anchor);
      final low = anchorIndex < 0
          ? index
          : anchorIndex < index
              ? anchorIndex
              : index;
      final high = anchorIndex < 0
          ? index
          : anchorIndex > index
              ? anchorIndex
              : index;
      final next = rows.skip(low).take(high - low + 1).map(_identity).toSet();
      final runStart = anchorIndex < 0 ? index : anchorIndex;
      var runLow = runStart;
      var runHigh = runStart;
      while (runLow > 0 && _selected.contains(_identity(rows[runLow - 1]))) {
        runLow--;
      }
      while (runHigh + 1 < rows.length &&
          _selected.contains(_identity(rows[runHigh + 1]))) {
        runHigh++;
      }
      setState(() {
        for (var i = runLow; i <= runHigh; i++) {
          _selected.remove(_identity(rows[i]));
        }
        _selected.addAll(next);
        _focused = identity;
        _anchor = anchor;
      });
    } else if (_hasToggleModifier) {
      setState(() {
        _focused = identity;
        _anchor = identity;
        if (!_selected.add(identity)) _selected.remove(identity);
      });
    } else {
      _select(row, select: true);
      return;
    }
    if (!_focus.hasFocus) _focus.requestFocus();
    _revealSelection();
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

  bool _isListNavigationKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.arrowDown ||
      key == LogicalKeyboardKey.home ||
      key == LogicalKeyboardKey.end ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.space;

  bool _isContextMenuKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.contextMenu ||
      (key == LogicalKeyboardKey.f10 &&
          (HardwareKeyboard.instance.isShiftPressed ||
              _contextMenuKeyDown == LogicalKeyboardKey.f10));

  Future<void> _showContextMenu(_GitRow row, Offset globalPosition) async {
    if (!mounted ||
        _contextMenuOpen ||
        !_rows.any((candidate) => _identity(candidate) == _identity(row))) {
      return;
    }
    final identity = _identity(row);
    final entry = row.entry;
    final origin = entry.origPath;
    var targetInvalidated = false;
    void invalidateTargetOnRefresh(List<GitStatusEntry> entries) {
      if (!entries.any((candidate) =>
          candidate.path == identity.path &&
          candidate.hasStagedChanges == identity.staged &&
          candidate.origPath == origin &&
          candidate.x == entry.x &&
          candidate.y == entry.y)) {
        targetInvalidated = true;
      }
    }

    _openMenuInvalidators.add(invalidateTargetOnRefresh);
    var ownsVisibleMenu = true;
    setState(() => _contextMenuOpen = true);
    try {
      final overlay = Navigator.of(context).overlay!.context.findRenderObject()
          as RenderBox;
      final localPosition = overlay.globalToLocal(globalPosition);
      final selected = await showMenu<String>(
        context: context,
        position: RelativeRect.fromRect(
          Rect.fromLTWH(localPosition.dx, localPosition.dy, 0, 0),
          Offset.zero & overlay.size,
        ),
        items: [
          const PopupMenuItem(
              value: 'open',
              key: ValueKey('scm-context-open'),
              child: Text('打开差异')),
          if (row.staged)
            const PopupMenuItem(
              value: 'unstage',
              key: ValueKey('scm-context-unstage'),
              child: Text('取消暂存此文件'),
            )
          else
            const PopupMenuItem(
              value: 'stage',
              key: ValueKey('scm-context-stage'),
              child: Text('暂存此文件'),
            ),
        ],
      );
      ownsVisibleMenu = false;
      if (mounted) setState(() => _contextMenuOpen = false);
      if (!mounted || selected == null || targetInvalidated) return;
      final current = _rows.where((candidate) =>
          candidate.entry.path == identity.path &&
          candidate.staged == identity.staged &&
          candidate.entry.origPath == origin);
      if (current.length != 1) return;
      final target = current.single;
      if (selected == 'open') {
        _focus.requestFocus();
        await Future<void>.value();
        if (!mounted || targetInvalidated) return;
        FocusManager.instance.applyFocusChangesIfNeeded();
        _openMenuInvalidators.remove(invalidateTargetOnRefresh);
        await widget.onOpen(target.entry, preserveFocus: false);
      } else if (selected == 'stage' && !target.staged) {
        _openMenuInvalidators.remove(invalidateTargetOnRefresh);
        await widget.onStage(target.entry.path);
      } else if (selected == 'unstage' && target.staged) {
        _openMenuInvalidators.remove(invalidateTargetOnRefresh);
        await widget.onUnstage(target.entry.path);
      }
    } finally {
      _openMenuInvalidators.remove(invalidateTargetOnRefresh);
      if (mounted && ownsVisibleMenu) {
        setState(() => _contextMenuOpen = false);
      }
    }
  }

  void _openKeyboardContextMenu() {
    final rows = _rows;
    final index = rows.indexWhere((row) => _identity(row) == _focused);
    if (index < 0 || _contextMenuOpen) return;
    final row = rows[index];
    final identity = _identity(row);
    final top = _focusOffset(rows, _focused);
    if (top == null) return;
    _revealSelection();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_focus.hasFocus ||
          !_scroll.hasClients ||
          _focused != identity ||
          !_rows.any((candidate) =>
              _identity(candidate) == identity &&
              candidate.entry.x == row.entry.x &&
              candidate.entry.y == row.entry.y &&
              candidate.entry.origPath == row.entry.origPath)) {
        return;
      }
      final currentTop = _focusOffset(_rows, identity);
      if (currentTop == null) return;
      _revealSelection();
      final renderObject = _viewportKey.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) return;
      final position = renderObject.localToGlobal(Offset(
          8,
          (currentTop - _scroll.offset + _rowHeight / 2)
              .clamp(0.0, renderObject.size.height)));
      unawaited(_showContextMenu(row, position));
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (_isContextMenuKey(key)) {
      if (event is KeyDownEvent) {
        _contextMenuKeyDown = key;
        return KeyEventResult.handled;
      }
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      if (event is KeyUpEvent) {
        final shouldOpen = _contextMenuKeyDown == key;
        _contextMenuKeyDown = null;
        if (shouldOpen) _openKeyboardContextMenu();
        return KeyEventResult.handled;
      }
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final toggleModifier = _hasToggleModifier;
    if (_hasAlt || _hasUnsupportedModifiers) {
      return _isListNavigationKey(key) ||
              (toggleModifier && key == LogicalKeyboardKey.keyA)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    final rows = _rows;
    if (rows.isEmpty) return KeyEventResult.ignored;
    final index = rows.indexWhere((row) => _identity(row) == _focused);
    if ((HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed) &&
        key != LogicalKeyboardKey.keyA) {
      return _isListNavigationKey(key)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed &&
        key != LogicalKeyboardKey.arrowUp &&
        key != LogicalKeyboardKey.arrowDown) {
      return _isListNavigationKey(key)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (toggleModifier && key == LogicalKeyboardKey.keyA) {
      if (event is KeyDownEvent) {
        setState(() {
          _selected
            ..clear()
            ..addAll(rows.map(_identity));
        });
        if (rows.length == 1) {
          unawaited(widget.onOpen(rows.single.entry, preserveFocus: true));
        }
      }
      return KeyEventResult.handled;
    }
    final shift = HardwareKeyboard.instance.isShiftPressed;
    int next;
    if (key == LogicalKeyboardKey.arrowDown) {
      next = index < 0 ? 0 : (index + 1).clamp(0, rows.length - 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      next = index < 0 ? 0 : (index - 1).clamp(0, rows.length - 1);
    } else if (!shift && key == LogicalKeyboardKey.home) {
      next = 0;
    } else if (!shift && key == LogicalKeyboardKey.end) {
      next = rows.length - 1;
    } else if (!shift &&
        (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space)) {
      if (index < 0) return KeyEventResult.ignored;
      if (event is KeyDownEvent) {
        unawaited(
            _open(rows[index], preserveFocus: key == LogicalKeyboardKey.space));
      }
      return KeyEventResult.handled;
    } else {
      return KeyEventResult.ignored;
    }
    if (shift &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown)) {
      if (next == index) return KeyEventResult.handled;
      final destination = _identity(rows[next]);
      final previous = index < 0 ? null : _identity(rows[index]);
      var preview = false;
      setState(() {
        _focused = destination;
        if (_selected.contains(destination)) {
          if (previous != null) _selected.remove(previous);
        } else {
          _selected.add(destination);
        }
        preview = _selected.length == 1;
      });
      if (preview) {
        unawaited(widget.onOpen(rows[next].entry, preserveFocus: true));
      }
      _focus.requestFocus();
      _revealSelection();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _revealSelection();
      });
    } else {
      _select(rows[next], focusList: true);
    }
    return KeyEventResult.handled;
  }

  Future<void> _runAction(_GitRow row) => row.staged
      ? widget.onUnstage(row.entry.path)
      : widget.onStage(row.entry.path);

  Widget _tile(_GitRow row) {
    final entry = row.entry;
    final name = p.posix.basename(entry.path.replaceAll('\\', '/'));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapUp: (details) {
        _select(row, focusList: true, updateAnchor: false);
        unawaited(_showContextMenu(row, details.globalPosition));
      },
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          key: ValueKey('git-${row.staged ? 's' : 'w'}-${entry.path}'),
          dense: true,
          selected: _selected.contains(_identity(row)),
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
            if (focused) _select(row, updateAnchor: false);
          },
          onTap: () {
            if (_hasUnsupportedModifiers) return;
            if (_hasToggleModifier ||
                HardwareKeyboard.instance.isShiftPressed) {
              _onModifiedTap(row);
            } else {
              unawaited(_open(row, preserveFocus: true));
            }
          },
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
              key: ValueKey(
                  'git-action-${row.staged ? 's' : 'w'}-${entry.path}'),
              tooltip: row.staged ? '取消暂存' : '暂存',
              onPressed: () => unawaited(_runAction(row)),
              icon: Icon(row.staged ? Icons.remove : Icons.add,
                  size: 15, color: Colors.grey.shade400),
            ),
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
      child: SizedBox(
        key: _viewportKey,
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
