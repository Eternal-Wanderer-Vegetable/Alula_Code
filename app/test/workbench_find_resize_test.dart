import 'dart:io';

import 'package:alula_app/editor/editor_minimap.dart';
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

Future<void> _doubleTap(WidgetTester tester, Finder target) async {
  await tester.tap(target);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Find sash resizes within editor bounds and persists without editing text',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      final temp = Directory.systemTemp.createTempSync('alula-find-resize-');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
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
      final document = editorState.widget.inputWindow.document;
      const originalSelection = TextSelection.collapsed(offset: 0);
      editorState.setSelection(originalSelection);
      editorState.requestFocus();
      await tester.pump();
      final version = document.version;
      final diskBytes = file.readAsBytesSync();

      await _pressChord(tester, LogicalKeyboardKey.keyF);
      await tester.pumpAndSettle();
      final findBar = find.byKey(const ValueKey('find-bar'));
      final findInput = find.byKey(const ValueKey('find-query-input'));
      final resizeHandle = find.byKey(const ValueKey('find-bar-resize-handle'));
      final availableBounds =
          find.byKey(const ValueKey('find-bar-available-bounds'));
      expect(tester.getSize(findBar).width, 419);
      expect(tester.getRect(resizeHandle).left,
          closeTo(tester.getRect(findBar).left, 0.5));
      expect(tester.getRect(findInput).left,
          greaterThanOrEqualTo(tester.getRect(resizeHandle).right));
      final maximumWidth = tester.getSize(availableBounds).width;
      expect(maximumWidth, greaterThan(419));

      await tester.drag(resizeHandle, const Offset(-120, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(findBar).width, 519);
      await tester.drag(resizeHandle, const Offset(-10000, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(findBar).width, maximumWidth);
      expect(tester.getSize(findBar).width, lessThanOrEqualTo(maximumWidth));
      final minimap = find.byType(EditorMinimap);
      expect(minimap, findsOneWidget);
      expect(
        tester.getRect(findBar).right,
        lessThanOrEqualTo(tester.getRect(minimap).left),
      );

      await tester.drag(resizeHandle, const Offset(10000, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(findBar).width, 419);
      await _doubleTap(tester, resizeHandle);
      await tester.pumpAndSettle();
      expect(tester.getSize(findBar).width, maximumWidth);
      await _doubleTap(tester, resizeHandle);
      await tester.pumpAndSettle();
      expect(tester.getSize(findBar).width, 419);

      await tester.enterText(findInput, 'foo');
      editorState.requestFocus();
      await tester.pump();
      await _pressChord(tester, LogicalKeyboardKey.keyH);
      await tester.pumpAndSettle();
      final replaceInput = find.byKey(const ValueKey('replace-query-input'));
      await tester.enterText(replaceInput, 'bar');
      await tester.pumpAndSettle();
      expect(tester.getSize(findInput).width,
          closeTo(tester.getSize(replaceInput).width, 0.5));
      expect(tester.widget<TextField>(findInput).controller!.text, 'foo');
      expect(tester.widget<TextField>(replaceInput).controller!.text, 'bar');

      await tester.drag(resizeHandle, const Offset(-100, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(findBar).width, 499);
      expect(
        tester.getSize(findInput).width,
        closeTo(tester.getSize(replaceInput).width, 0.5),
      );

      tester.view.physicalSize = const Size(640, 800);
      await tester.pumpAndSettle();
      final narrowMaximumWidth = tester.getSize(availableBounds).width;
      expect(
          tester.getSize(findBar).width, lessThanOrEqualTo(narrowMaximumWidth));
      expect(tester.getSize(findInput).width,
          closeTo(tester.getSize(replaceInput).width, 0.5));
      expect(find.byTooltip('下一个匹配'), findsOneWidget);
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(1600, 1000);
      await tester.pumpAndSettle();
      expect(tester.getSize(findBar).width, 499);

      editorState.requestFocus();
      await tester.pump();
      await _pressChord(tester, LogicalKeyboardKey.keyF);
      await tester.pumpAndSettle();
      expect(findBar, findsNothing);
      await _pressChord(tester, LogicalKeyboardKey.keyF);
      await tester.pumpAndSettle();
      expect(tester.getSize(findBar).width, 499);
      expect(tester.widget<TextField>(findInput).controller!.text, 'foo');
      expect(editorState.editingValue.selection, originalSelection);
      expect(document.version, version);
      expect(document.isDirty, isFalse);
      expect(document.resync().content, source);
      expect(file.readAsBytesSync(), diskBytes);
      expect(tester.takeException(), isNull);
    },
  );
}
