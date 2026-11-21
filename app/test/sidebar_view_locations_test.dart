import 'package:alula_app/workbench/activity_bar_order.dart';
import 'package:alula_app/workbench/activity_bar_pins.dart';
import 'package:alula_app/workbench/activity_bar_badges.dart';
import 'package:alula_app/workbench/activity_bar_global_actions.dart';
import 'package:alula_app/workbench/activity_bar_position.dart';
import 'package:alula_app/workbench/activity_bar_size.dart';
import 'package:alula_app/workbench/layout_controller.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/sidebar_position.dart';
import 'package:alula_app/workbench/secondary_sidebar_layout.dart';
import 'package:alula_app/workbench/sidebar_view_locations.dart';
import 'package:flutter/painting.dart' show Axis;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy layout defaults every built-in view to Primary', () {
    final legacy = WbNode.fromJson(defaultLayout().toJson()) as WbSplit;
    final layout = WorkbenchLayout(root: legacy);

    expect(
        layout.sidebarViews(primarySidebarViewLocation), activityBarViewOrder);
    expect(layout.sidebarViews(secondarySidebarViewLocation), isEmpty);
    expect(layout.primarySidebarView, 'explorer');
    expect(layout.secondarySidebarView, isNull);
    expect(legacy.toJson().containsKey('sidebarViewLocations'), isFalse,
        reason: 'legacy state stays compact until the user changes it');
    layout.dispose();
  });

  test('location metadata drops unknown IDs and invalid destinations', () {
    final json = defaultLayout().toJson()
      ..['sidebarViewLocations'] = {
        'explorer': secondarySidebarViewLocation,
        'search': 'unsupported',
        'unknown-view': secondarySidebarViewLocation,
      };
    final layout = WorkbenchLayout(root: WbNode.fromJson(json) as WbSplit);

    expect(layout.sidebarViews(secondarySidebarViewLocation), ['explorer']);
    expect(layout.sidebarViews(primarySidebarViewLocation),
        ['search', 'outline', 'git']);
    expect(layout.root.toJson()['sidebarViewLocations'], {
      'explorer': secondarySidebarViewLocation,
      'search': primarySidebarViewLocation,
      'outline': primarySidebarViewLocation,
      'git': primarySidebarViewLocation,
    });
    layout.dispose();
  });

  test('panel assignments round-trip and reset with side-bar selections', () {
    final layout = WorkbenchLayout();
    expect(layout.selectSidebarView('search'), isTrue);
    expect(layout.moveSidebarView('outline', panelSidebarViewLocation), isTrue);
    expect(layout.moveSidebarView('search', panelSidebarViewLocation), isTrue);
    expect(layout.primarySidebarView, 'explorer');
    expect(layout.sidebarViews(panelSidebarViewLocation), ['outline', 'search']);
    expect(layout.selectSidebarView('search'), isFalse);
    final saved = WbNode.fromJson(layout.root.toJson()) as WbSplit;
    final restored = WorkbenchLayout(root: saved);
    expect(
        restored.sidebarViews(panelSidebarViewLocation), ['outline', 'search']);
    expect(
        restored.sidebarViews(primarySidebarViewLocation), ['explorer', 'git']);
    expect(restored.moveSidebarView('search', secondarySidebarViewLocation),
        isTrue);
    expect(restored.secondarySidebarView, 'search');
    expect(restored.sidebarViews(panelSidebarViewLocation), ['outline']);
    expect(restored.resetSidebarViewLocations(), isTrue);
    expect(restored.sidebarViews(panelSidebarViewLocation), isEmpty);
    expect(restored.sidebarViews(primarySidebarViewLocation),
        activityBarViewOrder);
    expect(restored.secondarySidebarView, isNull);
    layout.dispose();
    restored.dispose();
  });

  test('moves one view, selects destination, and preserves Activity Bar state',
      () {
    final layout = WorkbenchLayout();
    layout.setActivityBarOrder(['git', 'explorer', 'search', 'outline']);
    layout.setActivityBarPinnedViews(['git', 'search']);
    var changes = 0;
    layout.addListener(() => changes++);
    changes = 0;

    expect(
      layout.moveSidebarView('explorer', secondarySidebarViewLocation),
      isTrue,
    );
    expect(layout.sidebarViews(primarySidebarViewLocation),
        ['search', 'outline', 'git']);
    expect(layout.sidebarViews(secondarySidebarViewLocation), ['explorer']);
    expect(layout.primarySidebarView, 'git');
    expect(layout.secondarySidebarView, 'explorer');
    expect(layout.activityBarOrder, ['git', 'explorer', 'search', 'outline']);
    expect(layout.activityBarPinnedViews, ['git', 'search']);
    expect(changes, 1);

    expect(
      layout.moveSidebarView('explorer', secondarySidebarViewLocation),
      isFalse,
      reason: 'choosing the current side is a no-op',
    );
    expect(changes, 1);

    final encoded = layout.root.toJson();
    final restored = WorkbenchLayout(
      root: WbNode.fromJson(encoded) as WbSplit,
    );
    expect(restored.sidebarViews(primarySidebarViewLocation),
        ['search', 'outline', 'git']);
    expect(restored.sidebarViews(secondarySidebarViewLocation), ['explorer']);
    expect(restored.primarySidebarView, 'git');
    expect(restored.secondarySidebarView, 'explorer');
    expect(restored.activityBarOrder, layout.activityBarOrder);
    expect(restored.activityBarPinnedViews, layout.activityBarPinnedViews);
    restored.dispose();
    layout.dispose();
  });

  test('selection follows a view after movement and empty sides stay empty',
      () {
    final layout = WorkbenchLayout();

    expect(layout.moveSidebarView('explorer', secondarySidebarViewLocation),
        isTrue);
    expect(layout.selectSidebarView('outline'), isTrue);
    expect(layout.primarySidebarView, 'outline');
    expect(layout.selectSidebarView('explorer'), isFalse,
        reason: 'selecting the already selected view is a no-op');
    expect(layout.secondarySidebarView, 'explorer');

    for (final view in ['search', 'outline', 'git']) {
      expect(
          layout.moveSidebarView(view, secondarySidebarViewLocation), isTrue);
    }
    expect(layout.sidebarViews(primarySidebarViewLocation), isEmpty);
    expect(layout.primarySidebarView, isNull);
    expect(layout.sidebarViews(secondarySidebarViewLocation),
        activityBarViewOrder);

    final restored = WorkbenchLayout(
      root: WbNode.fromJson(layout.root.toJson()) as WbSplit,
    );
    expect(restored.primarySidebarView, isNull);
    expect(restored.sidebarViews(secondarySidebarViewLocation),
        activityBarViewOrder);
    restored.dispose();
    layout.dispose();
  });

  test('each built-in view moves in both directions without changing layout',
      () {
    final layout = WorkbenchLayout();
    layout.splitRegion('editor', 'editor-2', Axis.horizontal);
    layout.setActivityBarOrder(['git', 'explorer', 'search', 'outline']);
    layout.setActivityBarPinnedViews(['git', 'search']);
    layout.setActivityBarBadgesDisabledViews(['outline']);
    layout.setActivityBarAccountsVisible(false);
    layout.setActivityBarSize(ActivityBarSize.compact);
    layout.setActivityBarLocation(ActivityBarLocation.top);
    layout.setSideBarPosition(SideBarPosition.right);
    layout.setRegionCollapsed('panel', false);
    layout.setRegionCollapsed('sidebar', true);
    layout.leafOf('sidebar')!.weight = 0.41;

    final unrelatedBefore = _withoutViewMetadata(layout.root.toJson());
    for (final view in activityBarViewOrder) {
      expect(layout.moveSidebarView(view, secondarySidebarViewLocation), isTrue,
          reason: '$view moves to Secondary');
      expect(layout.sidebarViewLocation(view), secondarySidebarViewLocation);
      expect(layout.moveSidebarView(view, primarySidebarViewLocation), isTrue,
          reason: '$view moves back to Primary');
      expect(layout.sidebarViewLocation(view), primarySidebarViewLocation);
    }
    expect(_withoutViewMetadata(layout.root.toJson()), unrelatedBefore,
        reason:
            'Activity Bar, positioning, editor split, dimensions, and Panel state survive');
    layout.dispose();
  });

  test('reset restores implicit defaults and preserves unrelated layout state',
      () {
    final layout = WorkbenchLayout();
    layout.splitRegion('editor', 'editor-2', Axis.vertical);
    layout.setActivityBarOrder(['git', 'explorer', 'search', 'outline']);
    layout.setActivityBarPinnedViews(['git', 'explorer']);
    layout.setActivityBarBadgesDisabledViews(['outline']);
    layout.setActivityBarAccountsVisible(false);
    layout.setActivityBarSize(ActivityBarSize.compact);
    layout.setActivityBarLocation(ActivityBarLocation.top);
    layout.setSideBarPosition(SideBarPosition.right);
    layout.setRegionCollapsed('sidebar', false);
    layout.setRegionCollapsed(secondarySidebarRegion, false);
    layout.setRegionCollapsed('panel', true);
    layout.leafOf('sidebar')!.weight = 0.42;
    layout.leafOf(secondarySidebarRegion)!.weight = 0.31;
    expect(
        layout.moveSidebarView('search', secondarySidebarViewLocation), isTrue);
    expect(layout.moveSidebarView('outline', secondarySidebarViewLocation),
        isTrue);
    expect(
        layout.moveSidebarView('outline', primarySidebarViewLocation), isTrue);
    expect(layout.selectSidebarView('git'), isTrue);

    final unrelatedBefore = _withoutViewMetadata(layout.root.toJson());
    var changes = 0;
    layout.addListener(() => changes++);

    expect(layout.resetSidebarViewLocations(), isTrue);
    expect(
        layout.sidebarViews(primarySidebarViewLocation), activityBarViewOrder);
    expect(layout.sidebarViews(secondarySidebarViewLocation), isEmpty);
    expect(layout.primarySidebarView, 'explorer');
    expect(layout.secondarySidebarView, isNull);
    expect(layout.root.sidebarViewLocations, isNull,
        reason: 'default assignments are represented implicitly');
    expect(layout.root.primarySidebarView, isNull);
    expect(layout.root.secondarySidebarView, isNull);
    expect(layout.root.toJson().containsKey('sidebarViewLocations'), isFalse);
    expect(_withoutViewMetadata(layout.root.toJson()), unrelatedBefore);
    expect(changes, 1);

    final restored = WorkbenchLayout(
      root: WbNode.fromJson(layout.root.toJson()) as WbSplit,
    );
    expect(restored.sidebarViews(primarySidebarViewLocation),
        activityBarViewOrder);
    expect(restored.primarySidebarView, 'explorer');
    expect(restored.secondarySidebarView, isNull);
    expect(_withoutViewMetadata(restored.root.toJson()), unrelatedBefore);
    expect(layout.resetSidebarViewLocations(), isFalse,
        reason: 'reset is idempotent at the implicit defaults');
    expect(changes, 1);

    restored.dispose();
    layout.dispose();
  });

  test('reset clears a stale selection in a layout without location metadata',
      () {
    final root = defaultLayout()..primarySidebarView = 'search';
    final layout = WorkbenchLayout(root: root);

    expect(layout.primarySidebarView, 'search');
    expect(layout.resetSidebarViewLocations(), isTrue);
    expect(layout.primarySidebarView, 'explorer');
    expect(layout.secondarySidebarView, isNull);
    expect(layout.root.toJson().containsKey('sidebarViewLocations'), isFalse);
    layout.dispose();
  });

  test('grouped Panel placements persist without changing standalone tabs', () {
    final layout = WorkbenchLayout();
    expect(layout.root.toJson(), isNot(contains('panelViewPlacements')));
    const placement = (tab: PanelViewTab.gitDiff, before: true);
    expect(
      layout.moveSidebarView('search', secondarySidebarViewLocation,
          panelPlacement: placement),
      isFalse,
    );
    expect(layout.selectSidebarView('search'), isTrue);
    expect(
      layout.moveSidebarView('search', panelSidebarViewLocation,
          panelPlacement: placement),
      isTrue,
    );
    expect(layout.moveSidebarView('outline', panelSidebarViewLocation), isTrue);
    expect(layout.primarySidebarView, 'explorer');
    expect(layout.standalonePanelViews, ['outline']);
    expect(layout.groupedPanelViews(PanelViewTab.gitDiff, before: true),
        ['search']);
    expect(layout.groupedPanelViews(PanelViewTab.gitDiff, before: false),
        isEmpty);

    final json = layout.root.toJson();
    expect(json['panelViewPlacements'], {
      'search': {'tab': 'gitDiff', 'before': true},
    });
    final placements = json['panelViewPlacements']! as Map<String, Object?>;
    placements['explorer'] = {'tab': 'gitDiff', 'before': false};
    placements['outline'] = {'tab': 'gitDiff', 'before': 'true'};
    placements['unknown'] = {'tab': 'diagnostics', 'before': false};
    final restored = WorkbenchLayout(root: WbSplit.fromJson(json));
    expect(restored.root.panelViewPlacements, {'search': placement});
    expect(restored.standalonePanelViews, ['outline']);
    expect(restored.moveSidebarView('search', primarySidebarViewLocation),
        isTrue);
    expect(restored.root.panelViewPlacements, isEmpty);
    expect(restored.root.toJson(), isNot(contains('panelViewPlacements')));

    expect(layout.resetSidebarViewLocations(), isTrue);
    expect(layout.root.panelViewPlacements, isEmpty);
    expect(layout.sidebarViewLocation('search'), primarySidebarViewLocation);
    restored.dispose();
    layout.dispose();
  });


  test('reorder uses a relative target and preserves per-pane layout state',
      () {
    final layout = WorkbenchLayout();
    layout.moveSidebarView('search', panelSidebarViewLocation);
    layout.moveSidebarView(
      'search',
      primarySidebarViewLocation,
      sidebarPlacement: (container: 'explorer', before: true),
    );
    layout.moveSidebarView('git', panelSidebarViewLocation);
    layout.moveSidebarView(
      'git',
      primarySidebarViewLocation,
      sidebarPlacement: (container: 'explorer', before: false),
    );
    layout.setSidebarGroupPaneCollapsed('search', true);
    layout.setSidebarGroupPaneWeights(
      'explorer',
      {'search': 1.22, 'explorer': 0.78, 'git': 1.0},
    );
    final weights = Map.of(layout.root.sidebarGroupPaneWeights);
    var changes = 0;
    layout.addListener(() => changes++);

    expect(
      layout.reorderSidebarGroupPane('explorer', 'search', 'explorer',
          before: true),
      isFalse,
    );
    expect(
      layout.reorderSidebarGroupPane('explorer', 'search', 'search',
          before: true),
      isFalse,
    );
    expect(
      layout.reorderSidebarGroupPane('explorer', 'search', 'outline',
          before: false),
      isFalse,
    );
    expect(changes, 0);
    expect(
      layout.reorderSidebarGroupPane('explorer', 'search', 'git',
          before: false),
      isTrue,
    );
    expect(layout.groupedSidebarViews('explorer', before: true), isEmpty);
    expect(layout.groupedSidebarViews('explorer', before: false),
        ['git', 'search']);
    expect(
      layout.reorderSidebarGroupPane('explorer', 'explorer', 'search',
          before: false),
      isTrue,
    );
    expect(layout.groupedSidebarViews('explorer', before: true),
        ['git', 'search']);
    expect(layout.groupedSidebarViews('explorer', before: false), isEmpty);
    expect(changes, 2);

    final restored =
        WorkbenchLayout(root: WbSplit.fromJson(layout.root.toJson()));
    expect(restored.groupedSidebarViews('explorer', before: true),
        ['git', 'search']);
    expect(restored.root.sidebarGroupCollapsedPanes, {'search'});
    expect(restored.root.sidebarGroupPaneWeights, weights);
    expect(restored.primarySidebarView, 'explorer');
    expect(restored.sidebarViewLocation('search'), primarySidebarViewLocation);
    restored.dispose();
    layout.dispose();
  });

  test('Panel pane sizes persist per standard tab and discard stale members',
      () {
    final layout = WorkbenchLayout();
    const tab = PanelViewTab.diagnostics;
    const otherTab = PanelViewTab.syntax;
    expect(layout.root.toJson(), isNot(contains('panelGroupPaneWeights')));
    for (final (view, tab) in [
      ('search', tab),
      ('git', tab),
      ('outline', otherTab)
    ]) {
      expect(
          layout.moveSidebarView(
            view,
            panelSidebarViewLocation,
            panelPlacement: (tab: tab, before: true),
          ),
          isTrue);
    }
    expect(
        layout.setPanelGroupPaneWeights(
            tab, {panelGroupOriginalPane: 1, 'search': 2}),
        isFalse);
    expect(
        layout.setPanelGroupPaneWeights(
            tab, {panelGroupOriginalPane: 2, 'search': 3, 'git': 1}),
        isTrue);
    expect(
        layout.setPanelGroupPaneWeights(
            otherTab, {panelGroupOriginalPane: 3, 'outline': 1}),
        isTrue);
    final saved = layout.root.toJson();
    final byTab = Map<String, Object?>.of(
      saved['panelGroupPaneWeights']! as Map<String, Object?>,
    );
    saved['panelGroupPaneWeights'] = byTab;
    final group = byTab[tab.name]! as Map<String, double>;
    group['obsolete'] = 0.3;
    byTab[PanelViewTab.gitDiff.name] = {panelGroupOriginalPane: 1};
    byTab['unknown'] = {panelGroupOriginalPane: 1};
    final restored = WorkbenchLayout(root: WbSplit.fromJson(saved));
    expect(restored.root.panelGroupPaneWeights, {
      tab: {panelGroupOriginalPane: 1.0, 'search': 1.5, 'git': 0.5},
      otherTab: {panelGroupOriginalPane: 1.5, 'outline': 0.5},
    });
    expect(
        restored.moveSidebarView('search', primarySidebarViewLocation), isTrue);
    expect(restored.root.panelGroupPaneWeights[tab],
        {panelGroupOriginalPane: 1.0, 'git': 0.5});
    expect(
        restored.moveSidebarView('git', secondarySidebarViewLocation), isTrue);
    expect(restored.root.panelGroupPaneWeights.keys, [otherTab]);
    expect(restored.resetSidebarViewLocations(), isTrue);
    expect(restored.root.toJson(), isNot(contains('panelGroupPaneWeights')));
    restored.dispose();
    layout.dispose();
  });

  test('Panel pane reorder keeps the original and member state in their tab',
      () {
    final layout = WorkbenchLayout();
    const tab = PanelViewTab.diagnostics;
    const otherTab = PanelViewTab.syntax;
    for (final (view, owner, before) in [
      ('search', tab, true),
      ('git', tab, false),
      ('outline', otherTab, true),
    ]) {
      layout.moveSidebarView(
        view,
        panelSidebarViewLocation,
        panelPlacement: (tab: owner, before: before),
      );
    }
    layout.setPanelGroupPaneCollapsed(tab, 'search', true);
    layout.setPanelGroupPaneWeights(
        tab, {'search': 1.3, 'git': .9, 'original': .8});
    final weights = Map.of(layout.root.panelGroupPaneWeights[tab]!);
    var changes = 0;
    layout.addListener(() => changes++);

    expect(
        layout.reorderPanelGroupPane(tab, 'search', 'original', before: true),
        isFalse);
    expect(layout.reorderPanelGroupPane(tab, 'search', 'search', before: true),
        isFalse);
    expect(
        layout.reorderPanelGroupPane(tab, 'search', 'outline', before: false),
        isFalse);
    expect(changes, 0);
    expect(layout.reorderPanelGroupPane(tab, 'search', 'git', before: false),
        isTrue);
    expect(layout.groupedPanelViews(tab, before: false), ['git', 'search']);
    expect(
        layout.reorderPanelGroupPane(tab, 'original', 'search', before: false),
        isTrue);
    expect(layout.groupedPanelViews(tab, before: true), ['git', 'search']);
    expect(layout.groupedPanelViews(otherTab, before: true), ['outline']);
    expect(changes, 2);

    final restored =
        WorkbenchLayout(root: WbSplit.fromJson(layout.root.toJson()));
    expect(restored.groupedPanelViews(tab, before: true), ['git', 'search']);
    expect(restored.groupedPanelViews(tab, before: false), isEmpty);
    expect(restored.root.panelGroupCollapsedPanes, {
      tab: {'search'}
    });
    expect(restored.root.panelGroupPaneWeights[tab], weights);
    expect(restored.root.panelViewPlacements['outline'],
        (tab: otherTab, before: true));
    restored.dispose();
    layout.dispose();
  });

  test(
      'detaching a member preserves its side and selects its independent entry',
      () {
    final layout = WorkbenchLayout();
    addTearDown(layout.dispose);
    const side = secondarySidebarViewLocation;
    layout.moveSidebarView('git', side);
    for (final view in ['search', 'outline']) {
      layout.moveSidebarView(view, side,
          sidebarPlacement: (container: 'git', before: view == 'search'));
    }
    layout.setSidebarGroupPaneWeights(
        'git', {'git': 1, 'search': .8, 'outline': 1.2});
    layout.setSidebarGroupPaneCollapsed('outline', true);
    final locations = Map.of(layout.root.sidebarViewLocations!);
    var changes = 0;
    layout.addListener(() => changes++);

    expect(layout.moveSidebarView('search', side), isFalse);
    expect(layout.moveSidebarView('git', side, detachFromSidebarGroup: true),
        isFalse);
    expect(changes, 0);
    expect(layout.moveSidebarView('search', side, detachFromSidebarGroup: true),
        isTrue);
    expect(changes, 1);
    expect(layout.root.sidebarViewLocations, locations);
    expect(layout.secondarySidebarView, 'search');
    expect(layout.root.sidebarViewPlacements,
        {'outline': (container: 'git', before: false)});
    expect(layout.root.sidebarGroupPaneWeights, {'git': 1, 'outline': 1.2});
    expect(layout.root.sidebarGroupCollapsedPanes, {'outline'});
    expect(layout.moveSidebarView('search', side, detachFromSidebarGroup: true),
        isFalse);
    expect(changes, 1);
  });

  test('moving a sidebar container persists the entire group atomically', () {
    final layout = WorkbenchLayout();
    addTearDown(layout.dispose);
    const primary = primarySidebarViewLocation;
    const secondary = secondarySidebarViewLocation;
    for (final view in ['search', 'outline']) {
      layout.moveSidebarView(view, panelSidebarViewLocation);
      layout.moveSidebarView(view, primary,
          sidebarPlacement: (container: 'explorer', before: view == 'search'));
    }
    layout.setSidebarGroupPaneWeights(
        'explorer', {'explorer': 1, 'search': .8, 'outline': 1.2});
    layout.setSidebarGroupPaneCollapsed('outline', true);
    final placements = Map.of(layout.root.sidebarViewPlacements);
    final weights = Map.of(layout.root.sidebarGroupPaneWeights);
    final observed = <List<String>>[];
    layout.addListener(() {
      observed.add([
        for (final view in ['explorer', 'search', 'outline'])
          layout.sidebarViewLocation(view),
      ]);
    });

    expect(layout.moveSidebarView('search', secondary, moveSidebarGroup: true),
        isFalse);
    expect(layout.moveSidebarView('explorer', primary, moveSidebarGroup: true),
        isFalse);
    expect(
        layout.moveSidebarView('explorer', panelSidebarViewLocation,
            moveSidebarGroup: true),
        isFalse);
    expect(observed, isEmpty);

    expect(
        layout.moveSidebarView('explorer', secondary, moveSidebarGroup: true),
        isTrue);
    expect(observed, [
      [secondary, secondary, secondary],
    ]);
    expect(layout.primarySidebarView, 'git');
    expect(layout.secondarySidebarView, 'explorer');
    expect(layout.root.sidebarViewPlacements, placements);
    expect(layout.root.sidebarGroupPaneWeights, weights);
    expect(layout.root.sidebarGroupCollapsedPanes, {'outline'});

    final restored =
        WorkbenchLayout(root: WbSplit.fromJson(layout.root.toJson()));
    addTearDown(restored.dispose);
    expect(restored.secondarySidebarView, 'explorer');
    expect(restored.groupedSidebarViews('explorer', before: true), ['search']);
    expect(
        restored.groupedSidebarViews('explorer', before: false), ['outline']);
    expect(restored.root.sidebarGroupPaneWeights, weights);
    expect(restored.root.sidebarGroupCollapsedPanes, {'outline'});
  });

  test('relative sidebar insertion saves order with the move', () {
    final layout = WorkbenchLayout();
    addTearDown(layout.dispose);
    const side = secondarySidebarViewLocation;
    const tab = PanelViewTab.diagnostics;
    layout.moveSidebarView('explorer', side);
    layout.moveSidebarView('outline', side,
        sidebarPlacement: (container: 'explorer', before: false));
    for (final view in ['search', 'git']) {
      layout.moveSidebarView(view, panelSidebarViewLocation,
          panelPlacement: (tab: tab, before: false));
    }
    layout.setSidebarGroupPaneWeights(
        'explorer', {'explorer': .9, 'outline': 1.1});
    layout.setSidebarGroupPaneCollapsed('outline', true);
    final weights = Map.of(layout.root.sidebarGroupPaneWeights);
    final notifications = <List<String>>[];
    layout.addListener(() {
      notifications.add(layout.groupedSidebarViews('explorer', before: false));
    });

    expect(
      layout.moveSidebarView('search', side,
          sidebarPlacement: (container: 'explorer', before: true),
          sidebarTarget: 'git'),
      isFalse,
    );
    expect(layout.sidebarViewLocation('search'), panelSidebarViewLocation);
    expect(notifications, isEmpty);

    expect(
      layout.moveSidebarView('search', side,
          sidebarPlacement: (container: 'explorer', before: true),
          sidebarTarget: 'outline'),
      isTrue,
    );
    expect(notifications, [
      ['search', 'outline'],
    ]);
    expect(layout.groupedPanelViews(tab, before: false), ['git']);
    expect(layout.secondarySidebarView, 'explorer');
    expect(layout.root.sidebarGroupPaneWeights, weights);
    expect(layout.root.sidebarGroupCollapsedPanes, {'outline'});

    final restored =
        WorkbenchLayout(root: WbSplit.fromJson(layout.root.toJson()));
    addTearDown(restored.dispose);
    expect(restored.groupedSidebarViews('explorer', before: false),
        ['search', 'outline']);
    expect(restored.root.sidebarGroupPaneWeights, weights);
  });

  test('relative panel insertion keeps one atomic layout update', () {
    final layout = WorkbenchLayout();
    addTearDown(layout.dispose);
    const tab = PanelViewTab.diagnostics;
    layout.moveSidebarView('outline', panelSidebarViewLocation,
        panelPlacement: (tab: tab, before: true));
    layout.moveSidebarView('git', panelSidebarViewLocation,
        panelPlacement: (tab: PanelViewTab.syntax, before: false));
    layout.setPanelGroupPaneWeights(tab, {'original': 1.4, 'outline': .6});
    layout.setPanelGroupPaneCollapsed(tab, 'outline', true);
    final oldWeights = Map.of(layout.root.panelGroupPaneWeights[tab]!);
    final notifications = <List<String>>[];
    layout.addListener(() {
      notifications.add(layout.groupedPanelViews(tab, before: true));
    });

    expect(
      layout.moveSidebarView('search', panelSidebarViewLocation,
          panelPlacement: (tab: tab, before: true), panelTarget: 'git'),
      isFalse,
    );
    expect(layout.sidebarViewLocation('search'), primarySidebarViewLocation);
    expect(notifications, isEmpty);

    expect(
      layout.moveSidebarView('search', panelSidebarViewLocation,
          panelPlacement: (tab: tab, before: true), panelTarget: 'original'),
      isTrue,
    );
    expect(notifications, [
      ['outline', 'search'],
    ]);
    expect(layout.standalonePanelViews, isEmpty);
    expect(
        layout.groupedPanelViews(PanelViewTab.syntax, before: false), ['git']);
    expect(layout.root.panelGroupPaneWeights[tab], oldWeights);
    expect(layout.root.panelGroupCollapsedPanes[tab], {'outline'});

    final restored =
        WorkbenchLayout(root: WbSplit.fromJson(layout.root.toJson()));
    addTearDown(restored.dispose);
    expect(
        restored.groupedPanelViews(tab, before: true), ['outline', 'search']);
    expect(restored.root.panelGroupPaneWeights[tab], oldWeights);
  });

  test('Panel pane collapse persists per tab and clears with its group', () {
    final layout = WorkbenchLayout();
    const tab = PanelViewTab.diagnostics;
    const otherTab = PanelViewTab.syntax;
    expect(layout.root.toJson(), isNot(contains('panelGroupCollapsedPanes')));
    expect(layout.setPanelGroupPaneCollapsed(tab, panelGroupOriginalPane, true),
        isFalse);
    for (final (view, tab) in [('search', tab), ('outline', otherTab)]) {
      layout.moveSidebarView(
        view,
        panelSidebarViewLocation,
        panelPlacement: (tab: tab, before: false),
      );
    }
    expect(layout.setPanelGroupPaneCollapsed(tab, 'outline', true), isFalse);
    expect(layout.setPanelGroupPaneCollapsed(tab, 'search', true), isTrue);
    expect(layout.setPanelGroupPaneCollapsed(tab, 'search', true), isFalse);
    expect(layout.setPanelGroupPaneCollapsed(tab, panelGroupOriginalPane, true),
        isTrue);
    expect(
        layout.setPanelGroupPaneCollapsed(otherTab, 'outline', true), isTrue);

    final saved = layout.root.toJson();
    final groups = Map<String, Object?>.of(
      saved['panelGroupCollapsedPanes']! as Map<String, Object?>,
    );
    groups[tab.name] = [
      'search',
      'outline',
      panelGroupOriginalPane,
      false,
      'search'
    ];
    groups[PanelViewTab.gitDiff.name] = [panelGroupOriginalPane];
    saved['panelGroupCollapsedPanes'] = groups;
    final restored = WorkbenchLayout(root: WbSplit.fromJson(saved));
    expect(restored.root.panelGroupCollapsedPanes, {
      tab: {'search', panelGroupOriginalPane},
      otherTab: {'outline'},
    });
    expect(
        restored.moveSidebarView('search', primarySidebarViewLocation), isTrue);
    expect(restored.root.panelGroupCollapsedPanes, {
      otherTab: {'outline'}
    });
    expect(restored.resetSidebarViewLocations(), isTrue);
    expect(restored.root.toJson(), isNot(contains('panelGroupCollapsedPanes')));
    restored.dispose();
    layout.dispose();
  });

  test('group collapse round-trips and clears when a group is removed', () {
    final layout = WorkbenchLayout();
    expect(layout.root.toJson(), isNot(contains('sidebarGroupCollapsedPanes')));
    expect(layout.setSidebarGroupPaneCollapsed('explorer', true), isFalse);
    layout.moveSidebarView('search', panelSidebarViewLocation);
    layout.moveSidebarView(
      'search',
      primarySidebarViewLocation,
      sidebarPlacement: (container: 'explorer', before: true),
    );

    var changes = 0;
    layout.addListener(() => changes++);
    expect(layout.setSidebarGroupPaneCollapsed('search', true), isTrue);
    expect(layout.setSidebarGroupPaneCollapsed('search', true), isFalse);
    expect(layout.setSidebarGroupPaneCollapsed('explorer', true), isTrue);
    expect(changes, 2);
    final saved = layout.root.toJson();
    expect(saved['sidebarGroupCollapsedPanes'], ['search', 'explorer']);
    expect(
      WbSplit.fromJson({...saved}..remove('sidebarGroupCollapsedPanes'))
          .sidebarGroupCollapsedPanes,
      isEmpty,
    );
    saved['sidebarGroupCollapsedPanes'] = [
      'search',
      'explorer',
      'explorer',
      'git',
      false,
      'unknown',
    ];
    final restored = WorkbenchLayout(root: WbSplit.fromJson(saved));
    expect(restored.root.sidebarGroupCollapsedPanes, {'search', 'explorer'});
    expect(
        restored.moveSidebarView('search', panelSidebarViewLocation), isTrue);
    expect(restored.root.sidebarGroupCollapsedPanes, isEmpty);
    expect(
        restored.root.toJson(), isNot(contains('sidebarGroupCollapsedPanes')));
    expect(layout.resetSidebarViewLocations(), isTrue);
    expect(layout.root.sidebarGroupCollapsedPanes, isEmpty);
    restored.dispose();
    layout.dispose();
  });

  test('Primary group keeps its container selected and restores orphaned views', () {
    final layout = WorkbenchLayout();
    expect(layout.root.toJson(), isNot(contains('sidebarViewPlacements')));
    expect(layout.moveSidebarView('search', panelSidebarViewLocation,
        panelPlacement: (tab: PanelViewTab.diagnostics, before: false)), isTrue);
    const placement = (container: 'explorer', before: true);
    expect(layout.moveSidebarView('search', secondarySidebarViewLocation,
        sidebarPlacement: placement), isFalse);
    expect(layout.moveSidebarView('search', primarySidebarViewLocation,
        sidebarPlacement: (container: 'search', before: false)), isFalse);
    expect(layout.moveSidebarView('search', primarySidebarViewLocation,
        sidebarPlacement: placement), isTrue);
    expect(layout.primarySidebarView, 'explorer');
    expect(layout.root.panelViewPlacements, isEmpty);
    expect(layout.groupedSidebarViews('explorer', before: true), ['search']);
    expect(layout.groupedSidebarViews('explorer', before: false), isEmpty);
    expect(layout.selectSidebarView('git'), isTrue);
    expect(layout.selectSidebarView('search'), isTrue);
    expect(layout.primarySidebarView, 'explorer');

    final json = layout.root.toJson();
    expect(json['sidebarViewPlacements'], {
      'search': {'container': 'explorer', 'before': true},
    });
    final placements = json['sidebarViewPlacements']! as Map<String, Object?>;
    placements['outline'] = {'container': 'search', 'before': true};
    placements['git'] = {'container': 'unknown', 'before': false};
    final restored = WorkbenchLayout(root: WbSplit.fromJson(json));
    expect(restored.root.sidebarViewPlacements, {'search': placement});
    expect(restored.primarySidebarView, 'explorer');
    expect(restored.moveSidebarView('explorer', secondarySidebarViewLocation),
        isTrue);
    expect(restored.root.sidebarViewPlacements, isEmpty);
    expect(restored.primarySidebarView, 'search');
    expect(restored.sidebarViewLocation('search'), primarySidebarViewLocation);
    expect(restored.root.toJson(), isNot(contains('sidebarViewPlacements')));

    expect(layout.resetSidebarViewLocations(), isTrue);
    expect(layout.root.sidebarViewPlacements, isEmpty);
    expect(layout.root.toJson(), isNot(contains('sidebarViewPlacements')));
    restored.dispose();
    layout.dispose();
  });


  test('Secondary groups round-trip and keep the current entry selected', () {
    final layout = WorkbenchLayout();
    expect(layout.moveSidebarView('explorer', secondarySidebarViewLocation),
        isTrue);
    expect(layout.moveSidebarView('search', panelSidebarViewLocation,
        panelPlacement: (tab: PanelViewTab.diagnostics, before: false)), isTrue);
    const placement = (container: 'explorer', before: false);
    expect(layout.moveSidebarView('search', secondarySidebarViewLocation,
        sidebarPlacement: placement), isTrue);
    expect(layout.secondarySidebarView, 'explorer');
    expect(layout.primarySidebarView, 'outline');
    expect(layout.groupedSidebarViews('explorer', before: false), ['search']);
    expect(layout.root.panelViewPlacements, isEmpty);

    final json = layout.root.toJson();
    final placements = json['sidebarViewPlacements']! as Map<String, Object?>;
    placements['outline'] = {'container': 'explorer', 'before': false};
    final restored = WorkbenchLayout(root: WbSplit.fromJson(json));
    expect(restored.root.sidebarViewPlacements, {'search': placement});
    expect(restored.secondarySidebarView, 'explorer');
    expect(restored.moveSidebarView('explorer', primarySidebarViewLocation),
        isTrue);
    expect(restored.secondarySidebarView, 'search');
    expect(restored.root.sidebarViewPlacements, isEmpty);
    expect(restored.sidebarViewLocation('search'), secondarySidebarViewLocation);
    restored.dispose();
    layout.dispose();
  });


  test('sidebar pane weights validate participants, round-trip, and prune', () {
    final layout = WorkbenchLayout();
    expect(layout.setSidebarGroupPaneWeights('explorer', {'explorer': 1}),
        isFalse);
    expect(layout.moveSidebarView('search', panelSidebarViewLocation), isTrue);
    expect(layout.moveSidebarView('search', primarySidebarViewLocation,
        sidebarPlacement: (container: 'explorer', before: true)), isTrue);
    expect(layout.setSidebarGroupPaneWeights(
        'explorer', {'search': double.infinity, 'explorer': 1}), isFalse);
    expect(layout.setSidebarGroupPaneWeights(
        'explorer', {'search': 1, 'outline': 1}), isFalse);
    expect(layout.setSidebarGroupPaneWeights(
        'explorer', {'search': 3, 'explorer': 1}), isTrue);
    expect(layout.setSidebarGroupPaneWeights(
        'explorer', {'search': 6, 'explorer': 2}), isFalse);
    expect(layout.root.sidebarGroupPaneWeights, {'search': 1.5, 'explorer': 0.5});
    final json = layout.root.toJson();
    final weights = json['sidebarGroupPaneWeights']! as Map<String, double>;
    weights['outline'] = 1;
    weights['explorer'] = double.nan;
    final rebuilt = WorkbenchLayout(root: WbSplit.fromJson(json));
    expect(rebuilt.root.sidebarGroupPaneWeights, {'search': 1.5});
    expect(layout.root.sidebarGroupPaneWeights, {'search': 1.5, 'explorer': 0.5});

    expect(rebuilt.moveSidebarView('search', secondarySidebarViewLocation),
        isTrue);
    expect(rebuilt.root.sidebarGroupPaneWeights, isEmpty);
    expect(rebuilt.root.toJson(), isNot(contains('sidebarGroupPaneWeights')));
    expect(layout.resetSidebarViewLocations(), isTrue);
    expect(layout.root.sidebarGroupPaneWeights, isEmpty);
    rebuilt.dispose();
    layout.dispose();
  });

}

Map<String, Object?> _withoutViewMetadata(Map<String, Object?> json) {
  return Map<String, Object?>.of(json)
    ..remove('sidebarViewLocations')
    ..remove('primarySidebarView')
    ..remove('secondarySidebarView');
}
