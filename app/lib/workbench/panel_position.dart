/// Top/bottom placement of the shared Panel region.
library;

import 'package:flutter/painting.dart' show Axis;

import 'layout_controller.dart';
import 'layout_model.dart';

enum PanelVerticalPosition { top, bottom }

extension WorkbenchPanelPosition on WorkbenchLayout {
  /// The root split order is the persisted Panel position. A layout with a
  /// non-vertical root or a nested Panel is not a supported position shape.
  PanelVerticalPosition? get panelVerticalPosition {
    if (root.axis != Axis.vertical) return null;
    final index = _panelRootIndex(root);
    if (index == 0) return PanelVerticalPosition.top;
    if (index == root.children.length - 1) {
      return PanelVerticalPosition.bottom;
    }
    return null;
  }

  /// Move the Panel leaf to the first or last root child while keeping the
  /// existing node and all workspace subtrees intact. Returns false when the
  /// requested position is already active or the root shape is unsupported.
  bool setPanelVerticalPosition(PanelVerticalPosition target) {
    if (root.axis != Axis.vertical) return false;
    final index = _panelRootIndex(root);
    if (index < 0) return false;

    final targetIndex =
        target == PanelVerticalPosition.top ? 0 : root.children.length - 1;
    if (index == targetIndex) return false;

    final panel = root.children.removeAt(index);
    if (target == PanelVerticalPosition.top) {
      root.children.insert(0, panel);
    } else {
      root.children.add(panel);
    }
    notifyLayoutChanged();
    return true;
  }
}

int _panelRootIndex(WbSplit root) => root.children.indexWhere(
      (node) => node is WbLeaf && node.region == 'panel',
    );
