import 'package:alula_app/bridge/alula_core.dart';
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

  testWidgets('oversized platform update is restored and reported to the host',
      (tester) async {
    final doc = _bootstrap.core!.openDoc(9722, 'abc');
    addTearDown(doc.close);
    final window = RustTextInputWindow.open(
      doc,
      startUtf16: 0,
      maxWindowUtf16: 4,
    );
    Object? inputError;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 200,
            child: RustTextInputField(
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

    expect(inputError, isA<TextInputWindowLimitException>());
    expect(window.pendingCount, 0);
    expect(window.text, 'abc');
    expect(doc.resync().content, 'abc');
    expect(find.byKey(const ValueKey('rust-bounded-text-input-error')),
        findsOneWidget);
  }, skip: _bootstrap.skip != null);
}
