import 'dart:convert';
import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

/// 测试工作台状态持有者：集中管理目录/store，避免 late 局部变量被闭包
/// 捕获后的确定性赋值分析报错。
class _Harness {
  Directory? temp;
  Directory? workspace;
  LayoutStore? layoutStore;
  SessionStore? sessionStore;
  CommandService? commands;

  String get base => temp!.path.replaceAll(r'\', '/');

  Future<void> prepare({required String workspaceRoot}) async {
    temp = Directory.systemTemp.createTempSync('alula-locked-scroll');
    workspace = Directory('${temp!.path}/workspace')..createSync();
    layoutStore = LayoutStore(path: '$base/layout.json');
    sessionStore = SessionStore(path: '$base/session.json');
  }

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(2400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: WorkbenchPage(
        autoFolder: workspace!.path,
        layoutStore: layoutStore!,
        sessionStore: sessionStore!,
        keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
        onCommandServiceReady: (service) => commands = service,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    expect(commands, isNotNull);
  }

  Future<void> disposeWorkbench(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }
}

RustTextInputField _fieldForDocument(WidgetTester tester, int documentId) =>
    tester
        .widgetList<RustTextInputField>(find.byType(RustTextInputField))
        .firstWhere(
          (field) => field.inputWindow.document.id == documentId,
        );

ScrollController _horizontalController(
  WidgetTester tester,
  RustTextInputField field,
) {
  final viewport = find.descendant(
    of: find.byWidget(field),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    ),
  );
  return tester.widget<SingleChildScrollView>(viewport).controller!;
}

void main() {
  late _Harness h;
  final statusEntry = find.byKey(const ValueKey('status-bar-locked-scrolling'));

  /// Seeds two horizontal groups: alpha（120 行）与 beta（60 行），长度
  /// 不同以便观察滚动位移。
  Future<void> seedTwoGroups(WidgetTester tester, _Harness harness,
      {bool wideLines = false}) async {
    final alpha = StringBuffer();
    if (wideLines) alpha.writeln(List.filled(470, "a").join());
    for (var i = 0; i < 120; i++) {
      alpha.writeln('alpha line $i');
    }
    final beta = StringBuffer();
    if (wideLines) beta.writeln(List.filled(310, "b").join());
    for (var i = 0; i < 60; i++) {
      beta.writeln('beta line $i');
    }
    final alphaFile = File('${harness.workspace!.path}/alpha.txt')
      ..writeAsStringSync(alpha.toString());
    final betaFile = File('${harness.workspace!.path}/beta.txt')
      ..writeAsStringSync(beta.toString());
    final layout = defaultLayout();
    layout.splitLeaf('editor', 'editor-2', Axis.horizontal);
    harness.layoutStore!.save(layout);
    File('${harness.base}/session.json').writeAsStringSync(jsonEncode({
      'v': 1,
      'editorTabMode': 'multiple',
      'focused': 'editor-2',
      'groups': [
        {
          'region': 'editor',
          'docs': [
            {'id': 10, 'path': alphaFile.path},
          ],
          'active': 10,
        },
        {
          'region': 'editor-2',
          'docs': [
            {'id': 11, 'path': betaFile.path},
          ],
          'active': 11,
        },
      ],
    }));
  }

  testWidgets(
    'locked scrolling preserves each visible pane anchor with unequal extents',
    (tester) async {
      h = _Harness();
      await h.prepare(workspaceRoot: 'unused');
      await seedTwoGroups(tester, h);
      await h.mount(tester);

      final alpha = _fieldForDocument(tester, 10).scrollController!;
      final beta = _fieldForDocument(tester, 11).scrollController!;
      alpha.jumpTo(250);
      beta.jumpTo(100);
      await tester.pumpAndSettle();
      await h.commands!.execute('workbench.action.toggleLockedScrolling');
      await tester.pumpAndSettle();
      expect(alpha.offset, 250);
      expect(beta.offset, 100);

      alpha.jumpTo(320);
      await tester.pumpAndSettle();
      expect(beta.offset, 170);
      beta.jumpTo(50);
      await tester.pumpAndSettle();
      expect(alpha.offset, 200);

      alpha.jumpTo(alpha.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(beta.offset, beta.position.maxScrollExtent);
      alpha.jumpTo(250);
      await tester.pumpAndSettle();
      expect(beta.offset, 100);

      await h.commands!.execute('workbench.action.toggleLockedScrolling');
      await tester.pumpAndSettle();
      alpha.jumpTo(0);
      await tester.pumpAndSettle();
      expect(beta.offset, 100);
      await h.disposeWorkbench(tester);
    },
  );

  testWidgets('locked scrolling rebases when same-document split views appear',
      (tester) async {
    h = _Harness();
    await h.prepare(workspaceRoot: 'unused');
    await seedTwoGroups(tester, h);
    await h.mount(tester);
    final alpha = _fieldForDocument(tester, 10).scrollController!;
    final beta = _fieldForDocument(tester, 11).scrollController!;
    alpha.jumpTo(150);
    beta.jumpTo(70);
    await tester.pumpAndSettle();
    await h.commands!.execute('workbench.action.toggleLockedScrolling');
    await tester.pumpAndSettle();

    await h.commands!.execute('workbench.action.splitEditorInGroup');
    await tester.pumpAndSettle();
    final views = tester
        .widgetList<RustTextInputField>(find.byType(RustTextInputField))
        .where((field) => field.inputWindow.document.id == 11)
        .map((field) => field.scrollController!)
        .toList();
    expect(views, hasLength(2));
    final source = views.first;
    final peer = views.last;
    final alphaBefore = alpha.offset;
    final peerBefore = peer.offset;
    final move = source.offset + 60;
    expect(move, lessThan(source.position.maxScrollExtent));
    source.jumpTo(move);
    await tester.pumpAndSettle();
    expect(alpha.offset, alphaBefore + 60);
    expect(peer.offset, peerBefore + 60);

    await h.commands!.execute('workbench.action.joinEditorInGroup');
    await tester.pumpAndSettle();
    final remaining = _fieldForDocument(tester, 11).scrollController!;
    final alphaRebased = alpha.offset;
    final remainingBefore = remaining.offset;
    remaining.jumpTo(remainingBefore + 30);
    await tester.pumpAndSettle();
    expect(alpha.offset, alphaRebased + 30);
    expect(tester.takeException(), isNull);
    await h.disposeWorkbench(tester);
  });

  testWidgets('locked scrolling applies both axes from independent origins',
      (tester) async {
    h = _Harness();
    await h.prepare(workspaceRoot: 'unused');
    await seedTwoGroups(tester, h, wideLines: true);
    await h.mount(tester);
    final alpha = _fieldForDocument(tester, 10);
    final beta = _fieldForDocument(tester, 11);
    final alphaX = _horizontalController(tester, alpha);
    final betaX = _horizontalController(tester, beta);
    final alphaY = alpha.scrollController!;
    final betaY = beta.scrollController!;
    expect(alphaX.position.maxScrollExtent,
        greaterThan(betaX.position.maxScrollExtent + 150));
    expect(betaX.position.maxScrollExtent, greaterThan(150));
    alphaX.jumpTo(140);
    betaX.jumpTo(45);
    alphaY.jumpTo(250);
    betaY.jumpTo(100);
    await tester.pumpAndSettle();

    await h.commands!.execute('workbench.action.toggleLockedScrolling');
    await tester.pumpAndSettle();
    expect([alphaX.offset, betaX.offset], [140, 45]);
    alphaX.jumpTo(210);
    await tester.pumpAndSettle();
    expect(betaX.offset, 115);
    expect([alphaY.offset, betaY.offset], [250, 100]);
    betaX.jumpTo(20);
    await tester.pumpAndSettle();
    expect(alphaX.offset, 115);

    alphaY.jumpTo(320);
    await tester.pumpAndSettle();
    expect(betaY.offset, 170);
    expect([alphaX.offset, betaX.offset], [115, 20]);

    alphaX.jumpTo(alphaX.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(betaX.offset, betaX.position.maxScrollExtent);
    alphaX.jumpTo(140);
    await tester.pumpAndSettle();
    expect(betaX.offset, 45);

    await h.commands!.execute('workbench.action.toggleLockedScrolling');
    await tester.pumpAndSettle();
    betaX.jumpTo(80);
    await tester.pumpAndSettle();
    expect(alphaX.offset, 140);
    await h.disposeWorkbench(tester);
  });

  testWidgets('horizontal anchors follow separate split views and rejoin',
      (tester) async {
    h = _Harness();
    await h.prepare(workspaceRoot: 'unused');
    await seedTwoGroups(tester, h, wideLines: true);
    await h.mount(tester);
    final alpha = _horizontalController(tester, _fieldForDocument(tester, 10));
    alpha.jumpTo(130);
    await tester.pumpAndSettle();

    await h.commands!.execute('workbench.action.toggleLockedScrolling');
    await h.commands!.execute('workbench.action.splitEditorInGroup');
    await tester.pumpAndSettle();
    final sameDocument = tester
        .widgetList<RustTextInputField>(find.byType(RustTextInputField))
        .where((field) => field.inputWindow.document.id == 11)
        .map((field) => _horizontalController(tester, field))
        .toList();
    expect(sameDocument, hasLength(2));
    final [source, peer] = sameDocument;
    expect(identical(source, peer), isFalse);
    final offsets = [alpha.offset, source.offset, peer.offset];
    source.jumpTo(offsets[1] + 35);
    await tester.pumpAndSettle();
    expect([alpha.offset, peer.offset], [offsets[0] + 35, offsets[2] + 35]);

    await h.commands!.execute('workbench.action.joinEditorInGroup');
    await tester.pumpAndSettle();
    final remaining =
        _horizontalController(tester, _fieldForDocument(tester, 11));
    final alphaRebased = alpha.offset;
    remaining.jumpTo(remaining.offset + 25);
    await tester.pumpAndSettle();
    expect(alpha.offset, alphaRebased + 25);
    await h.disposeWorkbench(tester);
    expect(tester.takeException(), isNull);
  });

  void bindHold(String key) {
    File('${h.base}/keybindings.json').writeAsStringSync(jsonEncode([
      {
        'key': key,
        'command': 'workbench.action.holdLockedScrolling',
        'when': 'editorTextFocus',
      },
      {
        'key': 'f10',
        'command': 'workbench.action.splitEditorInGroup',
        'when': 'editorTextFocus',
      },
    ]));
  }

  testWidgets('unbound Alt leaves vertical pane offsets independent',
      (tester) async {
    h = _Harness();
    await h.prepare(workspaceRoot: 'unused');
    await seedTwoGroups(tester, h);
    await h.mount(tester);
    final alpha = _fieldForDocument(tester, 10).scrollController!;
    final beta = _fieldForDocument(tester, 11).scrollController!;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    alpha.jumpTo(300);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    expect(beta.offset, 0);
    await h.disposeWorkbench(tester);
  });

  testWidgets('bound Hold syncs both axes until any key release',
      (tester) async {
    h = _Harness();
    await h.prepare(workspaceRoot: 'unused');
    await seedTwoGroups(tester, h, wideLines: true);
    bindHold('f8');
    await h.mount(tester);
    final alpha = _fieldForDocument(tester, 10);
    final beta = _fieldForDocument(tester, 11);
    beta.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    final alphaX = _horizontalController(tester, alpha);
    final betaX = _horizontalController(tester, beta);
    final alphaY = alpha.scrollController!;
    final betaY = beta.scrollController!;
    alphaX.jumpTo(140);
    betaX.jumpTo(45);
    alphaY.jumpTo(250);
    betaY.jumpTo(100);
    await tester.pumpAndSettle();
    expect([alphaX.offset, betaX.offset], [140, 45]);
    expect([alphaY.offset, betaY.offset], [250, 100]);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.f8);
    await tester.pumpAndSettle();
    expect(statusEntry, findsOneWidget);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.f8);
    await tester.pumpAndSettle();
    expect(statusEntry, findsOneWidget);
    alphaX.jumpTo(210);
    alphaY.jumpTo(320);
    await tester.pumpAndSettle();
    expect([betaX.offset, betaY.offset], [115, 170]);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.f10);
    await tester.pumpAndSettle();
    expect(find.byType(RustTextInputField), findsNWidgets(2));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f10);
    await tester.pumpAndSettle();
    expect(statusEntry, findsNothing);
    alphaX.jumpTo(260);
    await tester.pumpAndSettle();
    expect(betaX.offset, 115);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f8);
    await tester.pump(const Duration(milliseconds: 700));
    expect(h.sessionStore!.tryLoad()?['lockedScrolling'] ?? false, isFalse);
    await h.disposeWorkbench(tester);
  });

  testWidgets('native window blur restores the latched lock during Hold',
      (tester) async {
    h = _Harness();
    await h.prepare(workspaceRoot: 'unused');
    await seedTwoGroups(tester, h, wideLines: true);
    bindHold('f8');
    await h.mount(tester);
    final alpha = _fieldForDocument(tester, 10).scrollController!;
    final betaField = _fieldForDocument(tester, 11);
    final beta = betaField.scrollController!;
    betaField.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    alpha.jumpTo(250);
    beta.jumpTo(100);
    await tester.pumpAndSettle();
    await h.commands!.execute('workbench.action.toggleLockedScrolling');
    await tester.pump(const Duration(milliseconds: 700));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.f8);
    await tester.pumpAndSettle();
    expect(statusEntry, findsNothing);
    alpha.jumpTo(300);
    await tester.pumpAndSettle();
    expect(beta.offset, 100);

    final windowListener =
        tester.state(find.byType(WorkbenchPage)) as WindowListener;
    windowListener.onWindowBlur();
    await tester.pumpAndSettle();
    expect(statusEntry, findsOneWidget);
    alpha.jumpTo(330);
    await tester.pumpAndSettle();
    expect(beta.offset, 130);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f8);
    await tester.pump(const Duration(milliseconds: 700));
    expect(statusEntry, findsOneWidget);
    expect(h.sessionStore!.tryLoad()?['lockedScrolling'], isTrue);
    await h.disposeWorkbench(tester);
  });

  testWidgets('Hold uses the final chord key and supports command execution',
      (tester) async {
    h = _Harness();
    await h.prepare(workspaceRoot: 'unused');
    await seedTwoGroups(tester, h);
    bindHold('ctrl+k f8');
    await h.mount(tester);
    _fieldForDocument(tester, 11).focusNode!.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(statusEntry, findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.f8);
    await tester.pumpAndSettle();
    expect(statusEntry, findsOneWidget);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f8);
    await tester.pumpAndSettle();
    expect(statusEntry, findsNothing);

    final status =
        await h.commands!.execute('workbench.action.holdLockedScrolling');
    await tester.pumpAndSettle();
    expect(status, CommandExecutionStatus.executed);
    expect(statusEntry, findsOneWidget);
    await h.disposeWorkbench(tester);
  });

  testWidgets(
    'the locked-scrolling status appears only while active and turns off on tap',
    (tester) async {
      h = _Harness();
      await h.prepare(workspaceRoot: 'unused');
      await seedTwoGroups(tester, h);
      final semantics = tester.ensureSemantics();
      try {
        await h.mount(tester);
        expect(statusEntry, findsNothing);
        final encoding = find.byKey(const ValueKey('status-encoding'));
        final lineEnding = find.byKey(const ValueKey('status-line-ending'));
        final notifications =
            find.byKey(const ValueKey('status-notifications'));
        final notificationsBefore = tester.getRect(notifications);
        expect(
          notificationsBefore.right,
          greaterThan(tester.view.physicalSize.width - 55),
        );

        await h.commands!.execute('workbench.action.toggleLockedScrolling');
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 700));
        expect(statusEntry, findsOneWidget);
        expect(find.descendant(of: statusEntry, matching: find.text('滚动已锁定')),
            findsOneWidget);
        expect(find.bySemanticsLabel('滚动已锁定'), findsOneWidget);
        final bounds = tester.getRect(statusEntry);
        expect(bounds.right, lessThan(tester.getTopLeft(encoding).dx));
        expect(bounds.right, lessThan(tester.getTopLeft(lineEnding).dx));
        expect(tester.getRect(notifications), notificationsBefore);
        expect(h.sessionStore!.tryLoad()?['lockedScrolling'], isTrue);

        await tester.tap(statusEntry);
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 700));
        expect(statusEntry, findsNothing);
        expect(find.bySemanticsLabel('滚动已锁定'), findsNothing);
        expect(h.sessionStore!.tryLoad()?['lockedScrolling'], isFalse);
      } finally {
        semantics.dispose();
        await h.disposeWorkbench(tester);
      }
    },
  );
}
