import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/activity_bar_order.dart';
import 'package:alula_app/workbench/activity_bar_pins.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_controller.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/panel_position.dart';
import 'package:alula_app/workbench/secondary_sidebar_layout.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/sidebar_view_locations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late LayoutStore layoutStore;
  late SessionStore sessionStore;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('alula_sidebar_view_move');
    final root = temp.path.replaceAll(r'\', '/');
    layoutStore = LayoutStore(path: '$root/layout.json');
    sessionStore = SessionStore(path: '$root/session.json');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  testWidgets(
      'move and focused-view commands route built-ins and persist both sides',
      (tester) async {
    Future<void> mountApp() async {
      await tester.pumpWidget(AlulaApp(
        layoutStore: layoutStore,
        sessionStore: sessionStore,
      ));
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<Finder> openCommand(String query, String commandKey) async {
      await tester.tap(find.byKey(const ValueKey('command-center-control')));
      await tester.pumpAndSettle();
      final input = find.descendant(
        of: find.byKey(const ValueKey('quick-input')),
        matching: find.byType(TextField),
      );
      await tester.enterText(input, query);
      await tester.pumpAndSettle();
      final command = find.byKey(ValueKey(commandKey));
      expect(command, findsOneWidget);
      await tester.tap(command);
      await tester.pumpAndSettle();
      return find.descendant(
        of: find.byKey(const ValueKey('quick-input')),
        matching: find.byType(TextField),
      );
    }

    Future<void> moveView(String view, String destination) async {
      await openCommand('移动视图', 'qi-查看: 移动视图…');
      await tester.tap(find.byKey(ValueKey('qi-$view')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('qi-$destination')));
      await tester.pumpAndSettle();
    }

    await mountApp();
    final primary = find.byKey(const ValueKey('wb-region-sidebar'));
    final secondary = find.byKey(const ValueKey('wb-region-secondarySidebar'));
    Finder secondaryExplorer(Finder region) => find.descendant(
          of: find.descendant(
            of: region,
            matching: find.byKey(const ValueKey('builtin-view-focus-explorer')),
          ),
          matching: find.text('资源管理器'),
        );

    expect(secondary, findsNothing);

    final viewInput = await openCommand('移动视图', 'qi-查看: 移动视图…');
    await tester.enterText(viewInput, '资源管理器');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(secondary, findsOneWidget);
    expect(
      secondaryExplorer(secondary),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: primary,
        matching: find.byKey(const ValueKey('search-input')),
      ),
      findsOneWidget,
      reason: 'the source side selects a remaining view without losing it',
    );
    await tester.pump(const Duration(milliseconds: 600));
    final beforeCancel = layoutStore.tryLoad()!.toJson();

    final cancelInput = await openCommand('移动视图', 'qi-查看: 移动视图…');
    await tester.tap(find.byKey(const ValueKey('qi-搜索')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    expect(layoutStore.tryLoad()!.toJson(), beforeCancel,
        reason: 'canceling the destination picker does not change the layout');
    expect(cancelInput, findsNothing);
    expect(
      secondaryExplorer(secondary),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('secondary-sidebar-entry-explorer')),
    );
    await tester.pumpAndSettle();
    await openCommand('移动聚焦的视图', 'qi-查看: 移动聚焦的视图…');
    await tester.tap(find.byKey(const ValueKey('qi-主侧栏')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: primary, matching: find.text('资源管理器')),
      findsOneWidget,
      reason: 'moveFocusedView acts on the selected secondary entry',
    );

    await moveView('资源管理器', '次侧栏');
    await tester.pump(const Duration(milliseconds: 600));
    final saved = layoutStore.tryLoad()!;
    expect(
        saved.sidebarViewLocations!['explorer'], secondarySidebarViewLocation);
    expect(saved.primarySidebarView, 'search');
    expect(saved.secondarySidebarView, 'explorer');

    await moveView('资源管理器', '次侧栏');
    await tester.pump(const Duration(milliseconds: 600));
    expect(layoutStore.tryLoad()!.toJson(), saved.toJson(),
        reason:
            'choosing the current side does not change assignments or selection');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await mountApp();
    final restoredPrimary = find.byKey(const ValueKey('wb-region-sidebar'));
    final restoredSecondary =
        find.byKey(const ValueKey('wb-region-secondarySidebar'));
    expect(
      find.descendant(
        of: restoredPrimary,
        matching: find.byKey(const ValueKey('search-input')),
      ),
      findsOneWidget,
    );
    expect(
      secondaryExplorer(restoredSecondary),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'moved built-in views have independent panel tabs, preserve input, '
    'and restore their layout',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 980);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final bindings = File('${temp.path}/keybindings.json')
        ..writeAsStringSync(
          '[{"key":"f8","command":"workbench.action.moveFocusedView"}]',
        );

      Future<void> mountApp() async {
        await tester.pumpWidget(AlulaApp(
          layoutStore: layoutStore,
          sessionStore: sessionStore,
          keybindingsStore: KeybindingsStore(path: bindings.path),
        ));
        await tester.pumpAndSettle();
      }

      Future<void> run(String label) async {
        await tester.tap(find.byKey(const ValueKey('command-center-control')));
        await tester.pumpAndSettle();
        final input = find.descendant(
          of: find.byKey(const ValueKey('quick-input')),
          matching: find.byType(TextField),
        );
        await tester.enterText(input, label);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('qi-查看: $label')));
        await tester.pumpAndSettle();
      }

      Future<void> choose(String label) async {
        await tester.tap(find.byKey(ValueKey('qi-$label')));
        await tester.pumpAndSettle();
      }

      Future<void> moveToPanel(String label) async {
        await run('移动视图…');
        await choose(label);
        await choose('新建面板入口');
      }

      final panel = find.byKey(const ValueKey('wb-region-panel'));
      final primary = find.byKey(const ValueKey('wb-region-sidebar'));
      final secondary =
          find.byKey(const ValueKey('wb-region-secondarySidebar'));
      final search = find.byKey(const ValueKey('search-input'));
      final searchPanelTab =
          find.byKey(const ValueKey('panel-builtin-view-search'));
      final outlinePanelTab =
          find.byKey(const ValueKey('panel-builtin-view-outline'));
      Finder owner(Finder region) =>
          find.descendant(of: region, matching: search);

      await mountApp();
      await tester.tap(find.byTooltip('搜索'));
      await tester.pumpAndSettle();
      expect(owner(primary), findsOneWidget);
      await tester.enterText(search, 'survives the move 😀');
      await moveToPanel('搜索');
      expect(owner(panel), findsOneWidget);
      expect(owner(primary), findsNothing);
      expect(tester.widget<TextField>(search).controller!.text,
          'survives the move 😀');
      expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
      expect(searchPanelTab, findsOneWidget);
      expect(find.descendant(of: panel, matching: find.text('Git Diff')),
          findsOneWidget);

      await moveToPanel('大纲');
      expect(searchPanelTab, findsOneWidget);
      expect(outlinePanelTab, findsOneWidget);
      await tester.tap(searchPanelTab);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).controller!.text,
          'survives the move 😀');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      final saved = layoutStore.tryLoad()!;
      expect(saved.sidebarViewLocations?['search'], panelSidebarViewLocation);
      expect(saved.sidebarViewLocations?['outline'], panelSidebarViewLocation);
      expect(sessionStore.tryLoad()?['activePanelHostedView'], 'search');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mountApp();
      expect(owner(panel), findsOneWidget);
      expect(searchPanelTab, findsOneWidget);
      expect(outlinePanelTab, findsOneWidget);
      await tester.enterText(search, 'moving back');
      await tester.sendKeyEvent(LogicalKeyboardKey.f8);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('qi-新建面板入口')), findsNothing);
      await choose('次侧栏');
      expect(owner(panel), findsNothing);
      expect(owner(secondary), findsOneWidget);
      expect(tester.widget<TextField>(search).controller!.text, 'moving back');
      expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
      expect(searchPanelTab, findsNothing);
      expect(outlinePanelTab, findsOneWidget);

      await run('重置视图位置');
      expect(outlinePanelTab, findsNothing);
      expect(owner(secondary), findsNothing);
      expect(find.descendant(of: panel, matching: find.text('Git Diff')),
          findsOneWidget);
      await tester.tap(find.byTooltip('搜索'));
      await tester.pumpAndSettle();
      expect(owner(primary), findsOneWidget);
      expect(tester.widget<TextField>(search).controller!.text, 'moving back');
      await tester.pump(const Duration(milliseconds: 700));
      expect(layoutStore.tryLoad()!.sidebarViewLocations?['search'],
          primarySidebarViewLocation);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  for (final (location, region) in [
    (primarySidebarViewLocation, 'sidebar'),
    (secondarySidebarViewLocation, secondarySidebarRegion),
  ]) {
    testWidgets('panel views drag to the $location side bar and support cancel',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 980);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final layout = WorkbenchLayout();
      expect(
          layout.moveSidebarView('search', panelSidebarViewLocation), isTrue);
      layout.showRegion('panel');
      layout.showRegion(secondarySidebarRegion);
      layoutStore.save(layout.root);
      layout.dispose();
      sessionStore.save({
        'v': 1,
        'activePanelHostedView': 'search',
        'groups': [
          {'region': 'editor', 'docs': []},
        ],
      });
      await tester.pumpWidget(AlulaApp(
        layoutStore: layoutStore,
        sessionStore: sessionStore,
      ));
      await tester.pumpAndSettle();
      final panelTab = find.byKey(const ValueKey('panel-builtin-view-search'));
      final target = find.byKey(ValueKey('sidebar-panel-view-drop-$location'));
      final highlight =
          find.byKey(ValueKey('sidebar-panel-view-drop-highlight-$location'));
      final search = find.byKey(const ValueKey('search-input'));
      final editor = find.byKey(const ValueKey('wb-region-editor'));
      final panel = find.byKey(const ValueKey('wb-region-panel'));
      final side = find.byKey(ValueKey('wb-region-$region'));
      await tester.enterText(search, 'persistent query 😀');

      Future<TestGesture> startDrag(Finder destination) async {
        final gesture = await tester.startGesture(
          tester.getCenter(panelTab),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await gesture.moveBy(const Offset(0, -18));
        await tester.pump();
        await gesture.moveTo(tester.getCenter(destination));
        await tester.pump();
        return gesture;
      }

      final rejected = await startDrag(editor);
      expect(highlight, findsNothing);
      await rejected.up();
      await tester.pumpAndSettle();
      expect(panelTab, findsOneWidget);

      final cancel = await startDrag(target);
      expect(highlight, findsOneWidget);
      await cancel.cancel();
      await tester.pumpAndSettle();
      expect(highlight, findsNothing);
      expect(panelTab, findsOneWidget);
      expect(tester.widget<TextField>(search).controller!.text,
          'persistent query 😀');

      final accepted = await startDrag(target);
      expect(highlight, findsOneWidget);
      await accepted.up();
      await tester.pumpAndSettle();
      expect(highlight, findsNothing);
      expect(panelTab, findsNothing);
      expect(find.descendant(of: side, matching: search), findsOneWidget);
      expect(find.descendant(of: panel, matching: find.text('Git Diff')),
          findsOneWidget);
      final field = tester.widget<TextField>(search);
      expect(field.controller!.text, 'persistent query 😀');
      expect(field.focusNode!.hasFocus, isFalse);
      await tester.pump(const Duration(milliseconds: 700));
      expect(layoutStore.tryLoad()!.sidebarViewLocations?['search'], location);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('an Activity Bar view moves to an independent panel title entry',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const order = ['git', 'explorer', 'search', 'outline'];
    const pinned = ['git', 'explorer', 'search'];
    final layout = WorkbenchLayout();
    layout.setActivityBarOrder(order);
    layout.setActivityBarPinnedViews(pinned);
    layout.showRegion('panel');
    layoutStore.save(layout.root);
    layout.dispose();
    await tester.pumpWidget(AlulaApp(
      layoutStore: layoutStore,
      sessionStore: sessionStore,
    ));
    await tester.pumpAndSettle();

    final item =
        find.byKey(const ValueKey('activity-bar-item-menu-anchor-search'));
    final title = find.byKey(const ValueKey('panel-view-title-drop'));
    final highlight =
        find.byKey(const ValueKey('panel-view-title-drop-highlight'));
    final panelTab = find.byKey(const ValueKey('panel-builtin-view-search'));
    final search = find.byKey(const ValueKey('search-input'));
    final editor = find.byKey(const ValueKey('wb-region-editor'));
    final panel = find.byKey(const ValueKey('wb-region-panel'));
    final side = find.byKey(const ValueKey('wb-region-sidebar'));

    Future<TestGesture> startDrag(Finder source, Offset target) async {
      final gesture = await tester.startGesture(
        tester.getCenter(source),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveBy(const Offset(18, 0));
      await tester.pump();
      await gesture.moveTo(target);
      await tester.pump();
      return gesture;
    }

    await tester.tap(item);
    await tester.pumpAndSettle();
    await tester.enterText(search, 'persistent query 😀');
    final rejected = await startDrag(item, tester.getCenter(editor));
    expect(highlight, findsNothing);
    await rejected.up();
    await tester.pumpAndSettle();
    expect(item, findsOneWidget);
    expect(panelTab, findsNothing);

    final titleDrop = tester.getTopRight(title) + const Offset(-45, 24);
    final cancelled = await startDrag(item, titleDrop);
    expect(highlight, findsOneWidget);
    await cancelled.cancel();
    await tester.pumpAndSettle();
    expect(highlight, findsNothing);
    expect(item, findsOneWidget);
    expect(panelTab, findsNothing);

    final accepted = await startDrag(item, titleDrop);
    expect(highlight, findsOneWidget);
    await accepted.up();
    await tester.pumpAndSettle();
    expect(highlight, findsNothing);
    expect(item, findsNothing);
    expect(panelTab, findsOneWidget);
    expect(find.descendant(of: panel, matching: find.text('Git Diff')),
        findsOneWidget);
    final movedSearch = find.descendant(of: panel, matching: search);
    final field = tester.widget<TextField>(movedSearch);
    expect(field.controller!.text, 'persistent query 😀');
    expect(field.focusNode!.hasFocus, isTrue);
    await tester.pump(const Duration(milliseconds: 700));
    final saved = layoutStore.tryLoad()!;
    expect(saved.sidebarViewLocations?['search'], panelSidebarViewLocation);
    expect(saved.activityBarOrder, order);
    final restored = WorkbenchLayout(root: saved);
    expect(restored.activityBarPinnedViews, pinned);
    restored.dispose();

    final returned = await startDrag(panelTab, tester.getCenter(side));
    await returned.up();
    await tester.pumpAndSettle();
    expect(panelTab, findsNothing);
    expect(item, findsOneWidget);
    final returnedSearch = find.descendant(of: side, matching: search);
    expect(tester.widget<TextField>(returnedSearch).controller!.text,
        'persistent query 😀');
    expect(
        tester.widget<TextField>(returnedSearch).focusNode!.hasFocus, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  for (final (position, before) in [
    (PanelPosition.bottom, true),
    (PanelPosition.bottom, false),
    (PanelPosition.right, true),
    (PanelPosition.right, false),
  ]) {
    testWidgets(
        'Activity Bar body drop groups the view at $position, before=$before',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 980);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final layout = WorkbenchLayout();
      layout.setPanelPosition(position);
      layout.showRegion('panel');
      layoutStore.save(layout.root);
      layout.dispose();

      final keybindingsPath = '${temp.path}/group-keybindings.json';
      File(keybindingsPath).writeAsStringSync(
        '[{"key":"f6","command":"view.search"},'
        '{"key":"f9","command":"workbench.action.resetViewLocations"}]',
      );

      Future<void> mount() async {
        await tester.pumpWidget(AlulaApp(
          layoutStore: layoutStore,
          sessionStore: sessionStore,
          keybindingsStore: KeybindingsStore(path: keybindingsPath),
        ));
        await tester.pumpAndSettle();
      }

      await mount();
      final item =
          find.byKey(const ValueKey('activity-bar-item-menu-anchor-search'));
      final side = before ? 'before' : 'after';
      final drop =
          find.byKey(ValueKey('panel-view-body-drop-diagnostics-$side'));
      final highlight =
          find.byKey(ValueKey('panel-view-body-highlight-diagnostics-$side'));
      final search = find.byKey(const ValueKey('search-input'));
      final orig =
          find.byKey(const ValueKey('panel-view-group-diagnostics-original'));
      final group =
          find.byKey(const ValueKey('panel-view-group-diagnostics-search'));
      final panelTab = find.byKey(const ValueKey('panel-builtin-view-search'));

      Future<TestGesture> dragToBody() async {
        final gesture = await tester.startGesture(
          tester.getCenter(item),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await gesture.moveBy(const Offset(16, 0));
        await gesture.moveTo(tester.getCenter(drop));
        await tester.pump();
        return gesture;
      }

      await tester.tap(item);
      await tester.pumpAndSettle();
      await tester.enterText(search, 'grouped query 😀');

      final cancelled = await dragToBody();
      expect(highlight, findsOneWidget);
      await cancelled.cancel();
      await tester.pumpAndSettle();
      expect(highlight, findsNothing);
      expect(item, findsOneWidget);
      expect(group, findsNothing);

      final accepted = await dragToBody();
      expect(highlight, findsOneWidget);
      await accepted.up();
      await tester.pumpAndSettle();
      expect(item, findsNothing);
      expect(group, findsOneWidget);
      expect(highlight, findsNothing);
      expect(panelTab, findsNothing);
      expect(
          find.descendant(of: orig, matching: find.textContaining('LSP 未启动')),
          findsOneWidget);
      final field = tester
          .widget<TextField>(find.descendant(of: group, matching: search));
      expect(field.controller!.text, 'grouped query 😀');
      expect(field.focusNode!.hasFocus, isFalse);
      final searchRect = tester.getRect(group);
      final origRect = tester.getRect(orig);
      if (position == PanelPosition.bottom) {
        expect(searchRect.top, origRect.top);
        expect(searchRect.left < origRect.left, before);
      } else {
        expect(searchRect.left, origRect.left);
        expect(searchRect.top < origRect.top, before);
      }
      // Reset stays reachable immediately after releasing the drag.
      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      await tester.pumpAndSettle();
      expect(group, findsNothing);
      expect(item, findsOneWidget);
      await tester.tap(item);
      await tester.pumpAndSettle();
      final regrouped = await dragToBody();
      await regrouped.up();
      await tester.pumpAndSettle();
      expect(group, findsOneWidget);
      expect(tester.widget<TextField>(search).controller!.text,
          'grouped query 😀');

      // The drop overlay leaves pointer access to the hosted view intact.
      await tester.tap(search);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
      await tester.pump(const Duration(milliseconds: 700));
      expect(layoutStore.tryLoad()!.panelViewPlacements['search'],
          (tab: PanelViewTab.diagnostics, before: before));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mount();
      expect(orig, findsOneWidget);
      expect(group, findsOneWidget);
      expect(item, findsNothing);
      expect(panelTab, findsNothing);
      final restored = tester
          .widget<TextField>(find.descendant(of: group, matching: search));
      expect(restored.focusNode!.hasFocus, isFalse);
      await tester.tap(find.widgetWithText(Tab, '补全'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.pumpAndSettle();
      expect(find.descendant(of: group, matching: search), findsOneWidget);
      expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  for (final (location, region) in [
    (primarySidebarViewLocation, 'sidebar'),
    (secondarySidebarViewLocation, secondarySidebarRegion),
  ]) {
    testWidgets('Grouped panel titles return to a $location entry surface',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 980);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final layout = WorkbenchLayout();
      layout.moveSidebarView('git', secondarySidebarViewLocation);
      layout.moveSidebarView('search', panelSidebarViewLocation,
          panelPlacement: (tab: PanelViewTab.diagnostics, before: false));
      layout.moveSidebarView('outline', panelSidebarViewLocation,
          panelPlacement: (tab: PanelViewTab.diagnostics, before: true));
      layout.showRegion('panel');
      layout.showRegion(secondarySidebarRegion);
      layoutStore.save(layout.root);
      layout.dispose();

      Future<void> mount() async {
        await tester.pumpWidget(AlulaApp(
          layoutStore: layoutStore,
          sessionStore: sessionStore,
        ));
        await tester.pumpAndSettle();
      }

      await mount();
      final source =
          find.byKey(const ValueKey('panel-view-group-title-search'));
      final outline =
          find.byKey(const ValueKey('panel-view-group-title-outline'));
      final editor = find.byKey(const ValueKey('wb-region-editor'));
      final search = find.byKey(const ValueKey('search-input'));
      final owner = find.byKey(ValueKey('wb-region-$region'));
      final panel = find.byKey(const ValueKey('wb-region-panel'));
      final target =
          find.byKey(ValueKey('grouped-panel-view-entry-drop-$location'));
      final highlight =
          find.byKey(ValueKey('grouped-panel-view-entry-highlight-$location'));
      final activitySearch =
          find.byKey(const ValueKey('activity-bar-item-menu-anchor-search'));
      final secondarySearch =
          find.byKey(const ValueKey('secondary-sidebar-entry-search'));

      Future<TestGesture> dragTo(Finder destination) async {
        final gesture = await tester.startGesture(
          tester.getTopLeft(source) + const Offset(24, 12),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await gesture.moveBy(const Offset(0, -18));
        await gesture.moveTo(tester.getCenter(destination));
        await tester.pump();
        return gesture;
      }

      await tester.enterText(search, 'query remains 😀');
      final rejected = await dragTo(editor);
      expect(highlight, findsNothing);
      await rejected.up();
      await tester.pumpAndSettle();
      expect(source, findsOneWidget);
      expect(outline, findsOneWidget);

      final cancelled = await dragTo(target);
      expect(highlight, findsOneWidget);
      await cancelled.cancel();
      await tester.pumpAndSettle();
      expect(highlight, findsNothing);
      expect(source, findsOneWidget);

      final accepted = await dragTo(target);
      expect(highlight, findsOneWidget);
      await accepted.up();
      await tester.pumpAndSettle();
      expect(source, findsNothing);
      expect(highlight, findsNothing);
      expect(outline, findsOneWidget);
      expect(
          find.descendant(of: panel, matching: find.textContaining('LSP 未启动')),
          findsOneWidget);
      expect(find.descendant(of: owner, matching: search), findsOneWidget);
      final field = tester.widget<TextField>(search);
      expect(field.controller!.text, 'query remains 😀');
      expect(field.focusNode!.hasFocus, isTrue);

      if (location == secondarySidebarViewLocation) {
        expect(activitySearch, findsNothing);
        expect(secondarySearch, findsOneWidget);
        await tester
            .tap(find.byKey(const ValueKey('secondary-sidebar-entry-git')));
        await tester.pumpAndSettle();
        expect(search, findsNothing);
        await tester.tap(secondarySearch);
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(search).controller!.text,
            'query remains 😀');
        expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
      } else {
        expect(activitySearch, findsOneWidget);
        expect(secondarySearch, findsNothing);
      }

      await tester.pump(const Duration(milliseconds: 700));
      final saved = layoutStore.tryLoad()!;
      expect(saved.sidebarViewLocations?['search'], location);
      expect(saved.panelViewPlacements.keys, ['outline']);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mount();
      expect(outline, findsOneWidget);
      expect(source, findsNothing);
      expect(find.descendant(of: owner, matching: search), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  for (final (destination, before) in [
    (primarySidebarViewLocation, true),
    (primarySidebarViewLocation, false),
    (secondarySidebarViewLocation, true),
    (secondarySidebarViewLocation, false),
  ]) {
    testWidgets(
        'Grouped panel view moves into the active $destination body, before=$before',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 980);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final layout = WorkbenchLayout();
      final secondary = destination == secondarySidebarViewLocation;
      if (secondary) {
        layout.moveSidebarView('explorer', secondarySidebarViewLocation);
        layout.moveSidebarView('git', secondarySidebarViewLocation);
        layout.selectSidebarView('explorer');
        layout.showRegion(secondarySidebarRegion);
      }
      layout.moveSidebarView('search', panelSidebarViewLocation,
          panelPlacement: (tab: PanelViewTab.diagnostics, before: false));
      layout.moveSidebarView('outline', panelSidebarViewLocation,
          panelPlacement: (tab: PanelViewTab.diagnostics, before: true));
      layout.showRegion('panel');
      layoutStore.save(layout.root);
      layout.dispose();
      final keybindingsPath = '${temp.path}/side-group-keybindings.json';
      File(keybindingsPath).writeAsStringSync(
        '[{"key":"f6","command":"view.search"}]',
      );

      Future<void> mount() async {
        await tester.pumpWidget(AlulaApp(
          layoutStore: layoutStore,
          sessionStore: sessionStore,
          keybindingsStore: KeybindingsStore(path: keybindingsPath),
        ));
        await tester.pumpAndSettle();
      }

      await mount();
      final source =
          find.byKey(const ValueKey('panel-view-group-title-search'));
      final outline =
          find.byKey(const ValueKey('panel-view-group-title-outline'));
      final side = before ? 'before' : 'after';
      final target =
          find.byKey(ValueKey('$destination-sidebar-body-drop-$side'));
      final highlight =
          find.byKey(ValueKey('$destination-sidebar-body-highlight-$side'));
      final original =
          find.byKey(ValueKey('$destination-sidebar-group-original-explorer'));
      final group = find.byKey(ValueKey('$destination-sidebar-group-search'));
      final search = find.byKey(const ValueKey('search-input'));
      final activitySearch =
          find.byKey(const ValueKey('activity-bar-item-menu-anchor-search'));

      Future<TestGesture> dragTo(Finder destination) async {
        final gesture = await tester.startGesture(
          tester.getTopLeft(source) + const Offset(24, 12),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await gesture.moveBy(const Offset(0, -18));
        await gesture.moveTo(tester.getCenter(destination));
        await tester.pump();
        return gesture;
      }

      await tester.enterText(search, 'grouped into Explorer 😀');
      final rejected =
          await dragTo(find.byKey(const ValueKey('wb-region-editor')));
      expect(highlight, findsNothing);
      await rejected.up();
      await tester.pumpAndSettle();
      expect(source, findsOneWidget);
      final cancelled = await dragTo(target);
      expect(highlight, findsOneWidget);
      await cancelled.cancel();
      await tester.pumpAndSettle();
      expect(source, findsOneWidget);
      expect(group, findsNothing);

      final accepted = await dragTo(target);
      expect(highlight, findsOneWidget);
      await accepted.up();
      await tester.pumpAndSettle();
      expect(highlight, findsNothing);
      expect(source, findsNothing);
      expect(outline, findsOneWidget);
      expect(activitySearch, findsNothing);
      final explorerBody = find.descendant(
        of: original,
        matching: find.byKey(const ValueKey('builtin-view-focus-explorer')),
      );
      expect(find.descendant(of: explorerBody, matching: find.text('资源管理器')),
          findsOneWidget);
      final searchOrigin = tester.getTopLeft(group);
      final explorerOrigin = tester.getTopLeft(original);
      expect(searchOrigin.dx, explorerOrigin.dx);
      expect(searchOrigin.dy < explorerOrigin.dy, before);
      final field = tester
          .widget<TextField>(find.descendant(of: group, matching: search));
      expect(field.controller!.text, 'grouped into Explorer 😀');
      expect(field.focusNode!.hasFocus, isFalse);
      await tester.pump(const Duration(milliseconds: 700));
      final saved = layoutStore.tryLoad()!;
      expect(saved.sidebarViewPlacements['search'],
          (container: 'explorer', before: before));
      expect(saved.panelViewPlacements.keys, ['outline']);
      expect(secondary ? saved.secondarySidebarView : saved.primarySidebarView,
          'explorer');
      expect(find.byKey(const ValueKey('secondary-sidebar-entry-search')),
          findsNothing);
      if (secondary) {
        expect(find.byKey(const ValueKey('secondary-sidebar-entry-explorer')),
            findsOneWidget);
      }

      final otherEntry = secondary
          ? 'secondary-sidebar-entry-git'
          : 'activity-bar-item-menu-anchor-git';
      await tester.tap(find.byKey(ValueKey(otherEntry)));
      await tester.pumpAndSettle();
      expect(group, findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.pumpAndSettle();
      expect(group, findsOneWidget);
      expect(tester.widget<TextField>(search).controller!.text,
          'grouped into Explorer 😀');
      expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
      await tester.pump(const Duration(milliseconds: 700));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mount();
      expect(outline, findsOneWidget);
      expect(group, findsOneWidget);
      expect(source, findsNothing);
      expect(activitySearch, findsNothing);
      expect(tester.widget<TextField>(search).focusNode!.hasFocus, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  for (final location in [
    primarySidebarViewLocation,
    secondarySidebarViewLocation,
  ]) {
    testWidgets(
        '$location group sash clamps, cancels, resets and restores its sizes',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 980);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final layout = WorkbenchLayout();
      if (location == secondarySidebarViewLocation) {
        layout.moveSidebarView('explorer', location);
        layout.showRegion(secondarySidebarRegion);
      }
      layout.moveSidebarView('search', panelSidebarViewLocation);
      layout.moveSidebarView('search', location,
          sidebarPlacement: (container: 'explorer', before: true));
      layout.moveSidebarView('git', panelSidebarViewLocation);
      layout.moveSidebarView('git', location,
          sidebarPlacement: (container: 'explorer', before: false));
      layoutStore.save(layout.root);
      layout.dispose();

      Future<void> mount() async {
        await tester.pumpWidget(AlulaApp(
          layoutStore: layoutStore,
          sessionStore: sessionStore,
        ));
        await tester.pumpAndSettle();
      }

      await mount();
      final sash =
          find.byKey(ValueKey('sidebar-group-sash-$location-search-explorer'));
      final search = find.byKey(const ValueKey('search-input'));
      final first = find.byKey(ValueKey('$location-sidebar-group-search'));
      final second =
          find.byKey(ValueKey('$location-sidebar-group-original-explorer'));
      final neighbor = find.byKey(ValueKey('$location-sidebar-group-git'));
      await tester.enterText(search, 'retained through sash drag 😀');
      final initial = tester.getSize(first).height;
      final sameNeighbor = tester.getRect(neighbor);
      final initialSecond = tester.getRect(second);

      void expectNeighborUnchanged() {
        final current = tester.getRect(neighbor);
        expect(
            (current.topLeft - sameNeighbor.topLeft).distance, lessThan(1e-6));
        expect((current.bottomRight - sameNeighbor.bottomRight).distance,
            lessThan(1e-6));
      }

      Future<TestGesture> drag(double dy) async {
        final gesture = await tester.startGesture(
          tester.getCenter(sash),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await gesture.moveBy(Offset(0, dy));
        await tester.pump();
        return gesture;
      }

      final preview = await drag(84);
      expect(tester.getSize(first).height, closeTo(initial + 84, 0.05));
      expectNeighborUnchanged();
      await tester.pump(const Duration(milliseconds: 700));
      expect(layoutStore.tryLoad()!.sidebarGroupPaneWeights, isEmpty);
      await preview.cancel();
      await tester.pumpAndSettle();
      expect(tester.getSize(first).height, closeTo(initial, 0.05));
      expect(tester.getRect(second), initialSecond);
      await tester.pump(const Duration(milliseconds: 700));
      expect(layoutStore.tryLoad()!.sidebarGroupPaneWeights, isEmpty);

      final min = await drag(-1000);
      expect(tester.getSize(first).height, closeTo(148, 0.05));
      await min.up();
      await tester.pumpAndSettle();
      final max = await drag(1000);
      expect(tester.getSize(second).height, closeTo(148, 0.05));
      await max.up();
      await tester.pumpAndSettle();
      expectNeighborUnchanged();
      expect(tester.widget<TextField>(search).controller!.text,
          'retained through sash drag 😀');
      await tester.pump(const Duration(milliseconds: 700));
      final persisted = layoutStore.tryLoad()!.sidebarGroupPaneWeights;
      expect(persisted.keys.toSet(), {'explorer', 'search', 'git'});
      expect(persisted['search'], greaterThan(persisted['explorer']!));
      final dragged = tester.getSize(first).height;
      final midpoint = (dragged + tester.getSize(second).height) / 2;
      await tester.tap(sash, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.getSize(first).height, closeTo(dragged, 0.05));
      expect(layoutStore.tryLoad()!.sidebarGroupPaneWeights, persisted);

      await tester.tap(sash, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 70));
      await tester.tap(sash, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(tester.getSize(first).height, closeTo(midpoint, 0.05));
      expect(tester.getSize(second).height, closeTo(midpoint, 0.05));
      expectNeighborUnchanged();
      expect(tester.widget<TextField>(search).controller!.text,
          'retained through sash drag 😀');
      await tester.pump(const Duration(milliseconds: 700));
      final reset = layoutStore.tryLoad()!.sidebarGroupPaneWeights;
      expect(reset['search'], closeTo(reset['explorer']!, 1e-9));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mount();
      expect(tester.getSize(first).height, closeTo(midpoint, 0.05));
      expect(tester.getSize(second).height, closeTo(midpoint, 0.05));
      expectNeighborUnchanged();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  for (final location in [
    primarySidebarViewLocation,
    secondarySidebarViewLocation,
  ]) {
    testWidgets('$location grouped headers retain state and remembered sizes',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 980);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final layout = WorkbenchLayout();
      if (location == secondarySidebarViewLocation) {
        layout.moveSidebarView('explorer', location);
        layout.showRegion(secondarySidebarRegion);
      }
      for (final view in ['search', 'git']) {
        layout.moveSidebarView(view, panelSidebarViewLocation);
        layout.moveSidebarView(view, location, sidebarPlacement: (
          container: 'explorer',
          before: view == 'search'
        ));
      }
      layout.setSidebarGroupPaneWeights(
        'explorer',
        {'search': 1.16, 'explorer': 0.88, 'git': 0.96},
      );
      layoutStore.save(layout.root);
      layout.dispose();

      final keybindingsPath = '${temp.path}/collapsed-group-keybindings.json';
      File(keybindingsPath).writeAsStringSync(
        '[{"key":"f6","command":"view.search"}]',
      );
      Future<void> mount() async {
        await tester.pumpWidget(AlulaApp(
          layoutStore: layoutStore,
          sessionStore: sessionStore,
          keybindingsStore: KeybindingsStore(path: keybindingsPath),
        ));
        await tester.pumpAndSettle();
      }

      await mount();
      final search = find.byKey(const ValueKey('search-input'));
      final searchHeader =
          find.byKey(ValueKey('sidebar-group-header-$location-search'));
      final explorerHeader =
          find.byKey(ValueKey('sidebar-group-header-$location-explorer'));
      final gitHeader =
          find.byKey(ValueKey('sidebar-group-header-$location-git'));
      final searchPane = find.byKey(ValueKey('$location-sidebar-group-search'));
      final explorerPane =
          find.byKey(ValueKey('$location-sidebar-group-original-explorer'));
      final gitPane = find.byKey(ValueKey('$location-sidebar-group-git'));
      final sash =
          find.byKey(ValueKey('sidebar-group-sash-$location-search-explorer'));
      double height(Finder pane) => tester.getSize(pane).height;
      bool expanded(Finder header) =>
          tester.widget<Semantics>(header).properties.expanded!;
      Future<void> press(Finder header) async {
        await tester.tap(header, kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
      }

      const query = 'preserved when folded 😀';
      await tester.enterText(search, query);
      final searchHeight = height(searchPane);
      final explorerHeight = height(explorerPane);
      final gitHeight = height(gitPane);
      final initialWeights = layoutStore.tryLoad()!.sidebarGroupPaneWeights;

      await press(searchHeader);
      expect(expanded(searchHeader), isFalse);
      expect(height(searchPane), 28);
      expect(height(explorerPane), greaterThan(explorerHeight));
      expect(height(gitPane), greaterThan(gitHeight));
      expect(search, findsNothing);
      expect(sash, findsNothing);
      await tester.pump(const Duration(milliseconds: 700));
      expect(layoutStore.tryLoad()!.sidebarGroupCollapsedPanes, {'search'});
      expect(layoutStore.tryLoad()!.sidebarGroupPaneWeights, initialWeights);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(expanded(searchHeader), isTrue);
      expect(height(searchPane), closeTo(searchHeight, 0.05));
      expect(tester.widget<TextField>(search).controller!.text, query);
      expect(tester.widget<TextField>(search).focusNode!.hasFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(expanded(searchHeader), isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.pumpAndSettle();
      expect(expanded(searchHeader), isTrue);
      expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
      expect(tester.widget<TextField>(search).controller!.text, query);

      await press(explorerHeader);
      expect(expanded(explorerHeader), isFalse);
      expect(height(explorerPane), 28);
      expect(sash, findsOneWidget);
      final tallSearch = height(searchPane);
      await tester.drag(sash, const Offset(0, 64),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(height(searchPane), closeTo(tallSearch + 64, 0.05));
      expect(height(explorerPane), 28);
      await tester.tap(sash, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 70));
      await tester.tap(sash, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(height(searchPane), closeTo(height(gitPane), 0.05));
      expect(height(explorerPane), 28);
      await tester.pump(const Duration(milliseconds: 700));
      final balanced = layoutStore.tryLoad()!.sidebarGroupPaneWeights;
      expect(balanced['explorer'], closeTo(initialWeights['explorer']!, 1e-9));

      // Keep enough focusable headers to reopen a completely collapsed group.
      await press(searchHeader);
      await press(gitHeader);
      expect([searchPane, explorerPane, gitPane].map(height), [28, 28, 28]);
      expect(search, findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(expanded(gitHeader), isTrue);
      expect(height(gitPane), greaterThan(gitHeight));
      await tester.pump(const Duration(milliseconds: 700));
      expect(layoutStore.tryLoad()!.sidebarGroupCollapsedPanes,
          {'search', 'explorer'});

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mount();
      expect(expanded(searchHeader), isFalse);
      expect(expanded(explorerHeader), isFalse);
      await press(explorerHeader);
      await press(searchHeader);
      expect(expanded(searchHeader), isTrue);
      expect(expanded(explorerHeader), isTrue);
      expect(height(explorerPane), closeTo(explorerHeight, 0.05));
      expect(height(searchPane), closeTo(height(gitPane), 0.05));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  for (final location in [
    primarySidebarViewLocation,
    secondarySidebarViewLocation,
  ]) {
    testWidgets('$location pane headers reorder only inside their group',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 980);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final layout = WorkbenchLayout();
      if (location == secondarySidebarViewLocation) {
        layout.moveSidebarView('explorer', location);
        layout.showRegion(secondarySidebarRegion);
      }
      for (final view in ['search', 'git']) {
        layout.moveSidebarView(view, panelSidebarViewLocation);
        layout.moveSidebarView(view, location, sidebarPlacement: (
          container: 'explorer',
          before: view == 'search'
        ));
      }
      layout.setSidebarGroupPaneWeights(
        'explorer',
        {'search': 1.18, 'explorer': 0.84, 'git': 0.98},
      );
      layoutStore.save(layout.root);
      layout.dispose();

      Future<void> mount() async {
        await tester.pumpWidget(AlulaApp(
          layoutStore: layoutStore,
          sessionStore: sessionStore,
        ));
        await tester.pumpAndSettle();
      }

      await mount();
      final search = find.byKey(const ValueKey('search-input'));
      final searchHeader =
          find.byKey(ValueKey('sidebar-group-header-$location-search'));
      final explorerHeader =
          find.byKey(ValueKey('sidebar-group-header-$location-explorer'));
      final searchPane = find.byKey(ValueKey('$location-sidebar-group-search'));
      final explorerPane =
          find.byKey(ValueKey('$location-sidebar-group-original-explorer'));
      final gitPane = find.byKey(ValueKey('$location-sidebar-group-git'));
      final before =
          find.byKey(ValueKey('sidebar-group-drop-$location-explorer-before'));
      final after =
          find.byKey(ValueKey('sidebar-group-drop-$location-explorer-after'));

      double height(Finder pane) => tester.getSize(pane).height;
      bool searchFirst() =>
          tester.getTopLeft(searchPane).dy < tester.getTopLeft(explorerPane).dy;
      Future<TestGesture> dragTo(
          Finder header, Finder body, double fraction) async {
        final gesture = await tester.startGesture(
          tester.getTopLeft(header) + const Offset(32, 14),
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveBy(const Offset(18, 0));
        final size = tester.getSize(body);
        await gesture.moveTo(
          tester.getTopLeft(body) +
              Offset(size.width * .6, size.height * fraction),
        );
        await tester.pump();
        return gesture;
      }

      const input = 'search retained through reorder 😀';
      await tester.enterText(search, input);
      final originalSearchHeight = height(searchPane);
      final originalExplorerHeight = height(explorerPane);
      final gitRect = tester.getRect(gitPane);
      final savedWeights = layoutStore.tryLoad()!.sidebarGroupPaneWeights;

      final invalid = await dragTo(
        searchHeader,
        find.byKey(const ValueKey('wb-region-editor')),
        .6,
      );
      expect(before, findsNothing);
      expect(after, findsNothing);
      await invalid.up();
      await tester.pumpAndSettle();
      expect(searchFirst(), isTrue);
      final noOp = await dragTo(searchHeader, explorerPane, .25);
      expect(before, findsOneWidget);
      await noOp.up();
      await tester.pumpAndSettle();
      expect(searchFirst(), isTrue);

      final canceled = await dragTo(searchHeader, explorerPane, .74);
      expect(after, findsOneWidget);
      await canceled.cancel();
      await tester.pumpAndSettle();
      expect(after, findsNothing);
      expect(searchFirst(), isTrue);
      final move = await dragTo(searchHeader, explorerPane, .74);
      expect(after, findsOneWidget);
      await move.up();
      await tester.pumpAndSettle();
      expect(searchFirst(), isFalse);
      expect(height(searchPane), closeTo(originalSearchHeight, 0.05));
      expect(height(explorerPane), closeTo(originalExplorerHeight, 0.05));
      expect(tester.getRect(gitPane), gitRect);
      expect(tester.widget<TextField>(search).controller!.text, input);

      await tester.tap(searchHeader, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(search, findsNothing);
      final moveClosed = await dragTo(searchHeader, explorerPane, .25);
      expect(before, findsOneWidget);
      await moveClosed.up();
      await tester.pumpAndSettle();
      expect(searchFirst(), isTrue);
      expect(height(searchPane), 28);
      expect(search, findsNothing);
      await tester.tap(searchHeader, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).controller!.text, input);
      expect(height(searchPane), closeTo(originalSearchHeight, 0.05));

      final moveHost = await dragTo(explorerHeader, searchPane, .25);
      await moveHost.up();
      await tester.pumpAndSettle();
      expect(searchFirst(), isFalse);
      await tester.tap(searchHeader, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      final saved = layoutStore.tryLoad()!;
      expect(saved.sidebarViewPlacements['search'],
          (container: 'explorer', before: false));
      expect(saved.sidebarGroupPaneWeights, savedWeights);
      expect(saved.sidebarGroupCollapsedPanes, {'search'});

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mount();
      expect(searchFirst(), isFalse);
      expect(height(searchPane), 28);
      await tester.tap(searchHeader, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(height(searchPane), closeTo(originalSearchHeight, 0.05));
      expect(tester.getRect(gitPane), gitRect);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  for (final position in [PanelPosition.bottom, PanelPosition.right]) {
    testWidgets('$position group sash resizes and balances its adjacent panes',
        (tester) async {
      tester.view.physicalSize = const Size(1480, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final layout = WorkbenchLayout();
      const tab = PanelViewTab.diagnostics;
      for (final view in ['search', 'outline']) {
        layout.moveSidebarView(view, panelSidebarViewLocation,
            panelPlacement: (tab: tab, before: view == 'search'));
      }
      layout.setPanelPosition(position);
      layout.showRegion('panel');
      layout.setRegionCollapsed('sidebar', true);
      layoutStore.save(layout.root);
      layout.dispose();
      final keybindingsPath = '${temp.path}/panel-sash-keybindings.json';
      File(keybindingsPath).writeAsStringSync(
        '[{"key":"f7","command":"view.togglePanel"}]',
      );

      Future<void> mount() async {
        await tester.pumpWidget(AlulaApp(
          layoutStore: layoutStore,
          sessionStore: sessionStore,
          keybindingsStore: KeybindingsStore(path: keybindingsPath),
        ));
        await tester.pumpAndSettle();
      }

      await mount();
      final vertical = position == PanelPosition.right;
      final sash = find.byKey(
          const ValueKey('panel-group-sash-diagnostics-search-original'));
      final first =
          find.byKey(const ValueKey('panel-view-group-diagnostics-search'));
      final second =
          find.byKey(const ValueKey('panel-view-group-diagnostics-original'));
      final third =
          find.byKey(const ValueKey('panel-view-group-diagnostics-outline'));
      final search = find.byKey(const ValueKey('search-input'));
      double extent(Finder pane) {
        final size = tester.getSize(pane);
        return vertical ? size.height : size.width;
      }

      Future<TestGesture> drag(double delta) async {
        final gesture = await tester.startGesture(
          tester.getCenter(sash),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await gesture.moveBy(vertical ? Offset(0, delta) : Offset(delta, 0));
        await tester.pump();
        return gesture;
      }

      const query = 'survives panel sash drag 😀';
      await tester.enterText(search, query);
      final initialFirst = extent(first);
      final initialSecond = extent(second);
      final initialThird = extent(third);
      final preview = await drag(60);
      expect(extent(first), closeTo(initialFirst + 60, .05));
      expect(extent(second), closeTo(initialSecond - 60, .05));
      expect(extent(third), closeTo(initialThird, .05));
      await tester.pump(const Duration(milliseconds: 700));
      expect(layoutStore.tryLoad()!.panelGroupPaneWeights, isEmpty);
      await preview.cancel();
      await tester.pumpAndSettle();
      expect(extent(first), closeTo(initialFirst, .05));
      expect(extent(second), closeTo(initialSecond, .05));

      final searchMinimum = await drag(-1200);
      expect(extent(first), closeTo(228, .05));
      await searchMinimum.up();
      await tester.pumpAndSettle();
      final originalMinimum = await drag(1200);
      expect(extent(second), closeTo(228, .05));
      await originalMinimum.up();
      await tester.pumpAndSettle();
      expect(extent(third), closeTo(initialThird, .05));
      final dragged = extent(first);
      await tester.pump(const Duration(milliseconds: 700));
      final weights = layoutStore.tryLoad()!.panelGroupPaneWeights[tab]!;
      expect(weights.keys.toSet(), {'search', 'original', 'outline'});
      expect(weights['search'], greaterThan(weights['original']!));
      final midpoint = (dragged + extent(second)) / 2;

      await tester.tap(sash, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 400));
      expect(extent(first), closeTo(dragged, .05));
      expect(extent(second), closeTo(228, .05));
      expect(layoutStore.tryLoad()!.panelGroupPaneWeights[tab], weights);

      await tester.tap(sash, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 70));
      await tester.tap(sash, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(extent(first), closeTo(midpoint, .05));
      expect(extent(second), closeTo(midpoint, .05));
      expect(extent(third), closeTo(initialThird, .05));
      expect(tester.widget<TextField>(search).controller!.text, query);
      await tester.pump(const Duration(milliseconds: 700));
      final balanced = layoutStore.tryLoad()!.panelGroupPaneWeights[tab]!;
      expect(balanced['search'], closeTo(balanced['original']!, 1e-9));

      await tester.tap(find.byKey(const ValueKey('wb-region-editor')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f7);
      await tester.pumpAndSettle();
      expect(sash, findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.f7);
      await tester.pumpAndSettle();
      expect(extent(first), closeTo(midpoint, .05));
      expect(extent(second), closeTo(midpoint, .05));
      expect(tester.widget<TextField>(search).controller!.text, query);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mount();
      expect(extent(first), closeTo(midpoint, .05));
      expect(extent(second), closeTo(midpoint, .05));
      expect(extent(third), closeTo(initialThird, .05));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  for (final position in [PanelPosition.bottom, PanelPosition.right]) {
    testWidgets('$position grouped panels fold on their main axis',
        (tester) async {
      tester.view.physicalSize = const Size(1480, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final layout = WorkbenchLayout();
      const tab = PanelViewTab.diagnostics;
      layout.moveSidebarView('search', panelSidebarViewLocation,
          panelPlacement: (tab: tab, before: true));
      layout.setPanelGroupPaneWeights(tab, {'search': 1.3, 'original': .7});
      layout.setPanelPosition(position);
      layout.showRegion('panel');
      layout.setRegionCollapsed('sidebar', true);
      layoutStore.save(layout.root);
      layout.dispose();
      final keybindingsPath = '${temp.path}/panel-fold-keybindings.json';
      File(keybindingsPath).writeAsStringSync(
        '[{"key":"f6","command":"view.search"},{"key":"f7","command":"view.togglePanel"}]',
      );

      Future<void> mount() async {
        await tester.pumpWidget(AlulaApp(
          layoutStore: layoutStore,
          sessionStore: sessionStore,
          keybindingsStore: KeybindingsStore(path: keybindingsPath),
        ));
        await tester.pumpAndSettle();
      }

      await mount();
      final vertical = position == PanelPosition.right;
      final search = find.byKey(const ValueKey('search-input'));
      final searchHeader =
          find.byKey(const ValueKey('panel-group-header-diagnostics-search'));
      final hostHeader =
          find.byKey(const ValueKey('panel-group-header-diagnostics-original'));
      final sash = find.byKey(
          const ValueKey('panel-group-sash-diagnostics-search-original'));
      final first =
          find.byKey(const ValueKey('panel-view-group-diagnostics-search'));
      final host =
          find.byKey(const ValueKey('panel-view-group-diagnostics-original'));

      double extent(Finder pane) {
        final size = tester.getSize(pane);
        return vertical ? size.height : size.width;
      }

      bool expanded(Finder header) =>
          tester.widget<Semantics>(header).properties.expanded!;
      Future<void> press(Finder header) async {
        await tester.tap(header, kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
      }

      const query = 'retained through Panel folding 😀';
      await tester.enterText(search, query);
      final firstBefore = extent(first);
      final hostBefore = extent(host);
      final weights = layoutStore.tryLoad()!.panelGroupPaneWeights;
      await press(searchHeader);
      expect(expanded(searchHeader), isFalse);
      expect(extent(first), 28);
      expect(extent(host), greaterThan(hostBefore));
      expect(search, findsNothing);
      expect(sash, findsNothing);
      if (!vertical) {
        expect(tester.widget<Semantics>(searchHeader).properties.label, '搜索');
        expect(
          find.descendant(of: searchHeader, matching: find.byType(Tooltip)),
          findsOneWidget,
        );
      }
      await tester.pump(const Duration(milliseconds: 700));
      expect(layoutStore.tryLoad()!.panelGroupCollapsedPanes[tab], {'search'});
      expect(layoutStore.tryLoad()!.panelGroupPaneWeights, weights);

      await tester.tap(find.byKey(const ValueKey('wb-region-editor')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f7);
      await tester.pumpAndSettle();
      expect(searchHeader, findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.f7);
      await tester.pumpAndSettle();
      expect(expanded(searchHeader), isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.pumpAndSettle();
      expect(expanded(searchHeader), isTrue);
      expect(extent(first), closeTo(firstBefore, .05));
      expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
      expect(tester.widget<TextField>(search).controller!.text, query);

      await press(hostHeader);
      expect(expanded(hostHeader), isFalse);
      expect(extent(host), 28);
      expect(extent(first), greaterThan(firstBefore));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(expanded(hostHeader), isTrue);
      expect(extent(host), closeTo(hostBefore, .05));

      await press(hostHeader);
      await press(searchHeader);
      expect([extent(first), extent(host)], [28, 28]);
      expect(search, findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(expanded(searchHeader), isTrue);
      expect(tester.widget<TextField>(search).controller!.text, query);
      await tester.pump(const Duration(milliseconds: 700));
      expect(
          layoutStore.tryLoad()!.panelGroupCollapsedPanes[tab], {'original'});

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mount();
      expect(expanded(hostHeader), isFalse);
      expect(expanded(searchHeader), isTrue);
      await press(hostHeader);
      expect(extent(first), closeTo(firstBefore, .05));
      expect(extent(host), closeTo(hostBefore, .05));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets(
      'Reset View Locations command restores defaults and persists through remount',
      (tester) async {
    final seeded = WorkbenchLayout();
    expect(
        seeded.moveSidebarView('search', secondarySidebarViewLocation), isTrue);
    expect(seeded.moveSidebarView('git', secondarySidebarViewLocation), isTrue);
    expect(seeded.selectSidebarView('search'), isTrue);
    seeded.setRegionCollapsed(secondarySidebarRegion, false);
    final unrelatedBefore = _withoutViewMetadata(seeded.root.toJson());
    layoutStore.save(seeded.root);
    seeded.dispose();

    Future<void> mountApp() async {
      await tester.pumpWidget(AlulaApp(
        layoutStore: layoutStore,
        sessionStore: sessionStore,
      ));
      await tester.pump(const Duration(milliseconds: 300));
    }

    await mountApp();
    final primary = find.byKey(const ValueKey('wb-region-sidebar'));
    final secondary = find.byKey(const ValueKey('wb-region-secondarySidebar'));
    expect(
      find.descendant(
          of: secondary, matching: find.byKey(const ValueKey('search-input'))),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('command-center-control')));
    await tester.pumpAndSettle();
    final input = find.descendant(
      of: find.byKey(const ValueKey('quick-input')),
      matching: find.byType(TextField),
    );
    await tester.enterText(input, '重置视图位置');
    await tester.pumpAndSettle();
    final command = find.byKey(const ValueKey('qi-查看: 重置视图位置'));
    expect(command, findsOneWidget,
        reason: 'the fixed command is available directly from Command Palette');
    await tester.tap(command);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));

    final saved = layoutStore.tryLoad()!;
    expect(saved.sidebarViewLocations, isNull);
    final restoredLayout = WorkbenchLayout(root: saved);
    expect(restoredLayout.sidebarViews(primarySidebarViewLocation),
        activityBarViewOrder);
    expect(restoredLayout.sidebarViews(secondarySidebarViewLocation), isEmpty);
    expect(restoredLayout.primarySidebarView, 'explorer');
    expect(restoredLayout.secondarySidebarView, isNull);
    expect(saved.leafOf(secondarySidebarRegion)!.collapsed, isFalse,
        reason: 'resetting views preserves Secondary visibility');
    expect(_withoutViewMetadata(saved.toJson()), unrelatedBefore);
    expect(
      find.descendant(of: primary, matching: find.text('资源管理器')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: secondary, matching: find.text('此侧栏暂时没有视图')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await mountApp();
    final remountedPrimary = find.byKey(const ValueKey('wb-region-sidebar'));
    final remountedSecondary =
        find.byKey(const ValueKey('wb-region-secondarySidebar'));
    expect(
      find.descendant(of: remountedPrimary, matching: find.text('资源管理器')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: remountedSecondary, matching: find.text('此侧栏暂时没有视图')),
      findsOneWidget,
    );
    expect(layoutStore.tryLoad()!.sidebarViewLocations, isNull);

    restoredLayout.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

Map<String, Object?> _withoutViewMetadata(Map<String, Object?> json) {
  return Map<String, Object?>.of(json)
    ..remove('sidebarViewLocations')
    ..remove('primarySidebarView')
    ..remove('secondarySidebarView');
}
