import 'dart:io';

import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/secondary_sidebar_empty_state.dart';
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
    temp = await Directory.systemTemp.createTemp('alula_secondary_sidebar');
    final root = temp.path.replaceAll(r'\', '/');
    layoutStore = LayoutStore(path: '$root/layout.json');
    sessionStore = SessionStore(path: '$root/session.json');
    keybindingsStore = KeybindingsStore(path: '$root/keybindings.json');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  testWidgets(
    'layout controls and command palette toggle the persisted secondary side bar',
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

      Future<void> openLayoutControls() async {
        await tester.tap(find.byKey(const ValueKey('layout-controls-control')));
        await tester.pumpAndSettle();
      }

      Future<void> pressSecondarySidebarShortcut() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
      }

      final region = find.byKey(const ValueKey('wb-region-secondarySidebar'));
      final menuItem = find.byKey(const ValueKey(
        'layout-control-workbench.action.toggleAuxiliaryBar',
      ));

      await mountApp();
      expect(region, findsNothing,
          reason: 'secondary side bar defaults hidden');
      expect(find.byTooltip('布局控制'), findsOneWidget);

      await openLayoutControls();
      expect(menuItem, findsOneWidget);
      expect(
          tester.widget<MenuItemButton>(menuItem).leadingIcon, isA<SizedBox>());
      await tester.tap(menuItem);
      await tester.pumpAndSettle();

      expect(region, findsOneWidget);
      expect(find.text('此侧栏暂时没有视图'), findsOneWidget);
      expect(
        find.bySemanticsLabel(SecondarySidebarEmptyState.semanticsLabel),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(layoutStore.tryLoad()!.leafOf('secondarySidebar')!.collapsed,
          isFalse);

      await openLayoutControls();
      expect(
        tester.widget<MenuItemButton>(menuItem).leadingIcon,
        isA<Icon>(),
        reason: 'the title-bar action shows its checked state while visible',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await mountApp();
      expect(region, findsOneWidget,
          reason: 'visible state restores on reload');

      await tester.tap(find.byKey(const ValueKey('command-center-control')));
      await tester.pumpAndSettle();
      final paletteInput = find.descendant(
        of: find.byKey(const ValueKey('quick-input')),
        matching: find.byType(TextField),
      );
      await tester.enterText(paletteInput, '切换次侧栏');
      await tester.pumpAndSettle();
      final command = find.byKey(const ValueKey('qi-查看: 切换次侧栏'));
      expect(command, findsOneWidget,
          reason: 'the upstream command is searchable in Command Palette');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(region, findsNothing);
      await tester.pump(const Duration(milliseconds: 600));
      expect(
          layoutStore.tryLoad()!.leafOf('secondarySidebar')!.collapsed, isTrue);

      await pressSecondarySidebarShortcut();
      expect(region, findsOneWidget,
          reason: 'Ctrl+Alt+B shows the secondary side bar');
      await pressSecondarySidebarShortcut();
      expect(region, findsNothing,
          reason: 'Ctrl+Alt+B hides the secondary side bar');
      await tester.pump(const Duration(milliseconds: 600));
      expect(
          layoutStore.tryLoad()!.leafOf('secondarySidebar')!.collapsed, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await mountApp();
      expect(region, findsNothing, reason: 'hidden state restores on reload');
      semantics.dispose();
    },
  );

  testWidgets('P05.19 toggles Side Bar from Appearance and Command Palette',
      (tester) async {
    await tester.pumpWidget(AlulaApp(
      layoutStore: layoutStore,
      sessionStore: sessionStore,
      keybindingsStore: keybindingsStore,
    ));
    await tester.pump(const Duration(milliseconds: 300));

    Future<void> openAppearance() async {
      await tester.tap(find.text('查看(V)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('外观(A)'));
      await tester.pumpAndSettle();
    }

    Future<void> runPaletteCommand(String title) async {
      await tester.tap(find.byKey(const ValueKey('command-center-control')));
      await tester.pumpAndSettle();
      final input = find.descendant(
        of: find.byKey(const ValueKey('quick-input')),
        matching: find.byType(TextField),
      );
      await tester.enterText(input, '主侧栏');
      await tester.pumpAndSettle();
      final item = find.byKey(ValueKey('qi-查看: $title'));
      expect(item, findsOneWidget);
      await tester.tap(item);
      await tester.pumpAndSettle();
    }

    await openAppearance();
    final moveRight = find.text('将主侧栏移到右侧');
    expect(moveRight, findsOneWidget);
    await tester.tap(moveRight);
    await tester.pumpAndSettle();
    await openAppearance();
    expect(find.text('将主侧栏移到左侧'), findsOneWidget,
        reason: 'Appearance title reflects the current side');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await runPaletteCommand('将主侧栏移到左侧');
    await tester.pump(const Duration(milliseconds: 600));
    expect(layoutStore.tryLoad()!.sideBarPosition?.name, 'left');
    await runPaletteCommand('将主侧栏移到右侧');
    await tester.pump(const Duration(milliseconds: 600));
    expect(layoutStore.tryLoad()!.sideBarPosition?.name, 'right');
  });
}
