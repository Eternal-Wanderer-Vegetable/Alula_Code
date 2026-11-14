import 'dart:async';

import 'package:alula_app/workbench/quick_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('separators render as headings and navigation skips them',
      (tester) async {
    final harness = await _pumpHarness(tester);
    final runs = <String>[];

    unawaited(QuickInput.show(
      harness.pickerContext,
      hint: '分组项',
      items: [
        const QuickItem(label: '主侧栏', kind: QuickItemKind.separator),
        QuickItem(label: '资源管理器', onRun: () async => runs.add('explorer')),
        QuickItem(label: '搜索', onRun: () async => runs.add('search')),
        const QuickItem(label: '次侧栏', kind: QuickItemKind.separator),
        QuickItem(label: '源代码管理', onRun: () async => runs.add('git')),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('qi-separator-主侧栏')), findsOneWidget);
    expect(find.byKey(const ValueKey('qi-separator-次侧栏')), findsOneWidget);

    // 初始选中项越过前面的分组标题，直接落在第一个可选条目上。
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(runs, ['explorer']);

    // 再次打开：方向键跳过中间的分组标题。
    unawaited(QuickInput.show(
      harness.pickerContext,
      hint: '分组项',
      items: [
        const QuickItem(label: '主侧栏', kind: QuickItemKind.separator),
        QuickItem(label: '资源管理器', onRun: () async => runs.add('explorer2')),
        QuickItem(label: '搜索', onRun: () async => runs.add('search2')),
        const QuickItem(label: '次侧栏', kind: QuickItemKind.separator),
        QuickItem(label: '源代码管理', onRun: () async => runs.add('git2')),
      ],
    ));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(runs, ['explorer', 'git2'], reason: '三次向下依次经过搜索与“次侧栏”标题，落在源代码管理');
  });

  testWidgets('separators disappear while a query filters the list',
      (tester) async {
    final harness = await _pumpHarness(tester);
    unawaited(QuickInput.show(
      harness.pickerContext,
      hint: '分组项',
      items: [
        const QuickItem(label: '主侧栏', kind: QuickItemKind.separator),
        QuickItem(label: '资源管理器', onRun: () async {}),
        const QuickItem(label: '次侧栏', kind: QuickItemKind.separator),
        QuickItem(label: '搜索', onRun: () async {}),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('qi-separator-主侧栏')), findsOneWidget);

    await tester.enterText(_inputFinder(), '搜索');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('qi-separator-主侧栏')), findsNothing);
    expect(find.byKey(const ValueKey('qi-separator-次侧栏')), findsNothing);
    expect(find.byKey(const ValueKey('qi-搜索')), findsOneWidget);

    await tester.enterText(_inputFinder(), '');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('qi-separator-主侧栏')), findsOneWidget);
  });

  testWidgets('multi-select toggles with Space and accepts the picked items',
      (tester) async {
    final harness = await _pumpHarness(tester);
    final accepted = <List<String>>[];

    void show() {
      unawaited(QuickInput.show(
        harness.pickerContext,
        hint: '多选',
        canSelectMany: true,
        onAccept: (picked) => accepted.add(picked.map((e) => e.label).toList()),
        items: const [
          QuickItem(label: 'alpha'),
          QuickItem(label: 'beta', picked: true),
          QuickItem(label: 'gamma'),
        ],
      ));
    }

    show();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('qi-check-alpha')), findsOneWidget);
    expect(find.byKey(const ValueKey('qi-check-beta')), findsOneWidget);
    // `picked` 初始态直接进入接受集合。
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(accepted, [
      ['beta']
    ]);

    show();
    await tester.pumpAndSettle();
    // 初始选中 alpha：Space 勾选，再移动到 beta 取消勾选，Enter 接受 alpha。
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(accepted.last, ['alpha']);
  });

  testWidgets('description renders inline and detail renders as a second line',
      (tester) async {
    final harness = await _pumpHarness(tester);
    unawaited(QuickInput.show(
      harness.pickerContext,
      hint: '描述',
      items: [
        QuickItem(
          label: '命令面板',
          description: 'Ctrl+Shift+P',
          detail: '第二行说明',
          onRun: () async {},
        ),
      ],
    ));
    await tester.pumpAndSettle();
    final labelDy = tester.getCenter(find.text('命令面板')).dy;
    final descriptionDy = tester.getCenter(find.text('Ctrl+Shift+P')).dy;
    final detailDy = tester.getCenter(find.text('第二行说明')).dy;
    expect(descriptionDy, closeTo(labelDy, 0.5),
        reason: 'description 与 label 同行右侧');
    expect(detailDy, greaterThan(labelDy), reason: 'detail 渲染在 label 下一行');
  });

  testWidgets('validation message renders below the filter row',
      (tester) async {
    final harness = await _pumpHarness(tester);
    unawaited(QuickInput.show(
      harness.pickerContext,
      hint: '校验',
      validationMessage: '名称已被占用',
      items: [
        QuickItem(label: 'x', onRun: () async {}),
      ],
    ));
    await tester.pumpAndSettle();
    final message = find.byKey(const ValueKey('quick-input-validation'));
    expect(message, findsOneWidget);
    expect(find.text('名称已被占用'), findsOneWidget);
    final messageDy = tester.getCenter(message).dy;
    expect(messageDy, greaterThan(tester.getCenter(find.byType(TextField)).dy),
        reason: '校验消息位于输入行下方');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quick-input')), findsNothing,
        reason: '校验消息不阻断取消');
  });

  testWidgets('multi-select item buttons still run their own action',
      (tester) async {
    final harness = await _pumpHarness(tester);
    var buttonRuns = 0;
    var accepted = 0;
    unawaited(QuickInput.show(
      harness.pickerContext,
      hint: '多选按钮',
      canSelectMany: true,
      onAccept: (_) => accepted += 1,
      items: [
        QuickItem(
          label: 'alpha',
          onRun: () async {},
          buttons: [
            QuickItemButton(
              icon: Icons.push_pin,
              tooltip: '固定 alpha',
              onRun: () async => buttonRuns += 1,
            ),
          ],
        ),
      ],
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('qi-button-alpha-0')));
    await tester.pumpAndSettle();
    expect(buttonRuns, 1);
    expect(accepted, 0, reason: '按钮动作不触发多选接受');
    expect(find.byKey(const ValueKey('quick-input')), findsNothing);
  });
}

Finder _inputFinder() => find.descendant(
      of: find.byKey(const ValueKey('quick-input')),
      matching: find.byType(TextField),
    );

class _Harness {
  _Harness(this.pickerContext);

  final BuildContext pickerContext;
}

Future<_Harness> _pumpHarness(WidgetTester tester) async {
  final key = GlobalKey<_PickerHarnessState>();
  await tester.pumpWidget(_PickerHarness(key: key));
  await tester.pump();
  return _Harness(
    tester.element(find.byKey(const ValueKey('anchor-button'))),
  );
}

class _PickerHarness extends StatefulWidget {
  const _PickerHarness({super.key});

  @override
  State<_PickerHarness> createState() => _PickerHarnessState();
}

class _PickerHarnessState extends State<_PickerHarness> {
  final anchorFocus = FocusNode(debugLabel: 'anchor');

  @override
  void dispose() {
    anchorFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: TextButton(
            key: const ValueKey('anchor-button'),
            focusNode: anchorFocus,
            onPressed: () {},
            child: const Text('anchor'),
          ),
        ),
      ),
    );
  }
}
