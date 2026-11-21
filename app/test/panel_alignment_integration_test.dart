import 'dart:io';

import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late LayoutStore layoutStore;
  late SessionStore sessionStore;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('alula_panel_alignment');
    final root = temp.path.replaceAll(r'\', '/');
    layoutStore = LayoutStore(path: '$root/layout.json');
    sessionStore = SessionStore(path: '$root/session.json');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  testWidgets('alignment commands, submenu checks and root JSON restore',
      (tester) async {
    final seeded = defaultLayout();
    seeded.leafOf('panel')!
      ..collapsed = false
      ..lastWeight = null;
    layoutStore.save(seeded);

    Future<void> mountApp() async {
      await tester.pumpWidget(AlulaApp(
        layoutStore: layoutStore,
        sessionStore: sessionStore,
      ));
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> openAlignmentMenu() async {
      await tester.tap(find.text('查看(V)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('外观(A)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('面板对齐方式'));
      await tester.pumpAndSettle();
    }

    Future<void> expectAlignmentChecked(
      String label, {
      required bool checked,
      bool select = false,
    }) async {
      await openAlignmentMenu();
      final item = find
          .ancestor(of: find.text(label), matching: find.byType(MenuItemButton))
          .first;
      expect(
        tester.widget<MenuItemButton>(item).leadingIcon,
        checked ? isA<Icon>() : isA<SizedBox>(),
        reason: '$label checked state should be $checked',
      );
      if (select) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
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

    WbSplit persistedRoot() => layoutStore.tryLoad()!;

    await mountApp();
    await expectAlignmentChecked('居中', checked: true, select: true);

    // Code-OSS moves a side Panel to Bottom before applying the alignment.
    await openCommand('将面板移到左侧', 'qi-查看: 将面板移到左侧');
    await openCommand('将面板对齐到左侧', 'qi-查看: 将面板对齐到左侧');
    expect(persistedRoot().axis, Axis.vertical);
    expect(persistedRoot().children.last, isA<WbLeaf>());
    expect(persistedRoot().toJson()['panelAlignment'], 'left');
    await expectAlignmentChecked('左侧', checked: true);

    // Later side positioning retains the chosen alignment value.
    await openCommand('将面板移到右侧', 'qi-查看: 将面板移到右侧');
    expect(persistedRoot().axis, Axis.horizontal);
    expect(persistedRoot().toJson()['panelAlignment'], 'left');

    await openCommand('将面板对齐到两端', 'qi-查看: 将面板对齐到两端');
    expect(persistedRoot().axis, Axis.vertical);
    expect(persistedRoot().toJson()['panelAlignment'], 'justify');
    await expectAlignmentChecked('两端对齐', checked: true);

    await openCommand('将面板移到顶部', 'qi-查看: 将面板移到顶部');
    expect(persistedRoot().toJson()['panelAlignment'], 'justify');
    expect(persistedRoot().children.first, isA<WbLeaf>());

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await mountApp();
    expect(persistedRoot().toJson()['panelAlignment'], 'justify');
    await expectAlignmentChecked('两端对齐', checked: true);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
