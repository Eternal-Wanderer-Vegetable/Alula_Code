import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pressChord(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  required LogicalKeyboardKey modifier,
  bool shift = false,
}) async {
  await tester.sendKeyDownEvent(modifier);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
  await tester.pump();
}

Future<void> _openFile(WidgetTester tester, String name) async {
  await tester.tap(find.text(name).first);
  await tester.pump(const Duration(milliseconds: 300));
  final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
  await tester.showKeyboard(editor);
  await tester.pump();
}

Future<void> _withTargetPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  const platforms = [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ];

  for (final platform in platforms) {
    testWidgets('$platform cursor history stays separate from text undo',
        (tester) async {
      await _withTargetPlatform(platform, () async {
        final temp = Directory.systemTemp.createTempSync('alula-cursor-undo');
        addTearDown(() async {
          debugDefaultTargetPlatformOverride = null;
          await tester.pumpWidget(const SizedBox.shrink());
          if (temp.existsSync()) temp.deleteSync(recursive: true);
        });

        final workspace = Directory('${temp.path}/workspace')..createSync();
        final file = File('${workspace.path}/sample.txt')
          ..writeAsStringSync('foo foo');
        final base = temp.path.replaceAll(r'\\', '/');
        await tester.pumpWidget(AlulaApp(
          autoFolder: workspace.path,
          layoutStore: LayoutStore(path: '$base/layout.json'),
          sessionStore: SessionStore(path: '$base/session.json'),
          keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
        ));
        await tester.pump(const Duration(milliseconds: 600));
        await _openFile(tester, 'sample.txt');

        final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
        var field = tester.widget<RustTextInputField>(
          find.byType(RustTextInputField),
        );
        final document = field.inputWindow.document;
        final controller = tester.widget<TextField>(editor).controller!;
        controller.selection =
            const TextSelection(baseOffset: 0, extentOffset: 3);
        await tester.pump();

        final occurrenceModifier = platform == TargetPlatform.macOS
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;
        await _pressChord(
          tester,
          LogicalKeyboardKey.keyD,
          modifier: occurrenceModifier,
        );
        field =
            tester.widget<RustTextInputField>(find.byType(RustTextInputField));
        expect(field.additionalSelections, const [
          TextSelection(baseOffset: 4, extentOffset: 7),
        ]);

        final selectionVersion = document.version;
        await _pressChord(
          tester,
          LogicalKeyboardKey.keyU,
          modifier: LogicalKeyboardKey.controlLeft,
        );
        field =
            tester.widget<RustTextInputField>(find.byType(RustTextInputField));
        expect(controller.selection,
            const TextSelection(baseOffset: 0, extentOffset: 3));
        expect(field.additionalSelections, isEmpty);
        expect(document.resync().content, 'foo foo');
        expect(document.version, selectionVersion);

        await _pressChord(
          tester,
          LogicalKeyboardKey.keyU,
          modifier: LogicalKeyboardKey.controlLeft,
          shift: true,
        );
        field =
            tester.widget<RustTextInputField>(find.byType(RustTextInputField));
        expect(field.additionalSelections, const [
          TextSelection(baseOffset: 4, extentOffset: 7),
        ]);
        expect(document.resync().content, 'foo foo');
        expect(document.version, selectionVersion);

        tester.testTextInput.updateEditingValue(const TextEditingValue(
          text: 'bar bar',
          selection: TextSelection.collapsed(offset: 3),
        ));
        await tester.pump();
        await tester.pump();
        expect(document.resync().content, 'bar bar');
        final editedVersion = document.version;

        // Cursor undo changes only the selection and leaves the text undo frame
        // available for the following Ctrl+Z.
        await _pressChord(
          tester,
          LogicalKeyboardKey.keyU,
          modifier: LogicalKeyboardKey.controlLeft,
        );
        expect(document.resync().content, 'bar bar');
        expect(document.version, editedVersion);

        await _pressChord(
          tester,
          LogicalKeyboardKey.keyZ,
          modifier: LogicalKeyboardKey.controlLeft,
        );
        expect(document.resync().content, 'foo foo');
        await _pressChord(
          tester,
          LogicalKeyboardKey.keyZ,
          modifier: LogicalKeyboardKey.controlLeft,
          shift: true,
        );
        expect(document.resync().content, 'bar bar');
        expect(file.readAsStringSync(), 'foo foo');
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('$platform cursor and text histories stay with each document',
        (tester) async {
      await _withTargetPlatform(platform, () async {
        final temp =
            Directory.systemTemp.createTempSync('alula-document-cursor-undo');
        addTearDown(() async {
          debugDefaultTargetPlatformOverride = null;
          await tester.pumpWidget(const SizedBox.shrink());
          if (temp.existsSync()) temp.deleteSync(recursive: true);
        });

        final workspace = Directory('${temp.path}/workspace')..createSync();
        final aFile = File('${workspace.path}/a.txt')
          ..writeAsStringSync('foo foo');
        final bFile = File('${workspace.path}/b.txt')
          ..writeAsStringSync('bar bar');
        final base = temp.path.replaceAll(r'\\', '/');
        await tester.pumpWidget(AlulaApp(
          autoFolder: workspace.path,
          layoutStore: LayoutStore(path: '$base/layout.json'),
          sessionStore: SessionStore(path: '$base/session.json'),
          keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
        ));
        await tester.pump(const Duration(milliseconds: 600));
        await _openFile(tester, 'a.txt');

        final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
        var field =
            tester.widget<RustTextInputField>(find.byType(RustTextInputField));
        final aDocument = field.inputWindow.document;
        final aController = tester.widget<TextField>(editor).controller!;
        aController.selection =
            const TextSelection(baseOffset: 0, extentOffset: 3);
        await tester.pump();
        final occurrenceModifier = platform == TargetPlatform.macOS
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;
        await _pressChord(
          tester,
          LogicalKeyboardKey.keyD,
          modifier: occurrenceModifier,
        );

        await _openFile(tester, 'b.txt');
        field =
            tester.widget<RustTextInputField>(find.byType(RustTextInputField));
        final bDocument = field.inputWindow.document;
        final bController = tester.widget<TextField>(editor).controller!;
        bController.selection =
            const TextSelection(baseOffset: 0, extentOffset: 3);
        await tester.pump();
        await _pressChord(
          tester,
          LogicalKeyboardKey.keyD,
          modifier: occurrenceModifier,
        );

        final bVersionBeforeCursorUndo = bDocument.version;
        await _pressChord(
          tester,
          LogicalKeyboardKey.keyU,
          modifier: LogicalKeyboardKey.controlLeft,
        );
        field =
            tester.widget<RustTextInputField>(find.byType(RustTextInputField));
        expect(bController.selection,
            const TextSelection(baseOffset: 0, extentOffset: 3));
        expect(field.additionalSelections, isEmpty);
        expect(bDocument.resync().content, 'bar bar');
        expect(bDocument.version, bVersionBeforeCursorUndo);

        await _pressChord(
          tester,
          LogicalKeyboardKey.keyU,
          modifier: LogicalKeyboardKey.controlLeft,
          shift: true,
        );
        field =
            tester.widget<RustTextInputField>(find.byType(RustTextInputField));
        expect(field.additionalSelections, const [
          TextSelection(baseOffset: 4, extentOffset: 7),
        ]);

        await tester.tap(find.byKey(ValueKey('tab-${aDocument.id}')));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.showKeyboard(editor);
        await tester.pump();
        field =
            tester.widget<RustTextInputField>(find.byType(RustTextInputField));
        expect(field.inputWindow.document.id, aDocument.id);
        expect(field.additionalSelections, const [
          TextSelection(baseOffset: 4, extentOffset: 7),
        ]);

        final aVersionBeforeCursorUndo = aDocument.version;
        await _pressChord(
          tester,
          LogicalKeyboardKey.keyU,
          modifier: LogicalKeyboardKey.controlLeft,
        );
        field =
            tester.widget<RustTextInputField>(find.byType(RustTextInputField));
        expect(field.additionalSelections, isEmpty);
        expect(aDocument.resync().content, 'foo foo');
        expect(aDocument.version, aVersionBeforeCursorUndo);

        // Text undo and redo remain attached to their own document after tab
        // switches, independently of either cursor history.
        await _replaceDocumentText(tester, 'one one');
        expect(aDocument.resync().content, 'one one');

        await tester.tap(find.byKey(ValueKey('tab-${bDocument.id}')));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.showKeyboard(editor);
        await tester.pump();
        await _replaceDocumentText(tester, 'two two');
        expect(bDocument.resync().content, 'two two');

        // Undo B while A's edit remains, then undo A after switching back.
        await _pressChord(
          tester,
          LogicalKeyboardKey.keyZ,
          modifier: LogicalKeyboardKey.controlLeft,
        );
        expect(bDocument.resync().content, 'bar bar');
        expect(aDocument.resync().content, 'one one');

        await tester.tap(find.byKey(ValueKey('tab-${aDocument.id}')));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.showKeyboard(editor);
        await tester.pump();
        await _pressChord(
          tester,
          LogicalKeyboardKey.keyZ,
          modifier: LogicalKeyboardKey.controlLeft,
        );
        expect(aDocument.resync().content, 'foo foo');

        await _pressChord(
          tester,
          LogicalKeyboardKey.keyZ,
          modifier: LogicalKeyboardKey.controlLeft,
          shift: true,
        );
        expect(aDocument.resync().content, 'one one');
        expect(bDocument.resync().content, 'bar bar');

        await tester.tap(find.byKey(ValueKey('tab-${bDocument.id}')));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.showKeyboard(editor);
        await tester.pump();
        await _pressChord(
          tester,
          LogicalKeyboardKey.keyZ,
          modifier: LogicalKeyboardKey.controlLeft,
          shift: true,
        );
        expect(bDocument.resync().content, 'two two');
        expect(aDocument.resync().content, 'one one');
        expect(aFile.readAsStringSync(), 'foo foo');
        expect(bFile.readAsStringSync(), 'bar bar');
        expect(tester.takeException(), isNull);
      });
    });
  }
}

Future<void> _replaceDocumentText(WidgetTester tester, String text) async {
  tester.testTextInput.updateEditingValue(TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length ~/ 2),
  ));
  await tester.pump();
  await tester.pump();
}
