import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/editor/lsp_diagnostic_decorations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps current LSP UTF-16 ranges to absolute Rust ranges', () {
    final calls = <int>[];
    final lineOffsets = <int, DocumentLineOffset>{
      0: const DocumentLineOffset(
        version: 7,
        totalUtf16Length: 24,
        lineCount: 2,
        line: 0,
        offsetUtf16: 0,
      ),
      1: const DocumentLineOffset(
        version: 7,
        totalUtf16Length: 24,
        lineCount: 2,
        line: 1,
        offsetUtf16: 10,
      ),
    };

    final decorations = buildLspDiagnosticDecorations(
      diagnostics: [
        {
          'documentVersion': 7,
          'severity': 1,
          'line': 0,
          'character': 3,
          'endLine': 0,
          'endCharacter': 9,
        },
        {
          'documentVersion': 7,
          'severity': 2,
          'line': 0,
          'character': 8,
          'endLine': 1,
          'endCharacter': 2,
        },
      ],
      documentVersion: 7,
      inputWindowVersion: 7,
      windowStartUtf16: 8,
      windowEndUtf16: 15,
      totalUtf16Length: 24,
      documentLineCount: 2,
      firstVisibleLine: 0,
      lastVisibleLine: 1,
      lineOffset: (line) {
        calls.add(line);
        return lineOffsets[line]!;
      },
    );

    expect(decorations, hasLength(2));
    expect(
      decorations.map((item) => (item.startUtf16, item.endUtf16)),
      [(3, 9), (8, 12)],
      reason: 'line columns and absolute offsets use UTF-16, including emoji',
    );
    expect(decorations.first.underlineColor, const Color(0xFFFF5370));
    expect(decorations.last.underlineColor, const Color(0xFFFFC107));
    expect(calls.toSet(), {0, 1});
  });

  test('drops stale, unversioned, empty, malformed, and off-window ranges', () {
    final decorations = buildLspDiagnosticDecorations(
      diagnostics: [
        {
          'documentVersion': 6,
          'severity': 1,
          'line': 0,
          'character': 0,
          'endLine': 0,
          'endCharacter': 1,
        },
        {
          'severity': 1,
          'line': 0,
          'character': 0,
          'endLine': 0,
          'endCharacter': 1,
        },
        {
          'documentVersion': 7,
          'severity': 1,
          'line': 0,
          'character': 1,
          'endLine': 0,
          'endCharacter': 1,
        },
        {
          'documentVersion': 7,
          'severity': 1,
          'line': 3,
          'character': 0,
          'endLine': 3,
          'endCharacter': 2,
        },
        {
          'documentVersion': 7,
          'severity': 1,
          'line': 0,
          'character': 0,
          'endLine': 0,
          'endCharacter': 1,
        },
      ],
      documentVersion: 7,
      inputWindowVersion: 7,
      windowStartUtf16: 10,
      windowEndUtf16: 20,
      totalUtf16Length: 24,
      documentLineCount: 2,
      firstVisibleLine: 1,
      lastVisibleLine: 1,
      lineOffset: (line) => DocumentLineOffset(
        version: 7,
        totalUtf16Length: 24,
        lineCount: 2,
        line: line,
        offsetUtf16: line == 0 ? 0 : 10,
      ),
    );

    expect(decorations, isEmpty);
  });

  test('does not query Rust when the bounded window version is stale', () {
    var queried = false;
    final decorations = buildLspDiagnosticDecorations(
      diagnostics: const [],
      documentVersion: 6,
      inputWindowVersion: 7,
      windowStartUtf16: 0,
      windowEndUtf16: 4,
      totalUtf16Length: 4,
      documentLineCount: 1,
      firstVisibleLine: 0,
      lastVisibleLine: 0,
      lineOffset: (_) {
        queried = true;
        throw StateError('must not query');
      },
    );

    expect(decorations, isEmpty);
    expect(queried, isFalse);
  });
}
