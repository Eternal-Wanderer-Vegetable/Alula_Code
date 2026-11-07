/// Activity Bar size changes and their layout-tree updates.
library;

import 'layout_controller.dart';
import 'layout_model.dart';

extension WorkbenchActivityBarSize on WorkbenchLayout {
  /// The selected density, with older layouts defaulting to Default.
  ActivityBarSize get activityBarSize =>
      root.activityBarSize ?? ActivityBarSize.defaultSize;

  /// Updates the Activity Bar density and its fixed side extent when visible
  /// in the side position. Horizontal Activity Bars keep their 44 px height.
  bool setActivityBarSize(ActivityBarSize target) {
    final activity = root.leafOf('activity');
    if (activity == null) return false;

    final isSide = root.activityBarLocation == ActivityBarLocation.side ||
        (root.activityBarLocation == null && !activity.collapsed);
    final nextExtent = isSide ? target.sideExtent : activity.fixedExtent;
    final changed = root.activityBarSize != target ||
        (nextExtent != null && activity.fixedExtent != nextExtent);
    if (!changed) return false;

    root.activityBarSize = target;
    if (nextExtent != null) activity.fixedExtent = nextExtent;
    notifyLayoutChanged();
    return true;
  }
}
