import 'dart:convert';

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
  static const _vscodeEditorDataCodec = SimplePlatformCodec<String>(
    formats: ['vscode-editor-data'],
    onDecode: _decodeVscodeEditorData,
  );

  static const vscodeEditorDataFormat = SimpleValueFormat<String>(
    linux: _vscodeEditorDataCodec,
    macos: _vscodeEditorDataCodec,
    windows: _vscodeEditorDataCodec,
    fallback: _vscodeEditorDataCodec,
  );

  static Future<String?> _decodeVscodeEditorData(
    PlatformDataProvider provider,
    PlatformFormat format,
  ) async {
    final data = provider.getData(format);
    final value = await data;
    if (value is String &&
        value.length <= EditorClipboardMetadata.maxClipboardMetadataUtf16) {
      return value;
    }
    if (value is Uint8List && value.lengthInBytes <= _maxEditorDataBytes) {
      try {
        return utf8.decode(value);
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  static Future<void> write({
    required String text,
    required EditorClipboardMetadata metadata,
    String? html,
  }) async {
    var wroteNativeClipboard = false;
    if (!_nativeClipboardDisabled) {
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
    if (!_nativeClipboardDisabled) {
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
