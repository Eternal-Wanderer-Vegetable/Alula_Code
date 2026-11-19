import 'dart:convert';
import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/gestures.dart'
    show kMiddleMouseButton, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _openEditorsDoc(String region, int id) =>
    find.byKey(ValueKey('open-editors-doc-$region-$id'));

Finder _openEditorsClose(String region, int id) =>
    find.byKey(ValueKey('open-editors-close-$region-$id'));

Finder _tabIn(String region, int id) => find.descendant(
      of: find.byKey(ValueKey('editor-tab-strip-$region')),
      matching: find.byKey(ValueKey('tab-$id')),
    );

void main() {
  late Directory temp;
  late Directory workspace;
  late LayoutStore layoutStore;
  late SessionStore sessionStore;

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
        keybindingsStore:
            KeybindingsStore(path: '${baseOf()}/keybindings.json'),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> prepareWorkspace(WidgetTester tester) async {
    temp = Directory.systemTemp.createTempSync('alula-open-editors');
    workspace = Directory('${temp.path}/workspace')..createSync();
    layoutStore = LayoutStore(path: '${baseOf()}/layout.json');
    sessionStore = SessionStore(path: '${baseOf()}/session.json');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await _deleteDirectoryWithRetry(temp);
    });
  }

  Future<void> seedTwoGroups(WidgetTester tester) async {
    final alpha = File('${workspace.path}/alpha.rs')
      ..writeAsStringSync('fn alpha() {}\n');
    final beta = File('${workspace.path}/beta.rs')
      ..writeAsStringSync('fn beta() {}\n');
    final layout = defaultLayout();
    layout.splitLeaf('editor', 'editor-2', Axis.horizontal);
    layoutStore.save(layout);
    File('${baseOf()}/session.json').writeAsStringSync(jsonEncode({
      'v': 1,
      'editorTabMode': 'multiple',
      'focused': 'editor-2',
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
      ],
    }));
  }

  setUpClipboardCapture(WidgetTester tester, List<String> captured) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          captured.add(call.arguments['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
  }

  testWidgets(
      'path sorting changes sidebar projection only and restores preference',
      (tester) async {
    await prepareWorkspace(tester);
    final zeta = File('${workspace.path}/a/z%done#.rs')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('fn zeta() {}\n');
    final alpha = File('${workspace.path}/z/alpha.rs')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('fn alpha() {}\n');
    sessionStore.save({
      'v': 1,
      'focused': 'editor',
      'groups': [
        {
          'region': 'editor',
          'active': 10,
          'docs': [
            {'id': 10, 'path': zeta.path},
            {'id': 11, 'path': alpha.path},
          ],
        },
      ],
    });
    await mountPage(tester);
    final field = tester
        .widgetList<RustTextInputField>(find.byType(RustTextInputField))
        .firstWhere((field) => field.inputWindow.document.id == 10);
    final inputWindow = field.inputWindow;
    final document = inputWindow.document;
    final text = document.resync().content;
    final tabZeta = tester.getTopLeft(_tabIn('editor', 10));
    final tabAlpha = tester.getTopLeft(_tabIn('editor', 11));
    expect(tester.getTopLeft(_openEditorsDoc('editor', 10)).dy,
        lessThan(tester.getTopLeft(_openEditorsDoc('editor', 11)).dy));

    Future<void> choose(String mode) async {
      await tester.tap(find.byKey(const ValueKey('open-editors-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('open-editors-sort-$mode')));
      await tester.pumpAndSettle();
    }

    await choose('fullPath');
    expect(tester.getTopLeft(_openEditorsDoc('editor', 10)).dy,
        lessThan(tester.getTopLeft(_openEditorsDoc('editor', 11)).dy));
    await choose('alphabetical');
    expect(tester.getTopLeft(_openEditorsDoc('editor', 11)).dy,
        lessThan(tester.getTopLeft(_openEditorsDoc('editor', 10)).dy));
    expect(tester.getTopLeft(_tabIn('editor', 10)), tabZeta);
    expect(tester.getTopLeft(_tabIn('editor', 11)), tabAlpha);
    final after = tester
        .widgetList<RustTextInputField>(find.byType(RustTextInputField))
        .firstWhere((field) => field.inputWindow.document.id == 10);
    expect(after.inputWindow, same(inputWindow));
    expect(after.inputWindow.document, same(document));
    expect(document.resync().content, text);
    await tester.pump(const Duration(milliseconds: 700));
    expect(sessionStore.tryLoad()?['openEditorsSortOrder'], 'alphabetical');
    final saved = sessionStore.tryLoad()!;
    final groups = saved['groups'] as List;
    expect((groups.first as Map)['active'], 10);
    expect(
        ((groups.first as Map)['docs'] as List)
            .map((doc) => (doc as Map)['id'])
            .take(2),
        [10, 11]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await mountPage(tester);
    expect(tester.getTopLeft(_openEditorsDoc('editor', 11)).dy,
        lessThan(tester.getTopLeft(_openEditorsDoc('editor', 10)).dy));
    await choose('editorOrder');
    expect(tester.getTopLeft(_openEditorsDoc('editor', 10)).dy,
        lessThan(tester.getTopLeft(_openEditorsDoc('editor', 11)).dy));
    await choose('fullPath');
    expect(tester.getTopLeft(_openEditorsDoc('editor', 10)).dy,
        lessThan(tester.getTopLeft(_openEditorsDoc('editor', 11)).dy));
    await tester.tap(_openEditorsDoc('editor', 11));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 700));
    expect(((sessionStore.tryLoad()!['groups'] as List).first as Map)['active'],
        11);
    await tester.tap(_openEditorsClose('editor', 10));
    await tester.pumpAndSettle();
    expect(_openEditorsDoc('editor', 10), findsNothing);
    expect(_openEditorsDoc('editor', 11), findsOneWidget);
    expect(alpha.readAsStringSync(), 'fn alpha() {}\n');
    expect(zeta.readAsStringSync(), 'fn zeta() {}\n');
  });

  testWidgets(
    'the section renders grouped rows, the active highlight, and the dirty count',
    (tester) async {
      await prepareWorkspace(tester);
      await seedTwoGroups(tester);
      await mountPage(tester);
      expect(
          find.byKey(const ValueKey('open-editors-section')), findsOneWidget);
      expect(find.byKey(const ValueKey('open-editors-header')), findsOneWidget);
      expect(find.byKey(const ValueKey('open-editors-group-editor')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('open-editors-group-editor-2')),
          findsOneWidget);
      expect(_openEditorsDoc('editor', 10), findsOneWidget);
      expect(_openEditorsDoc('editor-2', 11), findsOneWidget);
      expect(
          find.byKey(const ValueKey('open-editors-dirty-count')), findsNothing,
          reason: 'no dirty documents yet');

      // Make beta dirty: the label gains the marker and the badge shows 1.
      final field = tester
          .widgetList<RustTextInputField>(find.byType(RustTextInputField))
          .firstWhere((field) => field.inputWindow.document.id == 11);
      field.focusNode!.requestFocus();
      await tester.pump();
      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: 'dirty line\n',
        selection: TextSelection.collapsed(offset: 5),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('open-editors-dirty-count')),
          findsOneWidget);
      expect(
        tester
            .widget<Text>(find.descendant(
              of: find.byKey(const ValueKey('open-editors-dirty-count')),
              matching: find.byType(Text),
            ))
            .data,
        '1',
      );
      expect(
        find.text('beta.rs •', findRichText: true),
        findsWidgets,
        reason: 'the dirty marker shows on the Open Editors row',
      );
    },
  );

  testWidgets(
    'clicking a row activates the document and the copy path lands in the clipboard',
    (tester) async {
      await prepareWorkspace(tester);
      await seedTwoGroups(tester);
      final captured = <String>[];
      await mountPage(tester);
      setUpClipboardCapture(tester, captured);
      expect(sessionStore.tryLoad()?['focused'], 'editor-2');

      // Click the alpha row: alpha activates in its group and the group
      // gains focus.
      await tester.tap(_openEditorsDoc('editor', 10));
      await tester.pumpAndSettle();
      // 推进 500ms 会话保存防抖，使断言读到持久化状态。
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(sessionStore.tryLoad()?['focused'], 'editor');
      expect(_tabIn('editor', 10), findsOneWidget);
      expect(
        tester
            .widget<Container>(find
                .descendant(
                  of: _openEditorsDoc('editor', 10),
                  matching: find.byType(Container),
                )
                .first)
            .color,
        const Color(0xFF22262D),
        reason: 'the active row is highlighted',
      );

      // Right-click the beta row and copy its path.
      await tester.tap(_openEditorsDoc('editor-2', 11),
          buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('复制路径'));
      await tester.pumpAndSettle();
      expect(captured, hasLength(1));
      expect(captured.single, contains('beta.rs'));
    },
  );

  testWidgets(
    'keyboard focus with Enter activates the row and closing uses the dirty-safe route',
    (tester) async {
      await prepareWorkspace(tester);
      await seedTwoGroups(tester);
      await mountPage(tester);
      expect(sessionStore.tryLoad()?['focused'], 'editor-2');

      // Focus the alpha row and press Enter: the row activates.
      final focus = tester.widget<Focus>(
          find.byKey(const ValueKey('open-editors-focus-editor-10')));
      focus.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(sessionStore.tryLoad()?['focused'], 'editor',
          reason: 'Enter activates the focused row');

      // The close buttons run the dirty-safe close route: the clean
      // documents close and the emptied group disappears (the welcome
      // untitled re-attaches to the focused group at mount).
      await tester.tap(_openEditorsClose('editor-2', 11));
      await tester.pumpAndSettle();
      await tester.tap(_openEditorsClose('editor-2', 1));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(_openEditorsDoc('editor-2', 11), findsNothing);
      expect(
          find.byKey(const ValueKey('editor-tab-strip-editor-2')), findsNothing,
          reason: 'the emptied group is removed');
    },
  );

  testWidgets(
      'middle-click closes the row in its owner group without activating it',
      (tester) async {
    await prepareWorkspace(tester);
    await seedTwoGroups(tester);
    await mountPage(tester);
    expect(sessionStore.tryLoad()?['focused'], 'editor-2');

    await tester.tap(
      _openEditorsDoc('editor', 10),
      buttons: kMiddleMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(_openEditorsDoc('editor', 10), findsNothing);
    expect(_openEditorsDoc('editor-2', 11), findsOneWidget);
    expect(
      sessionStore.tryLoad()?['focused'],
      'editor-2',
      reason: 'middle-clicking another group does not activate its row',
    );
    expect(File('${workspace.path}/alpha.rs').readAsStringSync(),
        'fn alpha() {}\n');
  });

  testWidgets('middle-click dirty close can cancel without losing edits',
      (tester) async {
    await prepareWorkspace(tester);
    await seedTwoGroups(tester);
    await mountPage(tester);
    final field = tester
        .widgetList<RustTextInputField>(find.byType(RustTextInputField))
        .firstWhere((field) => field.inputWindow.document.id == 10);
    const edited = 'fn alpha() {}\n// keep this edit\n';
    field.focusNode!.requestFocus();
    await tester.pump();
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: edited,
      selection: TextSelection.collapsed(offset: edited.length),
    ));
    await tester.pump();
    await tester.pump();
    expect(field.inputWindow.document.isDirty, isTrue);

    await tester.tap(_openEditorsDoc('editor-2', 11));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 700));
    expect(sessionStore.tryLoad()?['focused'], 'editor-2');

    await tester.tap(
      _openEditorsDoc('editor', 10),
      buttons: kMiddleMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-close-dirty-dialog')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('editor-close-cancel')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(_openEditorsDoc('editor', 10), findsOneWidget);
    expect(field.inputWindow.document.resync().content, edited);
    expect(field.inputWindow.document.isDirty, isTrue);
    expect(File('${workspace.path}/alpha.rs').readAsStringSync(),
        'fn alpha() {}\n');
    expect(sessionStore.tryLoad()?['focused'], 'editor-2');
  });

  testWidgets(
    'the collapse toggle persists across a session restore',
    (tester) async {
      await prepareWorkspace(tester);
      await seedTwoGroups(tester);
      await mountPage(tester);
      expect(_openEditorsDoc('editor', 10), findsOneWidget,
          reason: 'the section starts expanded');

      await tester.tap(find.byKey(const ValueKey('open-editors-header')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(_openEditorsDoc('editor', 10), findsNothing,
          reason: 'the collapsed section hides the rows');
      expect(sessionStore.tryLoad()?['openEditorsCollapsed'], isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await mountPage(tester);
      expect(_openEditorsDoc('editor', 10), findsNothing,
          reason: 'session restore reapplies the collapsed state');
      expect(sessionStore.tryLoad()?['openEditorsCollapsed'], isTrue);

      // Re-expanding shows the rows again.
      await tester.tap(find.byKey(const ValueKey('open-editors-header')));
      await tester.pumpAndSettle();
      expect(_openEditorsDoc('editor', 10), findsOneWidget);
    },
  );
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
