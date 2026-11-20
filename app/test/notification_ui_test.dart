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

      await _showNotificationCenter(tester);
      final panel =
          tester.getRect(find.byKey(const ValueKey('notification-center')));
      expect(panel.width, closeTo(toast.width, .01));
      expect(panel.right, closeTo(toast.right, .01));
      expect(panel.bottom, closeTo(toast.bottom, .01));
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

Future<void> _showNotificationCenter(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('status-notifications')));
  await tester.pump();
  await tester.pump();
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
