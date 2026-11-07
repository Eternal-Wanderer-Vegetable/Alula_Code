/// Primary/secondary Side Bar placement and layout-tree transformations.
library;

import 'package:flutter/painting.dart' show Axis;

import 'layout_controller.dart';
import 'layout_model.dart';
import 'secondary_sidebar_layout.dart';

const primarySidebarRegion = 'sidebar';
const activityBarRegion = 'activity';

extension WorkbenchSideBarPosition on WorkbenchLayout {
  /// Position of the Primary Side Bar. Older layouts default to Left.
  SideBarPosition get sideBarPosition =>
      root.sideBarPosition ?? SideBarPosition.left;

  /// Toggle the Primary Side Bar between Left and Right.
  bool toggleSideBarPosition() => setSideBarPosition(
        sideBarPosition == SideBarPosition.left
            ? SideBarPosition.right
            : SideBarPosition.left,
      );

  /// Put the Primary Side Bar at [target] and the Secondary Side Bar opposite.
  /// Existing nodes are moved as-is so their sizes, visibility, and contents
  /// remain unchanged. Returns false when the workbench row is unsupported or
  /// the requested position is already active.
  bool setSideBarPosition(SideBarPosition target) {
    if (target == sideBarPosition) return false;

    final row = _mainRowForSideBars(root);
    if (row == null) return false;
    final primary = _primarySideBarNodes(root, row);
    if (primary == null) return false;
    final secondaryIndex = row.children.indexWhere(
      (node) => node is WbLeaf && node.region == secondarySidebarRegion,
    );
    if (secondaryIndex < 0) return false;
    final secondary = row.children[secondaryIndex];

    final middle = row.children
        .where((node) =>
            !primary.any((primaryNode) => identical(primaryNode, node)) &&
            !identical(node, secondary))
        .toList();
    if (!middle.any(_containsEditorGroup)) return false;

    final cluster = primary.length == 2
        ? target == SideBarPosition.left
            ? primary
            : primary.reversed.toList()
        : primary;
    final next = target == SideBarPosition.left
        ? <WbNode>[...cluster, ...middle, secondary]
        : <WbNode>[secondary, ...middle, ...cluster];

    root.sideBarPosition = target;
    row.children
      ..clear()
      ..addAll(next);
    notifyLayoutChanged();
    return true;
  }
}

WbSplit? _mainRowForSideBars(WbSplit root) {
  final row = root.parentSplitOf(secondarySidebarRegion);
  if (row == null || row.axis != Axis.horizontal) return null;
  if (!row.children.any(_containsEditorGroup) ||
      !row.children.any(_containsPrimarySideBar)) {
    return null;
  }
  return row;
}

List<WbNode>? _primarySideBarNodes(WbSplit root, WbSplit row) {
  final activityLeaves = root.leaves
      .where((leaf) => leaf.region == activityBarRegion)
      .toList(growable: false);
  final sidebarLeaves = root.leaves
      .where((leaf) => leaf.region == primarySidebarRegion)
      .toList(growable: false);
  if (activityLeaves.length != 1 || sidebarLeaves.length != 1) return null;

  final activity = activityLeaves.single;
  final sidebar = sidebarLeaves.single;
  final activityParent = root.parentSplitOf(activityBarRegion);
  final sidebarParent = root.parentSplitOf(primarySidebarRegion);
  if (identical(activityParent, row) && identical(sidebarParent, row)) {
    if (!row.children.contains(activity) || !row.children.contains(sidebar)) {
      return null;
    }
    return [activity, sidebar];
  }

  if (activityParent == null ||
      !identical(activityParent, sidebarParent) ||
      activityParent.axis != Axis.vertical ||
      !activityParent.leaves.any((leaf) => leaf.region == activityBarRegion) ||
      !activityParent.leaves
          .any((leaf) => leaf.region == primarySidebarRegion) ||
      !row.children.any((node) => identical(node, activityParent))) {
    return null;
  }
  return [activityParent];
}

bool _containsPrimarySideBar(WbNode node) =>
    node.leaves.any((leaf) => leaf.region == primarySidebarRegion);

bool _containsEditorGroup(WbNode node) => node.leaves.any(
      (leaf) => leaf.region == 'editor' || leaf.region.startsWith('editor-'),
    );
