import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals, mapEquals, setEquals;
import 'package:flutter/gestures.dart'
    show PointerDownEvent, PointerMoveEvent, kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import 'layout_model.dart';

/// A vertical split within one side bar entry. Drag previews are local until
/// the pointer is released, so cancellation leaves the saved layout intact.
class SidebarGroupSplit extends StatefulWidget {
  const SidebarGroupSplit({
    super.key,
    required this.location,
    required this.container,
    required this.panes,
    required this.labels,
    required this.weights,
    required this.collapsed,
    required this.onCommit,
    required this.onSetCollapsed,
    required this.onFocus,
  }) : assert(panes.length > 1);

  final String location;
  final String container;
  final Map<String, Widget> panes;
  final Map<String, String> labels;
  final Map<String, double> weights;
  final Set<String> collapsed;
  final ValueChanged<Map<String, double>> onCommit;
  final void Function(String view, bool collapsed) onSetCollapsed;
  final ValueChanged<String> onFocus;

  @override
  State<SidebarGroupSplit> createState() => _SidebarGroupSplitState();
}

class _SidebarGroupSplitState extends State<SidebarGroupSplit> {
  static const _minimumPaneExtent = 148.0;
  static const _headerExtent = 28.0;

  ({int index, int pointer})? _drag;
  Map<String, double>? _preview;

  @override
  void didUpdateWidget(covariant SidebarGroupSplit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(
            oldWidget.panes.keys.toList(), widget.panes.keys.toList()) ||
        !mapEquals(oldWidget.weights, widget.weights) ||
        !setEquals(oldWidget.collapsed, widget.collapsed)) {
      _drag = null;
      _preview = null;
    }
  }

  WbSplit _split(List<String> views) {
    final weights = _preview ?? widget.weights;
    return WbSplit(
      axis: Axis.vertical,
      children: [
        for (final view in views)
          WbLeaf(
            region: view,
            weight: weights[view] ?? 1,
            minExtent: _minimumPaneExtent,
          ),
      ],
    );
  }

  void _start(int index, PointerDownEvent event) {
    if (_drag != null || (event.buttons & kPrimaryButton) == 0) return;
    _drag = (index: index, pointer: event.pointer);
  }

  void _resize(
      List<String> views, int index, PointerMoveEvent event, double inside) {
    if (_drag != (index: index, pointer: event.pointer)) return;
    final split = _split(views);
    final previous = [for (final pane in split.children) pane.weight];
    split.applyDrag(index, event.delta.dy, inside);
    final updated = [for (final pane in split.children) pane.weight];
    if (listEquals(previous, updated)) return;
    setState(() => _preview = _weightsAfterLayout(split));
  }

  void _finish(int index, int pointer, {required bool commit}) {
    if (_drag != (index: index, pointer: pointer)) return;
    final resized = _preview;
    setState(() {
      _drag = null;
      _preview = null;
    });
    if (commit && resized != null) widget.onCommit(resized);
  }

  void _reset(List<String> views, int index, double inside) {
    if (_drag != null) return;
    final split = _split(views);
    if (!split.resetDivider(index, inside)) return;
    widget.onCommit(_weightsAfterLayout(split));
  }

  Map<String, double> _weightsAfterLayout(WbSplit split) {
    final current = _preview ?? widget.weights;
    final expanded = split.children.cast<WbLeaf>();
    // Keep the saved share of a collapsed pane while resizing the open panes.
    final previousTotal = expanded.fold(
      0.0,
      (sum, pane) => sum + (current[pane.region] ?? 1),
    );
    final updatedTotal = expanded.fold(0.0, (sum, pane) => sum + pane.weight);
    return {
      for (final view in widget.panes.keys) view: current[view] ?? 1,
      for (final pane in expanded)
        pane.region: pane.weight / updatedTotal * previousTotal,
    };
  }

  Widget _buildDivider(
    String before,
    String after,
    List<String> expanded,
    int index,
    double inside,
    double thickness,
  ) {
    return SizedBox(
      key: ValueKey('sidebar-group-sash-${widget.location}-$before-$after'),
      height: thickness,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) => _start(index, event),
          onPointerMove: (event) => _resize(expanded, index, event, inside),
          onPointerUp: (event) => _finish(index, event.pointer, commit: true),
          onPointerCancel: (event) =>
              _finish(index, event.pointer, commit: false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: () => _reset(expanded, index, inside),
            child: const Center(
              child: SizedBox(
                width: double.infinity,
                height: 1,
                child: ColoredBox(color: Color(0xFF2A2E37)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final views = widget.panes.keys.toList(growable: false);
        final expandedIndices = [
          for (var i = 0; i < views.length; i++)
            if (!widget.collapsed.contains(views[i])) i,
        ];
        final first = expandedIndices.isEmpty ? 0 : expandedIndices.first;
        final last = expandedIndices.isEmpty ? 0 : expandedIndices.last;
        final dividerCount = last - first;
        final collapsedCount = views.length - expandedIndices.length;
        final extent = constraints.maxHeight;
        final header = collapsedCount == 0
            ? _headerExtent
            : math.min(_headerExtent, extent / collapsedCount);
        final available = math.max(0.0, extent - header * collapsedCount);
        final thickness = dividerCount == 0
            ? 0.0
            : math.min(workbenchDividerThickness, available / dividerCount);
        final inside = math.max(0.0, available - thickness * dividerCount);
        final expanded = [for (final i in expandedIndices) views[i]];
        final extents = switch (expanded.length) {
          0 => <double>[],
          1 => [inside],
          _ => _split(expanded).extentsFor(inside),
        };
        final sizes = {
          for (final view in widget.collapsed) view: header,
          for (var i = 0; i < expanded.length; i++) expanded[i]: extents[i],
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < views.length; i++) ...[
              _buildPane(views[i], sizes[views[i]]!),
              if (i >= first && i < last)
                _buildDivider(
                  views[i],
                  views[i + 1],
                  expanded,
                  expandedIndices.lastIndexWhere((value) => value <= i),
                  inside,
                  thickness,
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildPane(String view, double extent) {
    final collapsed = widget.collapsed.contains(view);
    final role = view == widget.container ? 'original-' : '';
    return SizedBox(
      key: ValueKey('${widget.location}-sidebar-group-$role$view'),
      height: extent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: math.min(_headerExtent, extent),
            child: _SidebarGroupHeader(
              semanticsKey:
                  ValueKey('sidebar-group-header-${widget.location}-$view'),
              label: widget.labels[view]!,
              collapsed: collapsed,
              onSetCollapsed: (value) => widget.onSetCollapsed(view, value),
              onFocus: () => widget.onFocus(view),
            ),
          ),
          Expanded(
            child: Visibility(
              visible: !collapsed,
              maintainState: true,
              child: widget.panes[view]!,
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarGroupHeader extends StatefulWidget {
  const _SidebarGroupHeader({
    required this.semanticsKey,
    required this.label,
    required this.collapsed,
    required this.onSetCollapsed,
    required this.onFocus,
  });

  final Key semanticsKey;
  final String label;
  final bool collapsed;
  final ValueChanged<bool> onSetCollapsed;
  final VoidCallback onFocus;

  @override
  State<_SidebarGroupHeader> createState() => _SidebarGroupHeaderState();
}

class _SidebarGroupHeaderState extends State<_SidebarGroupHeader> {
  final _focus = FocusNode();

  void _toggle() {
    _focus.requestFocus();
    widget.onSetCollapsed(!widget.collapsed);
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: widget.semanticsKey,
      button: true,
      expanded: !widget.collapsed,
      onTap: _toggle,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              widget.onSetCollapsed(true),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              widget.onSetCollapsed(false),
        },
        child: Material(
          color: const Color(0xFF252932),
          child: InkWell(
            focusNode: _focus,
            excludeFromSemantics: true,
            onFocusChange: (focused) {
              if (focused) widget.onFocus();
            },
            onTap: _toggle,
            child: ClipRect(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Icon(
                      widget.collapsed
                          ? Icons.chevron_right
                          : Icons.expand_more,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
