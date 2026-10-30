import 'package:alula_app/editor/editor_highlight_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const semantic = <Map<String, Object?>>[
    {'start_utf16': 4, 'end_utf16': 8, 'kind': 'function'},
  ];
  const syntax = <Map<String, Object?>>[
    {'start_utf16': 0, 'end_utf16': 2, 'kind': 'keyword'},
  ];

  test('uses semantic tokens only for the current committed document window', () {
    final result = selectEditorHighlightTokens(
      semanticTokens: semantic,
      semanticVersion: 7,
      documentVersion: 7,
      inputWindowVersion: 7,
      hasPendingInput: false,
      fallbackTokens: syntax,
      fallbackVersion: 7,
    );

    expect(result.tokens, same(semantic));
    expect(result.version, 7);
  });

  test('stale or locally pending semantic results use syntax fallback', () {
    final stale = selectEditorHighlightTokens(
      semanticTokens: semantic,
      semanticVersion: 6,
      documentVersion: 7,
      inputWindowVersion: 7,
      hasPendingInput: false,
      fallbackTokens: syntax,
      fallbackVersion: 7,
    );
    final pending = selectEditorHighlightTokens(
      semanticTokens: semantic,
      semanticVersion: 7,
      documentVersion: 7,
      inputWindowVersion: 7,
      hasPendingInput: true,
      fallbackTokens: syntax,
      fallbackVersion: 7,
    );

    expect(stale.tokens, same(syntax));
    expect(stale.version, 7);
    expect(pending.tokens, same(syntax));
    expect(pending.version, 7);
  });
}
