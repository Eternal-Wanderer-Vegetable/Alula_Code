import 'dart:io';

import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/activity_bar.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late LayoutStore layoutStore;
  late SessionStore sessionStore;
  late KeybindingsStore keybindingsStore;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('alula_activity_bar_pins');
    final root = temp.path.replaceAll(r'\', '/');
    layoutStore = LayoutStore(path: '$root/layout.json');
    sessionStore = SessionStore(path: '$root/session.json');
    keybindingsStore = KeybindingsStore(path: '$root/keybindings.json');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  testWidgets('P05.16 badge visibility persists through layout reload',
      (tester) async {
    Future<void> mountApp() async {
      await tester.pumpWidget(AlulaApp(
        layoutStore: layoutStore,
        sessionStore: sessionStore,
        keybindingsStore: keybindingsStore,
      ));
      await tester.pump(const Duration(milliseconds: 300));
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

    await mountApp();
    await tester.tapAt(
      tester.getCenter(_activityBarView('搜索')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('activity-bar-item-badge-search')),
    );
    await tester.pumpAndSettle();

    var activityBar = tester.widget<ActivityBar>(find.byType(ActivityBar));
    expect(activityBar.badgeDisabledViews, ['search']);
    await tester.pump(const Duration(milliseconds: 700));
    expect(layoutStore.tryLoad()!.activityBarBadgesDisabled, ['search']);

    await selectPosition('顶部(T)');
    await tester.pump(const Duration(milliseconds: 700));
    await selectPosition('底部(B)');
    await tester.pump(const Duration(milliseconds: 700));
    await selectPosition('侧边(D)');
    await tester.pump(const Duration(milliseconds: 700));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await mountApp();
    activityBar = tester.widget<ActivityBar>(find.byType(ActivityBar));
    expect(activityBar.badgeDisabledViews, ['search']);
    expect(layoutStore.tryLoad()!.activityBarBadgesDisabled, ['search']);
  });

  testWidgets('P05.15 pin state saves, survives modes and restores on remount',
      (tester) async {
    Future<void> mountApp() async {
      await tester.pumpWidget(AlulaApp(
        layoutStore: layoutStore,
        sessionStore: sessionStore,
        keybindingsStore: keybindingsStore,
      ));
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> waitForLayoutSave() async {
      await tester.pump(const Duration(milliseconds: 600));
      expect(layoutStore.tryLoad()!.activityBarPinned,
          ['explorer', 'outline', 'git']);
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
      final activity = tester.getRect(
        find.byKey(const ValueKey('wb-region-activity')),
      );
      await tester.tapAt(
        Offset(activity.center.dx, activity.top + activity.height * 0.72),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activity Bar Size'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('activity-bar-size-compact')));
      await tester.pumpAndSettle();
    }

    await mountApp();
    await tester.tap(_activityBarView('搜索'));
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getCenter(_activityBarView('搜索')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('activity-bar-item-pin-search')),
    );
    await tester.pumpAndSettle();
    expect(_activityBarView('搜索'), findsOneWidget,
        reason: 'an active view remains available after unpinning');
    await waitForLayoutSave();

    await tester.tap(find.byTooltip('资源管理器'));
    await tester.pumpAndSettle();
    expect(_activityBarView('搜索'), findsNothing,
        reason: 'switching away hides the active but unpinned view');
    await waitForLayoutSave();

    await selectPosition('顶部(T)');
    await waitForLayoutSave();
    await selectPosition('底部(B)');
    await waitForLayoutSave();
    await selectPosition('隐藏(H)');
    await waitForLayoutSave();
    await selectPosition('侧边(D)');
    await selectCompactSize();
    await waitForLayoutSave();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await mountApp();
    final activityBar = tester.widget<ActivityBar>(find.byType(ActivityBar));
    expect(activityBar.pinnedViews, ['explorer', 'outline', 'git']);
    expect(activityBar.size, ActivityBarSize.compact);
    expect(_activityBarView('搜索'), findsNothing);
    expect(layoutStore.tryLoad()!.activityBarPinned,
        ['explorer', 'outline', 'git']);
  });
}

Finder _activityBarView(String tooltip) => find.descendant(
      of: find.byType(ActivityBar),
      matching: find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.message == tooltip,
      ),
    );
