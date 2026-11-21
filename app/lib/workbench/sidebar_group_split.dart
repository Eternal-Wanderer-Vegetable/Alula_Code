import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/material.dart';

import 'pane_group_drop_target.dart';
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
      child: PaneGroupDropTarget<_SidebarGroupPaneDrag>(
        axis: Axis.vertical,
        view: view,
        highlightKeyPrefix: 'sidebar-group-drop-${widget.location}-$view',
        sourceFor: (data) => identical(data.group, _group) ? data.view : null,
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
