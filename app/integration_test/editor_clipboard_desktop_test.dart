import 'package:alula_app/editor/clipboard_metadata.dart';
import 'package:alula_app/editor/editor_clipboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:super_clipboard/super_clipboard.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native clipboard round trips text, HTML, and Code-OSS metadata',
      (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final clipboard = SystemClipboard.instance;
    expect(clipboard, isNotNull);

    const text = 'fn main() { println!("clipboard"); }';
    const html =
        '<div style="white-space:pre;"><span style="color:#C586C0;">fn</span> main()</div>';
    await EditorClipboard.write(
      text: text,
      html: html,
      metadata: const EditorClipboardMetadata(
        isFromEmptySelection: false,
        multiCursorText: ['fn main() {', 'println!("clipboard"); }'],
        mode: 'rust',
      ),
    );

    final reader = await clipboard!.read();
    expect(reader.canProvide(Formats.plainText), isTrue);
    expect(await reader.readValue(Formats.plainText), text);
    expect(reader.canProvide(Formats.htmlText), isTrue);
    final clipboardHtml = await reader.readValue(Formats.htmlText);
    expect(clipboardHtml, contains('<div style="white-space:pre;">'));
    expect(clipboardHtml, contains('<span style="color:#C586C0;">fn</span>'));
    expect(
      reader.canProvide(EditorClipboard.vscodeEditorDataFormat),
      isTrue,
      reason: 'Native formats: ${reader.platformFormats.join(', ')}',
    );
    final rawMetadata = await reader.readValue(
      EditorClipboard.vscodeEditorDataFormat,
    );
    final metadata = EditorClipboardMetadata.decodeClipboardJson(rawMetadata!);
    expect(metadata, isNotNull);
    expect(metadata!.mode, 'rust');
    expect(
        metadata.multiCursorText, ['fn main() {', 'println!("clipboard"); }']);
  });
}
