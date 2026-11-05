import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/editor/editor_rendering.dart';
import 'package:alula_app/editor/workspace_search_decorations.dart';
import 'package:alula_app/search/search_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildWorkspaceSearchDecorations', () {
    test('maps exact match ranges through Rust line offsets', () {
      const hit = SearchHit(
        path: 'src/main.rs',
        line: 2,
        lineText: '😀 foo foo',
        matchRanges: [
          SearchHitRange(startUtf16: 3, endUtf16: 6),
          SearchHitRange(startUtf16: 7, endUtf16: 10),
        ],
      );
      final decorations = buildWorkspaceSearchDecorations(
        hit: hit,
        documentVersion: 8,
        inputWindowVersion: 8,
        windowStartUtf16: 0,
        windowEndUtf16: 32,
        totalUtf16Length: 32,
        documentLineCount: 3,
        firstVisibleLine: 0,
        lastVisibleLine: 2,
        lineOffset: (line) => DocumentLineOffset(
          version: 8,
          totalUtf16Length: 32,
          lineCount: 3,
          line: line,
          offsetUtf16: 12,
        ),
      );

      expect(
        decorations
            .map((decoration) => (decoration.startUtf16, decoration.endUtf16))
            .toList(),
        [(15, 18), (19, 22)],
      );
    });

    test('git grep fallback marks the matching line', () {
      const hit = SearchHit(
        path: 'src/main.rs',
        line: 1,
        lineText: 'matched row',
      );
      final decorations = buildWorkspaceSearchDecorations(
        hit: hit,
        documentVersion: 2,
        inputWindowVersion: 2,
        windowStartUtf16: 0,
        windowEndUtf16: 20,
        totalUtf16Length: 20,
        documentLineCount: 1,
        firstVisibleLine: 0,
        lastVisibleLine: 0,
        lineOffset: (line) => const DocumentLineOffset(
          version: 2,
          totalUtf16Length: 20,
          lineCount: 1,
          line: 0,
          offsetUtf16: 0,
        ),
      );

      expect(decorations, hasLength(1));
      expect(decorations.single.startUtf16, 0);
      expect(decorations.single.endUtf16, hit.lineText.length);
    });

    test('rejects stale versions, invalid offsets and off-window rows', () {
      const hit = SearchHit(
        path: 'src/main.rs',
        line: 2,
        lineText: 'match',
        matchRanges: [SearchHitRange(startUtf16: 0, endUtf16: 5)],
      );
      List<EditorRangeDecoration> build({
        int documentVersion = 3,
        int inputWindowVersion = 3,
        int firstVisibleLine = 0,
        int lastVisibleLine = 1,
        int lineVersion = 3,
      }) =>
          buildWorkspaceSearchDecorations(
            hit: hit,
            documentVersion: documentVersion,
            inputWindowVersion: inputWindowVersion,
            windowStartUtf16: 0,
            windowEndUtf16: 20,
            totalUtf16Length: 20,
            documentLineCount: 2,
            firstVisibleLine: firstVisibleLine,
            lastVisibleLine: lastVisibleLine,
            lineOffset: (line) => DocumentLineOffset(
              version: lineVersion,
              totalUtf16Length: 20,
              lineCount: 2,
              line: line,
              offsetUtf16: 8,
            ),
          );

      expect(build(inputWindowVersion: 4), isEmpty);
      expect(build(lineVersion: 4), isEmpty);
      expect(build(firstVisibleLine: 2, lastVisibleLine: 2), isEmpty);
    });
  });
}
