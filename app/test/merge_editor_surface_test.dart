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
}
