import 'dart:convert';
import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
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

Finder _tab(String region, int id) => find
    .descendant(
      of: find.byKey(ValueKey('editor-tab-strip-$region')),
      matching: find.byKey(ValueKey('tab-$id')),
    )
    .hitTestable();

Finder _overflow(String region) =>
    find.byKey(ValueKey('editor-tab-overflow-$region'));

Finder _overflowItem(String region, int id) =>
    find.byKey(ValueKey('editor-tab-overflow-item-$region-$id'));

void main() {
  late Directory temp;
  late Directory workspace;
  late LayoutStore layoutStore;
  late SessionStore sessionStore;

  String baseOf() => temp.path.replaceAll(r'\', '/');

  Future<void> prepareWorkspace(WidgetTester tester, String tabMode) async {
    tester.view.physicalSize = const Size(2400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    temp = Directory.systemTemp.createTempSync('alula-tab-overflow');
    workspace = Directory('${temp.path}/workspace')..createSync();
    final files = <int, File>{
      10: File('${workspace.path}/alpha.rs')
        ..writeAsStringSync('fn alpha() {}\n'),
      20: File('${workspace.path}/beta.rs')
        ..writeAsStringSync('fn beta() {}\n'),
      21: File('${workspace.path}/gamma.rs')
        ..writeAsStringSync('fn gamma() {}\n'),
      22: File('${workspace.path}/delta.rs')
        ..writeAsStringSync('fn delta() {}\n'),
    };
    layoutStore = LayoutStore(path: '${baseOf()}/layout.json');
    sessionStore = SessionStore(path: '${baseOf()}/session.json');
    final layout = defaultLayout();
    expect(layout.splitLeaf('editor', 'editor-2', Axis.horizontal), isNotNull);
    layoutStore.save(layout);
    File('${baseOf()}/session.json').writeAsStringSync(jsonEncode({
      'v': 1,
      'editorTabMode': tabMode,
      'focused': 'editor',
      'groups': [
        {
          'region': 'editor',
          'docs': [
            {'id': 10, 'path': files[10]!.path},
          ],
          'active': 10,
        },
        {
          'region': 'editor-2',
          'docs': [
            {'id': 20, 'path': files[20]!.path},
            {'id': 21, 'path': files[21]!.path},
            {'id': 22, 'path': files[22]!.path},
          ],
          'active': 20,
          'sticky': [22],
        },
      ],
    }));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await _deleteDirectoryWithRetry(temp);
    });
  }

  Future<void> mountPage(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: WorkbenchPage(
        autoFolder: workspace.path,
        layoutStore: layoutStore,
        sessionStore: sessionStore,
        keybindingsStore:
            KeybindingsStore(path: '${baseOf()}/keybindings.json'),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
  }

  Map savedGroupFor(String region) =>
      (sessionStore.tryLoad()?['groups'] as List)
          .cast<Map>()
          .firstWhere((group) => group['region'] == region);

  testWidgets('group overflow lists every document in single and no-tab modes',
      (tester) async {
    await prepareWorkspace(tester, 'single');
    await mountPage(tester);

    expect(_overflow('editor-2'), findsOneWidget,
        reason: 'the group list remains available while tabs are single');
    await tester.tap(_overflow('editor-2'));
    await tester.pumpAndSettle();
    expect(_overflowItem('editor-2', 20), findsOneWidget);
    expect(_overflowItem('editor-2', 21), findsOneWidget);
    expect(_overflowItem('editor-2', 22), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(savedGroupFor('editor-2')['active'], 20,
        reason: 'cancel leaves the group selection unchanged');
    expect(sessionStore.tryLoad()?['focused'], 'editor',
        reason:
            'opening or canceling a group list does not activate that group');

    await tester.tap(_overflow('editor-2'));
    await tester.pumpAndSettle();
    await tester.tap(_overflowItem('editor-2', 21));
    await tester.pumpAndSettle();
    expect(savedGroupFor('editor-2')['active'], 21);
    expect(sessionStore.tryLoad()?['focused'], 'editor-2');
    expect((savedGroupFor('editor-2')['docs'] as List), hasLength(3),
        reason: 'selecting an entry activates an existing document');

    await tester.pumpWidget(const SizedBox.shrink());
    // Persist the no-tabs setting through the supported session format.
    final saved = sessionStore.tryLoad()!;
    saved['editorTabMode'] = 'none';
    sessionStore.save(saved);
    await tester.pumpWidget(const SizedBox.shrink());
    await mountPage(tester);
    expect(find.byKey(const ValueKey('tab-21')), findsNothing);
    expect(_overflow('editor-2'), findsOneWidget,
        reason: 'the group list remains available while tabs are hidden');
    await tester.tap(_overflow('editor-2'));
    await tester.pumpAndSettle();
    expect(_overflowItem('editor-2', 20), findsOneWidget);
    expect(_overflowItem('editor-2', 21), findsOneWidget);
    expect(_overflowItem('editor-2', 22), findsOneWidget);
  });

  testWidgets('inactive-group MRU picker preserves dirty text and undo state',
      (tester) async {
    await prepareWorkspace(tester, 'multiple');
    await mountPage(tester);

    await tester.tap(_tab('editor-2', 21));
    await tester.pumpAndSettle();
    final gammaField = find.byWidgetPredicate(
      (widget) =>
          widget is RustTextInputField &&
          widget.semanticsLabel == 'gamma.rs 编辑器 2',
    );
    expect(gammaField, findsOneWidget);
    final gammaDocument =
        tester.widget<RustTextInputField>(gammaField).inputWindow.document;
    await tester.tap(gammaField);
    const editedText = 'fn gamma() { let value = 7; }\n';
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: editedText,
      selection: TextSelection.collapsed(offset: editedText.length),
    ));
    await tester.pump();
    await tester.pump();
    expect(
        tester
            .widget<RustTextInputField>(gammaField)
            .inputWindow
            .document
            .isDirty,
        isTrue);
    final selectedBeforeSwitch = tester
        .state<RustTextInputFieldState>(gammaField)
        .editingValue
        .selection;

    await tester.tap(_tab('editor-2', 22));
    await tester.pumpAndSettle();
    await tester.tap(_tab('editor', 10));
    await tester.pumpAndSettle();
    expect(sessionStore.tryLoad()?['focused'], 'editor');

    await tester.tap(_overflow('editor-2'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(savedGroupFor('editor-2')['active'], 22);
    expect(sessionStore.tryLoad()?['focused'], 'editor');
    expect(
      gammaDocument.resync().content,
      editedText,
    );

    await tester.tap(_overflow('editor-2'));
    await tester.pumpAndSettle();
    final orderedItems =
        [22, 21, 20].map((id) => _overflowItem('editor-2', id));
    final itemCenters = orderedItems.map(tester.getCenter).toList();
    expect(itemCenters[0].dy, lessThan(itemCenters[1].dy));
    expect(itemCenters[1].dy, lessThan(itemCenters[2].dy));
    expect(
      find.byKey(const ValueKey('editor-tab-overflow-active-editor-2-22')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-tab-overflow-sticky-editor-2-22')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-tab-overflow-dirty-editor-2-21')),
      findsOneWidget,
    );

    await tester.tap(_overflowItem('editor-2', 21));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 700));
    final group = savedGroupFor('editor-2');
    expect(group['active'], 21);
    expect(group['sticky'], [22]);
    expect(sessionStore.tryLoad()?['focused'], 'editor-2');
    expect((group['docs'] as List), hasLength(3));
    expect(
      tester
          .widget<RustTextInputField>(gammaField)
          .inputWindow
          .document
          .resync()
          .content,
      editedText,
    );
    expect(
      tester.state<RustTextInputFieldState>(gammaField).editingValue.selection,
      selectedBeforeSwitch,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<RustTextInputField>(gammaField)
          .inputWindow
          .document
          .resync()
          .content,
      'fn gamma() {}\n',
      reason:
          'the document undo history survives opening and selecting the picker',
    );
  });
}
