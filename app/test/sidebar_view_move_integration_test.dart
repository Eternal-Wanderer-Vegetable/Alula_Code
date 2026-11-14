import 'dart:io';

import 'package:alula_app/main.dart';
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
