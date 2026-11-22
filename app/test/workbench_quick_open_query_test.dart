import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/recent_history_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/native_drag_drop.dart';

void main() {
  setUpAll(mockNativeDragDrop);

  testWidgets('Quick Open disables repeated page actions during loading',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-quick-open-pages');
    for (var i = 0; i < 220; i++) {
      File('${temp.path}/file-$i.txt').writeAsStringSync('');
    }
    CommandService? commands;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => temp.delete(recursive: true));
    });
    await tester.pumpWidget(MaterialApp(
        home: WorkbenchPage(
      autoFolder: temp.path,
      layoutStore: LayoutStore(path: '${temp.path}/layout.json'),
      sessionStore: SessionStore(path: '${temp.path}/session.json'),
      keybindingsStore: KeybindingsStore(path: '${temp.path}/keys.json'),
      onCommandServiceReady: (value) => commands = value,
    )));
    await tester.pump(const Duration(milliseconds: 600));
    await commands!.execute('view.quickOpen');
    await tester.pump(const Duration(milliseconds: 120));
    final input = find.descendant(
        of: find.byKey(const ValueKey('quick-input')),
        matching: find.byType(TextField));
    await tester.enterText(input, 'file-');
    final next = find.byKey(const ValueKey('quick-open-next-page'));
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
      if (next.evaluate().isNotEmpty &&
          tester.widget<IconButton>(next).onPressed != null) {
        break;
      }
    }
    expect(next, findsOneWidget);
    await tester.tap(next);
    await tester.pump();
    expect(tester.widget<IconButton>(next).onPressed, isNull);
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
      if (find
          .byKey(const ValueKey('quick-input-loading'))
          .evaluate()
          .isEmpty) {
        break;
      }
    }
    expect(next, findsNothing);
    expect(
        find.byKey(const ValueKey('quick-open-previous-page')), findsOneWidget);
    expect(find.text('无匹配项'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

  testWidgets(
      'Quick Open resolves absolute path and line suffix without a workspace',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-quick-open-query');
    final file = File('${temp.path}/position.txt')
      ..writeAsStringSync('alpha\r\n😀beta\r\nlast');
    CommandService? commands;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => temp.delete(recursive: true));
    });
    await tester.pumpWidget(MaterialApp(
        home: WorkbenchPage(
      layoutStore: LayoutStore(path: '${temp.path}/layout.json'),
      sessionStore: SessionStore(path: '${temp.path}/session.json'),
      keybindingsStore: KeybindingsStore(path: '${temp.path}/keys.json'),
      onCommandServiceReady: (value) => commands = value,
    )));
    await tester.pump(const Duration(milliseconds: 600));
    await commands!.execute('view.quickOpen');
    await tester.pump(const Duration(milliseconds: 120));
    final input = find.descendant(
        of: find.byKey(const ValueKey('quick-input')),
        matching: find.byType(TextField));
    await tester.enterText(input, '${file.path}:2:3');
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
      if (find.byKey(const ValueKey('qi-position.txt')).evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.byKey(const ValueKey('qi-position.txt')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
      final fields = find.byKey(const ValueKey('rust-bounded-text-input'));
      if (fields.evaluate().isNotEmpty &&
          tester.widget<TextField>(fields).controller!.selection.extentOffset ==
              8) {
        break;
      }
    }
    final controller = tester
        .widget<TextField>(
            find.byKey(const ValueKey('rust-bounded-text-input')))
        .controller!;
    expect(controller.text, 'alpha\n😀beta\nlast');
    expect(controller.selection.extentOffset, 8);
    expect(file.readAsStringSync(), 'alpha\r\n😀beta\r\nlast');
  });

  testWidgets('Quick Open separates recent files from workspace results',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-quick-open-groups');
    final root = Directory('${temp.path}/workspace')..createSync();
    final recent = File('${root.path}/needle-recent.txt')
      ..writeAsStringSync('recent document');
    File('${root.path}/needle-unopened.txt').writeAsStringSync('workspace hit');
    final session = SessionStore(path: '${temp.path}/session.json');
    final history =
        RecentHistoryStore(path: '${session.resolvePath()}.recent-history');
    expect(history.recordFile(recent.path), isTrue);
    expect(history.recordFile('${root.path}/stale.txt'), isTrue);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => temp.delete(recursive: true));
    });
    late CommandService commands;
    await tester.pumpWidget(MaterialApp(
      home: WorkbenchPage(
        autoFolder: root.path,
        layoutStore: LayoutStore(path: '${temp.path}/layout.json'),
        sessionStore: session,
        keybindingsStore: KeybindingsStore(path: '${temp.path}/keys.json'),
        onCommandServiceReady: (value) => commands = value,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 700));
    await commands.execute('view.quickOpen');
    await tester.pump(const Duration(milliseconds: 120));

    final panel = find.byKey(const ValueKey('quick-input'));
    final input = find.descendant(of: panel, matching: find.byType(TextField));
    final recentHeader =
        find.descendant(of: panel, matching: find.text('最近打开'));
    final fileHeader = find.descendant(of: panel, matching: find.text('文件结果'));
    final recentRow = find.byKey(const ValueKey('qi-needle-recent.txt'));
    final unopenedRow = find.byKey(const ValueKey('qi-needle-unopened.txt'));

    Future<void> waitFor(Finder item, {Finder? gone}) async {
      bool pending() =>
          item.evaluate().isEmpty || (gone?.evaluate().isNotEmpty ?? false);
      for (var attempt = 0; attempt < 100 && pending(); attempt++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(item, findsOneWidget);
    }

    await waitFor(recentRow);
    expect(recentHeader, findsOneWidget);
    expect(fileHeader, findsNothing);
    expect(unopenedRow, findsNothing);
    expect(find.byKey(const ValueKey('qi-stale.txt')), findsNothing);

    await tester.enterText(input, 'needle');
    await waitFor(unopenedRow);
    expect(recentRow, findsOneWidget);
    expect(tester.getTopLeft(recentHeader).dy,
        lessThan(tester.getTopLeft(recentRow).dy));
    expect(tester.getTopLeft(recentRow).dy,
        lessThan(tester.getTopLeft(fileHeader).dy));
    expect(tester.getTopLeft(fileHeader).dy,
        lessThan(tester.getTopLeft(unopenedRow).dy));

    await tester.enterText(input, '');
    await waitFor(recentRow, gone: unopenedRow);
    expect(fileHeader, findsNothing);
    expect(unopenedRow, findsNothing);

    await tester.enterText(input, 'needle');
    await waitFor(unopenedRow);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    final editors =
        tester.widgetList<RustTextInputField>(find.byType(RustTextInputField));
    expect(editors.any((editor) => editor.inputWindow.text == 'workspace hit'),
        isTrue);
  });

  testWidgets(
      'Quick Open removes the recent hit in place and keeps Open Recent',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-quick-open-remove');
    final root = Directory('${temp.path}/workspace')..createSync();
    final recent = File('${root.path}/needle-recent.txt')
      ..writeAsStringSync('recent document');
    File('${root.path}/needle-unopened.txt').writeAsStringSync('workspace hit');
    final session = SessionStore(path: '${temp.path}/session.json');
    final history =
        RecentHistoryStore(path: '${session.resolvePath()}.recent-history');
    expect(history.recordFile(recent.path), isTrue);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => temp.delete(recursive: true));
    });
    late CommandService commands;
    await tester.pumpWidget(MaterialApp(
      home: WorkbenchPage(
        autoFolder: root.path,
        layoutStore: LayoutStore(path: '${temp.path}/layout.json'),
        sessionStore: session,
        keybindingsStore: KeybindingsStore(path: '${temp.path}/keys.json'),
        onCommandServiceReady: (value) => commands = value,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 700));
    await commands.execute('view.quickOpen');
    await tester.pump(const Duration(milliseconds: 120));

    final panel = find.byKey(const ValueKey('quick-input'));
    final input = find.descendant(of: panel, matching: find.byType(TextField));
    final recentRow = find.byKey(const ValueKey('qi-needle-recent.txt'));
    final unopenedRow = find.byKey(const ValueKey('qi-needle-unopened.txt'));
    final remove = find.byTooltip('从最近打开中移除');

    Future<void> waitFor(Finder item, {Finder? gone}) async {
      for (var attempt = 0; attempt < 100; attempt++) {
        if (item.evaluate().isNotEmpty &&
            (gone == null || gone.evaluate().isEmpty)) {
          break;
        }
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(item, findsOneWidget);
      if (gone != null) expect(gone, findsNothing);
    }

    await tester.enterText(input, 'needle');
    await waitFor(unopenedRow);
    expect(find.descendant(of: recentRow, matching: remove), findsOneWidget);
    expect(find.descendant(of: unopenedRow, matching: remove), findsNothing);
    await tester.tap(remove);
    await waitFor(unopenedRow, gone: recentRow);
    final field = tester.widget<TextField>(input);
    expect(field.controller!.text, 'needle');
    expect(field.focusNode!.hasFocus, isTrue);
    expect(history.load().quickOpenFiles, isEmpty);
    expect(history.load().files.single.label, 'needle-recent.txt');
    expect(recent.readAsStringSync(), 'recent document');

    await tester.enterText(input, 'needle-recent.txt');
    await waitFor(recentRow);
    expect(find.text('最近打开'), findsNothing);
    expect(remove, findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.tap(find.text('文件(F)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开最近'));
    await tester.pumpAndSettle();
    final openRecent = find.textContaining('needle-recent.txt — ');
    expect(openRecent, findsOneWidget);
    await tester.tap(openRecent);
    await tester.pumpAndSettle();
    expect(history.load().quickOpenFiles.single.label, 'needle-recent.txt');
    expect(panel, findsNothing);
  });

  testWidgets('Quick Open opens to the right by Alt+Enter and row button',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-quick-open-side');
    final workspace = Directory('${temp.path}/workspace')..createSync();
    final source = File('${workspace.path}/source.txt')
      ..writeAsStringSync('original\nsource');
    final result = File('${workspace.path}/position.txt')
      ..writeAsStringSync('alpha\r\n😀beta\r\nlast');
    final lockedResult = File('${workspace.path}/isolated.txt')
      ..writeAsStringSync('third file');
    final session = SessionStore(path: '${temp.path}/session.json');
    expect(
        session.save({
          'v': 1,
          'workspace': workspace.path,
          'focused': 'editor',
          'groups': [
            {
              'region': 'editor',
              'active': 2,
              'docs': [
                {'id': 2, 'path': source.path},
              ],
            },
          ],
        }),
        isTrue);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => temp.delete(recursive: true));
    });
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late CommandService commands;
    await tester.pumpWidget(MaterialApp(
      home: WorkbenchPage(
        layoutStore: LayoutStore(path: '${temp.path}/layout.json'),
        sessionStore: session,
        keybindingsStore: KeybindingsStore(path: '${temp.path}/keys.json'),
        onCommandServiceReady: (value) => commands = value,
      ),
    ));
    await tester.pumpAndSettle();

    Finder editor(String region) => find.descendant(
          of: find.byKey(ValueKey('editor-body-drop-$region')),
          matching: find.byType(RustTextInputField),
        );
    RustTextInputField field(String region) =>
        tester.widget<RustTextInputField>(editor(region));
    final panel = find.byKey(const ValueKey('quick-input'));
    final filter = find.descendant(of: panel, matching: find.byType(TextField));
    Future<void> pick(File file,
        {String position = '', bool keyboard = false}) async {
      await commands.execute('view.quickOpen');
      await tester.pump(const Duration(milliseconds: 120));
      await tester.enterText(filter, '${file.path}$position');
      final row = find.byKey(ValueKey('qi-${file.uri.pathSegments.last}'));
      for (var attempt = 0;
          attempt < 100 && row.evaluate().isEmpty;
          attempt++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(row, findsOneWidget);
      if (keyboard) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      } else {
        await tester.tap(find.byTooltip('在侧边打开'));
      }
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
    }

    final input = find.descendant(
      of: editor('editor'),
      matching: find.byType(EditableText),
    );
    await tester.enterText(input, 'original\nsource!');
    await tester.pumpAndSettle();
    final left = field('editor');
    final selection = left.inputWindow.initialValue.selection;

    await pick(result, position: ':2:3', keyboard: true);
    final right = field('editor-2');
    expect(right.inputWindow.text, 'alpha\n😀beta\nlast');
    expect(right.inputWindow.initialValue.selection.extentOffset, 8);
    expect(right.focusNode!.hasPrimaryFocus, isTrue);
    expect(field('editor').inputWindow.initialValue.selection, selection);

    await tester.tap(find.byKey(const ValueKey('editor-tab-label-editor-2')));
    await tester.pumpAndSettle();
    await pick(source, position: ':1:2');
    final shared = field('editor-2');
    expect(shared.inputWindow.document.id, left.inputWindow.document.id);
    expect(shared.inputWindow.text, 'original\nsource!');
    expect(shared.inputWindow.initialValue.selection.extentOffset, 1);
    expect(field('editor').inputWindow.initialValue.selection, selection);
    expect(shared.focusNode!.hasPrimaryFocus, isTrue);

    await commands.execute('workbench.action.lockEditorGroup');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('editor-tab-label-editor-2')));
    await tester.pumpAndSettle();
    await pick(lockedResult, keyboard: true);
    expect(field('editor-3').inputWindow.text, 'third file');
    expect(field('editor-3').focusNode!.hasPrimaryFocus, isTrue);
    expect(field('editor-2').inputWindow.document.id,
        left.inputWindow.document.id);
    expect(source.readAsStringSync(), 'original\nsource');
    expect(result.readAsStringSync(), 'alpha\r\n😀beta\r\nlast');
  });
}
