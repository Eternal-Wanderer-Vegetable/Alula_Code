import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bridge/alula_core.dart' show HierarchyDirection;
import 'definition_peek.dart' show DefinitionPeekLine;

class CallHierarchyRow {
  const CallHierarchyRow({
    required this.id,
    required this.name,
    required this.detail,
    required this.depth,
    this.parentIndex,
    this.expanded,
    this.more = false,
    this.loading = false,
  });

  final Object id;
  final String name;
  final String detail;
  final int depth;
  final int? parentIndex;
  final bool? expanded;
  final bool more;
  final bool loading;
}

class CallHierarchyPeek extends StatefulWidget {
  const CallHierarchyPeek({
    super.key,
    required this.rows,
    this.preferredSelection,
    required this.direction,
    required this.loading,
    required this.message,
    required this.loadPreview,
    required this.onDirection,
    required this.onOpen,
    required this.onToggle,
    this.onSelection,
    required this.onClose,
    required this.onCommandKey,
  });

  final List<CallHierarchyRow> rows;
  final Object? preferredSelection;
  final HierarchyDirection direction;
  final bool loading;
  final String? message;
  final Future<List<DefinitionPeekLine>> Function(int index) loadPreview;
  final VoidCallback? onDirection;
  final ValueChanged<int> onOpen;
  final ValueChanged<int> onToggle;
  final ValueChanged<int?>? onSelection;
  final VoidCallback onClose;
  final KeyEventResult Function(KeyEvent) onCommandKey;

  @override
  State<CallHierarchyPeek> createState() => _CallHierarchyPeekState();
}

class _CallHierarchyPeekState extends State<CallHierarchyPeek> {
  static const _rowHeight = 26.0;
  final _resultsFocus = FocusNode(debugLabel: 'Call hierarchy results');
  final _scroll = ScrollController();
  int _selected = 0;
  Future<List<DefinitionPeekLine>>? _preview;

  String get _keyPrefix => switch (widget.direction) {
        HierarchyDirection.incoming || HierarchyDirection.outgoing =>
          'call-hierarchy',
        HierarchyDirection.supertypes || HierarchyDirection.subtypes =>
          'type-hierarchy',
      };

  int get _initialRow {
    final child = widget.rows.indexWhere((row) => row.depth > 0);
    return child < 0 ? 0 : child;
  }

  @override
  void initState() {
    super.initState();
    _refreshRows();
    _focusResultsAfterLayout();
  }

  @override
  void didUpdateWidget(CallHierarchyPeek oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.rows, oldWidget.rows)) {
      _refreshRows(oldWidget);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _revealRow(_selected);
      });
    }
    if (widget.direction != oldWidget.direction) _focusResultsAfterLayout();
  }

  void _focusResultsAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resultsFocus.requestFocus();
    });
  }

  void _refreshRows([CallHierarchyPeek? oldWidget]) {
    if (widget.rows.isEmpty) {
      _selected = 0;
      _preview = null;
      widget.onSelection?.call(null);
      return;
    }
    final preferred =
        widget.rows.indexWhere((row) => row.id == widget.preferredSelection);
    final previous = oldWidget != null &&
            oldWidget.direction == widget.direction &&
            _selected < oldWidget.rows.length
        ? oldWidget.rows[_selected]
        : null;
    int? oldIndex = previous == null ? null : _selected;
    var current = preferred;
    while (current < 0 && oldIndex != null) {
      final row = oldWidget!.rows[oldIndex];
      current = widget.rows.indexWhere((candidate) => candidate.id == row.id);
      oldIndex = row.parentIndex;
    }
    _selected = current < 0 ? _initialRow : current;
    widget.onSelection?.call(_selected);
    final row = widget.rows[_selected];
    if (!row.more && (row.id != previous?.id || _preview == null)) {
      _preview = widget.loadPreview(_selected);
    }
  }

  @override
  void dispose() {
    _resultsFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (widget.rows.isEmpty) return;
    final bounded = index.clamp(0, widget.rows.length - 1).toInt();
    if (bounded != _selected) {
      setState(() {
        _selected = bounded;
        widget.onSelection?.call(_selected);
        if (!widget.rows[bounded].more) {
          _preview = widget.loadPreview(bounded);
        }
      });
    }
    _revealRow(bounded);
  }

  void _revealRow(int index) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final top = index * _rowHeight;
    if (top < position.pixels) {
      _scroll.jumpTo(top);
    } else if (top + _rowHeight >
        position.pixels + position.viewportDimension) {
      final offset = top + _rowHeight - position.viewportDimension;
      _scroll.jumpTo(offset.clamp(0.0, position.maxScrollExtent).toDouble());
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    final command = widget.onCommandKey(event);
    if (command != KeyEventResult.ignored) return command;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (widget.rows.isEmpty ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _select(_selected + 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _select(_selected - 1);
    } else if (key == LogicalKeyboardKey.home) {
      _select(0);
    } else if (key == LogicalKeyboardKey.end) {
      _select(widget.rows.length - 1);
    } else if (key == LogicalKeyboardKey.enter) {
      widget.onOpen(_selected);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      final row = widget.rows[_selected];
      if (row.expanded == true) {
        widget.onToggle(_selected);
      } else if (row.parentIndex case final parent?) {
        _select(parent);
      } else {
        return KeyEventResult.ignored;
      }
    } else if (key == LogicalKeyboardKey.arrowRight) {
      final row = widget.rows[_selected];
      if (row.expanded == false) {
        widget.onToggle(_selected);
      } else if (_selected + 1 < widget.rows.length &&
          widget.rows[_selected + 1].parentIndex == _selected) {
        _select(_selected + 1);
      } else {
        return KeyEventResult.ignored;
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Widget _buildRow(int index, ColorScheme colors) {
    final row = widget.rows[index];
    final selected = index == _selected;
    return LayoutBuilder(builder: (context, constraints) {
      final indent = math.min(
          6.0 + 14.0 * row.depth, math.max(0.0, constraints.maxWidth - 68));
      return Semantics(
        key: ValueKey('$_keyPrefix-row-$index'),
        selected: selected,
        expanded: row.expanded,
        button: row.more,
        child: InkWell(
          onTap: () {
            _resultsFocus.requestFocus();
            _select(index);
            if (row.more) widget.onOpen(index);
          },
          onDoubleTap: row.more ? null : () => widget.onOpen(index),
          child: Container(
            padding: EdgeInsets.only(left: indent, right: 6),
            color: selected ? colors.primary.withValues(alpha: 0.25) : null,
            child: Row(
              children: [
                if (row.expanded case final expanded?)
                  InkWell(
                    key: ValueKey('$_keyPrefix-toggle-$index'),
                    onTap: () {
                      _resultsFocus.requestFocus();
                      _select(index);
                      widget.onToggle(index);
                    },
                    child: Icon(
                      expanded ? Icons.expand_more : Icons.chevron_right,
                      size: 16,
                    ),
                  )
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 4),
                if (row.loading)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: SizedBox(
                      width: 11,
                      height: 11,
                      child: CircularProgressIndicator(strokeWidth: 1),
                    ),
                  ),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: row.name,
                      children: [
                        if (row.detail.isNotEmpty)
                          TextSpan(
                            text: '  ${row.detail}',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildPreview(ColorScheme colors) {
    return FutureBuilder<List<DefinitionPeekLine>>(
      future: _preview,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final lines = snapshot.data ?? const <DefinitionPeekLine>[];
        if (lines.isEmpty) {
          return const Center(child: Text('预览不可用'));
        }
        return SelectionArea(
          key: ValueKey('$_keyPrefix-preview'),
          child: ListView.builder(
            itemCount: lines.length,
            itemBuilder: (context, index) {
              final line = lines[index];
              final start =
                  line.highlightStart.clamp(0, line.text.length).toInt();
              final end =
                  line.highlightEnd.clamp(start, line.text.length).toInt();
              return Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${line.number.toString().padLeft(4)}  ',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    TextSpan(text: line.text.substring(0, start)),
                    TextSpan(
                      text: line.text.substring(start, end),
                      style: TextStyle(
                        backgroundColor: colors.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    TextSpan(text: line.text.substring(end)),
                  ],
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.clip,
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (hierarchy, relation, switchLabel, switchIcon) = switch (widget.direction) {
      HierarchyDirection.incoming =>
        ('调用层级', '传入调用', '显示传出调用', Icons.call_made),
      HierarchyDirection.outgoing =>
        ('调用层级', '传出调用', '显示传入调用', Icons.call_received),
      HierarchyDirection.supertypes =>
        ('类型层级', '父类型', '显示子类型', Icons.account_tree_outlined),
      HierarchyDirection.subtypes =>
        ('类型层级', '子类型', '显示父类型', Icons.vertical_align_top),
    };
    return Material(
      color: colors.surfaceContainer,
      elevation: 3,
      child: Focus(
        focusNode: _resultsFocus,
        autofocus: true,
        onKeyEvent: _key,
        child: SizedBox(
          height: 234,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 34,
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$hierarchy · $relation',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      key: ValueKey('$_keyPrefix-direction'),
                      tooltip: switchLabel,
                      onPressed: widget.onDirection,
                      iconSize: 16,
                      icon: Icon(switchIcon),
                    ),
                    IconButton(
                      key: ValueKey('$_keyPrefix-close'),
                      tooltip: '关闭$hierarchy',
                      onPressed: widget.onClose,
                      iconSize: 16,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: colors.outlineVariant),
              Expanded(
                child: widget.loading
                    ? Center(child: Text('正在查询$hierarchy…'))
                    : widget.message != null && widget.rows.isEmpty
                        ? Center(child: Text(widget.message!))
                        : LayoutBuilder(
                            builder: (context, constraints) => Row(
                              children: [
                                if (constraints.maxWidth >= 420) ...[
                                  Expanded(
                                    flex: 7,
                                    child: widget.message == null
                                        ? _buildPreview(colors)
                                        : Center(child: Text(widget.message!)),
                                  ),
                                  VerticalDivider(
                                      width: 1, color: colors.outlineVariant),
                                ],
                                Expanded(
                                  flex: 3,
                                  child: ListView.builder(
                                    key: ValueKey('$_keyPrefix-results'),
                                    controller: _scroll,
                                    itemExtent: _rowHeight,
                                    itemCount: widget.rows.length,
                                    itemBuilder: (context, i) =>
                                        _buildRow(i, colors),
                                  ),
                                ),
                              ],
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
