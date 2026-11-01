/// VS Code editor metadata associated with the most recent plain-text copy.
///
/// Flutter's desktop clipboard channel currently carries plain text only. Keep
/// the small subset needed by the in-process multi-cursor paste path in a
/// bounded sidecar; the system clipboard remains ordinary interoperable text.
class EditorClipboardMetadata {
  const EditorClipboardMetadata({
    this.version = currentVersion,
    this.isFromEmptySelection = false,
    this.multiCursorText,
  });

  static const currentVersion = 1;

  final int version;
  final bool isFromEmptySelection;
  final List<String>? multiCursorText;
}

/// Retains metadata for one recent editor copy, matching it by exact text.
///
/// Both retained strings and copied segments are capped at 64 Ki UTF-16 code
/// units, and the segment list is capped at 10,000 entries. A clipboard update
/// outside those bounds drops the sidecar metadata and keeps plain-text paste
/// available.
class EditorClipboardMetadataStore {
  EditorClipboardMetadataStore._();

  static final shared = EditorClipboardMetadataStore._();
  static const maxRetainedTextUtf16 = 64 * 1024;
  static const maxMultiCursorSelections = 10000;

  String? _lastCopiedText;
  EditorClipboardMetadata? _lastMetadata;

  bool record(String copiedText, EditorClipboardMetadata metadata) {
    final segments = metadata.multiCursorText;
    if (metadata.version != EditorClipboardMetadata.currentVersion ||
        copiedText.length > maxRetainedTextUtf16 ||
        (segments?.length ?? 0) > maxMultiCursorSelections) {
      clear();
      return false;
    }

    var retainedSegmentUtf16 = 0;
    if (segments != null) {
      for (final segment in segments) {
        if (segment.length > maxRetainedTextUtf16 - retainedSegmentUtf16) {
          clear();
          return false;
        }
        retainedSegmentUtf16 += segment.length;
      }
    }

    _lastCopiedText = copiedText;
    _lastMetadata = EditorClipboardMetadata(
      version: metadata.version,
      isFromEmptySelection: metadata.isFromEmptySelection,
      multiCursorText:
          segments == null ? null : List<String>.unmodifiable(segments),
    );
    return true;
  }

  /// Returns metadata only when the current plain text still matches exactly.
  /// A mismatch invalidates the old sidecar so external clipboard contents can
  /// never inherit stale editor cursor data.
  EditorClipboardMetadata? lookup(String pastedText) {
    if (_lastCopiedText == pastedText) return _lastMetadata;
    clear();
    return null;
  }

  void clear() {
    _lastCopiedText = null;
    _lastMetadata = null;
  }
}
