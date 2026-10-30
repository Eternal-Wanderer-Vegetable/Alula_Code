import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/editor/editor_sticky_scroll.dart';
import 'package:alula_app/editor/rust_text_input_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Bootstrap {
  _Bootstrap() {
    try {
      core = AlulaCore.load();
    } catch (error) {
      skip = 'alula_core is unavailable; build it first ($error)';
    }
  }

  AlulaCore? core;
  String? skip;
}

final _bootstrap = _Bootstrap();

void main() {
  test('sticky scopes use inclusive end lines and keep the nearest five', () {
    final symbols = [
      const EditorStickySymbol(
        kind: 'function',
        name: 'outer',
        startUtf16: 0,
        line: 1,
        endLine: 20,
      ),
      const EditorStickySymbol(
        kind: 'impl',
        name: 'Thing',
        startUtf16: 10,
        line: 2,
        endLine: 18,
      ),
      const EditorStickySymbol(
        kind: 'function',
        name: 'finished',
        startUtf16: 20,
        line: 3,
        endLine: 5,
      ),
      const EditorStickySymbol(
        kind: 'function',
        name: 'inner',
        startUtf16: 30,
        line: 6,
        endLine: 17,
      ),
      const EditorStickySymbol(
        kind: 'const',
        name: 'VALUE',
        startUtf16: 40,
        line: 7,
        endLine: 15,
      ),
    ];

    expect(
      buildEditorStickyScrollScopes(
        symbols: symbols,
        firstVisibleLine: 9,
        maxScopes: 2,
      ).map((symbol) => symbol.name),
      ['Thing', 'inner'],
    );
    expect(
      buildEditorStickyScrollScopes(
        symbols: symbols,
        firstVisibleLine: 19,
      ).map((symbol) => symbol.name),
      ['outer'],
    );
    expect(
      buildEditorStickyScrollScopes(
        symbols: symbols,
        firstVisibleLine: 0,
      ),
      isEmpty,
    );
  });

  test('symbol JSON must include a valid end line', () {
    expect(
      EditorStickySymbol.fromMap({
        'kind': 'function',
        'name': 'ok',
        'start_utf16': 4,
        'line': 2,
        'end_line': 4,
      }),
      const EditorStickySymbol(
        kind: 'function',
        name: 'ok',
        startUtf16: 4,
        line: 2,
        endLine: 4,
      ),
    );
    expect(
      EditorStickySymbol.fromMap({
        'kind': 'function',
        'name': 'stale-abi',
        'start_utf16': 4,
        'line': 2,
      }),
      isNull,
    );
  });

  testWidgets('sticky headers follow scrolling and jump to scope start',
      (tester) async {
    final core = _bootstrap.core!;
    const source =
        'fn outer() {\n  fn inner() {\n    let x = 1;\n  }\n}\n';
    final doc = core.openDoc(9201, source);
    final window = RustTextInputWindow.open(doc, startUtf16: 0);
    final controller = ScrollController();
    final selectedOffsets = <int>[];
    addTearDown(() {
      controller.dispose();
      doc.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 64,
            child: EditorStickyScroll(
              document: doc,
              inputWindow: window,
              scrollController: controller,
              onSelectSymbol: selectedOffsets.add,
              child: SingleChildScrollView(
                key: const ValueKey('sticky-test-scroll'),
                controller: controller,
                child: const SizedBox(height: 420),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.drag(
      find.byKey(const ValueKey('sticky-test-scroll')),
      const Offset(0, -300),
    );
    await tester.pump();

    expect(find.text('outer'), findsOneWidget);
    expect(find.text('inner'), findsOneWidget);
    await tester.tap(find.text('inner'));
    expect(selectedOffsets, [source.indexOf('fn inner')]);
  }, skip: _bootstrap.skip != null);
}
