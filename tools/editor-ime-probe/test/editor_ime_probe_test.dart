import 'package:code_forge/code_forge.dart';
import 'package:editor_ime_probe/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('CodeForge accepts and commits a composing input value', (
    tester,
  ) async {
    final controller = CodeForgeController()..text = 'seed';
    final undoController = UndoRedoController();
    final focusNode = FocusNode();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodeForge(
            controller: controller,
            undoController: undoController,
            focusNode: focusNode,
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(80, 25));
    await tester.pump(const Duration(milliseconds: 400));

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'seedni',
        selection: TextSelection.collapsed(offset: 6),
        composing: TextRange(start: 4, end: 6),
      ),
    );
    await tester.pump();

    final activeComposition = controller.imeComposition;
    debugPrint(
      'P00.4_IME_ACTIVE active=' +
          controller.isComposingActive.toString() +
          ' display=' +
          (activeComposition?.displayText ?? 'null') +
          ' committedText=' +
          controller.text,
    );
    expect(controller.isComposingActive, isTrue);
    expect(activeComposition, isNotNull);
    expect(controller.text, 'seed');

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'seed你好',
        selection: TextSelection.collapsed(offset: 6),
        composing: TextRange.empty,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    debugPrint(
      'P00.4_IME_COMMIT active=' +
          controller.isComposingActive.toString() +
          ' text=' +
          controller.text +
          ' canUndo=' +
          undoController.canUndo.toString(),
    );
    expect(controller.isComposingActive, isFalse);
    expect(controller.text, 'seed你好');
    expect(undoController.canUndo, isTrue);
    expect(undoController.undo(), isTrue);
    expect(controller.text, 'seed');

    controller.dispose();
    undoController.dispose();
    focusNode.dispose();
  });

  testWidgets('10k-line viewport exposes multi-cursor state and scroll', (
    tester,
  ) async {
    final controller = CodeForgeController()
      ..text = List<String>.generate(10000, (line) {
        final padded = line.toString().padLeft(5, '0');
        return 'line $padded  value = $line;';
      }).join('\n');
    final scrollController = ScrollController();
    final undoController = UndoRedoController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 700,
            child: CodeForge(
              controller: controller,
              undoController: undoController,
              verticalScrollController: scrollController,
              enableFolding: false,
              lineWrap: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    controller.addMultiCursor(1, 5);
    controller.addMultiCursor(3, 5);
    controller.addMultiCursor(5, 5);
    await tester.pump();
    scrollController.jumpTo(scrollController.position.maxScrollExtent / 2);
    await tester.pump();

    debugPrint(
      'P00.4_VIEWPORT lines=' +
          controller.lineCount.toString() +
          ' chars=' +
          controller.length.toString() +
          ' cursors=' +
          controller.multiCursors.length.toString() +
          ' scroll=' +
          scrollController.position.pixels.toStringAsFixed(1) +
          ' max=' +
          scrollController.position.maxScrollExtent.toStringAsFixed(1),
    );
    expect(controller.lineCount, 10000);
    expect(controller.multiCursors.length, 3);
    expect(scrollController.position.pixels, greaterThan(0));
    expect(find.byType(CodeForge), findsOneWidget);

    controller.dispose();
    undoController.dispose();
    scrollController.dispose();
  });

  testWidgets('typed input fans out to all cursors and undoes together', (
    tester,
  ) async {
    const original = 'a\nb\nc\nd';
    final controller = CodeForgeController()
      ..text = original
      ..selection = const TextSelection.collapsed(offset: 1);
    final undoController = UndoRedoController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodeForge(
            controller: controller,
            undoController: undoController,
            autoFocus: true,
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(80, 25));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.testTextInput.isVisible, isTrue);
    controller.selection = const TextSelection.collapsed(offset: 1);
    controller.addMultiCursor(1, 1);
    controller.addMultiCursor(2, 1);
    controller.addMultiCursor(3, 1);
    await tester.pump();

    // CodeForge opts into DeltaTextInputClient. Drive the same insertion delta
    // the Windows text-input channel sends; TestTextInput's helper sends the
    // legacy full-value update and does not exercise multi-cursor insertion.
    // ignore: invalid_use_of_protected_member
    controller.updateEditingValueWithDeltas(
      const [
        TextEditingDeltaInsertion(
          oldText: original,
          textInserted: 'X',
          insertionOffset: 1,
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange.empty,
        ),
      ],
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    debugPrint(
      'P00.4_MULTICURSOR_TEXT chars=' +
          controller.length.toString() +
          ' text=' +
          controller.text.replaceAll('\n', '|') +
          ' cursors=' +
          controller.multiCursors.length.toString(),
    );
    expect(controller.text, 'aX\nbX\ncX\ndX');
    expect(controller.multiCursors.length, 3);
    expect(undoController.undo(), isTrue);
    expect(controller.text, original);
    await tester.pump(const Duration(milliseconds: 100));

    controller.dispose();
    undoController.dispose();
  });

  testWidgets('probe page starts with a ten-thousand-line document', (
    tester,
  ) async {
    await tester.pumpWidget(const EditorImeProbeApp());
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Lines: 10000'), findsOneWidget);
    expect(find.byType(CodeForge), findsOneWidget);
  });
}
