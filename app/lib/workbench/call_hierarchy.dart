import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'definition_peek.dart' show DefinitionPeekLine;

class CallHierarchyRow {
  const CallHierarchyRow({
    required this.name,
    required this.detail,
    required this.depth,
    this.expanded,
  });

  final String name;
  final String detail;
  final int depth;
  final bool? expanded;
}

class CallHierarchyPeek extends StatefulWidget {
  const CallHierarchyPeek({
    super.key,
    required this.rows,
    required this.incoming,
    required this.loading,
    required this.message,
    required this.loadPreview,
    required this.onDirection,
    required this.onOpen,
    required this.onToggle,
    required this.onClose,
    required this.onCommandKey,
  });

  final List<CallHierarchyRow> rows;
  final bool incoming;
  final bool loading;
  final String? message;
  final Future<List<DefinitionPeekLine>> Function(int index) loadPreview;
  final VoidCallback? onDirection;
  final ValueChanged<int> onOpen;
  final ValueChanged<int> onToggle;
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
    if (!identical(widget.rows, oldWidget.rows)) _refreshRows();
    if (widget.incoming != oldWidget.incoming) _focusResultsAfterLayout();
  }

  void _focusResultsAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resultsFocus.requestFocus();
    });
  }

  void _refreshRows() {
    _selected = _initialRow;
    _preview = widget.rows.isEmpty ? null : widget.loadPreview(_selected);
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
        _preview = widget.loadPreview(bounded);
      });
    }
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final top = bounded * _rowHeight;
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
    } else if (key == LogicalKeyboardKey.arrowLeft &&
        widget.rows[_selected].expanded == true) {
      widget.onToggle(_selected);
    } else if (key == LogicalKeyboardKey.arrowRight &&
        widget.rows[_selected].expanded == false) {
      widget.onToggle(_selected);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Widget _buildRow(int index, ColorScheme colors) {
    final row = widget.rows[index];
    final selected = index == _selected;
    return Semantics(
      key: ValueKey('call-hierarchy-row-$index'),
      selected: selected,
      child: InkWell(
        onTap: () {
          _resultsFocus.requestFocus();
          _select(index);
        },
        onDoubleTap: () => widget.onOpen(index),
        child: Container(
          padding: EdgeInsets.only(left: 6.0 + 14.0 * row.depth, right: 6),
          color: selected ? colors.primary.withValues(alpha: 0.25) : null,
          child: Row(
            children: [
              if (row.expanded case final expanded?)
                InkWell(
                  key: ValueKey('call-hierarchy-toggle-$index'),
                  onTap: () {
                    _resultsFocus.requestFocus();
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
          key: const ValueKey('call-hierarchy-preview'),
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
                        widget.incoming ? '调用层级 · 传入调用' : '调用层级 · 传出调用',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('call-hierarchy-direction'),
                      tooltip: widget.incoming ? '显示传出调用' : '显示传入调用',
                      onPressed: widget.onDirection,
                      iconSize: 16,
                      icon: Icon(widget.incoming
                          ? Icons.call_made
                          : Icons.call_received),
                    ),
                    IconButton(
                      key: const ValueKey('call-hierarchy-close'),
                      tooltip: '关闭调用层级',
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
                    ? const Center(child: Text('正在查询调用层级…'))
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
                                    key: const ValueKey(
                                        'call-hierarchy-results'),
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
