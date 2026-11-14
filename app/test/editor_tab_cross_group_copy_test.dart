import 'dart:convert';
import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
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

RustTextInputField _fieldWithLabel(WidgetTester tester, String label) =>
    tester
        .widgetList<RustTextInputField>(find.byType(RustTextInputField))
        .firstWhere((field) => field.semanticsLabel == label);

void main() {
  late Directory temp;
  late Directory workspace;
  late LayoutStore layoutStore;
  late SessionStore sessionStore;
  CommandService? commands;

  String baseOf() => temp.path.replaceAll(r'\', '/');

  Future<void> prepareWorkspace(WidgetTester tester) async {
    temp = Directory.systemTemp.createTempSync('alula-cross-group-copy');
    workspace = Directory('${temp.path}/workspace')..createSync();
    layoutStore = LayoutStore(path: '${baseOf()}/layout.json');
    sessionStore = SessionStore(path: '${baseOf()}/session.json');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await _deleteDirectoryWithRetry(temp);
    });
  }

  /// Seeds a two-group workspace layout and session; documents restore from
  /// disk by path so the tests never depend on the Explorer tree rendering.
  Future<void> seedTwoGroups({
    required List<Map<String, Object?>> editorDocs,
    required List<Map<String, Object?>> editor2Docs,
    String focused = 'editor-2',
    List<int> editorSticky = const [],
    List<int> editor2Sticky = const [],
    int? editorPreview,
    int? editor2Preview,
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
          if (editorSticky.isNotEmpty) 'sticky': editorSticky,
          if (editorPreview != null) 'preview': editorPreview,
          'active': editorActive ?? (editorDocs.first['id'] as int),
        },
        {
          'region': 'editor-2',
          'docs': editor2Docs,
          if (editor2Sticky.isNotEmpty) 'sticky': editor2Sticky,
          if (editor2Preview != null) 'preview': editor2Preview,
          'active': editor2Active ?? (editor2Docs.first['id'] as int),
        },
      ],
    }));
  }

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

  /// Drags a tab onto another tab with an optional held keyboard modifier,
  /// dropping at a horizontal side of the destination tab.
  Future<void> dragTabOntoTab(
    WidgetTester tester,
    String sourceRegion,
    int sourceId,
    String targetRegion,
    int targetId, {
    LogicalKeyboardKey? modifier,
    bool dropOnLeftHalf = true,
  }) async {
    final source = tester.getCenter(_tabIn(sourceRegion, sourceId));
    final targetRect = tester.getRect(_tabIn(targetRegion, targetId));
    final dropPoint = Offset(
      dropOnLeftHalf
          ? targetRect.left + targetRect.width * 0.25
          : targetRect.right - targetRect.width * 0.25,
      targetRect.center.dy,
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
    // 推进 500ms 会话保存防抖，使断言读到移动/复制后的持久化状态。
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'copy modifier duplicates the document view with pointer-side insertion',
    (tester) async {
      await prepareWorkspace(tester);
      final alpha = File('${workspace.path}/alpha.rs')
        ..writeAsStringSync('fn alpha() {}\n');
      final beta = File('${workspace.path}/beta.rs')
        ..writeAsStringSync('fn beta() {}\n');
      final gamma = File('${workspace.path}/gamma.rs')
        ..writeAsStringSync('fn gamma() {}\n');
      await seedTwoGroups(
        editorDocs: [
          {'id': 10, 'path': alpha.path},
          {'id': 11, 'path': beta.path},
        ],
        editor2Docs: [
          {'id': 12, 'path': gamma.path},
        ],
      );
      await mountPage(tester);

      // Restored session: editor has alpha/beta, editor-2 has gamma plus the
      // welcome untitled appended to the focused group.
      expect(_tabIdsIn(tester, 'editor'), [10, 11]);
      expect(_tabIdsIn(tester, 'editor-2'), [12, 1]);

      // Ctrl+drop gamma onto alpha's left half: editor gains a copy inserted
      // before alpha; the source group is untouched.
      await dragTabOntoTab(tester, 'editor-2', 12, 'editor', 10,
          modifier: LogicalKeyboardKey.controlLeft);
      expect(_tabIdsIn(tester, 'editor'), [12, 10, 11],
          reason: 'a left-half drop inserts the copy before the destination');
      expect(_tabIdsIn(tester, 'editor-2'), [12, 1],
          reason: 'the source group keeps its documents and order');
      expect(_tabCountAcrossStrips(tester, 12), 2,
          reason: 'both groups now hold a view of gamma');
      expect(_savedGroup(sessionStore, 'editor')['active'], 12,
          reason: 'the copied view is activated in the destination group');
      expect(_savedGroup(sessionStore, 'editor-2')['active'], 12,
          reason: 'the source group activation is unchanged');
      expect(sessionStore.tryLoad()?['focused'], 'editor',
          reason: 'the destination group gains focus');
      expect(
        _fieldWithLabel(tester, 'gamma.rs 主编辑器').inputWindow.document.id,
        12,
        reason: 'the copy renders as a second view of the same document',
      );
      expect(
        _fieldWithLabel(tester, 'gamma.rs 编辑器 2').inputWindow.document.id,
        12,
        reason: 'the source view keeps rendering in its group',
      );

      // Ctrl+drop alpha onto gamma's right half in editor-2: the copy is
      // inserted after the destination tab.
      await dragTabOntoTab(tester, 'editor', 10, 'editor-2', 12,
          modifier: LogicalKeyboardKey.controlLeft, dropOnLeftHalf: false);
      expect(_tabIdsIn(tester, 'editor-2'), [12, 10, 1],
          reason: 'a right-half drop inserts the copy after the destination');
      expect(_tabIdsIn(tester, 'editor'), [12, 10, 11],
          reason: 'the source group stays unchanged by the copy');
      expect(_savedGroup(sessionStore, 'editor-2')['active'], 10);
      expect(_tabCountAcrossStrips(tester, 10), 2);

      // A same-group drag without the modifier keeps the existing reorder
      // behavior.
      await dragTabOntoTab(tester, 'editor', 10, 'editor', 11);
      expect(_tabIdsIn(tester, 'editor'), [12, 11, 10],
          reason: 'same-group reorder is unchanged by the copy feature');

      // The copied group order survives a session restore.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await mountPage(tester);
      expect(_tabIdsIn(tester, 'editor'), [12, 11, 10],
          reason: 'session restore reapplies the copied group/tab order');
      expect(_tabIdsIn(tester, 'editor-2'), [12, 10, 1]);
    },
  );

  testWidgets(
    'copying onto a group that already shows the document activates it',
    (tester) async {
      await prepareWorkspace(tester);
      final alpha = File('${workspace.path}/alpha.rs')
        ..writeAsStringSync('fn alpha() {}\n');
      final beta = File('${workspace.path}/beta.rs')
        ..writeAsStringSync('fn beta() {}\n');
      final gamma = File('${workspace.path}/gamma.rs')
        ..writeAsStringSync('fn gamma() {}\n');
      await seedTwoGroups(
        editorDocs: [
          {'id': 10, 'path': alpha.path},
          {'id': 11, 'path': beta.path},
        ],
        editor2Docs: [
          {'id': 10, 'path': alpha.path},
          {'id': 12, 'path': gamma.path},
        ],
        editor2Active: 12,
      );
      await mountPage(tester);
      expect(_tabIdsIn(tester, 'editor'), [10, 11]);
      expect(_tabIdsIn(tester, 'editor-2'), [10, 12, 1]);

      // Ctrl+drop alpha onto gamma in editor-2: the existing alpha view is
      // activated without inserting a duplicate tab.
      await dragTabOntoTab(tester, 'editor', 10, 'editor-2', 12,
          modifier: LogicalKeyboardKey.controlLeft, dropOnLeftHalf: false);
      expect(_tabIdsIn(tester, 'editor-2'), [10, 12, 1],
          reason: 'no duplicate tab is inserted for an already-open document');
      expect(_tabCountAcrossStrips(tester, 10), 2);
      expect(_savedGroup(sessionStore, 'editor-2')['active'], 10,
          reason: 'the existing view is activated');
      expect(sessionStore.tryLoad()?['focused'], 'editor-2');
      expect(_savedGroup(sessionStore, 'editor')['active'], 10,
          reason: 'the source group stays untouched by the copy');

      // Dropping onto the same-document tab behaves identically.
      await dragTabOntoTab(tester, 'editor', 11, 'editor-2', 10,
          modifier: LogicalKeyboardKey.controlLeft);
      expect(_tabIdsIn(tester, 'editor-2'), [11, 10, 12, 1],
          reason: 'beta has no existing view, so it is copied normally');
      expect(_savedGroup(sessionStore, 'editor-2')['active'], 11);
    },
  );

  testWidgets(
    'untitled documents fall back to a move under the copy modifier',
    (tester) async {
      await prepareWorkspace(tester);
      await seedTwoGroups(
        editorDocs: [
          {'id': 5, 'text': 'untitled one'},
        ],
        editor2Docs: [
          {'id': 6, 'text': 'untitled two'},
        ],
        focused: 'editor-2',
      );
      await mountPage(tester);
      expect(_tabIdsIn(tester, 'editor'), [5]);
      expect(_tabIdsIn(tester, 'editor-2'), [6],
          reason: 'the focused group already holds an untitled document, so '
              'no welcome tab is appended');

      // Ctrl+drop of an untitled document moves it, matching the upstream
      // Singleton fallback.
      await dragTabOntoTab(tester, 'editor-2', 6, 'editor', 5);
      expect(_tabIdsIn(tester, 'editor'), [6, 5],
          reason: 'the untitled document moves instead of copying');
      expect(_strip('editor-2'), findsNothing,
          reason: 'the emptied source group is removed by the move');
      expect(_tabCountAcrossStrips(tester, 6), 1,
          reason: 'no duplicate view is created');
      expect(_savedGroups(sessionStore), hasLength(1));
      expect(_savedGroups(sessionStore).single['region'], 'editor');
    },
  );

  testWidgets(
    'a dirty document copy shares text and marks both views',
    (tester) async {
      await prepareWorkspace(tester);
      final alpha = File('${workspace.path}/alpha.rs')
        ..writeAsStringSync('fn alpha() {}\n');
      final beta = File('${workspace.path}/beta.rs')
        ..writeAsStringSync('fn beta() {}\n');
      final gamma = File('${workspace.path}/gamma.rs')
        ..writeAsStringSync('fn gamma() {}\n');
      await seedTwoGroups(
        editorDocs: [
          {'id': 10, 'path': alpha.path},
          {'id': 11, 'path': beta.path},
        ],
        editor2Docs: [
          {'id': 12, 'path': gamma.path},
        ],
        editorActive: 10,
      );
      await mountPage(tester);
      expect(_tabIdsIn(tester, 'editor'), [10, 11]);
      expect(_tabIdsIn(tester, 'editor-2'), [12, 1]);

      // Make alpha dirty, selected, and scrolled in the source group.
      await tester.tap(_tabIn('editor', 10));
      await tester.pump(const Duration(milliseconds: 300));
      final sourceField = _fieldWithLabel(tester, 'alpha.rs 主编辑器');
      sourceField.focusNode!.requestFocus();
      await tester.pump();
      final typedText =
          '${List.filled(40, 'dirty copy line').join('\n')}\nshared undo check\n';
      const selection = TextSelection.collapsed(offset: 7);
      tester.testTextInput.updateEditingValue(TextEditingValue(
        text: typedText,
        selection: selection,
      ));
      await tester.pump();
      await tester.pump();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('editor-tab-label-editor-10')))
            .data,
        contains('•'),
        reason: 'the source document is dirty before the copy',
      );

      // Ctrl+drop the dirty alpha onto gamma in editor-2: the copy shares
      // the dirty document, carries the selection, and matches the scroll.
      await dragTabOntoTab(tester, 'editor', 10, 'editor-2', 12,
          modifier: LogicalKeyboardKey.controlLeft, dropOnLeftHalf: false);
      expect(_tabIdsIn(tester, 'editor-2'), [12, 10, 1]);
      expect(_tabIdsIn(tester, 'editor'), [10, 11],
          reason: 'the source keeps its dirty document view');
      final copyField = _fieldWithLabel(tester, 'alpha.rs 编辑器 2');
      expect(copyField.inputWindow, isNot(same(sourceField.inputWindow)),
          reason: 'the copy is a distinct editor view of the shared document');
      final copyEditable = find.descendant(
        of: find.byKey(copyField.key!),
        matching: find.byType(EditableText),
      );
      final copyController =
          tester.widget<EditableText>(copyEditable).controller;
      expect(copyController.text, typedText,
          reason: 'the copy shares the dirty text via the shared document');
      expect(copyController.selection, selection,
          reason: 'the copy carries the source selection like a split view');

      expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('editor-tab-label-editor-2-10')))
            .data,
        contains('•'),
        reason: 'the copied view is dirty as well',
      );

      // Undo through the copy applies to the shared document in both views.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.pump();
      expect(copyController.text, isNot(typedText),
          reason: 'undo still reaches the shared document through the copy');
      final sourceEditable = find.descendant(
        of: find.byKey(sourceField.key!),
        matching: find.byType(EditableText),
      );
      final sourceController =
          tester.widget<EditableText>(sourceEditable).controller;
      expect(sourceController.text, copyController.text,
          reason: 'both views observe the same shared text after undo');
    },
  );

  testWidgets(
    'copies are ordinary tabs regardless of sticky or preview sources',
    (tester) async {
      await prepareWorkspace(tester);
      final alpha = File('${workspace.path}/alpha.rs')
        ..writeAsStringSync('fn alpha() {}\n');
      final beta = File('${workspace.path}/beta.rs')
        ..writeAsStringSync('fn beta() {}\n');
      final gamma = File('${workspace.path}/gamma.rs')
        ..writeAsStringSync('fn gamma() {}\n');
      await seedTwoGroups(
        editorDocs: [
          {'id': 10, 'path': alpha.path},
          {'id': 11, 'path': beta.path},
        ],
        editor2Docs: [
          {'id': 12, 'path': gamma.path},
        ],
        editorSticky: const [10],
        editorPreview: 11,
        editorActive: 10,
      );
      await mountPage(tester);
      expect(_tabIdsIn(tester, 'editor'), [10, 11]);
      expect(_savedGroup(sessionStore, 'editor')['sticky'], [10]);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('editor-tab-label-editor-11')))
            .style
            ?.fontStyle,
        FontStyle.italic,
        reason: 'the seeded preview renders italic in the source group',
      );

      // Copying the sticky tab: the copy joins editor-2 as an ordinary tab
      // and the source sticky membership stays intact.
      await dragTabOntoTab(tester, 'editor', 10, 'editor-2', 12,
          modifier: LogicalKeyboardKey.controlLeft, dropOnLeftHalf: false);
      expect(_tabIdsIn(tester, 'editor-2'), [12, 10, 1]);
      expect(_savedGroup(sessionStore, 'editor-2')['sticky'], isEmpty,
          reason: 'the copy is not sticky in the destination group');
      expect(_savedGroup(sessionStore, 'editor')['sticky'], [10],
          reason: 'the source sticky membership is unchanged');
      expect(
        find.byKey(const ValueKey('sticky-tab-indicator-editor-2-10')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('sticky-tab-indicator-editor-10')),
        findsOneWidget,
      );

      // Copying the preview: the copy is a regular tab while the source
      // preview designation is preserved.
      await dragTabOntoTab(tester, 'editor', 11, 'editor-2', 10,
          modifier: LogicalKeyboardKey.controlLeft, dropOnLeftHalf: false);
      expect(_tabIdsIn(tester, 'editor-2'), [12, 10, 11, 1]);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('editor-tab-label-editor-2-11')))
            .style
            ?.fontStyle,
        FontStyle.normal,
        reason: 'the copied preview is pinned as a regular tab',
      );
      expect(_savedGroup(sessionStore, 'editor-2')['preview'], isNull);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('editor-tab-label-editor-11')))
            .style
            ?.fontStyle,
        FontStyle.italic,
        reason: 'the source preview designation is untouched by the copy',
      );
      expect(_savedGroup(sessionStore, 'editor')['preview'], 11);
    },
  );

  testWidgets(
    'the copy modifier follows the platform convention',
    (tester) async {
      await prepareWorkspace(tester);
      final alpha = File('${workspace.path}/alpha.rs')
        ..writeAsStringSync('fn alpha() {}\n');
      final beta = File('${workspace.path}/beta.rs')
        ..writeAsStringSync('fn beta() {}\n');
      final gamma = File('${workspace.path}/gamma.rs')
        ..writeAsStringSync('fn gamma() {}\n');
      await seedTwoGroups(
        editorDocs: [
          {'id': 10, 'path': alpha.path},
          {'id': 11, 'path': beta.path},
        ],
        editor2Docs: [
          {'id': 12, 'path': gamma.path},
        ],
      );
      await mountPage(tester);
      expect(_tabIdsIn(tester, 'editor'), [10, 11]);
      expect(_tabIdsIn(tester, 'editor-2'), [12, 1]);

      // On the default (Windows/Linux) platform Alt is not the copy
      // modifier, so the drop behaves as a move.
      await dragTabOntoTab(tester, 'editor-2', 12, 'editor', 10,
          modifier: LogicalKeyboardKey.altLeft);
      expect(_tabIdsIn(tester, 'editor'), [12, 10, 11],
          reason: 'Alt on Windows/Linux falls back to the move behavior');
      expect(_tabIdsIn(tester, 'editor-2'), [1],
          reason: 'the source view leaves its group under a move');
      expect(_tabCountAcrossStrips(tester, 12), 1,
          reason: 'no duplicate view is created by the non-copy modifier');

      // Under a macOS platform override Alt copies while Ctrl moves.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await dragTabOntoTab(tester, 'editor', 12, 'editor-2', 1,
          modifier: LogicalKeyboardKey.altLeft, dropOnLeftHalf: false);
      expect(_tabIdsIn(tester, 'editor-2'), [1, 12],
          reason: 'Alt on macOS copies the document view');
      expect(_tabIdsIn(tester, 'editor'), [12, 10, 11],
          reason: 'the source group stays intact under a copy');
      expect(_tabCountAcrossStrips(tester, 12), 2);

      await dragTabOntoTab(tester, 'editor-2', 12, 'editor', 11,
          modifier: LogicalKeyboardKey.controlLeft);
      expect(_tabCountAcrossStrips(tester, 12), 1,
          reason: 'Ctrl on macOS is not the copy modifier, so the tab moves');
      expect(_tabIdsIn(tester, 'editor'), [12, 10, 11],
          reason: 'the moved view replaces the copy in the destination group');
      expect(_tabIdsIn(tester, 'editor-2'), [1]);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
