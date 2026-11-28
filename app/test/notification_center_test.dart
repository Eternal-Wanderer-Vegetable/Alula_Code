import 'dart:async';

import 'package:alula_app/workbench/notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationCenter', () {
    WorkbenchNotification notify(
      NotificationCenter center, {
      String message = 'm',
      String source = 'Alula',
      WorkbenchNotificationSeverity severity =
          WorkbenchNotificationSeverity.info,
      List<WorkbenchNotificationAction> actions =
          const <WorkbenchNotificationAction>[],
    }) =>
        center.notify(
          severity: severity,
          message: message,
          source: source,
          actions: actions,
        );

    test('notify lists newest first and keeps toast order oldest to newest',
        () {
      final center = NotificationCenter();
      final first = notify(center, message: 'one');
      final second = notify(center, message: 'two');
      expect(center.items.map((n) => n.message).toList(), ['two', 'one']);
      expect(center.toastIds, [first.id, second.id]);
      expect(center.unreadCount, 2);
      expect(center.hasUnread, isTrue);
    });

    test('toast stack is bounded and drops the oldest toast', () {
      final center = NotificationCenter();
      for (var i = 0; i < NotificationCenter.maxVisibleToasts + 2; i++) {
        notify(center, message: 'm$i');
      }
      expect(center.toastIds.length, NotificationCenter.maxVisibleToasts);
      expect(center.toastIds.last, NotificationCenter.maxVisibleToasts + 2);
    });

    test('closing a toast keeps the notification in the center', () {
      final center = NotificationCenter();
      final notification = notify(center);
      center.dismissToast(notification.id);
      expect(center.toastIds, isEmpty);
      expect(center.items.length, 1);
      expect(center.unreadCount, 1);
    });

    test('dismiss and clearAll remove items, unread state and toasts', () {
      final center = NotificationCenter();
      final notification = notify(center);
      notify(center);
      center.dismiss(notification.id);
      expect(center.items.length, 1);
      expect(center.toastIds, isNot(contains(notification.id)));
      center.clearAll();
      expect(center.isEmpty, isTrue);
      expect(center.toastIds, isEmpty);
      expect(center.unreadCount, 0);
    });

    test('do not disturb suppresses toasts but keeps center entries', () {
      final center = NotificationCenter();
      notify(center);
      center.setDoNotDisturb(true);
      expect(center.toastIds, isEmpty, reason: '开启 DND 清掉现有 toast');
      final notification = notify(center, message: 'quiet');
      expect(center.toastIds, isEmpty);
      expect(center.items.first.id, notification.id);
      center.setDoNotDisturb(false);
      notify(center, message: 'loud');
      expect(center.toastIds.length, 1);
    });

    test(
        'source preferences restore bounded, validated entries and current labels',
        () {
      final center = NotificationCenter();
      center.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Already observed',
        source: 'Current label',
        sourceId: 'fixture.0',
      );
      center.restoreSourceFilters({
        'invalid-key': {'label': 'Invalid', 'muted': 'yes'},
        '': {'label': 'Missing ID', 'muted': true},
        for (var i = 0; i < NotificationCenter.defaultMaxNotifications + 2; i++)
          'fixture.$i': {'label': 'Stored label $i', 'muted': true},
      });
      expect(center.sourceFilters,
          hasLength(NotificationCenter.defaultMaxNotifications));
      expect(center.sourceFilters['fixture.0'],
          (label: 'Current label', muted: true));
      expect(center.sourceFilters.containsKey('invalid-key'), isFalse);
      expect(center.sourceFilters.containsKey(''), isFalse);
      expect(center.toastIds, isEmpty);
      expect(center.items.single.message, 'Already observed');
    });

    test('notification priority combines with the global and source filters',
        () {
      final center = NotificationCenter();
      final firstUrgent = center.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Urgent before muting',
        sourceId: 'fixture.named',
        priority: WorkbenchNotificationPriority.urgent,
      );
      center.setSourceDoNotDisturb({'fixture.named': true});
      expect(center.toastIds, [firstUrgent.id]);
      center.setDoNotDisturb(true);
      expect(center.toastIds, isEmpty);

      final silent = center.notify(
        severity: WorkbenchNotificationSeverity.error,
        message: 'Explicitly silent error',
        priority: WorkbenchNotificationPriority.silent,
      );
      final urgent = center.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Urgent during Do Not Disturb',
        sourceId: 'fixture.named',
        priority: WorkbenchNotificationPriority.urgent,
      );
      final optional = center.notify(
        severity: WorkbenchNotificationSeverity.warning,
        message: 'Optional during Do Not Disturb',
        sourceId: 'fixture.named',
        priority: WorkbenchNotificationPriority.optional,
      );
      final error = center.notify(
        severity: WorkbenchNotificationSeverity.error,
        message: 'Normal error',
        sourceId: 'fixture.named',
      );
      expect(center.toastIds, [urgent.id, error.id]);
      expect(center.items, [error, optional, urgent, silent, firstUrgent]);
    });

    test('visible center consumes toasts and new unread state without replay',
        () {
      final center = NotificationCenter();
      final old = notify(center);
      final states = <(bool, int, List<int>)>[];
      center.addListener(() {
        states.add((center.centerVisible, center.unreadCount, center.toastIds));
      });

      center.setCenterVisible(true);
      center.setCenterVisible(true);
      final error = center.notify(
        severity: WorkbenchNotificationSeverity.error,
        priority: WorkbenchNotificationPriority.urgent,
        message: 'Error while center is open',
      );
      final banner = center.notify(
        severity: WorkbenchNotificationSeverity.warning,
        message: 'Banner uses its own surface',
        banner: true,
      );
      expect(center.items, [banner, error, old]);
      expect(center.banners, [banner]);

      center.setCenterVisible(false);
      final fresh = notify(center);
      expect(states.map((state) => (state.$1, state.$2)), [
        (true, 0),
        (true, 0),
        (true, 0),
        (false, 0),
        (false, 1),
      ]);
      expect(states.map((state) => state.$3), [
        [],
        [],
        [],
        [],
        [fresh.id],
      ]);
    });

    test('deleting the last entry closes the center without replay', () {
      final center = NotificationCenter();
      final notice = notify(center);
      center.setCenterVisible(true);

      center.dismiss(-1);
      expect(center.centerVisible, isTrue);
      expect(center.clearNotification(notice), isTrue);
      expect(center.centerVisible, isFalse);

      final next = notify(center);
      expect(center.toastIds, [next.id]);
      center.setCenterVisible(true);
      expect(center.clearAll(), 1);
      expect(center.centerVisible, isFalse);

      center.setCenterVisible(true);
      expect(center.clearAll(), 0);
      expect(center.centerVisible, isTrue);
    });

    test('disclosure changes only the owned collapsible notification', () {
      final center = NotificationCenter(maxNotifications: 2);
      final otherCenter = NotificationCenter();
      final notice = notify(center);
      final foreign = notify(otherCenter);
      final action = notify(
        center,
        actions: [WorkbenchNotificationAction(label: 'Run', run: () async {})],
      );
      expect(center.setExpanded(foreign, true), isFalse);
      expect(center.isExpanded(action), isTrue);
      expect(center.setExpanded(action, false), isFalse);
      expect(center.setExpanded(notice, true), isTrue);
      expect(center.setExpanded(notice, true), isFalse);
      expect(center.isExpanded(notice), isTrue);
      expect(center.items, [action, notice]);

      final fresh = notify(center);
      expect(center.setExpanded(notice, false), isFalse);
      expect(center.isExpanded(fresh), isFalse);
      expect(center.items, [fresh, action]);
    });

    test('a primary action dismisses its owner once and reports failure',
        () async {
      final center = NotificationCenter();
      final other = NotificationCenter();
      notify(other);
      final unrelated = notify(center);
      final completion = Completer<void>();
      var starts = 0;
      final action = WorkbenchNotificationAction(
        label: 'Retry',
        run: () {
          starts++;
          return completion.future;
        },
      );
      final notice = center.notify(
        severity: WorkbenchNotificationSeverity.warning,
        message: 'Original notice',
        source: 'Fixture',
        sourceId: 'fixture.primary',
        actions: [action],
      );
      final foreign = notify(other, actions: [action]);
      expect(foreign.id, notice.id);
      await center.runPrimaryAction(foreign, action);
      expect(starts, 0);
      final pending = center.runPrimaryAction(notice, action);
      expect(center.items, [unrelated]);
      await center.runPrimaryAction(notice, action);
      expect(starts, 1);

      completion.completeError(StateError('fixture failure'));
      await pending;
      expect(
          center.items.map((item) => item.id), [notice.id + 1, unrelated.id]);
      final failure = center.items.first;
      expect(failure.severity, WorkbenchNotificationSeverity.error);
      expect(failure.message, contains('fixture failure'));
      expect(failure.source, notice.source);
      expect(failure.sourceId, notice.sourceId);
    });

    test('keep-open primary actions retain their notification', () async {
      final center = NotificationCenter();
      var starts = 0;
      final action = WorkbenchNotificationAction(
        label: 'Retry',
        keepOpen: true,
        run: () async => starts++,
      );
      final notice = notify(center, actions: [action]);
      await center.runPrimaryAction(notice, action);
      expect(starts, 1);
      expect(center.items, [notice]);
      expect(center.toastIds, [notice.id]);
    });

    test('late action failure after center disposal has no recipient',
        () async {
      final center = NotificationCenter();
      final completion = Completer<void>();
      final action = WorkbenchNotificationAction(
        label: 'Retry',
        run: () => completion.future,
      );
      final notice = notify(center, actions: [action]);
      final pending = center.runPrimaryAction(notice, action);
      center.dispose();
      completion.completeError(StateError('late failure'));
      await pending;
    });

    test('markRead and markAllRead clear unread state', () {
      final center = NotificationCenter();
      final first = notify(center);
      notify(center);
      center.markRead(first.id);
      expect(center.unreadCount, 1);
      center.markAllRead();
      expect(center.unreadCount, 0);
      expect(center.hasUnread, isFalse);
    });

    test('list is bounded to maxNotifications and drops the oldest', () {
      final center = NotificationCenter(maxNotifications: 3);
      for (var i = 0; i < 5; i++) {
        notify(center, message: 'm$i');
      }
      expect(center.items.map((n) => n.message).toList(), ['m4', 'm3', 'm2']);
    });

    test('sources and filtered narrow the list', () {
      final center = NotificationCenter();
      notify(center, source: 'Alula');
      notify(center, source: 'Rust');
      notify(center, source: 'Alula');
      expect(center.sources, ['Alula', 'Rust']);
      expect(center.filtered().length, 3);
      expect(center.filtered('Alula').length, 2);
      expect(center.filtered('Rust').length, 1);
      expect(center.filtered('missing'), isEmpty);
    });

    test('byId finds notifications and severity is preserved', () {
      final center = NotificationCenter();
      final notification = notify(center,
          severity: WorkbenchNotificationSeverity.error, message: 'boom');
      expect(center.byId(notification.id)!.severity,
          WorkbenchNotificationSeverity.error);
      expect(center.byId(999), isNull);
    });
  });
}
