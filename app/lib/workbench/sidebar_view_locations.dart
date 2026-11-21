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
    final entry = root.sidebarViewPlacements[view]?.container ?? view;
    final selected = sidebarSelection(location);
    if (selected == entry && root.sidebarViewLocations != null) return false;

    root.sidebarViewLocations = normalizeSidebarViewLocations(
      root.sidebarViewLocations,
    );
    if (location == primarySidebarViewLocation) {
      root.primarySidebarView = entry;
    } else {
      root.secondarySidebarView = entry;
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

  List<String> groupedSidebarViews(String container, {required bool before}) =>
      [
        for (final entry in root.sidebarViewPlacements.entries)
          if (entry.value == (container: container, before: before)) entry.key,
      ];

  /// Persist the committed pane proportions for the current group only.
  bool setSidebarGroupPaneWeights(
      String container, Map<String, double> weights) {
    final panes = {
      container,
      ...groupedSidebarViews(container, before: true),
      ...groupedSidebarViews(container, before: false),
    };
    if (panes.length < 2 ||
        weights.length != panes.length ||
        !panes.every(weights.containsKey) ||
        weights.values.any((weight) => !weight.isFinite || weight <= 0)) {
      return false;
    }
    final total = weights.values.fold(0.0, (sum, weight) => sum + weight);
    if (!total.isFinite) return false;
    final normalized = {
      for (final view in panes) view: (weights[view]! / total) * panes.length,
    };
    if (normalized.values.any((weight) => weight <= 0)) return false;
    final saved = root.sidebarGroupPaneWeights;
    if (normalized.entries.every(
      (entry) => ((saved[entry.key] ?? 1) - entry.value).abs() < 1e-9,
    )) {
      return false;
    }
    saved.addAll(normalized);
    notifyLayoutChanged();
    return true;
  }

  /// Collapse only a pane currently participating in a side bar group.
  bool setSidebarGroupPaneCollapsed(String view, bool collapsed) {
    if (!root.sidebarGroupedPaneIds.contains(view)) return false;
    final panes = root.sidebarGroupCollapsedPanes;
    final changed = collapsed ? panes.add(view) : panes.remove(view);
    if (changed) notifyLayoutChanged();
    return changed;
  }

  /// Assign [view] to a side or panel. Select a replacement if it was the
  /// source side's selection. Panel placements can use a standard tab.
  bool moveSidebarView(
    String view,
    String destination, {
    PanelViewPlacement? panelPlacement,
    SidebarViewPlacement? sidebarPlacement,
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
    if (sidebarPlacement != null) {
      final container = sidebarPlacement.container;
      if (destination == panelSidebarViewLocation ||
          container == view ||
          locations[container] != destination ||
          root.sidebarViewPlacements.containsKey(container)) {
        return false;
      }
    }

    final sourceSelection =
        source == panelSidebarViewLocation ? null : sidebarSelection(source);
    if (destination == panelSidebarViewLocation) {
      locations.remove(view);
    }
    locations[view] = destination;
    root.sidebarViewLocations = locations;
    root.sidebarViewPlacements.remove(view);
    root.sidebarViewPlacements.removeWhere(
      (_, placement) => placement.container == view,
    );
    if (sidebarPlacement != null) {
      root.sidebarViewPlacements[view] = sidebarPlacement;
    }
    final stillGrouped = root.sidebarGroupedPaneIds;
    root.sidebarGroupPaneWeights.remove(view);
    root.sidebarGroupPaneWeights.removeWhere(
      (id, _) => !stillGrouped.contains(id),
    );
    root.sidebarGroupCollapsedPanes.remove(view);
    root.sidebarGroupCollapsedPanes.removeWhere(
      (id) => !stillGrouped.contains(id),
    );
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
      root.primarySidebarView = sidebarPlacement?.container ?? view;
    } else if (destination == secondarySidebarViewLocation) {
      root.secondarySidebarView = sidebarPlacement?.container ?? view;
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
    root.sidebarViewPlacements.clear();
    root.sidebarGroupPaneWeights.clear();
    root.sidebarGroupCollapsedPanes.clear();
    root.primarySidebarView = null;
    root.secondarySidebarView = null;
    notifyLayoutChanged();
    return true;
  }

  String? _selectedView(String? raw, String location) {
    final available = sidebarViews(location)
        .where((view) => !root.sidebarViewPlacements.containsKey(view))
        .toList();
    if (available.isEmpty) return null;
    final entry = root.sidebarViewPlacements[raw]?.container ?? raw;
    if (entry != null && available.contains(entry)) return entry;
    return available.first;
  }

  String? _firstViewAt(String location, Map<String, String> locations) {
    for (final id in normalizeActivityBarViewOrder(root.activityBarOrder)) {
      if (locations[id] == location &&
          !root.sidebarViewPlacements.containsKey(id)) {
        return id;
      }
    }
    return null;
  }
}
