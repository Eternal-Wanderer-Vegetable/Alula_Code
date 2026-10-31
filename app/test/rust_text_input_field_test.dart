import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/editor/multi_selection.dart';
import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/editor/rust_text_input_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _CoreBootstrap {
  _CoreBootstrap() {
    try {
      core = AlulaCore.load();
    } catch (error) {
      skip = 'alula_core is unavailable; build it first ($error)';
    }
  }

  AlulaCore? core;
  String? skip;
}

final _bootstrap = _CoreBootstrap();

void main() {
  testWidgets('bounded EditableText registers a positioned native input client',
      (tester) async {
    final doc = _bootstrap.core!.openDoc(9720, 'prefix|text input');
    addTearDown(doc.close);
    final window = RustTextInputWindow.open(
      doc,
      startUtf16: 7,
      maxWindowUtf16: 32,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 28, top: 36),
              child: SizedBox(
                width: 320,
                height: 180,
                child: RustTextInputField(inputWindow: window),
              ),
            ),
          ),
        ),
      ),
    );
    await tester
        .showKeyboard(find.byKey(const ValueKey('rust-bounded-text-input')));
    await tester.pump();

    expect(tester.testTextInput.isVisible, isTrue);
    final geometryCall = tester.testTextInput.log.lastWhere(
      (call) => call.method == 'TextInput.setEditableSizeAndTransform',
    );
    final geometry = geometryCall.arguments as Map<dynamic, dynamic>;
    expect(geometry['width'], greaterThan(0));
    expect(geometry['height'], greaterThan(0));
    final transform = (geometry['transform'] as List<dynamic>)
        .map((value) => (value as num).toDouble())
        .toList();
    expect(transform[12], greaterThan(10));
    expect(transform[13], greaterThan(10));
  }, skip: _bootstrap.skip != null);

  testWidgets('platform text-input composition stays overlay until commit',
      (tester) async {
    final doc = _bootstrap.core!.openDoc(9721, 'root|abc|tail');
    addTearDown(doc.close);
    final window = RustTextInputWindow.open(
      doc,
      startUtf16: 5,
      maxWindowUtf16: 32,
    );
    final fieldKey = GlobalKey<RustTextInputFieldState>();
    final deltas = <RustTextInputDelta>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 200,
            child: RustTextInputField(
              key: fieldKey,
              inputWindow: window,
              onDelta: deltas.add,
            ),
          ),
        ),
      ),
    );
    await tester
        .showKeyboard(find.byKey(const ValueKey('rust-bounded-text-input')));
    await tester.pump();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'ni|tail',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();
    expect(doc.resync().content, 'root|abc|tail');
    expect(window.text, 'abc|tail');
    expect(window.presentedText, 'ni|tail');
    expect(deltas.last.composingWindow, const TextRange(start: 0, end: 2));

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '你好|tail',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange.empty,
      ),
    );
    await tester.pump();
    expect(doc.resync().content, 'root|你好|tail');
    expect(deltas.last.operations.length, 2);
    expect(deltas.last.selection!.baseOffset, 7);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'wo|tail',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();
    expect(doc.resync().content, 'root|你好|tail');
    final cancelled = fieldKey.currentState!.cancelComposition()!;
    expect(cancelled.operations, isEmpty);
    expect(fieldKey.currentState!.editingValue.text, '你好|tail');
    expect(doc.resync().content, 'root|你好|tail');
  }, skip: _bootstrap.skip != null);

  testWidgets('secondary carets commit together through the Rust input window',
      (tester) async {
    final doc = _bootstrap.core!.openDoc(9725, 'abc def');
    addTearDown(doc.close);
    final window = RustTextInputWindow.open(
      doc,
      startUtf16: 0,
      maxWindowUtf16: 32,
      selection: const TextSelection.collapsed(offset: 3),
    );
    final deltas = <RustTextInputDelta>[];
    var secondary = const [TextSelection.collapsed(offset: 7)];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          height: 180,
          child: RustTextInputField(
            inputWindow: window,
            inputFormatter: MultiSelectionTextInputFormatter(
              additionalSelections: () => secondary,
              onSelectionsChanged: (value) => secondary = value,
            ),
            additionalSelections: secondary,
            onDelta: deltas.add,
          ),
        ),
      ),
    ));
    await tester
        .showKeyboard(find.byKey(const ValueKey('rust-bounded-text-input')));
    await tester.pump();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'abcX def',
        selection: TextSelection.collapsed(offset: 4),
      ),
    );
    await tester.pump();

    expect(doc.resync().content, 'abcX defX');
    expect(secondary, const [TextSelection.collapsed(offset: 9)]);
    expect(deltas.last.operations, isNotEmpty);
    expect(deltas.last.operations.length, lessThanOrEqualTo(2));
  }, skip: _bootstrap.skip != null);

  testWidgets('host-generated cut edit is formatted across selected ranges',
      (tester) async {
    final doc = _bootstrap.core!.openDoc(9726, 'red green red');
    addTearDown(doc.close);
    final window = RustTextInputWindow.open(
      doc,
      startUtf16: 0,
      maxWindowUtf16: 32,
      selection: const TextSelection(baseOffset: 0, extentOffset: 3),
    );
    var secondary = const [TextSelection(baseOffset: 10, extentOffset: 13)];
    final fieldKey = GlobalKey<RustTextInputFieldState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          height: 180,
          child: RustTextInputField(
            key: fieldKey,
            inputWindow: window,
            inputFormatter: MultiSelectionTextInputFormatter(
              additionalSelections: () => secondary,
              onSelectionsChanged: (value) => secondary = value,
            ),
          ),
        ),
      ),
    ));

    fieldKey.currentState!.applyFormattedValue(const TextEditingValue(
      text: ' green red',
      selection: TextSelection.collapsed(offset: 0),
    ));
    await tester.pump();

    expect(doc.resync().content, ' green ');
    expect(secondary, const [TextSelection.collapsed(offset: 7)]);
  }, skip: _bootstrap.skip != null);

  testWidgets(
      'Rust accepts multi-caret edits around emoji, combining marks, CRLF',
      (tester) async {
    const source = '🙂\r\ne\u0301 x';
    final doc = _bootstrap.core!.openDoc(9727, source);
    addTearDown(doc.close);
    final window = RustTextInputWindow.open(
      doc,
      startUtf16: 0,
      maxWindowUtf16: 32,
      selection: const TextSelection.collapsed(offset: 2),
    );
    var secondary = const [TextSelection.collapsed(offset: 8)];
    final deltas = <RustTextInputDelta>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          height: 180,
          child: RustTextInputField(
            inputWindow: window,
            inputFormatter: MultiSelectionTextInputFormatter(
              additionalSelections: () => secondary,
              onSelectionsChanged: (value) => secondary = value,
            ),
            onDelta: deltas.add,
          ),
        ),
      ),
    ));
    await tester
        .showKeyboard(find.byKey(const ValueKey('rust-bounded-text-input')));
    await tester.pump();
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: '🙂Z\r\ne\u0301 x',
      selection: TextSelection.collapsed(offset: 3),
    ));
    await tester.pump();
    await tester.pump();

    expect(doc.resync().content, '🙂Z\r\ne\u0301 xZ');
    expect(secondary, const [TextSelection.collapsed(offset: 10)]);
    expect(deltas.last.operations, isNotEmpty);
  }, skip: _bootstrap.skip != null);

  testWidgets('oversized platform update is committed and recentered',
      (tester) async {
    final doc = _bootstrap.core!.openDoc(9722, 'abc');
    addTearDown(doc.close);
    final window = RustTextInputWindow.open(
      doc,
      startUtf16: 0,
      maxWindowUtf16: 4,
    );
    Object? inputError;
    final fieldKey = GlobalKey<RustTextInputFieldState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 200,
            child: RustTextInputField(
              key: fieldKey,
              inputWindow: window,
              onError: (error) => inputError = error,
            ),
          ),
        ),
      ),
    );
    await tester
        .showKeyboard(find.byKey(const ValueKey('rust-bounded-text-input')));
    await tester.pump();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'abcde',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();

    expect(inputError, isNull);
    expect(window.pendingCount, 0);
    expect(window.text.length, lessThanOrEqualTo(window.maxWindowUtf16));
    expect(doc.resync().content, 'abcde');
    expect(fieldKey.currentState!.editingValue.text, window.text);
    expect(find.byKey(const ValueKey('rust-bounded-text-input-error')),
        findsNothing);
  }, skip: _bootstrap.skip != null);

  testWidgets('version-conflicted draft can retry when the window is unchanged',
      (tester) async {
    const source = 'middle text in the bounded window and tail';
    final doc = _bootstrap.core!.openDoc(9723, source);
    addTearDown(doc.close);
    final window = RustTextInputWindow.open(
      doc,
      startUtf16: 0,
      maxWindowUtf16: 24,
    );
    final fieldKey = GlobalKey<RustTextInputFieldState>();
    final deltas = <RustTextInputDelta>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 200,
          child: RustTextInputField(
            key: fieldKey,
            inputWindow: window,
            onDelta: deltas.add,
          ),
        ),
      ),
    ));

    final value = fieldKey.currentState!.editingValue;
    final caret = value.selection.extentOffset;
    fieldKey.currentState!.setEditingValue(value.copyWith(
      text: value.text.replaceRange(caret, caret, 'X'),
      selection: TextSelection.collapsed(offset: caret + 1),
    ));
    doc.apply([const TextOp.insert(source.length, '!')]);
    await tester.pump();
    expect(find.byKey(const ValueKey('rust-bounded-text-input-error')),
        findsOneWidget);
    expect(window.pendingCount, 1);

    await tester.tap(find.text('重试同步'));
    await tester.pump();
    expect(find.byKey(const ValueKey('rust-bounded-text-input-error')),
        findsNothing);
    expect(window.pendingCount, 0);
    expect(doc.resync().content,
        '${source.substring(0, caret)}X${source.substring(caret)}!');
    expect(deltas.last.operations, isNotEmpty);
  }, skip: _bootstrap.skip != null);
}
