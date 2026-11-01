import 'dart:convert';

import 'package:alula_app/editor/clipboard_metadata.dart';
import 'package:alula_app/editor/editor_clipboard.dart';
import 'package:alula_app/editor/rich_text_clipboard.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_clipboard/super_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Code-OSS v1 metadata round trips and rejects invalid or oversized data',
      () {
    const metadata = EditorClipboardMetadata(
      isFromEmptySelection: true,
      isBlock: true,
      multiCursorText: ['first\nline', 'second'],
      mode: 'rust',
    );
    final encoded = jsonEncode(metadata.toClipboardJson());
    final decoded = EditorClipboardMetadata.decodeClipboardJson(encoded);

    expect(decoded, isNotNull);
    expect(decoded!.version, EditorClipboardMetadata.currentVersion);
    expect(decoded.id, matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(decoded.isFromEmptySelection, isTrue);
    expect(decoded.isBlock, isTrue);
    expect(decoded.multiCursorText, metadata.multiCursorText);
    expect(decoded.mode, 'rust');
    expect(
      EditorClipboardMetadata.decodeClipboardJson(
        jsonEncode({'version': 2}),
      ),
      isNull,
    );
    expect(
      EditorClipboardMetadata.decodeClipboardJson(
        jsonEncode({
          'version': 1,
          'multicursorText': [List<String>.filled(65537, 'x').join()],
        }),
      ),
      isNull,
    );
    expect(
      EditorClipboardMetadata.decodeClipboardJson(
        List<String>.filled(
          EditorClipboardMetadata.maxClipboardMetadataUtf16 + 1,
          ' ',
        ).join(),
      ),
      isNull,
    );
  });

  test('Code-OSS metadata decoder accepts bounded native UTF-8 bytes',
      () async {
    final codec = EditorClipboard.vscodeEditorDataFormat.codec;
    final raw = jsonEncode(
      const EditorClipboardMetadata(mode: 'rust').toClipboardJson(),
    );
    final bytes = await codec.decode(
      _ClipboardDataProvider(Uint8List.fromList(utf8.encode(raw))),
      'vscode-editor-data',
    );
    final string = await codec.decode(
      _ClipboardDataProvider(raw),
      'vscode-editor-data',
    );
    final oversized = await codec.decode(
      _ClipboardDataProvider(Uint8List(1024 * 1024 + 1)),
      'vscode-editor-data',
    );

    expect(bytes, raw);
    expect(string, raw);
    expect(oversized, isNull);
  });

  test('macOS metadata includes a registered pasteboard type', () {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = previousPlatform;
    });

    expect(
      EditorClipboard.vscodeEditorDataFormat.codec.encodingFormats,
      containsAll([
        'vscode-editor-data',
        'com.microsoft.vscode-editor-data',
      ]),
    );
  });

  test('rich HTML clips exact UTF-16 token ranges and escapes source text', () {
    const source = '😀<&\n';
    final html = buildRichTextClipboardHtml(
      text: source,
      selectionStartUtf16: 8,
      languageId: 'rust',
      tokens: const [
        {'start_utf16': 10, 'end_utf16': 12, 'kind': 'string'},
      ],
      colorForToken: (kind) => kind == 'string' ? '#CE9178' : '#D4D4D4',
    );

    expect(html, contains('😀'));
    expect(html, contains('<span style="color:#CE9178;">&lt;&amp;</span>'));
    expect(html, contains('<br>'));
    expect(html, contains('white-space:pre'));
  });

  test('rich HTML falls back for plaintext, large text, and dense token data',
      () {
    String? build(
      String text, {
      String language = 'rust',
      List<Map<String, Object?>> tokens = const [],
    }) =>
        buildRichTextClipboardHtml(
          text: text,
          selectionStartUtf16: 0,
          languageId: language,
          tokens: tokens,
          colorForToken: (_) => '#D4D4D4',
        );

    expect(build('plain', language: 'plaintext'), isNull);
    expect(
      build(List<String>.filled(maxClipboardHtmlUtf16 + 1, 'x').join()),
      isNull,
    );
    final denseTokens = [
      for (var index = 0; index <= maxClipboardHtmlTokens; index++)
        {
          'start_utf16': index,
          'end_utf16': index + 1,
          'kind': 'keyword',
        },
    ];
    expect(
      build(List<String>.filled(denseTokens.length, 'x').join(),
          tokens: denseTokens),
      isNull,
    );
  });

  test('plain-text Flutter fallback still reads and writes the clipboard',
      () async {
    Map<dynamic, dynamic> clipboard = const {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = Map<dynamic, dynamic>.from(call.arguments as Map);
      }
      if (call.method == 'Clipboard.getData') return clipboard;
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await EditorClipboard.write(
      text: 'fallback text',
      html: '<b>fallback text</b>',
      metadata: const EditorClipboardMetadata(mode: 'rust'),
    );
    final payload = await EditorClipboard.read();

    expect(clipboard['text'], 'fallback text');
    expect(payload?.text, 'fallback text');
    expect(payload?.metadata?.mode, 'rust');
  });
}

class _ClipboardDataProvider implements PlatformDataProvider {
  const _ClipboardDataProvider(this.value);

  final Object? value;

  @override
  List<PlatformFormat> getAllFormats() => const ['vscode-editor-data'];

  @override
  Future<Object?> getData(PlatformFormat format) async => value;
}
