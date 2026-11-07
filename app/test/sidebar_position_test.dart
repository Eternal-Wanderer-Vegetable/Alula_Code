import 'package:alula_app/workbench/activity_bar_position.dart';
import 'package:alula_app/workbench/layout_controller.dart';
import 'package:alula_app/workbench/layout_grid.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/secondary_sidebar_empty_state.dart';
import 'package:alula_app/workbench/sidebar_position.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WbSplit _mainRow(WorkbenchLayout layout) =>
    layout.root.parentSplitOf('secondarySidebar')!;

Widget _gridHost(WorkbenchLayout layout) => MaterialApp(
      home: Scaffold(
        body: WorkbenchGrid(
          layout: layout,
          builders: {
            for (final region in [
              'activity',
              'sidebar',
              'editor',
              'secondarySidebar',
              'panel',
            ])
              region: (_) => ColoredBox(
                    key: ValueKey('probe-$region'),
                    color: Colors.blue,
                    child: region == 'secondarySidebar'
                        ? const SecondarySidebarEmptyState()
                        : null,
                  ),
          },
        ),
      ),
    );

void main() {
  test('position defaults old JSON to Left and persists Right', () {
    final legacyJson = defaultLayout().toJson();
    expect(legacyJson.containsKey('sideBarPosition'), isFalse);
    final legacy = WorkbenchLayout(
      root: WbNode.fromJson(legacyJson) as WbSplit,
    );
    expect(legacy.sideBarPosition, SideBarPosition.left);

    expect(legacy.setSideBarPosition(SideBarPosition.right), isTrue);
    expect(legacy.root.toJson()['sideBarPosition'], 'right');
    final restored = WorkbenchLayout(
      root: WbNode.fromJson(legacy.root.toJson()) as WbSplit,
    );
    expect(restored.sideBarPosition, SideBarPosition.right);
    expect(
      WorkbenchLayout(
        root: WbNode.fromJson(
          legacyJson..['sideBarPosition'] = 'unsupported',
        ) as WbSplit,
      ).sideBarPosition,
      SideBarPosition.left,
    );
    restored.dispose();
    legacy.dispose();
  });

  test(
      'moving preserves editor groups, dimensions, visibility, and panel state',
      () {
    final layout = WorkbenchLayout();
    expect(layout.splitRegion('editor', 'editor-2', Axis.horizontal), isTrue);
    final row = _mainRow(layout);
    final activity = layout.leafOf('activity')!;
    final sidebar = layout.leafOf('sidebar')!;
    final editorGroup = row.children[2] as WbSplit;
    final secondary = layout.leafOf('secondarySidebar')!;
    final panel = layout.leafOf('panel')!;
    layout.setRegionCollapsed('sidebar', true);
    layout.setRegionCollapsed('secondarySidebar', false);
    secondary.weight = 0.33;
    layout.setRegionCollapsed('panel', false);
    final groupJson = editorGroup.toJson();
    final editorWeight = editorGroup.weight;
    final panelWeight = panel.weight;
    var changes = 0;
    layout.addListener(() => changes++);

    expect(layout.toggleSideBarPosition(), isTrue);
    expect(layout.sideBarPosition, SideBarPosition.right);
    expect(row.children, [secondary, editorGroup, sidebar, activity]);
    expect(changes, 1);
    expect(editorGroup.toJson(), groupJson);
    expect(editorGroup.weight, editorWeight);
    expect(sidebar.collapsed, isTrue);
    expect(sidebar.lastWeight, closeTo(0.24, 1e-9));
    expect(secondary.collapsed, isFalse);
    expect(secondary.weight, closeTo(0.33, 1e-9));
    expect(panel.collapsed, isFalse);
    expect(panel.weight, panelWeight);

    expect(layout.toggleSideBarPosition(), isTrue);
    expect(layout.sideBarPosition, SideBarPosition.left);
    expect(row.children, [activity, sidebar, editorGroup, secondary]);
    expect(changes, 2);
    layout.dispose();
  });

  test('Side Bar position composes with all Activity Bar placements', () {
    for (final location in ActivityBarLocation.values) {
      for (final positionFirst in [false, true]) {
        final layout = WorkbenchLayout();
        if (positionFirst) {
          expect(layout.toggleSideBarPosition(), isTrue);
        }
        if (location != ActivityBarLocation.side) {
          layout.setActivityBarLocation(location);
        }
        if (!positionFirst) {
          expect(layout.toggleSideBarPosition(), isTrue);
        }
        final row = _mainRow(layout);

        expect(layout.sideBarPosition, SideBarPosition.right,
            reason: '$location, positionFirst=$positionFirst');
        if (location == ActivityBarLocation.top ||
            location == ActivityBarLocation.bottom) {
          final primary = row.children.last as WbSplit;
          expect(primary.name, 'primary-sidebar');
          expect(primary.axis, Axis.vertical);
          expect(
              primary.leaves.map((leaf) => leaf.region),
              containsAll([
                'activity',
                'sidebar',
              ]));
          expect(
              layout.setActivityBarLocation(ActivityBarLocation.side), isTrue);
        }
        expect(row.children.first, layout.leafOf('secondarySidebar'));
        expect(row.children[row.children.length - 2], layout.leafOf('sidebar'));
        expect(row.children.last, layout.leafOf('activity'));

        expect(layout.toggleSideBarPosition(), isTrue);
        expect(row.children.first, layout.leafOf('activity'));
        expect(row.children[1], layout.leafOf('sidebar'));
        expect(row.children.last, layout.leafOf('secondarySidebar'));
        expect(layout.sideBarPosition, SideBarPosition.left);
        layout.dispose();
      }
    }
  });

  testWidgets('Right places secondary left and Activity Bar at the outer edge',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final layout = WorkbenchLayout();
    layout.setRegionCollapsed('secondarySidebar', false);
    await tester.pumpWidget(_gridHost(layout));
    await tester.pump();
    layout.setSideBarPosition(SideBarPosition.right);
    await tester.pump();

    final secondary = tester.getRect(
      find.byKey(const ValueKey('probe-secondarySidebar')),
    );
    final editor = tester.getRect(find.byKey(const ValueKey('probe-editor')));
    final sidebar = tester.getRect(find.byKey(const ValueKey('probe-sidebar')));
    final activity =
        tester.getRect(find.byKey(const ValueKey('probe-activity')));
    expect(secondary.right, lessThanOrEqualTo(editor.left));
    expect(editor.right, lessThanOrEqualTo(sidebar.left));
    expect(sidebar.right, lessThanOrEqualTo(activity.left));
    expect(activity.right, closeTo(1280, 1));
    layout.dispose();
  });
}
