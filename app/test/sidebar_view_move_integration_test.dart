import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_controller.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/layout_store.dart';
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
      find.descendant(of: secondary, matching: find.text('资源管理器')),
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
      find.descendant(of: secondary, matching: find.text('资源管理器')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('资源管理器'));
    await tester.pumpAndSettle();
    await openCommand('移动聚焦的视图', 'qi-查看: 移动聚焦的视图…');
    await tester.tap(find.byKey(const ValueKey('qi-主侧栏')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: primary, matching: find.text('资源管理器')),
      findsOneWidget,
      reason: 'moveFocusedView acts on the view selected by the Activity Bar',
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
      find.descendant(
        of: restoredSecondary,
        matching: find.text('资源管理器'),
      ),
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
