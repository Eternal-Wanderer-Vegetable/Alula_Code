import 'dart:io';

import 'dart:ui' show Tristate;
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/activity_bar.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
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
}

Finder _activityBarView(String label) => find
    .descendant(
      of: find.byType(ActivityBar),
      matching: find.byTooltip(label),
    )
    .first;
