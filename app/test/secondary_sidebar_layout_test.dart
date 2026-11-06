import 'dart:io';

import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/activity_bar_position.dart';
import 'package:alula_app/workbench/layout_controller.dart';
import 'package:alula_app/workbench/layout_grid.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/secondary_sidebar_empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  test('default secondary sidebar is hidden and remembers its width', () {
    final layout = WorkbenchLayout();
    final secondary = layout.leafOf('secondarySidebar')!;
    expect(secondary.collapsed, isTrue);
    expect(secondary.lastWeight, closeTo(0.26, 1e-9));
    expect(secondary.minExtent, 170);
    expect(layout.isCollapsed('sidebar'), isFalse);
    layout.dispose();
  });

  testWidgets('empty state is visible and announces that no views are assigned',
      (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final layout = WorkbenchLayout();
    await tester.pumpWidget(_gridHost(layout));
    expect(layout.toggleRegion('secondarySidebar'), isFalse);
    await tester.pump();

    expect(find.text('次侧栏'), findsOneWidget);
    expect(find.text('此侧栏暂时没有视图'), findsOneWidget);
    expect(
      find.bySemanticsLabel(SecondarySidebarEmptyState.semanticsLabel),
      findsOneWidget,
    );
    layout.dispose();
    semantics.dispose();
  });

  testWidgets('collapsed default keeps the current sidebar/editor geometry',
      (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final layout = WorkbenchLayout();
    await tester.pumpWidget(_gridHost(layout));
    await tester.pump();

    expect(find.byKey(const ValueKey('probe-secondarySidebar')), findsNothing);
    expect(tester.getSize(find.byKey(const ValueKey('probe-sidebar'))).width,
        closeTo(748 * 0.24, 1.5));
    expect(tester.getSize(find.byKey(const ValueKey('probe-editor'))).width,
        closeTo(748 * 0.76, 1.5));
    layout.dispose();
  });

  testWidgets('visible secondary side bar is placed to the right of editor',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final layout = WorkbenchLayout();
    await tester.pumpWidget(_gridHost(layout));
    expect(layout.toggleRegion('secondarySidebar'), isFalse);
    await tester.pump();

    final editorRect = tester.getRect(
      find.byKey(const ValueKey('probe-editor')),
    );
    final secondaryRect = tester.getRect(
      find.byKey(const ValueKey('probe-secondarySidebar')),
    );
    expect(secondaryRect.left, greaterThanOrEqualTo(editorRect.right));
    expect(secondaryRect.width, greaterThanOrEqualTo(170));
    await tester.drag(
      find.byKey(const ValueKey('wb-div-editor-secondarySidebar')),
      const Offset(40, 0),
    );
    await tester.pump();
    expect(
      tester
          .getSize(find.byKey(const ValueKey('probe-secondarySidebar')))
          .width,
      closeTo(secondaryRect.width - 40, 2),
      reason: 'the secondary side bar can be resized independently',
    );
    expect(layout.toggleRegion('secondarySidebar'), isTrue);
    await tester.pump();
    expect(find.byKey(const ValueKey('probe-secondarySidebar')), findsNothing);
    layout.dispose();
  });

  test('legacy store migration preserves regions, views, and layout metadata',
      () async {
    final temp = await Directory.systemTemp.createTemp('alula_secondary_side');
    addTearDown(() => temp.delete(recursive: true));
    final store = LayoutStore(path: '${temp.path}/layout.json');

    final oldLayout = WorkbenchLayout(root: defaultLayout());
    oldLayout.setActivityBarLocation(ActivityBarLocation.top);
    oldLayout.splitRegion('editor', 'editor-2', Axis.horizontal);
    oldLayout.root.activityBarPinned = const ['search'];
    oldLayout.setRegionCollapsed('panel', false);
    expect(oldLayout.root.removeLeaf('secondarySidebar'), isTrue);
    store.save(oldLayout.root);
    oldLayout.dispose();

    final restored = store.tryLoad()!;
    final secondary = restored.leafOf('secondarySidebar')!;
    expect(secondary.collapsed, isTrue);
    expect(secondary.lastWeight, closeTo(0.26, 1e-9));
    expect(restored.leafOf('activity')!.fixedExtent, 44);
    expect(restored.activityBarLocation, ActivityBarLocation.top);
    expect(restored.activityBarPinned, ['search']);
    expect(restored.leafOf('editor-2'), isNotNull);
    expect(restored.leafOf('panel')!.collapsed, isFalse);
    final row = restored.parentSplitOf('secondarySidebar')!.children;
    final secondaryIndex = row.indexWhere(
      (node) => node is WbLeaf && node.region == 'secondarySidebar',
    );
    final editorIndex = row.indexWhere(
      (node) => node.leaves.any(
        (leaf) => leaf.region == 'editor-2',
      ),
    );
    expect(secondaryIndex, editorIndex + 1);
  });

  test('visibility and resized width persist through layout JSON', () async {
    final temp = await Directory.systemTemp.createTemp('alula_secondary_save');
    addTearDown(() => temp.delete(recursive: true));
    final store = LayoutStore(path: '${temp.path}/layout.json');

    final layout = WorkbenchLayout();
    expect(layout.setRegionCollapsed('secondarySidebar', false), isFalse);
    layout.leafOf('secondarySidebar')!.weight = 0.33;
    store.save(layout.root);
    layout.dispose();

    final visible = store.tryLoad()!;
    expect(visible.leafOf('secondarySidebar')!.collapsed, isFalse);
    expect(visible.leafOf('secondarySidebar')!.weight, closeTo(0.33, 1e-9));

    final restoredLayout = WorkbenchLayout(root: visible);
    expect(
      restoredLayout.setRegionCollapsed('secondarySidebar', true),
      isTrue,
    );
    store.save(restoredLayout.root);
    restoredLayout.dispose();

    final hidden = store.tryLoad()!;
    expect(hidden.leafOf('secondarySidebar')!.collapsed, isTrue);
    expect(hidden.leafOf('secondarySidebar')!.lastWeight, closeTo(0.33, 1e-9));
    final finalLayout = WorkbenchLayout(root: hidden);
    expect(
      finalLayout.setRegionCollapsed('secondarySidebar', false),
      isFalse,
    );
    expect(finalLayout.leafOf('secondarySidebar')!.weight, closeTo(0.33, 1e-9));
    finalLayout.dispose();
  });

  test('default and macOS keybindings match the pinned toggle action', () {
    final windows = KeybindingSet.load(platform: TargetPlatform.windows);
    final linux = KeybindingSet.load(platform: TargetPlatform.linux);
    final mac = KeybindingSet.load(platform: TargetPlatform.macOS);
    expect(
      windows.commandForChord(parseChord('ctrl+alt+b')!),
      'workbench.action.toggleAuxiliaryBar',
    );
    expect(
      linux.commandForChord(parseChord('ctrl+alt+b')!),
      'workbench.action.toggleAuxiliaryBar',
    );
    expect(
      mac.commandForChord(parseChord('cmd+alt+b')!),
      'workbench.action.toggleAuxiliaryBar',
    );
  });
}
