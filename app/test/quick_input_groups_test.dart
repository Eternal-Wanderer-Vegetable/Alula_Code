import 'dart:async';

import 'package:alula_app/workbench/quick_input.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
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

  testWidgets('page and boundary keys reveal mixed-height picker rows',
      (tester) async {
    final harness = await _pumpHarness(tester);
    final accepted = <String>[];
    var active = '';
    QuickItem row(int number) {
      final label = 'Item ${number.toString().padLeft(2, '0')}';
      return QuickItem(
        label: label,
        detail: number % 3 == 1 ? 'Additional detail' : null,
        onPreview: () => active = label,
        onRun: () async => accepted.add(label),
      );
    }

    final firstGroup = List.generate(16, (index) => row(index + 1));
    final secondGroup = List.generate(24, (index) => row(index + 17));
    unawaited(QuickInput.show(
      harness.pickerContext,
      hint: 'Long picker',
      items: [
        const QuickItem(label: 'First group', kind: QuickItemKind.separator),
        ...firstGroup,
        const QuickItem(label: 'Second group', kind: QuickItemKind.separator),
        ...secondGroup,
        const QuickItem(label: 'Last heading', kind: QuickItemKind.separator),
      ],
    ));
    await tester.pumpAndSettle();

    final list = find.descendant(
      of: find.byKey(const ValueKey('quick-input')),
      matching: find.byType(ListView),
    );
    Finder itemFinder(String label) => find.byKey(ValueKey('qi-$label'));
    bool fullyVisible(String label) {
      final item = itemFinder(label);
      if (item.evaluate().isEmpty) return false;
      final viewport = tester.getRect(list);
      final rect = tester.getRect(item);
      return rect.top >= viewport.top - 0.5 &&
          rect.bottom <= viewport.bottom + 0.5;
    }

    Future<void> key(LogicalKeyboardKey key, {bool control = false}) async {
      if (control) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      }
      await tester.sendKeyEvent(key);
      if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    expect(active, 'Item 01');
    final firstPageTail =
        firstGroup.where((item) => fullyVisible(item.label)).last.label;
    await key(LogicalKeyboardKey.pageDown);
    expect(active, firstPageTail);
    expect(fullyVisible(active), isTrue);
    await key(LogicalKeyboardKey.pageDown);
    expect(active.compareTo(firstPageTail), greaterThan(0));
    expect(fullyVisible(active), isTrue);
    final pageTail = active;

    await key(LogicalKeyboardKey.pageUp);
    expect(active.compareTo(pageTail), lessThan(0));
    expect(fullyVisible(active), isTrue);

    await key(LogicalKeyboardKey.end, control: true);
    expect(active, 'Item 40');
    expect(fullyVisible(active), isTrue);
    await key(LogicalKeyboardKey.pageDown);
    expect(active, 'Item 40', reason: 'the trailing heading is skipped');
    await key(LogicalKeyboardKey.home, control: true);
    expect(active, 'Item 01');
    expect(fullyVisible(active), isTrue);
    await key(LogicalKeyboardKey.pageUp);
    expect(active, 'Item 01');
    final editor = find.descendant(
        of: _inputFinder(), matching: find.byType(EditableText));
    expect(
        tester.widget<EditableText>(editor).focusNode.hasPrimaryFocus, isTrue);

    await key(LogicalKeyboardKey.end, control: true);
    await key(LogicalKeyboardKey.enter);
    expect(accepted, ['Item 40']);
    expect(find.byKey(const ValueKey('quick-input')), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('a pending page resolves before accept or yields to a new query',
      (tester) async {
    final harness = await _pumpHarness(tester);
    final accepted = <int>[];
    var preview = -1;
    final items = [
      for (var index = 1; index <= 40; index++)
        QuickItem(
          label: 'Result $index',
          onPreview: () => preview = index,
          onRun: () async => accepted.add(index),
        ),
      QuickItem(label: 'Fresh match', onRun: () async => accepted.add(41)),
    ];

    Future<int> pageOnce() async {
      unawaited(QuickInput.show(
        harness.pickerContext,
        hint: 'Long picker',
        items: items,
      ));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      return preview;
    }

    final firstTail = await pageOnce();
    expect(firstTail, greaterThan(1));
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(accepted, hasLength(1));
    expect(accepted.single, greaterThan(firstTail));
    expect(accepted.single, lessThan(41));

    await pageOnce();
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.enterText(_inputFinder(), 'Fresh match');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(accepted, hasLength(2));
    expect(accepted.last, 41);
  });

  testWidgets('group keys reveal distant groups and use filtered boundaries',
      (tester) async {
    final harness = await _pumpHarness(tester);
    final runs = <int>[];
    var active = 0;
    final modifier = defaultTargetPlatform == TargetPlatform.macOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.altLeft;

    QuickItem item(int i) => QuickItem(
          label: 'Choice $i',
          detail: i.isEven ? 'Two-line item' : null,
          onPreview: () => active = i,
          onRun: () async => runs.add(i),
        );

    unawaited(
        QuickInput.show(harness.pickerContext, hint: 'Grouped results', items: [
      const QuickItem(label: 'First section', kind: QuickItemKind.separator),
      for (var i = 1; i <= 32; i++) item(i),
      const QuickItem(label: 'Empty section', kind: QuickItemKind.separator),
      const QuickItem(label: 'Second section', kind: QuickItemKind.separator),
      for (var i = 33; i <= 40; i++) item(i),
      const QuickItem(label: 'Trailing heading', kind: QuickItemKind.separator),
    ]));
    await tester.pumpAndSettle();

    Future<void> jump({
      required bool down,
      bool explicitGroup = false,
    }) async {
      if (explicitGroup) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      }
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(
          down ? LogicalKeyboardKey.arrowDown : LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(modifier);
      if (explicitGroup) {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      }
      await tester.pumpAndSettle();
    }

    void expectItem(int number) {
      expect(active, number);
      expect(find.byKey(ValueKey('qi-Choice $number')).hitTestable(),
          findsOneWidget);
    }

    expectItem(1);
    expect(find.byKey(const ValueKey('qi-Choice 33')), findsNothing);
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(
      location: tester.getCenter(find.byKey(const ValueKey('qi-Choice 1'))),
    );
    addTearDown(pointer.removePointer);
    await tester.pump();
    await jump(down: true);
    expectItem(33);
    await jump(down: true);
    expectItem(1);
    await jump(down: false);
    expectItem(33);
    await pointer.moveTo(
      tester.getCenter(find.byKey(const ValueKey('qi-Choice 34'))),
    );
    await tester.pumpAndSettle();
    expectItem(34);
    await jump(down: false);
    expectItem(33);
    await jump(down: false);
    expectItem(1);
    await jump(down: true, explicitGroup: true);
    expectItem(33);

    await tester.enterText(_inputFinder(), 'Choice');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('qi-separator-Second section')),
        findsNothing);
    expectItem(1);
    await jump(down: true);
    expectItem(40);
    await jump(down: true);
    expectItem(1);
    await jump(down: false);
    expectItem(1);
    final input = find.descendant(
        of: _inputFinder(), matching: find.byType(EditableText));
    expect(
        tester.widget<EditableText>(input).focusNode.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(runs, [1]);
  },
      variant: const TargetPlatformVariant({
        TargetPlatform.windows,
        TargetPlatform.macOS,
      }));

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

  testWidgets('picker viewport resizes and item buttons keep compact rows',
      (tester) async {
    tester.view.devicePixelRatio = 1.25;
    tester.view.physicalSize = const Size(995, 734);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = await _pumpHarness(tester);
    var buttonCalls = 0;
    unawaited(QuickInput.show(
      harness.pickerContext,
      hint: 'Layered picker',
      canSelectMany: true,
      items: [
        QuickItem(
          label: 'Plain row',
          picked: true,
          buttons: [
            QuickItemButton(
              icon: Icons.push_pin,
              tooltip: 'Pin item',
              onRun: () async => buttonCalls++,
            ),
          ],
        ),
        const QuickItem(label: 'Detail row', detail: 'Additional detail'),
        for (var i = 0; i < 35; i++) QuickItem(label: 'Item $i'),
      ],
    ));
    await tester.pumpAndSettle();

    final panel = find.byKey(const ValueKey('quick-input'));
    final viewport =
        find.descendant(of: panel, matching: find.byType(ListView));
    final plain = find.byKey(const ValueKey('qi-Plain row'));
    final detail = find.byKey(const ValueKey('qi-Detail row'));
    expect(tester.getSize(viewport).width, closeTo(493.52, 0.5));
    expect(tester.getSize(viewport).height, 233);
    expect(tester.getSize(plain).height, 22);
    expect(tester.getSize(detail).height, 44);
    expect(find.byKey(const ValueKey('qi-check-Plain row')), findsOneWidget);
    expect(find.byKey(const ValueKey('qi-button-Plain row-0')), findsOneWidget);

    tester.view.physicalSize = const Size(1112, 1042);
    await tester.pumpAndSettle();
    expect(tester.getSize(viewport).width, closeTo(551.55, 0.5));
    expect(tester.getSize(viewport).height, 321);
    expect(tester.getSize(plain).height, 22);
    expect(tester.getSize(detail).height, 44);
    final input = find.descendant(
        of: _inputFinder(), matching: find.byType(EditableText));
    expect(
        tester.widget<EditableText>(input).focusNode.hasPrimaryFocus, isTrue);

    final dispatcher = tester.platformDispatcher;
    addTearDown(dispatcher.clearTextScaleFactorTestValue);
    dispatcher.textScaleFactorTestValue = 2;
    await tester.pumpAndSettle();
    expect(tester.getSize(plain).height, greaterThan(22));
    expect(tester.getSize(detail).height, greaterThan(44));
    expect(
        tester.widget<EditableText>(input).focusNode.hasPrimaryFocus, isTrue);
    dispatcher.clearTextScaleFactorTestValue();
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(tester.getSize(plain).height, 22);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(buttonCalls, 1);
    expect(find.byKey(const ValueKey('quick-input')), findsNothing);
    expect(tester.takeException(), isNull);
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
