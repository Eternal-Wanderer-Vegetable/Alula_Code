import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/activity_bar.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late LayoutStore layoutStore;
  late SessionStore sessionStore;
  late KeybindingsStore keybindingsStore;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('alula_activity_bar_position');
    final root = temp.path.replaceAll(r'\', '/');
    layoutStore = LayoutStore(path: '$root/layout.json');
    sessionStore = SessionStore(path: '$root/session.json');
    keybindingsStore = KeybindingsStore(path: '$root/keybindings.json');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  testWidgets('P05.12 Top/Bottom/Side/Hidden commands, menu, persistence',
      (tester) async {
    final semantics = tester.ensureSemantics();

    Future<void> mountApp() async {
      await tester.pumpWidget(AlulaApp(
        layoutStore: layoutStore,
        sessionStore: sessionStore,
        keybindingsStore: keybindingsStore,
      ));
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> openActivityBarPositionMenu() async {
      await tester.tap(find.text('查看(V)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('外观(A)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('活动栏位置(A)'));
      await tester.pumpAndSettle();
    }

    Future<void> selectActivityBarPosition(String itemLabel) async {
      await openActivityBarPositionMenu();
      await tester.tap(find.text(itemLabel));
      await tester.pumpAndSettle();
    }

    Future<void> expectChecked(String label, bool checked) async {
      await openActivityBarPositionMenu();
      final item = find
          .ancestor(of: find.text(label), matching: find.byType(MenuItemButton))
          .first;
      expect(
        tester.widget<MenuItemButton>(item).leadingIcon,
        checked ? isA<Icon>() : isA<SizedBox>(),
        reason: '$label checked state should be $checked',
      );
      // Activate the already selected item to close the menu without changing
      // the layout; the setter is intentionally idempotent.
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    Future<void> waitForLayoutSave() =>
        tester.pump(const Duration(milliseconds: 600));

    await mountApp();
    final activityRegion = find.byKey(const ValueKey('wb-region-activity'));
    final sidebarRegion = find.byKey(const ValueKey('wb-region-sidebar'));
    expect(activityRegion, findsOneWidget);
    expect(tester.widget<ActivityBar>(find.byType(ActivityBar)).axis,
        Axis.vertical);
    await tester.tap(find.byTooltip('搜索'));
    await tester.pump();

    await selectActivityBarPosition('顶部(T)');
    expect(tester.widget<ActivityBar>(find.byType(ActivityBar)).axis,
        Axis.horizontal);
    expect(tester.getRect(activityRegion).height, closeTo(44, 1));
    expect(tester.getRect(activityRegion).top,
        lessThan(tester.getRect(sidebarRegion).top));
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('搜索'))
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
      reason: 'moving the Activity Bar must keep the active Sidebar view',
    );
    await expectChecked('顶部(T)', true);
    await waitForLayoutSave();
    expect(layoutStore.tryLoad()!.activityBarLocation, ActivityBarLocation.top);

    // A fresh Workbench must rebuild the horizontal bar from saved root JSON.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await mountApp();
    expect(tester.widget<ActivityBar>(find.byType(ActivityBar)).axis,
        Axis.horizontal);
    await expectChecked('顶部(T)', true);

    // The currently selected location is omitted from Command Palette results;
    // another placement command remains searchable and executable.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    final paletteInput = find.descendant(
      of: find.byKey(const ValueKey('quick-input')),
      matching: find.byType(TextField),
    );
    await tester.enterText(paletteInput, '将活动栏移到顶部');
    await tester.pumpAndSettle();
    expect(find.text('无匹配项'), findsOneWidget);
    await tester.enterText(paletteInput, '将活动栏移到底部');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('qi-查看: 将活动栏移到底部')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tester.widget<ActivityBar>(find.byType(ActivityBar)).axis,
        Axis.horizontal);
    expect(tester.getRect(activityRegion).bottom,
        greaterThan(tester.getRect(sidebarRegion).bottom));
    await expectChecked('底部(B)', true);

    await waitForLayoutSave();
    expect(
      layoutStore.tryLoad()!.activityBarLocation,
      ActivityBarLocation.bottom,
    );
    await selectActivityBarPosition('侧边(D)');
    expect(tester.widget<ActivityBar>(find.byType(ActivityBar)).axis,
        Axis.vertical);
    expect(tester.getRect(activityRegion).width, closeTo(48, 1));
    expect(tester.getRect(activityRegion).right,
        lessThanOrEqualTo(tester.getRect(sidebarRegion).left));

    await selectActivityBarPosition('隐藏(H)');
    expect(activityRegion, findsNothing);
    await waitForLayoutSave();
    final hidden = layoutStore.tryLoad()!;
    expect(hidden.activityBarLocation, ActivityBarLocation.hidden);
    expect(hidden.leafOf('activity')!.collapsed, isTrue);

    // Hidden remains checked after remount and can restore into Top.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await mountApp();
    expect(activityRegion, findsNothing);
    await expectChecked('隐藏(H)', true);
    await selectActivityBarPosition('顶部(T)');
    expect(activityRegion, findsOneWidget);
    expect(tester.widget<ActivityBar>(find.byType(ActivityBar)).axis,
        Axis.horizontal);
    await expectChecked('顶部(T)', true);
    semantics.dispose();
  });
}
