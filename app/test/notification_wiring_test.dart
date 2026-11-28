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
    temp = await Directory.systemTemp.createTemp('alula_notification_wiring');
    final root = temp.path.replaceAll(r'\', '/');
    layoutStore = LayoutStore(path: '$root/layout.json');
    sessionStore = SessionStore(path: '$root/session.json');
    notifications = NotificationCenter();
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  testWidgets('journal write failure notifies once per failure streak',
      (tester) async {
    final root = temp.path.replaceAll(r'\', '/');
    // 让 journal 的目标路径是一个目录：SessionStore.save 必然失败。
    Directory('$root/journal-as-directory').createSync();
    final brokenSession = SessionStore(path: '$root/journal-as-directory');

    await tester.pumpWidget(AlulaApp(
      layoutStore: layoutStore,
      sessionStore: brokenSession,
      notificationCenter: notifications,
    ));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 700));

    Future<void> toggleSidebar() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 700));
    }

    await toggleSidebar();
    await toggleSidebar();

    final notices = notifications.items
        .where((n) => n.source == '工作台')
        .toList(growable: false);
    expect(notices.length, 1, reason: '同一失败 streak 内只通知一次');
    expect(notices.single.message, contains('会话 journal 写入失败'));
    expect(notices.single.severity, WorkbenchNotificationSeverity.warning);
    expect(notices.single.actions.single.label, '重试保存会话');
    expect(
      find.byKey(ValueKey('notification-toast-${notices.single.id}')),
      findsOneWidget,
    );

    // 重试动作仍失败，但不产生第二条通知。
    await tester.tap(find
        .byKey(ValueKey('notification-toast-action-${notices.single.id}-0')));
    await tester.pump(const Duration(milliseconds: 700));
    expect(
      notifications.items.where((n) => n.source == '工作台').length,
      1,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('read-only save failure notifies with a save-as action',
      (tester) async {
    final root = temp.path.replaceAll(r'\', '/');
    final workspace = Directory('$root/wiring-workspace')..createSync();
    final file = File('${workspace.path}/note.txt')
      ..writeAsStringSync('seed\n');
    addTearDown(() async {
      if (file.existsSync()) await _setFileReadOnly(file, false);
    });

    await tester.runAsync(() async {
      await tester.pumpWidget(AlulaApp(
        autoFolder: workspace.path,
        layoutStore: layoutStore,
        sessionStore: sessionStore,
        notificationCenter: notifications,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await tester.pump();
      await tester.tap(find.text('note.txt').first);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();

      await _setFileReadOnly(file, true);
      await tester.enterText(find.byType(TextField).first, 'edited\n');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 350));

      final failures =
          notifications.items.where((n) => n.source == '文件').toList();
      expect(failures.length, 1);
      expect(failures.single.severity, WorkbenchNotificationSeverity.error);
      expect(failures.single.message, contains('保存'));
      expect(failures.single.actions.single.label, '另存为…');
      // 既有反馈保持不变：磁盘字节未改、状态栏/横幅仍提示只读，仍提供另存为入口。
      expect(file.readAsStringSync(), 'seed\n');
      expect(find.textContaining('只读文件'), findsOneWidget);
      expect(find.byKey(const ValueKey('external-save-as')), findsWidgets);

      // 同一文档同一错误码再次失败不重复通知。
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 350));
      expect(notifications.items.where((n) => n.source == '文件').length, 1);

      // 通知动作能打开既有另存为对话框。
      await tester.tap(find.byKey(
          ValueKey('notification-toast-action-${failures.single.id}-0')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('save-as-path')), findsOneWidget);
      expect(notifications.byId(failures.single.id), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('save-as-path')), findsNothing);
    });

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

Future<void> _setFileReadOnly(File file, bool value) async {
  final result = Platform.isWindows
      ? await Process.run('attrib', [value ? '+R' : '-R', file.path])
      : await Process.run('chmod', [value ? 'a-w' : 'u+w', file.path]);
  if (result.exitCode != 0) {
    throw StateError('设置只读属性失败：${result.stderr}');
  }
}
