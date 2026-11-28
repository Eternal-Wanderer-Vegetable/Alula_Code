import 'dart:async';
import 'dart:io';

import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/notifications.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

late Directory temp;
late LayoutStore layoutStore;
late SessionStore sessionStore;
late NotificationCenter notifications;

void main() {
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('alula_notification_progress');
    final root = temp.path.replaceAll(r'\', '/');
    layoutStore = LayoutStore(path: '$root/layout.json');
    sessionStore = SessionStore(path: '$root/session.json');
    notifications = NotificationCenter();
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  testWidgets('toast close is available only after progress completes',
      (tester) async {
    await _mountApp(tester);
    try {
      var cancels = 0;
      final progress = NotificationProgress(
        total: 4,
        worked: 1,
        onCancel: () async => cancels += 1,
      );
      addTearDown(progress.dispose);
      final notification = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: '正在索引工作区',
        source: 'Search',
        progress: progress,
      );
      await tester.pump();
      expect(
          find.byKey(const ValueKey('notification-toast-1')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('notification-progress-percent-1')),
        findsOneWidget,
      );
      expect(find.text('25%'), findsOneWidget);
      final close = find.byKey(const ValueKey('notification-toast-close-1'));
      expect(close, findsNothing);
      expect(find.byKey(const ValueKey('notification-toast-cancel-1')),
          findsOneWidget);

      progress.report(worked: 3);
      await tester.pump();
      expect(find.text('75%'), findsOneWidget, reason: '进度条监听器直接重建 toast');
      expect(close, findsNothing);

      progress.done();
      await tester.pump();
      expect(find.byKey(const ValueKey('notification-toast-1')), findsOneWidget,
          reason: 'completion hides progress but retains the notification');
      expect(
          find.byKey(const ValueKey('notification-progress-1')), findsNothing);
      expect(find.byKey(const ValueKey('notification-toast-cancel-1')),
          findsNothing);
      expect(close, findsOneWidget);

      await tester.tap(close);
      await tester.pump();
      expect(find.byKey(const ValueKey('notification-toast-1')), findsNothing);
      expect(notifications.items, [notification]);
      expect(notifications.unreadCount, 1);
      expect(cancels, 0);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('cancel action disables while cancellation is pending',
      (tester) async {
    await _mountApp(tester);
    final finishCancellation = Completer<void>();
    var cancels = 0;
    final progress = NotificationProgress(
      total: 5,
      onCancel: () {
        cancels++;
        return finishCancellation.future;
      },
    );
    notifications.notify(
      severity: WorkbenchNotificationSeverity.info,
      message: '正在同步',
      progress: progress,
    );
    await tester.pump();

    final cancel = find.byKey(const ValueKey('notification-toast-cancel-1'));
    await tester.tap(cancel);
    await tester.pump();
    expect(cancels, 1);
    expect(find.text('正在取消…'), findsOneWidget);
    expect(tester.widget<TextButton>(cancel).onPressed, isNull);

    finishCancellation.complete();
    await tester.pump();
    expect(tester.widget<TextButton>(cancel).onPressed, isNotNull);
    await _unmountApp(tester);
  });

  testWidgets('center close appears after progress without affecting banners',
      (tester) async {
    await _mountApp(tester);
    try {
      final progress = NotificationProgress(total: 10, worked: 2);
      addTearDown(progress.dispose);
      final notification = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: '正在下载语言服务',
        progress: progress,
      );
      notifications.notify(
        severity: WorkbenchNotificationSeverity.warning,
        message: '需要信任此工作区',
        banner: true,
        actions: [
          WorkbenchNotificationAction(label: '管理信任', run: () async {}),
        ],
      );
      await tester.pump();

      final banner = find.byKey(const ValueKey('notification-banner-2'));
      expect(banner, findsOneWidget);
      expect(
        tester.getTopLeft(banner).dy,
        lessThan(tester
            .getTopLeft(find.byKey(const ValueKey('wb-region-editor')))
            .dy),
        reason: 'banner 位于编辑器网格上方',
      );
      expect(find.text('需要信任此工作区'), findsOneWidget);
      expect(find.byKey(const ValueKey('notification-banner-action-2-0')),
          findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('status-notifications')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('notification-progress-1')),
        findsOneWidget,
        reason: '中心条目同样展示进度条',
      );
      expect(find.text('20%'), findsOneWidget);
      final close = find.byKey(const ValueKey('notification-dismiss-1'));
      expect(close, findsNothing);
      expect(
          find.byKey(const ValueKey('notification-dismiss-2')), findsOneWidget);

      progress.done();
      await tester.pump();
      expect(
          find.byKey(const ValueKey('notification-progress-1')), findsNothing);
      expect(notifications.byId(notification.id), same(notification));
      expect(close, findsOneWidget);

      await tester.tap(close);
      await tester.pump();
      expect(find.byKey(const ValueKey('notification-item-1')), findsNothing);
      expect(notifications.byId(notification.id), isNull);
      expect(banner, findsOneWidget);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('banner closes, and zen mode hides the banner layer',
      (tester) async {
    await _mountApp(tester);
    try {
      notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: '横幅通知',
        banner: true,
      );
      await tester.pump();
      final banner = find.byKey(const ValueKey('notification-banner-1'));
      expect(banner, findsOneWidget);

      await tester
          .tap(find.byKey(const ValueKey('notification-banner-close-1')));
      await tester.pump();
      expect(banner, findsNothing);
      expect(notifications.banners, isEmpty);

      notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: '再次出现的横幅',
        banner: true,
      );
      await tester.pump();
      expect(
          find.byKey(const ValueKey('notification-banner-2')), findsOneWidget);

      await _runPaletteCommand(tester, '禅模式', '查看: 切换禅模式');
      expect(find.byKey(const ValueKey('notification-banner-2')), findsNothing,
          reason: 'zen 模式隐藏编辑器区上方的 banner 层');
    } finally {
      await _unmountApp(tester);
    }
  });
}

Future<void> _runPaletteCommand(
    WidgetTester tester, String query, String key) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.f1);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(
      of: find.byKey(const ValueKey('quick-input')),
      matching: find.byType(TextField),
    ),
    query,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('qi-$key')));
  await tester.pumpAndSettle();
}

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
