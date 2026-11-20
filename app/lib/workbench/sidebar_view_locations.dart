/// Built-in Activity Bar assignments to the side bars or panel.
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
    if (location == panelSidebarViewLocation) {
      return [
        for (final entry in normalized.entries)
          if (entry.value == location) entry.key,
      ];
    }
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
    if (location == panelSidebarViewLocation) return false;
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

  List<String> get standalonePanelViews => [
        for (final view in sidebarViews(panelSidebarViewLocation))
          if (!root.panelViewPlacements.containsKey(view)) view,
      ];

  List<String> groupedPanelViews(PanelViewTab tab, {required bool before}) => [
        for (final entry in root.panelViewPlacements.entries)
          if (entry.value == (tab: tab, before: before)) entry.key,
      ];

  /// Assign [view] to a side or panel. Select a replacement if it was the
  /// source side's selection. Panel placements can use a standard tab.
  bool moveSidebarView(
    String view,
    String destination, {
    PanelViewPlacement? panelPlacement,
  }) {
    if (!activityBarViewOrder.contains(view)) return false;
    if (destination != primarySidebarViewLocation &&
        destination != secondarySidebarViewLocation &&
        destination != panelSidebarViewLocation) {
      return false;
    }

    if (panelPlacement != null && destination != panelSidebarViewLocation) {
      return false;
    }

    final locations = normalizeSidebarViewLocations(
      root.sidebarViewLocations,
    );
    final source = locations[view]!;
    if (source == destination) return false;

    final sourceSelection =
        source == panelSidebarViewLocation ? null : sidebarSelection(source);
    if (destination == panelSidebarViewLocation) {
      locations.remove(view);
    }
    locations[view] = destination;
    root.sidebarViewLocations = locations;
    if (panelPlacement == null) {
      root.panelViewPlacements.remove(view);
    } else {
      root.panelViewPlacements[view] = panelPlacement;
    }

    if (sourceSelection == view) {
      final sourceFallback = _firstViewAt(source, locations);
      if (source == primarySidebarViewLocation) {
        root.primarySidebarView = sourceFallback;
      } else {
        root.secondarySidebarView = sourceFallback;
      }
    }
    if (destination == primarySidebarViewLocation) {
      root.primarySidebarView = view;
    } else if (destination == secondarySidebarViewLocation) {
      root.secondarySidebarView = view;
    }

    notifyLayoutChanged();
    return true;
  }

  /// Restore the built-in views to their implicit default assignment.
  /// A null location map keeps legacy/default layouts compact in JSON.
  bool resetSidebarViewLocations() {
    if (root.sidebarViewLocations == null &&
        root.primarySidebarView == null &&
        root.secondarySidebarView == null) {
      return false;
    }

    root.sidebarViewLocations = null;
    root.panelViewPlacements.clear();
    root.primarySidebarView = null;
    root.secondarySidebarView = null;
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
