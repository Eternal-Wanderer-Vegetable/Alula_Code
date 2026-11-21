import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals, mapEquals, setEquals;
import 'package:flutter/gestures.dart'
    show PointerDownEvent, PointerMoveEvent, kPrimaryButton;
import 'package:flutter/material.dart';

import 'layout_model.dart';

/// Adjacent pane sizing within a view container. A drag previews its sizes
/// locally and only saves them when the pointer is released.
class PaneGroupSplit extends StatefulWidget {
  const PaneGroupSplit({
    super.key,
    required this.axis,
    required this.minimums,
    required this.weights,
    required this.sashKeyPrefix,
    required this.buildPane,
    required this.onCommit,
    this.collapsed = const {},
    this.collapsedExtent = 0,
    this.resetOnDoubleClick = false,
  }) : assert(minimums.length > 1);

  final Axis axis;
  final Map<String, double> minimums;
  final Map<String, double> weights;
  final String sashKeyPrefix;
  final Widget Function(String view, double extent) buildPane;
  final ValueChanged<Map<String, double>> onCommit;
  final Set<String> collapsed;
  final double collapsedExtent;
  final bool resetOnDoubleClick;

  @override
  State<PaneGroupSplit> createState() => _PaneGroupSplitState();
}

class _PaneGroupSplitState extends State<PaneGroupSplit> {
  ({int index, int pointer})? _drag;
  Map<String, double>? _preview;

  @override
  void didUpdateWidget(covariant PaneGroupSplit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(
            oldWidget.minimums.keys.toList(), widget.minimums.keys.toList()) ||
        !mapEquals(oldWidget.minimums, widget.minimums) ||
        oldWidget.axis != widget.axis ||
        !mapEquals(oldWidget.weights, widget.weights) ||
        !setEquals(oldWidget.collapsed, widget.collapsed)) {
      _drag = null;
      _preview = null;
    }
  }

  WbSplit _split(List<String> views) {
    final weights = _preview ?? widget.weights;
    return WbSplit(
      axis: widget.axis,
      children: [
        for (final view in views)
          WbLeaf(
            region: view,
            weight: weights[view] ?? 1,
            minExtent: widget.minimums[view]!,
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
    final delta =
        widget.axis == Axis.vertical ? event.delta.dy : event.delta.dx;
    split.applyDrag(index, delta, inside);
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
      for (final view in widget.minimums.keys) view: current[view] ?? 1,
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
    final vertical = widget.axis == Axis.vertical;
    return SizedBox(
      key: ValueKey('${widget.sashKeyPrefix}-$before-$after'),
      height: vertical ? thickness : null,
      width: vertical ? null : thickness,
      child: MouseRegion(
        cursor: vertical
            ? SystemMouseCursors.resizeUpDown
            : SystemMouseCursors.resizeLeftRight,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) => _start(index, event),
          onPointerMove: (event) => _resize(expanded, index, event, inside),
          onPointerUp: (event) => _finish(index, event.pointer, commit: true),
          onPointerCancel: (event) =>
              _finish(index, event.pointer, commit: false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: widget.resetOnDoubleClick
                ? () => _reset(expanded, index, inside)
                : null,
            child: Center(
              child: SizedBox(
                width: vertical ? double.infinity : 1,
                height: vertical ? 1 : double.infinity,
                child: const ColoredBox(color: Color(0xFF2A2E37)),
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
        final views = widget.minimums.keys.toList(growable: false);
        final expandedIndices = [
          for (var i = 0; i < views.length; i++)
            if (!widget.collapsed.contains(views[i])) i,
        ];
        final first = expandedIndices.isEmpty ? 0 : expandedIndices.first;
        final last = expandedIndices.isEmpty ? 0 : expandedIndices.last;
        final dividerCount = last - first;
        final collapsedCount = views.length - expandedIndices.length;
        final vertical = widget.axis == Axis.vertical;
        final extent = vertical ? constraints.maxHeight : constraints.maxWidth;
        final header = collapsedCount == 0
            ? 0.0
            : math.min(widget.collapsedExtent, extent / collapsedCount);
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
        return Flex(
          direction: widget.axis,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < views.length; i++) ...[
              SizedBox(
                key: ValueKey(views[i]),
                width: vertical ? null : sizes[views[i]],
                height: vertical ? sizes[views[i]] : null,
                child: widget.buildPane(views[i], sizes[views[i]]!),
              ),
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
}
