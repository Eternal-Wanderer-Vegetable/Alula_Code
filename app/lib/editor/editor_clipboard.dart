import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';

import 'clipboard_metadata.dart';
import 'paste_as.dart'
    show
        maxPasteAsPlainTextUtf16,
        maxPasteAsUriCount,
        maxPasteAsUriListUtf16,
        parsePasteAsUriList;
import 'rich_text_clipboard.dart' show maxClipboardHtmlUtf16;

/// Clipboard snapshot used by editor paste commands.
class EditorClipboardPayload {
  const EditorClipboardPayload({required this.text, this.metadata});

  final String text;
  final EditorClipboardMetadata? metadata;
}

/// Multi-MIME snapshot used only by Paste As provider resolution.
class EditorPasteAsPayload {
  const EditorPasteAsPayload({
    required this.text,
    this.containsPlainText = true,
    this.metadata,
    this.html,
    this.uriList,
  });

  final String text;
  final bool containsPlainText;
  final EditorClipboardMetadata? metadata;
  final String? html;
  final String? uriList;

  bool get hasPlainText => containsPlainText;

  factory EditorPasteAsPayload.fromPlainText(EditorClipboardPayload payload) =>
      EditorPasteAsPayload(text: payload.text, metadata: payload.metadata);
}

/// Writes the interoperable text, optional rich HTML, and Code-OSS metadata.
///
/// Native rich formats are used when the desktop clipboard plugin is present.
/// Flutter's built-in channel remains a plain-text fallback so widget tests and
/// unsupported runners keep the existing copy/paste path.
class EditorClipboard {
  EditorClipboard._();

  static const _nativeClipboardTimeout = Duration(seconds: 2);
  static const _maxEditorDataBytes = 1024 * 1024;
  static bool _nativeClipboardDisabled = false;

  /// Lets widget tests keep using the mocked Flutter clipboard channel.
  ///
  /// Native clipboard interoperability is covered separately by the desktop
  /// integration smoke, where the real system clipboard is available.
  @visibleForTesting
  static bool forceFlutterClipboardFallbackForTesting = false;

  /// Supplies deterministic multi-MIME snapshots to workbench widget tests.
  @visibleForTesting
  static Future<EditorPasteAsPayload?> Function()?
      readForPasteAsOverrideForTesting;

  static const _vscodeEditorDataCodec = SimplePlatformCodec<String>(
    formats: ['vscode-editor-data'],
    onDecode: _decodeVscodeEditorData,
  );
  static const _windowsVscodeEditorDataCodec = SimplePlatformCodec<String>(
    formats: ['vscode-editor-data'],
    onEncode: _encodeWindowsVscodeEditorData,
    onDecode: _decodeVscodeEditorData,
  );
  static const _macVscodeEditorDataCodec = SimplePlatformCodec<String>(
    // AppKit only retains registered, reverse-DNS pasteboard types. Keep the
    // Code-OSS MIME as the first candidate for Electron-based peers, and add
    // an AppKit-valid equivalent for native pasteboard round trips.
    formats: [
      'vscode-editor-data',
      'com.microsoft.vscode-editor-data',
    ],
    onDecode: _decodeVscodeEditorData,
  );

  static const vscodeEditorDataFormat = SimpleValueFormat<String>(
    linux: _vscodeEditorDataCodec,
    macos: _macVscodeEditorDataCodec,
    windows: _windowsVscodeEditorDataCodec,
    fallback: _vscodeEditorDataCodec,
  );

  static const uriListFormat = SimpleValueFormat<String>(
    linux: SimplePlatformCodec<String>(
      formats: ['text/uri-list'],
      onDecode: _decodeUriList,
    ),
    macos: SimplePlatformCodec<String>(
      // URI lists can contain multiple entries, while AppKit's URL UTIs
      // represent one URL and percent-escape list separators. Keep this
      // aggregate representation as text; native URL pasteboard items are
      // read individually by _readNativeUriItems.
      formats: ['public.utf8-plain-text'],
      onDecode: _decodeUriList,
    ),
    windows: SimplePlatformCodec<String>(
      formats: [
        'text/uri-list',
        'UniformResourceLocatorW',
        'UniformResourceLocator'
      ],
      onDecode: _decodeUriList,
    ),
    fallback: SimplePlatformCodec<String>(
      formats: ['text/uri-list'],
      onDecode: _decodeUriList,
    ),
  );

  static Uint8List _encodeWindowsVscodeEditorData(
    String value,
    PlatformFormat _,
  ) =>
      Uint8List.fromList(utf8.encode(value));

  static Future<String?> _decodeVscodeEditorData(
    PlatformDataProvider provider,
    PlatformFormat format,
  ) async {
    final data = provider.getData(format);
    final value = await data;
    if (value is String) {
      final normalized = _withoutTrailingNulls(value);
      if (normalized.length <=
          EditorClipboardMetadata.maxClipboardMetadataUtf16) {
        return normalized;
      }
    }
    if (value is Uint8List && value.lengthInBytes <= _maxEditorDataBytes) {
      try {
        final decoded = _decodeClipboardDataBytes(value);
        final normalized = _withoutTrailingNulls(decoded);
        if (normalized.length <=
            EditorClipboardMetadata.maxClipboardMetadataUtf16) {
          return normalized;
        }
        return null;
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  static Future<String?> _decodeUriList(
    PlatformDataProvider provider,
    PlatformFormat format,
  ) async {
    final value = await provider.getData(format);
    if (value is String) {
      final normalized = _withoutTrailingNulls(value);
      return normalized.length <= maxPasteAsUriListUtf16 ? normalized : null;
    }
    if (value is Uint8List && value.lengthInBytes <= 256 * 1024) {
      try {
        final decoded = _withoutTrailingNulls(_decodeClipboardDataBytes(value));
        return decoded.length <= maxPasteAsUriListUtf16 ? decoded : null;
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  static String _decodeClipboardDataBytes(Uint8List value) {
    final isUtf16 = value.length.isEven &&
        value.length >= 2 &&
        ((value[0] == 0xFF && value[1] == 0xFE) ||
            (value[0] == 0xFE && value[1] == 0xFF) ||
            value[0] == 0 ||
            value[1] == 0);
    if (!isUtf16) return utf8.decode(value);

    final hasLittleEndianBom = value[0] == 0xFF && value[1] == 0xFE;
    final hasBigEndianBom = value[0] == 0xFE && value[1] == 0xFF;
    final littleEndian =
        hasLittleEndianBom || (!hasBigEndianBom && value[0] != 0);
    var offset = hasLittleEndianBom || hasBigEndianBom ? 2 : 0;
    final codeUnits = <int>[];
    while (offset < value.length) {
      final first = value[offset++];
      final second = value[offset++];
      codeUnits
          .add(littleEndian ? first | (second << 8) : (first << 8) | second);
    }
    return String.fromCharCodes(codeUnits);
  }

  static String _withoutTrailingNulls(String value) {
    var end = value.length;
    while (end > 0 && value.codeUnitAt(end - 1) == 0) {
      end--;
    }
    return end == value.length ? value : value.substring(0, end);
  }

  static Future<void> write({
    required String text,
    required EditorClipboardMetadata metadata,
    String? html,
  }) async {
    var wroteNativeClipboard = false;
    if (!_nativeClipboardDisabled && !forceFlutterClipboardFallbackForTesting) {
      try {
        final clipboard = SystemClipboard.instance;
        if (clipboard != null) {
          final item = DataWriterItem();
          item.add(Formats.plainText(text));
          if (html != null) item.add(Formats.htmlText(html));
          item.add(
            vscodeEditorDataFormat(jsonEncode(metadata.toClipboardJson())),
          );
          await clipboard.write([item]).timeout(_nativeClipboardTimeout);
          wroteNativeClipboard = true;
        }
      } on Object {
        // A stalled Linux display server must not retain a pending call per copy.
        _nativeClipboardDisabled = true;
      }
    }

    if (!wroteNativeClipboard) {
      await Clipboard.setData(ClipboardData(text: text));
    }
    EditorClipboardMetadataStore.shared.record(text, metadata);
  }

  static Future<EditorClipboardPayload?> read() async {
    final payload = await _readSnapshot(includeOptionalFormats: false);
    return payload?.hasPlainText == true
        ? EditorClipboardPayload(
            text: payload!.text, metadata: payload.metadata)
        : null;
  }

  /// Reads the bounded native MIME snapshot used by explicit Paste As actions.
  /// Plain text remains optional so an HTML-only or URI-only clipboard can be
  /// offered by its matching provider without becoming the ordinary paste.
  static Future<EditorPasteAsPayload?> readForPasteAs() {
    final override = readForPasteAsOverrideForTesting;
    return override != null
        ? override()
        : _readSnapshot(includeOptionalFormats: true);
  }

  static Future<EditorPasteAsPayload?> _readSnapshot({
    required bool includeOptionalFormats,
  }) async {
    String? text;
    String? html;
    String? uriList;
    String? rawEditorData;
    if (!_nativeClipboardDisabled && !forceFlutterClipboardFallbackForTesting) {
      try {
        final clipboard = SystemClipboard.instance;
        if (clipboard != null) {
          final reader =
              await clipboard.read().timeout(_nativeClipboardTimeout);
          if (reader.canProvide(Formats.plainText)) {
            text = await reader
                .readValue(Formats.plainText)
                .timeout(_nativeClipboardTimeout);
          }
          if (includeOptionalFormats && reader.canProvide(Formats.htmlText)) {
            final value = await reader
                .readValue(Formats.htmlText)
                .timeout(_nativeClipboardTimeout);
            if (value != null && value.length <= maxClipboardHtmlUtf16) {
              html = value;
            }
          }
          if (includeOptionalFormats && reader.canProvide(uriListFormat)) {
            uriList = await reader
                .readValue(uriListFormat)
                .timeout(_nativeClipboardTimeout);
          }
          if (includeOptionalFormats) {
            final nativeUriItems = await _readNativeUriItems(reader)
                .timeout(_nativeClipboardTimeout);
            if (uriList == null) {
              uriList = nativeUriItems;
            } else {
              final existingUris = parsePasteAsUriList(uriList);
              final itemUris = parsePasteAsUriList(nativeUriItems);
              if (existingUris.isNotEmpty &&
                  itemUris.length > existingUris.length) {
                uriList = nativeUriItems;
              }
            }
          }
          if (reader.canProvide(vscodeEditorDataFormat)) {
            rawEditorData = await reader
                .readValue(vscodeEditorDataFormat)
                .timeout(_nativeClipboardTimeout);
          }
        }
      } on Object {
        _nativeClipboardDisabled = true;
      }
    }

    if (includeOptionalFormats &&
        text != null &&
        text.length > maxPasteAsPlainTextUtf16) {
      text = null;
    }
    text ??= (await Clipboard.getData('text/plain'))?.text;
    if (!includeOptionalFormats && text != null) {
      return EditorPasteAsPayload(
        text: text,
        containsPlainText: true,
        metadata: EditorClipboardMetadataStore.shared.lookup(text),
      );
    }
    if (includeOptionalFormats &&
        text != null &&
        text.length > maxPasteAsPlainTextUtf16) {
      text = null;
    }
    if (text == null && html == null && uriList == null) return null;

    final localMetadata =
        text == null ? null : EditorClipboardMetadataStore.shared.lookup(text);
    final nativeMetadata = rawEditorData == null
        ? null
        : EditorClipboardMetadata.decodeClipboardJson(rawEditorData);
    return EditorPasteAsPayload(
      text: text ?? '',
      containsPlainText: text != null,
      metadata: nativeMetadata ?? localMetadata,
      html: html,
      uriList: uriList,
    );
  }

  static Future<String?> _readNativeUriItems(ClipboardReader reader) async {
    final values = <String>[];
    for (final item in reader.items.take(maxPasteAsUriCount + 1)) {
      Uri? uri;
      if (item.canProvide(Formats.fileUri)) {
        uri = await item
            .readValue(Formats.fileUri)
            .timeout(_nativeClipboardTimeout);
      }
      if (uri == null && item.canProvide(Formats.uri)) {
        final namedUri =
            await item.readValue(Formats.uri).timeout(_nativeClipboardTimeout);
        uri = namedUri?.uri;
      }
      if (uri != null) {
        values.add(uri.toString());
        if (values.length > maxPasteAsUriCount) return null;
      }
    }
    return values.isEmpty ? null : values.join('\r\n');
  }
}
