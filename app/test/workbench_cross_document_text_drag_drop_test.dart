import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/editor/text_drag_drop.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

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

Future<void> _unmountAndDeleteTempDirectory(
  WidgetTester tester,
  Directory directory,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await _deleteDirectoryWithRetry(directory);
}

void main() {
  testWidgets(
    'cross-document copy updates target, preserves source, and saves undoably',
    (tester) async {
      final temp = Directory.systemTemp.createTempSync('alula-cross-doc-drop');
      addTearDown(() => _unmountAndDeleteTempDirectory(tester, temp));

      final workspace = Directory('${temp.path}/workspace')..createSync();
      const sourceText = 'fn source() { println!("alpha"); }';
      const targetText = 'fn target() {}';
      final sourceFile = File('${workspace.path}/source.rs')
        ..writeAsStringSync(sourceText);
      final targetFile = File('${workspace.path}/target.rs')
        ..writeAsStringSync(targetText);
      final base = temp.path.replaceAll(r'\', '/');
      final layoutStore = LayoutStore(path: '$base/layout.json');
      final sessionStore = SessionStore(path: '$base/session.json');
      sessionStore.save({
        'v': 1,
        'focused': 'editor',
        'workspace': workspace.path,
        'groups': [
          {
            'region': 'editor',
            'active': 97632,
            'docs': [
              {'id': 97631, 'path': sourceFile.path},
              {'id': 97632, 'path': targetFile.path},
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

      await tester.tap(find.text('source.rs').first);
      await tester.pump(const Duration(milliseconds: 250));
      final sourceField = tester.widget<RustTextInputField>(
        find.byType(RustTextInputField),
      );
      expect(sourceField.inputWindow.document.id, 97631);
      expect(sourceField.inputWindow.document.resync().content, sourceText);
      final sourceVersion = sourceField.inputWindow.document.version;
      final selectionStart = sourceText.indexOf('alpha');
      expect(selectionStart, greaterThanOrEqualTo(0));

      await tester.tap(find.text('target.rs').first);
      await tester.pump(const Duration(milliseconds: 250));
      final targetField = tester.widget<RustTextInputField>(
        find.byType(RustTextInputField),
      );
      expect(targetField.inputWindow.document.id, 97632);
      expect(targetField.inputWindow.document.resync().content, targetText);
      expect(targetField.onTextDragDrop, isNotNull);

      final request = EditorTextDragDropRequest(
        payload: EditorTextDragPayload(
          selection: EditorTextDragSelection(
            documentId: sourceField.inputWindow.document.id,
            documentVersion: sourceVersion,
            startUtf16: selectionStart,
            endUtf16: selectionStart + 'alpha'.length,
          ),
          selectedText: 'alpha',
          token: 97631,
        ),
        targetDocumentId: targetField.inputWindow.document.id,
        targetDocumentVersion: targetField.inputWindow.document.version,
        targetOffsetUtf16: targetText.length,
        operation: EditorTextDropOperation.copy,
      );
      targetField.onTextDragDrop!(request);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      var views = tester
          .widgetList<RustTextInputField>(find.byType(RustTextInputField))
          .toList();
      expect(views, hasLength(1));
      expect(views.single.inputWindow.document.id, 97632);
      expect(
        views.single.inputWindow.document.resync().content,
        '${targetText}alpha',
      );
      expect(views.single.inputWindow.document.isDirty, isTrue);
      expect(sourceField.inputWindow.document.resync().content, sourceText);
      expect(sourceFile.readAsStringSync(), sourceText);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 50));
      views = tester
          .widgetList<RustTextInputField>(find.byType(RustTextInputField))
          .toList();
      expect(views.single.inputWindow.document.resync().content, targetText);
      expect(views.single.inputWindow.document.isDirty, isFalse);
      expect(sourceField.inputWindow.document.resync().content, sourceText);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 50));
      views = tester
          .widgetList<RustTextInputField>(find.byType(RustTextInputField))
          .toList();
      expect(
        views.single.inputWindow.document.resync().content,
        '${targetText}alpha',
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 100));
      expect(targetFile.readAsStringSync(), '${targetText}alpha');
      expect(views.single.inputWindow.document.isDirty, isFalse);
      expect(sourceField.inputWindow.document.resync().content, sourceText);
    },
  );

  testWidgets(
    'cross-document move edits and undoes both documents atomically',
    (tester) async {
      final temp = Directory.systemTemp.createTempSync('alula-cross-doc-move');
      addTearDown(() => _unmountAndDeleteTempDirectory(tester, temp));

      final workspace = Directory('${temp.path}/workspace')..createSync();
      const sourceText = 'fn source() { println!("alpha"); }';
      const targetText = 'fn target() {}';
      final sourceFile = File('${workspace.path}/source.rs')
        ..writeAsStringSync(sourceText);
      final targetFile = File('${workspace.path}/target.rs')
        ..writeAsStringSync(targetText);
      final base = temp.path.replaceAll(r'\', '/');
      final layoutStore = LayoutStore(path: '$base/layout.json');
      final sessionStore = SessionStore(path: '$base/session.json');
      sessionStore.save({
        'v': 1,
        'focused': 'editor',
        'workspace': workspace.path,
        'groups': [
          {
            'region': 'editor',
            'active': 97642,
            'docs': [
              {'id': 97641, 'path': sourceFile.path},
              {'id': 97642, 'path': targetFile.path},
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

      await tester.tap(find.text('source.rs').first);
      await tester.pump(const Duration(milliseconds: 250));
      final sourceField = tester.widget<RustTextInputField>(
        find.byType(RustTextInputField),
      );
      final sourceDocument = sourceField.inputWindow.document;
      expect(sourceDocument.id, 97641);
      expect(sourceDocument.resync().content, sourceText);
      final selectionStart = sourceText.indexOf('alpha');
      final sourceVersion = sourceDocument.version;

      await tester.tap(find.text('target.rs').first);
      await tester.pump(const Duration(milliseconds: 250));
      final targetField = tester.widget<RustTextInputField>(
        find.byType(RustTextInputField),
      );
      final targetDocument = targetField.inputWindow.document;
      expect(targetDocument.id, 97642);
      expect(targetField.onTextDragDrop, isNotNull);
      expect(sourceField.onTextDragCompleted, isNotNull);

      final payload = EditorTextDragPayload(
        selection: EditorTextDragSelection(
          documentId: sourceDocument.id,
          documentVersion: sourceVersion,
          startUtf16: selectionStart,
          endUtf16: selectionStart + 'alpha'.length,
        ),
        selectedText: 'alpha',
        token: 97641,
      );
      targetField.onTextDragDrop!(EditorTextDragDropRequest(
        payload: payload,
        targetDocumentId: targetDocument.id,
        targetDocumentVersion: targetDocument.version,
        targetOffsetUtf16: targetText.length,
        operation: EditorTextDropOperation.move,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(sourceDocument.resync().content,
          sourceText.replaceFirst('alpha', ''));
      expect(targetDocument.resync().content, '${targetText}alpha');
      expect(sourceDocument.isDirty, isTrue);
      expect(targetDocument.isDirty, isTrue);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 50));
      expect(sourceDocument.resync().content, sourceText);
      expect(targetDocument.resync().content, targetText);
      expect(sourceDocument.isDirty, isFalse);
      expect(targetDocument.isDirty, isFalse);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 50));
      expect(sourceDocument.resync().content,
          sourceText.replaceFirst('alpha', ''));
      expect(targetDocument.resync().content, '${targetText}alpha');
      expect(sourceDocument.isDirty, isTrue);
      expect(targetDocument.isDirty, isTrue);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 100));
      expect(targetFile.readAsStringSync(), '${targetText}alpha');
      expect(targetDocument.isDirty, isFalse);

      await tester.tap(find.text('source.rs').first);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 100));
      expect(
          sourceFile.readAsStringSync(), sourceText.replaceFirst('alpha', ''));
      expect(sourceDocument.isDirty, isFalse);

      await tester.enterText(find.byType(EditableText), '!');
      await tester.pump(const Duration(milliseconds: 50));
      final sourceWithFollowUp = sourceDocument.resync().content;
      expect(sourceWithFollowUp, isNot(sourceText.replaceFirst('alpha', '')));

      await tester.tap(find.text('target.rs').first);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 50));
      expect(sourceDocument.resync().content, sourceWithFollowUp);
      expect(targetDocument.resync().content, '${targetText}alpha');

      await tester.tap(find.text('source.rs').first);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 50));
      expect(sourceDocument.resync().content,
          sourceText.replaceFirst('alpha', ''));

      await tester.tap(find.text('target.rs').first);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 50));
      expect(sourceDocument.resync().content, sourceText);
      expect(targetDocument.resync().content, targetText);

      await tester.tap(find.text('source.rs').first);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 50));
      expect(sourceDocument.resync().content,
          sourceText.replaceFirst('alpha', ''));
      expect(targetDocument.resync().content, '${targetText}alpha');
      expect(sourceDocument.isDirty, isFalse);
      expect(targetDocument.isDirty, isFalse);

      // A stale target version is rejected by the internal move handler. The
      // drag-completed fallback must not then delete text from the source.
      final beforeRejectedDropSource = sourceDocument.resync().content;
      final beforeRejectedDropTarget = targetDocument.resync().content;
      final rejectedPayload = EditorTextDragPayload(
        selection: EditorTextDragSelection(
          documentId: sourceDocument.id,
          documentVersion: sourceDocument.version,
          startUtf16: sourceText.indexOf('println'),
          endUtf16: sourceText.indexOf('println') + 'println'.length,
        ),
        selectedText: 'println',
        token: 97643,
      );
      await tester.tap(find.text('target.rs').first);
      await tester.pump(const Duration(milliseconds: 100));
      final currentTargetField = tester.widget<RustTextInputField>(
        find.byType(RustTextInputField),
      );
      currentTargetField.onTextDragDrop!(EditorTextDragDropRequest(
        payload: rejectedPayload,
        targetDocumentId: targetDocument.id,
        targetDocumentVersion: targetDocument.version + 1,
        targetOffsetUtf16: targetDocument.resync().content.length,
        operation: EditorTextDropOperation.move,
      ));
      sourceField.onTextDragCompleted!(
        rejectedPayload,
        EditorTextDropOperation.move,
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(sourceDocument.resync().content, beforeRejectedDropSource);
      expect(targetDocument.resync().content, beforeRejectedDropTarget);
      expect(sourceFile.readAsStringSync(), beforeRejectedDropSource);
      expect(targetFile.readAsStringSync(), beforeRejectedDropTarget);
    },
  );
}
