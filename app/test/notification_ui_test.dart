import 'dart:async';
import 'dart:io';

import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/notification_widgets.dart';
import 'package:alula_app/workbench/notifications.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      expect(find.byKey(const ValueKey('status-notifications-indicator')),
          findsOneWidget);
      expect(_notificationBellTooltip(tester), '1 条新通知');

      await tester
          .tap(find.byKey(const ValueKey('notification-toast-close-1')));
      await tester.pump();
      expect(find.byKey(const ValueKey('notification-toast-1')), findsNothing);
      expect(find.byKey(const ValueKey('status-notifications-indicator')),
          findsOneWidget,
          reason: '关闭 toast 不改变未读/中心条目');

      await tester.tap(find.byKey(const ValueKey('status-notifications')));
      await tester.pump();
      expect(find.byKey(const ValueKey('notification-center')), findsOneWidget);
      expect(find.byKey(const ValueKey('notification-item-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('status-notifications-indicator')),
          findsNothing,
          reason: '打开中心即标记已读');
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('notification bell describes only background progress',
      (tester) async {
    final progress = NotificationProgress(total: 5);
    addTearDown(progress.dispose);
    await _mountApp(tester);
    try {
      final badge =
          find.byKey(const ValueKey('status-notifications-indicator'));
      final beak = find.byKey(const ValueKey('status-notifications-beak'));
      expect(_notificationBellTooltip(tester), '没有通知');
      expect(badge, findsNothing);

      final pending = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Pending background job',
        progress: progress,
      );
      await tester.pump();
      expect(_notificationBellTooltip(tester), '1 条新通知');
      expect(badge, findsOneWidget);

      await _showNotificationCenter(tester);
      expect(_notificationBellTooltip(tester), '隐藏通知');
      expect(beak, findsOneWidget);
      expect(badge, findsNothing);

      await tester.tap(find.byKey(const ValueKey('notification-center-close')));
      await tester.pump();
      expect(_notificationBellTooltip(tester), '没有新通知（1 项正在进行）');
      expect(badge, findsOneWidget);
      expect(beak, findsNothing);

      progress.done();
      await tester.pump();
      expect(_notificationBellTooltip(tester), '没有新通知');
      expect(badge, findsNothing);
      expect(notifications.items, [pending]);

      notifications.setDoNotDisturb(true);
      await tester.pump();
      expect(_notificationBellTooltip(tester), '请勿打扰已启用');
      expect(badge, findsNothing);
      notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Quiet notification for the bell',
      );
      await tester.pump();
      expect(_notificationBellTooltip(tester), '请勿打扰已启用');
      expect(badge, findsOneWidget);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('shortcut and center clear button send one native signal each',
      (tester) async {
    final feedback = _ClearFeedbackProbe(tester);
    final progress = NotificationProgress(total: 5);
    addTearDown(progress.dispose);
    await _mountApp(tester);
    try {
      notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Ordinary notification',
      );
      final active = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Progress notification',
        progress: progress,
      );
      await tester.pump();
      await _showNotificationCenter(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(feedback.announcements, isEmpty);
      expect(feedback.sounds, isEmpty);
      expect(notifications.byId(active.id), same(active));

      progress.done();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(notifications.byId(active.id), isNull);
      expect(feedback.announcements, ['通知已清除']);
      expect(feedback.viewIds, [tester.view.viewId]);
      expect(feedback.sounds, ['SystemSoundType.alert']);

      await tester.tap(find.byKey(const ValueKey('notification-dismiss-1')));
      await tester.pump();
      expect(notifications.items, isEmpty);
      expect(feedback.announcements, ['通知已清除', '通知已清除']);
      expect(
          feedback.sounds, ['SystemSoundType.alert', 'SystemSoundType.alert']);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('clear all reports only the actual cleared count once',
      (tester) async {
    final feedback = _ClearFeedbackProbe(tester);
    final progress = NotificationProgress(total: 5);
    addTearDown(progress.dispose);
    await _mountApp(tester);
    try {
      for (final name in ['First notification', 'Second notification']) {
        notifications.notify(
          severity: WorkbenchNotificationSeverity.info,
          message: name,
        );
      }
      final active = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Still running',
        progress: progress,
      );
      await tester.pump();
      await _showNotificationCenter(tester);
      await tester.tap(find.byKey(const ValueKey('notification-clear-all')));
      await tester.pump();

      expect(notifications.items, [active]);
      expect(feedback.announcements, ['已清除 2 条通知']);
      expect(feedback.sounds, ['SystemSoundType.alert']);

      await _runClearAllCommand(tester);
      expect(notifications.items, [active]);
      expect(feedback.announcements, ['已清除 2 条通知']);
      expect(feedback.sounds, hasLength(1));

      progress.done();
      await _runClearAllCommand(tester);
      expect(notifications.items, isEmpty);
      expect(feedback.announcements, ['已清除 2 条通知', '通知已清除']);
      expect(feedback.sounds, hasLength(2));

      await _runClearAllCommand(tester);
      expect(feedback.announcements, hasLength(2));
      expect(feedback.sounds, hasLength(2));
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('clear stays silent when accessibility semantics are disabled',
      (tester) async {
    final feedback = _ClearFeedbackProbe(tester);
    await _mountApp(tester);
    try {
      notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'No active semantics',
      );
      await tester.pump();
      await _showNotificationCenter(tester);
      await tester.tap(find.byKey(const ValueKey('notification-dismiss-1')));
      await tester.pump();
      expect(notifications.items, isEmpty);
      expect(feedback.announcements, isEmpty);
      expect(feedback.sounds, isEmpty);
    } finally {
      await _unmountApp(tester);
    }
  }, semanticsEnabled: false);

  testWidgets('Linux uses the screen reader state instead of semantics alone',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final feedback = _ClearFeedbackProbe(tester);
    var readerEnabled = false;
    var statusReads = 0;
    const channel = MethodChannel('alula/accessibility');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'screenReaderEnabled');
      statusReads++;
      return readerEnabled;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await _mountApp(tester);
    try {
      for (final message in ['First item', 'Second item']) {
        notifications.notify(
          severity: WorkbenchNotificationSeverity.info,
          message: message,
        );
      }
      await tester.pump();
      await _showNotificationCenter(tester);

      await tester.tap(find.byKey(const ValueKey('notification-dismiss-2')));
      await tester.pump();
      expect(notifications.items, hasLength(1));
      expect(feedback.announcements, isEmpty);
      expect(feedback.sounds, isEmpty);

      readerEnabled = true;
      await tester.tap(find.byKey(const ValueKey('notification-dismiss-1')));
      await tester.pump();
      expect(notifications.items, isEmpty);
      expect(feedback.announcements, ['通知已清除']);
      expect(feedback.sounds, ['SystemSoundType.alert']);
      expect(statusReads, 2);
    } finally {
      await _unmountApp(tester);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'visual layout keeps the latest toast first and matches surface widths',
      (tester) async {
    await _mountApp(tester);
    try {
      for (final name in ['Older item', 'Newer item']) {
        notifications.notify(
          severity: WorkbenchNotificationSeverity.info,
          message: name,
        );
      }
      await tester.pump();
      final older = find.byKey(const ValueKey('notification-toast-1'));
      final newer = find.byKey(const ValueKey('notification-toast-2'));
      expect(
          tester.getTopLeft(newer).dy, lessThan(tester.getTopLeft(older).dy));
      final toast = tester.getRect(older);
      expect(toast.top - tester.getBottomLeft(newer).dy, 4);
      expect(toast.width, 452);
      expect(toast.bottom, 564);

      await _showNotificationCenter(tester);
      final panel =
          tester.getRect(find.byKey(const ValueKey('notification-center')));
      expect(panel.width, closeTo(toast.width, .01));
      expect(panel.right, closeTo(toast.right, .01));
      expect(panel.bottom, closeTo(toast.bottom, .01));
      expect(
        tester.getSize(find.byKey(const ValueKey('notification-position'))),
        const Size(24, 24),
      );
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('visual disclosure carries a long message from toast to center',
      (tester) async {
    await _mountApp(tester);
    try {
      const message =
          'A long message that needs to wrap on a notification card '
          'after the user chooses to expand it and show the source details.';
      notifications.notify(
        severity: WorkbenchNotificationSeverity.warning,
        message: message,
        source: 'Visual Fixture',
      );
      await tester.pump();
      final text = find.text(message);
      final source = find.text('来源：Visual Fixture');
      expect(tester.widget<Text>(text).maxLines, 1);
      expect(source, findsNothing);

      await tester
          .tap(find.byKey(const ValueKey('notification-toast-toggle-1')));
      await tester.pump();
      expect(tester.widget<Text>(text).maxLines, isNull);
      expect(source, findsOneWidget);

      await _showNotificationCenter(tester);
      expect(tester.widget<Text>(text).maxLines, isNull);
      expect(source, findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('notification-toggle-1')));
      await tester.pump();
      expect(tester.widget<Text>(text).maxLines, 1);
      expect(source, findsNothing);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('visual surfaces fit narrow constraints with inline actions',
      (tester) async {
    Future<void> showSurface(Widget surface) => tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 344, maxHeight: 350),
                child: surface,
              ),
            ),
          ),
        ));
    notifications.notify(
      severity: WorkbenchNotificationSeverity.error,
      message: 'Could not save the current document.',
      source: 'Visual Fixture',
      actions: [
        WorkbenchNotificationAction(label: 'Retry', run: () async {}),
        WorkbenchNotificationAction(label: 'Open Log', run: () async {}),
      ],
    );
    try {
      await showSurface(WorkbenchNotificationToasts(
        center: notifications,
        onDismissToast: notifications.dismissToast,
      ));

      final toast = find.byKey(const ValueKey('notification-toast-1'));
      final source = find.text('来源：Visual Fixture');
      final action =
          find.byKey(const ValueKey('notification-toast-action-1-0'));
      expect(tester.getSize(toast).width, 344);
      expect(
          tester.getCenter(source).dy, closeTo(tester.getCenter(action).dy, 1));
      expect(find.byKey(const ValueKey('notification-toast-toggle-1')),
          findsNothing);

      await showSurface(WorkbenchNotificationCenter(
        center: notifications,
        sourceFilter: null,
        onSourceFilterChanged: (_) {},
        onDismiss: notifications.dismiss,
        onClearAll: notifications.clearAll,
        onToggleDoNotDisturb: () {},
        onConfigureDoNotDisturbSources: () {},
        onClose: () {},
      ));
      final panel = find.byKey(const ValueKey('notification-center'));
      expect(tester.getSize(panel).width, 344);
      expect(tester.takeException(), isNull);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('visual progress track sits below its details and cancel button',
      (tester) async {
    await _mountApp(tester);
    final progress = NotificationProgress(
      total: 10,
      worked: 2,
      onCancel: () async {},
    );
    addTearDown(progress.dispose);
    try {
      notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Indexing files',
        progress: progress,
      );
      await tester.pump();
      final line = find.byKey(const ValueKey('notification-progress-1'));
      final cancel = find.byKey(const ValueKey('notification-toast-cancel-1'));
      expect(tester.getTopLeft(line).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(cancel).dy));
      expect(find.text('20%'), findsOneWidget);
      expect(find.byKey(const ValueKey('notification-toast-close-1')),
          findsNothing);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('notification position menu moves the center, toast and bell',
      (tester) async {
    await _mountApp(tester);
    try {
      notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Position fixture',
      );
      await tester.pump();
      final toast = find.byKey(const ValueKey('notification-toast-1'));
      final panel = find.byKey(const ValueKey('notification-center'));
      final statusBell = find.byKey(const ValueKey('status-notifications'));
      final titleBell = find.byKey(const ValueKey('title-notifications'));
      final originalToast = tester.getRect(toast);
      final originalBell = tester.getCenter(statusBell);

      await _showNotificationCenter(tester);
      Future<void> choose(String target) async {
        await tester.tap(find.byKey(const ValueKey('notification-position')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('notification-position-$target')));
        await tester.pumpAndSettle();
      }

      await choose('bottomLeft');
      final left = tester.getRect(panel);
      expect(left.left, 8);
      expect(left.bottom, originalToast.bottom);
      expect(tester.getCenter(statusBell).dx, lessThan(originalBell.dx));

      await choose('topRight');
      final top = tester.getRect(panel);
      expect(top.right, originalToast.right);
      expect(top.top, 36);
      expect(top.top, greaterThan(tester.getBottomLeft(titleBell).dy));
      expect(statusBell, findsNothing);
      expect(_notificationBellTooltip(tester, titleBar: true), '切换通知');

      await tester.tap(titleBell);
      await tester.pump();
      expect(toast, findsNothing);
      final fresh = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'New notice at the updated position',
      );
      await tester.pump();
      final freshToast = find.byKey(ValueKey('notification-toast-${fresh.id}'));
      expect(tester.getRect(freshToast).top, top.top);
      expect(tester.getRect(freshToast).right, top.right);

      await tester.tap(titleBell);
      await tester.pump();
      await choose('bottomRight');
      expect(tester.getRect(panel).bottomRight, originalToast.bottomRight);
      expect(statusBell, findsOneWidget);
      expect(titleBell, findsNothing);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('closing the notification center does not replay toasts',
      (tester) async {
    await _mountApp(tester);
    try {
      final old = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Arrived before opening the center',
      );
      final panel = find.byKey(const ValueKey('notification-center'));
      final oldToast = find.byKey(ValueKey('notification-toast-${old.id}'));
      const badgeKey = ValueKey('status-notifications-indicator');
      await tester.pump();
      expect(oldToast, findsOneWidget);
      expect(find.byKey(badgeKey), findsOneWidget);

      await _showNotificationCenter(tester);
      final urgent = notifications.notify(
        severity: WorkbenchNotificationSeverity.error,
        priority: WorkbenchNotificationPriority.urgent,
        message: 'Urgent error in the open center',
      );
      await tester.pump();
      expect(panel, findsOneWidget);
      expect(find.text(old.message), findsOneWidget);
      expect(find.text(urgent.message), findsOneWidget);
      expect(find.byKey(badgeKey), findsNothing);
      expect(notifications.toastIds, isEmpty);

      await tester.tap(find.byKey(const ValueKey('notification-center-close')));
      await tester.pump();
      expect(panel, findsNothing);
      expect(oldToast, findsNothing);
      expect(find.text(urgent.message), findsNothing);
      expect(find.byKey(badgeKey), findsNothing);

      final fresh = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Arrived after closing the center',
      );
      await tester.pump();
      expect(find.byKey(ValueKey('notification-toast-${fresh.id}')),
          findsOneWidget);
      expect(find.byKey(badgeKey), findsOneWidget);
      expect(notifications.items, [fresh, urgent, old]);

      await _showNotificationCenter(tester);
      for (final entry in [fresh, urgent, old]) {
        await tester
            .tap(find.byKey(ValueKey('notification-dismiss-${entry.id}')));
        await tester.pump();
      }
      expect(panel, findsNothing);
      expect(notifications.toastIds, isEmpty);
      expect(notifications.items, isEmpty);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('notification position command persists through session restore',
      (tester) async {
    await _mountApp(tester);
    try {
      await tester.tap(find.byKey(const ValueKey('command-center-control')));
      await tester.pumpAndSettle();
      await tester.enterText(_paletteInput(), '通知位置：右上角');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('qi-查看: 通知位置：右上角')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 550));
      expect(sessionStore.tryLoad()?['workbench.notifications.position'],
          'top-right');
    } finally {
      await _unmountApp(tester);
    }

    notifications = NotificationCenter();
    await _mountApp(tester);
    try {
      expect(find.byKey(const ValueKey('title-notifications')), findsOneWidget);
      expect(find.byKey(const ValueKey('status-notifications')), findsNothing);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('unknown notification position restores the default',
      (tester) async {
    expect(
        sessionStore.save({
          'v': 1,
          'workbench.notifications.position': 'unrecognized',
        }),
        isTrue);
    await _mountApp(tester);
    try {
      await _showNotificationCenter(tester);
      final panel =
          tester.getRect(find.byKey(const ValueKey('notification-center')));
      expect(panel.right, 792);
      expect(panel.bottom, 564);
      expect(find.byKey(const ValueKey('title-notifications')), findsNothing);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('copies the raw message of the context menu owner',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final clipboardWrites = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardWrites.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await _mountApp(tester);
    try {
      const first = '保存出错 🧪\r\n详情：文件已改动';
      const second = 'Another notification';
      final older = notifications.notify(
        severity: WorkbenchNotificationSeverity.warning,
        message: first,
        source: '文件',
      );
      final newer = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: second,
      );
      await tester.pump();

      final toast = find.byKey(const ValueKey('notification-toast-1'));
      final toastCopy =
          find.byKey(const ValueKey('notification-toast-copy-1'));
      Future<void> openToastMenu() async {
        await tester.tapAt(
          tester.getCenter(toast),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        expect(toastCopy, findsOneWidget);
      }

      await openToastMenu();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(toastCopy, findsNothing);
      expect(clipboardWrites, isEmpty);
      await openToastMenu();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(clipboardWrites, [first]);
      expect(notifications.toastIds, contains(older.id));

      await _showNotificationCenter(tester);
      expect(focusedWorkbenchNotification()?.notification, same(newer));
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('notification-copy-2')));
      await tester.pumpAndSettle();
      expect(clipboardWrites, [first, second]);
      expect(focusedWorkbenchNotification()?.notification, same(newer));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('notification-copy-2')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(clipboardWrites, [first, second]);

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(notifications.items, [older]);
    } finally {
      await _unmountApp(tester);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('toast context menu leaves with its owner', (tester) async {
    await _mountApp(tester);
    try {
      final notice = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Context menu lifecycle',
      );
      await tester.pump();
      await tester.tapAt(
        tester.getCenter(find.byKey(const ValueKey('notification-toast-1'))),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      final copy = find.byKey(const ValueKey('notification-toast-copy-1'));
      expect(copy, findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      expect(notifications.toastIds, [notice.id]);
      expect(copy, findsOneWidget);
      notifications.dismissToast(notice.id);
      await tester.pumpAndSettle();
      expect(copy, findsNothing);
      expect(notifications.items, [notice]);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('secondary notification actions target the menu owner',
      (tester) async {
    await _mountApp(tester);
    try {
      final selected = <String>[];
      final notice = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Notification with actions',
        actions: [
          WorkbenchNotificationAction(
            label: 'Primary action',
            run: () async => selected.add('primary'),
          ),
        ],
        secondaryActions: [
          WorkbenchNotificationAction(
            label: 'Secondary action',
            run: () async => selected.add('secondary'),
          ),
        ],
      );
      notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Other notification',
      );
      await tester.pump();
      expect(find.text('Primary action'), findsOneWidget);
      expect(find.text('Secondary action'), findsNothing);
      expect(find.byKey(const ValueKey('notification-toast-more-2')),
          findsNothing);

      await tester.tap(find.byKey(const ValueKey('notification-toast-more-1')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('notification-toast-secondary-1-0')));
      await tester.pumpAndSettle();
      expect(selected, ['secondary']);
      expect(notifications.byId(notice.id), same(notice));
      expect(notifications.toastIds, contains(notice.id));

      await _showNotificationCenter(tester);
      final more = find.byKey(const ValueKey('notification-more-1'));
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('notification-secondary-1-0')),
          findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Secondary action'), findsNothing);
      expect(focusedWorkbenchNotification()?.notification, same(notice));
      expect(selected, ['secondary']);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('notification-secondary-1-0')));
      await tester.pumpAndSettle();
      expect(selected, ['secondary', 'secondary']);
      expect(notifications.items, hasLength(2));
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets(
      'an open secondary notification menu preserves the toast at expiry',
      (tester) async {
    await _mountApp(tester);
    try {
      final notice = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Expiring notification',
        secondaryActions: [
          WorkbenchNotificationAction(label: 'Details', run: () async {}),
        ],
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('notification-toast-more-1')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 10));
      expect(notifications.toastIds, contains(notice.id));
      expect(find.text('Details'), findsOneWidget);
      notifications.dismissToast(notice.id);
      await tester.pumpAndSettle();
      expect(find.text('Details'), findsNothing);
      expect(notifications.byId(notice.id), same(notice));
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('secondary notification failures retain active progress',
      (tester) async {
    await _mountApp(tester);
    try {
      final notice = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Running operation',
        progress: NotificationProgress(total: 10),
        secondaryActions: [
          WorkbenchNotificationAction(
            label: 'Open details',
            run: () async => throw StateError('details unavailable'),
          ),
        ],
      );
      await tester.pump();
      await _showNotificationCenter(tester);
      expect(
          find.byKey(const ValueKey('notification-dismiss-1')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('notification-more-1')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('notification-secondary-1-0')));
      await tester.pumpAndSettle();
      expect(notifications.byId(notice.id), same(notice));
      expect(notice.hasProgress, isTrue);
      expect(notifications.items.first.severity,
          WorkbenchNotificationSeverity.error);
      expect(
          notifications.items.first.message, contains('details unavailable'));
      expect(
          find.byKey(const ValueKey('notification-dismiss-1')), findsNothing);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('Windows sends each successful clear to the native runner once',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final feedback = _ClearFeedbackProbe(tester);
    final messages = <String>[];
    const channel = MethodChannel('alula/accessibility');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'notificationCleared');
      messages.add(call.arguments as String);
      return false;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final progress = NotificationProgress(total: 10);
    addTearDown(progress.dispose);
    await _mountApp(tester);
    try {
      final active = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Active progress',
        progress: progress,
      );
      for (final name in ['Batch one', 'Batch two', 'Button', 'Keyboard']) {
        notifications.notify(
          severity: WorkbenchNotificationSeverity.info,
          message: name,
        );
      }
      await tester.pump();
      await _showNotificationCenter(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(notifications.byId(5), isNull);

      await tester.tap(find.byKey(const ValueKey('notification-dismiss-4')));
      await tester.pump();
      expect(notifications.byId(4), isNull);

      await tester.tap(find.byKey(const ValueKey('notification-clear-all')));
      await tester.pump();
      expect(notifications.items, [active]);

      await _runClearAllCommand(tester);

      expect(messages, ['通知已清除', '通知已清除', '已清除 2 条通知']);
      expect(feedback.announcements, isEmpty);
      expect(feedback.sounds, isEmpty);
    } finally {
      await _unmountApp(tester);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'Windows uses Flutter feedback only for registered reader fallback',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final feedback = _ClearFeedbackProbe(tester);
    var useFlutter = false;
    const channel = MethodChannel('alula/accessibility');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'notificationCleared');
      return useFlutter;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await _mountApp(tester);
    try {
      for (final name in ['Registered reader', 'Reader off']) {
        notifications.notify(
          severity: WorkbenchNotificationSeverity.info,
          message: name,
        );
      }
      await tester.pump();
      await _showNotificationCenter(tester);

      await tester.tap(find.byKey(const ValueKey('notification-dismiss-2')));
      await tester.pump();
      expect(feedback.announcements, isEmpty);
      expect(feedback.sounds, isEmpty);

      useFlutter = true;
      await tester.tap(find.byKey(const ValueKey('notification-dismiss-1')));
      await tester.pump();
      expect(notifications.items, isEmpty);
      expect(feedback.announcements, ['通知已清除']);
      expect(feedback.sounds, ['SystemSoundType.alert']);
    } finally {
      await _unmountApp(tester);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('unavailable native feedback does not interrupt clearing',
      (tester) async {
    final feedback = _ClearFeedbackProbe(
      tester,
      supportsAnnounce: false,
      failSound: true,
    );
    await _mountApp(tester);
    try {
      notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'No announcement support',
      );
      await tester.pump();
      await _showNotificationCenter(tester);
      await tester.tap(find.byKey(const ValueKey('notification-dismiss-1')));
      await tester.pump();
      expect(notifications.items, isEmpty);
      expect(feedback.announcements, isEmpty);
      expect(feedback.sounds, ['SystemSoundType.alert']);
      expect(tester.takeException(), isNull);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('toast hide, middle click and expiration leave feedback silent',
      (tester) async {
    final feedback = _ClearFeedbackProbe(tester);
    await _mountApp(tester);
    try {
      final hidden = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Hide this toast',
      );
      await tester.pump();
      await tester
          .tap(find.byKey(ValueKey('notification-toast-close-${hidden.id}')));
      await tester.pump();

      final expired = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Expiring toast',
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      expect(notifications.toastIds, isEmpty);

      final middle = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Middle-click this toast',
      );
      await tester.pump();
      await _middleClick(tester, find.text(middle.message));
      expect(notifications.byId(middle.id), isNull);

      expect(notifications.items, [expired, hidden]);
      expect(feedback.announcements, isEmpty);
      expect(feedback.sounds, isEmpty);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('middle click clears only the toast hit on release',
      (tester) async {
    await _mountApp(tester);
    try {
      final clicked = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Middle-click toast',
      );
      final other = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Other toast',
      );
      await tester.pump();

      final press = await tester.startGesture(
        tester.getCenter(find.text(clicked.message)),
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await tester.pump();
      expect(notifications.items, [other, clicked]);
      await press.up();
      await tester.pump();

      expect(notifications.items, [other]);
      expect(notifications.toastIds, [other.id]);
      expect(notifications.unreadCount, 1);
      expect(find.text(clicked.message), findsNothing);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('middle click clears the clicked row and preserves other focus',
      (tester) async {
    await _mountApp(tester);
    try {
      final clicked = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Clicked notification row',
      );
      final focused = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Focused notification row',
      );
      await tester.pump();
      await _showNotificationCenter(tester);
      final focus = Focus.of(tester.element(find.text(focused.message)));
      expect(focus.hasPrimaryFocus, isTrue);

      await _middleClick(tester, find.text(clicked.message));

      expect(notifications.items, [focused]);
      expect(find.text(clicked.message), findsNothing);
      expect(focus.hasPrimaryFocus, isTrue);
    } finally {
      await _unmountApp(tester);
    }
  });

  for (final inCenter in [false, true]) {
    testWidgets(
        'middle click protects progress in the ${inCenter ? 'center' : 'toast'}',
        (tester) async {
      final progress = NotificationProgress(total: 10, worked: 2);
      addTearDown(progress.dispose);
      await _mountApp(tester);
      try {
        final entry = notifications.notify(
          severity: WorkbenchNotificationSeverity.info,
          message: 'Active progress',
          progress: progress,
        );
        await tester.pump();
        if (inCenter) await _showNotificationCenter(tester);

        await _middleClick(tester, find.text(entry.message));
        expect(notifications.items, [entry]);

        progress.done();
        await tester.pump();
        await _middleClick(tester, find.text(entry.message));
        expect(notifications.items, isEmpty);
      } finally {
        await _unmountApp(tester);
      }
    });
  }

  testWidgets('other buttons, cancellation and release outside keep the row',
      (tester) async {
    await _mountApp(tester);
    try {
      final entry = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Notification row with gestures',
      );
      await tester.pump();
      await _showNotificationCenter(tester);
      final row = tester.getRect(
        find.byKey(ValueKey('notification-item-${entry.id}')),
      );

      for (final buttons in [
        kPrimaryMouseButton,
        kSecondaryMouseButton,
        kPrimaryMouseButton | kMiddleMouseButton,
      ]) {
        await tester.tapAt(
          row.center,
          kind: PointerDeviceKind.mouse,
          buttons: buttons,
        );
        await tester.pump();
        expect(notifications.items, [entry]);
        if (buttons == kSecondaryMouseButton) {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
        }
      }

      final canceled = await tester.startGesture(
        row.center,
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await canceled.cancel();
      await tester.pump();
      expect(notifications.items, [entry]);

      final slidesOutside = await tester.startGesture(
        Offset(row.center.dx, row.top + 1),
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await slidesOutside.moveBy(const Offset(0, -3));
      await slidesOutside.up();
      await tester.pump();
      expect(notifications.items, [entry]);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('releasing a withdrawn toast keeps its retained notification',
      (tester) async {
    await _mountApp(tester);
    try {
      final entry = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Retained after hiding toast',
      );
      await tester.pump();
      final press = await tester.startGesture(
        tester.getCenter(find.text(entry.message)),
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );

      notifications.dismissToast(entry.id);
      await press.up();
      await tester.pump();
      expect(notifications.items, [entry]);
      expect(notifications.toastIds, isEmpty);
      expect(notifications.unreadCount, 1);
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
      expect(
          find.byKey(const ValueKey('notification-toast-1')), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      expect(find.byKey(const ValueKey('notification-toast-1')), findsNothing);
      expect(notifications.items, hasLength(1));
      expect(notifications.unreadCount, 1);
      expect(find.byKey(const ValueKey('status-notifications-indicator')),
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

      await _chooseGlobalDoNotDisturb(tester);
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

  testWidgets('global do not disturb dismisses current surfaces and admits new errors',
      (tester) async {
    await _mountApp(tester);
    try {
      final oldInfo = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Initially visible info',
      );
      final oldError = notifications.notify(
        severity: WorkbenchNotificationSeverity.error,
        message: 'Initially visible error',
      );
      await tester.pump();
      expect(notifications.toastIds, [oldInfo.id, oldError.id]);
      await _showNotificationCenter(tester);
      await _chooseGlobalDoNotDisturb(tester);
      await tester.pumpAndSettle();
      expect(notifications.doNotDisturb, isTrue);
      expect(find.byKey(const ValueKey('notification-center')), findsNothing);
      expect(notifications.toastIds, isEmpty);
      expect(notifications.items, [oldError, oldInfo]);

      final warning = notifications.notify(
        severity: WorkbenchNotificationSeverity.warning,
        message: 'Quiet warning',
      );
      final info = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Quiet info',
      );
      final error = notifications.notify(
        severity: WorkbenchNotificationSeverity.error,
        message: 'New error during quiet mode',
      );
      await tester.pump();
      expect(notifications.toastIds, [error.id]);
      expect(find.text(error.message), findsOneWidget);
      expect(find.text(warning.message), findsNothing);
      expect(find.text(info.message), findsNothing);

      await _showNotificationCenter(tester);
      for (final entry in [oldInfo, oldError, warning, info, error]) {
        expect(find.byKey(ValueKey('notification-item-${entry.id}')),
            findsOneWidget);
      }
      await _chooseGlobalDoNotDisturb(tester);
      await tester.pumpAndSettle();
      expect(notifications.doNotDisturb, isFalse);
      expect(find.byKey(const ValueKey('notification-center')), findsOneWidget);
      expect(notifications.toastIds, isEmpty);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('center DND menu shows ten sources and links to the full picker',
      (tester) async {
    await _mountApp(tester);
    try {
      for (var index = 12; index >= 1; index--) {
        final suffix = index.toString().padLeft(2, '0');
        notifications.notify(
          severity: WorkbenchNotificationSeverity.info,
          message: 'Notification from source $suffix',
          source: 'Fixture Source $suffix',
          sourceId: 'fixture.source.$suffix',
        );
      }
      await tester.pump();
      await _showNotificationCenter(tester);
      final button = find.byKey(const ValueKey('notification-dnd-toggle'));
      final global = find.byKey(const ValueKey('notification-dnd-global'));
      final more = find.byKey(const ValueKey('notification-dnd-more'));
      final panel = find.byKey(const ValueKey('notification-center'));
      final first = find.byKey(
        const ValueKey('notification-dnd-source-fixture.source.01'),
      );

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);
      expect(notifications.doNotDisturb, isFalse);
      expect(global, findsOneWidget);
      for (var index = 1; index <= 12; index++) {
        final suffix = index.toString().padLeft(2, '0');
        expect(
          find.byKey(
              ValueKey('notification-dnd-source-fixture.source.$suffix')),
          index <= 10 ? findsOneWidget : findsNothing,
        );
      }
      expect(tester.widget<CheckedPopupMenuItem<VoidCallback>>(first).checked,
          isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);
      expect(first, findsNothing);

      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(notifications.sourceFilters['fixture.source.01']?.muted, isTrue);
      expect(notifications.sourceFilters['fixture.source.02']?.muted, isFalse);
      expect(panel, findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckedPopupMenuItem<VoidCallback>>(first).checked,
          isFalse);
      await tester.ensureVisible(more);
      await tester.tap(more);
      await tester.pumpAndSettle();
      await tester.enterText(_paletteInput(), 'Fixture Source 12');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('qi-Fixture Source 12')));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(notifications.sourceFilters['fixture.source.12']?.muted, isTrue);
      expect(notifications.sourceFilters['fixture.source.11']?.muted, isFalse);
      expect(notifications.sourceFilters['fixture.source.01']?.muted, isTrue);
      expect(panel, findsOneWidget);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('global do not disturb command survives session restore',
      (tester) async {
    await _mountApp(tester);
    try {
      await tester.tap(find.byKey(const ValueKey('command-center-control')));
      await tester.pumpAndSettle();
      await tester.enterText(_paletteInput(), '切换请勿打扰');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('qi-查看: 切换请勿打扰')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 550));
      expect(notifications.doNotDisturb, isTrue);
      expect(sessionStore.tryLoad()?['notifications.doNotDisturbMode'], isTrue);
    } finally {
      await _unmountApp(tester);
    }

    notifications = NotificationCenter();
    await _mountApp(tester);
    try {
      expect(notifications.doNotDisturb, isTrue);
      notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Quiet after restart',
      );
      final error = notifications.notify(
        severity: WorkbenchNotificationSeverity.error,
        message: 'Visible error after restart',
      );
      await tester.pump();
      expect(notifications.toastIds, [error.id]);
      expect(find.text(error.message), findsOneWidget);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('source do not disturb uses IDs and survives session restore',
      (tester) async {
    const period = 'notifications.perSourceDoNotDisturbMode';
    const alphaId = 'fixture.alpha';
    const betaId = 'fixture.beta';
    const alphaLabel = '同名 ($alphaId)';
    const betaLabel = '同名 ($betaId)';
    final alphaRow = find.byKey(const ValueKey('qi-$alphaLabel'));
    final betaRow = find.byKey(const ValueKey('qi-$betaLabel'));

    Future<void> openSourcePicker() async {
      await tester.tap(find.byKey(const ValueKey('command-center-control')));
      await tester.pumpAndSettle();
      await tester.enterText(_paletteInput(), '按来源切换请勿打扰');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('qi-查看: 按来源切换请勿打扰')));
      await tester.pumpAndSettle();
    }

    await _mountApp(tester);
    try {
      final alpha = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Alpha info',
        source: '同名',
        sourceId: alphaId,
      );
      final beta = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Beta info',
        source: '同名',
        sourceId: betaId,
      );
      await tester.pumpAndSettle();
      await openSourcePicker();
      expect(alphaRow, findsOneWidget);
      expect(betaRow, findsOneWidget);
      await tester.tap(alphaRow);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(notifications.toastIds, [alpha.id, beta.id]);

      await openSourcePicker();
      expect(
          tester
              .widget<Icon>(
                find.byKey(const ValueKey('qi-check-$alphaLabel')),
              )
              .icon,
          Icons.check_box);
      await tester.tap(alphaRow);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(notifications.toastIds, [beta.id]);
      expect(notifications.items, [beta, alpha]);

      notifications.notify(
        severity: WorkbenchNotificationSeverity.warning,
        message: 'Alpha warning stays in center',
        source: '同名',
        sourceId: alphaId,
      );
      final betaWarning = notifications.notify(
        severity: WorkbenchNotificationSeverity.warning,
        message: 'Beta warning still pops up',
        source: '同名',
        sourceId: betaId,
      );
      final alphaError = notifications.notify(
        severity: WorkbenchNotificationSeverity.error,
        message: 'Alpha error still pops up',
        source: '同名',
        sourceId: alphaId,
      );
      await tester.pump(const Duration(milliseconds: 550));
      expect(notifications.toastIds, [beta.id, betaWarning.id, alphaError.id]);
      expect(sessionStore.tryLoad()?[period], {
        alphaId: {'label': '同名', 'muted': true},
        betaId: {'label': '同名', 'muted': false},
      });
    } finally {
      await _unmountApp(tester);
    }

    notifications = NotificationCenter();
    await _mountApp(tester);
    try {
      await openSourcePicker();
      expect(
          tester
              .widget<Icon>(
                find.byKey(const ValueKey('qi-check-$alphaLabel')),
              )
              .icon,
          Icons.check_box_outline_blank);
      expect(betaRow, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      notifications.notify(
        severity: WorkbenchNotificationSeverity.warning,
        message: 'Alpha remains quiet after rename',
        source: '改名',
        sourceId: alphaId,
      );
      await tester.pump();
      expect(notifications.toastIds, isEmpty);
      expect(notifications.items.single.source, '改名');
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('notification secondary menu configures its source only',
      (tester) async {
    await _mountApp(tester);
    try {
      final entry = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Source controllable notification',
        source: 'Fixture',
        sourceId: 'fixture.named',
        secondaryActions: [
          WorkbenchNotificationAction(label: 'Details', run: () async {}),
        ],
      );
      final oldError = notifications.notify(
        severity: WorkbenchNotificationSeverity.error,
        message: 'Existing source error',
        source: 'Fixture',
        sourceId: 'fixture.named',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('notification-toast-more-1')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('notification-toast-source-dnd-1')));
      await tester.pumpAndSettle();
      expect(notifications.toastIds, [oldError.id]);
      expect(notifications.items, [oldError, entry]);
      await _showNotificationCenter(tester);
      await tester.tap(find.byKey(const ValueKey('notification-more-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('notification-source-dnd-1')));
      await tester.pumpAndSettle();
      expect(notifications.toastIds, isEmpty);
      await tester.tap(find.byKey(const ValueKey('notification-center-close')));
      await tester.pump();
      final enabled = notifications.notify(
        severity: WorkbenchNotificationSeverity.warning,
        message: 'Warnings show again',
        source: 'Fixture',
        sourceId: 'fixture.named',
      );
      expect(notifications.toastIds, [enabled.id]);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets(
      'optional notifications give way to an editable field in their corner',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    expect(
      sessionStore.save({
        'v': 1,
        'workbench.notifications.position': 'top-right',
      }),
      isTrue,
    );
    await _mountApp(tester);
    try {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('find-query-input'));
      expect(input, findsOneWidget);
      await tester.tap(input);
      await tester.pump();
      final anchor = tester.getTopLeft(input);
      expect(anchor.dx, greaterThan(600));
      expect(anchor.dy, lessThan(400));

      final hidden = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Optional under the active find input',
        priority: WorkbenchNotificationPriority.optional,
      );
      final normal = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Regular notice while find has focus',
      );
      await tester.pump();
      expect(notifications.toastIds, [normal.id]);
      expect(notifications.items, [normal, hidden]);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(input, findsNothing);
      final visible = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Optional after find closes',
        priority: WorkbenchNotificationPriority.optional,
      );
      await tester.pump();
      expect(notifications.toastIds, [normal.id, visible.id]);
    } finally {
      await _unmountApp(tester);
    }
    expect(notifications.allowOptionalToast, isNull);
  });

  testWidgets('center keeps compact row heights when separators are painted',
      (tester) async {
    await _mountApp(tester);
    try {
      final older = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'First density row',
      );
      final newer = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Second density row',
      );
      await tester.pump();
      await _showNotificationCenter(tester);
      final header = find.byKey(const ValueKey('notification-center-header'));
      final clear = find.byKey(const ValueKey('notification-clear-all'));
      final quiet = find.byKey(const ValueKey('notification-dnd-toggle'));
      final panel = find.byKey(const ValueKey('notification-center'));

      for (final notice in [newer, older]) {
        final row = find.byKey(ValueKey('notification-item-${notice.id}'));
        expect(tester.getSize(row).height, 34);
      }
      expect(tester.getSize(header).height, 35);
      expect(tester.getCenter(clear).dx, lessThan(tester.getCenter(quiet).dx));
      expect(tester.getSize(panel).height, 105);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('the center scrolls once its rows exceed the fixed viewport',
      (tester) async {
    await _mountApp(tester);
    try {
      for (var index = 0; index < 18; index++) {
        notifications.notify(
          severity: WorkbenchNotificationSeverity.info,
          message: 'Scrollable notification $index',
        );
      }
      await tester.pump();
      await _showNotificationCenter(tester);
      final panel = find.byKey(const ValueKey('notification-center'));
      final list = find.descendant(
        of: panel,
        matching: find.byType(ListView),
      );
      expect(tester.getSize(list).height, 400);
      expect(tester.getSize(panel).height, 437);

      await tester.drag(list, const Offset(0, -390));
      await tester.pumpAndSettle();
      expect(
          find.text('Scrollable notification 0').hitTestable(), findsOneWidget);
    } finally {
      await _unmountApp(tester);
    }
  });

  for (final inCenter in [false, true]) {
    testWidgets(
        'a primary action closes only its own notice in ${inCenter ? 'center' : 'toast'}',
        (tester) async {
      await _mountApp(tester);
      try {
        final completion = Completer<void>();
        var invoked = 0;
        final retained = notifications.notify(
          severity: WorkbenchNotificationSeverity.info,
          priority: WorkbenchNotificationPriority.silent,
          message: 'Other entry',
        );
        final notice = notifications.notify(
          severity: WorkbenchNotificationSeverity.error,
          message: 'Primary action',
          actions: [
            WorkbenchNotificationAction(
              label: 'Test operation',
              run: () {
                invoked++;
                return completion.future;
              },
            ),
          ],
        );
        await tester.pump();
        if (inCenter) await _showNotificationCenter(tester);
        final prefix = inCenter ? 'notification' : 'notification-toast';
        final button = find.byKey(ValueKey('$prefix-action-${notice.id}-0'));
        await tester.tap(button);
        await tester.pump();
        expect(invoked, 1);
        expect(notifications.items, [retained]);
        expect(button, findsNothing);
        completion.complete();
        await tester.pump();
        expect(notifications.items, [retained]);
      } finally {
        await _unmountApp(tester);
      }
    });
  }

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
            keepOpen: true,
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
      expect(find.byKey(const ValueKey('notification-center')), findsNothing);
      expect(notifications.isEmpty, isTrue);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('clear all becomes available when progress finishes',
      (tester) async {
    final progress = NotificationProgress(total: 10, worked: 4);
    addTearDown(progress.dispose);
    await _mountApp(tester);
    try {
      final running = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Indexing files',
        progress: progress,
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('status-notifications')));
      await tester.pump();

      final clearAll = find.byKey(const ValueKey('notification-clear-all'));
      expect(tester.widget<IconButton>(clearAll).onPressed, isNull);
      progress.report(worked: 8);
      await tester.pump();
      expect(tester.widget<IconButton>(clearAll).onPressed, isNull);
      expect(notifications.items, [running]);

      progress.done();
      await tester.pump();
      expect(tester.widget<IconButton>(clearAll).onPressed, isNotNull);
      await tester.tap(clearAll);
      await tester.pump();
      expect(find.byKey(const ValueKey('notification-center')), findsNothing);
      expect(notifications.items, isEmpty);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('clear notifications command preserves an active progress entry',
      (tester) async {
    final progress = NotificationProgress(total: 10, worked: 4);
    addTearDown(progress.dispose);
    await _mountApp(tester);
    try {
      notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Ordinary notification',
      );
      final running = notifications.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Indexing files',
        progress: progress,
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('status-notifications')));
      await tester.pump();
      expect(find.byKey(const ValueKey('notification-center')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('command-center-control')));
      await tester.pumpAndSettle();
      await tester.enterText(_paletteInput(), '清除所有通知');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('qi-查看: 清除所有通知')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('notification-center')), findsNothing);
      expect(notifications.items, [running]);
      expect(progress.isDone, isFalse);
      await tester.tap(find.byKey(const ValueKey('status-notifications')));
      await tester.pump();
      expect(find.text('Indexing files'), findsOneWidget);
      expect(find.text('Ordinary notification'), findsNothing);
    } finally {
      await _unmountApp(tester);
    }
  });

  testWidgets('the palette can accept a new notification primary action',
      (tester) async {
    await _mountApp(tester);
    try {
      final handled = <String>[];
      WorkbenchNotification add(String message) => notifications.notify(
            severity: WorkbenchNotificationSeverity.info,
            message: message,
            actions: [
              WorkbenchNotificationAction(
                label: 'First',
                run: () async => handled.add(message),
              ),
            ],
          );
      final older = add('Earlier action notification');
      final latest = add('Newest action notification');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('command-center-control')));
      await tester.pumpAndSettle();
      await tester.enterText(_paletteInput(), '执行通知主操作');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('qi-查看: 执行通知主操作')));
      await tester.pumpAndSettle();
      expect(handled, [latest.message]);
      expect(notifications.items, [older]);
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

String _notificationBellTooltip(WidgetTester tester, {bool titleBar = false}) {
  final target = find.byKey(
    ValueKey(titleBar ? 'title-notifications' : 'status-notifications'),
  );
  final tooltip = find.descendant(of: target, matching: find.byType(Tooltip));
  return tester.widget<Tooltip>(tooltip).message!;
}

Finder _paletteInput() => find.descendant(
      of: find.byKey(const ValueKey('quick-input')),
      matching: find.byType(TextField),
    );

Future<void> _showNotificationCenter(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('status-notifications')));
  await tester.pump();
  await tester.pump();
}

Future<void> _chooseGlobalDoNotDisturb(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('notification-dnd-toggle')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('notification-dnd-global')));
  await tester.pumpAndSettle();
}

Future<void> _middleClick(WidgetTester tester, Finder target) async {
  await tester.tapAt(
    tester.getCenter(target),
    kind: PointerDeviceKind.mouse,
    buttons: kMiddleMouseButton,
  );
  await tester.pump();
}

Future<void> _runClearAllCommand(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('command-center-control')));
  await tester.pumpAndSettle();
  await tester.enterText(_paletteInput(), '清除所有通知');
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('qi-查看: 清除所有通知')));
  await tester.pumpAndSettle();
}

class _ClearFeedbackProbe {
  _ClearFeedbackProbe(
    WidgetTester tester, {
    bool supportsAnnounce = true,
    bool failSound = false,
  }) {
    final dispatcher = tester.binding.platformDispatcher;
    dispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(supportsAnnounce: supportsAnnounce);
    addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);

    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockDecodedMessageHandler<Object?>(
      SystemChannels.accessibility,
      (Object? message) async {
        if (message case {'type': 'announce', 'data': final Map data}) {
          announcements.add(data['message'] as String);
          viewIds.add(data['viewId'] as int);
        }
        return null;
      },
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemSound.play' &&
          call.arguments == 'SystemSoundType.alert') {
        sounds.add(call.arguments as String);
        if (failSound) throw PlatformException(code: 'sound-unavailable');
      }
      return null;
    });

    addTearDown(() {
      messenger.setMockDecodedMessageHandler<Object?>(
        SystemChannels.accessibility,
        null,
      );
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
  }

  final announcements = <String>[];
  final viewIds = <int>[];
  final sounds = <String>[];
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
