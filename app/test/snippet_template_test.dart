import 'package:flutter_test/flutter_test.dart';

import 'package:alula_app/editor/snippet_template.dart';
import 'package:alula_app/editor/snippet_variable_transform.dart';

void main() {
  group('snippetFilenameVariables', () {
    test('uses the filename and removes only its final extension', () async {
      expect(
        snippetFilenameVariables('archive.tar.rs'),
        {'TM_FILENAME': 'archive.tar.rs', 'TM_FILENAME_BASE': 'archive.tar'},
      );
      expect(
        snippetFilenameVariables('README'),
        {'TM_FILENAME': 'README', 'TM_FILENAME_BASE': 'README'},
      );
    });

    test('preserves dotfiles and resolves an untitled name to empty', () async {
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
    test('formats nested POSIX paths and tildifies the home directory',
        () async {
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

    test('keeps POSIX filesystem-root parent behavior', () async {
      expect(
        snippetDocumentPathVariables('/main.rs', windows: false),
        {
          'TM_DIRECTORY': '/',
          'TM_DIRECTORY_BASE': '',
          'TM_FILEPATH': '/main.rs',
        },
      );
    });

    test('normalizes Windows drive paths and lowercases the drive letter',
        () async {
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

    test('handles Windows drive roots and UNC paths', () async {
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

    test('returns empty variables for untitled documents', () async {
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

  group('snippetWorkspaceVariables', () {
    test('returns the folder basename and an absolute POSIX path', () async {
      expect(
        snippetWorkspaceVariables('/home/alice/project/..', windows: false),
        {
          'WORKSPACE_NAME': 'alice',
          'WORKSPACE_FOLDER': '/home/alice',
        },
      );
      expect(
        snippetWorkspaceVariables('/home/alice/project', windows: false),
        {
          'WORKSPACE_NAME': 'project',
          'WORKSPACE_FOLDER': '/home/alice/project',
        },
      );
    });

    test('normalizes Windows paths and preserves UNC roots', () async {
      expect(
        snippetWorkspaceVariables(
          r'C:\workspace\project\..',
          windows: true,
        ),
        {
          'WORKSPACE_NAME': 'workspace',
          'WORKSPACE_FOLDER': r'c:\workspace',
        },
      );
      expect(
        snippetWorkspaceVariables(
          r'\\server\share\workspace',
          windows: true,
        ),
        {
          'WORKSPACE_NAME': 'workspace',
          'WORKSPACE_FOLDER': r'\\server\share\workspace',
        },
      );
    });

    test('resolves an unopened workspace to empty strings', () async {
      expect(
        snippetWorkspaceVariables(null, windows: false),
        {
          'WORKSPACE_NAME': '',
          'WORKSPACE_FOLDER': '',
        },
      );
      expect(
        snippetWorkspaceVariables('', windows: true),
        {
          'WORKSPACE_NAME': '',
          'WORKSPACE_FOLDER': '',
        },
      );
    });
  });

  group('snippetClipboardVariables', () {
    test('preserves clipboard text and leaves empty clipboard unresolved',
        () async {
      expect(
        snippetClipboardVariables('copied 🙂\nsecond line'),
        {'CLIPBOARD': 'copied 🙂\nsecond line'},
      );
      expect(snippetClipboardVariables(null), isEmpty);
      expect(snippetClipboardVariables(''), isEmpty);
    });

    test('uses a clipboard variable default only when clipboard text is empty',
        () async {
      expect(
        (await expandSnippetTemplate(
          r'${CLIPBOARD:fallback}|$CLIPBOARD',
          variables: snippetClipboardVariables('value'),
        ))
            .text,
        'value|value',
      );
      expect(
        (await expandSnippetTemplate(
          r'${CLIPBOARD:fallback}|$CLIPBOARD',
          variables: snippetClipboardVariables(''),
        ))
            .text,
        'fallback|',
      );
      expect(
        (await expandSnippetTemplate(
          r'${CLIPBOARD:line\$value}',
          variables: snippetClipboardVariables(null),
        ))
            .text,
        'line\$value',
      );
    });

    test('escaped clipboard references stay literal and are not resolved',
        () async {
      expect(snippetTemplateUsesVariable(r'\$CLIPBOARD', 'CLIPBOARD'), isFalse);
      expect(
        (await expandSnippetTemplate(r'\$CLIPBOARD', variables: const {})).text,
        r'$CLIPBOARD',
      );
    });
  });

  group('snippetRelativeFilePathVariables', () {
    test('returns a workspace relative path without a root prefix', () async {
      expect(
        snippetRelativeFilePathVariables(
          '/home/alice/project/src/main.rs',
          '/home/alice/project',
          windows: false,
          userHome: '/home/alice',
        ),
        {'RELATIVE_FILEPATH': 'src/main.rs'},
      );
    });

    test('returns empty for the workspace root and untitled documents',
        () async {
      expect(
        snippetRelativeFilePathVariables(
          '/workspace',
          '/workspace/',
          windows: false,
        ),
        {'RELATIVE_FILEPATH': ''},
      );
      expect(
        snippetRelativeFilePathVariables(null, '/workspace', windows: false),
        {'RELATIVE_FILEPATH': ''},
      );
    });

    test('uses the absolute label when there is no containing workspace',
        () async {
      expect(
        snippetRelativeFilePathVariables(
          '/home/alice/other/main.rs',
          '/home/alice/project',
          windows: false,
          userHome: '/home/alice',
        ),
        {'RELATIVE_FILEPATH': '~/other/main.rs'},
      );
    });

    test(
        'normalizes Windows relative paths and compares root case-insensitively',
        () async {
      expect(
        snippetRelativeFilePathVariables(
          r'C:\Workspace\src\..\src\main.rs',
          r'c:\workspace',
          windows: true,
          userHome: r'C:\Users\Alice',
        ),
        {'RELATIVE_FILEPATH': r'src\main.rs'},
      );
    });
  });

  group('snippetLineVariables', () {
    test('formats zero-based and one-based line numbers', () async {
      expect(
        snippetLineVariables(0),
        {'TM_LINE_INDEX': '0', 'TM_LINE_NUMBER': '1'},
      );
      expect(
        snippetLineVariables(41),
        {'TM_LINE_INDEX': '41', 'TM_LINE_NUMBER': '42'},
      );
    });

    test('rejects a negative document line', () async {
      expect(() => snippetLineVariables(-1), throwsRangeError);
    });
  });

  group('snippetCurrentLineVariables', () {
    test('keeps the current line verbatim, including empty lines', () async {
      expect(
        snippetCurrentLineVariables(r'  call($TM_FILENAME); 🦊'),
        {'TM_CURRENT_LINE': r'  call($TM_FILENAME); 🦊'},
      );
      expect(snippetCurrentLineVariables(''), {'TM_CURRENT_LINE': ''});
    });
  });

  group('snippetCurrentWordVariables', () {
    test('uses the default word definition at the cursor position', () async {
      expect(
        snippetCurrentWordVariables('alpha.beta -12.5ms', 2),
        {'TM_CURRENT_WORD': 'alpha'},
      );
      expect(
        snippetCurrentWordVariables('alpha.beta -12.5ms', 5),
        {'TM_CURRENT_WORD': 'alpha'},
      );
      expect(
        snippetCurrentWordVariables('alpha.beta -12.5ms', 6),
        {'TM_CURRENT_WORD': 'beta'},
      );
      expect(
        snippetCurrentWordVariables('alpha.beta -12.5ms', 14),
        {'TM_CURRENT_WORD': '-12.5ms'},
      );
    });

    test('uses UTF-16 cursor columns and returns no value off a word',
        () async {
      expect(
        snippetCurrentWordVariables('🙂 value', 4),
        {'TM_CURRENT_WORD': 'value'},
      );
      expect(
        snippetCurrentWordVariables('🙂 value', 2),
        {'TM_CURRENT_WORD': '🙂'},
      );
      expect(snippetCurrentWordVariables('   ', 2), isEmpty);
      expect(
        () => snippetCurrentWordVariables('word', 5),
        throwsRangeError,
      );
    });

    test('bounds long-line lookup to the Code-OSS context window', () async {
      final line = "${'a' * 100}Q${'a' * 1100}";
      final variables = snippetCurrentWordVariables(line, 600);
      expect(variables['TM_CURRENT_WORD'], 'a' * 1000);
    });
  });

  group('snippetTemplateUsesVariable', () {
    test('recognizes plain, braced, and defaulted references', () async {
      expect(
          snippetTemplateUsesVariable(r'$TM_CURRENT_LINE', 'TM_CURRENT_LINE'),
          isTrue);
      expect(
          snippetTemplateUsesVariable(r'${TM_CURRENT_LINE}', 'TM_CURRENT_LINE'),
          isTrue);
      expect(
        snippetTemplateUsesVariable(
            r'${TM_CURRENT_LINE:fallback}', 'TM_CURRENT_LINE'),
        isTrue,
      );
      expect(
        snippetTemplateUsesVariable(r'$TM_CURRENT_WORD', 'TM_CURRENT_WORD'),
        isTrue,
      );
      expect(
        snippetTemplateUsesVariable(
            r'${TM_CURRENT_WORD:fallback}', 'TM_CURRENT_WORD'),
        isTrue,
      );
    });

    test('ignores escaped references, suffixes, and nested default text',
        () async {
      expect(
          snippetTemplateUsesVariable(r'\$TM_CURRENT_LINE', 'TM_CURRENT_LINE'),
          isFalse);
      expect(
          snippetTemplateUsesVariable(
              r'$TM_CURRENT_LINE_SUFFIX', 'TM_CURRENT_LINE'),
          isFalse);
      expect(
        snippetTemplateUsesVariable(
            r'${TM_SELECTED_TEXT:$TM_CURRENT_LINE}', 'TM_CURRENT_LINE'),
        isFalse,
      );
      expect(
        snippetTemplateUsesVariable(r'\$TM_CURRENT_WORD', 'TM_CURRENT_WORD'),
        isFalse,
      );
      expect(
        snippetTemplateUsesVariable(
            r'$TM_CURRENT_WORD_SUFFIX', 'TM_CURRENT_WORD'),
        isFalse,
      );
      expect(
        snippetTemplateUsesVariable(
            r'${TM_SELECTED_TEXT:$TM_CURRENT_WORD}', 'TM_CURRENT_WORD'),
        isFalse,
      );
    });

    test('recognizes transformed names and skips transform format literals',
        () async {
      expect(
        snippetTemplateUsesVariable(
          r'${TM_CURRENT_LINE/(.*)/${1:/upcase}/}',
          'TM_CURRENT_LINE',
        ),
        isTrue,
      );
      expect(
        snippetTemplateUsesVariable(
          r'${TM_FILENAME//${1:+$CLIPBOARD}/g}',
          'CLIPBOARD',
        ),
        isFalse,
      );
      expect(
        snippetTemplateUsesVariable(
          r'${TM_SELECTED_TEXT/(.*)/$TM_CURRENT_LINE/',
          'TM_CURRENT_LINE',
        ),
        isFalse,
      );
    });
  });

  group('expandSnippetTemplate', () {
    test('expands defaults, linked tabstops, and the final cursor stop',
        () async {
      final expansion = await expandSnippetTemplate(r'let ${1:name} = $1;$0');

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

    test('uses the first non-empty default for earlier empty mirrors',
        () async {
      final expansion = await expandSnippetTemplate(r'$1 ${1:} ${1:value} $1');

      expect(expansion.text, 'value value value value');
      expect(expansion.rangesFor(1), hasLength(4));
    });

    test('uses one value for repeated defaults on the same tabstop', () async {
      final expansion =
          await expandSnippetTemplate(r'${1:first} $1 ${1:later}');

      expect(expansion.text, 'first first first');
      expect(expansion.rangesFor(1), hasLength(3));
    });

    test('expands choice placeholders from the first option and links mirrors',
        () async {
      final expansion = await expandSnippetTemplate(r'${1|one,two|}-$1$0');

      expect(expansion.text, 'one-one');
      expect(expansion.tabstopOrder, [1, 0]);
      expect(expansion.rangesFor(1), hasLength(2));
      expect(expansion.rangesFor(1).first.choice?.options, ['one', 'two']);
      expect(expansion.rangesFor(1).last.choice, isNull);
    });

    test('unescapes choice commas, pipes, and backslashes', () async {
      final expansion = await expandSnippetTemplate(
        r'${1|\,comma,pipe\|value,back\\slash|}',
      );

      expect(expansion.text, ',comma');
      expect(
        expansion.rangesFor(1).single.choice?.options,
        [',comma', 'pipe|value', r'back\slash'],
      );
    });

    test('keeps malformed and empty choice expressions as literal text',
        () async {
      for (final template in [
        r'${1||}',
        r'${1|one,,two|}',
        r'${1|one,two,|}',
        r'${1|one,two',
        r'${0|one,two|}',
      ]) {
        final expansion = await expandSnippetTemplate(template);
        expect(expansion.text, template, reason: template);
        expect(expansion.placeholders, isEmpty, reason: template);
      }
    });

    test('bounds choice option count', () async {
      await expectLater(
        expandSnippetTemplate(
          r'${1|one,two,three|}',
          maxChoiceOptions: 2,
        ),
        throwsA(isA<SnippetTemplateException>()),
      );
      const incomplete = r'${1|one,two';
      expect(
        (await expandSnippetTemplate(incomplete, maxChoiceOptions: 1)).text,
        incomplete,
      );
    });

    test('keeps choice range offsets in UTF-16 units across emoji and CRLF',
        () async {
      final expansion = await expandSnippetTemplate('🙂\r\n\${1|猫,fox|}-\$1');

      expect(expansion.text, '🙂\r\n猫-猫');
      expect(
        expansion
            .rangesFor(1)
            .map((range) => [range.startUtf16, range.endUtf16]),
        [
          [4, 5],
          [6, 7],
        ],
      );
    });

    test('adds an implicit final cursor stop when omitted', () async {
      final expansion = await expandSnippetTemplate(r'${1:name}-$1');

      expect(expansion.text, 'name-name');
      expect(expansion.tabstopOrder, [1, 0]);
      expect(expansion.rangesFor(0).single.startUtf16, 9);
    });

    test('keeps UTF-16 offsets across emoji and CRLF', () async {
      final expansion = await expandSnippetTemplate('🙂\r\n\${1:x} \$1');

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
        () async {
      final expansion = await expandSnippetTemplate(
        r'\$x \} \\ ${1:a\}b} $1 ${TM_FILENAME} $TM_FILENAME',
      );

      expect(expansion.text, r'$x } \ a}b a}b ${TM_FILENAME} $TM_FILENAME');
    });

    test('expands selected text as literal text without a tabstop', () async {
      final expansion = await expandSnippetTemplate(
        r'<$TM_SELECTED_TEXT> ${TM_SELECTED_TEXT} \$TM_SELECTED_TEXT ${TM_FILENAME}$0',
        variables: const {'TM_SELECTED_TEXT': '🙂x'},
      );

      expect(expansion.text, r'<🙂x> 🙂x $TM_SELECTED_TEXT ${TM_FILENAME}');
      expect(expansion.tabstopOrder, [0]);
      expect(expansion.rangesFor(0).single.startUtf16, expansion.text.length);
    });

    test('uses an explicitly resolved empty selected-text variable', () async {
      final expansion = await expandSnippetTemplate(
        r'${TM_SELECTED_TEXT:fallback}',
        variables: const {'TM_SELECTED_TEXT': ''},
      );

      expect(expansion.text, isEmpty);
    });

    test('expands filename variables without turning them into tabstops',
        () async {
      final expansion = await expandSnippetTemplate(
        r'$TM_FILENAME ${TM_FILENAME_BASE:fallback}$0',
        variables: {
          ...snippetFilenameVariables('archive.tar.rs'),
        },
      );

      expect(expansion.text, 'archive.tar.rs archive.tar');
      expect(expansion.tabstopOrder, [0]);
    });

    test('expands current-line contents once as literal text', () async {
      final expansion = await expandSnippetTemplate(
        r'<$TM_CURRENT_LINE>$0',
        variables: snippetCurrentLineVariables(r'let $TM_FILENAME = 🦊;'),
      );

      expect(expansion.text, r'<let $TM_FILENAME = 🦊;>');
      expect(expansion.tabstopOrder, [0]);
    });

    test('expands current word and preserves unresolved references', () async {
      expect(
        (await expandSnippetTemplate(
          r'<$TM_CURRENT_WORD>${TM_CURRENT_WORD:fallback}',
          variables: snippetCurrentWordVariables('let value', 6),
        ))
            .text,
        '<value>value',
      );
      expect(
        (await expandSnippetTemplate(r'$TM_CURRENT_WORD')).text,
        r'$TM_CURRENT_WORD',
      );
      expect(
        (await expandSnippetTemplate(r'${TM_CURRENT_WORD:fallback}')).text,
        r'${TM_CURRENT_WORD:fallback}',
      );
    });

    test('preserves malformed placeholder syntax as literal text', () async {
      expect((await expandSnippetTemplate(r'${1:unfinished')).text,
          r'${1:unfinished');
      expect((await expandSnippetTemplate(r'$x')).text, r'$x');
    });

    test('counts nested placeholders once when an outer default is incomplete',
        () async {
      final expansion = await expandSnippetTemplate(
        r'${1:${2:x}',
        maxPlaceholderOccurrences: 1,
      );

      expect(expansion.text, r'${1:x');
      expect(expansion.tabstopOrder, [2, 0]);
    });

    test('applies variable regex transforms with groups and flags', () async {
      final expansion = await expandSnippetTemplate(
        r'${TM_FILENAME/(.*)\..+$/$1/} ${TM_CURRENT_WORD/[a-z]+/X/gi}',
        variables: {
          'TM_FILENAME': 'archive.tar.rs',
          'TM_CURRENT_WORD': 'alpha ALPHA beta',
        },
      );

      expect(expansion.text, 'archive.tar X X X');
      expect(expansion.placeholders, isEmpty);
    });

    test('applies capture case and conditional formats', () async {
      final expansion = await expandSnippetTemplate(
        r'${NAME/(.*)/${1:/pascalcase} ${1:+set} ${2:-fallback} ${2:?yes:no}/}',
        variables: const {'NAME': 'hello world'},
      );

      expect(expansion.text, 'HelloWorld set fallback no');
      expect(expansion.placeholders, isEmpty);
    });

    test('supports all documented capture case formats', () async {
      final expansion = await expandSnippetTemplate(
        r'${NAME/(.*)/${1:/camelcase}|${1:/pascalcase}|${1:/kebabcase}|${1:/snakecase}|${1:/capitalize}|${1:/downcase}|${1:/upcase}/}',
        variables: const {'NAME': 'hello World'},
      );

      expect(
        expansion.text,
        'helloWorld|HelloWorld|hello-world|hello_world|Hello World|hello world|HELLO WORLD',
      );
    });

    test('transforms unresolved variables from the empty string', () async {
      final expansion = await expandSnippetTemplate(
        r'${UNKNOWN/(.*)/${1:+matched}${1:-empty}/}',
      );

      expect(expansion.text, 'matched');
    });

    test('parses placeholder transforms and defers them until tabstop exit',
        () async {
      final expansion = await expandSnippetTemplate(
        r'${1:name}-${1/([a-z]+)/${1:/upcase}/g}-${1/x/${1:-fallback}/}$0',
      );

      expect(expansion.text, 'name-name-name');
      final ranges = expansion.rangesFor(1);
      expect(ranges, hasLength(3));
      expect(ranges.first.transform, isNull);
      expect(ranges[1].transform?.pattern, r'([a-z]+)');
      expect(ranges[1].transform?.applyFormatWhenNoMatch, isFalse);
      expect(ranges[2].transform?.applyFormatWhenNoMatch, isTrue);

      final unmatched = await applySnippetVariableTransforms([
        ranges[2].transform!.withValue('dog'),
      ]);
      expect(unmatched, ['fallback']);

      final noElse = await applySnippetVariableTransforms([
        ranges[1].transform!.withValue('123'),
      ]);
      expect(noElse, ['123']);
    });

    test('keeps an incomplete placeholder transform literal', () async {
      const template = r'${1/regex/format/options';
      expect((await expandSnippetTemplate(template)).text, template);
      await expectLater(
        expandSnippetTemplate(r'${TM_FILENAME/[a-z]+/\}'),
        throwsA(isA<SnippetTemplateException>()),
      );
    });

    test('rejects invalid regex and enforces transform expression limits',
        () async {
      await expectLater(
        expandSnippetTemplate(r'${NAME/[/x/}', variables: const {'NAME': 'x'}),
        throwsA(isA<SnippetTemplateException>()),
      );
      final longRegex = 'a' * 513;
      await expectLater(
        expandSnippetTemplate('\${NAME/$longRegex/x/}',
            variables: const {'NAME': 'x'}),
        throwsA(isA<SnippetTemplateException>()),
      );
    });

    test('bounds transform count, aggregate input, and replacement output',
        () async {
      final tooManyTransforms = List.filled(65, r'${NAME/a/b/}').join();
      await expectLater(
        expandSnippetTemplate(tooManyTransforms,
            variables: const {'NAME': 'a'}),
        throwsA(isA<SnippetTemplateException>()),
      );
      await expectLater(
        expandSnippetTemplate(
          r'${NAME/a/b/}',
          variables: {'NAME': 'a' * (256 * 1024 + 1)},
        ),
        throwsA(isA<SnippetTemplateException>()),
      );
      await expectLater(
        expandSnippetTemplate(
          r'${NAME/a/$0$0/g}',
          variables: {'NAME': 'a' * (128 * 1024 + 1)},
        ),
        throwsA(isA<SnippetTemplateException>()),
      );
    });

    test('times out a pathological regex without blocking the caller isolate',
        () async {
      final pathologicalInput = "${'a' * 48}b";
      await expectLater(
        expandSnippetTemplate(
          r'${NAME/(a|aa)+$/$0/}',
          variables: {'NAME': pathologicalInput},
        ),
        throwsA(isA<SnippetTemplateException>()),
      );
    });

    test('expands nested placeholders and keeps their linked ranges', () async {
      final expansion =
          await expandSnippetTemplate(r'${1:outer ${2:inner}} / $1 / $2');

      expect(expansion.text, 'outer inner / outer inner / inner');
      expect(expansion.tabstopOrder, [1, 2, 0]);
      expect(
        expansion.rangesFor(1).map((range) => [
              range.startUtf16,
              range.endUtf16,
              range.ancestorOccurrenceIds,
            ]),
        [
          [0, 11, <int>[]],
          [14, 25, <int>[]],
        ],
      );
      expect(
        expansion.rangesFor(2).map((range) => [
              range.startUtf16,
              range.endUtf16,
              range.ancestorOccurrenceIds,
            ]),
        [
          [
            6,
            11,
            [expansion.rangesFor(1).first.occurrenceId]
          ],
          [
            20,
            25,
            [expansion.rangesFor(1).last.occurrenceId]
          ],
          [28, 33, <int>[]],
        ],
      );
    });

    test('nested offsets remain UTF-16 and escaped braces stay literal',
        () async {
      final expansion = await expandSnippetTemplate(r'${1:🦊 ${2:🙂x}}$0');

      expect(expansion.text, '🦊 🙂x');
      expect(expansion.rangesFor(1).single.lengthUtf16, 6);
      expect(expansion.rangesFor(2).single.startUtf16, 3);
      expect(expansion.rangesFor(2).single.endUtf16, 6);
      expect(
        (await expandSnippetTemplate(r'${1:literal \${2:not-a-tabstop\}}'))
            .text,
        r'literal ${2:not-a-tabstop}',
      );
    });

    test('bounds nested depth and rendered mirror range growth', () async {
      final nested =
          '${List.filled(33, r'${1:').join()}x${List.filled(33, '}').join()}';
      await expectLater(
        expandSnippetTemplate(nested),
        throwsA(isA<SnippetTemplateException>()),
      );

      await expectLater(
        expandSnippetTemplate(
          r'${1:${2:${3:${4:x}}}}$1$1$1$1',
          maxPlaceholderOccurrences: 8,
        ),
        throwsA(isA<SnippetTemplateException>()),
      );
    });

    test('bounds template size, expansion size, placeholder count, and indices',
        () async {
      await expectLater(
        expandSnippetTemplate('1234', maxTemplateUtf16: 3),
        throwsA(isA<SnippetTemplateException>()),
      );
      await expectLater(
        expandSnippetTemplate(r'${1:long}$1', maxExpandedUtf16: 5),
        throwsA(isA<SnippetTemplateException>()),
      );
      await expectLater(
        expandSnippetTemplate(r'${1:x}$1', maxPlaceholderOccurrences: 1),
        throwsA(isA<SnippetTemplateException>()),
      );
      await expectLater(
        expandSnippetTemplate(r'$10', maxTabstopIndex: 9),
        throwsA(isA<SnippetTemplateException>()),
      );
    });
  });
}
