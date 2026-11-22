import 'dart:convert';
import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/recent_history_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
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

  testWidgets('Quick Open selects UTF-16 locations and bounded ranges',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-quick-open-range');
    final root = Directory('${temp.path}/workspace')..createSync();
    const original = 'head\r\n\t😀beta\r\nlast';
    final bytes = [0xef, 0xbb, 0xbf, ...utf8.encode(original)];
    final file = File('${root.path}/position.txt')..writeAsBytesSync(bytes);
    final longLine = '😀abc' * 5000;
    final largeFile = File('${root.path}/large.txt')
      ..writeAsStringSync('head\n$longLine\nlast');
    final messenger = tester.binding.defaultBinaryMessenger;
    String? copied;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() async {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => temp.delete(recursive: true));
    });

    late CommandService commands;
    await tester.pumpWidget(MaterialApp(
      home: WorkbenchPage(
        autoFolder: root.path,
        layoutStore: LayoutStore(path: '${temp.path}/layout.json'),
        sessionStore: SessionStore(path: '${temp.path}/session.json'),
        keybindingsStore: KeybindingsStore(path: '${temp.path}/keys.json'),
        onCommandServiceReady: (value) => commands = value,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 700));
    final panel = find.byKey(const ValueKey('quick-input'));
    final input = find.descendant(of: panel, matching: find.byType(TextField));
    final editor = find.byKey(const ValueKey('rust-bounded-text-input'));

    Future<TextSelection> openAt(String query, String name) async {
      await commands.execute('view.quickOpen');
      await tester.pump(const Duration(milliseconds: 120));
      await tester.enterText(input, query);
      final row = find.byKey(ValueKey('qi-$name'));
      for (var i = 0; i < 100 && row.evaluate().isEmpty; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(row, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      return tester.widget<TextField>(editor).controller!.selection;
    }

    expect(await openAt('${file.path}#2,2', 'position.txt'),
        const TextSelection.collapsed(offset: 6));
    expect(await openAt('position.txt (2,2-2,3)', 'position.txt'),
        const TextSelection(baseOffset: 6, extentOffset: 8));
    expect(await openAt('position.txt:3:3-2:4', 'position.txt'),
        const TextSelection(baseOffset: 8, extentOffset: 15));
    expect(await openAt('position.txt:99:1', 'position.txt'),
        const TextSelection.collapsed(offset: 17));
    expect(file.readAsBytesSync(), bytes);

    await openAt('large.txt:2-3:1', 'large.txt');
    final field =
        tester.widget<RustTextInputField>(find.byType(RustTextInputField));
    expect(field.inputWindow.text.length, lessThan(longLine.length));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(copied?.length, longLine.length + 1);
    expect(copied == '$longLine\n', isTrue);
    expect(largeFile.readAsStringSync(), 'head\n$longLine\nlast');
  });

  testWidgets('Quick Open keeps the active file while its location changes',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-quick-open-reuse');
    final root = Directory('${temp.path}/workspace')..createSync();
    final first = File('${root.path}/needle-first.txt')
      ..writeAsStringSync('head\nfirst');
    final second = File('${root.path}/needle-second.txt')
      ..writeAsStringSync('head\nsecond');
    final session = SessionStore(path: '${temp.path}/session.json');
    final history =
        RecentHistoryStore(path: '${session.resolvePath()}.recent-history');
    expect(history.recordFile(second.path), isTrue);
    expect(history.recordFile(first.path), isTrue);
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
    final row = find.byKey(const ValueKey('qi-needle-second.txt'));
    final loading = find.byKey(const ValueKey('quick-input-loading'));
    await tester.enterText(input, 'needle');
    for (var i = 0;
        i < 100 && (row.evaluate().isEmpty || loading.evaluate().isNotEmpty);
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(row, findsOneWidget);
    expect(loading, findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    final sideButton =
        find.byKey(const ValueKey('qi-button-needle-second.txt-0'));
    final focus = tester.widget<IconButton>(sideButton).focusNode;

    await tester.enterText(input, 'needle:');
    await tester.pump();
    expect(tester.widget<IconButton>(sideButton).focusNode, same(focus));
    expect(loading, findsNothing);
    await tester.enterText(input, 'needle:2:3');
    await tester.pump();
    expect(tester.widget<IconButton>(sideButton).focusNode, same(focus));
    expect(loading, findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    final editor = tester.widget<TextField>(
        find.byKey(const ValueKey('rust-bounded-text-input')));
    expect(editor.controller!.text, 'head\nsecond');
    expect(
        editor.controller!.selection, const TextSelection.collapsed(offset: 7));
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

  testWidgets('Quick Open marks unsaved files and removes their history safely',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-quick-open-dirty');
    final root = Directory('${temp.path}/workspace')..createSync();
    final dirty = File('${root.path}/dirty.txt')..writeAsStringSync('original');
    final clean = File('${root.path}/clean.txt')..writeAsStringSync('clean');
    final session = SessionStore(path: '${temp.path}/session.json');
    expect(
        session.save({
          'v': 1,
          'workspace': root.path,
          'focused': 'editor',
          'groups': [
            {
              'region': 'editor',
              'active': 2,
              'docs': [
                {'id': 2, 'path': dirty.path},
              ],
            },
          ],
        }),
        isTrue);
    final history =
        RecentHistoryStore(path: '${session.resolvePath()}.recent-history');
    expect(history.recordFile(dirty.path), isTrue);
    expect(history.recordFile(clean.path), isTrue);
    late CommandService commands;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => temp.delete(recursive: true));
    });
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

    final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
    await tester.showKeyboard(editor);
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: 'unsaved 😀',
      selection: TextSelection.collapsed(offset: 10),
    ));
    await tester.pump();
    await tester.pump();
    final document = tester
        .widget<RustTextInputField>(find.byType(RustTextInputField))
        .inputWindow
        .document;
    expect(document.isDirty, isTrue);

    await commands.execute('view.quickOpen');
    await tester.pump(const Duration(milliseconds: 120));
    final dirtyRow = find.byKey(const ValueKey('qi-dirty.txt'));
    final cleanRow = find.byKey(const ValueKey('qi-clean.txt'));
    final removeDirty = find.byKey(const ValueKey('qi-button-dirty.txt-1'));
    final removeClean = find.byKey(const ValueKey('qi-button-clean.txt-1'));
    for (var attempt = 0;
        attempt < 100 && dirtyRow.evaluate().isEmpty;
        attempt++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(tester.getTopLeft(cleanRow).dy,
        lessThan(tester.getTopLeft(dirtyRow).dy));
    IconData? glyph(Finder button) =>
        (tester.widget<IconButton>(button).icon as Icon).icon;
    expect(glyph(removeClean), Icons.close);
    expect(glyph(removeDirty), Icons.fiber_manual_record);
    expect(find.byKey(const ValueKey('qi-button-dirty.txt-0')), findsNothing);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('dirty.txt，有未保存的更改')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('clean.txt，有未保存的更改')), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(dirtyRow));
    addTearDown(mouse.removePointer);
    await tester.pump();
    expect(glyph(removeDirty), Icons.close);
    await mouse.moveTo(tester.getCenter(cleanRow));
    await tester.pump();
    expect(glyph(removeDirty), Icons.fiber_manual_record);

    await tester.tap(removeDirty);
    for (var attempt = 0;
        attempt < 100 && dirtyRow.evaluate().isNotEmpty;
        attempt++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(dirtyRow, findsNothing);
    expect(find.byKey(const ValueKey('quick-input')), findsOneWidget);
    expect(document.isDirty, isTrue);
    expect(document.resync().content, 'unsaved 😀');
    expect(dirty.readAsStringSync(), 'original');
    expect(history.load().files.map((entry) => entry.label),
        contains('dirty.txt'));
  });

  testWidgets('Quick Open keeps plain accepts and side-opens modified accepts',
      (tester) async {
    final temp =
        Directory.systemTemp.createTempSync('alula-quick-open-modifiers');
    final root = Directory('${temp.path}/workspace')..createSync();
    final source = File('${root.path}/source.txt')
      ..writeAsStringSync('main\neditor');
    final target = File('${root.path}/target.txt')
      ..writeAsStringSync('alpha\r\n😀beta\r\nlast');
    final session = SessionStore(path: '${temp.path}/session.json');
    expect(
        session.save({
          'v': 1,
          'workspace': root.path,
          'focused': 'editor',
          'groups': [
            {
              'region': 'editor',
              'active': 2,
              'preview': 2,
              'docs': [
                {'id': 2, 'path': source.path},
              ],
            },
          ],
        }),
        isTrue);
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => temp.delete(recursive: true));
    });

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
    final sourceTab = find.byKey(const ValueKey('editor-tab-label-editor-2'));
    final panel = find.byKey(const ValueKey('quick-input'));
    final filter = find.descendant(of: panel, matching: find.byType(TextField));
    RustTextInputField editor(String region) =>
        tester.widget<RustTextInputField>(find.descendant(
          of: find.byKey(ValueKey('editor-body-drop-$region')),
          matching: find.byType(RustTextInputField),
        ));

    Future<void> pick(File file, String position,
        {LogicalKeyboardKey? modifier, bool click = false}) async {
      await commands.execute('view.quickOpen');
      await tester.pump(const Duration(milliseconds: 120));
      await tester.enterText(filter, '${file.path}$position');
      final row = find.byKey(ValueKey('qi-${file.uri.pathSegments.last}'));
      for (var i = 0; i < 100 && row.evaluate().isEmpty; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(row, findsOneWidget);
      if (modifier != null) await tester.sendKeyDownEvent(modifier);
      if (click) {
        await tester.tap(row, kind: PointerDeviceKind.mouse);
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      }
      if (modifier != null) await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
    }

    expect(tester.widget<Text>(sourceTab).style?.fontStyle, FontStyle.italic);
    await pick(source, ':1:2');
    expect(tester.widget<Text>(sourceTab).style?.fontStyle,
        isNot(FontStyle.italic));
    expect(
        find.byKey(const ValueKey('editor-body-drop-editor-2')), findsNothing);
    expect(editor('editor').inputWindow.initialValue.selection.extentOffset, 1);

    await pick(target, ':2:3', modifier: LogicalKeyboardKey.controlLeft);
    final right = editor('editor-2');
    expect(right.inputWindow.text, 'alpha\n😀beta\nlast');
    expect(right.inputWindow.initialValue.selection.extentOffset, 8);
    expect(right.focusNode!.hasPrimaryFocus, isTrue);
    expect(editor('editor').inputWindow.initialValue.selection.extentOffset, 1);

    await tester.tap(sourceTab);
    await tester.pumpAndSettle();
    await pick(target, ':3:2', modifier: LogicalKeyboardKey.metaLeft);
    final reused = editor('editor-2');
    expect(
        find.byKey(const ValueKey('editor-body-drop-editor-3')), findsNothing);
    expect(reused.inputWindow.document.id, right.inputWindow.document.id);
    expect(reused.inputWindow.initialValue.selection.extentOffset, 14);
    expect(reused.focusNode!.hasPrimaryFocus, isTrue);
    await tester.tap(sourceTab);
    await tester.pumpAndSettle();
    await pick(source, ':1:3', click: true);
    expect(editor('editor').focusNode!.hasPrimaryFocus, isTrue);
    expect(editor('editor').inputWindow.initialValue.selection.extentOffset, 2);

    for (final modifier in [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.altLeft,
    ]) {
      await tester.tap(sourceTab);
      await tester.pumpAndSettle();
      await pick(target, ':2:4', modifier: modifier, click: true);
      final clicked = editor('editor-2');
      expect(clicked.inputWindow.document.id, right.inputWindow.document.id);
      expect(clicked.inputWindow.initialValue.selection.extentOffset, 9);
      expect(clicked.focusNode!.hasPrimaryFocus, isTrue);
      expect(find.byKey(const ValueKey('editor-body-drop-editor-3')),
          findsNothing);
    }

    expect(source.readAsStringSync(), 'main\neditor');
    expect(target.readAsStringSync(), 'alpha\r\n😀beta\r\nlast');
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
