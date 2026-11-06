/// Activity Bar badge presentation values and local hide/show persistence.
library;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;

import 'layout_controller.dart';
import 'layout_model.dart';

enum ActivityBarBadgeType { number, icon, progress }

/// A provider-supplied badge for one built-in Activity Bar view.
@immutable
class ActivityBarBadge {
  const ActivityBarBadge.number({
    required this.value,
    required this.description,
  })  : type = ActivityBarBadgeType.number,
        icon = null;

  const ActivityBarBadge.icon({
    required this.icon,
    required this.description,
  })  : type = ActivityBarBadgeType.icon,
        value = null;

  const ActivityBarBadge.progress({required this.description})
      : type = ActivityBarBadgeType.progress,
        value = null,
        icon = null;

  final ActivityBarBadgeType type;
  final int? value;
  final IconData? icon;
  final String description;

  bool get hasVisibleContent =>
      type != ActivityBarBadgeType.number || (value ?? 0) > 0;

  String get accessibleDescription {
    final supplied = description.trim();
    if (supplied.isNotEmpty) return supplied;
    return switch (type) {
      ActivityBarBadgeType.number => '有 ${value ?? 0} 条通知',
      ActivityBarBadgeType.icon => '有活动通知',
      ActivityBarBadgeType.progress => '正在进行中',
    };
  }

  String? get numberText {
    final count = value ?? 0;
    if (count <= 0) return null;
    if (count <= 999) return '$count';
    final thousands = count ~/ 1000;
    return count % 1000 == 0 ? '${thousands}K' : '${thousands}K+';
  }
}

extension WorkbenchActivityBarBadges on WorkbenchLayout {
  /// IDs with disabled Activity Bar badges. Missing metadata means all enabled.
  List<String> get activityBarBadgesDisabledViews => List.unmodifiable(
        normalizeActivityBarBadgesDisabled(
          root.activityBarBadgesDisabled,
          order: root.activityBarOrder,
        ),
      );

  /// Persist a normalized disabled set. Empty is a valid state that re-enables
  /// badges on every view.
  bool setActivityBarBadgesDisabledViews(Object? disabledViews) {
    final normalized = normalizeActivityBarBadgesDisabled(
      disabledViews,
      order: root.activityBarOrder,
    );
    if (listEquals(activityBarBadgesDisabledViews, normalized)) return false;

    root.activityBarBadgesDisabled = normalized.isEmpty ? null : normalized;
    notifyLayoutChanged();
    return true;
  }
}
