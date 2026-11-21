import 'dart:ui' show Tristate;

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/workbench/auxiliary_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'compact mode reduces auxiliary chrome and restores it without changing the document',
    (tester) async {
      const windowManagerChannel = MethodChannel('window_manager');
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        windowManagerChannel,
        (call) async {
          calls.add(call);
          switch (call.method) {
            case 'isAlwaysOnTop':
            case 'isFocused':
              return false;
            case 'setPreventClose':
              return null;
            default:
              return null;
          }
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(windowManagerChannel, null);
      });

      const body = 'alpha\r\nsecond 😀 line\n';
      final payload = AuxiliaryWindowPayload.forDocument(
        documentId: 100,
        name: 'notes.txt',
        mainWindowId: 'main',
        text: body,
        dirty: true,
      );
      final originalPayload = payload.toArguments();
      await tester.pumpWidget(
        MaterialApp(home: AuxiliaryEditorApp(payload: payload)),
      );
      await tester.pumpAndSettle();

      final inputFinder = find.byKey(const ValueKey('auxiliary-editor-input'));
      expect(inputFinder, findsOneWidget);
      final inputState = tester.state<RustTextInputFieldState>(inputFinder);
      final inputWindow = inputState.widget.inputWindow;
      final doc = inputWindow.document;
      inputState.setSelection(
        const TextSelection(baseOffset: 1, extentOffset: 5),
      );
      await tester.pump();

      final originalSelection = inputState.editingValue.selection;
      final originalVersion = doc.version;
      final originalTitleSize =
          tester.getSize(find.byKey(const ValueKey('auxiliary-title-row')));
      final originalEditorRect = tester.getRect(inputFinder);
      final callsBeforeToggle = calls.length;

      final compactSemantics =
          find.byKey(const ValueKey('auxiliary-compact-mode-semantics'));
      final compactButton =
          find.byKey(const ValueKey('auxiliary-compact-mode-button'));
      expect(
        tester.widget<IconButton>(compactButton).tooltip,
        '启用紧凑模式',
      );
      final expandedSemantics =
          tester.getSemantics(compactSemantics).getSemanticsData();
      expect(expandedSemantics.label, '紧凑模式');
      expect(expandedSemantics.flagsCollection.isButton, isTrue);
      expect(
        expandedSemantics.flagsCollection.isToggled,
        Tristate.isFalse,
      );
      await tester.tap(compactButton);
      await tester.pumpAndSettle();

      final compactTitleSize =
          tester.getSize(find.byKey(const ValueKey('auxiliary-title-row')));
      final compactEditorRect = tester.getRect(inputFinder);
      expect(originalTitleSize.height - compactTitleSize.height, 8);
      expect(originalEditorRect.top - compactEditorRect.top, 12);
      expect(originalEditorRect.left - compactEditorRect.left, 4);
      expect(find.text('notes.txt •'), findsNothing);
      expect(tester.widget<IconButton>(compactButton).tooltip, '退出紧凑模式');
      expect(
        tester
            .getSemantics(compactSemantics)
            .getSemanticsData()
            .flagsCollection
            .isToggled,
        Tristate.isTrue,
      );
      expect(
        find.byKey(const ValueKey('auxiliary-always-on-top-button')),
        findsOneWidget,
      );
      expect(
          find.byKey(const ValueKey('auxiliary-close-button')), findsOneWidget);

      await tester.tap(compactButton);
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byKey(const ValueKey('auxiliary-title-row'))),
        originalTitleSize,
      );
      expect(tester.getRect(inputFinder), originalEditorRect);
      expect(find.text('notes.txt •'), findsOneWidget);
      expect(tester.widget<IconButton>(compactButton).tooltip, '启用紧凑模式');
      expect(doc.resync().content, body);
      expect(inputWindow.text, body);
      expect(doc.version, originalVersion);
      expect(doc.isDirty, isTrue);
      expect(inputState.editingValue.selection, originalSelection);
      expect(payload.toArguments(), originalPayload);
      expect(calls, hasLength(callsBeforeToggle));
      expect(calls.where((call) => call.method == 'setAlwaysOnTop'), isEmpty);
    },
  );
}
