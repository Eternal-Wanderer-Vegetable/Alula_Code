import 'package:flutter_test/flutter_test.dart';

import 'package:alula_app/editor/snippet_template.dart';

void main() {
  group('expandSnippetTemplate', () {
    test('expands defaults, linked tabstops, and the final cursor stop', () {
      final expansion = expandSnippetTemplate(r'let ${1:name} = $1;$0');

      expect(expansion.text, 'let name = name;');
      expect(expansion.tabstopOrder, [1, 0]);
      expect(
        expansion
            .rangesFor(1)
            .map((range) => [range.startUtf16, range.endUtf16]),
        [
          [4, 8],
          [11, 15],
        ],
      );
      expect(expansion.rangesFor(0).single.startUtf16, 16);
      expect(expansion.rangesFor(0).single.lengthUtf16, 0);
    });

    test('uses the first non-empty default for earlier empty mirrors', () {
      final expansion = expandSnippetTemplate(r'$1 ${1:} ${1:value} $1');

      expect(expansion.text, 'value value value value');
      expect(expansion.rangesFor(1), hasLength(4));
    });

    test('uses one value for repeated defaults on the same tabstop', () {
      final expansion = expandSnippetTemplate(r'${1:first} $1 ${1:later}');

      expect(expansion.text, 'first first first');
      expect(expansion.rangesFor(1), hasLength(3));
    });

    test('adds an implicit final cursor stop when omitted', () {
      final expansion = expandSnippetTemplate(r'${1:name}-$1');

      expect(expansion.text, 'name-name');
      expect(expansion.tabstopOrder, [1, 0]);
      expect(expansion.rangesFor(0).single.startUtf16, 9);
    });

    test('keeps UTF-16 offsets across emoji and CRLF', () {
      final expansion = expandSnippetTemplate('🙂\r\n\${1:x} \$1');

      expect(expansion.text, '🙂\r\nx x');
      expect(
          expansion
              .rangesFor(1)
              .map((range) => [range.startUtf16, range.endUtf16]),
          [
            [4, 5],
            [6, 7],
          ]);
    });

    test('unescapes TextMate literal escapes and preserves unknown variables',
        () {
      final expansion = expandSnippetTemplate(
        r'\$x \} \\ ${1:a\}b} $1 ${TM_FILENAME} $TM_FILENAME',
      );

      expect(expansion.text, r'$x } \ a}b a}b ${TM_FILENAME} $TM_FILENAME');
    });

    test('preserves malformed placeholder syntax as literal text', () {
      expect(expandSnippetTemplate(r'${1:unfinished').text, r'${1:unfinished');
      expect(expandSnippetTemplate(r'$x').text, r'$x');
    });

    test('rejects unsupported nested, choice, and transform syntax', () {
      expect(
        () => expandSnippetTemplate(r'${1|one,two|}'),
        throwsA(isA<SnippetTemplateException>()),
      );
      expect(
        () => expandSnippetTemplate(r'${1/([a-z]+)/$1/g}'),
        throwsA(isA<SnippetTemplateException>()),
      );
      expect(
        () => expandSnippetTemplate(r'${1:${2:nested}}'),
        throwsA(isA<SnippetTemplateException>()),
      );
    });

    test('bounds template size, expansion size, placeholder count, and indices',
        () {
      expect(
        () => expandSnippetTemplate('1234', maxTemplateUtf16: 3),
        throwsA(isA<SnippetTemplateException>()),
      );
      expect(
        () => expandSnippetTemplate(r'${1:long}$1', maxExpandedUtf16: 5),
        throwsA(isA<SnippetTemplateException>()),
      );
      expect(
        () => expandSnippetTemplate(r'${1:x}$1', maxPlaceholderOccurrences: 1),
        throwsA(isA<SnippetTemplateException>()),
      );
      expect(
        () => expandSnippetTemplate(r'$10', maxTabstopIndex: 9),
        throwsA(isA<SnippetTemplateException>()),
      );
    });
  });
}
