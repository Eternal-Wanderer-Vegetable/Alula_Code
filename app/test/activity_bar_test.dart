import 'dart:ui' show CheckedState, SemanticsAction, Tristate;

import 'package:alula_app/workbench/activity_bar.dart';
import 'package:alula_app/workbench/activity_bar_badges.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
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

  testWidgets('Accounts and Manage are ordered global actions in both axes',
      (tester) async {
    final semantics = tester.ensureSemantics();
    for (final axis in [Axis.vertical, Axis.horizontal]) {
      await tester.pumpWidget(_activityBarApp(
        activeView: 'explorer',
        sidebarCollapsed: false,
        axis: axis,
        onManageCommand: (_) {},
      ));

      final accounts = tester.getRect(find.byTooltip('Accounts'));
      final manage = tester.getRect(find.byTooltip('Manage'));
      if (axis == Axis.vertical) {
        expect(accounts.top, lessThan(manage.top));
      } else {
        expect(accounts.left, lessThan(manage.left));
      }
      _expectButtonSemantics(tester, 'Accounts', selected: false);
      _expectButtonSemantics(tester, 'Manage', selected: false);
    }
    semantics.dispose();
  });

  testWidgets('Accounts announces the honest empty provider state',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_activityBarApp(
      activeView: 'explorer',
      sidebarCollapsed: false,
    ));

    await tester.tap(find.byTooltip('Accounts'));
    await tester.pumpAndSettle();
    expect(find.text('暂无可用帐户提供程序'), findsOneWidget);
    final node = tester.getSemantics(find.bySemanticsLabel('Accounts'));
    expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    semantics.dispose();
  });

  testWidgets('Accounts context Hide and bar checklist Show update visibility',
      (tester) async {
    var accountsVisible = true;
    final visibilityChanges = <bool>[];
    Future<void> mount() => tester.pumpWidget(_activityBarApp(
          activeView: 'explorer',
          sidebarCollapsed: false,
          accountsVisible: accountsVisible,
          onAccountsVisibilityChanged: (visible) {
            accountsVisible = visible;
            visibilityChanges.add(visible);
          },
        ));

    await mount();
    await tester.tapAt(
      tester.getCenter(find.byTooltip('Accounts')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('activity-bar-accounts-hide')));
    await tester.pumpAndSettle();
    expect(visibilityChanges, [false]);

    await mount();
    expect(find.byTooltip('Accounts'), findsNothing);
    final bar = tester.getRect(find.byType(ActivityBar));
    await tester.tapAt(
      Offset(bar.center.dx, bar.top + 220),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    final checklist =
        find.byKey(const ValueKey('activity-bar-checklist-accounts'));
    expect(
        tester.widget<MenuItemButton>(checklist).leadingIcon, isA<SizedBox>());
    expect(
      tester
          .getSemantics(find.text('Accounts'))
          .getSemanticsData()
          .flagsCollection
          .isChecked,
      CheckedState.isFalse,
    );
    await tester.tap(checklist);
    await tester.pumpAndSettle();
    expect(visibilityChanges, [false, true]);

    await mount();
    expect(find.byTooltip('Accounts'), findsOneWidget);
  });

  testWidgets('Manage keyboard navigation opens actionable commands',
      (tester) async {
    final commands = <String>[];
    await tester.pumpWidget(_activityBarApp(
      activeView: 'explorer',
      sidebarCollapsed: false,
      onManageCommand: commands.add,
    ));

    final accountsFocus = _actionFocusNode(tester, 'Accounts');
    final manageFocus = _actionFocusNode(tester, 'Manage');
    accountsFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(manageFocus.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(manageFocus.hasFocus, isTrue,
        reason: 'global action navigation does not loop');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('activity-bar-manage-command-palette')),
        findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('activity-bar-manage-command-palette')),
    );
    await tester.pumpAndSettle();
    expect(commands, ['view.commandPalette']);
  });

  testWidgets('number, icon and progress badges render in both orientations',
      (tester) async {
    final badges = {
      'explorer': const ActivityBarBadge.number(
        value: 12,
        description: '12 file errors',
      ),
      'search': const ActivityBarBadge.icon(
        icon: Icons.warning_amber_outlined,
        description: 'Search needs attention',
      ),
      'git': const ActivityBarBadge.progress(description: 'Sync in progress'),
      'outline': const ActivityBarBadge.number(
        value: 0,
        description: 'No outline notices',
      ),
    };
    final semantics = tester.ensureSemantics();

    for (final axis in [Axis.vertical, Axis.horizontal]) {
      await tester.pumpWidget(_activityBarApp(
        activeView: 'explorer',
        sidebarCollapsed: false,
        axis: axis,
        badges: badges,
      ));

      expect(find.text('12'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('No outline notices'), findsNothing);
      expect(find.byTooltip('资源管理器, 12 file errors'), findsOneWidget);
      final semanticsNode = tester.getSemantics(
        find.bySemanticsLabel('资源管理器, 12 file errors'),
      );
      expect(semanticsNode.label, '资源管理器, 12 file errors');
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('搜索, Search needs attention'))
            .label,
        '搜索, Search needs attention',
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('源代码管理, Sync in progress'))
            .label,
        '源代码管理, Sync in progress',
      );
    }

    semantics.dispose();
  });

  testWidgets('item menu independently hides and restores its provider badge',
      (tester) async {
    final badges = {
      'search': const ActivityBarBadge.number(
        value: 4,
        description: '4 search results',
      ),
      'git': const ActivityBarBadge.number(
        value: 2,
        description: '2 changes',
      ),
    };
    var disabled = <String>[];
    final updates = <List<String>>[];

    Future<void> mount() => tester.pumpWidget(_activityBarApp(
          activeView: 'explorer',
          sidebarCollapsed: false,
          badges: badges,
          badgeDisabledViews: disabled,
          onBadgeDisabledViewsChanged: (value) {
            disabled = value;
            updates.add(value);
          },
        ));

    await mount();
    await tester.tapAt(
      tester.getCenter(find.byTooltip('搜索, 4 search results')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('activity-bar-item-badge-search')));
    await tester.pumpAndSettle();

    expect(updates, [
      ['search']
    ]);
    await mount();
    expect(find.text('4'), findsNothing);
    expect(find.text('2'), findsOneWidget,
        reason: 'another view keeps its badge visible');

    await tester.tapAt(
      tester.getCenter(find.byTooltip('搜索')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('Show Badge'), findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('activity-bar-item-badge-search')));
    await tester.pumpAndSettle();

    expect(updates, [
      ['search'],
      []
    ]);
    await mount();
    expect(find.text('4'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  test('badge number labels suppress zero and compact large counts', () {
    expect(
      const ActivityBarBadge.number(value: 0, description: 'none').numberText,
      isNull,
    );
    expect(
      const ActivityBarBadge.number(value: 9, description: 'nine').numberText,
      '9',
    );
    expect(
      const ActivityBarBadge.number(value: 1200, description: 'many')
          .numberText,
      '1K+',
    );
  });

  testWidgets('side Default and Compact use their fixed item and icon sizes',
      (tester) async {
    await tester.pumpWidget(_activityBarApp(
      activeView: 'explorer',
      sidebarCollapsed: false,
    ));
    var item = find.descendant(
      of: find.byTooltip('资源管理器'),
      matching: find.byType(InkWell),
    );
    expect(tester.getSize(item), const Size(48, 48));
    expect(
      tester
          .widget<Icon>(find.descendant(
            of: find.byTooltip('资源管理器'),
            matching: find.byType(Icon),
          ))
          .size,
      24,
    );

    await tester.pumpWidget(_activityBarApp(
      activeView: 'explorer',
      sidebarCollapsed: false,
      size: ActivityBarSize.compact,
    ));
    item = find.descendant(
      of: find.byTooltip('资源管理器'),
      matching: find.byType(InkWell),
    );
    expect(tester.getSize(item), const Size(36, 28));
    expect(
      tester
          .widget<Icon>(find.descendant(
            of: find.byTooltip('资源管理器'),
            matching: find.byType(Icon),
          ))
          .size,
      16,
    );
  });

  testWidgets('right-click opens a checked size submenu only on Side',
      (tester) async {
    final selectedSizes = <ActivityBarSize>[];
    Future<void> openSizeMenu() async {
      final bar = tester.getRect(find.byType(ActivityBar));
      await tester.tapAt(
        Offset(bar.center.dx, bar.top + 220),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activity Bar Size'));
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(_activityBarApp(
      activeView: 'explorer',
      sidebarCollapsed: false,
      onSizeChanged: selectedSizes.add,
    ));
    await openSizeMenu();
    expect(
      tester
          .widget<MenuItemButton>(
            find.byKey(const ValueKey('activity-bar-size-default')),
          )
          .leadingIcon,
      isA<Icon>(),
    );
    expect(
      tester
          .widget<MenuItemButton>(
            find.byKey(const ValueKey('activity-bar-size-compact')),
          )
          .leadingIcon,
      isA<SizedBox>(),
    );
    await tester.tap(find.byKey(const ValueKey('activity-bar-size-compact')));
    await tester.pumpAndSettle();
    expect(selectedSizes, [ActivityBarSize.compact]);

    await tester.pumpWidget(_activityBarApp(
      activeView: 'explorer',
      sidebarCollapsed: false,
      size: ActivityBarSize.compact,
      onSizeChanged: selectedSizes.add,
    ));
    await openSizeMenu();
    expect(
      tester
          .widget<MenuItemButton>(
            find.byKey(const ValueKey('activity-bar-size-default')),
          )
          .leadingIcon,
      isA<SizedBox>(),
    );
    expect(
      tester
          .widget<MenuItemButton>(
            find.byKey(const ValueKey('activity-bar-size-compact')),
          )
          .leadingIcon,
      isA<Icon>(),
    );
    await tester.tapAt(const Offset(700, 500));
    await tester.pumpAndSettle();

    await tester.pumpWidget(_activityBarApp(
      activeView: 'explorer',
      sidebarCollapsed: false,
      axis: Axis.horizontal,
      size: ActivityBarSize.compact,
      onSizeChanged: selectedSizes.add,
    ));
    await tester.tapAt(
      tester.getCenter(find.byType(ActivityBar)),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('Activity Bar Size'), findsNothing);
  });

  testWidgets(
      'view item menu hides and keeps; active unpinned view stays until switch',
      (tester) async {
    final pinChanges = <List<String>>[];
    await tester.pumpWidget(_activityBarApp(
      activeView: 'search',
      sidebarCollapsed: false,
      onPinnedViewsChanged: pinChanges.add,
    ));

    await tester.tapAt(
      tester.getCenter(find.byTooltip('搜索')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    final hideSearch =
        find.byKey(const ValueKey('activity-bar-item-pin-search'));
    expect(tester.widget<MenuItemButton>(hideSearch).onPressed, isNotNull);
    expect(find.text('Hide Search'), findsOneWidget);
    await tester.tap(hideSearch);
    await tester.pumpAndSettle();
    expect(find.text('Hide Search'), findsNothing,
        reason: 'the item context menu closes after its action');
    expect(pinChanges, [
      ['explorer', 'outline', 'git'],
    ]);

    await tester.pumpWidget(_activityBarApp(
      activeView: 'search',
      sidebarCollapsed: false,
      pinnedViews: pinChanges.last,
      onPinnedViewsChanged: pinChanges.add,
    ));
    expect(find.byTooltip('搜索'), findsOneWidget,
        reason: 'an active but unpinned view stays visible');

    await tester.pumpWidget(_activityBarApp(
      activeView: 'explorer',
      sidebarCollapsed: false,
      pinnedViews: pinChanges.last,
      onPinnedViewsChanged: pinChanges.add,
    ));
    expect(find.byTooltip('搜索'), findsNothing,
        reason: 'switching to another view hides the unpinned view');
    expect(find.byTooltip('Manage'), findsOneWidget,
        reason: 'Manage remains fixed in the bar');
  });

  testWidgets('bar checklist syncs pin state and refuses to hide the last view',
      (tester) async {
    final pinChanges = <List<String>>[];
    Future<void> openBarChecklist() async {
      final bar = tester.getRect(find.byType(ActivityBar));
      await tester.tapAt(
        Offset(bar.center.dx, bar.top + 220),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(_activityBarApp(
      activeView: 'explorer',
      sidebarCollapsed: false,
      onPinnedViewsChanged: pinChanges.add,
    ));
    await openBarChecklist();
    final searchChecklist =
        find.byKey(const ValueKey('activity-bar-checklist-search'));
    expect(
      tester.widget<MenuItemButton>(searchChecklist).leadingIcon,
      isA<Icon>(),
    );
    expect(
      tester
          .getSemantics(find.text('Search'))
          .getSemanticsData()
          .flagsCollection
          .isChecked,
      CheckedState.isTrue,
    );
    await tester.tap(searchChecklist);
    await tester.pumpAndSettle();
    expect(searchChecklist, findsNothing,
        reason: 'the Activity Bar checklist closes after its action');
    expect(pinChanges.single, ['explorer', 'outline', 'git']);

    await tester.pumpWidget(_activityBarApp(
      activeView: 'explorer',
      sidebarCollapsed: false,
      pinnedViews: pinChanges.single,
      onPinnedViewsChanged: pinChanges.add,
    ));
    await openBarChecklist();
    expect(
      tester.widget<MenuItemButton>(searchChecklist).leadingIcon,
      isA<SizedBox>(),
    );
    expect(
      tester
          .getSemantics(find.text('Search'))
          .getSemanticsData()
          .flagsCollection
          .isChecked,
      CheckedState.isFalse,
    );
    await tester.tap(searchChecklist);
    await tester.pumpAndSettle();
    expect(pinChanges.last, activityBarViewOrder);

    await tester.pumpWidget(_activityBarApp(
      activeView: 'git',
      sidebarCollapsed: false,
      pinnedViews: const ['git'],
      onPinnedViewsChanged: pinChanges.add,
    ));
    await openBarChecklist();
    final lastPinned = find.byKey(const ValueKey('activity-bar-checklist-git'));
    expect(tester.widget<MenuItemButton>(lastPinned).onPressed, isNull);
    expect(find.text('Manage'), findsNothing);
    expect(
      find.byKey(const ValueKey('activity-bar-checklist-manage')),
      findsNothing,
    );
    await tester.tapAt(const Offset(700, 500));
    await tester.pumpAndSettle();

    await tester.tapAt(
      tester.getCenter(find.byTooltip('源代码管理')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    final hideLast = find.byKey(const ValueKey('activity-bar-item-pin-git'));
    expect(tester.widget<MenuItemButton>(hideLast).onPressed, isNull);
    expect(find.text('Hide Source Control'), findsOneWidget);
    expect(pinChanges, hasLength(2));
  });

  testWidgets('keeping a view restores custom-order keyboard traversal',
      (tester) async {
    const order = ['git', 'search', 'explorer', 'outline'];
    final pinChanges = <List<String>>[];
    await tester.pumpWidget(_activityBarApp(
      activeView: 'explorer',
      sidebarCollapsed: false,
      order: order,
      pinnedViews: const ['git', 'explorer'],
      onPinnedViewsChanged: pinChanges.add,
    ));

    final bar = tester.getRect(find.byType(ActivityBar));
    await tester.tapAt(
      Offset(bar.center.dx, bar.top + 220),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    final keepSearch =
        find.byKey(const ValueKey('activity-bar-checklist-search'));
    expect(
        tester.widget<MenuItemButton>(keepSearch).leadingIcon, isA<SizedBox>());
    await tester.tap(keepSearch);
    await tester.pumpAndSettle();
    expect(pinChanges.single, ['git', 'search', 'explorer']);

    await tester.pumpWidget(_activityBarApp(
      activeView: 'explorer',
      sidebarCollapsed: false,
      order: order,
      pinnedViews: pinChanges.single,
      onPinnedViewsChanged: pinChanges.add,
    ));
    expect(find.byTooltip('大纲'), findsNothing);

    final focusNodes = [
      _viewFocusNode(tester, '源代码管理'),
      _viewFocusNode(tester, '搜索'),
      _viewFocusNode(tester, '资源管理器'),
    ];
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focusNodes[0].hasFocus, isTrue,
        reason: 'Source Control remains first in the customized order');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focusNodes[1].hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focusNodes[2].hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focusNodes[2].hasFocus, isTrue,
        reason: 'focus stops at the final pinned view');
  });

  testWidgets('Top Activity Bar exposes the view checklist without size menu',
      (tester) async {
    await tester.pumpWidget(_activityBarApp(
      activeView: 'explorer',
      sidebarCollapsed: false,
      axis: Axis.horizontal,
      onPinnedViewsChanged: (_) {},
    ));
    final bar = tester.getRect(find.byType(ActivityBar));
    await tester.tapAt(
      Offset(bar.left + 2, bar.center.dy),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('activity-bar-checklist-search')),
        findsOneWidget);
    expect(find.text('Activity Bar Size'), findsNothing);
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

  testWidgets('vertical drag moves a view after its target in order',
      (tester) async {
    final orders = <List<String>>[];
    await tester.pumpWidget(_activityBarApp(
      activeView: 'explorer',
      sidebarCollapsed: false,
      onOrderChanged: orders.add,
    ));

    final source = tester.getRect(find.byTooltip('资源管理器'));
    final target = tester.getRect(find.byTooltip('大纲'));
    await tester.dragFrom(
      source.center,
      Offset(0, target.bottom - 3 - source.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(orders, [
      ['search', 'outline', 'explorer', 'git'],
    ]);

    final sameItem = tester.getRect(find.byTooltip('大纲'));
    await tester.dragFrom(
      sameItem.center,
      const Offset(0, 20),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(orders, hasLength(1),
        reason: 'dropping on the same view is a no-op');
  });

  testWidgets('horizontal drag moves a view before target; Manage stays fixed',
      (tester) async {
    final orders = <List<String>>[];
    await tester.pumpWidget(_activityBarApp(
      activeView: 'search',
      sidebarCollapsed: false,
      axis: Axis.horizontal,
      onOrderChanged: orders.add,
    ));

    final source = tester.getRect(find.byTooltip('源代码管理'));
    final target = tester.getRect(find.byTooltip('资源管理器'));
    await tester.dragFrom(
      source.center,
      Offset(target.left + 4 - source.center.dx, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(orders, [
      ['git', 'explorer', 'search', 'outline'],
    ]);

    await tester.dragFrom(
      tester.getCenter(find.byTooltip('大纲')),
      Offset(
        tester.getCenter(find.byTooltip('Manage')).dx -
            tester.getCenter(find.byTooltip('大纲')).dx,
        0,
      ),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(orders, hasLength(1), reason: 'Manage is not a drop target');
  });

  testWidgets('custom order drives horizontal keyboard focus by view ID',
      (tester) async {
    final selected = <String>[];
    await tester.pumpWidget(_activityBarApp(
      activeView: 'search',
      sidebarCollapsed: false,
      axis: Axis.horizontal,
      order: const ['git', 'explorer', 'search', 'outline'],
      onSelectView: selected.add,
      onOrderChanged: (_) {},
    ));

    final focusNodes = _viewFocusNodes(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focusNodes[3].hasFocus, isTrue,
        reason: 'Git is the first view in the custom order');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(focusNodes[0].hasFocus, isTrue,
        reason: 'Explorer follows Git by ID, not its default focus index');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selected, ['explorer']);
  });
}

Widget _activityBarApp({
  required String activeView,
  required bool sidebarCollapsed,
  Axis axis = Axis.vertical,
  ActivityBarSize size = ActivityBarSize.defaultSize,
  List<String> order = activityBarViewOrder,
  List<String> pinnedViews = activityBarViewOrder,
  Map<String, ActivityBarBadge> badges = const {},
  List<String> badgeDisabledViews = const [],
  bool accountsVisible = true,
  ValueChanged<String>? onSelectView,
  ValueChanged<ActivityBarSize>? onSizeChanged,
  ValueChanged<List<String>>? onOrderChanged,
  ValueChanged<List<String>>? onPinnedViewsChanged,
  ValueChanged<List<String>>? onBadgeDisabledViewsChanged,
  ValueChanged<bool>? onAccountsVisibilityChanged,
  ValueChanged<String>? onManageCommand,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: axis == Axis.horizontal ? 400 : size.sideExtent,
        height: axis == Axis.horizontal ? 44 : 320,
        child: ActivityBar(
          activeView: activeView,
          sidebarCollapsed: sidebarCollapsed,
          axis: axis,
          size: size,
          order: order,
          pinnedViews: pinnedViews,
          badges: badges,
          badgeDisabledViews: badgeDisabledViews,
          accountsVisible: accountsVisible,
          onSelectView: onSelectView ?? (_) {},
          onSizeChanged: onSizeChanged,
          onOrderChanged: onOrderChanged,
          onPinnedViewsChanged: onPinnedViewsChanged,
          onBadgeDisabledViewsChanged: onBadgeDisabledViewsChanged,
          onAccountsVisibilityChanged: onAccountsVisibilityChanged,
          onManageCommand: onManageCommand,
        ),
      ),
    ),
  );
}

FocusNode _actionFocusNode(WidgetTester tester, String tooltipLabel) {
  final item = find.descendant(
    of: find.byTooltip(tooltipLabel),
    matching: find.byType(InkWell),
  );
  return tester.widget<InkWell>(item).focusNode!;
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

FocusNode _viewFocusNode(WidgetTester tester, String label) {
  final tooltip = find.descendant(
    of: find.byType(ActivityBar),
    matching: find.byWidgetPredicate(
      (widget) => widget is Tooltip && widget.message == label,
    ),
  );
  final item = find.descendant(of: tooltip, matching: find.byType(InkWell));
  return tester.widget<InkWell>(item).focusNode!;
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
