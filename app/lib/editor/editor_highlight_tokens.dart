/// Picks current LSP semantic tokens when their snapshot matches the Rust
/// document and bounded input window, otherwise retaining the local parser's
/// syntax tokens as the fallback.
({List<Map<String, Object?>> tokens, int version}) selectEditorHighlightTokens({
  required List<Map<String, Object?>> semanticTokens,
  required int semanticVersion,
  required int documentVersion,
  required int inputWindowVersion,
  required bool hasPendingInput,
  required List<Map<String, Object?>> fallbackTokens,
  required int fallbackVersion,
}) {
  if (semanticTokens.isEmpty ||
      semanticVersion != documentVersion ||
      semanticVersion != inputWindowVersion ||
      hasPendingInput) {
    return (tokens: fallbackTokens, version: fallbackVersion);
  }
  return (tokens: semanticTokens, version: semanticVersion);
}
