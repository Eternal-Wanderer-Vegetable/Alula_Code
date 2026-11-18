import 'package:alula_app/workbench/notification_widgets.dart';
import 'package:alula_app/workbench/notifications.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (severity, seconds) in [
    (WorkbenchNotificationSeverity.info, 10),
    (WorkbenchNotificationSeverity.warning, 12),
    (WorkbenchNotificationSeverity.error, 15),
  ]) {
    testWidgets(
        '${severity.name} toast expires after ${seconds}s, keeping unread',
        (tester) async {
      final center = NotificationCenter();
      addTearDown(center.dispose);
      final notification = center.notify(
        severity: severity,
        message: 'Timed notification',
      );
      await _mount(tester, center);

      await tester.pump(Duration(seconds: seconds - 1));
      expect(_toast(notification.id), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 999));
      expect(_toast(notification.id), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(_toast(notification.id), findsNothing);
      expect(center.toastIds, isEmpty);
      expect(center.items, [notification]);
      expect(center.unreadCount, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
      'hover at deadline postpones; mouse leave does not reset interval',
      (tester) async {
    final center = NotificationCenter();
    addTearDown(center.dispose);
    final notification = center.notify(
      severity: WorkbenchNotificationSeverity.info,
      message: 'Hover notification',
    );
    await _mount(tester, center);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await tester.pump(const Duration(seconds: 9));
    await mouse.moveTo(tester.getCenter(_toast(notification.id)));
    await tester.pump(const Duration(seconds: 1));
    expect(_toast(notification.id), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(seconds: 8));
    expect(_toast(notification.id), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(_toast(notification.id), findsNothing);
    expect(center.items, [notification]);
    expect(center.unreadCount, 1);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('descendant action focus postpones the deadline', (tester) async {
    final center = NotificationCenter();
    addTearDown(center.dispose);
    final notification = center.notify(
      severity: WorkbenchNotificationSeverity.info,
      message: 'Focusable notification',
      actions: [
        WorkbenchNotificationAction(label: 'Retry', run: () async {}),
      ],
    );
    await _mount(tester, center);
    final actionFocus = Focus.of(tester.element(find.text('Retry')));
    actionFocus.requestFocus();
    await tester.pump();
    expect(actionFocus.hasPrimaryFocus, isTrue);
    await tester.pump(const Duration(seconds: 10));
    expect(_toast(notification.id), findsOneWidget);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump(const Duration(seconds: 9));
    expect(_toast(notification.id), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(_toast(notification.id), findsNothing);
    expect(center.unreadCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('focus restored before deadline does not restart the interval',
      (tester) async {
    final center = NotificationCenter();
    addTearDown(center.dispose);
    final notification = center.notify(
      severity: WorkbenchNotificationSeverity.info,
      message: 'Return before deadline',
    );
    await _mount(tester, center);
    await tester.pump(const Duration(seconds: 2));
    await _mount(tester, center, windowFocused: false);
    await tester.pump(const Duration(seconds: 4));
    await _mount(tester, center, windowFocused: true);
    await tester.pump(const Duration(seconds: 3));
    expect(_toast(notification.id), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(_toast(notification.id), findsNothing);
    expect(center.unreadCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hover ending before deadline does not restart the interval',
      (tester) async {
    final center = NotificationCenter();
    addTearDown(center.dispose);
    final notification = center.notify(
      severity: WorkbenchNotificationSeverity.info,
      message: 'Leave before deadline',
    );
    await _mount(tester, center);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await tester.pump(const Duration(seconds: 2));
    await mouse.moveTo(tester.getCenter(_toast(notification.id)));
    await tester.pump(const Duration(seconds: 7));
    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(seconds: 1));
    expect(_toast(notification.id), findsNothing);
    expect(center.unreadCount, 1);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('inactive deadline waits for window focus then a full interval',
      (tester) async {
    final center = NotificationCenter();
    addTearDown(center.dispose);
    final notification = center.notify(
      severity: WorkbenchNotificationSeverity.info,
      message: 'Inactive notification',
    );
    await _mount(tester, center);
    await tester.pump(const Duration(seconds: 9));
    await _mount(tester, center, windowFocused: false);
    await tester.pump(const Duration(seconds: 1));
    expect(_toast(notification.id), findsOneWidget);
    await tester.pump(const Duration(seconds: 35));
    expect(_toast(notification.id), findsOneWidget);
    await _mount(tester, center, windowFocused: true);
    await tester.pump(const Duration(seconds: 9));
    expect(_toast(notification.id), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(_toast(notification.id), findsNothing);
    expect(center.items, [notification]);
    expect(center.unreadCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'active progress and errors with actions remain sticky at deadlines',
      (tester) async {
    final center = NotificationCenter();
    final progress = NotificationProgress(total: 100);
    addTearDown(center.dispose);
    addTearDown(progress.dispose);
    final working = center.notify(
      severity: WorkbenchNotificationSeverity.info,
      message: 'Working',
      progress: progress,
    );
    final error = center.notify(
      severity: WorkbenchNotificationSeverity.error,
      message: 'Failed with recovery',
      actions: [
        WorkbenchNotificationAction(label: 'Recover', run: () async {}),
      ],
    );
    await _mount(tester, center);
    await tester.pump(const Duration(seconds: 10));
    expect(_toast(working.id), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(_toast(error.id), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(_toast(working.id), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    progress.done();
    await tester.pump();
    await tester.pump(const Duration(seconds: 8));
    expect(_toast(working.id), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(_toast(working.id), findsNothing,
        reason:
            'Progress completion is reevaluated at t=30, not restarted at 21');
    expect(_toast(error.id), findsOneWidget);
    expect(center.toastIds, [error.id]);
    expect(center.items, [error, working]);
    expect(center.unreadCount, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'unchanged rebuilds and a new keyed sibling do not restart lifetime',
      (tester) async {
    final center = NotificationCenter();
    addTearDown(center.dispose);
    final first = center.notify(
      severity: WorkbenchNotificationSeverity.info,
      message: 'Original',
    );
    await _mount(tester, center);
    await tester.pump(const Duration(seconds: 9));
    await _mount(tester, center);
    final second = center.notify(
      severity: WorkbenchNotificationSeverity.info,
      message: 'New sibling',
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(_toast(first.id), findsNothing);
    expect(_toast(second.id), findsOneWidget);
    expect(center.toastIds, [second.id]);
    expect(center.items, [second, first]);
    expect(center.unreadCount, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final removal in ['clear', 'dnd', 'dismiss', 'evict', 'unmount']) {
    testWidgets('$removal cancels lifetime without a late dismissal callback',
        (tester) async {
      final center = NotificationCenter();
      addTearDown(center.dispose);
      final notification = center.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Removed before expiry',
      );
      final dismissed = <int>[];
      await _mount(tester, center, onDismissToast: (id) {
        dismissed.add(id);
        center.dismissToast(id);
      });
      await tester.pump(const Duration(seconds: 9));
      switch (removal) {
        case 'clear':
          center.clearAll();
        case 'dnd':
          center.setDoNotDisturb(true);
        case 'dismiss':
          center.dismissToast(notification.id);
        case 'evict':
          for (var i = 0; i < 3; i++) {
            center.notify(
              severity: WorkbenchNotificationSeverity.error,
              message: 'Sticky replacement $i',
              actions: [
                WorkbenchNotificationAction(label: 'Retry', run: () async {}),
              ],
            );
          }
        case 'unmount':
          await tester.pumpWidget(const SizedBox.shrink());
      }
      await tester.pump();
      expect(_toast(notification.id), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(dismissed, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 30));
      expect(dismissed, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unmount while waiting for window focus has no late callback',
      (tester) async {
    final center = NotificationCenter();
    addTearDown(center.dispose);
    center.notify(
      severity: WorkbenchNotificationSeverity.info,
      message: 'Waiting for focus',
    );
    final dismissed = <int>[];
    await _mount(tester, center,
        windowFocused: false, onDismissToast: dismissed.add);
    await tester.pump(const Duration(seconds: 10));
    expect(_toast(1), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
    expect(dismissed, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

Finder _toast(int id) => find.byKey(ValueKey('notification-toast-$id'));

Future<void> _mount(
  WidgetTester tester,
  NotificationCenter center, {
  bool windowFocused = true,
  void Function(int id)? onDismissToast,
}) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomRight,
          child: ListenableBuilder(
            listenable: center,
            builder: (context, _) => WorkbenchNotificationToasts(
              center: center,
              onDismissToast: onDismissToast ?? center.dismissToast,
              windowFocused: windowFocused,
            ),
          ),
        ),
      ),
    ));
