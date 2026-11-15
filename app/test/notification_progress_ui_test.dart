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
    temp = await Directory.systemTemp.createTemp('alula_notification_progress');
    final root = temp.path.replaceAll(r'\', '/');
    layoutStore = LayoutStore(path: '$root/layout.json');
    sessionStore = SessionStore(path: '$root/session.json');
    notifications = NotificationCenter();
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  testWidgets('toast shows determinate progress, updates and cancels',
      (tester) async {
    await _mountApp(tester);
    try {
      var cancels = 0;
      final progress = NotificationProgress(
        total: 4,
        worked: 1,
        onCancel: () async => cancels += 1,
      );
      notifications.notify(
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

      progress.report(worked: 3);
      await tester.pump();
      expect(find.text('75%'), findsOneWidget, reason: '进度条监听器直接重建 toast');

      await tester
          .tap(find.byKey(const ValueKey('notification-toast-cancel-1')));
      await tester.pump();
      expect(cancels, 1);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('center row shows progress and banner renders above the grid',
      (tester) async {
    await _mountApp(tester);
    try {
      final progress = NotificationProgress(total: 10, worked: 2);
      notifications.notify(
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
  await tester.tap(find.byKey(const ValueKey('command-center-control')));
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
