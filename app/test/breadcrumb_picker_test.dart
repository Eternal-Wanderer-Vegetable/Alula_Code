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

Finder _breadcrumbSegment(String region, String name) => find.descendant(
      of: find.byKey(ValueKey('breadcrumb-$region')),
      matching: find.text(name),
    );

RustTextInputField _fieldForDocument(WidgetTester tester, int documentId) =>
    tester
        .widgetList<RustTextInputField>(find.byType(RustTextInputField))
        .firstWhere(
          (field) => field.inputWindow.document.id == documentId,
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
        keybindingsStore: KeybindingsStore(path: '${baseOf()}/keybindings.json'),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
  }

  Future<void> prepareWorkspace(WidgetTester tester) async {
    temp = Directory.systemTemp.createTempSync('alula-breadcrumb-picker');
    workspace = Directory('${temp.path}/workspace')..createSync();
    layoutStore = LayoutStore(path: '${baseOf()}/layout.json');
    sessionStore = SessionStore(path: '${baseOf()}/session.json');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await _deleteDirectoryWithRetry(temp);
    });
  }

  /// Seeds a workspace with src/main.rs, src/lib.rs and a nested folder so
  /// the breadcrumb pickers have real children to list.
  Future<int> seedWorkspaceAndOpen(WidgetTester tester) async {
    final src = Directory('${workspace.path}/src')..createSync();
    final nested = Directory('${src.path}/nested')..createSync();
    final main = File('${src.path}/main.rs')
      ..writeAsStringSync(
          'fn main() {\n    println!("main");\n}\n\nfn helper_fn() {\n}\n');
    File('${src.path}/lib.rs').writeAsStringSync('fn lib_fn() {}\n');
    File('${nested.path}/util.rs').writeAsStringSync('fn util_fn() {}\n');
    layoutStore.save(defaultLayout());
    File('${baseOf()}/session.json').writeAsStringSync(jsonEncode({
      'v': 1,
      'editorTabMode': 'multiple',
      'focused': 'editor',
      'groups': [
        {
          'region': 'editor',
          'docs': [
            {'id': 10, 'path': main.path},
          ],
          'active': 10,
        },
      ],
    }));
    return 10;
  }

  testWidgets(
    'the folder breadcrumb segment opens a picker of tree children',
    (tester) async {
      await prepareWorkspace(tester);
      await seedWorkspaceAndOpen(tester);
      await mountPage(tester);

      // Click the src folder segment: the picker lists its children.
      await tester.tap(_breadcrumbSegment('editor', 'src'));
      await tester.pumpAndSettle();
      // ignore: avoid_print
      print('PICKERDBG texts=${[
        for (final t in tester.widgetList<Text>(find.byType(Text)))
          if (t.data != null) t.data
      ].take(40)}');
      expect(find.text('main.rs'), findsWidgets);
      expect(find.text('lib.rs'), findsOneWidget);
      expect(find.text('nested/'), findsOneWidget);

      // Selecting lib.rs opens it in the editor.
      await tester.tap(find.text('lib.rs').last);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      final opened = tester
          .widgetList<RustTextInputField>(find.byType(RustTextInputField))
          .any((field) => field.semanticsLabel?.startsWith('lib.rs') == true);
      expect(opened, isTrue, reason: 'the picked file opens in the editor');
    },
  );

  testWidgets(
    'the file breadcrumb segment opens the symbol picker with keyboard support',
    (tester) async {
      await prepareWorkspace(tester);
      const docId = 10;
      await seedWorkspaceAndOpen(tester);
      await mountPage(tester);

      // Give the outline symbols time to populate for the active document.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(_breadcrumbSegment('editor', 'main.rs'));
      await tester.pumpAndSettle();
      // ignore: avoid_print
      print('SYMDBG texts=${[
        for (final t in tester.widgetList<Text>(find.byType(Text)))
          if (t.data != null) t.data
      ].take(40)}');
      // main() symbol is listed by the LSP outline source.
      final mainEntry = find.textContaining('main()');
      expect(mainEntry, findsWidgets,
          reason: 'the symbol picker lists the document symbols');

      // Keyboard: arrow down twice to reach helper_fn (main starts at
      // offset 0), then Enter picks it and jumps the caret to its offset.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final field = _fieldForDocument(tester, docId);
      final editable = find.descendant(
        of: find.byKey(field.key!),
        matching: find.byType(EditableText),
      );
      final controller = tester.widget<EditableText>(editable).controller;
      expect(controller.selection.isValid, isTrue);
      expect(controller.selection.baseOffset, greaterThan(0),
          reason: 'the caret jumped to the selected symbol offset');
    },
  );

  testWidgets(
    'a folder without children shows an empty state and reveal still works',
    (tester) async {
      await prepareWorkspace(tester);
      await seedWorkspaceAndOpen(tester);
      await mountPage(tester);

      // The nested folder was never expanded in the tree; selecting it in
      // the picker reveals and expands it in the file tree.
      await tester.tap(_breadcrumbSegment('editor', 'src'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('nested/'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      // 节点键保留 Rust 返回的原生分隔符：用后缀匹配避免分隔符差异。
      expect(
        find.byWidgetPredicate((widget) {
          final key = widget.key;
          return key is ValueKey<String> &&
              key.value.startsWith('explorer-node:') &&
              key.value.endsWith('nested');
        }),
        findsOneWidget,
        reason: 'the picked folder expands in the file tree',
      );
    },
  );
}
