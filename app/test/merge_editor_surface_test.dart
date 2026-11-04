import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/editor/merge_editor_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows selectable frozen sources and toggles the base pane',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: MergeEditorSurface(
          base: 'base snapshot 😀\r\n',
          input1: 'input one\n',
          input2: 'input two\n',
          resultEditor: ColoredBox(
            key: ValueKey('merge-test-result-editor'),
            color: Colors.blueGrey,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('merge-editor-pane-input1')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('merge-editor-pane-input2')), findsOneWidget);
    expect(find.byKey(const ValueKey('merge-editor-pane-base')), findsNothing);
    expect(find.byKey(const ValueKey('merge-editor-pane-result-frame')),
        findsOneWidget);

    final input1Pane = find.byKey(const ValueKey('merge-editor-pane-input1'));
    final input1Selectable = find.descendant(
      of: input1Pane,
      matching: find.byType(SelectableText),
    );
    expect(input1Selectable, findsOneWidget);
    expect(tester.widget<SelectableText>(input1Selectable).data, 'input one\n');
    final input1Editable = find.descendant(
      of: input1Pane,
      matching: find.byType(EditableText),
    );
    expect(input1Editable, findsOneWidget);
    expect(tester.widget<EditableText>(input1Editable).readOnly, isTrue);
    expect(
      find.descendant(of: input1Pane, matching: find.byType(TextField)),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('merge-editor-toggle-base')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('merge-editor-pane-base')), findsOneWidget);
    final baseText = find.descendant(
      of: find.byKey(const ValueKey('merge-editor-pane-base')),
      matching: find.byType(SelectableText),
    );
    expect(
        tester.widget<SelectableText>(baseText).data, 'base snapshot 😀\r\n');
  });

  testWidgets('columns layout adapts to a narrow viewport without overflow',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: MergeEditorSurface(
          base: 'base\n',
          input1: 'ours\n',
          input2: 'theirs\n',
          resultEditor: ColoredBox(color: Colors.blueGrey),
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('merge-editor-layout-columns')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('merge-editor-narrow-layout-hint')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(360, 700);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('merge-editor-narrow-layout-hint')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('merge-editor-mixed-source-scroll')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('merge-editor-pane-result-frame')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows conflict status and routes active conflict actions',
      (tester) async {
    var previous = 0;
    var next = 0;
    var acceptInput1 = 0;
    var acceptInput2 = 0;
    const first = AlulaMergeConflict(
      id: 7,
      baseStartLine: 1,
      baseEndLineExclusive: 2,
      resultStartUtf16: 5,
      resultEndUtf16: 9,
      baseText: 'base',
      input1Text: 'left',
      input2Text: 'right',
      resolution: null,
    );
    const second = AlulaMergeConflict(
      id: 9,
      baseStartLine: 4,
      baseEndLineExclusive: 5,
      resultStartUtf16: 20,
      resultEndUtf16: 25,
      baseText: 'base2',
      input1Text: 'left2',
      input2Text: 'right2',
      resolution: AlulaMergeSide.input1,
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MergeEditorSurface(
          base: '',
          input1: '',
          input2: '',
          resultEditor: const ColoredBox(color: Colors.blueGrey),
          conflicts: const [first, second],
          resolutions: const {9: AlulaMergeSide.input1},
          unresolvedConflictCount: 1,
          activeConflict: first,
          onNavigatePrevious: () => previous++,
          onNavigateNext: () => next++,
          onAcceptInput1: () => acceptInput1++,
          onAcceptInput2: () => acceptInput2++,
        ),
      ),
    ));

    expect(find.text('Conflict 1 of 2 · 1 unresolved'), findsOneWidget);
    final previousButton =
        find.byKey(const ValueKey('merge-editor-previous-unhandled-conflict'));
    final nextButton =
        find.byKey(const ValueKey('merge-editor-next-unhandled-conflict'));
    final acceptInput1Button =
        find.byKey(const ValueKey('merge-editor-accept-input1'));
    final acceptInput2Button =
        find.byKey(const ValueKey('merge-editor-accept-input2'));
    for (final finder in [
      previousButton,
      nextButton,
      acceptInput1Button,
      acceptInput2Button,
    ]) {
      await tester.ensureVisible(finder);
      await tester.tap(finder);
    }

    expect(previous, 1);
    expect(next, 1);
    expect(acceptInput1, 1);
    expect(acceptInput2, 1);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: MergeEditorSurface(
          base: '',
          input1: '',
          input2: '',
          resultEditor: ColoredBox(color: Colors.blueGrey),
          conflicts: [first, second],
          resolutions: {7: AlulaMergeSide.input2},
          unresolvedConflictCount: 2,
          activeConflict: first,
          conflictRangesCurrent: false,
        ),
      ),
    ));
    expect(find.text('Conflict locations are out of date'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(
            const ValueKey('merge-editor-next-unhandled-conflict'),
          ))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('merge-editor-accept-input1')),
          )
          .onPressed,
      isNull,
    );
  });
}
