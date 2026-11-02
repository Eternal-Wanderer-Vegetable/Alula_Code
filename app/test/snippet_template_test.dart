import 'package:flutter_test/flutter_test.dart';

import 'package:alula_app/editor/snippet_template.dart';

void main() {
  group('snippetFilenameVariables', () {
    test('uses the filename and removes only its final extension', () {
      expect(
        snippetFilenameVariables('archive.tar.rs'),
        {'TM_FILENAME': 'archive.tar.rs', 'TM_FILENAME_BASE': 'archive.tar'},
      );
      expect(
        snippetFilenameVariables('README'),
        {'TM_FILENAME': 'README', 'TM_FILENAME_BASE': 'README'},
      );
    });

    test('preserves dotfiles and resolves an untitled name to empty', () {
      expect(
        snippetFilenameVariables('.env'),
        {'TM_FILENAME': '.env', 'TM_FILENAME_BASE': '.env'},
      );
      expect(
        snippetFilenameVariables(null),
        {'TM_FILENAME': '', 'TM_FILENAME_BASE': ''},
      );
    });
  });

  group('snippetDocumentPathVariables', () {
    test('formats nested POSIX paths and tildifies the home directory', () {
      expect(
        snippetDocumentPathVariables(
          '/home/alice/project/src/main.rs',
          windows: false,
          userHome: '/home/alice',
        ),
        {
          'TM_DIRECTORY': '~/project/src',
          'TM_DIRECTORY_BASE': 'src',
          'TM_FILEPATH': '~/project/src/main.rs',
        },
      );
    });

    test('keeps POSIX filesystem-root parent behavior', () {
      expect(
        snippetDocumentPathVariables('/main.rs', windows: false),
        {
          'TM_DIRECTORY': '/',
          'TM_DIRECTORY_BASE': '',
          'TM_FILEPATH': '/main.rs',
        },
      );
    });

    test('normalizes Windows drive paths and lowercases the drive letter', () {
      expect(
        snippetDocumentPathVariables(
          r'C:\workspace\src\..\src\main.rs',
          windows: true,
          userHome: r'C:\Users\Alice',
        ),
        {
          'TM_DIRECTORY': r'c:\workspace\src',
          'TM_DIRECTORY_BASE': 'src',
          'TM_FILEPATH': r'c:\workspace\src\main.rs',
        },
      );
    });

    test('handles Windows drive roots and UNC paths', () {
      expect(
        snippetDocumentPathVariables(r'C:\main.rs', windows: true),
        {
          'TM_DIRECTORY': r'c:\',
          'TM_DIRECTORY_BASE': '',
          'TM_FILEPATH': r'c:\main.rs',
        },
      );
      expect(
        snippetDocumentPathVariables(
          r'\\server\share\src\main.rs',
          windows: true,
        ),
        {
          'TM_DIRECTORY': r'\\server\share\src',
          'TM_DIRECTORY_BASE': 'src',
          'TM_FILEPATH': r'\\server\share\src\main.rs',
        },
      );
    });

    test('returns empty variables for untitled documents', () {
      expect(
        snippetDocumentPathVariables(null, windows: false),
        {
          'TM_DIRECTORY': '',
          'TM_DIRECTORY_BASE': '',
          'TM_FILEPATH': '',
        },
      );
    });
  });

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

    test('expands selected text as literal text without a tabstop', () {
      final expansion = expandSnippetTemplate(
        r'<$TM_SELECTED_TEXT> ${TM_SELECTED_TEXT} \$TM_SELECTED_TEXT ${TM_FILENAME}$0',
        variables: const {'TM_SELECTED_TEXT': '🙂x'},
      );

      expect(expansion.text, r'<🙂x> 🙂x $TM_SELECTED_TEXT ${TM_FILENAME}');
      expect(expansion.tabstopOrder, [0]);
      expect(expansion.rangesFor(0).single.startUtf16, expansion.text.length);
    });

    test('uses an explicitly resolved empty selected-text variable', () {
      final expansion = expandSnippetTemplate(
        r'${TM_SELECTED_TEXT:fallback}',
        variables: const {'TM_SELECTED_TEXT': ''},
      );

      expect(expansion.text, isEmpty);
    });

    test('expands filename variables without turning them into tabstops', () {
      final expansion = expandSnippetTemplate(
        r'$TM_FILENAME ${TM_FILENAME_BASE:fallback}$0',
        variables: {
          ...snippetFilenameVariables('archive.tar.rs'),
        },
      );

      expect(expansion.text, 'archive.tar.rs archive.tar');
      expect(expansion.tabstopOrder, [0]);
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
        () => expandSnippetTemplate(r'${TM_SELECTED_TEXT/(.*)/$1/}'),
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
