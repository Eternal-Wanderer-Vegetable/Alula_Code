import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
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

Future<void> _unmountAndDeleteTempDirectory(
  WidgetTester tester,
  Directory directory,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await _deleteDirectoryWithRetry(directory);
}

RustTextInputField _fieldForDocument(WidgetTester tester, int documentId) =>
    tester
        .widgetList<RustTextInputField>(find.byType(RustTextInputField))
        .firstWhere(
          (field) => field.inputWindow.document.id == documentId,
        );

RustTextInputField _fieldWithLabel(WidgetTester tester, String label) => tester
    .widgetList<RustTextInputField>(find.byType(RustTextInputField))
    .firstWhere((field) => field.semanticsLabel == label);

void main() {
  testWidgets(
    'directional move reuses editor views, creates groups, and deduplicates shared documents',
    (tester) async {
      final temp =
          Directory.systemTemp.createTempSync('alula-directional-move');
      addTearDown(() => _unmountAndDeleteTempDirectory(tester, temp));
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final workspace = Directory('${temp.path}/workspace')..createSync();
      File('${workspace.path}/main.rs')
          .writeAsStringSync('fn main() { println!("main"); }');
      File('${workspace.path}/other.rs')
          .writeAsStringSync('fn helper() { println!("other"); }');
      final base = temp.path.replaceAll(r'\', '/');
      final initialLayout = defaultLayout();
      final layoutStore = LayoutStore(path: '$base/layout.json')
        ..save(initialLayout);
      final sessionStore = SessionStore(path: '$base/session.json');
      CommandService? commands;

      await tester.pumpWidget(MaterialApp(
        home: WorkbenchPage(
          autoFolder: workspace.path,
          layoutStore: layoutStore,
          sessionStore: sessionStore,
          keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
          onCommandServiceReady: (service) => commands = service,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 600));
      expect(commands, isNotNull);

      Future<void> execute(String command) async {
        expect(
          await commands!.execute(command),
          CommandExecutionStatus.executed,
          reason: '$command is registered and callable',
        );
        await tester.pump(const Duration(milliseconds: 700));
      }

      Future<void> expectViewPreserved(
        RustTextInputField before,
        RustTextInputFieldState beforeState,
        int documentId,
      ) async {
        final after =
            tester.widget<RustTextInputField>(find.byKey(before.key!));
        expect(after.key, same(before.key));
        expect(after.inputWindow.document.id, documentId);
        expect(after.inputWindow, same(before.inputWindow));
        expect(after.focusNode, same(before.focusNode));
        expect(after.scrollController, same(before.scrollController));
        expect(
          tester.state<RustTextInputFieldState>(find.byKey(before.key!)),
          same(beforeState),
          reason: 'the same keyed input state carries selection and IME state',
        );
      }

      // Registered commands are no-ops when the focused group has no editor.
      await tester.tap(find.byKey(const ValueKey('close-tab-editor-1')));
      await tester.pump(const Duration(milliseconds: 600));
      final noActiveLayout = layoutStore.tryLoad()!.toJson();
      await execute('workbench.action.moveEditorToRightGroup');
      expect(layoutStore.tryLoad()!.toJson(), noActiveLayout);
      expect(find.byType(RustTextInputField), findsNothing);

      await tester.tap(find.text('main.rs').first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('other.rs').first);
      await tester.pump(const Duration(milliseconds: 300));
      final otherBeforeRight = tester.widget<RustTextInputField>(
        find.byType(RustTextInputField),
      );
      final otherStateBeforeRight = tester.state<RustTextInputFieldState>(
        find.byKey(otherBeforeRight.key!),
      );
      final otherId = otherBeforeRight.inputWindow.document.id;

      await execute('workbench.action.moveEditorToRightGroup');
      await expectViewPreserved(
        otherBeforeRight,
        otherStateBeforeRight,
        otherId,
      );
      expect(sessionStore.tryLoad()?['focused'], 'editor-2');
      var savedRoot = layoutStore.tryLoad()!;
      expect(savedRoot.parentSplitOf('editor-2')!.axis, Axis.horizontal);
      expect(
        savedRoot
            .parentSplitOf('editor-2')!
            .children
            .map((node) => (node as WbLeaf).region),
        ['editor', 'editor-2'],
      );
      expect(find.byType(RustTextInputField), findsNWidgets(2));

      // Move left into an existing group with a different document.
      final otherBeforeLeft = _fieldForDocument(tester, otherId);
      final otherStateBeforeLeft = tester.state<RustTextInputFieldState>(
        find.byKey(otherBeforeLeft.key!),
      );
      await execute('workbench.action.moveEditorToLeftGroup');
      await expectViewPreserved(
        otherBeforeLeft,
        otherStateBeforeLeft,
        otherId,
      );
      expect(sessionStore.tryLoad()?['focused'], 'editor');
      savedRoot = layoutStore.tryLoad()!;
      expect(
        savedRoot.leaves.where((leaf) => leaf.region.startsWith('editor')),
        hasLength(1),
      );

      // With no group above, moving up creates one above and preserves the view.
      final otherBeforeUp = _fieldForDocument(tester, otherId);
      final otherStateBeforeUp = tester.state<RustTextInputFieldState>(
        find.byKey(otherBeforeUp.key!),
      );
      await execute('workbench.action.moveEditorToAboveGroup');
      await expectViewPreserved(otherBeforeUp, otherStateBeforeUp, otherId);
      expect(sessionStore.tryLoad()?['focused'], 'editor-2');
      savedRoot = layoutStore.tryLoad()!;
      expect(savedRoot.parentSplitOf('editor-2')!.axis, Axis.vertical);
      expect(
        savedRoot
            .parentSplitOf('editor-2')!
            .children
            .map((node) => (node as WbLeaf).region),
        ['editor-2', 'editor'],
      );

      // Moving down finds the existing group and removes the empty source leaf.
      final otherBeforeDown = _fieldForDocument(tester, otherId);
      final otherStateBeforeDown = tester.state<RustTextInputFieldState>(
        find.byKey(otherBeforeDown.key!),
      );
      await execute('workbench.action.moveEditorToBelowGroup');
      await expectViewPreserved(otherBeforeDown, otherStateBeforeDown, otherId);
      expect(sessionStore.tryLoad()?['focused'], 'editor');
      savedRoot = layoutStore.tryLoad()!;
      expect(
        savedRoot.leaves.where((leaf) => leaf.region.startsWith('editor')),
        hasLength(1),
      );
      expect(
        (WbNode.fromJson(savedRoot.toJson()) as WbSplit).toJson(),
        savedRoot.toJson(),
      );

      // Splitting copies a view; moving it back to its existing document
      // focuses that view and closes the duplicate safely.
      await execute('workbench.action.splitEditorRight');
      expect(sessionStore.tryLoad()?['focused'], 'editor-2');
      expect(find.byType(RustTextInputField), findsNWidgets(2));
      await execute('workbench.action.splitEditorDown');
      expect(sessionStore.tryLoad()?['focused'], 'editor-3');
      expect(find.byType(RustTextInputField), findsNWidgets(3));

      await tester.tap(find.bySemanticsLabel('other.rs 编辑器 2'));
      await tester.pump(const Duration(milliseconds: 100));
      final belowTarget = _fieldWithLabel(tester, 'other.rs 编辑器 3');
      final belowTargetState = tester.state<RustTextInputFieldState>(
        find.byKey(belowTarget.key!),
      );
      await execute('workbench.action.moveEditorToBelowGroup');
      expect(sessionStore.tryLoad()?['focused'], 'editor-3');
      await expectViewPreserved(belowTarget, belowTargetState, otherId);

      final leftTarget = _fieldWithLabel(tester, 'other.rs 主编辑器');
      final leftTargetState = tester.state<RustTextInputFieldState>(
        find.byKey(leftTarget.key!),
      );
      await execute('workbench.action.moveEditorToLeftGroup');
      expect(sessionStore.tryLoad()?['focused'], 'editor');
      await expectViewPreserved(leftTarget, leftTargetState, otherId);
      expect(find.byType(RustTextInputField), findsOneWidget);
      expect(
        layoutStore
            .tryLoad()!
            .leaves
            .where((leaf) => leaf.region.startsWith('editor')),
        hasLength(1),
      );

      final savedSession = sessionStore.tryLoad()!;
      final groups =
          (savedSession['groups'] as List).cast<Map<String, Object?>>();
      final editor = groups.singleWhere((group) => group['region'] == 'editor');
      final paths = (editor['docs'] as List)
          .cast<Map<String, Object?>>()
          .map((doc) => doc['path'])
          .toList();
      expect(paths, hasLength(2),
          reason: 'the document appears only once in the target group');
    },
  );
}
