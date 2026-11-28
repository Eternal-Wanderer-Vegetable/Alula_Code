/// Legacy layout migration for the secondary side bar region.
library;

import 'package:flutter/painting.dart' show Axis;

import 'layout_model.dart';

const secondarySidebarRegion = 'secondarySidebar';
const secondarySidebarDefaultWeight = 0.26;
const secondarySidebarMinimumWidth = 170.0;

extension WbSplitSecondarySidebar on WbSplit {
  /// Adds the default hidden secondary side bar beside the editor when loading
  /// a layout written before the region existed. Returns false if already
  /// present or if this is not a recognizable workbench editor row.
  bool ensureSecondarySidebar() {
    if (leafOf(secondarySidebarRegion) != null) return false;

    final row = _editorRowContainingPrimarySidebar(this);
    if (row == null) return false;

    var lastEditorChild = -1;
    for (var i = 0; i < row.children.length; i++) {
      if (_containsEditorGroup(row.children[i])) lastEditorChild = i;
    }
    if (lastEditorChild < 0) return false;

    row.children.insert(
      lastEditorChild + 1,
      WbLeaf(
        region: secondarySidebarRegion,
        weight: secondarySidebarDefaultWeight,
        minExtent: secondarySidebarMinimumWidth,
        collapsed: true,
        lastWeight: secondarySidebarDefaultWeight,
      ),
    );
    return true;
  }
}

WbSplit? _editorRowContainingPrimarySidebar(WbSplit root) {
  if (root.axis == Axis.horizontal &&
      root.children.any(_containsPrimarySidebar) &&
      root.children.any(_containsEditorGroup)) {
    return root;
  }

  for (final child in root.children) {
    if (child is WbSplit) {
      final found = _editorRowContainingPrimarySidebar(child);
      if (found != null) return found;
    }
  }
  return null;
}

bool _containsPrimarySidebar(WbNode node) =>
    node.leaves.any((leaf) => leaf.region == 'sidebar');

bool _containsEditorGroup(WbNode node) => node.leaves.any(
      (leaf) => leaf.region == 'editor' || leaf.region.startsWith('editor-'),
    );
