import 'dart:io';
import 'dart:ui' show Tristate;

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
    temp = await Directory.systemTemp.createTemp('alula_activity_bar_size');
    final root = temp.path.replaceAll(r'\', '/');
    layoutStore = LayoutStore(path: '$root/layout.json');
    sessionStore = SessionStore(path: '$root/session.json');
    keybindingsStore = KeybindingsStore(path: '$root/keybindings.json');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  testWidgets('P05.13 Side size menu, position retention and persistence',
      (tester) async {
    Future<void> mountApp() async {
      await tester.pumpWidget(AlulaApp(
        layoutStore: layoutStore,
        sessionStore: sessionStore,
        keybindingsStore: keybindingsStore,
      ));
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> openSizeSubmenu() async {
      await tester.tapAt(
        tester.getCenter(find.byKey(const ValueKey('wb-region-activity'))),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activity Bar Size'));
      await tester.pumpAndSettle();
    }

    Future<void> selectSize(String key) async {
      await openSizeSubmenu();
      await tester.tap(find.byKey(ValueKey('activity-bar-size-$key')));
      await tester.pumpAndSettle();
    }

    Future<void> selectPosition(String itemLabel) async {
      await tester.tap(find.text('查看(V)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('外观(A)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('活动栏位置(A)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(itemLabel));
      await tester.pumpAndSettle();
    }

    await mountApp();
    final activityRegion = find.byKey(const ValueKey('wb-region-activity'));
    final sidebarRegion = find.byKey(const ValueKey('wb-region-sidebar'));
    expect(tester.getRect(activityRegion).width, closeTo(48, 1));

    await tester.tap(_activityBarView('搜索'));
    await tester.pump();
    await selectSize('compact');
    expect(tester.getRect(activityRegion).width, closeTo(36, 1));
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('搜索'))
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );

    await selectSize('default');
    expect(tester.getRect(activityRegion).width, closeTo(48, 1));
    await selectSize('compact');
    expect(tester.getRect(activityRegion).width, closeTo(36, 1));

    await tester.pump(const Duration(milliseconds: 600));
    final compact = layoutStore.tryLoad()!;
    expect(compact.activityBarSize, ActivityBarSize.compact);
    expect(compact.leafOf('activity')!.fixedExtent, 36);
    expect(compact.leafOf('sidebar')!.collapsed, isFalse);
    expect(compact.leafOf('editor')!.weight, closeTo(0.76, 1e-9));
    expect(compact.leafOf('panel')!.weight, closeTo(0.3, 1e-9));

    await tester.tap(_activityBarView('搜索'));
    await tester.pump();
    expect(sidebarRegion, findsNothing);
    await tester.pump(const Duration(milliseconds: 600));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await mountApp();
    expect(tester.getRect(activityRegion).width, closeTo(36, 1));
    expect(sidebarRegion, findsNothing,
        reason: 'size persistence must preserve sidebar collapsed state');

    await selectPosition('顶部(T)');
    expect(tester.getRect(activityRegion).height, closeTo(44, 1));
    await tester.tapAt(
      tester.getCenter(activityRegion),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('Activity Bar Size'), findsNothing,
        reason: 'the size submenu is only available on Side');
    await tester.pump(const Duration(milliseconds: 600));
    expect(layoutStore.tryLoad()!.activityBarSize, ActivityBarSize.compact);

    await selectPosition('侧边(D)');
    expect(tester.getRect(activityRegion).width, closeTo(36, 1));
    await tester.pump(const Duration(milliseconds: 600));
    expect(layoutStore.tryLoad()!.activityBarSize, ActivityBarSize.compact);
  });
}

Finder _activityBarView(String tooltip) => find.descendant(
      of: find.byType(ActivityBar),
      matching: find.byTooltip(tooltip),
    );
