import 'dart:io';

import 'package:alula_app/editor/paste_as.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;

void main() {
  group('Paste As providers', () {
    test('orders only available providers by configured preference', () {
      final options = buildPasteAsOptions(
        plainText: 'plain',
        html: '<b>rich</b>',
        uriList: null,
        workspaceRoot: null,
        preferences: const ['html', 'missing', 'text'],
      );

      expect(options.map((option) => option.id), ['html', 'text']);
      expect(options.first.text, '<b>rich</b>');
    });

    test('offers HTML-only and URI-only clipboard snapshots', () {
      expect(
        buildPasteAsOptions(
          plainText: null,
          html: '<p>rich</p>',
          uriList: null,
          workspaceRoot: null,
        ).map((option) => option.id),
        ['html'],
      );
      expect(
        buildPasteAsOptions(
          plainText: 'file fallback',
          html: null,
          uriList: 'https://example.test/a\n',
          workspaceRoot: null,
        ).single.text,
        'https://example.test/a',
      );
    });

    test('URI provider joins multiple items with spaces and ranks by kind', () {
      final options = buildPasteAsOptions(
        plainText: 'ignored plain fallback',
        html: null,
        uriList: 'https://example.test/a\nhttps://example.test/b\n',
        workspaceRoot: null,
        preferences: const ['uri.path.absolute'],
      );

      expect(options, hasLength(1));
      expect(options.single.kind, 'uri.path.absolute');
      expect(
          options.single.text, 'https://example.test/a https://example.test/b');
    });

    test('preferences may match a provider parent kind', () {
      final options = buildPasteAsOptions(
        plainText: 'plain',
        html: '<b>rich</b>',
        uriList: null,
        workspaceRoot: null,
        preferences: const ['text'],
      );

      expect(options.map((option) => option.kind), ['text.plain', 'html']);
    });

    test('converts workspace file URIs to relative paths only when contained',
        () {
      final root = Directory.systemTemp.createTempSync('paste-as-root-');
      addTearDown(() => root.deleteSync(recursive: true));
      final inside = Uri.file(
          '${root.path}${Platform.pathSeparator}src${Platform.pathSeparator}main.rs');
      final outside =
          Uri.file('${root.parent.path}${Platform.pathSeparator}other.rs');

      final relative = buildPasteAsOptions(
        plainText: null,
        html: null,
        uriList: '${inside.toString()}\r\n',
        workspaceRoot: root.path,
      );
      expect(relative.map((option) => option.id), ['uri', 'relativeUri']);
      expect(relative.last.text, 'src/main.rs');

      final escaped = buildPasteAsOptions(
        plainText: null,
        html: null,
        uriList: outside.toString(),
        workspaceRoot: root.path,
      );
      expect(escaped.map((option) => option.id), ['uri']);
    });

    test('rejects malformed and over-limit URI lists without truncating', () {
      expect(parsePasteAsUriList('# comment\n\nhttps://example.test/a'),
          hasLength(1));
      expect(parsePasteAsUriList('/relative/path'), isEmpty);
      expect(
          parsePasteAsUriList(
              List.filled(maxPasteAsUriCount + 1, 'https://example.test/a')
                  .join('\n')),
          isEmpty);
      expect(parsePasteAsUriList('x' * (maxPasteAsUriListUtf16 + 1)), isEmpty);
    });

    test('reads recognized editor Paste As settings with safe defaults', () {
      final config = PasteAsConfiguration.fromSettings({
        'editor.pasteAs.enabled': false,
        'editor.pasteAs.showPasteSelector': 'never',
        'editor.pasteAs.preferences': [
          'uri.path.relative',
          'text.plain',
          'x' * 129,
        ],
      });

      expect(config.enabled, isFalse);
      expect(config.showPasteSelector, 'never');
      expect(config.preferences, ['uri.path.relative', 'text.plain']);
      final defaults = PasteAsConfiguration.fromSettings(const {});
      expect(defaults.enabled, isTrue);
      expect(defaults.showPasteSelector, 'afterPaste');
      expect(defaults.preferences, isEmpty);
    });

    test('binds Paste As to the platform editor shortcut', () {
      expect(
        KeybindingSet.defaultsFor(
            TargetPlatform.windows)['editor.action.pasteAs'],
        'ctrl+shift+v',
      );
      expect(
        KeybindingSet.defaultsFor(
            TargetPlatform.macOS)['editor.action.pasteAs'],
        'cmd+shift+v',
      );
    });
  });
}
