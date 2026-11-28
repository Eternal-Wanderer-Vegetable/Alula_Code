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

void main() {
  testWidgets(
    'directional split commands copy the active view and persist nested order',
    (tester) async {
      final temp =
          Directory.systemTemp.createTempSync('alula-directional-split');
      addTearDown(() => _unmountAndDeleteTempDirectory(tester, temp));

      final workspace = Directory('${temp.path}/workspace')..createSync();
      final file = File('${workspace.path}/main.rs')
        ..writeAsStringSync('fn main() { println!("linux-save-ok"); }');
      final base = temp.path.replaceAll(r'\', '/');
      final layoutStore = LayoutStore(path: '$base/layout.json');
      final initialLayout = defaultLayout();
      layoutStore.save(initialLayout);
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

      await tester.tap(find.byKey(const ValueKey('close-tab-editor-1')));
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byType(RustTextInputField), findsNothing);
      expect(
        await commands!.execute('workbench.action.splitEditorRight'),
        CommandExecutionStatus.executed,
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(layoutStore.tryLoad()!.toJson(), initialLayout.toJson(),
          reason: 'split without an active document is a no-op');
      expect(find.byType(RustTextInputField), findsNothing);

      await tester.tap(find.text('main.rs').first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
          file.readAsStringSync(), 'fn main() { println!("linux-save-ok"); }');

      Future<void> executeSplit({
        required String command,
        required String region,
        required Axis axis,
        required List<String> directOrder,
        required int viewCount,
      }) async {
        expect(
          await commands!.execute(command),
          CommandExecutionStatus.executed,
          reason: '$command is registered',
        );
        await tester.pump(const Duration(milliseconds: 600));

        expect(sessionStore.tryLoad()?['focused'], region,
            reason: 'the newly created group receives focus');
        final restoredRoot = layoutStore.tryLoad();
        expect(restoredRoot, isNotNull);
        final parent = restoredRoot!.parentSplitOf(region)!;
        expect(parent.axis, axis);
        expect(
          parent.children.map((node) => (node as WbLeaf).region),
          directOrder,
        );
        expect(
            restoredRoot.leaves.map((leaf) => leaf.region),
            containsAll([
              'activity',
              'sidebar',
              'secondarySidebar',
              'editor',
              'editor-2',
              'panel',
              for (var index = 3; index <= viewCount; index++) 'editor-$index',
            ]));

        final fields = find.byType(RustTextInputField);
        expect(fields, findsNWidgets(viewCount));
        final views = tester.widgetList<RustTextInputField>(fields).toList();
        expect(views.map((view) => view.inputWindow.document.id).toSet(),
            hasLength(1));
        expect(views.map((view) => view.inputWindow).toSet(),
            hasLength(viewCount));
        expect(views.map((view) => view.scrollController).toSet(),
            hasLength(viewCount));

        final roundTrip = WbNode.fromJson(restoredRoot.toJson()) as WbSplit;
        expect(roundTrip.toJson(), restoredRoot.toJson());
        expect(roundTrip.parentSplitOf(region)!.axis, axis);
      }

      // The existing toolbar command remains the default Right split.
      await executeSplit(
        command: 'editor.split',
        region: 'editor-2',
        axis: Axis.horizontal,
        directOrder: ['editor', 'editor-2'],
        viewCount: 2,
      );
      await executeSplit(
        command: 'workbench.action.splitEditorLeft',
        region: 'editor-3',
        axis: Axis.horizontal,
        directOrder: ['editor-3', 'editor-2'],
        viewCount: 3,
      );
      await executeSplit(
        command: 'workbench.action.splitEditorUp',
        region: 'editor-4',
        axis: Axis.vertical,
        directOrder: ['editor-4', 'editor-3'],
        viewCount: 4,
      );
      await executeSplit(
        command: 'workbench.action.splitEditorDown',
        region: 'editor-5',
        axis: Axis.vertical,
        directOrder: ['editor-4', 'editor-5'],
        viewCount: 5,
      );
      await executeSplit(
        command: 'workbench.action.splitEditorRight',
        region: 'editor-6',
        axis: Axis.horizontal,
        directOrder: ['editor-5', 'editor-6'],
        viewCount: 6,
      );

      final semantics = tester.ensureSemantics();
      final rects = {
        for (final label in [
          'main.rs 主编辑器',
          'main.rs 编辑器 2',
          'main.rs 编辑器 3',
          'main.rs 编辑器 4',
          'main.rs 编辑器 5',
          'main.rs 编辑器 6',
        ])
          label: tester.getRect(find.bySemanticsLabel(label)),
      };
      semantics.dispose();
      expect(
          rects['main.rs 主编辑器']!.left, lessThan(rects['main.rs 编辑器 3']!.left));
      expect(
          rects['main.rs 编辑器 3']!.left, lessThan(rects['main.rs 编辑器 2']!.left));
      expect(
          rects['main.rs 编辑器 4']!.top, lessThan(rects['main.rs 编辑器 5']!.top));
      expect(
          rects['main.rs 编辑器 5']!.top, lessThan(rects['main.rs 编辑器 3']!.top));
      expect(
          rects['main.rs 编辑器 5']!.left, lessThan(rects['main.rs 编辑器 6']!.left));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(MaterialApp(
        home: WorkbenchPage(
          autoFolder: workspace.path,
          layoutStore: layoutStore,
          sessionStore: sessionStore,
          keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byType(RustTextInputField), findsNWidgets(6));
      expect(sessionStore.tryLoad()?['focused'], 'editor-6');
      final remountedRoot = layoutStore.tryLoad()!;
      expect(
          remountedRoot.leaves
              .where((leaf) => leaf.region.startsWith('editor')),
          hasLength(6));
      expect(
        (WbNode.fromJson(remountedRoot.toJson()) as WbSplit).toJson(),
        remountedRoot.toJson(),
      );
    },
  );
}
