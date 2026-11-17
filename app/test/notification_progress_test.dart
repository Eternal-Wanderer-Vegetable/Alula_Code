import 'dart:async';

import 'package:alula_app/workbench/notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationProgress', () {
    test('determinate progress reports fraction, percent and updates', () {
      final progress = NotificationProgress(total: 10, worked: 4);
      expect(progress.isDeterminate, isTrue);
      expect(progress.fraction, closeTo(0.4, 1e-9));
      expect(progress.percent, 40);
      var changes = 0;
      progress.addListener(() => changes += 1);
      progress.report(worked: 8);
      expect(progress.percent, 80);
      expect(changes, 1);
      progress.report(worked: 12);
      expect(progress.fraction, 1.0, reason: '超过总量时钳制到 1');
      expect(changes, 2);
    });

    test('infinite progress has no fraction until a total is reported', () {
      final progress = NotificationProgress(worked: 3, infinite: true);
      expect(progress.isDeterminate, isFalse);
      expect(progress.fraction, isNull);
      expect(progress.percent, isNull);
      progress.report(infinite: false, total: 6);
      expect(progress.fraction, closeTo(0.5, 1e-9));
    });

    test('cancel only exists with a callback and is single-flight', () async {
      final plain = NotificationProgress(total: 1);
      expect(plain.cancellable, isFalse);
      await plain.cancel();

      var cancels = 0;
      final finishCancellation = Completer<void>();
      final cancellable = NotificationProgress(
        total: 5,
        onCancel: () {
          cancels += 1;
          return finishCancellation.future;
        },
      );
      final firstCancel = cancellable.cancel();
      expect(cancellable.cancellationPending, isTrue);
      expect(cancellable.cancellable, isFalse);
      await cancellable.cancel();
      expect(cancels, 1);
      finishCancellation.complete();
      await firstCancel;
      expect(cancellable.cancellable, isTrue);
    });

    test('failed cancellation can be retried and done is terminal', () async {
      var cancels = 0;
      final progress = NotificationProgress(
        total: 2,
        onCancel: () async {
          cancels++;
          if (cancels == 1) throw StateError('cancel failed');
        },
      );
      await expectLater(progress.cancel(), throwsStateError);
      expect(progress.cancellable, isTrue);
      await progress.cancel();
      expect(cancels, 2);

      var changes = 0;
      progress.addListener(() => changes++);
      progress.done();
      expect(progress.isDone, isTrue);
      expect(progress.cancellable, isFalse);
      progress.report(worked: 2);
      progress.done();
      expect(progress.worked, 0, reason: 'done rejects late progress reports');
      expect(changes, 1);
    });
  });

  group('NotificationCenter progress and banners', () {
    test('progress notifications stay in the center and toast stack', () {
      final center = NotificationCenter();
      final progress = NotificationProgress(total: 4, worked: 1);
      final notification = center.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: '正在索引',
        progress: progress,
      );
      expect(notification.hasProgress, isTrue);
      expect(center.byId(notification.id)!.progress, same(progress));
      expect(center.items.length, 1);
      expect(center.toastIds, [notification.id]);
      expect(center.banners, isEmpty);
    });

    test('banner notifications skip toasts and are bounded', () {
      final center = NotificationCenter();
      center.notify(
        severity: WorkbenchNotificationSeverity.warning,
        message: '需要信任此工作区',
        banner: true,
      );
      expect(center.banners.length, 1);
      expect(center.banners.first.banner, isTrue);
      expect(center.toastIds, isEmpty);

      for (var i = 0; i < NotificationCenter.maxVisibleBanners + 2; i++) {
        center.notify(
          severity: WorkbenchNotificationSeverity.info,
          message: 'banner $i',
          banner: true,
        );
      }
      expect(center.banners.length, NotificationCenter.maxVisibleBanners);
      expect(center.banners.last.message,
          'banner ${NotificationCenter.maxVisibleBanners + 1}');
    });

    test('banners stay visible under do not disturb', () {
      final center = NotificationCenter();
      center.setDoNotDisturb(true);
      center.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'banner under DND',
        banner: true,
      );
      center.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'toast under DND',
      );
      expect(center.banners.length, 1);
      expect(center.toastIds, isEmpty);
    });

    test('dismiss and clearAll remove banners with the notifications', () {
      final center = NotificationCenter();
      final banner = center.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'banner',
        banner: true,
      );
      center.dismiss(banner.id);
      expect(center.banners, isEmpty);
      expect(center.isEmpty, isTrue);

      center.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'banner 2',
        banner: true,
      );
      center.clearAll();
      expect(center.banners, isEmpty);
    });
  });
}
