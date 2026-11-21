import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:flutter/gestures.dart'
    show PointerDownEvent, PointerMoveEvent, kPrimaryButton;
import 'package:flutter/material.dart';

import 'layout_model.dart';

/// A vertical split within one side bar entry. Drag previews are local until
/// the pointer is released, so cancellation leaves the saved layout intact.
class SidebarGroupSplit extends StatefulWidget {
  const SidebarGroupSplit({
    super.key,
    required this.location,
    required this.panes,
    required this.weights,
    required this.onCommit,
  }) : assert(panes.length > 1);

  final String location;
  final Map<String, Widget> panes;
  final Map<String, double> weights;
  final ValueChanged<Map<String, double>> onCommit;

  @override
  State<SidebarGroupSplit> createState() => _SidebarGroupSplitState();
}

class _SidebarGroupSplitState extends State<SidebarGroupSplit> {
  static const _minimumPaneExtent = 148.0;

  ({int index, int pointer})? _drag;
  Map<String, double>? _preview;

  @override
  void didUpdateWidget(covariant SidebarGroupSplit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(
            oldWidget.panes.keys.toList(), widget.panes.keys.toList()) ||
        !mapEquals(oldWidget.weights, widget.weights)) {
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
    setState(() {
      _preview = {
        for (var i = 0; i < views.length; i++) views[i]: updated[i],
      };
    });
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final views = widget.panes.keys.toList(growable: false);
        final dividerCount = views.length - 1;
        final extent = constraints.maxHeight;
        final thickness = math.min(
          workbenchDividerThickness,
          extent / dividerCount,
        );
        final inside = math.max(0.0, extent - thickness * dividerCount);
        final extents = _split(views).extentsFor(inside);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < views.length; i++) ...[
              SizedBox(
                key: ValueKey(views[i]),
                height: extents[i],
                child: widget.panes[views[i]],
              ),
              if (i < dividerCount)
                SizedBox(
                  key: ValueKey(
                    'sidebar-group-sash-${widget.location}-${views[i]}-${views[i + 1]}',
                  ),
                  height: thickness,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeUpDown,
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (event) => _start(i, event),
                      onPointerMove: (event) =>
                          _resize(views, i, event, inside),
                      onPointerUp: (event) =>
                          _finish(i, event.pointer, commit: true),
                      onPointerCancel: (event) =>
                          _finish(i, event.pointer, commit: false),
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
            ],
          ],
        );
      },
    );
  }
}
