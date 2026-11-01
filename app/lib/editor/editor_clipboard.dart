import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';

import 'clipboard_metadata.dart';

/// Clipboard snapshot used by editor paste commands.
class EditorClipboardPayload {
  const EditorClipboardPayload({required this.text, this.metadata});

  final String text;
  final EditorClipboardMetadata? metadata;
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
    String? text;
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

    text ??= (await Clipboard.getData('text/plain'))?.text;
    if (text == null) return null;

    final localMetadata = EditorClipboardMetadataStore.shared.lookup(text);
    final nativeMetadata = rawEditorData == null
        ? null
        : EditorClipboardMetadata.decodeClipboardJson(rawEditorData);
    return EditorClipboardPayload(
      text: text,
      metadata: nativeMetadata ?? localMetadata,
    );
  }
}
