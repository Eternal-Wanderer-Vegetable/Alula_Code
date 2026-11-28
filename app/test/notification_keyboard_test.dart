import 'dart:async';
import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/notification_widgets.dart';
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

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    testWidgets(
        '$platform opens the center with a chord and restores the editor',
        (tester) async {
      await _withWorkbench(tester, platform, (center) async {
        final editorFocus = _editorFocus(tester);
        editorFocus.requestFocus();
        await tester.pump();
        final notice = _notify(center, 'Notice for the default shortcut');
        await tester.pump();

        await _sendShowNotificationChord(tester, platform);
        expect(center.centerVisible, isTrue);
        expect(center.toastIds, isEmpty);
        expect(focusedWorkbenchNotification()?.notification, same(notice));

        // The fixed show command is idempotent, including outside the editor.
        await _sendShowNotificationChord(tester, platform);
        expect(center.centerVisible, isTrue);
        expect(focusedWorkbenchNotification()?.notification, same(notice));

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.pump();
        expect(center.centerVisible, isFalse);
        expect(center.items, [notice]);
        expect(editorFocus.hasPrimaryFocus, isTrue);
      });
    });
  }

  testWidgets('the show chord is available outside the editor', (tester) async {
    await _withWorkbench(tester, TargetPlatform.windows, (center) async {
      final editorFocus = _editorFocus(tester);
      final bell = find.byKey(const ValueKey('status-notifications'));
      Focus.of(tester.element(bell)).requestFocus();
      await tester.pump();
      expect(editorFocus.hasPrimaryFocus, isFalse);
      _notify(center, 'Notice while workbench chrome has focus');
      await tester.pump();

      await _sendShowNotificationChord(tester, TargetPlatform.windows);
      expect(center.centerVisible, isTrue);
    });
  });

  testWidgets('Escape hides toasts and restores focus from a toast action',
      (tester) async {
    await _withWorkbench(tester, TargetPlatform.windows, (center) async {
      final editorFocus = _editorFocus(tester);
      final item = _notify(center, 'Toast focused before Escape');
      await tester.pump();

      Focus.of(tester.element(find.text(item.message))).requestFocus();
      await tester.pump();
      expect(focusedWorkbenchNotification()?.notification, same(item));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump();
      expect(center.toastIds, isEmpty);
      expect(center.items, [item]);
      expect(editorFocus.hasPrimaryFocus, isTrue);
    });
  });

  testWidgets('unfocused toast Escape gives editor Find the first dismissal',
      (tester) async {
    await _withWorkbench(tester, TargetPlatform.windows, (center) async {
      final query = await _showEditorFind(tester);
      final item = _notify(center, 'Toast while Find is focused');
      await tester.pump();
      expect(query, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(query, findsNothing);
      expect(center.toastIds, [item.id]);
      expect(_editorFocus(tester).hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(center.toastIds, isEmpty);
      expect(center.items, [item]);
    });
  });

  testWidgets('center Escape takes priority over editor Find', (tester) async {
    await _withWorkbench(tester, TargetPlatform.windows, (center) async {
      _notify(center, 'Center notice while Find is focused');
      await tester.pump();
      await _showCenter(tester);
      final query = await _showEditorFind(tester);
      expect(center.centerVisible, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(center.centerVisible, isFalse);
      expect(query, findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(query, findsNothing);
    });
  });

  testWidgets('the custom center key suppresses the old chord', (tester) async {
    await _withWorkbench(tester, TargetPlatform.windows, (center) async {
      _editorFocus(tester).requestFocus();
      await tester.pump();
      _notify(center, 'Notice for a rebound shortcut');
      await tester.pump();

      await _sendShowNotificationChord(tester, TargetPlatform.windows);
      expect(center.centerVisible, isFalse);
      await _sendReboundChord(tester);
      expect(center.centerVisible, isTrue);
    }, keybindings: '[{"key":"alt+f10","command":"notifications.showList"}]');
  });

  testWidgets('toast focus commands navigate newest to oldest and hand off',
      (tester) async {
    await _withWorkbench(tester, TargetPlatform.windows, (center) async {
      final first = _notify(center, 'Oldest toast');
      final second = _notify(center, 'Middle toast');
      final third = _notify(center, 'Newest toast');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      final palette = find.byKey(const ValueKey('quick-input'));
      await tester.enterText(
        find.descendant(of: palette, matching: find.byType(TextField)),
        '聚焦通知弹窗',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('qi-查看: 聚焦通知弹窗')));
      await tester.pumpAndSettle();
      expect(focusedWorkbenchNotification()?.notification, same(third));
      expect(focusedWorkbenchNotification()?.isToast, isTrue);

      Color borderColor(WorkbenchNotification notice) {
        final frame =
            find.byKey(ValueKey('notification-toast-frame-${notice.id}'));
        final decoration =
            tester.widget<Container>(frame).decoration! as BoxDecoration;
        return (decoration.border! as Border).top.color;
      }

      final focusColor = Theme.of(tester.element(find.text(third.message)))
          .colorScheme
          .primary;
      expect(borderColor(third), focusColor);
      expect(borderColor(second), isNot(focusColor));

      Future<void> expectFocus(
          LogicalKeyboardKey key, WorkbenchNotification notice) async {
        await tester.sendKeyEvent(key);
        await tester.pump();
        await tester.pump();
        expect(focusedWorkbenchNotification()?.notification, same(notice));
        expect(borderColor(notice), focusColor);
      }

      await expectFocus(LogicalKeyboardKey.arrowUp, third);
      await expectFocus(LogicalKeyboardKey.arrowDown, second);
      await expectFocus(LogicalKeyboardKey.arrowDown, first);
      await expectFocus(LogicalKeyboardKey.arrowDown, first);
      await expectFocus(LogicalKeyboardKey.home, third);
      await expectFocus(LogicalKeyboardKey.end, first);
      await expectFocus(LogicalKeyboardKey.pageUp, third);
      await expectFocus(LogicalKeyboardKey.pageDown, first);
      await expectFocus(LogicalKeyboardKey.arrowUp, second);

      await expectFocus(LogicalKeyboardKey.delete, first);
      expect(center.items, [third, first]);
      await expectFocus(LogicalKeyboardKey.delete, third);
      expect(center.items, [third]);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      await tester.pump();
      expect(center.items, isEmpty);
      expect(focusedWorkbenchNotification(), isNull);
      expect(_editorFocus(tester).hasPrimaryFocus, isTrue);
    });
  });

  testWidgets('removing a different toast preserves focus on the current one',
      (tester) async {
    await _withWorkbench(tester, TargetPlatform.windows, (center) async {
      final oldest = _notify(center, 'Toast before focused item');
      final selected = _notify(center, 'Toast retaining focus');
      _notify(center, 'Toast after focused item');
      await tester.pump();
      final node = Focus.of(tester.element(find.text(selected.message)));
      node.requestFocus();
      await tester.pump();

      center.dismissToast(oldest.id);
      await tester.pump();
      expect(focusedWorkbenchNotification()?.notification, same(selected));
      expect(center.items, hasLength(3));
      expect(center.toastIds, hasLength(2));
    });
  });

  testWidgets('notification disclosure keys are shared by toast and center',
      (tester) async {
    await _withWorkbench(tester, TargetPlatform.windows, (center) async {
      final notice = _notify(center, 'Message with a disclosure row');
      await tester.pump();

      Finder message() => find.text(notice.message);
      int? lines() => tester.widget<Text>(message()).maxLines;
      Focus.of(tester.element(message())).requestFocus();
      await tester.pump();
      expect(lines(), 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(lines(), isNull);
      expect(find.text('来源：Alula'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(lines(), 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(lines(), isNull);

      await _showCenter(tester);
      expect(lines(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(lines(), 1);
      await tester.tap(message());
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(message());
      await tester.pump(const Duration(milliseconds: 50));
      expect(lines(), isNull);
    });
  });

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
  testWidgets(
      'fixed notification command IDs and old bindings use the same actions',
      (tester) async {
    final progress = NotificationProgress(total: 8);
    addTearDown(progress.dispose);
    await _withWorkbench(tester, TargetPlatform.windows, (center) async {
      Future<void> press(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.pump();
      }

      final active = _notify(center, 'Active job', progress: progress);
      _notify(center, 'Read report');
      await tester.pump();
      await _showCenter(tester);
      await press(LogicalKeyboardKey.f8);
      expect(center.centerVisible, isFalse);
      expect(center.items, [active]);

      await press(LogicalKeyboardKey.f10);
      expect(center.doNotDisturb, isTrue);
      final quiet = _notify(center, 'Quiet notification');
      await tester.pump();
      expect(center.toastIds, isEmpty);

      await press(LogicalKeyboardKey.f11);
      expect(center.doNotDisturb, isFalse);
      final visible = _notify(center, 'Ordinary notification again');
      await tester.pump();
      expect(center.toastIds, [visible.id]);
      expect(center.items, [visible, quiet, active]);

      progress.done();
      await press(LogicalKeyboardKey.f9);
      expect(center.items, isEmpty);
    }, keybindings: '''
[
  {"key":"alt+f8","command":"notifications.clearAll"},
  {"key":"alt+f9","command":"workbench.action.clearNotifications"},
  {"key":"alt+f10","command":"notifications.toggleDoNotDisturbMode"},
  {"key":"alt+f11","command":"workbench.action.toggleNotificationsDoNotDisturb"}
]
''');
  });
  testWidgets(
      'notification command accepts the first action of its focused row',
      (tester) async {
    await _withWorkbench(tester, TargetPlatform.windows, (center) async {
      final handled = <String>[];
      WorkbenchNotification add(String message, {bool keepOpen = false}) {
        return center.notify(
          severity: WorkbenchNotificationSeverity.info,
          message: message,
          actions: [
            WorkbenchNotificationAction(
              label: 'First',
              keepOpen: keepOpen,
              run: () async => handled.add('$message first'),
            ),
            WorkbenchNotificationAction(
              label: 'Second',
              run: () async => handled.add('$message second'),
            ),
          ],
        );
      }

      final older = add('Older action');
      final latest = add('Latest action');
      await tester.pump();
      await _showCenter(tester);
      Focus.of(tester.element(find.text(older.message))).requestFocus();
      await tester.pump();
      expect(focusedWorkbenchNotification()?.notification, same(older));
      await _sendReboundChord(tester);
      expect(handled, ['Older action first']);
      expect(center.items, [latest]);

      await tester.tap(find.byKey(const ValueKey('notification-center-close')));
      await tester.pump();
      _editorFocus(tester).requestFocus();
      final plain = _notify(center, 'Newer without actions');
      await tester.pump();
      await _sendReboundChord(tester);
      expect(handled, ['Older action first']);
      expect(center.items, [plain, latest]);

      center.dismiss(plain.id);
      await tester.pump();
      await _sendReboundChord(tester);
      expect(handled, ['Older action first', 'Latest action first']);
      expect(center.items, isEmpty);

      final keep = add('Explicitly kept action', keepOpen: true);
      await tester.pump();
      await _sendReboundChord(tester);
      expect(handled.last, 'Explicitly kept action first');
      expect(center.items, [keep]);
    },
        keybindings:
            '[{"key":"alt+f10","command":"notification.acceptPrimaryAction"}]');
  });
  testWidgets('default primary action key checks the reader and current focus',
      (tester) async {
    const channel = MethodChannel('alula/accessibility');
    final messenger = tester.binding.defaultBinaryMessenger;
    var enabled = false;
    var queries = 0;
    Completer<bool>? pending;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'screenReaderEnabled');
      queries++;
      return pending == null ? enabled : await pending!.future;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    Future<void> press() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    await _withWorkbench(tester, TargetPlatform.windows, (center) async {
      var actions = 0;
      final notice = center.notify(
        severity: WorkbenchNotificationSeverity.info,
        message: 'Primary shortcut action',
        actions: [
          WorkbenchNotificationAction(
            label: 'First action',
            run: () async => actions++,
          ),
        ],
      );
      _editorFocus(tester).requestFocus();
      await tester.pump();
      await press();
      expect(queries, 1);
      expect(actions, 0);
      expect(center.items, [notice]);

      final answer = pending = Completer<bool>();
      await press();
      expect(queries, 2);
      await _showCenter(tester);
      expect(focusedWorkbenchNotification()?.notification, same(notice));
      pending = null;
      enabled = true;
      answer.complete(true);
      await tester.pump();
      expect(actions, 0);
      expect(center.items, [notice]);

      await press();
      expect(queries, 3);
      expect(actions, 1);
      expect(center.items, isEmpty);
      await press();
      expect(queries, 3);
    });
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

Future<Finder> _showEditorFind(WidgetTester tester) async {
  _editorFocus(tester).requestFocus();
  await tester.pump();
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();

  final query = find.byKey(const ValueKey('find-query-input'));
  await tester.tap(query);
  await tester.pump();
  final editable = find.descendant(
    of: query,
    matching: find.byType(EditableText),
  );
  expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
  return query;
}

FocusNode _editorFocus(WidgetTester tester) {
  final field = find.descendant(
    of: find.byType(RustTextInputField).first,
    matching: find.byType(TextField),
  );
  return tester.widget<TextField>(field).focusNode!;
}

Future<void> _sendShowNotificationChord(
    WidgetTester tester, TargetPlatform platform) async {
  final modifier = platform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(modifier);
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
