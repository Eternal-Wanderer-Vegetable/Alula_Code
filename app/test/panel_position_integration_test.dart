import 'dart:io';

import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/panel_position.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late LayoutStore layoutStore;
  late SessionStore sessionStore;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('alula_panel_position');
    final root = temp.path.replaceAll(r'\', '/');
    layoutStore = LayoutStore(path: '$root/layout.json');
    sessionStore = SessionStore(path: '$root/session.json');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  testWidgets('all Panel positions, menus, persistence and remount',
      (tester) async {
    final seeded = defaultLayout();
    final panel = seeded.leafOf('panel')!..collapsed = false;
    panel.lastWeight = null;
    layoutStore.save(seeded);

    Future<void> mountApp() async {
      await tester.pumpWidget(AlulaApp(
        layoutStore: layoutStore,
        sessionStore: sessionStore,
      ));
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> openPanelPositionMenu() async {
      await tester.tap(find.text('查看(V)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('外观(A)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('面板位置(M)'));
      await tester.pumpAndSettle();
    }

    Future<void> expectPositionChecked(String label, bool checked) async {
      await openPanelPositionMenu();
      final item = find
          .ancestor(of: find.text(label), matching: find.byType(MenuItemButton))
          .first;
      expect(
        tester.widget<MenuItemButton>(item).leadingIcon,
        checked ? isA<Icon>() : isA<SizedBox>(),
        reason: '$label checked state should be $checked',
      );
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    Future<void> openCommand(String query, String commandKey) async {
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
      await tester.pump(const Duration(milliseconds: 600));
    }

    void expectPanelAt(PanelPosition position) {
      final saved = layoutStore.tryLoad()!;
      final panelIndex = saved.children.indexWhere(
        (node) => node is WbLeaf && node.region == 'panel',
      );
      final leading =
          position == PanelPosition.top || position == PanelPosition.left;
      expect(panelIndex, leading ? 0 : saved.children.length - 1);
      expect(
        saved.axis,
        position == PanelPosition.top || position == PanelPosition.bottom
            ? Axis.vertical
            : Axis.horizontal,
      );
      final panelRect =
          tester.getRect(find.byKey(const ValueKey('wb-region-panel')));
      final editorRect =
          tester.getRect(find.byKey(const ValueKey('wb-region-editor')));
      expect(
        switch (position) {
          PanelPosition.top => panelRect.top < editorRect.top,
          PanelPosition.bottom => panelRect.top > editorRect.top,
          PanelPosition.left => panelRect.right < editorRect.left,
          PanelPosition.right => panelRect.left > editorRect.right,
        },
        isTrue,
        reason: 'Panel should be at $position',
      );
    }

    await mountApp();
    await expectPositionChecked('底部(B)', true);

    await openCommand(
      '将面板移到左侧',
      'qi-查看: 将面板移到左侧',
    );
    expectPanelAt(PanelPosition.left);
    await expectPositionChecked('左侧(L)', true);

    await openCommand(
      '将面板移到右侧',
      'qi-查看: 将面板移到右侧',
    );
    expectPanelAt(PanelPosition.right);
    await expectPositionChecked('右侧(R)', true);

    await openCommand(
      '将面板移到顶部',
      'qi-查看: 将面板移到顶部',
    );
    expectPanelAt(PanelPosition.top);
    await expectPositionChecked('顶部(T)', true);

    // The Appearance submenu routes the registered command and persists the
    // horizontal/vertical root orientation for a fresh workbench.
    await openPanelPositionMenu();
    await tester.tap(find.text('底部(B)'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    expectPanelAt(PanelPosition.bottom);
    await expectPositionChecked('底部(B)', true);

    await openPanelPositionMenu();
    await tester.tap(find.text('左侧(L)'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    expectPanelAt(PanelPosition.left);
    await expectPositionChecked('左侧(L)', true);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await mountApp();
    expectPanelAt(PanelPosition.left);
    await expectPositionChecked('左侧(L)', true);
  });

  testWidgets('collapsed Panel can move horizontally and retains its state',
      (tester) async {
    final seeded = defaultLayout();
    expect(seeded.leafOf('panel')!.collapsed, isTrue);
    layoutStore.save(seeded);

    Future<void> mountApp() async {
      await tester.pumpWidget(AlulaApp(
        layoutStore: layoutStore,
        sessionStore: sessionStore,
      ));
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> movePanelToLeft() async {
      await tester.tap(find.byKey(const ValueKey('command-center-control')));
      await tester.pumpAndSettle();
      final input = find.descendant(
        of: find.byKey(const ValueKey('quick-input')),
        matching: find.byType(TextField),
      );
      await tester.enterText(input, '将面板移到左侧');
      await tester.pumpAndSettle();
      final command = find.byKey(const ValueKey('qi-查看: 将面板移到左侧'));
      expect(command, findsOneWidget);
      await tester.tap(command);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
    }

    await mountApp();
    await movePanelToLeft();

    WbLeaf savedPanel() {
      final saved = layoutStore.tryLoad()!;
      expect(saved.axis, Axis.horizontal);
      expect(saved.children.first, isA<WbLeaf>());
      final panel = saved.children.first as WbLeaf;
      expect(panel.region, 'panel');
      expect(panel.collapsed, isTrue);
      return panel;
    }

    savedPanel();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await mountApp();
    savedPanel();

    await tester.tap(find.byKey(const ValueKey('command-center-control')));
    await tester.pumpAndSettle();
    final input = find.descendant(
      of: find.byKey(const ValueKey('quick-input')),
      matching: find.byType(TextField),
    );
    await tester.enterText(input, '将面板移到底部');
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('qi-查看: 将面板移到底部')),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    final restored = layoutStore.tryLoad()!;
    expect(restored.axis, Axis.vertical);
    final restoredPanel = restored.children.last as WbLeaf;
    expect(restoredPanel.region, 'panel');
    expect(restoredPanel.collapsed, isTrue);
  });
}
