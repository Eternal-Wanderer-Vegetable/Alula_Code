import 'dart:io';

import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/layout_store.dart';
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

  testWidgets('Top/Bottom commands, Appearance menu, persistence and remount',
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

    void expectPanelAt(bool top) {
      final saved = layoutStore.tryLoad()!;
      final panelIndex = saved.children.indexWhere(
        (node) => node is WbLeaf && node.region == 'panel',
      );
      expect(panelIndex, top ? 0 : saved.children.length - 1);
      final panelRect =
          tester.getRect(find.byKey(const ValueKey('wb-region-panel')));
      final editorRect =
          tester.getRect(find.byKey(const ValueKey('wb-region-editor')));
      expect(
        panelRect.top,
        top ? lessThan(editorRect.top) : greaterThan(editorRect.top),
      );
    }

    await mountApp();
    await expectPositionChecked('底部(B)', true);

    await openCommand(
      '将面板移到顶部',
      'qi-查看: 将面板移到顶部',
    );
    expectPanelAt(true);
    await expectPositionChecked('顶部(T)', true);

    // The menu routes the second command through the same registry and saves
    // the tree order used by a fresh workbench.
    await openPanelPositionMenu();
    await tester.tap(find.text('底部(B)'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    expectPanelAt(false);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await mountApp();
    expectPanelAt(false);
    await expectPositionChecked('底部(B)', true);
  });

  testWidgets('collapsed Panel can move and retains its hidden state',
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

    Future<void> movePanelToTop() async {
      await tester.tap(find.byKey(const ValueKey('command-center-control')));
      await tester.pumpAndSettle();
      final input = find.descendant(
        of: find.byKey(const ValueKey('quick-input')),
        matching: find.byType(TextField),
      );
      await tester.enterText(input, '将面板移到顶部');
      await tester.pumpAndSettle();
      final command = find.byKey(const ValueKey('qi-查看: 将面板移到顶部'));
      expect(command, findsOneWidget);
      await tester.tap(command);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
    }

    await mountApp();
    await movePanelToTop();

    WbLeaf savedPanel() {
      final saved = layoutStore.tryLoad()!;
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
  });
}
