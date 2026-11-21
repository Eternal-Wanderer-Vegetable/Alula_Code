import 'dart:io';

import 'dart:ui' show Tristate;
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/activity_bar.dart';
import 'package:alula_app/workbench/activity_bar_order.dart';
import 'package:alula_app/workbench/activity_bar_position.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_controller.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/secondary_sidebar_layout.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/sidebar_view_locations.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late LayoutStore layoutStore;
  late SessionStore sessionStore;
  late KeybindingsStore keybindingsStore;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('alula_activity_bar_order');
    final root = temp.path.replaceAll(r'\', '/');
    layoutStore = LayoutStore(path: '$root/layout.json');
    sessionStore = SessionStore(path: '$root/session.json');
    keybindingsStore = KeybindingsStore(path: '$root/keybindings.json');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  testWidgets('P05.14 reorders, persists, remounts and survives layout modes',
      (tester) async {
    Future<void> mountApp() async {
      await tester.pumpWidget(AlulaApp(
        layoutStore: layoutStore,
        sessionStore: sessionStore,
        keybindingsStore: keybindingsStore,
      ));
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> saveAndExpectOrder(List<String> expected) async {
      await tester.pump(const Duration(milliseconds: 600));
      expect(layoutStore.tryLoad()!.activityBarOrder, expected);
    }

    Future<void> selectPosition(String label) async {
      await tester.tap(find.text('查看(V)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('外观(A)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('活动栏位置(A)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    Future<void> selectCompactSize() async {
      final activity = find.byKey(const ValueKey('wb-region-activity'));
      await tester.tapAt(
        tester.getCenter(activity),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activity Bar Size'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('activity-bar-size-compact')));
      await tester.pumpAndSettle();
    }

    final semantics = tester.ensureSemantics();
    await mountApp();
    await tester.tap(_activityBarView('搜索'));
    await tester.pump();

    // Move Search before Explorer by dropping on the first half of the target.
    var source = tester.getRect(_activityBarView('搜索'));
    var target = tester.getRect(_activityBarView('资源管理器'));
    await tester.dragFrom(
      source.center,
      Offset(target.center.dx - source.center.dx,
          target.top + 4 - source.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    var expected = ['search', 'explorer', 'outline', 'git'];
    expect(
        tester.widget<ActivityBar>(find.byType(ActivityBar)).order, expected);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('搜索'))
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
      reason: 'the active view remains selected by ID after reorder',
    );
    await saveAndExpectOrder(expected);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await mountApp();
    expect(
        tester.widget<ActivityBar>(find.byType(ActivityBar)).order, expected);

    // Horizontal Top reordering uses left/right drop halves.
    await selectPosition('顶部(T)');
    source = tester.getRect(_activityBarView('源代码管理'));
    target = tester.getRect(_activityBarView('搜索'));
    await tester.dragFrom(
      source.center,
      Offset(target.left + 4 - source.center.dx,
          target.center.dy - source.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expected = ['git', 'search', 'explorer', 'outline'];
    expect(
        tester.widget<ActivityBar>(find.byType(ActivityBar)).order, expected);
    await saveAndExpectOrder(expected);

    await selectPosition('底部(B)');
    await saveAndExpectOrder(expected);
    await selectPosition('隐藏(H)');
    await saveAndExpectOrder(expected);
    await selectPosition('侧边(D)');
    await selectCompactSize();
    await saveAndExpectOrder(expected);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await mountApp();
    final restored = tester.widget<ActivityBar>(find.byType(ActivityBar));
    expect(restored.order, expected);
    expect(restored.size, ActivityBarSize.compact);
    semantics.dispose();
  });

  for (final (position, placement, expected) in [
    (
      ActivityBarLocation.side,
      'before',
      ['explorer', 'git', 'search', 'outline']
    ),
    (
      ActivityBarLocation.side,
      'after',
      ['git', 'explorer', 'search', 'outline']
    ),
    (
      ActivityBarLocation.side,
      'tail',
      ['git', 'search', 'outline', 'explorer']
    ),
    (
      ActivityBarLocation.top,
      'after',
      ['git', 'explorer', 'search', 'outline']
    ),
  ]) {
    testWidgets(
        'secondary group inserts $placement on the $position Activity Bar',
        (tester) async {
      tester.view.physicalSize = const Size(1480, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final layout = WorkbenchLayout();
      layout.moveSidebarView('explorer', secondarySidebarViewLocation);
      layout.moveSidebarView('search', secondarySidebarViewLocation,
          sidebarPlacement: (container: 'explorer', before: true));
      layout.setActivityBarLocation(position);
      layout.setActivityBarOrder(
        placement == 'tail'
            ? ['explorer', 'git', 'search', 'outline']
            : ['git', 'search', 'outline', 'explorer'],
      );
      layout.showRegion(secondarySidebarRegion);
      final placements = Map.of(layout.root.sidebarViewPlacements);
      layoutStore.save(layout.root);
      layout.dispose();

      await tester.pumpWidget(AlulaApp(
        layoutStore: layoutStore,
        sessionStore: sessionStore,
        keybindingsStore: keybindingsStore,
      ));
      await tester.pumpAndSettle();
      final entry =
          find.byKey(const ValueKey('secondary-sidebar-entry-explorer'));
      final search = find.byKey(const ValueKey('search-input'));
      const query = 'retained at the new activity position 😀';
      await tester.enterText(search, query);

      final source = tester.getCenter(entry);
      final git = tester.getRect(_activityBarView('源代码管理'));
      final bar = tester.getRect(find.byType(ActivityBar));
      final destination = switch ((position, placement)) {
        (_, 'tail') => bar.center,
        (ActivityBarLocation.top, _) => Offset(git.right - 4, git.center.dy),
        (_, 'before') => Offset(git.center.dx, git.top + 4),
        _ => Offset(git.center.dx, git.bottom - 4),
      };
      final drag =
          await tester.startGesture(source, kind: PointerDeviceKind.mouse);
      await drag.moveBy(const Offset(-20, 0));
      await drag.moveTo(destination);
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();

      expect(entry, findsNothing);
      expect(
          tester.widget<ActivityBar>(find.byType(ActivityBar)).order, expected);
      expect(tester.widget<TextField>(search).controller!.text, query);
      final visible = expected.where((view) => view != 'search').toList();
      final actual = [
        for (final id in visible)
          tester.getCenter(
              find.byKey(ValueKey('activity-bar-item-menu-anchor-$id'))),
      ];
      final offsets = actual
          .map((point) =>
              position == ActivityBarLocation.top ? point.dx : point.dy)
          .toList();
      expect(offsets, orderedEquals([...offsets]..sort()));
      await tester.pump(const Duration(milliseconds: 700));
      final saved = layoutStore.tryLoad()!;
      expect(saved.activityBarOrder, expected);
      expect(saved.sidebarViewPlacements, placements);
      expect(saved.primarySidebarView, 'explorer');
      expect(
          saved.sidebarViewLocations?['explorer'], primarySidebarViewLocation);
      expect(saved.sidebarViewLocations?['search'], primarySidebarViewLocation);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}

Finder _activityBarView(String label) => find
    .descendant(
      of: find.byType(ActivityBar),
      matching: find.byTooltip(label),
    )
    .first;
