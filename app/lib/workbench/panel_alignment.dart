/// Panel alignment state and the presentation-only workbench reflow.
library;

import 'package:flutter/painting.dart' show Axis;

import 'layout_controller.dart';
import 'layout_model.dart';
import 'panel_position.dart';

extension WorkbenchPanelAlignment on WorkbenchLayout {
  /// Legacy layouts without alignment metadata use Code-OSS's Center default.
  PanelAlignment get panelAlignment =>
      root.panelAlignment ?? PanelAlignment.center;

  /// Select an alignment. Code-OSS only aligns a top/bottom Panel; a command
  /// issued while it is left/right first moves it to the bottom.
  bool setPanelAlignment(PanelAlignment target) {
    var changed = false;
    final position = panelPosition;
    if (position == PanelPosition.left || position == PanelPosition.right) {
      changed = setPanelPosition(PanelPosition.bottom);
    }
    if (panelAlignment != target) {
      root.panelAlignment = target;
      changed = true;
    }
    if (changed) notifyLayoutChanged();
    return changed;
  }
}

/// A temporary split tree that changes only the rendered geometry. The saved
/// layout tree remains canonical, so existing Activity Bar, Side Bar, and
/// Panel position operations continue to work against the same region nodes.
class PanelAlignmentProjection {
  PanelAlignmentProjection._({
    required this.tree,
    required this.outerRow,
    required this.panelColumn,
    required this.editorRow,
    required this.mainRow,
    required this.panelColumnWidthNodes,
  });

  final WbSplit tree;
  final WbSplit outerRow;
  final WbSplit panelColumn;
  final WbSplit editorRow;
  final WbSplit mainRow;
  final List<WbNode> panelColumnWidthNodes;

  /// Synthetic split weights are copied into the canonical nodes after a
  /// drag, keeping sash changes stable across layout notifications and saves.
  void syncAfterDividerDrag(WbSplit split) {
    if (identical(split, panelColumn)) {
      mainRow.weight = editorRow.weight;
    }
    if (identical(split, outerRow)) {
      _syncAggregateWeight(panelColumnWidthNodes, panelColumn.weight);
    }
  }
}

// This only exists in the projection tree and is always collapsed. A split
// wrapper needs two children even when the selected editor row has one node.
const _alignmentSpacer = '__panel_alignment_spacer__';

/// Build the Code-OSS alignment geometry for the standard root Panel layout.
/// Unsupported custom trees keep their existing geometry and state intact.
PanelAlignmentProjection? projectPanelAlignment(WorkbenchLayout layout) {
  final position = layout.panelPosition;
  if (position != PanelPosition.top && position != PanelPosition.bottom) {
    return null;
  }

  final root = layout.root;
  final panelIndices = <int>[
    for (var i = 0; i < root.children.length; i++)
      if (root.children[i] case WbLeaf(region: 'panel')) i,
  ];
  if (panelIndices.length != 1) return null;
  final panel = root.children[panelIndices.single] as WbLeaf;
  final mainRows = <WbSplit>[
    for (var i = 0; i < root.children.length; i++)
      if (i != panelIndices.single && root.children[i] is WbSplit)
        root.children[i] as WbSplit,
  ];
  if (mainRows.length != 1 || mainRows.single.axis != Axis.horizontal) {
    return null;
  }

  final mainRow = mainRows.single;
  final children = mainRow.children;
  int? uniqueIndex(bool Function(WbNode) predicate) {
    final indices = <int>[
      for (var i = 0; i < children.length; i++)
        if (predicate(children[i])) i,
    ];
    return indices.length == 1 ? indices.single : null;
  }

  bool hasRegion(WbNode node, String region) =>
      node.leaves.any((leaf) => leaf.region == region);
  bool hasEditor(WbNode node) => node.leaves.any(
      (leaf) => leaf.region == 'editor' || leaf.region.startsWith('editor-'));

  final primaryIndex = uniqueIndex((node) => hasRegion(node, 'sidebar'));
  final secondaryIndex = uniqueIndex(
    (node) => hasRegion(node, 'secondarySidebar'),
  );
  final activityIndex = uniqueIndex((node) => hasRegion(node, 'activity'));
  final editorIndices = <int>[
    for (var i = 0; i < children.length; i++)
      if (hasEditor(children[i])) i,
  ];
  if (primaryIndex == null ||
      secondaryIndex == null ||
      editorIndices.isEmpty ||
      primaryIndex == secondaryIndex) {
    return null;
  }

  final sideBarPosition = root.sideBarPosition ?? SideBarPosition.left;
  final primaryInEditorBranch =
      !(layout.panelAlignment == PanelAlignment.center ||
          (sideBarPosition == SideBarPosition.left &&
              layout.panelAlignment == PanelAlignment.right) ||
          (sideBarPosition == SideBarPosition.right &&
              layout.panelAlignment == PanelAlignment.left));
  final secondaryInEditorBranch =
      !(layout.panelAlignment == PanelAlignment.center ||
          (sideBarPosition == SideBarPosition.right &&
              layout.panelAlignment == PanelAlignment.right) ||
          (sideBarPosition == SideBarPosition.left &&
              layout.panelAlignment == PanelAlignment.left));
  final activityIsPrimary = activityIndex == primaryIndex;
  final activityIsSeparate = activityIndex != null && !activityIsPrimary;

  final editorBranchNodes = <WbNode>[];
  for (var i = 0; i < children.length; i++) {
    if (activityIsSeparate && i == activityIndex) continue;
    if (i == primaryIndex && !primaryInEditorBranch) continue;
    if (i == secondaryIndex && !secondaryInEditorBranch) continue;
    editorBranchNodes.add(children[i]);
  }
  if (editorBranchNodes.isEmpty) return null;

  final editorRowChildren = List<WbNode>.of(editorBranchNodes);
  if (editorRowChildren.length == 1) {
    editorRowChildren.add(WbLeaf(
      region: _alignmentSpacer,
      collapsed: true,
      lastWeight: 1,
    ));
  }
  final editorRow = WbSplit(
    axis: Axis.horizontal,
    name: 'panel-alignment-editor-row',
    weight: mainRow.weight,
    children: editorRowChildren,
  );
  final panelColumnWidth = _sumFlexibleWeights(editorBranchNodes);
  if (panelColumnWidth <= 0) return null;
  final panelColumn = WbSplit(
    axis: Axis.vertical,
    name: 'panel-alignment-column',
    weight: panelColumnWidth,
    children:
        position == PanelPosition.top ? [panel, editorRow] : [editorRow, panel],
  );

  final activity = activityIsSeparate ? children[activityIndex] : null;
  final primary = children[primaryIndex];
  final secondary = children[secondaryIndex];
  final primaryOutside = !primaryInEditorBranch;
  final secondaryOutside = !secondaryInEditorBranch;
  final outerChildren = <WbNode>[];
  if (sideBarPosition == SideBarPosition.left) {
    if (activity != null) outerChildren.add(activity);
    if (primaryOutside) outerChildren.add(primary);
    outerChildren.add(panelColumn);
    if (secondaryOutside) outerChildren.add(secondary);
  } else {
    if (secondaryOutside) outerChildren.add(secondary);
    outerChildren.add(panelColumn);
    if (primaryOutside) outerChildren.add(primary);
    if (activity != null) outerChildren.add(activity);
  }
  if (outerChildren.length < 2) return null;

  final outerRow = WbSplit(
    axis: Axis.horizontal,
    name: 'panel-alignment-root',
    children: outerChildren,
  );
  return PanelAlignmentProjection._(
    tree: outerRow,
    outerRow: outerRow,
    panelColumn: panelColumn,
    editorRow: editorRow,
    mainRow: mainRow,
    panelColumnWidthNodes: editorBranchNodes,
  );
}

double _sumFlexibleWeights(Iterable<WbNode> nodes) => nodes.fold(
      0,
      (sum, node) => sum + _flexibleWeight(node),
    );

double _flexibleWeight(WbNode node) {
  if (node case WbLeaf(:final fixedExtent, :final collapsed)) {
    if (fixedExtent != null || collapsed) return 0;
  }
  return node.weight;
}

void _syncAggregateWeight(List<WbNode> nodes, double targetWeight) {
  final currentWeight = _sumFlexibleWeights(nodes);
  if (currentWeight <= 0 || targetWeight <= 0) return;
  final scale = targetWeight / currentWeight;
  for (final node in nodes) {
    if (_flexibleWeight(node) == 0) continue;
    node.weight *= scale;
  }
}
