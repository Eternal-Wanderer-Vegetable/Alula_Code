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

import 'helpers/native_drag_drop.dart';

Finder _row(String region, int id) =>
    find.byKey(ValueKey('open-editors-doc-$region-$id'));

Finder _strip(String region) =>
    find.byKey(ValueKey('editor-tab-strip-$region'));

Finder _tab(String region, int id) => find.descendant(
      of: _strip(region),
      matching: find.byKey(ValueKey('tab-$id')),
    );

Finder _closeGroup(String region) =>
    find.byKey(ValueKey('open-editors-close-group-$region'));

const _dirtyDialog = ValueKey('editor-close-dirty-dialog');

void main() {
  setUpAll(mockNativeDragDrop);

  late Directory temp;
  late Directory workspace;
  late LayoutStore layoutStore;
  late SessionStore sessionStore;
  late CommandService commands;
  late Map<int, File> files;

  String original(int id) => 'fn original_$id() {\r\n    // 😀\r\n}\r\n';

  Future<void> prepare(WidgetTester tester) async {
    temp =
        Directory.systemTemp.createTempSync('alula-open-editors-close-group');
    workspace = Directory('${temp.path}/workspace')..createSync();
    layoutStore = LayoutStore(path: '${temp.path}/layout.json');
    sessionStore = SessionStore(path: '${temp.path}/session.json');
    files = {};
    tester.view.physicalSize = const Size(2400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => _deleteDirectoryWithRetry(temp));
    });
  }

  void seed({
    required List<int> target,
    List<int> other = const [20],
    List<int> sticky = const [],
    bool split = true,
  }) {
    for (final id in {...target, if (split) ...other}) {
      files[id] = File('${workspace.path}/doc_$id.rs')
        ..writeAsStringSync(original(id));
    }
    final layout = defaultLayout();
    if (split) {
      expect(
          layout.splitLeaf('editor', 'editor-2', Axis.horizontal), isNotNull);
    }
    layoutStore.save(layout);
    sessionStore.save({
      'v': 1,
      'focused': split ? 'editor-2' : 'editor',
      'workspace': workspace.path,
      'groups': [
        {
          'region': 'editor',
          'active': target.isEmpty ? null : target.first,
          'sticky': sticky,
          'docs': [
            for (final id in target) {'id': id, 'path': files[id]!.path},
          ],
        },
        if (split)
          {
            'region': 'editor-2',
            'active': other.last,
            'docs': [
              for (final id in other) {'id': id, 'path': files[id]!.path},
            ],
          },
      ],
    });
  }

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: WorkbenchPage(
        autoFolder: workspace.path,
        layoutStore: layoutStore,
        sessionStore: sessionStore,
        keybindingsStore: KeybindingsStore(path: '${temp.path}/keys.json'),
        onCommandServiceReady: (service) => commands = service,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> finishIo(WidgetTester tester) async {
    for (var attempt = 0; attempt < 10; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  RustTextInputField field(WidgetTester tester, int id) => tester
      .widgetList<RustTextInputField>(find.byType(RustTextInputField))
      .lastWhere((field) => field.inputWindow.document.id == id);

  Future<void> activate(WidgetTester tester, String region, int id) async {
    await tester.ensureVisible(_row(region, id));
    await tester.tap(_row(region, id));
    await tester.pumpAndSettle();
  }

  Future<void> edit(
      WidgetTester tester, String region, int id, String text) async {
    await activate(tester, region, id);
    final editor = field(tester, id);
    editor.focusNode!.requestFocus();
    await tester.pump();
    tester.testTextInput.updateEditingValue(TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    ));
    await tester.pump();
    await tester.pump();
    expect(editor.inputWindow.document.resync().content, text);
    expect(editor.inputWindow.document.isDirty, isTrue);
  }

  Future<void> closeTarget(WidgetTester tester) async {
    // Document activation can scroll the lazy group heading out of the tree.
    final scrollable = find.descendant(
      of: find.byKey(const ValueKey('open-editors-section')),
      matching: find.byType(Scrollable),
    );
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pump();
    await tester.ensureVisible(_closeGroup('editor'));
    final button = tester.widget<IconButton>(_closeGroup('editor'));
    expect(button.tooltip, '关闭编辑器组');
    expect((button.icon as Icon).icon, Icons.close);
    await tester.tap(_closeGroup('editor'));
    await tester.pumpAndSettle();
  }

  void expectOpen(String region, Iterable<int> ids) {
    expect(_strip(region), findsOneWidget);
    for (final id in ids) {
      expect(_row(region, id), findsOneWidget);
      expect(_tab(region, id), findsOneWidget);
    }
  }

  void expectTargetRemoved() {
    expect(_strip('editor'), findsNothing);
    expect(
        find.byKey(const ValueKey('open-editors-group-editor')), findsNothing);
    expect(_closeGroup('editor'), findsNothing);
  }

  void expectDiskUnchanged() {
    for (final entry in files.entries) {
      expect(entry.value.readAsStringSync(), original(entry.key));
    }
  }

  testWidgets(
      'inline close removes the inactive group including sticky editors and preserves other focus',
      (tester) async {
    await prepare(tester);
    seed(target: [10, 11], sticky: [10]);
    await mount(tester);
    expect(sessionStore.tryLoad()?['focused'], 'editor-2');
    final otherWindow = field(tester, 20).inputWindow;
    final otherContent = otherWindow.document.resync().content;
    expect(find.byKey(const ValueKey('sticky-tab-indicator-editor-10')),
        findsOneWidget);
    expect(_closeGroup('editor-2'), findsOneWidget);

    await closeTarget(tester);
    await finishIo(tester);

    expectTargetRemoved();
    for (final id in [10, 11]) {
      expect(_row('editor', id), findsNothing);
    }
    expectOpen('editor-2', [20]);
    expect(field(tester, 20).inputWindow, same(otherWindow));
    expect(otherWindow.document.resync().content, otherContent);
    expect(find.byKey(_dirtyDialog), findsNothing);
    expect(sessionStore.tryLoad()?['focused'], 'editor-2');
    expect(_closeGroup('editor-2'), findsNothing,
        reason: 'the remaining last group has no inline close button');
    expectDiskUnchanged();
  });

  testWidgets('dirty Cancel preserves the whole target group including sticky',
      (tester) async {
    await prepare(tester);
    seed(target: [10, 11, 12], sticky: [12]);
    await mount(tester);
    const edited = 'fn cancelled() {\r\n    // unsaved 😀\r\n}\r\n';
    await edit(tester, 'editor', 11, edited);
    final dirtyWindow = field(tester, 11).inputWindow;
    await activate(tester, 'editor-2', 20);

    await closeTarget(tester);
    expect(find.byKey(_dirtyDialog), findsOneWidget);
    expectOpen('editor', [10, 11, 12]);
    await tester.tap(find.byKey(const ValueKey('editor-close-cancel')));
    await finishIo(tester);

    expect(find.byKey(_dirtyDialog), findsNothing);
    expectOpen('editor', [10, 11, 12]);
    // The other group's row can be offscreen in the lazy list.
    expect(_tab('editor-2', 20), findsOneWidget);
    expect(_closeGroup('editor'), findsOneWidget);
    expect(find.byKey(const ValueKey('sticky-tab-indicator-editor-12')),
        findsOneWidget);
    expect(field(tester, 11).inputWindow, same(dirtyWindow));
    expect(dirtyWindow.document.resync().content, edited);
    expect(dirtyWindow.document.isDirty, isTrue);
    expectDiskUnchanged();
  });

  testWidgets('returning to the original workspace leaves its old close stale',
      (tester) async {
    await prepare(tester);
    seed(target: [10, 11], sticky: [10]);
    // The parent is a different root and keeps the open file paths relative.
    final nextWorkspace = workspace.parent;
    await mount(tester);
    const edited = 'fn keep_after_workspace_switch() {}\n';
    await edit(tester, 'editor', 10, edited);
    final dirtyWindow = field(tester, 10).inputWindow;
    final otherWindow = field(tester, 20).inputWindow;

    await closeTarget(tester);
    expect(find.byKey(_dirtyDialog), findsOneWidget);
    final folderPath = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == '文件夹路径',
    );
    for (final root in [nextWorkspace, workspace]) {
      final switching = commands.execute('file.openFolder');
      await tester.pumpAndSettle();
      await tester.enterText(folderPath, root.path);
      await tester.tap(find.widgetWithText(FilledButton, '打开'));
      await tester.pumpAndSettle();
      expect(await switching, CommandExecutionStatus.executed);
      await finishIo(tester);
      expect(sessionStore.tryLoad()?['workspace'], root.path);
      expect(find.byKey(_dirtyDialog), findsOneWidget);
    }

    await tester.tap(find.byKey(const ValueKey('editor-close-discard')));
    await finishIo(tester);

    expect(find.byKey(_dirtyDialog), findsNothing);
    expect(sessionStore.tryLoad()?['workspace'], workspace.path);
    expectOpen('editor', [10, 11]);
    expect(_tab('editor-2', 20), findsOneWidget);
    expect(find.byKey(const ValueKey('sticky-tab-indicator-editor-10')),
        findsOneWidget);
    expect(field(tester, 10).inputWindow, same(dirtyWindow));
    expect(dirtyWindow.document.resync().content, edited);
    expect(dirtyWindow.document.isDirty, isTrue);
    expect(field(tester, 20).inputWindow, same(otherWindow));
    expectDiskUnchanged();
  });

  testWidgets('dirty Save writes before removing the group and its sticky view',
      (tester) async {
    await prepare(tester);
    seed(target: [10, 11], sticky: [10]);
    await mount(tester);
    const edited = 'fn saved() {\r\n    println!("😀");\r\n}\r\n';
    const otherText = 'fn other_unsaved() {}\n';
    await edit(tester, 'editor', 10, edited);
    await edit(tester, 'editor-2', 20, otherText);
    final otherWindow = field(tester, 20).inputWindow;

    await closeTarget(tester);
    expect(find.byKey(_dirtyDialog), findsOneWidget);
    expectOpen('editor', [10, 11]);
    expect(files[10]!.readAsStringSync(), original(10));
    final dialog = tester.widget<AlertDialog>(find.byKey(_dirtyDialog));
    expect((dialog.content! as Text).data, contains('doc_10.rs'));
    expect((dialog.content! as Text).data, isNot(contains('doc_20.rs')));
    await tester.tap(find.byKey(const ValueKey('editor-close-save')));
    await finishIo(tester);

    expect(find.byKey(_dirtyDialog), findsNothing);
    expectTargetRemoved();
    expectOpen('editor-2', [20]);
    expect(files[10]!.readAsStringSync(), edited);
    expect(files[11]!.readAsStringSync(), original(11));
    expect(files[20]!.readAsStringSync(), original(20));
    expect(field(tester, 20).inputWindow, same(otherWindow));
    expect(otherWindow.document.resync().content, otherText);
    expect(otherWindow.document.isDirty, isTrue);
  });

  testWidgets(
      'shared dirty view closes its owner without prompting or releasing Rust identity',
      (tester) async {
    await prepare(tester);
    seed(target: [10, 11], other: [10, 20], sticky: [10]);
    await mount(tester);
    const edited = 'fn shared_dirty() {\r\n    // 😀\r\n}\r\n';
    await edit(tester, 'editor', 10, edited);
    await activate(tester, 'editor-2', 10);
    final shared = tester
        .widgetList<RustTextInputField>(find.byType(RustTextInputField))
        .where((field) => field.inputWindow.document.id == 10)
        .toList();
    expect(shared, hasLength(2));
    expect(shared.first.inputWindow.document,
        same(shared.last.inputWindow.document));
    final remainingWindow = shared.last.inputWindow;
    final document = remainingWindow.document;

    await closeTarget(tester);
    await finishIo(tester);

    expect(find.byKey(_dirtyDialog), findsNothing);
    expectTargetRemoved();
    expectOpen('editor-2', [10, 20]);
    final remaining = field(tester, 10);
    expect(remaining.inputWindow, same(remainingWindow));
    expect(remaining.inputWindow.document, same(document));
    expect(document.resync().content, edited);
    expect(document.isDirty, isTrue);
    expectDiskUnchanged();
  });

  testWidgets('inline close removes a preexisting empty inactive group',
      (tester) async {
    await prepare(tester);
    seed(target: []);
    await mount(tester);
    expect(_strip('editor'), findsOneWidget);
    expectOpen('editor-2', [20]);
    final otherWindow = field(tester, 20).inputWindow;
    final otherContent = otherWindow.document.resync().content;

    await closeTarget(tester);
    await finishIo(tester);

    expectTargetRemoved();
    expectOpen('editor-2', [20]);
    expect(field(tester, 20).inputWindow, same(otherWindow));
    expect(otherWindow.document.resync().content, otherContent);
    expect(find.byKey(_dirtyDialog), findsNothing);
    expect(sessionStore.tryLoad()?['focused'], 'editor-2');
    expectDiskUnchanged();
  });

  testWidgets(
      'single group has no inline close button and closing all retains it',
      (tester) async {
    await prepare(tester);
    seed(target: [10], sticky: [10], split: false);
    await mount(tester);
    expectOpen('editor', [10]);
    expect(_closeGroup('editor'), findsNothing);
    expect(find.byTooltip('关闭编辑器组'), findsNothing);

    expect(await commands.execute('workbench.action.closeAllGroups'),
        CommandExecutionStatus.executed);
    await finishIo(tester);

    expect(_strip('editor'), findsOneWidget);
    expect(_row('editor', 10), findsNothing);
    expect(find.byType(RustTextInputField), findsNothing);
    expect(_closeGroup('editor'), findsNothing);
    expect(find.byTooltip('关闭编辑器组'), findsNothing);
    expect(find.byKey(_dirtyDialog), findsNothing);
    expectDiskUnchanged();
  });
}

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
