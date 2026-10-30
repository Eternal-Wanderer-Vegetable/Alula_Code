import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/editor/find_replace.dart';
import 'package:alula_app/editor/editor_minimap.dart';
import 'package:alula_app/editor/editor_minimap_markers.dart';
import 'package:alula_app/editor/editor_minimap_syntax.dart';
import 'package:alula_app/editor/rust_text_input_window.dart';
import 'package:alula_app/search/search_service.dart';
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
  test('minimap syntax ranges clip by Rust sample offsets and UTF-16 units',
      () {
    const sample = DocumentMinimapSample(
      version: 4,
      totalUtf16Length: 13,
      lineCount: 2,
      lines: [
        DocumentMinimapLineSample(
          line: 0,
          startUtf16: 0,
          utf16Length: 6,
          text: '\uFEFF🦊 fn',
        ),
        DocumentMinimapLineSample(
          line: 1,
          startUtf16: 8,
          utf16Length: 5,
          text: 'let x',
        ),
      ],
    );
    final segments = buildEditorMinimapSyntaxSegments(
      sample: sample,
      tokenVersion: 4,
      tokens: [
        {'start_utf16': 4, 'end_utf16': 6, 'kind': 'keyword'},
        {'start_utf16': 8, 'end_utf16': 11, 'kind': 'keyword'},
        {'start_utf16': 12, 'end_utf16': 13, 'kind': 'variable'},
      ],
      colorForKind: (kind) => switch (kind) {
        'keyword' => const Color(0xFFC586C0),
        _ => const Color(0xFF9CDCFE),
      },
    );

    expect(
      segments,
      [
        const EditorMinimapSyntaxSegment(
          line: 0,
          startUtf16: 4,
          endUtf16: 6,
          color: Color(0xFFC586C0),
        ),
        const EditorMinimapSyntaxSegment(
          line: 1,
          startUtf16: 0,
          endUtf16: 3,
          color: Color(0xFFC586C0),
        ),
        const EditorMinimapSyntaxSegment(
          line: 1,
          startUtf16: 4,
          endUtf16: 5,
          color: Color(0xFF9CDCFE),
        ),
      ],
    );
    expect(
      buildEditorMinimapSyntaxSegments(
        sample: sample,
        tokenVersion: 3,
        tokens: [
          {'start_utf16': 4, 'end_utf16': 6, 'kind': 'keyword'},
        ],
        colorForKind: (_) => const Color(0xFFC586C0),
      ),
      isEmpty,
    );
  });

  test('minimap syntax paint commands have a strict global cap', () {
    final lines = List.generate(
      maxDocMinimapSampleLines,
      (index) => DocumentMinimapLineSample(
        line: index,
        startUtf16: index * 49,
        utf16Length: 48,
        text: 'x' * 48,
      ),
      growable: false,
    );
    final sample = DocumentMinimapSample(
      version: 8,
      totalUtf16Length: 512 * 49 - 1,
      lineCount: 512,
      lines: lines,
    );
    final tokens = List.generate(512 * 48, (index) {
      final line = index ~/ 48;
      final column = index % 48;
      final start = line * 49 + column;
      return <String, Object?>{
        'start_utf16': start,
        'end_utf16': start + 1,
        'kind': column.isEven ? 'a' : 'b',
      };
    }, growable: false);

    final segments = buildEditorMinimapSyntaxSegments(
      sample: sample,
      tokens: tokens,
      tokenVersion: sample.version,
      colorForKind: (kind) =>
          kind == 'a' ? const Color(0xFFC586C0) : const Color(0xFF9CDCFE),
    );

    expect(segments, hasLength(maxEditorMinimapSyntaxSegments));
    expect(segments.first.line, 0);
    expect(segments.last.line, maxDocMinimapSampleLines - 1);
  });

  test('find overview markers map UTF-16 hits to sampled logical lines', () {
    const text = '\uFEFF🦊 fox\r\nnone\nfox';
    final matches = findMatches(text, 'fox');
    final lines = buildEditorMinimapFindLines(text, matches);

    expect(lines, [0, 2]);

    final manyLines = List.generate(600, (line) => 'hit $line').join('\n');
    final sampled = buildEditorMinimapFindLines(
      manyLines,
      findMatches(manyLines, 'hit'),
    );
    expect(sampled, hasLength(maxEditorMinimapFindMarkers));
    expect(sampled.first, 0);
    expect(sampled[128], 300);
    expect(sampled.last, 599);
  });

  test('overview markers are versioned, bounded, and use logical lines', () {
    final diagnostics = [
      <String, Object?>{
        '_documentId': 17,
        'documentVersion': 8,
        'severity': 1,
        'line': 3,
      },
      <String, Object?>{
        '_documentId': 17,
        'documentVersion': 7,
        'severity': 2,
        'line': 5,
      },
      <String, Object?>{
        '_documentId': 17,
        'documentVersion': 8,
        'severity': 2,
        'line': 4,
      },
      <String, Object?>{
        '_documentId': 17,
        'documentVersion': 8,
        'severity': 3,
        'line': 5,
      },
      <String, Object?>{
        '_documentId': 17,
        'documentVersion': 8,
        'severity': 4,
        'line': 6,
      },
      <String, Object?>{
        '_documentId': 18,
        'documentVersion': 8,
        'severity': 2,
        'line': 9,
      },
      <String, Object?>{
        '_documentId': 17,
        'documentVersion': 8,
        'severity': 2,
        'line': -1,
      },
    ];

    final minimapMarkers = buildEditorMinimapMarkers(
      documentId: 17,
      documentVersion: 8,
      diagnostics: diagnostics,
      selectedSearchDocumentId: 17,
      selectedSearchDocumentVersion: 8,
      selectedSearchHit: const SearchHit(
        path: 'src/main.rs',
        line: 21,
        lineText: 'needle',
      ),
      enabled: true,
      maxMarkers: 1,
    );

    expect(minimapMarkers, hasLength(1));
    expect(minimapMarkers.single.kind, EditorMinimapMarkerKind.search);
    expect(minimapMarkers.single.line, 20);
    expect(
      buildEditorMinimapMarkers(
        documentId: 17,
        documentVersion: 8,
        diagnostics: diagnostics,
        selectedSearchDocumentId: 17,
        selectedSearchDocumentVersion: 8,
        selectedSearchHit: const SearchHit(
          path: 'src/main.rs',
          line: 21,
          lineText: 'needle',
        ),
        enabled: false,
      ),
      isEmpty,
    );
    final diagnosticMarkers = buildEditorMinimapMarkers(
      documentId: 17,
      documentVersion: 8,
      diagnostics: diagnostics,
      selectedSearchDocumentId: null,
      selectedSearchDocumentVersion: null,
      selectedSearchHit: null,
      enabled: true,
    );
    expect(diagnosticMarkers, hasLength(4));
    expect(
      diagnosticMarkers.map((marker) => marker.kind),
      [
        EditorMinimapMarkerKind.error,
        EditorMinimapMarkerKind.warning,
        EditorMinimapMarkerKind.information,
        EditorMinimapMarkerKind.hint,
      ],
    );
    expect(diagnosticMarkers.map((marker) => marker.line), [3, 4, 5, 6]);
    final withFindMarkers = buildEditorMinimapMarkers(
      documentId: 17,
      documentVersion: 8,
      diagnostics: diagnostics,
      selectedSearchDocumentId: 17,
      selectedSearchDocumentVersion: 8,
      selectedSearchHit: const SearchHit(
        path: 'src/main.rs',
        line: 21,
        lineText: 'needle',
      ),
      findMatchLines: [1, 7, 12],
      findMatchesDocumentId: 17,
      findMatchesDocumentVersion: 8,
      enabled: true,
    );
    expect(withFindMarkers, hasLength(8));
    expect(
      withFindMarkers
          .where((marker) => marker.kind == EditorMinimapMarkerKind.find)
          .map((marker) => marker.line),
      [1, 7, 12],
    );
    expect(withFindMarkers.last.kind, EditorMinimapMarkerKind.search);
    final staleFindMarkers = buildEditorMinimapMarkers(
      documentId: 17,
      documentVersion: 8,
      diagnostics: const [],
      selectedSearchDocumentId: null,
      selectedSearchDocumentVersion: null,
      selectedSearchHit: null,
      findMatchLines: [1, 7, 12],
      findMatchesDocumentId: 17,
      findMatchesDocumentVersion: 7,
      enabled: true,
    );
    expect(
      staleFindMarkers.where(
        (marker) => marker.kind == EditorMinimapMarkerKind.find,
      ),
      isEmpty,
    );

    final boundedMarkers = buildEditorMinimapMarkers(
      documentId: 17,
      documentVersion: 8,
      diagnostics: List.generate(
        600,
        (line) => <String, Object?>{
          '_documentId': 17,
          'documentVersion': 8,
          'severity': 1,
          'line': line,
        },
      ),
      selectedSearchDocumentId: null,
      selectedSearchDocumentVersion: null,
      selectedSearchHit: null,
      enabled: true,
    );
    expect(boundedMarkers, hasLength(maxEditorMinimapMarkers));
    final combinedBound = buildEditorMinimapMarkers(
      documentId: 17,
      documentVersion: 8,
      diagnostics: List.generate(
        600,
        (line) => <String, Object?>{
          '_documentId': 17,
          'documentVersion': 8,
          'severity': 1,
          'line': line,
        },
      ),
      selectedSearchDocumentId: 17,
      selectedSearchDocumentVersion: 8,
      selectedSearchHit: const SearchHit(
        path: 'src/main.rs',
        line: 21,
        lineText: 'needle',
      ),
      findMatchLines: List.generate(300, (line) => line),
      findMatchesDocumentId: 17,
      findMatchesDocumentVersion: 8,
      enabled: true,
    );
    expect(combinedBound, hasLength(maxEditorMinimapMarkers));
    expect(
      combinedBound
          .where((marker) => marker.kind == EditorMinimapMarkerKind.find),
      hasLength(maxEditorMinimapFindMarkers),
    );
    expect(combinedBound.last.kind, EditorMinimapMarkerKind.search);
    expect(
      projectEditorMinimapMarkerY(line: 0, lineCount: 10, height: 90),
      0,
    );
    expect(
      projectEditorMinimapMarkerY(line: 9, lineCount: 10, height: 90),
      90,
    );
  });

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

    Widget buildMinimap({
      List<Map<String, Object?>> syntaxTokens = const [],
      List<EditorMinimapMarker> overviewMarkers = const [],
    }) =>
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: EditorMinimap(
                inputWindow: window,
                scrollController: scrollController,
                syntaxDocumentId: doc.id,
                syntaxTokens: syntaxTokens,
                syntaxVersion: doc.version,
                syntaxEnabled: true,
                syntaxTokenColor: (_) => const Color(0xFFC586C0),
                overviewMarkers: overviewMarkers,
                onNavigateToLine: (line) => navigatedLine = line,
              ),
            ),
          ),
        );

    await tester.pumpWidget(
      buildMinimap(
        syntaxTokens: const [
          {'start_utf16': 0, 'end_utf16': 4, 'kind': 'keyword'},
        ],
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

    CustomPainter minimapPainter() => tester
        .widget<CustomPaint>(
          find.descendant(of: minimap, matching: find.byType(CustomPaint)),
        )
        .painter!;
    final previousPainter = minimapPainter();
    await tester.pumpWidget(buildMinimap());
    expect(minimapPainter().shouldRepaint(previousPainter), isTrue);

    final plainPainter = minimapPainter();
    await tester.pumpWidget(
      buildMinimap(
        overviewMarkers: [
          EditorMinimapMarker(
            documentId: doc.id,
            documentVersion: doc.version,
            line: 900,
            kind: EditorMinimapMarkerKind.error,
          ),
        ],
      ),
    );
    expect(minimapPainter().shouldRepaint(plainPainter), isTrue);
  }, skip: _bootstrap.skip != null);
}
