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
