import 'dart:convert';
import 'dart:io';

import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/material.dart';
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
    temp = Directory.systemTemp.createTempSync('alula-group-mru-close');
    workspace = Directory('${temp.path}/workspace')..createSync();
    layoutStore = LayoutStore(path: '${baseOf()}/layout.json');
    sessionStore = SessionStore(path: '${baseOf()}/session.json');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await _deleteDirectoryWithRetry(temp);
    });
  }

  /// Seeds a three-group horizontal layout with one file document per group.
  Future<void> seedThreeGroups({required String focused}) async {
    final alpha = File('${workspace.path}/alpha.rs')
      ..writeAsStringSync('fn alpha() {}\n');
    final beta = File('${workspace.path}/beta.rs')
      ..writeAsStringSync('fn beta() {}\n');
    final gamma = File('${workspace.path}/gamma.rs')
      ..writeAsStringSync('fn gamma() {}\n');
    final layout = defaultLayout();
    layout.splitLeaf('editor', 'editor-2', Axis.horizontal);
    layout.splitLeaf('editor-2', 'editor-3', Axis.horizontal);
    layoutStore.save(layout);
    File('${baseOf()}/session.json').writeAsStringSync(jsonEncode({
      'v': 1,
      'editorTabMode': 'multiple',
      'focused': focused,
      'groups': [
        {
          'region': 'editor',
          'docs': [
            {'id': 10, 'path': alpha.path},
          ],
          'active': 10,
        },
        {
          'region': 'editor-2',
          'docs': [
            {'id': 11, 'path': beta.path},
          ],
          'active': 11,
        },
        {
          'region': 'editor-3',
          'docs': [
            {'id': 12, 'path': gamma.path},
          ],
          'active': 12,
        },
      ],
    }));
  }

  testWidgets(
    'closing the focused group focuses the most recently active group',
    (tester) async {
      await prepareWorkspace(tester);
      await seedThreeGroups(focused: 'editor-3');
      await mountPage(tester);
      expect(_strip('editor'), findsOneWidget);
      expect(_strip('editor-2'), findsOneWidget);
      expect(_strip('editor-3'), findsOneWidget);

      // Establish the activation order editor -> editor-2 (editor-3 stays
      // the focused group with the oldest restored activation).
      await tester.tap(_tabIn('editor', 10));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(_tabIn('editor-2', 11));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(_tabIn('editor-3', 12));
      await tester.pump(const Duration(milliseconds: 200));

      // Close the focused group's documents (the welcome untitled re-attaches
      // to the focused group at mount): once the group empties it is removed
      // and the most recently active remaining group (editor-2) gains focus,
      // not the insertion-first group (editor).
      await tester.tap(find.byKey(const ValueKey('close-tab-editor-3-12')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('close-tab-editor-3-1')));
      await tester.pumpAndSettle();
      // 推进 500ms 会话保存防抖，使断言读到持久化状态。
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(_strip('editor-3'), findsNothing,
          reason: 'the emptied group is removed');
      expect(sessionStore.tryLoad()?['focused'], 'editor-2',
          reason: 'the most recently active remaining group gains focus '
              '(upstream doRemoveEmptyGroup mostRecentlyActiveGroups[1])');
    },
  );

  testWidgets(
    'closing a non-focused middle group keeps focus and MRU continues',
    (tester) async {
      await prepareWorkspace(tester);
      await seedThreeGroups(focused: 'editor-3');
      await mountPage(tester);

      // Activation order: editor-3 (restored focus) -> editor -> editor-2.
      await tester.tap(_tabIn('editor', 10));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(_tabIn('editor-2', 11));
      await tester.pump(const Duration(milliseconds: 200));

      // Close the non-focused first group: focus stays on editor-2.
      await tester.tap(find.byKey(const ValueKey('close-tab-editor-10')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(_strip('editor'), findsNothing);
      expect(sessionStore.tryLoad()?['focused'], 'editor-2',
          reason: 'closing a non-focused group does not move focus');

      // Closing the focused editor-2 group falls back to the most recently
      // active remaining group (editor-3, activated before editor-2).
      await tester.tap(find.byKey(const ValueKey('close-tab-editor-2-11')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(_strip('editor-2'), findsNothing);
      expect(sessionStore.tryLoad()?['focused'], 'editor-3',
          reason: 'the MRU chain continues across consecutive group closes');
    },
  );
}
