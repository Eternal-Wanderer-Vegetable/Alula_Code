import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late LayoutStore layoutStore;
  late SessionStore sessionStore;
  late KeybindingsStore keybindingsStore;

  setUp(() async {
    temp =
        await Directory.systemTemp.createTemp('alula_activity_bar_visibility');
    final root = temp.path.replaceAll(r'\', '/');
    layoutStore = LayoutStore(path: '$root/layout.json');
    sessionStore = SessionStore(path: '$root/session.json');
    keybindingsStore = KeybindingsStore(path: '$root/keybindings.json');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  testWidgets(
    'P05.11 Activity Bar 隐藏、恢复、checked 状态与布局重启保存',
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

      final sideItem = find
          .ancestor(
            of: find.text('侧边(D)'),
            matching: find.byType(MenuItemButton),
          )
          .first;
      final hiddenItem = find
          .ancestor(
            of: find.text('隐藏(H)'),
            matching: find.byType(MenuItemButton),
          )
          .first;

      await mountApp();
      final activityRegion = find.byKey(const ValueKey('wb-region-activity'));
      expect(activityRegion, findsOneWidget);

      // Current view lives in Workbench state and must survive hiding the bar.
      await tester.tap(find.byTooltip('搜索'));
      await tester.pump();
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('搜索'))
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );

      await selectActivityBarPosition('隐藏(H)');
      expect(activityRegion, findsNothing);

      // Restore in the same Workbench session and retain the selected view.
      await openActivityBarPositionMenu();
      expect(
        tester.widget<MenuItemButton>(sideItem).leadingIcon,
        isA<SizedBox>(),
      );
      expect(
        tester.widget<MenuItemButton>(hiddenItem).leadingIcon,
        isA<Icon>(),
      );
      await tester.tap(find.text('侧边(D)'));
      await tester.pumpAndSettle();
      expect(activityRegion, findsOneWidget);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('搜索'))
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
        reason: '恢复 Activity Bar 后保留原来的 Search 视图',
      );

      // Hide again so the saved layout exercises restart restoration.
      await selectActivityBarPosition('隐藏(H)');
      expect(activityRegion, findsNothing);
      await tester.pump(const Duration(milliseconds: 600));
      expect(layoutStore.tryLoad()!.leafOf('activity')!.collapsed, isTrue);

      // A fresh app instance exercises the same persisted layout load path.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await mountApp();
      expect(activityRegion, findsNothing);

      // The View menu remains available while the Activity Bar is hidden.
      await openActivityBarPositionMenu();
      expect(
        tester.widget<MenuItemButton>(sideItem).leadingIcon,
        isA<SizedBox>(),
      );
      expect(
        tester.widget<MenuItemButton>(hiddenItem).leadingIcon,
        isA<Icon>(),
      );
      await tester.tap(find.text('侧边(D)'));
      await tester.pumpAndSettle();
      expect(activityRegion, findsOneWidget);

      // Reopen the menu to make sure its checked state follows the new layout.
      await openActivityBarPositionMenu();
      expect(
        tester.widget<MenuItemButton>(sideItem).leadingIcon,
        isA<Icon>(),
      );
      expect(
        tester.widget<MenuItemButton>(hiddenItem).leadingIcon,
        isA<SizedBox>(),
      );
      semantics.dispose();
    },
  );
}
