import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/explorer_preview.dart';

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

Future<void> _unmountAndDeleteTempDirectory(
  WidgetTester tester,
  Directory directory,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await _deleteDirectoryWithRetry(directory);
}

Finder _tab(int id) => find.byKey(ValueKey('tab-$id'));

Finder _tabIn(String region, int id) => find.descendant(
      of: find.byKey(ValueKey('editor-tab-strip-$region')),
      matching: _tab(id),
    );

Finder _strip(String region) =>
    find.byKey(ValueKey('editor-tab-strip-$region'));

/// Tab ids inside a strip in visual order.
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
    }).toList();

/// Groups as saved by the existing session save path.
List<Map<String, Object?>> _savedGroups(SessionStore store) =>
    (store.tryLoad()!['groups'] as List)
        .cast<Map>()
        .map((group) => group.cast<String, Object?>())
        .toList();

Map<String, Object?> _savedGroup(SessionStore store, String region) =>
    _savedGroups(store).singleWhere((group) => group['region'] == region);

int _savedDocumentId(WidgetTester tester, String fileName) {
  final label = tester.widgetList<Text>(find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> &&
        key.value.startsWith('editor-tab-label-') &&
        widget is Text &&
        widget.data?.startsWith(fileName) == true;
  })).single;
  final key = label.key! as ValueKey<String>;
  return int.parse(key.value.split('-').last);
}

RustTextInputField _fieldForDocument(WidgetTester tester, int documentId) =>
    tester
        .widgetList<RustTextInputField>(find.byType(RustTextInputField))
        .firstWhere(
          (field) => field.inputWindow.document.id == documentId,
        );

Future<void> _setSticky(WidgetTester tester, int id) async {
  await tester.tapAt(tester.getCenter(_tab(id)), buttons: kSecondaryButton);
  await tester.pumpAndSettle();
  await tester.tap(find.text('固定编辑器'));
  await tester.pumpAndSettle();
}

Future<void> _pressCtrlZ(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.pump();
}

void main() {
  late Directory temp;
  late Directory workspace;
  late LayoutStore layoutStore;
  late SessionStore sessionStore;
  CommandService? commands;

  Future<void> mountPage(
    WidgetTester tester, {
    required String path,
    // 2400px 保证三个编辑器组的标签不会延伸到组右缘的拆分按钮下方，
    // 否则 drop 点会被工具栏 IconButton 截获（1600px 三组时每组仅 ~320px）。
    int width = 2400,
    int height = 1000,
  }) async {
    tester.view.physicalSize = Size(width.toDouble(), height.toDouble());
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: WorkbenchPage(
        autoFolder: workspace.path,
        layoutStore: layoutStore,
        sessionStore: sessionStore,
        keybindingsStore: KeybindingsStore(path: path),
        onCommandServiceReady: (service) => commands = service,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    expect(commands, isNotNull);
  }

  Future<void> execute(WidgetTester tester, String command) async {
    expect(
      await commands!.execute(command),
      CommandExecutionStatus.executed,
      reason: '$command is registered and callable',
    );
    await tester.pump(const Duration(milliseconds: 700));
  }

  /// Drags a tab onto another tab and drops at a horizontal side of the
  /// destination tab, mirroring the pointer-relative insertion rule.
  Future<void> dragTabOntoTab(
    WidgetTester tester,
    String sourceRegion,
    int sourceId,
    String targetRegion,
    int targetId, {
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
    final gesture = await tester.startGesture(source);
    await tester.pump();
    await gesture.moveBy(const Offset(14, 0));
    await tester.pump();
    await gesture.moveTo(dropPoint);
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pumpAndSettle();
    // 推进 500ms 会话保存防抖，使断言读到移动后的持久化状态。
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
  }

  /// Creates a fresh workspace and store pair for one test.
  Future<void> prepareWorkspace(WidgetTester tester) async {
    temp = Directory.systemTemp.createTempSync('alula-cross-group-move');
    workspace = Directory('${temp.path}/workspace')..createSync();
    final base = temp.path.replaceAll(r'\', '/');
    layoutStore = LayoutStore(path: '$base/layout.json');
    sessionStore = SessionStore(path: '$base/session.json');
    addTearDown(() => _unmountAndDeleteTempDirectory(tester, temp));
  }

  testWidgets(
    'cross-group tab drag moves in both directions with pointer-side insertion',
    (tester) async {
      await prepareWorkspace(tester);
      final base = temp.path.replaceAll(r'\', '/');
      await mountPage(tester, path: '$base/keybindings.json');

      // A fresh workbench starts with one untitled document (id 1).
      await execute(tester, 'workbench.action.files.newUntitledFile');
      await execute(tester, 'workbench.action.files.newUntitledFile');
      expect(_tabIdsIn(tester, 'editor'), [1, 2, 3]);

      await execute(tester, 'workbench.action.splitEditorRight');
      expect(_tabIdsIn(tester, 'editor-2'), [3]);
      await execute(tester, 'workbench.action.files.newUntitledFile');
      await execute(tester, 'workbench.action.files.newUntitledFile');
      expect(_tabIdsIn(tester, 'editor-2'), [3, 4, 5]);
      expect(_savedGroup(sessionStore, 'editor-2')['active'], 5);

      // Drag the last editor-2 tab onto the first editor tab, dropping on the
      // left half: the moved tab is inserted before the destination tab.
      await dragTabOntoTab(tester, 'editor-2', 5, 'editor', 1);
      expect(_tabIdsIn(tester, 'editor'), [5, 1, 2, 3],
          reason: 'a left-half drop inserts before the destination tab');
      expect(_tabIdsIn(tester, 'editor-2'), [3, 4],
          reason: 'the source group keeps its remaining tabs');
      expect(_savedGroup(sessionStore, 'editor')['active'], 5,
          reason: 'the moved document is activated in the destination group');
      expect(_savedGroup(sessionStore, 'editor-2')['active'], 4,
          reason: 'the source group falls back to its most recent tab');
      expect(sessionStore.tryLoad()?['focused'], 'editor',
          reason: 'the destination group becomes focused');

      // Same-group reorder keeps its existing behavior.
      await dragTabOntoTab(tester, 'editor', 1, 'editor', 2);
      expect(_tabIdsIn(tester, 'editor'), [5, 2, 1, 3],
          reason: 'an earlier tab dropped on a later tab still follows it');

      // Drag an editor tab onto an editor-2 tab, dropping on the right half:
      // the moved tab is inserted after the destination tab.
      await dragTabOntoTab(tester, 'editor', 2, 'editor-2', 4,
          dropOnLeftHalf: false);
      expect(_tabIdsIn(tester, 'editor'), [5, 1, 3],
          reason: 'the source group closes the gap after the move');
      expect(_tabIdsIn(tester, 'editor-2'), [3, 4, 2],
          reason: 'a right-half drop inserts after the destination tab');
      expect(_savedGroup(sessionStore, 'editor-2')['active'], 2,
          reason: 'the moved document is activated in the destination group');
      expect(_savedGroup(sessionStore, 'editor')['active'], 5,
          reason: 'the source group keeps its active tab when another moved');

      // The resulting group/tab order survives a session restore.
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await mountPage(tester, path: '$base/keybindings.json');
      expect(_tabIdsIn(tester, 'editor'), [5, 1, 3],
          reason: 'session restore reapplies the moved group/tab order');
      expect(_tabIdsIn(tester, 'editor-2'), [3, 4, 2]);
      expect(_savedGroup(sessionStore, 'editor-2')['active'], 2);
    },
  );

  testWidgets(
    'dropping on a destination that already shows the document activates it',
    (tester) async {
      await prepareWorkspace(tester);
      final base = temp.path.replaceAll(r'\', '/');
      await mountPage(tester, path: '$base/keybindings.json');

      await execute(tester, 'workbench.action.files.newUntitledFile');
      expect(_tabIdsIn(tester, 'editor'), [1, 2]);

      await execute(tester, 'workbench.action.splitEditorRight');
      expect(_tabIdsIn(tester, 'editor-2'), [2]);
      await execute(tester, 'workbench.action.files.newUntitledFile');
      expect(_tabIdsIn(tester, 'editor-2'), [2, 3]);

      // Drop tab 2 onto its own other view in editor-2: the existing view is
      // activated and the source duplicate is removed without reinsertion.
      await dragTabOntoTab(tester, 'editor', 2, 'editor-2', 2,
          dropOnLeftHalf: false);
      expect(_tabIdsIn(tester, 'editor'), [1],
          reason: 'the source duplicate view is removed');
      expect(_tabIdsIn(tester, 'editor-2'), [2, 3],
          reason: 'no extra tab is inserted for an already-open document');
      expect(_savedGroup(sessionStore, 'editor-2')['active'], 2,
          reason: 'the destination view is activated');
      expect(sessionStore.tryLoad()?['focused'], 'editor-2');

      // Split the focused duplicate group: dropping its view on a different
      // tab of the group that already shows the document behaves identically
      // and removes the now-empty source group.
      await execute(tester, 'workbench.action.splitEditorRight');
      expect(_tabIdsIn(tester, 'editor-3'), [2]);
      await dragTabOntoTab(tester, 'editor-3', 2, 'editor-2', 3);
      expect(_tabIdsIn(tester, 'editor-2'), [2, 3],
          reason: 'the existing view is activated without reinsertion');
      expect(_strip('editor-3'), findsNothing,
          reason: 'the emptied duplicate source group is removed');
      expect(_savedGroup(sessionStore, 'editor-2')['active'], 2);
      expect(sessionStore.tryLoad()?['focused'], 'editor-2');
    },
  );

  testWidgets(
    'moving the last tab removes the emptied source group',
    (tester) async {
      await prepareWorkspace(tester);
      final base = temp.path.replaceAll(r'\', '/');
      await mountPage(tester, path: '$base/keybindings.json');

      await execute(tester, 'workbench.action.files.newUntitledFile');
      expect(_tabIdsIn(tester, 'editor'), [1, 2]);

      await execute(tester, 'workbench.action.splitEditorRight');
      await execute(tester, 'workbench.action.files.newUntitledFile');
      expect(_tabIdsIn(tester, 'editor-2'), [2, 3]);

      // Leave a single, non-shared document in the source group.
      await tester.tap(_tabIn('editor', 1));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('close-tab-editor-2')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(_tabIdsIn(tester, 'editor'), [1]);

      await dragTabOntoTab(tester, 'editor', 1, 'editor-2', 3,
          dropOnLeftHalf: false);
      expect(_tabIdsIn(tester, 'editor-2'), [2, 3, 1],
          reason: 'the moved tab is inserted after the destination tab');
      expect(_strip('editor'), findsNothing,
          reason: 'the emptied source group is removed');
      expect(sessionStore.tryLoad()?['focused'], 'editor-2');
      expect(_savedGroups(sessionStore), hasLength(1));
      expect(_savedGroups(sessionStore).single['region'], 'editor-2');
    },
  );

  testWidgets(
    'cross-group moves keep dirty state, selection, scroll, and focus identity',
    (tester) async {
      await prepareWorkspace(tester);
      final base = temp.path.replaceAll(r'\', '/');
      await mountPage(tester, path: '$base/keybindings.json');

      await execute(tester, 'workbench.action.files.newUntitledFile');
      await execute(tester, 'workbench.action.files.newUntitledFile');
      expect(_tabIdsIn(tester, 'editor'), [1, 2, 3]);

      await execute(tester, 'workbench.action.splitEditorRight');
      await execute(tester, 'workbench.action.files.newUntitledFile');
      expect(_tabIdsIn(tester, 'editor-2'), [3, 4]);

      // Make document 1 active, dirty, scrolled, and focused in the source.
      await tester.tap(_tabIn('editor', 1));
      await tester.pump(const Duration(milliseconds: 300));
      final field = _fieldForDocument(tester, 1);
      final fieldState =
          tester.state<RustTextInputFieldState>(find.byKey(field.key!));
      field.focusNode!.requestFocus();
      await tester.pump();
      final editable = find.descendant(
        of: find.byKey(field.key!),
        matching: find.byType(EditableText),
      );
      final textController = tester.widget<EditableText>(editable).controller;
      final typedText =
          '${List.filled(60, 'cross-group line').join('\n')}\nend marker';
      const selection = TextSelection.collapsed(offset: 10);
      tester.testTextInput.updateEditingValue(TextEditingValue(
        text: typedText,
        selection: selection,
      ));
      await tester.pump();
      await tester.pump();
      field.scrollController!.jumpTo(40);
      await tester.pump();
      final scrollOffset = field.scrollController!.offset;
      expect(scrollOffset, greaterThan(0),
          reason: 'the document is scrolled before the move');
      expect(field.focusNode!.hasFocus, isTrue);
      expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('editor-tab-label-editor-1')))
            .data,
        contains('•'),
        reason: 'the document is dirty before the move',
      );

      await dragTabOntoTab(tester, 'editor', 1, 'editor-2', 4,
          dropOnLeftHalf: false);
      expect(_tabIdsIn(tester, 'editor'), [2, 3]);
      expect(_tabIdsIn(tester, 'editor-2'), [3, 4, 1]);
      expect(_savedGroup(sessionStore, 'editor-2')['active'], 1);
      expect(_savedGroup(sessionStore, 'editor')['active'], 3,
          reason: 'the source group falls back to its most recent tab');

      // The same editor view carries text, selection, scroll, and focus over.
      final movedField =
          tester.widget<RustTextInputField>(find.byKey(field.key!));
      expect(movedField.key, same(field.key));
      expect(movedField.inputWindow, same(field.inputWindow));
      expect(movedField.focusNode, same(field.focusNode));
      expect(movedField.scrollController, same(field.scrollController));
      expect(
        tester.state<RustTextInputFieldState>(find.byKey(field.key!)),
        same(fieldState),
        reason: 'the same keyed input state carries selection and IME state',
      );
      expect(
        tester
            .widget<EditableText>(find.descendant(
              of: find.byKey(field.key!),
              matching: find.byType(EditableText),
            ))
            .controller,
        same(textController),
      );
      expect(textController.text, typedText);
      expect(textController.selection, selection);
      expect(movedField.scrollController!.offset, scrollOffset);
      expect(movedField.focusNode!.hasFocus, isTrue,
          reason: 'the moved editor keeps editor focus');
      expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('editor-tab-label-editor-2-1')))
            .data,
        contains('•'),
        reason: 'the dirty marker moves with the document',
      );

      // The undo history stays attached to the moved document.
      await _pressCtrlZ(tester);
      expect(textController.text, isNot(typedText),
          reason: 'undo still reaches the moved document');
    },
  );

  testWidgets(
    'sticky tabs move into the sticky partition of the destination group',
    (tester) async {
      await prepareWorkspace(tester);
      final base = temp.path.replaceAll(r'\', '/');
      await mountPage(tester, path: '$base/keybindings.json');

      await execute(tester, 'workbench.action.files.newUntitledFile');
      await execute(tester, 'workbench.action.files.newUntitledFile');
      expect(_tabIdsIn(tester, 'editor'), [1, 2, 3]);

      await _setSticky(tester, 1);
      await tester.tap(_tabIn('editor', 2));
      await tester.pump(const Duration(milliseconds: 300));
      await execute(tester, 'workbench.action.splitEditorRight');
      await execute(tester, 'workbench.action.files.newUntitledFile');
      expect(_tabIdsIn(tester, 'editor-2'), [2, 4]);

      // A sticky tab dropped before an ordinary tab lands at the sticky front.
      await dragTabOntoTab(tester, 'editor', 1, 'editor-2', 2);
      expect(_tabIdsIn(tester, 'editor-2'), [1, 2, 4],
          reason: 'the sticky tab joins the front sticky partition');
      expect(_savedGroup(sessionStore, 'editor-2')['sticky'], [1],
          reason: 'sticky membership moves with the tab');
      expect(_savedGroup(sessionStore, 'editor')['sticky'], isEmpty,
          reason: 'sticky membership leaves the source group');

      // An ordinary tab dropped before a sticky tab stays out of the sticky
      // partition.
      await dragTabOntoTab(tester, 'editor', 3, 'editor-2', 1);
      expect(_tabIdsIn(tester, 'editor-2'), [1, 3, 2, 4],
          reason: 'the ordinary tab is clamped behind the sticky partition');
      expect(_savedGroup(sessionStore, 'editor-2')['sticky'], [1]);
      expect(
        find.byKey(const ValueKey('sticky-tab-indicator-editor-2-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('sticky-tab-indicator-editor-2-3')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'a clean preview becomes a regular pinned tab on cross-group move',
    (tester) async {
      await prepareWorkspace(tester);
      File('${workspace.path}/beta.rs').writeAsStringSync('fn beta() {}\n');
      File('${workspace.path}/alpha.rs').writeAsStringSync('fn alpha() {}\n');
      final base = temp.path.replaceAll(r'\', '/');
      await mountPage(tester, path: '$base/keybindings.json');

      await openPinnedExplorerFile(tester, find.text('beta.rs').first);
      await tester.pump(const Duration(milliseconds: 300));
      final betaId = _savedDocumentId(tester, 'beta.rs');
      await execute(tester, 'workbench.action.splitEditorRight');
      expect(_tabIdsIn(tester, 'editor-2'), [betaId]);

      // Single-click opens alpha as a clean preview in the focused group.
      await tester.tap(find.text('alpha.rs').first);
      await tester.pump(const Duration(milliseconds: 300));
      final alphaId = _savedDocumentId(tester, 'alpha.rs');
      expect(
        tester
            .widget<Text>(
                find.byKey(ValueKey('editor-tab-label-editor-2-$alphaId')))
            .style
            ?.fontStyle,
        FontStyle.italic,
        reason: 'alpha opens as a preview in editor-2',
      );

      await dragTabOntoTab(tester, 'editor-2', alphaId, 'editor', betaId,
          dropOnLeftHalf: false);
      expect(_tabIdsIn(tester, 'editor'), [1, betaId, alphaId],
          reason: 'the moved preview joins the destination group as regular');
      expect(_tabIdsIn(tester, 'editor-2'), [betaId],
          reason: 'the preview tab leaves the source group');
      expect(
        tester
            .widget<Text>(
                find.byKey(ValueKey('editor-tab-label-editor-$alphaId')))
            .style
            ?.fontStyle,
        FontStyle.normal,
        reason: 'the moved preview is pinned as a regular tab',
      );
      expect(_savedGroup(sessionStore, 'editor')['preview'], isNull,
          reason: 'the destination does not treat the moved tab as preview');
      expect(_savedGroup(sessionStore, 'editor-2')['preview'], isNull,
          reason: 'the source preview designation is cleared');
      expect(_savedGroup(sessionStore, 'editor')['active'], alphaId);
    },
  );
}
