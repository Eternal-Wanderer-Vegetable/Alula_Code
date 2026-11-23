import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/foundation.dart';
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
        keybindingsStore:
            KeybindingsStore(path: '${baseOf()}/keybindings.json'),
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

  Future<int> seedSiblingFilesAndOpen() async {
    final side = Directory('${workspace.path}/src/side')
      ..createSync(recursive: true);
    File('${side.path}/a_target.rs').writeAsStringSync('fn target() {}\n');
    final source = File('${side.path}/z_source.rs')
      ..writeAsStringSync('fn source() {}\n');
    layoutStore.save(defaultLayout());
    File('${baseOf()}/session.json').writeAsStringSync(jsonEncode({
      'v': 1,
      'editorTabMode': 'multiple',
      'focused': 'editor',
      'groups': [
        {
          'region': 'editor',
          'docs': [
            {'id': 10, 'path': source.path},
          ],
          'active': 10,
        },
      ],
    }));
    return 10;
  }

  Future<int> seedNestedOnlyAndOpen() async {
    final nested = Directory('${workspace.path}/src/nested')
      ..createSync(recursive: true);
    final source = File('${nested.path}/main.rs')
      ..writeAsStringSync('fn main() {}\n');
    layoutStore.save(defaultLayout());
    File('${baseOf()}/session.json').writeAsStringSync(jsonEncode({
      'v': 1,
      'editorTabMode': 'multiple',
      'focused': 'editor',
      'groups': [
        {
          'region': 'editor',
          'docs': [
            {'id': 10, 'path': source.path},
          ],
          'active': 10,
        },
      ],
    }));
    return 10;
  }

  testWidgets(
    'the folder breadcrumb lists siblings and focuses the current folder',
    (tester) async {
      await prepareWorkspace(tester);
      await seedWorkspaceAndOpen(tester);
      File('${workspace.path}/notes.txt').writeAsStringSync('workspace notes\n');
      await mountPage(tester);

      await tester.tap(_breadcrumbSegment('editor', 'src'));
      await tester.pumpAndSettle();

      final rows = find.byWidgetPredicate((w) => w is PopupMenuItem<String>);
      final folder = find.descendant(of: rows, matching: find.text('src/'));
      final sibling = find.descendant(of: rows, matching: find.text('notes.txt'));
      expect(folder, findsOneWidget);
      expect(sibling, findsOneWidget);
      expect(Focus.of(tester.element(folder)).hasPrimaryFocus, isTrue);
      expect(find.descendant(of: rows, matching: find.text('lib.rs')), findsNothing);

      await tester.tap(sibling);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      final siblingField = tester
          .widgetList<RustTextInputField>(find.byType(RustTextInputField))
          .singleWhere((field) => field.semanticsLabel!.startsWith('notes.txt'));
      expect(siblingField.focusNode!.hasFocus, isTrue);
    },
  );

  testWidgets(
    'the file breadcrumb lists siblings and focuses the current file',
    (tester) async {
      await prepareWorkspace(tester);
      await seedWorkspaceAndOpen(tester);
      await mountPage(tester);

      await tester.tap(_breadcrumbSegment('editor', 'main.rs'));
      await tester.pumpAndSettle();

      final rows = find.byWidgetPredicate((w) => w is PopupMenuItem<String>);
      final sibling = find.descendant(of: rows, matching: find.text('lib.rs'));
      final current = find.descendant(of: rows, matching: find.text('main.rs'));
      expect(sibling, findsOneWidget);
      expect(current, findsOneWidget);
      expect(Focus.of(tester.element(current)).hasPrimaryFocus, isTrue);
      expect(find.descendant(of: rows, matching: find.text('nested/')),
          findsOneWidget);

      await tester.tap(sibling);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      final siblingField = tester
          .widgetList<RustTextInputField>(find.byType(RustTextInputField))
          .singleWhere((field) => field.semanticsLabel!.startsWith('lib.rs'));
      expect(siblingField.focusNode!.hasFocus, isTrue);
    },
  );

  testWidgets(
    'breadcrumb path rows put directories first and sort numeric names',
    (tester) async {
      await prepareWorkspace(tester);
      await seedWorkspaceAndOpen(tester);
      final src = Directory('${workspace.path}/src');
      for (final name in ['dir10', 'dir2']) {
        Directory('${src.path}/$name').createSync();
      }
      for (final name in ['a10.rs', 'a2.rs', 'a01.rs', 'A1.rs']) {
        File('${src.path}/$name').writeAsStringSync('fn sibling() {}\n');
      }
      await mountPage(tester);

      // Exercise ICU collation for this menu's order.
      await runZoned(
        () async {
          await tester.tap(_breadcrumbSegment('editor', 'main.rs'));
          await tester.pumpAndSettle();
        },
        zoneValues: {#test.allowFormatting: true},
      );
      final rows = find.byWidgetPredicate((w) => w is PopupMenuItem<String>);
      final labels = find.descendant(of: rows, matching: find.byType(Text));
      expect(
        tester.widgetList<Text>(labels).map((label) => label.data),
        [
          'dir2/',
          'dir10/',
          'nested/',
          'A1.rs',
          'a01.rs',
          'a2.rs',
          'a10.rs',
          'lib.rs',
          'main.rs',
        ],
      );
      final current = find.descendant(of: rows, matching: find.text('main.rs'));
      expect(Focus.of(tester.element(current)).hasPrimaryFocus, isTrue);
    },
  );

  testWidgets(
    'the outline breadcrumb segment opens the symbol picker with keyboard support',
    (tester) async {
      await prepareWorkspace(tester);
      const docId = 10;
      await seedWorkspaceAndOpen(tester);
      await mountPage(tester);

      // Give the outline symbols time to populate for the active document.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(_breadcrumbSegment('editor', 'main'));
      await tester.pumpAndSettle();
      // ignore: avoid_print
      print('SYMDBG texts=${[
        for (final t in tester.widgetList<Text>(find.byType(Text)))
          if (t.data != null) t.data
      ].take(40)}');
      expect(find.text('fn helper_fn'), findsOneWidget,
          reason: 'the outline picker lists the document symbols');

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
    'workspace breadcrumbs follow current-version Rust symbol ancestry',
    (tester) async {
      await prepareWorkspace(tester);
      await seedWorkspaceAndOpen(tester);
      const source =
          '\u{FEFF}// 🦊\r\nmod outer {\r\n    fn inner() {}\r\n}\r\nfn sibling() {}\r\n';
      final file = File('${workspace.path}/src/main.rs')
        ..writeAsStringSync(source);
      await mountPage(tester);

      final field = _fieldForDocument(tester, 10);
      final document = field.inputWindow.document;
      final bufferText = document.resync().content;
      final version = document.version;
      final symbols = document.core.lsp.symbols(document.id)!.symbols;
      final inner = symbols.singleWhere((symbol) => symbol['name'] == 'inner');
      int utf16Offset(String needle) =>
          bufferText.substring(0, bufferText.indexOf(needle)).codeUnits.length;
      expect(inner['start_utf16'], utf16Offset('fn inner'));
      final siblingStart = utf16Offset('fn sibling');

      // The initial caret is on the comment line, outside all symbols.
      expect(_breadcrumbSegment('editor', 'outer'), findsNothing);
      final editor = find.descendant(
        of: find.byKey(field.key!),
        matching: find.byType(TextField),
      );
      final controller = tester.widget<TextField>(editor).controller!;
      field.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(_breadcrumbSegment('editor', 'outer'), findsOneWidget);
      expect(_breadcrumbSegment('editor', 'inner'), findsOneWidget);

      // Symbol segments keep their symbol picker instead of being routed as
      // file-system paths; selecting the entry jumps to its UTF-16 start.
      await tester.tap(_breadcrumbSegment('editor', 'inner'));
      await tester.pumpAndSettle();
      final innerEntry = find.descendant(
        of: find.byType(PopupMenuItem<String>),
        matching: find.textContaining('inner'),
      );
      expect(innerEntry, findsOneWidget);
      await tester.tap(innerEntry);
      await tester.pumpAndSettle();
      expect(controller.selection.extentOffset, inner['start_utf16']);
      expect(_breadcrumbSegment('editor', 'outer'), findsOneWidget);
      expect(_breadcrumbSegment('editor', 'inner'), findsOneWidget);
      expect(field.focusNode!.hasFocus, isTrue,
          reason: 'choosing a symbol returns keyboard focus to the editor');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(_breadcrumbSegment('editor', 'outer'), findsNothing);
      expect(_breadcrumbSegment('editor', 'inner'), findsNothing);
      expect(_breadcrumbSegment('editor', 'sibling'), findsOneWidget);

      expect(controller.text, bufferText);
      expect(document.version, version,
          reason: 'following symbol ancestry must not edit the document');
      expect(file.readAsBytesSync(), utf8.encode(source));
      expect(
        document.lineBoundary(controller.selection.extentOffset).line,
        document.lineBoundary(siblingStart).line,
        reason: 'the caret moved to the sibling declaration line',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(_breadcrumbSegment('editor', 'outer'), findsOneWidget);
      expect(_breadcrumbSegment('editor', 'inner'), findsOneWidget);

      // A document version change invalidates the cached symbol path before
      // the debounced outline refresh can return a new snapshot.
      field.focusNode!.requestFocus();
      await tester.pump();
      final editedText = '$bufferText// changed after snapshot';
      tester.testTextInput.updateEditingValue(TextEditingValue(
        text: editedText,
        selection: TextSelection.collapsed(offset: inner['start_utf16'] as int),
      ));
      await tester.pump();
      await tester.pump();
      expect(document.resync().content, editedText);
      expect(document.version, greaterThan(version));
      expect(_breadcrumbSegment('editor', 'outer'), findsNothing);
      expect(_breadcrumbSegment('editor', 'sibling'), findsNothing);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(_breadcrumbSegment('editor', 'outer'), findsOneWidget,
          reason: 'the fresh versioned symbol snapshot restores the path');
      expect(_breadcrumbSegment('editor', 'inner'), findsOneWidget);
      expect(file.readAsBytesSync(), utf8.encode(source));
    },
  );

  testWidgets(
    'the breadcrumb path picker expands a directory and navigates to its child',
    (tester) async {
      await prepareWorkspace(tester);
      await seedWorkspaceAndOpen(tester);
      await mountPage(tester);
      await tester.tap(_breadcrumbSegment('editor', 'main.rs'));
      await tester.pumpAndSettle();

      final rows = find.byWidgetPredicate((w) => w is PopupMenuItem<String>);
      final folder = find.descendant(of: rows, matching: find.text('nested/'));
      final child = find.descendant(of: rows, matching: find.text('util.rs'));
      final current = find.descendant(of: rows, matching: find.text('main.rs'));
      expect(child, findsNothing);
      await tester.tap(folder);
      await tester.pumpAndSettle();
      expect(child, findsOneWidget);
      expect(current, findsOneWidget);
      expect(Focus.of(tester.element(folder)).hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(child, findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(child, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(child, findsOneWidget);
      expect(Focus.of(tester.element(folder)).hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      expect(rows, findsNothing);
      final opened = tester
          .widgetList<RustTextInputField>(find.byType(RustTextInputField))
          .singleWhere((field) => field.semanticsLabel!.startsWith('util.rs'));
      expect(opened.focusNode!.hasFocus, isTrue);
    },
  );

  testWidgets(
    'the breadcrumb path picker applies the default workspace file exclusions',
    (tester) async {
      await prepareWorkspace(tester);
      await seedWorkspaceAndOpen(tester);
      final src = Directory('${workspace.path}/src');
      for (final name in ['.git', '.svn', '.hg', '.jj']) {
        Directory('${src.path}/$name').createSync();
      }
      for (final name in ['.DS_Store', 'Thumbs.db', '.git-notes']) {
        File('${src.path}/$name').writeAsStringSync(name);
      }
      final nested = Directory('${src.path}/nested');
      Directory('${nested.path}/.JJ').createSync();
      File('${nested.path}/Thumbs.db').writeAsStringSync('nested metadata');

      await mountPage(tester);
      await tester.tap(_breadcrumbSegment('editor', 'main.rs'));
      await tester.pumpAndSettle();

      final rows = find.byWidgetPredicate((w) => w is PopupMenuItem<String>);
      Finder entry(String label) => find.descendant(
            of: rows,
            matching: find.text(label),
          );

      expect(entry('main.rs'), findsOneWidget);
      expect(entry('.git-notes'), findsOneWidget);
      for (final name in [
        '.git/',
        '.svn/',
        '.hg/',
        '.jj/',
        '.DS_Store',
        'Thumbs.db',
      ]) {
        expect(entry(name), findsNothing);
      }

      await tester.tap(entry('nested/'));
      await tester.pumpAndSettle();
      expect(entry('util.rs'), findsOneWidget);
      expect(entry('Thumbs.db'), findsNothing);
      expect(
        entry('.JJ/'),
        defaultTargetPlatform == TargetPlatform.linux
            ? findsOneWidget
            : findsNothing,
      );

      await tester.tap(entry('util.rs'));
      await tester.pumpAndSettle();
      expect(rows, findsNothing);
      expect(_breadcrumbSegment('editor', 'util.rs'), findsOneWidget);
      expect(
        File('${nested.path}/Thumbs.db').readAsStringSync(),
        'nested metadata',
      );
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.linux,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'workspace exclusions do not apply to an external breadcrumb path',
    (tester) async {
      await prepareWorkspace(tester);
      final outside = Directory('${workspace.path}-outside')..createSync();
      final source = File('${outside.path}/source.rs')
        ..writeAsStringSync('fn source() {}\n');
      Directory('${outside.path}/.git').createSync();
      File('${outside.path}/Thumbs.db').writeAsStringSync('external metadata');
      layoutStore.save(defaultLayout());
      sessionStore.save({
        'v': 1,
        'editorTabMode': 'multiple',
        'focused': 'editor',
        'groups': [
          {
            'region': 'editor',
            'docs': [
              {'id': 10, 'path': source.path},
            ],
            'active': 10,
          },
        ],
      });
      await mountPage(tester);
      await tester.tap(_breadcrumbSegment('editor', 'source.rs'));
      await tester.pumpAndSettle();

      final rows = find.byWidgetPredicate((w) => w is PopupMenuItem<String>);
      for (final name in ['.git/', 'Thumbs.db', 'source.rs']) {
        expect(find.descendant(of: rows, matching: find.text(name)),
            findsOneWidget);
      }
    },
  );

  testWidgets(
    'Cmd+Enter opens the focused breadcrumb file in a side group',
    (tester) async {
      await prepareWorkspace(tester);
      await seedSiblingFilesAndOpen();
      await mountPage(tester);

      final source = _fieldForDocument(tester, 10);
      final sourceDocument = source.inputWindow.document;
      final originalText = sourceDocument.resync().content;
      final originalVersion = sourceDocument.version;
      final originalSelection = tester
          .widget<EditableText>(find.descendant(
            of: find.byKey(source.key!),
            matching: find.byType(EditableText),
          ))
          .controller
          .selection;
      final sourcePath = File('${workspace.path}/src/side/z_source.rs');
      final originalBytes = sourcePath.readAsBytesSync();

      await tester.tap(_breadcrumbSegment('editor', 'z_source.rs'));
      await tester.pumpAndSettle();
      expect(find.text('a_target.rs'), findsOneWidget);
      expect(find.text('z_source.rs'), findsWidgets);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        expect(HardwareKeyboard.instance.isMetaPressed, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
      await tester.pumpAndSettle();

      final fields = tester.widgetList<RustTextInputField>(
        find.byType(RustTextInputField),
      );
      expect(fields, hasLength(2));
      final sideField = fields.singleWhere(
        (field) => field.semanticsLabel?.startsWith('a_target.rs') == true,
      );
      expect(sideField.focusNode!.hasFocus, isTrue);
      final sourceEditable = tester.widget<EditableText>(find.descendant(
        of: find.byKey(source.key!),
        matching: find.byType(EditableText),
      ));
      expect(sourceEditable.controller.selection, originalSelection);
      expect(sourceDocument.resync().content, originalText);
      expect(sourceDocument.version, originalVersion);
      expect(sourceDocument.isDirty, isFalse);
      expect(sourcePath.readAsBytesSync(), originalBytes);
    },
  );

  testWidgets(
    'Windows Ctrl+Enter opens the focused breadcrumb symbol in a side view',
    (tester) async {
      await prepareWorkspace(tester);
      const docId = 10;
      await seedWorkspaceAndOpen(tester);
      await mountPage(tester);
      await tester.pump(const Duration(milliseconds: 400));

      final source = _fieldForDocument(tester, docId);
      final document = source.inputWindow.document;
      final originalText = document.resync().content;
      final originalVersion = document.version;
      final helperStart = originalText
          .substring(0, originalText.indexOf('fn helper_fn'))
          .codeUnits
          .length;
      final sourceFile = File('${workspace.path}/src/main.rs');
      final originalBytes = sourceFile.readAsBytesSync();
      final sourceEditableFinder = find.descendant(
        of: find.byKey(source.key!),
        matching: find.byType(EditableText),
      );
      final sourceEditable = tester.widget<EditableText>(sourceEditableFinder);
      final originalSelection = sourceEditable.controller.selection;

      await tester.tap(_breadcrumbSegment('editor', 'main'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('breadcrumb-editor-2')), findsOneWidget);
      final fields = tester
          .widgetList<RustTextInputField>(find.byType(RustTextInputField))
          .where((field) => field.inputWindow.document.id == docId)
          .toList();
      expect(fields, hasLength(2), reason: 'the symbol has a side view');
      final sideField =
          fields.singleWhere((field) => field.focusNode!.hasFocus);
      final sideEditable = tester.widget<EditableText>(find.descendant(
        of: find.byKey(sideField.key!),
        matching: find.byType(EditableText),
      ));
      expect(sideEditable.controller.selection.extentOffset, helperStart);
      expect(sourceEditable.controller.selection, originalSelection);
      expect(document.resync().content, originalText);
      expect(document.version, originalVersion);
      expect(document.isDirty, isFalse);
      expect(sourceFile.readAsBytesSync(), originalBytes);
    },
  );

  testWidgets(
    'folder confirmation stays in the picker and Space expands the directory',
    (tester) async {
      await prepareWorkspace(tester);
      await seedNestedOnlyAndOpen();
      await mountPage(tester);

      await tester.tap(_breadcrumbSegment('editor', 'nested'));
      await tester.pumpAndSettle();
      final rows = find.byWidgetPredicate((w) => w is PopupMenuItem<String>);
      final folder = find.descendant(of: rows, matching: find.text('nested/'));
      final child = find.descendant(of: rows, matching: find.text('main.rs'));
      expect(folder, findsOneWidget);
      expect(child, findsNothing);
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
      await tester.pumpAndSettle();
      expect(folder, findsOneWidget);
      expect(child, findsNothing);
      expect(find.byKey(const ValueKey('breadcrumb-editor-2')), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(child, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(rows, findsNothing);
      expect(_fieldForDocument(tester, 10).focusNode!.hasFocus, isTrue);
    },
  );

  testWidgets(
    'Ctrl+Enter ignores a breadcrumb file picker after its document changes',
    (tester) async {
      await prepareWorkspace(tester);
      await seedSiblingFilesAndOpen();
      await mountPage(tester);

      final source = _fieldForDocument(tester, 10);
      final document = source.inputWindow.document;
      final originalText = document.resync().content;
      final originalVersion = document.version;

      await tester.tap(_breadcrumbSegment('editor', 'z_source.rs'));
      await tester.pumpAndSettle();
      expect(find.text('a_target.rs'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();

      document.apply([TextOp.insert(originalText.codeUnits.length, '!')]);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(
        tester.widgetList<RustTextInputField>(find.byType(RustTextInputField)),
        hasLength(1),
        reason: 'a stale picker selection must not create a side group',
      );
      expect(document.resync().content, '$originalText!');
      expect(document.version, greaterThan(originalVersion));
      expect(
        _fieldForDocument(tester, 10).semanticsLabel,
        startsWith('z_source.rs'),
      );
    },
  );
}
