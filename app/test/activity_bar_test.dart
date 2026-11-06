import 'dart:ui' show Tristate;

import 'package:alula_app/workbench/activity_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('view actions expose button and selected semantics',
      (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(_activityBarApp(
      activeView: 'search',
      sidebarCollapsed: false,
    ));

    _expectButtonSemantics(tester, '资源管理器', selected: false);
    _expectButtonSemantics(tester, '搜索', selected: true);
    _expectButtonSemantics(tester, '大纲', selected: false);
    _expectButtonSemantics(tester, '源代码管理', selected: false);

    await tester.pumpWidget(_activityBarApp(
      activeView: 'search',
      sidebarCollapsed: true,
    ));
    for (final label in ['资源管理器', '搜索', '大纲', '源代码管理']) {
      _expectButtonSemantics(tester, label, selected: false);
    }
    semantics.dispose();
  });

  testWidgets('Tab and arrow keys move focus; Enter and Space activate',
      (tester) async {
    final selected = <String>[];
    await tester.pumpWidget(_activityBarApp(
      activeView: 'explorer',
      sidebarCollapsed: false,
      onSelectView: selected.add,
    ));

    final focusNodes = _viewFocusNodes(tester);
    for (var index = 0; index < focusNodes.length; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focusNodes[index].hasFocus, isTrue,
          reason: 'Tab should follow the visible view order at index $index');
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(focusNodes[2].hasFocus, isTrue);
    expect(selected, isEmpty,
        reason: 'arrow keys move focus without activation');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focusNodes[3].hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focusNodes[3].hasFocus, isTrue,
        reason: 'Down stays at the last view instead of wrapping');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(focusNodes[2].hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(focusNodes[1].hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(focusNodes[0].hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(focusNodes[0].hasFocus, isTrue,
        reason: 'Up stays at the first view instead of wrapping');
    expect(selected, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selected, ['explorer']);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(selected, ['explorer', 'explorer']);
  });

  testWidgets('mouse click keeps the existing view selection route',
      (tester) async {
    final selected = <String>[];
    await tester.pumpWidget(_activityBarApp(
      activeView: 'explorer',
      sidebarCollapsed: false,
      onSelectView: selected.add,
    ));

    await tester.tap(find.byTooltip('搜索'));
    await tester.pump();
    expect(selected, ['search']);
  });

  testWidgets('horizontal Activity Bar follows left/right focus order',
      (tester) async {
    final selected = <String>[];
    await tester.pumpWidget(_activityBarApp(
      activeView: 'explorer',
      sidebarCollapsed: false,
      axis: Axis.horizontal,
      onSelectView: selected.add,
    ));

    final centers = ['资源管理器', '搜索', '大纲', '源代码管理']
        .map((label) => tester.getCenter(find.byTooltip(label)))
        .toList();
    expect(centers.map((point) => point.dy).toSet().length, 1);
    for (var i = 1; i < centers.length; i++) {
      expect(centers[i].dx, greaterThan(centers[i - 1].dx));
    }

    final focusNodes = _viewFocusNodes(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focusNodes.first.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focusNodes.first.hasFocus, isTrue,
        reason: 'perpendicular arrows do not move horizontal focus');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(focusNodes[1].hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(focusNodes.first.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(focusNodes.first.hasFocus, isTrue,
        reason: 'Left stays at the first view instead of wrapping');
    expect(selected, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(selected, ['explorer', 'explorer']);
  });
}

Widget _activityBarApp({
  required String activeView,
  required bool sidebarCollapsed,
  Axis axis = Axis.vertical,
  ValueChanged<String>? onSelectView,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: axis == Axis.horizontal ? 400 : 44,
        height: axis == Axis.horizontal ? 44 : 320,
        child: ActivityBar(
          activeView: activeView,
          sidebarCollapsed: sidebarCollapsed,
          axis: axis,
          onSelectView: onSelectView ?? (_) {},
        ),
      ),
    ),
  );
}

List<FocusNode> _viewFocusNodes(WidgetTester tester) {
  return [
    '资源管理器',
    '搜索',
    '大纲',
    '源代码管理',
  ].map((label) {
    final tooltip = find.byTooltip(label);
    final item = find.descendant(of: tooltip, matching: find.byType(InkWell));
    return tester.widget<InkWell>(item).focusNode!;
  }).toList();
}

void _expectButtonSemantics(
  WidgetTester tester,
  String label, {
  required bool selected,
}) {
  final node = tester.getSemantics(find.bySemanticsLabel(label));
  expect(node.label, label);
  final flags = node.getSemanticsData().flagsCollection;
  expect(flags.isButton, isTrue);
  expect(flags.isSelected, selected ? Tristate.isTrue : Tristate.isFalse);
}
