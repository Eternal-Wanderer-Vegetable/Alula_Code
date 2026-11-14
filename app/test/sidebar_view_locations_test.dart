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
        'search': 'panel',
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
}

Map<String, Object?> _withoutViewMetadata(Map<String, Object?> json) {
  return Map<String, Object?>.of(json)
    ..remove('sidebarViewLocations')
    ..remove('primarySidebarView')
    ..remove('secondarySidebarView');
}
