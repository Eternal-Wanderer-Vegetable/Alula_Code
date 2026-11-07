/// Runtime Panel maximize/restore state and upstream eligibility rules.
library;

import 'layout_controller.dart';
import 'layout_model.dart';
import 'panel_alignment.dart';
import 'panel_position.dart';

extension WorkbenchPanelMaximization on WorkbenchLayout {
  /// VS Code supports every Center-aligned Panel position and non-center
  /// alignment only while the Panel is docked to a side.
  bool get canMaximizePanel {
    final position = panelPosition;
    if (position == null) return false;
    return panelAlignment == PanelAlignment.center ||
        position == PanelPosition.left ||
        position == PanelPosition.right;
  }

  /// Runs `workbench.action.toggleMaximizedPanel` semantics. A hidden Panel is
  /// revealed and maximized; if it was already maximized while hidden, it is
  /// simply revealed in that state.
  bool togglePanelMaximization() {
    if (!canMaximizePanel) return false;

    if (isCollapsed('panel')) {
      setRegionCollapsed('panel', false);
      if (!panelMaximized) setPanelMaximized(true);
      return true;
    }

    setPanelMaximized(!panelMaximized);
    return true;
  }
}
