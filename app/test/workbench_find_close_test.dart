import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pressChord(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _pressShiftEscape(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Escape and close restore editor focus and clear find selection scope',
    (tester) async {
      final temp = Directory.systemTemp.createTempSync('alula-find-close-');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });

      final workspace = Directory('${temp.path}/workspace')..createSync();
      const source = 'foo bar foo';
      final file = File('${workspace.path}/notes.txt')
        ..writeAsStringSync(source);
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

      final editorFinder = find.byType(RustTextInputField);
      final editorState = tester.state<RustTextInputFieldState>(editorFinder);
      final editorFocus = editorState.widget.focusNode!;
      final document = editorState.widget.inputWindow.document;
      const originalSelection = TextSelection(baseOffset: 0, extentOffset: 3);
      editorState.setSelection(originalSelection);
      editorState.requestFocus();
      await tester.pump();
      final version = document.version;
      final diskBytes = file.readAsBytesSync();

      await _pressChord(tester, LogicalKeyboardKey.keyF);
      final findBar = find.byKey(const ValueKey('find-bar'));
      final queryInput = find.byKey(const ValueKey('find-query-input'));
      await tester.enterText(queryInput, 'foo');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('find-in-selection')));
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('find-in-selection')))
            .isSelected,
        isTrue,
      );
      expect(find.text('-/1'), findsOneWidget);

      await tester.tap(queryInput);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(findBar, findsNothing);
      expect(editorFocus.hasFocus, isTrue);
      expect(editorState.editingValue.selection, originalSelection);
      expect(document.version, version);
      expect(document.isDirty, isFalse);
      expect(document.resync().content, source);
      expect(file.readAsBytesSync(), diskBytes);

      // A collapsed caret on the separator does not reseed the query, so the
      // reopened count also proves that closing discarded the old scope.
      editorState.setSelection(const TextSelection.collapsed(offset: 3));
      editorState.requestFocus();
      await tester.pump();
      await _pressChord(tester, LogicalKeyboardKey.keyF);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(queryInput).controller!.text, 'foo');
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('find-in-selection')))
            .isSelected,
        isFalse,
      );
      expect(find.text('-/2'), findsOneWidget);

      editorState.requestFocus();
      await tester.pump();
      await _pressChord(tester, LogicalKeyboardKey.keyH);
      final replaceInput = find.byKey(const ValueKey('replace-query-input'));
      expect(replaceInput, findsOneWidget);
      await tester.tap(replaceInput);
      await _pressShiftEscape(tester);
      expect(findBar, findsNothing);
      expect(editorFocus.hasFocus, isTrue);
      expect(document.version, version);
      expect(document.resync().content, source);
      expect(file.readAsBytesSync(), diskBytes);

      editorState.requestFocus();
      await tester.pump();
      await _pressChord(tester, LogicalKeyboardKey.keyF);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(findBar, findsNothing);
      expect(editorFocus.hasFocus, isTrue);
      expect(document.version, version);
      expect(document.isDirty, isFalse);
      expect(document.resync().content, source);
      expect(file.readAsBytesSync(), diskBytes);
    },
  );
}
