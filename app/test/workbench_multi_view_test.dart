import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'the same Rust document opens in two groups with independent view state',
    (tester) async {
      final temp = Directory.systemTemp.createTempSync('alula-multiview');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });

      final workspace = Directory('${temp.path}/workspace')..createSync();
      const sample = 'fn main() { println!("linux-save-ok"); }';
      final source = [
        sample,
        ...List.generate(
          99,
          (line) => 'fn item$line() { let value = $line; println!("$line"); }',
        ),
      ].join('\n');
      final file = File('${workspace.path}/main.rs')..writeAsStringSync(source);
      final base = temp.path.replaceAll(r'\', '/');

      await tester.pumpWidget(AlulaApp(
        autoFolder: workspace.path,
        layoutStore: LayoutStore(path: '$base/layout.json'),
        sessionStore: SessionStore(path: '$base/session.json'),
        keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
      ));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('main.rs').first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(RustTextInputField), findsOneWidget);

      await tester.tap(find.byTooltip('拆分编辑器').first);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byTooltip('拆分编辑器'), findsNWidgets(2));
      await tester.tap(find.text('main.rs').first);
      await tester.pump(const Duration(milliseconds: 300));

      final semantics = tester.ensureSemantics();
      final fieldsFinder = find.byType(RustTextInputField);
      expect(fieldsFinder, findsNWidgets(2));
      expect(find.bySemanticsLabel('main.rs 主编辑器'), findsOneWidget);
      expect(find.bySemanticsLabel('main.rs 编辑器 2'), findsOneWidget);
      semantics.dispose();
      var views = tester.widgetList<RustTextInputField>(fieldsFinder).toList();
      expect(
          views[0].inputWindow.document.id, views[1].inputWindow.document.id);
      expect(identical(views[0].inputWindow, views[1].inputWindow), isFalse);
      expect(identical(views[0].scrollController, views[1].scrollController),
          isFalse);

      Finder textFieldAt(int index) => find.descendant(
            of: fieldsFinder.at(index),
            matching: find.byType(TextField),
          );

      final firstController =
          tester.widget<TextField>(textFieldAt(0)).controller!;
      final secondController =
          tester.widget<TextField>(textFieldAt(1)).controller!;
      final secondScroll = views[1].scrollController!;
      expect(secondScroll.hasClients, isTrue);
      secondScroll.jumpTo(secondScroll.position.maxScrollExtent);
      await tester.pump();
      final secondScrollOffset = secondScroll.offset;
      expect(secondScrollOffset, greaterThan(0));
      expect(views[0].scrollController!.offset, closeTo(0, 1));

      firstController.selection = const TextSelection.collapsed(offset: 0);
      secondController.selection = const TextSelection.collapsed(offset: 20);
      await tester.pump();
      final firstValue = firstController.value;
      firstController.value = TextEditingValue(
        text: 'X${firstValue.text}',
        selection: const TextSelection.collapsed(offset: 1),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      views = tester.widgetList<RustTextInputField>(fieldsFinder).toList();
      expect(views.map((view) => view.inputWindow.document.version).toSet(),
          hasLength(1));
      expect(firstController.text, 'X$source');
      expect(secondController.text, 'X$source');
      final secondView = views.singleWhere(
        (view) => identical(view.scrollController, secondScroll),
      );
      expect(
        secondView.inputWindow.initialValue.selection.extentOffset,
        21,
        reason: 'an insertion before another view selection maps its caret',
      );
      expect(secondController.selection.extentOffset, 21);
      expect(views[1].scrollController!.offset, closeTo(secondScrollOffset, 1));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 100));
      expect(file.readAsStringSync(), 'X$source');

      final sharedDocumentId = views.first.inputWindow.document.id;
      await tester.tap(
        find.byKey(ValueKey('close-tab-editor-2-$sharedDocumentId')),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(fieldsFinder, findsOneWidget);
      var remainingView = tester.widget<RustTextInputField>(fieldsFinder);
      expect(remainingView.inputWindow.document.id, sharedDocumentId);
      expect(remainingView.inputWindow.document.resync().content, 'X$source');

      await tester.tap(
        find.byKey(ValueKey('close-tab-editor-$sharedDocumentId')),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('main.rs').first);
      await tester.pump(const Duration(milliseconds: 300));
      remainingView = tester.widget<RustTextInputField>(fieldsFinder);
      expect(remainingView.inputWindow.document.id, isNot(sharedDocumentId));
      expect(remainingView.inputWindow.document.resync().content, 'X$source');
    },
  );

  testWidgets(
      'conflicting duplicate journal entries survive as a recovery draft',
      (tester) async {
    final temp =
        Directory.systemTemp.createTempSync('alula-multiview-recovery');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    final workspace = Directory('${temp.path}/workspace')..createSync();
    final base = temp.path.replaceAll(r'\', '/');
    final layout = defaultLayout();
    expect(layout.splitLeaf('editor', 'editor-2', Axis.horizontal), isNotNull);
    final layoutStore = LayoutStore(path: '$base/layout.json')..save(layout);
    final sessionStore = SessionStore(path: '$base/session.json');
    sessionStore.save({
      'v': 1,
      'focused': 'editor-2',
      'workspace': workspace.path,
      'groups': [
        {
          'region': 'editor',
          'active': 7,
          'docs': [
            {'id': 7, 'text': 'first unsaved copy'},
          ],
        },
        {
          'region': 'editor-2',
          'active': 7,
          'docs': [
            {'id': 7, 'text': 'second unsaved copy'},
          ],
        },
      ],
    });

    await tester.pumpWidget(AlulaApp(
      autoFolder: workspace.path,
      layoutStore: layoutStore,
      sessionStore: sessionStore,
      keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
    ));
    await tester.pump(const Duration(milliseconds: 600));

    final fields = find.byType(RustTextInputField);
    expect(fields, findsNWidgets(2));
    final restoredTexts = <String>{};
    for (var index = 0; index < 2; index++) {
      final field = fields.at(index);
      final editor =
          find.descendant(of: field, matching: find.byType(TextField));
      restoredTexts.add(tester.widget<TextField>(editor).controller!.text);
    }
    expect(restoredTexts, {'first unsaved copy', 'second unsaved copy'});
    expect(find.textContaining('已将冲突内容保留为未命名恢复副本'), findsWidgets);
  });

  testWidgets('session restore shares one Rust document across editor groups',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-multiview-session');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    final workspace = Directory('${temp.path}/workspace')..createSync();
    const source = 'fn main() { println!("linux-save-ok"); }';
    final file = File('${workspace.path}/main.rs')..writeAsStringSync(source);
    final base = temp.path.replaceAll(r'\', '/');
    final layout = defaultLayout();
    layout.splitLeaf('editor', 'editor-2', Axis.horizontal);
    final layoutStore = LayoutStore(path: '$base/layout.json')..save(layout);
    final sessionStore = SessionStore(path: '$base/session.json');
    sessionStore.save({
      'v': 1,
      'focused': 'editor-2',
      'workspace': workspace.path,
      'groups': [
        for (final region in ['editor', 'editor-2'])
          {
            'region': region,
            'active': 9,
            'docs': [
              {'id': 9, 'path': file.path},
            ],
          },
      ],
    });

    await tester.pumpWidget(AlulaApp(
      layoutStore: layoutStore,
      sessionStore: sessionStore,
      keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
    ));
    await tester.pump(const Duration(milliseconds: 600));

    final fields = tester
        .widgetList<RustTextInputField>(
          find.byType(RustTextInputField),
        )
        .toList();
    expect(fields, hasLength(2));
    expect(fields[0].inputWindow.document.id, 9);
    expect(fields[1].inputWindow.document.id, 9);
    expect(identical(fields[0].inputWindow, fields[1].inputWindow), isFalse);
    expect(identical(fields[0].scrollController, fields[1].scrollController),
        isFalse);
    expect(identical(fields[0].focusNode, fields[1].focusNode), isFalse);
    expect(fields[0].inputWindow.document.resync().content, source);
  });

  testWidgets('the tail of a 50000-line document remains editable and saveable',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-large-tail-save');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    final workspace = Directory('${temp.path}/workspace')..createSync();
    const firstLine = 'fn main() { println!("linux-save-ok"); }';
    const tailMarker = 'TAIL_MARKER';
    final rows = List<String>.generate(
      49998,
      (line) => 'row-${line.toString().padLeft(5, '0')} ${'x' * 24}',
    );
    expect(rows, hasLength(49998));
    final source = [firstLine, ...rows, tailMarker].join('\n');
    final file = File('${workspace.path}/large.txt')..writeAsStringSync(source);
    final base = temp.path.replaceAll(r'\', '/');

    await tester.pumpWidget(AlulaApp(
      autoFolder: workspace.path,
      layoutStore: LayoutStore(path: '$base/layout.json'),
      sessionStore: SessionStore(path: '$base/session.json'),
      keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('large.txt').first);
    await tester.pump(const Duration(milliseconds: 300));

    final editorView = tester.widget<RustTextInputField>(
      find.byType(RustTextInputField),
    );
    expect(editorView.inputWindow.text.length, lessThan(source.length));
    expect(editorView.inputWindow.document.resync().content, source);

    await tester.tap(find.byTooltip('拆分编辑器').first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('large.txt').first);
    await tester.pump(const Duration(milliseconds: 300));
    var views = tester
        .widgetList<RustTextInputField>(find.byType(RustTextInputField))
        .toList();
    expect(views, hasLength(2));
    expect(
      views.map((view) => view.inputWindow.document.id).toSet(),
      hasLength(1),
    );
    expect(identical(views[0].scrollController, views[1].scrollController),
        isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 100));
    final findBar = find.byKey(const ValueKey('find-bar'));
    await tester.enterText(
      find.descendant(of: findBar, matching: find.byType(TextField)).first,
      tailMarker,
    );
    await tester.pump();
    await tester.tap(find.byTooltip('下一个匹配').first);
    await tester.pump();

    views = tester
        .widgetList<RustTextInputField>(find.byType(RustTextInputField))
        .toList();
    final tailView = views.singleWhere(
      (view) => view.inputWindow.startUtf16 > 100000,
    );
    expect(tailView.inputWindow.text, contains(tailMarker));

    final editor = find.descendant(
      of: find.byWidget(tailView),
      matching: find.byType(TextField),
    );
    await tester.showKeyboard(editor);
    await tester.pump();
    final controller = tester.widget<TextField>(editor).controller!;
    final markerStart = controller.text.lastIndexOf(tailMarker);
    expect(markerStart, greaterThanOrEqualTo(0));
    final editedWindow = controller.text.replaceRange(
      markerStart,
      markerStart + tailMarker.length,
      'SAVED_MARKER',
    );
    controller.value = TextEditingValue(
      text: editedWindow,
      selection: TextSelection.collapsed(
        offset: markerStart + 'SAVED_MARKER'.length,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 100));

    final expected = '${source.substring(0, source.length - tailMarker.length)}'
        'SAVED_MARKER';
    views = tester
        .widgetList<RustTextInputField>(find.byType(RustTextInputField))
        .toList();
    expect(views.map((view) => view.inputWindow.document.id).toSet(),
        hasLength(1));
    expect(
      views.every(
        (view) => view.inputWindow.document.resync().content == expected,
      ),
      isTrue,
      reason: 'both views observe the same Rust-authoritative saved text',
    );
    final tailViewAfterSave = views.singleWhere(
      (view) => view.inputWindow.startUtf16 > 100000,
    );
    expect(tailViewAfterSave.scrollController!.positions.length, 1);
    expect(file.readAsStringSync(), expected);
  });
}
