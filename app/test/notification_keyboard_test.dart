import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/notifications.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    testWidgets('$platform clears only the focused notification center row',
        (tester) async {
      await _withWorkbench(tester, platform, (center) async {
        final older = _notify(center, 'Earlier notice');
        _notify(center, 'Initially focused notice');
        await tester.pump();
        await _showCenter(tester);

        // Keep the same item focused when a new row is inserted above it.
        final newer = _notify(center, 'New arrival');
        await tester.pump();
        await tester.sendKeyEvent(platform == TargetPlatform.macOS
            ? LogicalKeyboardKey.delete
            : LogicalKeyboardKey.backspace);
        await tester.pump();
        expect(center.items, hasLength(3));

        if (platform == TargetPlatform.macOS) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        } else {
          await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        }
        await tester.pump();
        expect(center.items, [newer, older]);
        expect(find.text('Initially focused notice'), findsNothing);
      });
    });
  }

  testWidgets('toast shortcut protects running progress and clears after done',
      (tester) async {
    final progress = NotificationProgress(total: 10, worked: 1);
    addTearDown(progress.dispose);
    await _withWorkbench(tester, TargetPlatform.windows, (center) async {
      final other = _notify(center, 'Unrelated toast');
      final running = _notify(center, 'Running toast', progress: progress);
      await tester.pump();

      Focus.of(tester.element(find.text('Running toast'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(center.items, [running, other]);

      progress.done();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(center.items, [other]);
      expect(center.toastIds, [other.id]);
      expect(center.unreadCount, 1);
    });
  });

  testWidgets('a toast removed before repaint cannot clear its retained item',
      (tester) async {
    await _withWorkbench(tester, TargetPlatform.linux, (center) async {
      final toast = _notify(center, 'Retained notice');
      await tester.pump();
      final focus = Focus.of(tester.element(find.text('Retained notice')));
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasPrimaryFocus, isTrue);

      center.dismissToast(toast.id);
      expect(focus.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(center.items, [toast]);
      expect(center.toastIds, isEmpty);
      expect(center.unreadCount, 1);
    });
  });

  testWidgets('a new notification does not steal focus from the editor',
      (tester) async {
    await _withWorkbench(tester, TargetPlatform.linux, (center) async {
      await _showCenter(tester);
      final field = find.descendant(
        of: find.byType(RustTextInputField).first,
        matching: find.byType(TextField),
      );
      final focus = tester.widget<TextField>(field).focusNode!;
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasPrimaryFocus, isTrue);

      _notify(center, 'Late arrival');
      await tester.pump();
      await tester.pump();
      expect(focus.hasPrimaryFocus, isTrue);
    });
  });

  testWidgets(
      'user keybinding replaces the default and stays out of the editor',
      (tester) async {
    await _withWorkbench(tester, TargetPlatform.linux, (center) async {
      final editable = find.byType(RustTextInputField).first;
      final field =
          find.descendant(of: editable, matching: find.byType(TextField));
      await tester.enterText(field, 'abcd');
      await tester.pump(const Duration(milliseconds: 150));

      final notice = _notify(center, 'Rebound notice');
      await tester.pump();
      await _showCenter(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(center.items, [notice]);

      final editor = tester.widget<TextField>(field);
      editor.focusNode!.requestFocus();
      editor.controller!.selection = const TextSelection.collapsed(offset: 1);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        tester
            .widget<RustTextInputField>(editable)
            .inputWindow
            .document
            .resync()
            .content,
        'acd',
      );
      expect(center.items, [notice]);
      await _sendReboundChord(tester);
      expect(center.items, [notice]);

      Focus.of(tester.element(find.text('Rebound notice'))).requestFocus();
      await tester.pump();
      await _sendReboundChord(tester);
      expect(center.items, isEmpty);
    }, keybindings: '[{"key":"alt+f10","command":"notification.clear"}]');
  });
}

WorkbenchNotification _notify(
  NotificationCenter center,
  String message, {
  NotificationProgress? progress,
}) =>
    center.notify(
      severity: WorkbenchNotificationSeverity.info,
      message: message,
      progress: progress,
    );

Future<void> _showCenter(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('status-notifications')));
  await tester.pump();
  await tester.pump();
}

Future<void> _sendReboundChord(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.f10);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  await tester.pump();
}

Future<void> _withWorkbench(
  WidgetTester tester,
  TargetPlatform platform,
  Future<void> Function(NotificationCenter) run, {
  String? keybindings,
}) async {
  final temp = Directory.systemTemp.createTempSync('alula_notification_keys');
  final center = NotificationCenter();
  final keys = File('${temp.path}/keys.json');
  if (keybindings != null) keys.writeAsStringSync(keybindings);
  debugDefaultTargetPlatformOverride = platform;
  try {
    await tester.pumpWidget(AlulaApp(
      layoutStore: LayoutStore(path: '${temp.path}/layout.json'),
      sessionStore: SessionStore(path: '${temp.path}/session.json'),
      keybindingsStore: KeybindingsStore(path: keys.path),
      notificationCenter: center,
    ));
    await tester.pump(const Duration(milliseconds: 300));
    await run(center);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
    temp.deleteSync(recursive: true);
  }
}
