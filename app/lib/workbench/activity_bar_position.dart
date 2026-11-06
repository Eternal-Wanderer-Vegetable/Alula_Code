/// Activity Bar location changes and their layout-tree transformations.
library;

import 'package:flutter/painting.dart' show Axis;

import 'layout_controller.dart';
import 'layout_model.dart';

extension WorkbenchActivityBarPosition on WorkbenchLayout {
  /// The persisted placement, with P05.11 JSON compatibility when metadata is
  /// absent: a collapsed Activity leaf means Hidden, otherwise Side.
  ActivityBarLocation get activityBarLocation {
    return root.activityBarLocation ??
        (root.leafOf('activity')?.collapsed == true
            ? ActivityBarLocation.hidden
            : ActivityBarLocation.side);
  }

  /// Move the Activity leaf and update its root JSON metadata. Returns false
  /// when the layout has no Activity/Sidebar pair or no state changed.
  bool setActivityBarLocation(ActivityBarLocation target) {
    final activity = root.leafOf('activity');
    final sidebar = root.leafOf('sidebar');
    if (activity == null || sidebar == null) return false;

    var changed = false;
    if (target == ActivityBarLocation.hidden) {
      if (!activity.collapsed) {
        activity.lastWeight = activity.weight;
        activity.collapsed = true;
        changed = true;
      }
    } else {
      final moved = _moveActivityLeaf(root, target);
      if (moved == null) return false;
      changed = moved;
      if (activity.collapsed) {
        activity.collapsed = false;
        activity.lastWeight = null;
        changed = true;
      }
    }

    if (root.activityBarLocation != target) {
      root.activityBarLocation = target;
      changed = true;
    }
    if (root.activityBarSize == null) {
      root.activityBarSize = ActivityBarSize.defaultSize;
      changed = true;
    }
    if (target != ActivityBarLocation.hidden) {
      final nextExtent = target == ActivityBarLocation.side
          ? root.activityBarSize!.sideExtent
          : 44.0;
      if (activity.fixedExtent != nextExtent) {
        activity.fixedExtent = nextExtent;
        changed = true;
      }
    }
    if (changed) notifyLayoutChanged();
    return changed;
  }
}

bool? _moveActivityLeaf(WbSplit root, ActivityBarLocation target) {
  final activityParent = root.parentSplitOf('activity');
  final sidebarParent = root.parentSplitOf('sidebar');
  if (activityParent == null ||
      sidebarParent == null ||
      !identical(activityParent, sidebarParent)) {
    return null;
  }

  final parent = activityParent;
  final activityIndex = parent.children.indexWhere(
    (node) => node is WbLeaf && node.region == 'activity',
  );
  final sidebarIndex = parent.children.indexWhere(
    (node) => node is WbLeaf && node.region == 'sidebar',
  );
  if (activityIndex < 0 || sidebarIndex < 0) return null;
  final activity = parent.children[activityIndex] as WbLeaf;
  final sidebar = parent.children[sidebarIndex] as WbLeaf;

  if (parent.axis == Axis.horizontal) {
    if (target == ActivityBarLocation.side) return false;
    final groupWeight = sidebar.weight;
    parent.children.removeAt(activityIndex);
    final newSidebarIndex = parent.children.indexWhere(
      (node) => node is WbLeaf && node.region == 'sidebar',
    );
    if (newSidebarIndex < 0) return null;

    // In Top/Bottom mode the primary sidebar is a vertical stack: the same
    // 44px Activity extent becomes height, while its outer weight remains the
    // former Sidebar weight and the editor weight is left untouched.
    sidebar.weight = 1;
    parent.children[newSidebarIndex] = WbSplit(
      axis: Axis.vertical,
      weight: groupWeight,
      name: 'primary-sidebar',
      children: target == ActivityBarLocation.top
          ? [activity, sidebar]
          : [sidebar, activity],
    );
    return true;
  }

  if (parent.axis != Axis.vertical || parent.children.length != 2) {
    return null;
  }

  if (target == ActivityBarLocation.top ||
      target == ActivityBarLocation.bottom) {
    final desired = target == ActivityBarLocation.top
        ? <WbLeaf>[activity, sidebar]
        : <WbLeaf>[sidebar, activity];
    if (identical(parent.children[0], desired[0]) &&
        identical(parent.children[1], desired[1])) {
      return false;
    }
    parent.children
      ..clear()
      ..addAll(desired);
    return true;
  }

  if (target != ActivityBarLocation.side) return null;
  final outerParent = _parentOfSplit(root, parent);
  if (outerParent == null) return null;
  final groupIndex =
      outerParent.children.indexWhere((node) => identical(node, parent));
  if (groupIndex < 0) return null;

  sidebar.weight = parent.weight;
  outerParent.children
    ..removeAt(groupIndex)
    ..insertAll(groupIndex, [activity, sidebar]);
  return true;
}

WbSplit? _parentOfSplit(WbSplit root, WbSplit target) {
  WbSplit? walk(WbSplit parent) {
    for (final child in parent.children) {
      if (identical(child, target)) return parent;
      if (child is WbSplit) {
        final found = walk(child);
        if (found != null) return found;
      }
    }
    return null;
  }

  return walk(root);
}
