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

void main() {
  late _Harness h;

  /// Seeds two horizontal groups: alpha（120 行）与 beta（60 行），长度
  /// 不同以便观察滚动位移。
  Future<void> seedTwoGroups(WidgetTester tester, _Harness harness) async {
    final alpha = StringBuffer();
    for (var i = 0; i < 120; i++) {
      alpha.writeln('alpha line $i');
    }
    final beta = StringBuffer();
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

  testWidgets(
    'holding Alt syncs a scroll gesture even when the toggle is off',
    (tester) async {
      h = _Harness();
      await h.prepare(workspaceRoot: 'unused');
      seedTwoGroups(tester, h);
      await h.mount(tester);
      expect(
        (h.sessionStore!.tryLoad()?['lockedScrolling'] as bool?) ?? false,
        isFalse,
      );

      final alphaField = _fieldForDocument(tester, 10);
      final betaField = _fieldForDocument(tester, 11);
      alphaField.scrollController!.jumpTo(
        alphaField.scrollController!.position.maxScrollExtent * 0.8,
      );
      await tester.pumpAndSettle();
      expect(betaField.scrollController!.offset, 0);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      alphaField.scrollController!.jumpTo(
        alphaField.scrollController!.position.maxScrollExtent * 0.5,
      );
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      final betaMax = betaField.scrollController!.position.maxScrollExtent;
      expect(betaField.scrollController!.offset,
          closeTo(betaMax * 0.5, betaMax * 0.5 * 0.1),
          reason: 'Alt-held scroll syncs without the toggle');
      await h.disposeWorkbench(tester);
    },
  );

  testWidgets(
    'the status bar indicator reflects and toggles the state with persistence',
    (tester) async {
      h = _Harness();
      await h.prepare(workspaceRoot: 'unused');
      seedTwoGroups(tester, h);
      await h.mount(tester);
      expect(find.byKey(const ValueKey('status-bar-locked-scrolling')),
          findsOneWidget);
      expect(find.byIcon(Icons.lock_open), findsOneWidget);
      expect(find.byIcon(Icons.lock), findsNothing);

      await tester
          .tap(find.byKey(const ValueKey('status-bar-locked-scrolling')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byIcon(Icons.lock), findsOneWidget,
          reason: 'the status bar reflects locked scrolling');
      expect(h.sessionStore!.tryLoad()?['lockedScrolling'], isTrue,
          reason: 'the state persists through the session journal');

      await tester
          .tap(find.byKey(const ValueKey('status-bar-locked-scrolling')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byIcon(Icons.lock_open), findsOneWidget);
      expect(h.sessionStore!.tryLoad()?['lockedScrolling'], isFalse);
      await h.disposeWorkbench(tester);
    },
  );
}
