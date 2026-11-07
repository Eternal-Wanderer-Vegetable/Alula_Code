/// Activity Bar view pin state and its root layout metadata updates.
library;

import 'package:flutter/foundation.dart' show listEquals;

import 'layout_controller.dart';
import 'layout_model.dart';

extension WorkbenchActivityBarPins on WorkbenchLayout {
  /// Pinned view IDs in the current Activity Bar order. Legacy layouts default
  /// to keeping every built-in view available.
  List<String> get activityBarPinnedViews => List.unmodifiable(
        normalizeActivityBarPinnedViews(
          root.activityBarPinned,
          order: root.activityBarOrder,
        ),
      );

  /// Persist a normalized pin set and notify layout listeners when it changes.
  /// The normalizer prevents corrupt input from hiding every built-in view.
  bool setActivityBarPinnedViews(Object? pinnedViews) {
    if (pinnedViews is List &&
        !pinnedViews.any(
          (id) => id is String && activityBarViewOrder.contains(id),
        )) {
      return false;
    }
    final normalized = normalizeActivityBarPinnedViews(
      pinnedViews,
      order: root.activityBarOrder,
    );
    if (listEquals(activityBarPinnedViews, normalized)) return false;

    root.activityBarPinned = normalized;
    notifyLayoutChanged();
    return true;
  }
}
