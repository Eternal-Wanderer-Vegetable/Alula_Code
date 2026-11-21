import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/material.dart';

import 'pane_group_header.dart';
import 'pane_group_split.dart';

/// The panes inside one side bar entry, including their interactive headers.
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
    required this.onReorder,
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
  final void Function(String source, String target, bool before) onReorder;

  @override
  State<SidebarGroupSplit> createState() => _SidebarGroupSplitState();
}

class _SidebarGroupSplitState extends State<SidebarGroupSplit> {
  static const _minimumPaneExtent = 148.0;
  static const _headerExtent = 28.0;

  final _group = Object();

  @override
  Widget build(BuildContext context) {
    return PaneGroupSplit(
      axis: Axis.vertical,
      minimums: {
        for (final view in widget.panes.keys) view: _minimumPaneExtent
      },
      weights: widget.weights,
      collapsed: widget.collapsed,
      collapsedExtent: _headerExtent,
      sashKeyPrefix: 'sidebar-group-sash-${widget.location}',
      buildPane: _buildPane,
      onCommit: widget.onCommit,
    );
  }

  Widget _buildPane(String view, double extent) {
    final collapsed = widget.collapsed.contains(view);
    final role = view == widget.container ? 'original-' : '';
    final label = widget.labels[view]!;
    return SizedBox(
      key: ValueKey('${widget.location}-sidebar-group-$role$view'),
      height: extent,
      child: _SidebarGroupDropTarget(
        group: _group,
        view: view,
        location: widget.location,
        onReorder: widget.onReorder,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: math.min(_headerExtent, extent),
              child: Draggable<_SidebarGroupPaneDrag>(
                data: (group: _group, view: view),
                maxSimultaneousDrags: 1,
                allowedButtonsFilter: (buttons) => buttons == kPrimaryButton,
                dragAnchorStrategy: pointerDragAnchorStrategy,
                feedback: Material(
                  color: const Color(0xFF252932),
                  borderRadius: BorderRadius.circular(3),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Text(label, style: const TextStyle(fontSize: 12)),
                  ),
                ),
                child: PaneGroupHeader(
                  semanticsKey:
                      ValueKey('sidebar-group-header-${widget.location}-$view'),
                  label: label,
                  collapsed: collapsed,
                  onSetCollapsed: (value) => widget.onSetCollapsed(view, value),
                  onFocus: () => widget.onFocus(view),
                ),
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
      ),
    );
  }
}

typedef _SidebarGroupPaneDrag = ({Object group, String view});

class _SidebarGroupDropTarget extends StatefulWidget {
  const _SidebarGroupDropTarget({
    required this.group,
    required this.view,
    required this.location,
    required this.onReorder,
    required this.child,
  });

  final Object group;
  final String view;
  final String location;
  final void Function(String source, String target, bool before) onReorder;
  final Widget child;

  @override
  State<_SidebarGroupDropTarget> createState() =>
      _SidebarGroupDropTargetState();
}

class _SidebarGroupDropTargetState extends State<_SidebarGroupDropTarget> {
  bool _before = true;

  bool _accepts(_SidebarGroupPaneDrag source) =>
      identical(source.group, widget.group) && source.view != widget.view;

  bool _isBefore(Offset position) {
    final target = context.findRenderObject()! as RenderBox;
    return target.globalToLocal(position).dy < target.size.height / 2;
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<_SidebarGroupPaneDrag>(
      onWillAcceptWithDetails: (details) => _accepts(details.data),
      onMove: (details) {
        if (!_accepts(details.data)) return;
        final before = _isBefore(details.offset);
        if (_before != before) setState(() => _before = before);
      },
      onAcceptWithDetails: (details) {
        if (_accepts(details.data)) {
          widget.onReorder(
            details.data.view,
            widget.view,
            _isBefore(details.offset),
          );
        }
      },
      builder: (context, candidates, _) => Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (candidates.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: FractionallySizedBox(
                  heightFactor: 0.5,
                  alignment:
                      _before ? Alignment.topCenter : Alignment.bottomCenter,
                  child: DecoratedBox(
                    key: ValueKey(
                      'sidebar-group-drop-${widget.location}-${widget.view}-'
                      '${_before ? 'before' : 'after'}',
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0x30007ACC),
                      border: Border.fromBorderSide(
                        BorderSide(color: Color(0xFF55B8FF)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
