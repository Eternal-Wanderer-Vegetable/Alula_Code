import 'package:alula_app/workbench/open_editors_sort_order.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Doc = ({int id, String? uri});

List<_Doc> _sort(Iterable<_Doc> docs) => sortOpenEditors(
      docs,
      OpenEditorsSortOrder.fullPath,
      uriOf: (doc) => doc.uri,
    );

void main() {
  test('parse accepts only the two persisted choices and defaults safely', () {
    expect(OpenEditorsSortOrder.values, [
      OpenEditorsSortOrder.editorOrder,
      OpenEditorsSortOrder.fullPath,
    ]);
    expect(
        OpenEditorsSortOrder.parse('fullPath'), OpenEditorsSortOrder.fullPath);
    for (final value in <Object?>[
      'editorOrder',
      null,
      '',
      'alphabetical',
      'FullPath',
      true,
      1,
      {},
      [],
    ]) {
      expect(
          OpenEditorsSortOrder.parse(value), OpenEditorsSortOrder.editorOrder);
    }
  });

  test('editorOrder copies a lazy iterable without evaluating resource keys',
      () {
    final docs = [(id: 1, uri: 'file:///z'), (id: 2, uri: 'file:///a')];
    final result = sortOpenEditors<_Doc>(
      docs.map((doc) => doc),
      OpenEditorsSortOrder.editorOrder,
      uriOf: (_) => throw StateError('editor order needs no resource'),
    );
    expect(result, docs);
    expect(identical(result, docs), isFalse);
    result.removeLast();
    expect(docs, hasLength(2));
  });

  test('resource-less and malformed entries precede non-file then file', () {
    final docs = <_Doc>[
      (id: 0, uri: 'file:///a'),
      (id: 1, uri: null),
      (id: 2, uri: 'untitled:Z'),
      (id: 3, uri: 'not a URI'),
      (id: 4, uri: 'file:///%GG'),
      (id: 5, uri: ''),
      (id: 6, uri: 'file:///%FF'),
      (id: 7, uri: 'file:///bad\npath'),
      (id: 8, uri: 'git:/a'),
      (id: 9, uri: 'file:////invalid'),
    ];
    final original = docs.toList();
    final result = _sort(docs);
    expect(result.map((doc) => doc.id), [1, 3, 4, 5, 6, 7, 9, 8, 2, 0]);
    expect(docs, original);
    for (final doc in result) {
      expect(identical(doc, docs[doc.id]), isTrue);
    }
  });

  test('ordinal numeric paths and full directory paths, not basename order',
      () {
    final docs = <_Doc>[
      (id: 0, uri: 'file:///b/a'),
      (id: 1, uri: 'file:///a/file2'),
      (id: 2, uri: 'file:///a/file10'),
      (id: 3, uri: 'file:///a/z'),
    ];
    expect(_sort(docs).map((doc) => doc.id), [2, 1, 3, 0]);
  });

  test('decoded path case ties retain original index in either input order',
      () {
    final docs = <_Doc>[
      (id: 0, uri: 'file:///C:/WORK/%41.txt'),
      (id: 1, uri: 'file:///c:/work/a.txt'),
      (id: 2, uri: 'file:///c%3A/Work/A.txt'),
    ];
    expect(_sort(docs), docs);
    expect(_sort(docs.reversed), docs.reversed.toList());
  });

  test('query and fragment case stays significant, path case does not', () {
    final docs = <_Doc>[
      (id: 0, uri: 'file:///A?q=a#F'),
      (id: 1, uri: 'file:///a?q=A#f'),
      (id: 2, uri: 'file:///a?q=A#F'),
      (id: 3, uri: 'file:///a?q=%41#%46'),
    ];
    expect(_sort(docs).map((doc) => doc.id), [2, 3, 1, 0]);
  });

  test('drive colon must be encoded, unlike a literal path slash', () {
    final docs = <_Doc>[
      (id: 0, uri: 'file:///c/next'),
      (id: 1, uri: 'file:///C:/next'),
    ];
    // file:///c%3A/next < file:///c/next (percent precedes slash).
    expect(_sort(docs).map((doc) => doc.id), [1, 0]);
  });

  test('reserved punctuation is encoded before ordinal comparison', () {
    // Escaped punctuation precedes the literal hyphen, even when the decoded
    // character (colon, @, square bracket, etc.) would follow it.
    for (final character in [
      '!',
      r'$',
      '&',
      "'",
      '(',
      ')',
      '*',
      '+',
      ',',
      ':',
      ';',
      '=',
      '@',
      '[',
      ']',
      '?',
      '#',
      '%',
      ' ',
      '中',
      '😀'
    ]) {
      final docs = <_Doc>[
        (id: 0, uri: 'file:///x-'),
        (id: 1, uri: 'file:///x${Uri.encodeComponent(character)}'),
      ];
      expect(_sort(docs).map((doc) => doc.id), [1, 0], reason: character);
    }
  });

  test('space, percent, CJK and emoji use encoded UTF-8 ordinal keys', () {
    final docs = <_Doc>[
      (id: 0, uri: 'file:///x😀'),
      (id: 1, uri: 'file:///x中'),
      (id: 2, uri: 'file:///x%25'),
      (id: 3, uri: 'file:///x%20'),
      (id: 4, uri: 'file:///x '),
      (id: 5, uri: 'file:///x%2520'),
    ];
    expect(_sort(docs).map((doc) => doc.id), [3, 4, 2, 5, 1, 0]);
  });

  test('UNC authority case folds, but query and fragment do not', () {
    final docs = <_Doc>[
      (id: 0, uri: 'file://SERVER/Share/A?q=a#F'),
      (id: 1, uri: 'file://server/share/a?q=A#F'),
      (id: 2, uri: 'file://Server/SHARE/a?q=A#F'),
    ];
    expect(_sort(docs).map((doc) => doc.id), [1, 2, 0]);
  });

  test('generic URI serializer matches pinned encoded-key ordering', () {
    // Literal golden keys from uri.ts _asFormatted, after lowercasing path.
    // Compare all pairs to cover scheme, authority/userinfo/port, encoded
    // components and case without exposing the private production serializer.
    const fixtures = <({String uri, String key})>[
      (uri: 'git:/A!', key: 'git:/a%21'),
      (uri: 'git:/a-', key: 'git:/a-'),
      (uri: 'git:/a?x=A&B#F/G', key: 'git:/a?x%3DA%26B#F%2FG'),
      (uri: 'git:/a?x=a&b#f/g', key: 'git:/a?x%3Da%26b#f%2Fg'),
      (uri: 'git:/a?x%3DA%26B#F%2FG', key: 'git:/a?x%3DA%26B#F%2FG'),
      (uri: 'git://HOST/A', key: 'git://host/a'),
      (uri: 'git://host/a', key: 'git://host/a'),
      (uri: 'git://HOST:42/A', key: 'git://host:42/a'),
      (uri: 'git://[ABCD::1]:42/A', key: 'git://[abcd::1]:42/a'),
      (uri: 'git://User:Pa%3Ass@HOST/A', key: 'git://User:Pa%3Ass@host/a'),
      (uri: 'git://user:Pa%3Ass@HOST/A', key: 'git://user:Pa%3Ass@host/a'),
      (uri: 'git://User%40Name@HOST/A', key: 'git://User@name%40host/a'),
      (uri: 'git:/C:/A', key: 'git:/c%3A/a'),
      (uri: 'git:/c/A', key: 'git:/c/a'),
      (uri: 'git:/x%20', key: 'git:/x%20'),
      (uri: 'git:/x%25', key: 'git:/x%25'),
      (uri: 'git:/x中', key: 'git:/x%E4%B8%AD'),
      (uri: 'git:/x😀', key: 'git:/x%F0%9F%98%80'),
      (uri: 'git:/x-', key: 'git:/x-'),
      (uri: 'git:/x~', key: 'git:/x~'),
      (uri: 'git:/a?#', key: 'git:/a'),
      (uri: 'git:/a', key: 'git:/a'),
      (uri: 'git:/a/../b', key: 'git:/a/../b'),
      (uri: 'git:/b', key: 'git:/b'),
      (uri: 'GIT:/A', key: 'GIT:/a'),
      (uri: 'https://HOST', key: 'https://host/'),
    ];
    for (var a = 0; a < fixtures.length; a++) {
      for (var b = 0; b < fixtures.length; b++) {
        final docs = <_Doc>[
          (id: 0, uri: fixtures[a].uri),
          (id: 1, uri: fixtures[b].uri),
        ];
        final expected =
            fixtures[a].key.compareTo(fixtures[b].key) <= 0 ? [0, 1] : [1, 0];
        expect(_sort(docs).map((doc) => doc.id), expected,
            reason: '${fixtures[a].uri} vs ${fixtures[b].uri}');
      }
    }
  });

  test('native file URI projection handles POSIX, Windows and UNC paths', () {
    for (final fixture in [
      (windows: false, root: '/tmp/project/'),
      (windows: true, root: r'C:\project\'),
      (windows: true, root: r'\\server\share\'),
    ]) {
      final docs = <_Doc>[
        (
          id: 0,
          uri: Uri.file('${fixture.root}z%done#.rs', windows: fixture.windows)
              .toString()
        ),
        (
          id: 1,
          uri: Uri.file('${fixture.root}alpha.rs', windows: fixture.windows)
              .toString()
        ),
      ];
      expect(_sort(docs).map((doc) => doc.id), [1, 0], reason: fixture.root);
    }
  });

  test('empty and singleton inputs still return independent lists', () {
    expect(_sort(const <_Doc>[]), isEmpty);
    final docs = <_Doc>[(id: 1, uri: null)];
    final sorted = _sort(docs);
    expect(sorted, docs);
    expect(identical(sorted, docs), isFalse);
  });
}
