import 'dart:convert';
import 'dart:math';

/// VS Code editor metadata associated with the most recent plain-text copy.
///
/// Keep the copy state needed by the editor in a bounded sidecar while
/// mirroring the same v1 record to the system clipboard.
class EditorClipboardMetadata {
  const EditorClipboardMetadata({
    this.version = currentVersion,
    this.id,
    this.isFromEmptySelection = false,
    this.isBlock = false,
    this.multiCursorText,
    this.mode,
  });

  static const currentVersion = 1;
  static const maxClipboardMetadataUtf16 = 128 * 1024;

  final int version;
  final String? id;
  final bool isFromEmptySelection;
  final bool isBlock;
  final List<String>? multiCursorText;
  final String? mode;

  /// Matches the v1 shape written by Code-OSS `clipboardUtils.ts`.
  Map<String, Object?> toClipboardJson() => {
        'version': version,
        'id': id ?? _newClipboardMetadataId(),
        'isFromEmptySelection': isFromEmptySelection,
        'isBlock': isBlock,
        'multicursorText': multiCursorText,
        'mode': mode,
      };

  static EditorClipboardMetadata? decodeClipboardJson(String raw) {
    if (raw.length > maxClipboardMetadataUtf16) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic> ||
          value['version'] != currentVersion) {
        return null;
      }
      final id = value['id'];
      final emptySelection = value['isFromEmptySelection'];
      final isBlock = value['isBlock'];
      final mode = value['mode'];
      final rawSegments = value['multicursorText'];
      if ((id != null && id is! String) ||
          (emptySelection != null && emptySelection is! bool) ||
          (isBlock != null && isBlock is! bool) ||
          (mode != null && mode is! String) ||
          (rawSegments != null && rawSegments is! List)) {
        return null;
      }

      List<String>? segments;
      if (rawSegments is List) {
        if (rawSegments.length >
                EditorClipboardMetadataStore.maxMultiCursorSelections ||
            rawSegments.any((segment) => segment is! String)) {
          return null;
        }
        var totalUtf16 = 0;
        segments = <String>[];
        for (final segment in rawSegments.cast<String>()) {
          if (segment.length >
              EditorClipboardMetadataStore.maxRetainedTextUtf16 - totalUtf16) {
            return null;
          }
          totalUtf16 += segment.length;
          segments.add(segment);
        }
      }
      return EditorClipboardMetadata(
        id: id as String?,
        isFromEmptySelection: emptySelection as bool? ?? false,
        isBlock: isBlock as bool? ?? false,
        multiCursorText:
            segments == null ? null : List<String>.unmodifiable(segments),
        mode: mode as String?,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}

String _newClipboardMetadataId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0'));
  final joined = hex.join();
  return '${joined.substring(0, 8)}-${joined.substring(8, 12)}-'
      '${joined.substring(12, 16)}-${joined.substring(16, 20)}-'
      '${joined.substring(20)}';
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
      id: metadata.id,
      isFromEmptySelection: metadata.isFromEmptySelection,
      isBlock: metadata.isBlock,
      multiCursorText:
          segments == null ? null : List<String>.unmodifiable(segments),
      mode: metadata.mode,
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
