/// Built-in Activity Bar view assignments and selection for both side bars.
library;

import 'layout_controller.dart';
import 'layout_model.dart';

extension WorkbenchSidebarViewLocations on WorkbenchLayout {
  /// Built-in views assigned to a side. Legacy layouts put all four views in
  /// the Primary Side Bar.
  List<String> sidebarViews(String location) {
    final normalized = normalizeSidebarViewLocations(
      root.sidebarViewLocations,
    );
    return [
      for (final id in activityBarViewOrder)
        if (normalized[id] == location) id,
    ];
  }

  String sidebarViewLocation(String view) {
    if (!activityBarViewOrder.contains(view)) {
      throw ArgumentError.value(view, 'view', 'unknown built-in view');
    }
    return normalizeSidebarViewLocations(root.sidebarViewLocations)[view]!;
  }

  /// Current Primary selection; malformed or stale values fall back to the
  /// first assigned view. An empty side has no selection.
  String? get primarySidebarView => _selectedView(
        root.primarySidebarView,
        primarySidebarViewLocation,
      );

  /// Current Secondary selection; malformed or stale values fall back to the
  /// first assigned view. An empty side has no selection.
  String? get secondarySidebarView => _selectedView(
        root.secondarySidebarView,
        secondarySidebarViewLocation,
      );

  String? sidebarSelection(String location) => switch (location) {
        primarySidebarViewLocation => primarySidebarView,
        secondarySidebarViewLocation => secondarySidebarView,
        _ => throw ArgumentError.value(location, 'location'),
      };

  bool selectSidebarView(String view) {
    if (!activityBarViewOrder.contains(view)) return false;
    final location = sidebarViewLocation(view);
    final selected = sidebarSelection(location);
    if (selected == view && root.sidebarViewLocations != null) return false;

    root.sidebarViewLocations = normalizeSidebarViewLocations(
      root.sidebarViewLocations,
    );
    if (location == primarySidebarViewLocation) {
      root.primarySidebarView = view;
    } else {
      root.secondarySidebarView = view;
    }
    notifyLayoutChanged();
    return true;
  }

  /// Assign [view] to a side and select it there. If it was the source side's
  /// selection, select the first remaining view in Activity Bar order.
  bool moveSidebarView(String view, String destination) {
    if (!activityBarViewOrder.contains(view)) return false;
    if (destination != primarySidebarViewLocation &&
        destination != secondarySidebarViewLocation) {
      return false;
    }

    final locations = normalizeSidebarViewLocations(
      root.sidebarViewLocations,
    );
    final source = locations[view]!;
    if (source == destination) return false;

    final sourceSelection = sidebarSelection(source);
    locations[view] = destination;
    root.sidebarViewLocations = locations;

    final sourceFallback = _firstViewAt(source, locations);
    if (source == primarySidebarViewLocation) {
      if (sourceSelection == view) root.primarySidebarView = sourceFallback;
      root.secondarySidebarView = view;
    } else {
      if (sourceSelection == view) root.secondarySidebarView = sourceFallback;
      root.primarySidebarView = view;
    }

    notifyLayoutChanged();
    return true;
  }

  String? _selectedView(String? raw, String location) {
    final available = sidebarViews(location);
    if (available.isEmpty) return null;
    if (raw != null && available.contains(raw)) return raw;
    return available.first;
  }

  String? _firstViewAt(String location, Map<String, String> locations) {
    for (final id in normalizeActivityBarViewOrder(root.activityBarOrder)) {
      if (locations[id] == location) return id;
    }
    return null;
  }
}
