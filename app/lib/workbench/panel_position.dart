/// Root edge and orientation used to place the shared Panel region.
library;

import 'package:flutter/painting.dart' show Axis;

import 'layout_controller.dart';
import 'layout_model.dart';

enum PanelPosition { top, bottom, left, right }

extension on PanelPosition {
  Axis get axis => switch (this) {
        PanelPosition.top || PanelPosition.bottom => Axis.vertical,
        PanelPosition.left || PanelPosition.right => Axis.horizontal,
      };

  bool get isLeadingEdge =>
      this == PanelPosition.top || this == PanelPosition.left;
}

extension WorkbenchPanelPosition on WorkbenchLayout {
  /// The root split orientation and child order are the persisted position.
  /// A nested, duplicated, or non-edge Panel is not a supported shape.
  PanelPosition? get panelPosition {
    if (root.children.length < 2) return null;
    final index = _panelRootIndex(root);
    if (index == 0) {
      return root.axis == Axis.vertical
          ? PanelPosition.top
          : PanelPosition.left;
    }
    if (index == root.children.length - 1) {
      return root.axis == Axis.vertical
          ? PanelPosition.bottom
          : PanelPosition.right;
    }
    return null;
  }

  /// Move the Panel leaf to a root edge while keeping the existing root,
  /// Panel leaf, siblings, and workspace subtrees intact. Returns false when
  /// the requested position is already active or the root shape is unsupported.
  bool setPanelPosition(PanelPosition target, {bool notify = true}) {
    final index = _panelRootIndex(root);
    if (root.children.length < 2 || index < 0 || panelPosition == null) {
      return false;
    }
    if (panelPosition == target) return false;

    final panel = root.children.removeAt(index);
    root.axis = target.axis;
    if (target.isLeadingEdge) {
      root.children.insert(0, panel);
    } else {
      root.children.add(panel);
    }
    final centerAligned =
        (root.panelAlignment ?? PanelAlignment.center) == PanelAlignment.center;
    if (panelMaximized &&
        !centerAligned &&
        (target == PanelPosition.top || target == PanelPosition.bottom)) {
      setPanelMaximized(false, notify: false);
    }
    if (notify) notifyLayoutChanged();
    return true;
  }
}

int _panelRootIndex(WbSplit root) {
  if (root.leaves.where((leaf) => leaf.region == 'panel').length != 1) {
    return -1;
  }
  var panelIndex = -1;
  for (var i = 0; i < root.children.length; i++) {
    final node = root.children[i];
    if (node is WbLeaf && node.region == 'panel') {
      if (panelIndex != -1) return -1;
      panelIndex = i;
    }
  }
  return panelIndex;
}
