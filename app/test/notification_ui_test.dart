import 'dart:io';

import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/notifications.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

late Directory temp;
late LayoutStore layoutStore;
late SessionStore sessionStore;
late NotificationCenter notifications;

void main() {
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('alula_notifications');
    final root = temp.path.replaceAll(r'\', '/');
    layoutStore = LayoutStore(path: '$root/layout.json');
    sessionStore = SessionStore(path: '$root/session.json');
    notifications = NotificationCenter();
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  testWidgets('toast renders and closing it keeps the center entry and badge',
      (tester) async {
    await _mountApp(tester);
    try {
      notifications.notify(
        severity: WorkbenchNotificationSeverity.warning,
        message: '磁盘版本已变化',
        source: 'Alula',
      );
      await tester.pump();
      expect(
          find.byKey(const ValueKey('notification-toast-1')), findsOneWidget);
      expect(find.text('磁盘版本已变化'), findsOneWidget);
      expect(find.byKey(const ValueKey('status-notifications-badge')),
          findsOneWidget);
      expect(
        tester
            .widget<Text>(find.descendant(
              of: find.byKey(const ValueKey('status-notifications-badge')),
              matching: find.byType(Text),
            ))
            .data,
        '1',
      );

      await tester
          .tap(find.byKey(const ValueKey('notification-toast-close-1')));
      await tester.pump();
      expect(find.byKey(const ValueKey('notification-toast-1')), findsNothing);
      expect(find.byKey(const ValueKey('status-notifications-badge')),
          findsOneWidget,
          reason: '关闭 toast 不改变未读/中心条目');

      await tester.tap(find.byKey(const ValueKey('status-notifications')));
      await tester.pump();
      expect(find.byKey(const ValueKey('notification-center')), findsOneWidget);
      expect(find.byKey(const ValueKey('notification-item-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('status-notifications-badge')),
          findsNothing,
          reason: '打开中心即标记已读');
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('automatic toast expiry retains unread center notification',
      (tester) async {
    await _mountApp(tester);
    try {
      notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: '自动隐藏但保留记录',
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('notification-toast-1')), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      expect(find.byKey(const ValueKey('notification-toast-1')), findsNothing);
      expect(notifications.items, hasLength(1));
      expect(notifications.unreadCount, 1);
      expect(find.byKey(const ValueKey('status-notifications-badge')),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('status-notifications')));
      await tester.pump();
      expect(find.byKey(const ValueKey('notification-item-1')), findsOneWidget);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('do not disturb suppresses toasts but keeps entries',
      (tester) async {
    await _mountApp(tester);
    try {
      notifications.setDoNotDisturb(true);
      notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: '安静模式通知',
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('notification-toast-1')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('status-notifications')));
      await tester.pump();
      expect(find.byKey(const ValueKey('notification-item-1')), findsOneWidget);
      expect(notifications.doNotDisturb, isTrue);

      await tester.tap(find.byKey(const ValueKey('notification-dnd-toggle')));
      await tester.pump();
      expect(notifications.doNotDisturb, isFalse);
      await tester.tap(find.byKey(const ValueKey('notification-center-close')));
      await tester.pump();

      notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: '恢复后的通知',
      );
      await tester.pump();
      expect(
          find.byKey(const ValueKey('notification-toast-2')), findsOneWidget);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('actions run, source filter narrows and clear all empties',
      (tester) async {
    await _mountApp(tester);
    try {
      var actionRuns = 0;
      notifications.notify(
        severity: WorkbenchNotificationSeverity.error,
        message: '保存失败',
        source: 'Alula',
        actions: [
          WorkbenchNotificationAction(
            label: '重试',
            run: () async => actionRuns += 1,
          ),
        ],
      );
      notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: '语言服务已就绪',
        source: 'Rust',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('status-notifications')));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('notification-action-1-0')));
      await tester.pump();
      expect(actionRuns, 1);

      // 来源过滤：选 Rust 后只剩语言服务通知。
      await tester
          .tap(find.byKey(const ValueKey('notification-source-filter')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Rust').last);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('notification-item-1')), findsNothing);
      expect(find.byKey(const ValueKey('notification-item-2')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('notification-clear-all')));
      await tester.pump();
      expect(find.byKey(const ValueKey('notification-empty')), findsOneWidget);
      expect(notifications.isEmpty, isTrue);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('notification commands drive the center from the palette',
      (tester) async {
    await _mountApp(tester);
    try {
      await tester.tap(find.byKey(const ValueKey('command-center-control')));
      await tester.pumpAndSettle();
      await tester.enterText(_paletteInput(), '通知');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('qi-查看: 通知')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('notification-center')), findsOneWidget);
      expect(find.byKey(const ValueKey('notification-empty')), findsOneWidget);
    } finally {
      await _unmountApp(tester);
    }
  });
}

Finder _paletteInput() => find.descendant(
      of: find.byKey(const ValueKey('quick-input')),
      matching: find.byType(TextField),
    );

Future<void> _mountApp(WidgetTester tester) async {
  await tester.pumpWidget(AlulaApp(
    layoutStore: layoutStore,
    sessionStore: sessionStore,
    notificationCenter: notifications,
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _unmountApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}
