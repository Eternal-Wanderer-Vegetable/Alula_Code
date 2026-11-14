/// Activity Bar view ordering and its root layout metadata updates.
library;

import 'package:flutter/foundation.dart' show listEquals;

import 'layout_controller.dart';
import 'layout_model.dart';

extension WorkbenchActivityBarOrder on WorkbenchLayout {
  /// The current order; legacy layouts use the built-in default order.
  List<String> get activityBarOrder => List.unmodifiable(
        normalizeActivityBarViewOrder(root.activityBarOrder),
      );

  /// Persist a normalized order and notify layout listeners when it changes.
  bool setActivityBarOrder(Object? order) {
    final normalized = normalizeActivityBarViewOrder(order);
    if (listEquals(activityBarOrder, normalized)) return false;

    root.activityBarOrder = normalized;
    notifyLayoutChanged();
    return true;
  }
}
