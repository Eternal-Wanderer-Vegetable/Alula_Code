import 'dart:convert';
import 'dart:io';

import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _deleteDirectoryWithRetry(Directory directory) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (!directory.existsSync()) return;
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 49) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}

Finder _tabIn(String region, int id) => find.descendant(
      of: find.byKey(ValueKey('editor-tab-strip-$region')),
      matching: find.byKey(ValueKey('tab-$id')),
    );

Finder _strip(String region) =>
    find.byKey(ValueKey('editor-tab-strip-$region'));

Finder _bodyDrop(String region) =>
    find.byKey(ValueKey('editor-body-drop-$region'));

List<int> _tabIdsIn(WidgetTester tester, String region) => find
    .descendant(
      of: _strip(region),
      matching: find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> && key.value.startsWith('tab-');
      }),
    )
    .evaluate()
    .map((element) {
      final key = element.widget.key! as ValueKey<String>;
      return int.parse(key.value.substring('tab-'.length));
    })
    .toList();

int _tabCountAcrossStrips(WidgetTester tester, int id) =>
    _tabIn('editor', id).evaluate().length +
    _tabIn('editor-2', id).evaluate().length +
    _tabIn('editor-3', id).evaluate().length;

Map<String, Object?> _savedGroup(SessionStore store, String region) =>
    (store.tryLoad()!['groups'] as List)
        .cast<Map>()
        .map((group) => group.cast<String, Object?>())
        .singleWhere((group) => group['region'] == region);

void main() {
  late Directory temp;
  late Directory workspace;
  late LayoutStore layoutStore;
  late SessionStore sessionStore;
  CommandService? commands;

  String baseOf() => temp.path.replaceAll(r'\', '/');

  Future<void> mountPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(2400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: WorkbenchPage(
        autoFolder: workspace.path,
        layoutStore: layoutStore,
        sessionStore: sessionStore,
        keybindingsStore: KeybindingsStore(path: '${baseOf()}/keybindings.json'),
        onCommandServiceReady: (service) => commands = service,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    expect(commands, isNotNull);
  }

  Future<void> prepareWorkspace(WidgetTester tester) async {
    temp = Directory.systemTemp.createTempSync('alula-split-drop');
    workspace = Directory('${temp.path}/workspace')..createSync();
    layoutStore = LayoutStore(path: '${baseOf()}/layout.json');
    sessionStore = SessionStore(path: '${baseOf()}/session.json');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await _deleteDirectoryWithRetry(temp);
    });
  }

  /// Seeds a two-group layout and session with documents restored from disk.
  /// 给目标组两个文档，边缘落点移动后源组仍有剩余，避免空组摘除干扰断言。
  Future<void> seedTwoGroups({
    required List<Map<String, Object?>> editorDocs,
    required List<Map<String, Object?>> editor2Docs,
    String focused = 'editor-2',
  }) async {
    final layout = defaultLayout();
    layout.splitLeaf('editor', 'editor-2', Axis.horizontal);
    layoutStore.save(layout);
    File('${baseOf()}/session.json').writeAsStringSync(jsonEncode({
      'v': 1,
      'editorTabMode': 'multiple',
      'focused': focused,
      'groups': [
        {
          'region': 'editor',
          'docs': editorDocs,
          'active': editorDocs.first['id'],
        },
        {
          'region': 'editor-2',
          'docs': editor2Docs,
          'active': editor2Docs.first['id'],
        },
      ],
    }));
  }

  /// Drops a tab at a horizontal/vertical fraction of a group's editor body.
  Future<void> dropTabOnBody(
    WidgetTester tester,
    String sourceRegion,
    int sourceId,
    String targetRegion, {
    required double dxFraction,
    required double dyFraction,
    LogicalKeyboardKey? modifier,
  }) async {
    final source = tester.getCenter(_tabIn(sourceRegion, sourceId));
    final bodyRect = tester.getRect(_bodyDrop(targetRegion));
    final dropPoint = Offset(
      bodyRect.left + bodyRect.width * dxFraction,
      bodyRect.top + bodyRect.height * dyFraction,
    );

    if (modifier != null) {
      await tester.sendKeyDownEvent(modifier);
      await tester.pump();
    }
    final gesture = await tester.startGesture(source);
    await tester.pump();
    await gesture.moveBy(const Offset(14, 0));
    await tester.pump();
    await gesture.moveTo(dropPoint);
    await tester.pump();
    await gesture.up();
    await tester.pump();
    if (modifier != null) {
      await tester.sendKeyUpEvent(modifier);
    }
    await tester.pumpAndSettle();
    // 推进 500ms 会话保存防抖，使断言读到持久化状态。
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
  }

  List<Map<String, Object?>> fileDoc(String path, int id) =>
      [{'id': id, 'path': path}];

  testWidgets(
    'a right-edge drop creates a horizontal group to the right',
    (tester) async {
      await prepareWorkspace(tester);
      final alpha = File('${workspace.path}/alpha.rs')
        ..writeAsStringSync('fn alpha() {}\n');
      final gamma = File('${workspace.path}/gamma.rs')
        ..writeAsStringSync('fn gamma() {}\n');
      final delta = File('${workspace.path}/delta.rs')
        ..writeAsStringSync('fn delta() {}\n');
      await seedTwoGroups(
        editorDocs: [...fileDoc(alpha.path, 10)],
        editor2Docs: [...fileDoc(gamma.path, 12), ...fileDoc(delta.path, 13)],
      );
      await mountPage(tester);
      expect(_tabIdsIn(tester, 'editor'), [10]);
      expect(_tabIdsIn(tester, 'editor-2'), [12, 13, 1]);
      expect(_strip('editor-3'), findsNothing);

      await dropTabOnBody(tester, 'editor-2', 13, 'editor-2',
          dxFraction: 0.95, dyFraction: 0.5);
      expect(_strip('editor-3'), findsOneWidget,
          reason: 'the edge drop creates an adjacent group');
      expect(_tabIdsIn(tester, 'editor-3'), [13]);
      expect(_tabIdsIn(tester, 'editor-2'), [12, 1],
          reason: 'the source group keeps its remaining documents');
      final split = layoutStore.tryLoad()!.parentSplitOf('editor-3')!;
      expect(split.axis, Axis.horizontal);
      expect(
        split.children.map((node) => (node as WbLeaf).region),
        ['editor-2', 'editor-3'],
        reason: 'the new group sits to the right of the drop target group',
      );
      expect(_savedGroup(sessionStore, 'editor-3')['active'], 13);
      expect(sessionStore.tryLoad()?['focused'], 'editor-3');
      expect(_savedGroup(sessionStore, 'editor-2')['active'], 12,
          reason: 'the source group keeps its own activation');
    },
  );

  testWidgets(
    'left, up, and down edge drops follow the drop direction',
    (tester) async {
      await prepareWorkspace(tester);
      final alpha = File('${workspace.path}/alpha.rs')
        ..writeAsStringSync('fn alpha() {}\n');
      final beta = File('${workspace.path}/beta.rs')
        ..writeAsStringSync('fn beta() {}\n');
      final gamma = File('${workspace.path}/gamma.rs')
        ..writeAsStringSync('fn gamma() {}\n');
      final delta = File('${workspace.path}/delta.rs')
        ..writeAsStringSync('fn delta() {}\n');
      final epsilon = File('${workspace.path}/epsilon.rs')
        ..writeAsStringSync('fn epsilon() {}\n');
      await seedTwoGroups(
        editorDocs: [
          ...fileDoc(alpha.path, 10),
          ...fileDoc(beta.path, 11),
          ...fileDoc(gamma.path, 12),
          ...fileDoc(delta.path, 13),
          ...fileDoc(epsilon.path, 14),
        ],
        editor2Docs: [
          {'id': 20, 'text': 'untitled two'},
        ],
        focused: 'editor-2',
      );
      await mountPage(tester);
      expect(_tabIdsIn(tester, 'editor'), [10, 11, 12, 13, 14]);
      expect(_tabIdsIn(tester, 'editor-2'), [20]);

      // Down-edge drop creates a vertical split below the target group.
      await dropTabOnBody(tester, 'editor', 10, 'editor',
          dxFraction: 0.5, dyFraction: 0.95);
      expect(_strip('editor-3'), findsOneWidget);
      expect(_tabIdsIn(tester, 'editor-3'), [10]);
      expect(_tabIdsIn(tester, 'editor'), [11, 12, 13, 14]);
      final downSplit = layoutStore.tryLoad()!.parentSplitOf('editor-3')!;
      expect(downSplit.axis, Axis.vertical);
      expect(
        downSplit.children.map((node) => (node as WbLeaf).region),
        ['editor', 'editor-3'],
      );

      // Left-edge drop within the same group: the new group is inserted
      // before it.
      await dropTabOnBody(tester, 'editor', 13, 'editor',
          dxFraction: 0.05, dyFraction: 0.5);
      expect(_strip('editor-4'), findsOneWidget);
      expect(_tabIdsIn(tester, 'editor-4'), [13]);
      expect(_tabIdsIn(tester, 'editor'), [11, 12, 14]);
      final leftSplit = layoutStore.tryLoad()!.parentSplitOf('editor-4')!;
      expect(leftSplit.axis, Axis.horizontal);
      expect(
        leftSplit.children.map((node) => (node as WbLeaf).region),
        ['editor-4', 'editor'],
        reason: 'the new group is inserted before the drop target group',
      );

      // Up-edge drop creates a vertical split above the target group. The
      // first tab is used as the drag source because the last tab's center
      // sits under the group toolbar in this narrow pane (P05.42 finding).
      await dropTabOnBody(tester, 'editor', 11, 'editor',
          dxFraction: 0.5, dyFraction: 0.03);
      expect(_strip('editor-5'), findsOneWidget);
      expect(_tabIdsIn(tester, 'editor-5'), [11]);
      expect(_tabIdsIn(tester, 'editor'), [12, 14],
          reason: 'the source group keeps its remaining documents');
      final upSplit = layoutStore.tryLoad()!.parentSplitOf('editor-5')!;
      expect(upSplit.axis, Axis.vertical);
      expect(
        upSplit.children.map((node) => (node as WbLeaf).region),
        ['editor-5', 'editor'],
      );
    },
  );

  testWidgets(
    'center-band drops append and the toggle modifier disables zones',
    (tester) async {
      await prepareWorkspace(tester);
      final alpha = File('${workspace.path}/alpha.rs')
        ..writeAsStringSync('fn alpha() {}\n');
      final beta = File('${workspace.path}/beta.rs')
        ..writeAsStringSync('fn beta() {}\n');
      final gamma = File('${workspace.path}/gamma.rs')
        ..writeAsStringSync('fn gamma() {}\n');
      await seedTwoGroups(
        editorDocs: [...fileDoc(alpha.path, 10), ...fileDoc(beta.path, 11)],
        editor2Docs: [...fileDoc(gamma.path, 12)],
      );
      await mountPage(tester);
      expect(_tabIdsIn(tester, 'editor'), [10, 11]);
      expect(_tabIdsIn(tester, 'editor-2'), [12, 1]);

      // A center-band drop appends without creating a group.
      await dropTabOnBody(tester, 'editor-2', 12, 'editor',
          dxFraction: 0.5, dyFraction: 0.5);
      expect(_strip('editor-3'), findsNothing,
          reason: 'center-band drops do not split');
      expect(_tabIdsIn(tester, 'editor'), [10, 11, 12]);
      expect(_tabIdsIn(tester, 'editor-2'), [1]);

      // Alt on Windows/Linux disables the split zones: a right-edge drop
      // behaves as an append instead of creating a group.
      await dropTabOnBody(tester, 'editor', 10, 'editor-2',
          dxFraction: 0.95,
          dyFraction: 0.5,
          modifier: LogicalKeyboardKey.altLeft);
      expect(_strip('editor-3'), findsNothing,
          reason: 'the toggle modifier disables split zones');
      expect(_tabIdsIn(tester, 'editor-2'), [1, 10],
          reason: 'the edge drop appends under the toggle modifier');
      expect(_tabIdsIn(tester, 'editor'), [11, 12]);
    },
  );

  testWidgets(
    'copy and untitled fallbacks apply to split drops',
    (tester) async {
      await prepareWorkspace(tester);
      final alpha = File('${workspace.path}/alpha.rs')
        ..writeAsStringSync('fn alpha() {}\n');
      final gamma = File('${workspace.path}/gamma.rs')
        ..writeAsStringSync('fn gamma() {}\n');
      await seedTwoGroups(
        editorDocs: [...fileDoc(alpha.path, 10)],
        editor2Docs: [
          ...fileDoc(gamma.path, 12),
          {'id': 5, 'text': 'untitled body'},
        ],
      );
      await mountPage(tester);
      expect(_tabIdsIn(tester, 'editor-2'), [12, 5]);

      // Ctrl+right-edge drop copies gamma into the new group; the source
      // keeps its view.
      await dropTabOnBody(tester, 'editor-2', 12, 'editor-2',
          dxFraction: 0.95,
          dyFraction: 0.5,
          modifier: LogicalKeyboardKey.controlLeft);
      expect(_strip('editor-3'), findsOneWidget);
      expect(_tabIdsIn(tester, 'editor-3'), [12]);
      expect(_tabIdsIn(tester, 'editor-2'), [12, 5],
          reason: 'the source keeps its view under a copy');
      expect(_tabCountAcrossStrips(tester, 12), 2);

      // An untitled document moves into the new group even with the copy
      // modifier (upstream Singleton fallback).
      await dropTabOnBody(tester, 'editor-2', 5, 'editor-3',
          dxFraction: 0.95,
          dyFraction: 0.5,
          modifier: LogicalKeyboardKey.controlLeft);
      expect(_strip('editor-4'), findsOneWidget);
      expect(_tabIdsIn(tester, 'editor-4'), [5]);
      expect(_tabIdsIn(tester, 'editor-2'), [12],
          reason: 'the untitled document leaves its group under a move');
      expect(_tabIn('editor-4', 5), findsOneWidget);
    },
  );

  testWidgets(
    'the split layout and documents survive a session restore',
    (tester) async {
      await prepareWorkspace(tester);
      final alpha = File('${workspace.path}/alpha.rs')
        ..writeAsStringSync('fn alpha() {}\n');
      final gamma = File('${workspace.path}/gamma.rs')
        ..writeAsStringSync('fn gamma() {}\n');
      final delta = File('${workspace.path}/delta.rs')
        ..writeAsStringSync('fn delta() {}\n');
      await seedTwoGroups(
        editorDocs: [...fileDoc(alpha.path, 10)],
        editor2Docs: [...fileDoc(gamma.path, 12), ...fileDoc(delta.path, 13)],
      );
      await mountPage(tester);
      await dropTabOnBody(tester, 'editor-2', 13, 'editor-2',
          dxFraction: 0.95, dyFraction: 0.5);
      expect(_tabIdsIn(tester, 'editor-3'), [13]);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await mountPage(tester);
      expect(_strip('editor-3'), findsOneWidget,
          reason: 'the split layout is persisted and restored');
      expect(_tabIdsIn(tester, 'editor-3'), [13, 1],
          reason: 'the focused group without an untitled document re-attaches '
              'the welcome untitled (existing workbench behavior)');
      expect(_tabIdsIn(tester, 'editor'), [10]);
      expect(_tabIdsIn(tester, 'editor-2'), [12, 1]);
      final split = layoutStore.tryLoad()!.parentSplitOf('editor-3')!;
      expect(split.axis, Axis.horizontal);
      expect(
        split.children.map((node) => (node as WbLeaf).region),
        ['editor-2', 'editor-3'],
      );
    },
  );
}
