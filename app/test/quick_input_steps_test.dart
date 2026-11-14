import 'dart:async';
import 'dart:io';

import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/quick_input.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

late Directory temp;
late LayoutStore layoutStore;
late SessionStore sessionStore;

void main() {
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('alula_quick_input');
    final root = temp.path.replaceAll(r'\', '/');
    layoutStore = LayoutStore(path: '$root/layout.json');
    sessionStore = SessionStore(path: '$root/session.json');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  group('QuickInput steps', () {
    testWidgets('back arrow returns to the previous step and keeps its input',
        (tester) async {
      final harness = await _pumpHarness(tester);
      final anchor = harness.anchorFocus;
      anchor.requestFocus();
      await tester.pump();
      expect(anchor.hasFocus, isTrue);

      // 多步 flow：第一步捕获流程外焦点并透传给第二步，第二步返回第一步。
      final restore = QuickInput.externalFocus();
      expect(restore, same(anchor));
      var backCount = 0;

      void showFirstStep() {
        unawaited(QuickInput.show(
          harness.pickerContext,
          hint: '选择要移动的视图',
          restoreFocus: restore,
          items: [
            QuickItem(label: '资源管理器', onRun: () async {}),
          ],
        ));
      }

      unawaited(QuickInput.show(
        harness.pickerContext,
        hint: '选择视图的新侧栏位置',
        restoreFocus: restore,
        onBack: () {
          backCount += 1;
          showFirstStep();
        },
        items: [
          QuickItem(label: '主侧栏', onRun: () async {}),
        ],
      ));
      await tester.pumpAndSettle();
      expect(_hintOf(tester), '选择视图的新侧栏位置');
      expect(find.byKey(const ValueKey('quick-input-back')), findsOneWidget,
          reason: '提供 onBack 时过滤行头部渲染返回箭头');

      await tester.tap(find.byKey(const ValueKey('quick-input-back')));
      await tester.pumpAndSettle();
      expect(backCount, 1);
      expect(_hintOf(tester), '选择要移动的视图');
      expect(find.byKey(const ValueKey('quick-input-back')), findsNothing,
          reason: '第一步没有上一步可返回');
      expect(_inputHasFocus(tester), isTrue, reason: '返回只切换步骤，焦点留在重新显示的面板输入框');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(anchor.hasFocus, isTrue, reason: '取消后回到整个 flow 之前的焦点节点');
    });

    testWidgets('item buttons run their own action instead of the item',
        (tester) async {
      final harness = await _pumpHarness(tester);
      var itemRuns = 0;
      var buttonRuns = 0;

      unawaited(QuickInput.show(
        harness.pickerContext,
        hint: '带按钮的候选项',
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
        ],
      ));
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('qi-button-alpha-0'));
      expect(button, findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(buttonRuns, 1);
      expect(itemRuns, 0, reason: '按钮动作不触发候选项自身的 onRun');
      expect(find.byKey(const ValueKey('quick-input')), findsNothing);
    });

    testWidgets('Escape and barrier cancel restore the previous focus',
        (tester) async {
      final harness = await _pumpHarness(tester);
      final anchor = harness.anchorFocus;

      Future<void> openPicker() async {
        await tester.pumpAndSettle();
        anchor.requestFocus();
        await tester.pump();
        unawaited(QuickInput.show(
          harness.pickerContext,
          hint: '取消我',
          items: [
            QuickItem(label: 'x', onRun: () async {}),
          ],
        ));
        await tester.pumpAndSettle();
        expect(anchor.hasFocus, isFalse);
      }

      await openPicker();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(anchor.hasFocus, isTrue, reason: 'Esc 取消后恢复先前焦点');

      await openPicker();
      await tester.tapAt(const Offset(20, 560));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quick-input')), findsNothing);
      expect(anchor.hasFocus, isTrue, reason: '点击屏障取消后恢复先前焦点');
    });

    testWidgets('running an item leaves focus to the item action',
        (tester) async {
      final harness = await _pumpHarness(tester);
      final anchor = harness.anchorFocus;
      final second = harness.secondFocus;
      anchor.requestFocus();
      await tester.pump();

      unawaited(QuickInput.show(
        harness.pickerContext,
        hint: '执行项',
        items: [
          QuickItem(
            label: 'go',
            onRun: () async => second.requestFocus(),
          ),
        ],
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('qi-go')));
      await tester.pumpAndSettle();
      expect(second.hasFocus, isTrue, reason: '执行后由候选项决定去向');
      expect(anchor.hasFocus, isFalse, reason: '执行候选项后不再把焦点拉回先前节点');
    });
  });

  testWidgets(
      'move-view flow shows the back arrow only on the destination step',
      (tester) async {
    await _mountWorkbench(tester);
    try {
      await _openMoveViewCommand(tester);
      expect(_hintOf(tester), '选择要移动的视图');
      expect(find.byKey(const ValueKey('quick-input-back')), findsNothing,
          reason: '视图选择是 flow 的第一步，没有返回箭头');

      await tester.tap(find.byKey(const ValueKey('qi-资源管理器')));
      await tester.pumpAndSettle();
      expect(_hintOf(tester), '选择视图的新侧栏位置');
      expect(find.byKey(const ValueKey('quick-input-back')), findsOneWidget);
    } finally {
      await _unmountWorkbench(tester);
    }
  });

  testWidgets('back returns to the view step with the input focused',
      (tester) async {
    await _mountWorkbench(tester);
    try {
      await _openMoveViewCommand(tester);
      await tester.tap(find.byKey(const ValueKey('qi-资源管理器')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quick-input-back')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('quick-input-back')));
      await tester.pumpAndSettle();
      expect(_hintOf(tester), '选择要移动的视图');
      expect(find.byKey(const ValueKey('quick-input-back')), findsNothing);
      expect(_inputHasFocus(tester), isTrue, reason: '返回后输入框可继续筛选视图');
    } finally {
      await _unmountWorkbench(tester);
    }
  });

  testWidgets('after going back the flow still moves another view',
      (tester) async {
    await _mountWorkbench(tester);
    try {
      await _openMoveViewCommand(tester);
      await tester.tap(find.byKey(const ValueKey('qi-资源管理器')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quick-input-back')));
      await tester.pumpAndSettle();

      await tester.enterText(_inputFinder(), '搜索');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('qi-搜索')));
      await tester.pumpAndSettle();
      expect(_hintOf(tester), '选择视图的新侧栏位置');
      await tester.tap(find.byKey(const ValueKey('qi-次侧栏')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));

      final saved = layoutStore.tryLoad()!;
      expect(
          saved.sidebarViewLocations!['search'], secondarySidebarViewLocation);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('wb-region-secondarySidebar')),
          matching: find.byKey(const ValueKey('search-input')),
        ),
        findsOneWidget,
      );
    } finally {
      await _unmountWorkbench(tester);
    }
  });
}

Finder _inputFinder() => find.descendant(
      of: find.byKey(const ValueKey('quick-input')),
      matching: find.byType(TextField),
    );

String _hintOf(WidgetTester tester) {
  final field = tester.widget<TextField>(_inputFinder());
  return field.decoration?.hintText ?? '';
}

bool _inputHasFocus(WidgetTester tester) {
  final editable = tester.widget<EditableText>(find.descendant(
    of: find.byKey(const ValueKey('quick-input')),
    matching: find.byType(EditableText),
  ));
  return editable.focusNode.hasFocus;
}

Future<void> _openMoveViewCommand(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('command-center-control')));
  await tester.pumpAndSettle();
  await tester.enterText(_inputFinder(), '移动视图');
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('qi-查看: 移动视图…')));
  await tester.pumpAndSettle();
}

Future<void> _mountWorkbench(WidgetTester tester) async {
  await tester.pumpWidget(AlulaApp(
    layoutStore: layoutStore,
    sessionStore: sessionStore,
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _unmountWorkbench(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

class _Harness {
  _Harness(this.state, this.pickerContext);

  final _PickerHarnessState state;
  final BuildContext pickerContext;

  FocusNode get anchorFocus => state.anchorFocus;
  FocusNode get secondFocus => state.secondFocus;
}

Future<_Harness> _pumpHarness(WidgetTester tester) async {
  final key = GlobalKey<_PickerHarnessState>();
  await tester.pumpWidget(_PickerHarness(key: key));
  await tester.pump();
  final state = key.currentState!;
  return _Harness(
    state,
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
  final secondFocus = FocusNode(debugLabel: 'second');

  @override
  void dispose() {
    anchorFocus.dispose();
    secondFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                key: const ValueKey('anchor-button'),
                focusNode: anchorFocus,
                onPressed: () {},
                child: const Text('anchor'),
              ),
              TextButton(
                key: const ValueKey('second-button'),
                focusNode: secondFocus,
                onPressed: () {},
                child: const Text('second'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
