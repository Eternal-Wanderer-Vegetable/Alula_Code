import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/editor/editor_minimap.dart';
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
  test('minimap viewport projection is bounded and tracks the input window',
      () {
    final first = projectEditorMinimapViewport(
      documentLineCount: 10000,
      inputWindowFirstLine: 400,
      inputWindowLineCount: 200,
      scrollOffset: 0,
      maxScrollExtent: 1000,
      viewportHeight: 210,
    );
    final last = projectEditorMinimapViewport(
      documentLineCount: 10000,
      inputWindowFirstLine: 400,
      inputWindowLineCount: 200,
      scrollOffset: 1000,
      maxScrollExtent: 1000,
      viewportHeight: 210,
    );
    final tail = projectEditorMinimapViewport(
      documentLineCount: 100,
      inputWindowFirstLine: 95,
      inputWindowLineCount: 20,
      scrollOffset: 0,
      maxScrollExtent: 0,
      viewportHeight: 210,
    );

    expect(first.firstLine, 400);
    expect(first.lineCount, 10);
    expect(last.firstLine, 590);
    expect(last.lineCount, 10);
    expect(tail.firstLine, 95);
    expect(tail.lineCount, 5);
  });

  testWidgets('minimap paints the Rust overview and navigates by absolute line',
      (tester) async {
    final doc = _bootstrap.core!.openDoc(
      96501,
      List.generate(1200, (line) => 'line $line  🦊').join('\n'),
    );
    addTearDown(doc.close);
    final window = RustTextInputWindow.openAround(
      doc,
      selectionUtf16: 0,
      maxWindowUtf16: 2048,
    );
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    var navigatedLine = -1;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: EditorMinimap(
              inputWindow: window,
              scrollController: scrollController,
              onNavigateToLine: (line) => navigatedLine = line,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    final minimap = find.byKey(const ValueKey<String>('editor-minimap'));
    expect(minimap, findsOneWidget);
    expect(
      find.bySemanticsLabel('代码缩略图，共 1200 行，点击或拖动跳转'),
      findsOneWidget,
    );
    final rect = tester.getRect(minimap);
    await tester.tapAt(Offset(rect.center.dx, rect.top + rect.height * 0.75));

    expect(navigatedLine, 900);
    expect(doc.readMinimapSample().lines, hasLength(512));
  }, skip: _bootstrap.skip != null);
}
