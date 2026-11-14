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

Finder _dropArea(String region) =>
    find.byKey(ValueKey('editor-drop-area-$region'));

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
    _tabIn('editor-2', id).evaluate().length;

List<Map<String, Object?>> _savedGroups(SessionStore store) =>
    (store.tryLoad()!['groups'] as List)
        .cast<Map>()
        .map((group) => group.cast<String, Object?>())
        .toList();

Map<String, Object?> _savedGroup(SessionStore store, String region) =>
    _savedGroups(store).singleWhere((group) => group['region'] == region);

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
    temp = Directory.systemTemp.createTempSync('alula-group-area-drop');
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
  Future<void> seedTwoGroups({
    required List<Map<String, Object?>> editorDocs,
    required List<Map<String, Object?>> editor2Docs,
    String focused = 'editor-2',
    int? editorActive,
    int? editor2Active,
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
          'active': editorActive ?? (editorDocs.first['id'] as int),
        },
        {
          'region': 'editor-2',
          'docs': editor2Docs,
          'active': editor2Active ?? (editor2Docs.first['id'] as int),
        },
      ],
    }));
  }

  /// Drags a tab and drops it at the center of a group's pane area.
  Future<void> dropTabOnArea(
    WidgetTester tester,
    String sourceRegion,
    int sourceId,
    String targetRegion, {
    LogicalKeyboardKey? modifier,
  }) async {
    final source = tester.getCenter(_tabIn(sourceRegion, sourceId));
    final dropPoint = tester.getCenter(_dropArea(targetRegion));
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
    'a tab dropped on another group area appends and activates there',
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

      await dropTabOnArea(tester, 'editor-2', 12, 'editor');
      expect(_tabIdsIn(tester, 'editor'), [10, 11, 12],
          reason: 'the area drop appends the document at the group end');
      expect(_tabIdsIn(tester, 'editor-2'), [1],
          reason: 'the source group loses the moved document');
      expect(_savedGroup(sessionStore, 'editor')['active'], 12,
          reason: 'the moved document is activated in the destination group');
      expect(sessionStore.tryLoad()?['focused'], 'editor',
          reason: 'the destination group gains focus');
      expect(_savedGroup(sessionStore, 'editor-2')['active'], 1,
          reason: 'the source group falls back to its remaining document');

      // The appended order survives a session restore.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await mountPage(tester);
      // The welcome untitled (id 1) re-attaches to the focused group on
      // remount because the moved session focused editor, which holds no
      // untitled document after the move (existing workbench behavior).
      expect(_tabIdsIn(tester, 'editor'), [10, 11, 12, 1]);
      expect(_tabIdsIn(tester, 'editor-2'), [1]);
    },
  );

  testWidgets(
    'same-group area drops stay no-ops and the copy modifier duplicates',
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

      // Dropping on the own group's area does nothing.
      await dropTabOnArea(tester, 'editor', 10, 'editor');
      expect(_tabIdsIn(tester, 'editor'), [10, 11],
          reason: 'same-group area drops are no-ops');
      expect(_savedGroup(sessionStore, 'editor')['active'], 10);

      // Ctrl+drop gamma on the editor area copies it appended at the end.
      await dropTabOnArea(tester, 'editor-2', 12, 'editor',
          modifier: LogicalKeyboardKey.controlLeft);
      expect(_tabIdsIn(tester, 'editor'), [10, 11, 12],
          reason: 'the copy is appended at the group end');
      expect(_tabIdsIn(tester, 'editor-2'), [12, 1],
          reason: 'the source group stays untouched by the copy');
      expect(_tabCountAcrossStrips(tester, 12), 2);
      expect(_savedGroup(sessionStore, 'editor')['active'], 12);
      expect(_savedGroup(sessionStore, 'editor-2')['active'], 12,
          reason: 'the source group activation is unchanged');
      expect(sessionStore.tryLoad()?['focused'], 'editor');
    },
  );

  testWidgets(
    'untitled documents move on area drops even with the copy modifier',
    (tester) async {
      await prepareWorkspace(tester);
      final alpha = File('${workspace.path}/alpha.rs')
        ..writeAsStringSync('fn alpha() {}\n');
      final beta = File('${workspace.path}/beta.rs')
        ..writeAsStringSync('fn beta() {}\n');
      await seedTwoGroups(
        editorDocs: [...fileDoc(alpha.path, 10), ...fileDoc(beta.path, 11)],
        editor2Docs: [
          {'id': 5, 'text': 'untitled body'},
        ],
      );
      await mountPage(tester);
      expect(_tabIdsIn(tester, 'editor'), [10, 11]);
      expect(_tabIdsIn(tester, 'editor-2'), [5]);

      await dropTabOnArea(tester, 'editor-2', 5, 'editor',
          modifier: LogicalKeyboardKey.controlLeft);
      expect(_tabIdsIn(tester, 'editor'), [10, 11, 5],
          reason: 'the untitled document moves instead of copying');
      expect(_strip('editor-2'), findsNothing,
          reason: 'the emptied source group is removed');
      expect(_tabCountAcrossStrips(tester, 5), 1);
      expect(_savedGroups(sessionStore), hasLength(1));
    },
  );

  testWidgets(
    'area drops into a group already showing the document deduplicate',
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
        editor2Docs: [...fileDoc(alpha.path, 10), ...fileDoc(gamma.path, 12)],
        editor2Active: 12,
      );
      await mountPage(tester);
      expect(_tabIdsIn(tester, 'editor'), [10, 11]);
      expect(_tabIdsIn(tester, 'editor-2'), [10, 12, 1]);

      // Moving alpha via the area drop activates the existing view in
      // editor-2 and removes the source duplicate.
      await dropTabOnArea(tester, 'editor', 10, 'editor-2');
      expect(_tabIdsIn(tester, 'editor-2'), [10, 12, 1],
          reason: 'no duplicate tab is appended for an already-open document');
      expect(_tabIdsIn(tester, 'editor'), [11],
          reason: 'the source duplicate view is removed by the move');
      expect(_savedGroup(sessionStore, 'editor-2')['active'], 10,
          reason: 'the existing view is activated');
      expect(_savedGroup(sessionStore, 'editor')['active'], 11);

      // Copying beta via the area drop appends normally (no existing view).
      await dropTabOnArea(tester, 'editor', 11, 'editor-2',
          modifier: LogicalKeyboardKey.controlLeft);
      expect(_tabIdsIn(tester, 'editor-2'), [10, 12, 1, 11]);
      expect(_savedGroup(sessionStore, 'editor-2')['active'], 11);
    },
  );
}
