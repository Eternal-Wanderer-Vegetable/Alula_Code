import 'dart:async';
import 'dart:io';

import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/command_history.dart';
import 'package:alula_app/workbench/command_history_store.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/quick_input.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

late Directory temp;
late LayoutStore layoutStore;
late SessionStore sessionStore;
late CommandHistoryStore commandHistoryStore;

void main() {
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('alula_cmd_palette_history');
    final root = temp.path.replaceAll(r'\', '/');
    layoutStore = LayoutStore(path: '$root/layout.json');
    sessionStore = SessionStore(path: '$root/session.json');
    commandHistoryStore = CommandHistoryStore(path: '$root/command-history');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  testWidgets(
      'palette records accepted commands, reorders and survives remount',
      (tester) async {
    await _mountApp(tester);
    try {
      await _openPalette(tester);
      await tester.enterText(_inputFinder(), '> 移动视图');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('qi-查看: 移动视图…')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
          commandHistoryStore.load().commandIds, ['workbench.action.moveView']);

      await _openPalette(tester);
      expect(find.byKey(const ValueKey('qi-separator-最近使用')), findsOneWidget);
      expect(find.byKey(const ValueKey('qi-separator-其他命令')), findsOneWidget);
      expect(
          _rowTop(tester, '查看: 移动视图…'), lessThan(_rowTop(tester, '文件: 新建文本文件')),
          reason: '最近使用的命令在空查询里排到最前');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // 重新挂载后历史从 journal 恢复。
      await _unmountApp(tester);
      await _mountApp(tester);
      await _openPalette(tester);
      expect(find.byKey(const ValueKey('qi-separator-最近使用')), findsOneWidget);
      expect(find.byKey(const ValueKey('qi-separator-其他命令')), findsOneWidget);
      expect(
          _rowTop(tester, '查看: 移动视图…'), lessThan(_rowTop(tester, '文件: 新建文本文件')),
          reason: '历史跨重启恢复并继续参与排序');
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('old notification command history resolves to one current row',
      (tester) async {
    expect(
        commandHistoryStore.save(CommandHistory(commandIds: const [
          'workbench.action.clearNotifications',
          'notifications.clearAll',
          'workbench.action.toggleNotificationsDoNotDisturb',
        ])),
        isTrue);
    await _mountApp(tester);
    try {
      await _openPalette(tester);
      const clear = '查看: 清除所有通知';
      expect(find.byKey(const ValueKey('qi-separator-最近使用')), findsOneWidget);
      expect(find.byKey(const ValueKey('qi-查看: 清除所有通知')), findsOneWidget);
      expect(_rowTop(tester, clear), lessThan(_rowTop(tester, '文件: 新建文本文件')));

      await tester.enterText(_inputFinder(), '> 清除所有通知');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('qi-查看: 清除所有通知')));
      await tester.pumpAndSettle();
      expect(commandHistoryStore.load().commandIds, [
        'notifications.clearAll',
        'notifications.toggleDoNotDisturbMode',
      ]);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('keybinding execution does not enter the palette history',
      (tester) async {
    await _mountApp(tester);
    try {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      final layout = layoutStore.tryLoad();
      expect(layout, isNotNull);
      expect(layout!.leafOf('sidebar')!.collapsed, isTrue,
          reason: 'Ctrl+B 确实执行了切换侧栏');
      expect(commandHistoryStore.load().isEmpty, isTrue,
          reason: '键位执行不写命令面板历史');
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('item buttons render on the active row and run from the keyboard',
      (tester) async {
    final harness = await _pumpPickerHarness(tester);
    var buttonRuns = 0;
    var itemRuns = 0;
    unawaited(QuickInput.show(
      harness.pickerContext,
      hint: '按钮显示时机',
      items: [
        QuickItem(
          label: 'alpha',
          onRun: () async => itemRuns += 1,
          buttons: [
            QuickItemButton(
              icon: Icons.push_pin,
              tooltip: '固定 alpha',
              onRun: () async => buttonRuns += 1,
            ),
          ],
        ),
        QuickItem(
          label: 'beta',
          onRun: () async => itemRuns += 1,
          buttons: [
            QuickItemButton(
              icon: Icons.delete,
              tooltip: '删除 beta',
              onRun: () async => buttonRuns += 1,
            ),
          ],
        ),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('qi-button-alpha-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('qi-button-beta-0')), findsNothing,
        reason: '非活动行不渲染 item 按钮');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('qi-button-alpha-0')), findsNothing,
        reason: '离开该行后按钮隐藏');
    expect(find.byKey(const ValueKey('qi-button-beta-0')), findsOneWidget);

    // Tab 从输入框进入活动行按钮，Enter 触发按钮动作（不触发 item onRun）。
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(buttonRuns, 1);
    expect(itemRuns, 0);
    expect(find.byKey(const ValueKey('quick-input')), findsNothing);
  });
}

Finder _inputFinder() => find.descendant(
      of: find.byKey(const ValueKey('quick-input')),
      matching: find.byType(TextField),
    );

double _rowTop(WidgetTester tester, String label) =>
    tester.getTopLeft(find.byKey(ValueKey('qi-$label'))).dy;

Future<void> _openPalette(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('command-center-control')));
  await tester.pumpAndSettle();
}

Future<void> _mountApp(WidgetTester tester) async {
  await tester.pumpWidget(AlulaApp(
    layoutStore: layoutStore,
    sessionStore: sessionStore,
    commandHistoryStore: commandHistoryStore,
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _unmountApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

class _Harness {
  _Harness(this.pickerContext);

  final BuildContext pickerContext;
}

Future<_Harness> _pumpPickerHarness(WidgetTester tester) async {
  await tester.pumpWidget(const _PickerHarness());
  await tester.pump();
  return _Harness(
    tester.element(find.byKey(const ValueKey('anchor-button'))),
  );
}

class _PickerHarness extends StatelessWidget {
  const _PickerHarness();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: TextButton(
            key: const ValueKey('anchor-button'),
            onPressed: () {},
            child: const Text('anchor'),
          ),
        ),
      ),
    );
  }
}
