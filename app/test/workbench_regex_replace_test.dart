import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pressChord(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _pressAltEnter(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  await tester.pump();
}

Future<void> _pressShiftEnter(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
}

Future<void> _waitForIsolates(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 80)),
  );
  await tester.pump();
}

String _documentText(WidgetTester tester) => tester
    .state<RustTextInputFieldState>(find.byType(RustTextInputField))
    .widget
    .inputWindow
    .document
    .resync()
    .content;

Future<File> _launchFindWorkspace(
  WidgetTester tester,
  Directory temp, {
  required String text,
}) async {
  final workspace = Directory('${temp.path}/workspace')..createSync();
  final file = File('${workspace.path}/notes.txt')..writeAsStringSync(text);
  final base = temp.path.replaceAll(r'\', '/');
  await tester.pumpWidget(AlulaApp(
    autoFolder: workspace.path,
    layoutStore: LayoutStore(path: '$base/layout.json'),
    sessionStore: SessionStore(path: '$base/session.json'),
    keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
  ));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.tap(find.text('notes.txt').first);
  await tester.pump(const Duration(milliseconds: 300));
  return file;
}

void main() {
  testWidgets('Shift+Enter finds previous; Enter still finds next',
      (tester) async {
    final temp =
        Directory.systemTemp.createTempSync('alula-find-previous-match-');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    const source = 'foo foo foo';
    await _launchFindWorkspace(tester, temp, text: source);
    final editorFinder = find.byType(RustTextInputField);
    final editorState = tester.state<RustTextInputFieldState>(editorFinder);
    editorState.setSelection(const TextSelection.collapsed(offset: 0));
    await tester.pump();
    final documentVersion = editorState.widget.inputWindow.document.version;

    await _pressChord(tester, LogicalKeyboardKey.keyH);
    final findInput = find.byKey(const ValueKey('find-query-input'));
    final replaceInput = find.byKey(const ValueKey('replace-query-input'));
    await tester.enterText(findInput, 'foo');
    await tester.pump();
    await tester.tap(findInput);
    await _pressShiftEnter(tester);
    await tester.pumpAndSettle();

    expect(
      editorState.editingValue.selection,
      const TextSelection(baseOffset: 8, extentOffset: 11),
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      editorState.editingValue.selection,
      const TextSelection(baseOffset: 0, extentOffset: 3),
    );

    await tester.tap(replaceInput);
    await _pressShiftEnter(tester);
    await tester.pumpAndSettle();
    expect(
      editorState.editingValue.selection,
      const TextSelection(baseOffset: 0, extentOffset: 3),
      reason: 'Shift+Enter in the Replace field must not navigate Find',
    );
    expect(_documentText(tester), source);
    expect(
      tester
          .widget<RustTextInputField>(editorFinder)
          .inputWindow
          .document
          .version,
      documentVersion,
    );
  });

  testWidgets('Ctrl+F seeds Find from a single-line UTF-16 selection',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-find-seed-emoji-');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    const source = '🍁foo | 🍁foo';
    final file = await _launchFindWorkspace(tester, temp, text: source);
    final editorFinder = find.byType(RustTextInputField);
    final editorState = tester.state<RustTextInputFieldState>(editorFinder);
    const selection = TextSelection(baseOffset: 0, extentOffset: 5);
    editorState.setSelection(selection);
    await tester.pump();
    final document = editorState.widget.inputWindow.document;
    final version = document.version;
    final bytes = file.readAsBytesSync();

    editorState.requestFocus();
    await _pressChord(tester, LogicalKeyboardKey.keyF);
    final queryField = tester.widget<TextField>(
      find.byKey(const ValueKey('find-query-input')),
    );
    expect(queryField.controller!.text, '🍁foo');
    expect(find.text('-/2'), findsOneWidget);
    expect(editorState.editingValue.selection, selection);
    expect(document.resync().content, source);
    expect(document.version, version);
    expect(document.isDirty, isFalse);
    expect(file.readAsBytesSync(), bytes);

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    editorState.requestFocus();
    await _pressChord(tester, LogicalKeyboardKey.keyZ);
    expect(document.resync().content, source);
    expect(document.version, version);
    expect(document.isDirty, isFalse);
    expect(file.readAsBytesSync(), bytes);
  });

  testWidgets(
      'regex Find seed escapes metacharacters and multiline keeps query',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-find-seed-regex-');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    const selected = 'a+b?*';
    const source = 'a+b?* aXbZZ\nsecond';
    final file = await _launchFindWorkspace(tester, temp, text: source);
    final editorFinder = find.byType(RustTextInputField);
    final editorState = tester.state<RustTextInputFieldState>(editorFinder);
    final document = editorState.widget.inputWindow.document;
    final version = document.version;
    final bytes = file.readAsBytesSync();

    editorState.requestFocus();
    await _pressChord(tester, LogicalKeyboardKey.keyF);
    await tester.tap(find.byKey(const ValueKey('find-regex')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    const singleLineSelection =
        TextSelection(baseOffset: 0, extentOffset: selected.length);
    editorState.setSelection(singleLineSelection);
    editorState.requestFocus();
    await tester.pump();
    await _pressChord(tester, LogicalKeyboardKey.keyF);
    await _waitForIsolates(tester);
    await tester.pumpAndSettle();
    final queryField = tester.widget<TextField>(
      find.byKey(const ValueKey('find-query-input')),
    );
    final escaped = RegExp.escape(selected);
    expect(queryField.controller!.text, escaped);
    expect(find.text('-/1'), findsOneWidget);
    expect(editorState.editingValue.selection, singleLineSelection);

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    final multilineSelection = TextSelection(
      baseOffset: 0,
      extentOffset: source.indexOf('\n') + 1,
    );
    editorState.setSelection(multilineSelection);
    editorState.requestFocus();
    await tester.pump();
    await _pressChord(tester, LogicalKeyboardKey.keyF);

    final reopenedQuery = tester.widget<TextField>(
      find.byKey(const ValueKey('find-query-input')),
    );
    expect(reopenedQuery.controller!.text, escaped);
    expect(editorState.editingValue.selection, multilineSelection);
    expect(document.resync().content, source);
    expect(document.version, version);
    expect(document.isDirty, isFalse);
    expect(file.readAsBytesSync(), bytes);
  });

  testWidgets('Ctrl+F seeds the default word at an empty UTF-16 caret',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-find-word-seed-');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    const source = '🍁alpha foo.bar -12.5e3';
    final file = await _launchFindWorkspace(tester, temp, text: source);
    final editorFinder = find.byType(RustTextInputField);
    final editorState = tester.state<RustTextInputFieldState>(editorFinder);
    final document = editorState.widget.inputWindow.document;
    const caret = 5;
    const selection = TextSelection.collapsed(offset: caret);
    editorState.setSelection(selection);
    await tester.pump();
    final version = document.version;
    final bytes = file.readAsBytesSync();

    editorState.requestFocus();
    await _pressChord(tester, LogicalKeyboardKey.keyF);
    final queryField = tester.widget<TextField>(
      find.byKey(const ValueKey('find-query-input')),
    );
    expect(queryField.controller!.text, '🍁alpha');
    expect(find.text('-/1'), findsOneWidget);
    expect(editorState.editingValue.selection, selection);
    expect(document.resync().content, source);
    expect(document.version, version);
    expect(document.isDirty, isFalse);
    expect(file.readAsBytesSync(), bytes);

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    editorState.requestFocus();
    await _pressChord(tester, LogicalKeyboardKey.keyZ);
    expect(document.resync().content, source);
    expect(document.version, version);
    expect(document.isDirty, isFalse);
    expect(file.readAsBytesSync(), bytes);
  });

  testWidgets(
      'regex Find seeds the current word and keeps prior query on a separator',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-find-word-regex-');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    const source = 'alpha beta +';
    await _launchFindWorkspace(tester, temp, text: source);
    final editorFinder = find.byType(RustTextInputField);
    final editorState = tester.state<RustTextInputFieldState>(editorFinder);
    editorState.setSelection(const TextSelection.collapsed(offset: 8));
    editorState.requestFocus();
    await _pressChord(tester, LogicalKeyboardKey.keyF);
    await tester.tap(find.byKey(const ValueKey('find-regex')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    editorState.setSelection(const TextSelection.collapsed(offset: 8));
    editorState.requestFocus();
    await tester.pump();
    await _pressChord(tester, LogicalKeyboardKey.keyF);
    await _waitForIsolates(tester);
    await tester.pumpAndSettle();
    final queryFinder = find.byKey(const ValueKey('find-query-input'));
    final queryField = tester.widget<TextField>(queryFinder);
    expect(queryField.controller!.text, 'beta');
    expect(find.text('-/1'), findsOneWidget);

    await tester.enterText(queryFinder, 'remember');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    editorState.setSelection(const TextSelection.collapsed(offset: 11));
    editorState.requestFocus();
    await tester.pump();
    await _pressChord(tester, LogicalKeyboardKey.keyF);
    final reopenedQuery = tester.widget<TextField>(
      find.byKey(const ValueKey('find-query-input')),
    );
    expect(reopenedQuery.controller!.text, 'remember');
  });

  testWidgets('Ctrl+F bounds long-line word lookup to Code-OSS window',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-find-word-window-');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final source = List<String>.filled(1600, 'x').join();
    await _launchFindWorkspace(tester, temp, text: source);
    final editorFinder = find.byType(RustTextInputField);
    final editorState = tester.state<RustTextInputFieldState>(editorFinder);
    editorState.setSelection(const TextSelection.collapsed(offset: 800));
    editorState.requestFocus();
    await tester.pump();
    await _pressChord(tester, LogicalKeyboardKey.keyF);

    final query = tester
        .widget<TextField>(
          find.byKey(const ValueKey('find-query-input')),
        )
        .controller!
        .text;
    expect(query, source.substring(301, 1301));
    expect(query.length, 1000);
  });

  testWidgets(
      'Alt+Enter selects literal hits and keeps the current hit primary',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-find-select-all-');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    const source = 'foo foo FOO';
    await _launchFindWorkspace(tester, temp, text: source);
    final editorFinder = find.byType(RustTextInputField);
    final editorState = tester.state<RustTextInputFieldState>(editorFinder);
    editorState
        .setSelection(const TextSelection(baseOffset: 8, extentOffset: 11));
    await tester.pump();

    await _pressChord(tester, LogicalKeyboardKey.keyF);
    final findInput = find.byKey(const ValueKey('find-query-input'));
    await tester.enterText(findInput, 'foo');
    await tester.pump();
    await _pressAltEnter(tester);
    await tester.pumpAndSettle();

    final editor = tester.widget<RustTextInputField>(editorFinder);
    expect(editorState.editingValue.selection,
        const TextSelection(baseOffset: 8, extentOffset: 11));
    expect(editor.additionalSelections, const [
      TextSelection(baseOffset: 0, extentOffset: 3),
      TextSelection(baseOffset: 4, extentOffset: 7),
    ]);
    expect(_documentText(tester), source);
  });

  testWidgets('Alt+Enter honors regex and find-in-selection scope',
      (tester) async {
    final temp =
        Directory.systemTemp.createTempSync('alula-find-select-scoped-regex-');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    const source = 'foo FOO foo';
    await _launchFindWorkspace(tester, temp, text: source);
    final editorFinder = find.byType(RustTextInputField);
    final editorState = tester.state<RustTextInputFieldState>(editorFinder);
    editorState
        .setSelection(const TextSelection(baseOffset: 0, extentOffset: 7));
    await tester.pump();

    await _pressChord(tester, LogicalKeyboardKey.keyF);
    final findInput = find.byKey(const ValueKey('find-query-input'));
    await tester.enterText(findInput, 'f.o');
    await tester.tap(find.byKey(const ValueKey('find-regex')));
    await _waitForIsolates(tester);
    await tester.tap(find.byKey(const ValueKey('find-in-selection')));
    await _waitForIsolates(tester);
    await tester.tap(findInput);
    await _pressAltEnter(tester);
    await _waitForIsolates(tester);
    await tester.pumpAndSettle();

    final editor = tester.widget<RustTextInputField>(editorFinder);
    expect(editorState.editingValue.selection,
        const TextSelection(baseOffset: 0, extentOffset: 3));
    expect(editor.additionalSelections,
        const [TextSelection(baseOffset: 4, extentOffset: 7)]);
    expect(_documentText(tester), source);
  });

  testWidgets('Alt+Enter on invalid regex preserves existing selections',
      (tester) async {
    final temp =
        Directory.systemTemp.createTempSync('alula-find-select-error-');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    const source = 'foo foo';
    await _launchFindWorkspace(tester, temp, text: source);
    final editorFinder = find.byType(RustTextInputField);
    final editorState = tester.state<RustTextInputFieldState>(editorFinder);
    final before = editorState.editingValue.selection;

    await _pressChord(tester, LogicalKeyboardKey.keyF);
    final findInput = find.byKey(const ValueKey('find-query-input'));
    await tester.enterText(findInput, '(');
    await tester.tap(find.byKey(const ValueKey('find-regex')));
    await _waitForIsolates(tester);
    await tester.tap(findInput);
    await _pressAltEnter(tester);
    await _waitForIsolates(tester);
    await tester.pumpAndSettle();

    final editor = tester.widget<RustTextInputField>(editorFinder);
    expect(editorState.editingValue.selection, before);
    expect(editor.additionalSelections, isEmpty);
    expect(_documentText(tester), source);
  });

  testWidgets('Alt+Enter discards a regex result after the query goes stale',
      (tester) async {
    final temp =
        Directory.systemTemp.createTempSync('alula-find-select-stale-');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    const source = 'foo bar foo';
    await _launchFindWorkspace(tester, temp, text: source);
    final editorFinder = find.byType(RustTextInputField);
    final editorState = tester.state<RustTextInputFieldState>(editorFinder);
    const originalSelection = TextSelection(baseOffset: 4, extentOffset: 7);
    editorState.setSelection(originalSelection);
    await tester.pump();

    await _pressChord(tester, LogicalKeyboardKey.keyF);
    final findInput = find.byKey(const ValueKey('find-query-input'));
    await tester.enterText(findInput, 'foo');
    await tester.tap(find.byKey(const ValueKey('find-regex')));
    await tester.tap(findInput);
    await _pressAltEnter(tester);
    await tester.enterText(findInput, 'bar');
    await _waitForIsolates(tester);
    await tester.pumpAndSettle();

    final editor = tester.widget<RustTextInputField>(editorFinder);
    expect(editorState.editingValue.selection, originalSelection);
    expect(editor.additionalSelections, isEmpty);
    expect(_documentText(tester), source);
  });

  testWidgets('preserve-case applies to a literal current replacement',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-literal-case-');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    final workspace = Directory('${temp.path}/workspace')..createSync();
    File('${workspace.path}/notes.txt').writeAsStringSync('Foo foo');
    final base = temp.path.replaceAll(r'\', '/');
    await tester.pumpWidget(AlulaApp(
      autoFolder: workspace.path,
      layoutStore: LayoutStore(path: '$base/layout.json'),
      sessionStore: SessionStore(path: '$base/session.json'),
      keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('notes.txt').first);
    await tester.pump(const Duration(milliseconds: 300));

    await _pressChord(tester, LogicalKeyboardKey.keyH);
    await tester.enterText(
        find.byKey(const ValueKey('find-query-input')), 'foo');
    await tester.enterText(
      find.byKey(const ValueKey('replace-query-input')),
      'bar',
    );
    await tester.tap(find.byKey(const ValueKey('find-preserve-case')));
    await tester.tap(find.byTooltip('替换'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('替换'));
    await tester.pumpAndSettle();
    expect(_documentText(tester), 'Bar foo');
  });

  testWidgets(
    'preserve-case toggle applies to regex current/all replacement and undo',
    (tester) async {
      final temp = Directory.systemTemp.createTempSync('alula-regex-case-');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });

      final workspace = Directory('${temp.path}/workspace')..createSync();
      final file = File('${workspace.path}/notes.txt')
        ..writeAsStringSync('foo FOO Foo');
      final base = temp.path.replaceAll(r'\', '/');
      await tester.pumpWidget(AlulaApp(
        autoFolder: workspace.path,
        layoutStore: LayoutStore(path: '$base/layout.json'),
        sessionStore: SessionStore(path: '$base/session.json'),
        keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
      ));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('notes.txt').first);
      await tester.pump(const Duration(milliseconds: 300));

      await _pressChord(tester, LogicalKeyboardKey.keyH);
      await tester.enterText(
          find.byKey(const ValueKey('find-query-input')), 'foo');
      await tester.enterText(
        find.byKey(const ValueKey('replace-query-input')),
        'bar',
      );
      await tester.tap(find.byKey(const ValueKey('find-regex')));
      expect(
        tester
            .widget<IconButton>(
                find.byKey(const ValueKey('find-preserve-case')))
            .isSelected,
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('find-preserve-case')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(
                find.byKey(const ValueKey('find-preserve-case')))
            .isSelected,
        isTrue,
      );
      await _waitForIsolates(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('替换'));
      await _waitForIsolates(tester);
      await tester.pumpAndSettle();
      expect(_documentText(tester), 'foo FOO Foo',
          reason: 'the first click selects the next match');
      await tester.tap(find.byTooltip('替换'));
      await _waitForIsolates(tester);
      await tester.pumpAndSettle();
      expect(_documentText(tester), 'bar FOO Foo');

      await tester.tap(find.byType(RustTextInputField));
      await _pressChord(tester, LogicalKeyboardKey.keyZ);
      expect(_documentText(tester), 'foo FOO Foo');
      await _pressChord(tester, LogicalKeyboardKey.keyZ, shift: true);
      expect(_documentText(tester), 'bar FOO Foo');

      await tester.tap(find.byTooltip('全部替换'));
      await _waitForIsolates(tester);
      await tester.pumpAndSettle();
      expect(_documentText(tester), 'bar BAR Bar');
      await tester.tap(find.byType(RustTextInputField));
      await _pressChord(tester, LogicalKeyboardKey.keyS);
      expect(file.readAsStringSync(), 'bar BAR Bar');
      await _pressChord(tester, LogicalKeyboardKey.keyZ);
      expect(_documentText(tester), 'bar FOO Foo');
      await _pressChord(tester, LogicalKeyboardKey.keyZ, shift: true);
      expect(_documentText(tester), 'bar BAR Bar');
    },
  );

  testWidgets(
    'regex current and replace-all edits use one undo step and save back',
    (tester) async {
      final temp = Directory.systemTemp.createTempSync('alula-regex-replace-');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });

      final workspace = Directory('${temp.path}/workspace')..createSync();
      final file = File('${workspace.path}/notes.txt')
        ..writeAsStringSync('foo_1 foo_2');
      final base = temp.path.replaceAll(r'\', '/');
      await tester.pumpWidget(AlulaApp(
        autoFolder: workspace.path,
        layoutStore: LayoutStore(path: '$base/layout.json'),
        sessionStore: SessionStore(path: '$base/session.json'),
        keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
      ));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('notes.txt').first);
      await tester.pump(const Duration(milliseconds: 300));

      await _pressChord(tester, LogicalKeyboardKey.keyH);
      final findInput = find.byKey(const ValueKey('find-query-input'));
      final replaceInput = find.byKey(const ValueKey('replace-query-input'));
      await tester.enterText(findInput, r'foo_(\d+)');
      await tester.enterText(replaceInput, r'item-$1');
      await tester.tap(find.byKey(const ValueKey('find-regex')));
      await _waitForIsolates(tester);
      await tester.pumpAndSettle();
      expect(find.text('-/2'), findsOneWidget);

      await tester.tap(find.byTooltip('替换'));
      await _waitForIsolates(tester);
      await tester.pumpAndSettle();
      expect(_documentText(tester), 'foo_1 foo_2',
          reason: 'the first click selects the next match');
      expect(
        tester
            .state<RustTextInputFieldState>(find.byType(RustTextInputField))
            .editingValue
            .selection,
        const TextSelection(baseOffset: 0, extentOffset: 5),
      );
      await tester.tap(find.byTooltip('替换'));
      await _waitForIsolates(tester);
      await tester.pumpAndSettle();
      expect(_documentText(tester), 'item-1 foo_2');

      await tester.tap(find.byType(RustTextInputField));
      await _pressChord(tester, LogicalKeyboardKey.keyS);
      await tester.pump(const Duration(milliseconds: 200));
      expect(file.readAsStringSync(), 'item-1 foo_2');

      await _pressChord(tester, LogicalKeyboardKey.keyZ);
      await tester.pumpAndSettle();
      expect(_documentText(tester), 'foo_1 foo_2');
      await _pressChord(tester, LogicalKeyboardKey.keyZ, shift: true);
      await tester.pumpAndSettle();
      expect(_documentText(tester), 'item-1 foo_2');

      await tester.tap(find.byTooltip('全部替换'));
      await _waitForIsolates(tester);
      await tester.pumpAndSettle();
      expect(_documentText(tester), 'item-1 item-2');
      await _pressChord(tester, LogicalKeyboardKey.keyZ);
      await tester.pumpAndSettle();
      expect(_documentText(tester), 'item-1 foo_2',
          reason: 'replace-all is one reversible document edit');
    },
  );

  testWidgets('a superseded regex replace cannot apply its stale result',
      (tester) async {
    final temp =
        Directory.systemTemp.createTempSync('alula-regex-replace-stale-');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    final workspace = Directory('${temp.path}/workspace')..createSync();
    final source = '${'a' * 20000}b';
    File('${workspace.path}/notes.txt').writeAsStringSync(source);
    final base = temp.path.replaceAll(r'\', '/');
    await tester.pumpWidget(AlulaApp(
      autoFolder: workspace.path,
      layoutStore: LayoutStore(path: '$base/layout.json'),
      sessionStore: SessionStore(path: '$base/session.json'),
      keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('notes.txt').first);
    await tester.pump(const Duration(milliseconds: 300));

    await _pressChord(tester, LogicalKeyboardKey.keyH);
    final findInput = find.byKey(const ValueKey('find-query-input'));
    await tester.enterText(findInput, r'^(a+)+$');
    await tester.enterText(
      find.byKey(const ValueKey('replace-query-input')),
      'replacement',
    );
    await tester.tap(find.byKey(const ValueKey('find-regex')));
    await tester.tap(find.byTooltip('全部替换'));
    await tester.enterText(findInput, 'no-match');
    await _waitForIsolates(tester);
    await tester.pumpAndSettle();

    expect(_documentText(tester), source);
  });
}
