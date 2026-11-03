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
