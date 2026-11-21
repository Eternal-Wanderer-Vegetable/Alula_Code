import 'package:alula_app/workbench/document_symbols.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> row(
  String name,
  int start,
  int line,
  int endLine, {
  String kind = 'function',
}) =>
    {
      'kind': kind,
      'name': name,
      'start_utf16': start,
      'line': line,
      'end_line': endLine,
    };

List<String> names(List<({DocumentSymbolNode symbol, int depth})> rows) =>
    [for (final entry in rows) entry.symbol.name];

void main() {
  test('builds ordered nested ranges from unsorted input without mutation', () {
    final raw = [
      row('leaf', 30, 4, 4),
      row('after', 100, 12, 12),
      row('outer', 0, 1, 10, kind: 'class'),
      row('inner', 20, 3, 6),
      row('sibling', 70, 8, 9),
    ];
    final roots = buildDocumentSymbolTree(raw);
    final projected = projectDocumentSymbols(roots);
    expect(names(projected), ['outer', 'inner', 'leaf', 'sibling', 'after']);
    expect(projected.map((entry) => entry.depth), [0, 1, 2, 1, 0]);
    expect(raw.first['name'], 'leaf');
    expect(roots.first.children.map((node) => node.name), ['inner', 'sibling']);
    expect(() => roots.first.children.clear(), throwsUnsupportedError);
  });

  test('same-line and equal-range declarations remain siblings', () {
    final roots = buildDocumentSymbolTree([
      row('container', 0, 1, 10),
      row('first', 10, 2, 2),
      row('second', 20, 2, 2),
      row('equalA', 30, 3, 6),
      row('equalB', 40, 3, 6),
    ]);
    expect(roots.single.children.map((node) => node.name),
        ['first', 'second', 'equalA', 'equalB']);
    expect(
        roots.single.children.every((node) => node.children.isEmpty), isTrue);
  });

  test('same starts cannot imply parentage even for narrower ranges', () {
    final roots = buildDocumentSymbolTree([
      row('outer', 0, 1, 10),
      row('sameStart', 0, 2, 4),
      row('later', 20, 5, 6),
    ]);
    expect(roots.map((node) => node.name), ['outer', 'sameStart']);
    expect(roots.first.children.single.name, 'later');
    expect(roots.last.children, isEmpty);
  });

  test('crossing intervals are siblings and containing earlier parent survives',
      () {
    final roots = buildDocumentSymbolTree([
      row('outer', 0, 1, 20),
      row('left', 10, 2, 7),
      row('crossing', 20, 5, 10),
      row('insideLeft', 30, 6, 6),
      row('later', 40, 12, 13),
    ]);
    expect(roots.single.children.map((node) => node.name),
        ['left', 'crossing', 'later']);
    expect(roots.single.children[1].children.single.name, 'insideLeft');
  });

  test('containment includes first and last lines but requires ordered starts',
      () {
    final roots = buildDocumentSymbolTree([
      row('earlyNarrow', 0, 2, 2),
      row('outer', 10, 1, 10),
      row('firstLine', 20, 1, 1),
      row('lastLine', 30, 10, 10),
    ]);
    expect(roots.map((node) => node.name), ['earlyNarrow', 'outer']);
    expect(roots.last.children.map((node) => node.name),
        ['firstLine', 'lastLine']);
  });

  test('stable IDs depend only on UTF-16 start, kind and full name', () {
    final first = buildDocumentSymbolTree([row('🦊:name', 12, 2, 5)]).single;
    final moved = buildDocumentSymbolTree([row('🦊:name', 12, 3, 8)]).single;
    final differentKind = buildDocumentSymbolTree([
      row('🦊:name', 12, 2, 5, kind: 'class'),
    ]).single;
    final differentStart =
        buildDocumentSymbolTree([row('🦊:name', 13, 2, 5)]).single;
    expect(first.id, moved.id);
    expect(first.id, isNot(differentKind.id));
    expect(first.id, isNot(differentStart.id));
    expect(first.name, '🦊:name');
    expect(first.startUtf16, 12);
    final colonKind = buildDocumentSymbolTree([
      row('c', 0, 1, 1, kind: 'a:b'),
      row('b:c', 0, 1, 1, kind: 'a'),
    ]);
    expect(colonKind.first.id, isNot(colonKind.last.id));
  });

  test('name and kind sorting operate per sibling group, retaining hierarchy',
      () {
    final roots = buildDocumentSymbolTree([
      row('Zulu', 0, 1, 10, kind: 'class'),
      row('zebra', 10, 2, 2),
      row('Alpha', 20, 3, 3, kind: 'variable'),
      row('beta', 100, 12, 12),
      row('alpha', 110, 13, 13, kind: 'variable'),
    ]);
    expect(names(projectDocumentSymbols(roots)),
        ['Zulu', 'zebra', 'Alpha', 'beta', 'alpha']);
    expect(names(projectDocumentSymbols(roots, sort: DocumentSymbolSort.name)),
        ['alpha', 'beta', 'Zulu', 'Alpha', 'zebra']);
    expect(names(projectDocumentSymbols(roots, sort: DocumentSymbolSort.kind)),
        ['Zulu', 'zebra', 'Alpha', 'beta', 'alpha']);
    expect(names(projectDocumentSymbols(roots)),
        ['Zulu', 'zebra', 'Alpha', 'beta', 'alpha']);
  });

  test('sort ties use position and same-kind ties use name', () {
    final roots = buildDocumentSymbolTree([
      row('zulu', 0, 1, 1),
      row('Same', 20, 3, 3),
      row('same', 10, 2, 2),
    ]);
    expect(
      projectDocumentSymbols(roots, sort: DocumentSymbolSort.name)
          .map((entry) => entry.symbol.startUtf16),
      [10, 20, 0],
    );
    expect(names(projectDocumentSymbols(roots, sort: DocumentSymbolSort.kind)),
        ['same', 'Same', 'zulu']);
  });

  test('query preserves ancestors and matches case-insensitive substrings', () {
    final roots = buildDocumentSymbolTree([
      row('outer', 0, 1, 10),
      row('nested', 10, 2, 7),
      row('MyNeedleValue', 20, 3, 3),
      row('unrelated', 30, 4, 4),
      row('otherRoot', 100, 12, 12),
    ]);
    final projected = projectDocumentSymbols(roots, query: ' nEeDlE ');
    expect(names(projected), ['outer', 'nested', 'MyNeedleValue']);
    expect(projected.map((entry) => entry.depth), [0, 1, 2]);
    expect(projectDocumentSymbols(roots, query: 'absent'), isEmpty);
    expect(projectDocumentSymbols(roots, query: 'function'), isEmpty);
  });

  test('matching a folder does not include unrelated descendants', () {
    final roots = buildDocumentSymbolTree([
      row('needleFolder', 0, 1, 10),
      row('unrelated', 10, 2, 5),
      row('needleLeaf', 20, 3, 3),
      row('anotherChild', 60, 7, 7),
    ]);
    expect(names(projectDocumentSymbols(roots, query: 'needleFolder')),
        ['needleFolder']);
    expect(names(projectDocumentSymbols(roots, query: 'needle')),
        ['needleFolder', 'unrelated', 'needleLeaf']);
  });

  test('collapse hides descendants only without an active query', () {
    final roots = buildDocumentSymbolTree([
      row('outer', 0, 1, 10),
      row('inner', 10, 2, 8),
      row('match', 20, 3, 3),
      row('sibling', 90, 10, 10),
      row('root', 100, 12, 12),
    ]);
    final collapsed = {roots.first.id, roots.first.children.first.id};
    expect(names(projectDocumentSymbols(roots, collapsed: collapsed)),
        ['outer', 'root']);
    expect(
        names(projectDocumentSymbols(roots, query: '  ', collapsed: collapsed)),
        ['outer', 'root']);
    expect(
      names(
          projectDocumentSymbols(roots, query: 'MATCH', collapsed: collapsed)),
      ['outer', 'inner', 'match'],
    );
    expect(
      names(projectDocumentSymbols(roots,
          collapsed: {roots.first.children.first.id})),
      ['outer', 'inner', 'sibling', 'root'],
    );
  });

  test('line lookup selects deepest inclusive range and excludes gaps', () {
    final roots = buildDocumentSymbolTree([
      row('outer', 0, 1, 10),
      row('inner', 10, 2, 6),
      row('leaf', 20, 3, 3),
      row('after', 100, 12, 12),
    ]);
    expect(documentSymbolAtLine(roots, 0), isNull);
    expect(documentSymbolAtLine(roots, -1), isNull);
    expect(documentSymbolAtLine(roots, 1)?.name, 'outer');
    expect(documentSymbolAtLine(roots, 2)?.name, 'inner');
    expect(documentSymbolAtLine(roots, 3)?.name, 'leaf');
    expect(documentSymbolAtLine(roots, 6)?.name, 'inner');
    expect(documentSymbolAtLine(roots, 10)?.name, 'outer');
    expect(documentSymbolAtLine(roots, 11), isNull);
    expect(documentSymbolAtLine(roots, 12)?.name, 'after');
    expect(documentSymbolAtLine(roots, 13), isNull);
  });

  test('line lookup breaks same-depth ambiguity with later start', () {
    final roots = buildDocumentSymbolTree([
      row('first', 0, 1, 1),
      row('second', 10, 1, 1),
    ]);
    expect(documentSymbolAtLine(roots, 1)?.name, 'second');
    expect(documentSymbolAtLine(roots.reversed.toList(), 1)?.name, 'second');
  });

  test('line path returns nested ancestors and excludes gaps', () {
    final roots = buildDocumentSymbolTree([
      row('outer', 0, 1, 12, kind: 'mod'),
      row('left', 10, 2, 5),
      row('inner', 20, 3, 4),
      row('right', 40, 7, 9),
      row('after', 100, 14, 14),
    ]);
    expect(
      documentSymbolPathAtLine(roots, 3).map((symbol) => symbol.name),
      ['outer', 'left', 'inner'],
    );
    expect(
      documentSymbolPathAtLine(roots, 7).map((symbol) => symbol.name),
      ['outer', 'right'],
    );
    expect(
      documentSymbolPathAtLine(roots, 6).map((symbol) => symbol.name),
      ['outer'],
    );
    expect(documentSymbolPathAtLine(roots, 0), isEmpty);
    expect(documentSymbolPathAtLine(roots, 10000), isEmpty);
  });

  test('same-depth line path uses the same later-start tie break', () {
    final roots = buildDocumentSymbolTree([
      row('first', 0, 1, 1),
      row('second', 10, 1, 1),
    ]);
    final path = documentSymbolPathAtLine(roots, 1);
    expect(path.map((symbol) => symbol.name), ['second']);
    expect(path.last, documentSymbolAtLine(roots, 1));
  });

  test('rejects invalid rows without coercing wire types', () {
    final valid = row('valid', 0, 1, 1);
    final invalid = <Map<String, Object?>>[
      {},
      for (final key in valid.keys) {...valid}..remove(key),
      for (final kind in <Object?>[null, '', '  ', 7]) {...valid, 'kind': kind},
      for (final name in <Object?>[null, '', '  ', 7]) {...valid, 'name': name},
      for (final start in <Object?>[null, -1, '0', 0.0, double.nan])
        {...valid, 'start_utf16': start},
      for (final line in <Object?>[null, -1, 0, '1', 1.0])
        {...valid, 'line': line},
      for (final endLine in <Object?>[null, -1, 0, '1', 1.0])
        {...valid, 'end_line': endLine},
      row('reversed', 10, 3, 2),
    ];
    expect(buildDocumentSymbolTree(invalid), isEmpty);
    expect(buildDocumentSymbolTree([...invalid, valid]).single.name, 'valid');
  });

  test('empty input supports building, querying and line lookup', () {
    final roots = buildDocumentSymbolTree([]);
    expect(roots, isEmpty);
    expect(projectDocumentSymbols(roots), isEmpty);
    expect(projectDocumentSymbols(roots, query: 'needle'), isEmpty);
    expect(documentSymbolAtLine(roots, 1), isNull);
  });

  test('10000 deep ancestors build, filter and look up without recursion', () {
    final roots = buildDocumentSymbolTree([
      for (var index = 0; index < 10000; index++)
        row(index == 9999 ? 'needle' : 'ancestor$index', index, index + 1,
            20000 - index),
    ]);
    expect(roots.length, 1);
    final projected = projectDocumentSymbols(
      roots,
      query: 'needle',
      collapsed: {roots.single.id},
    );
    expect(projected.length, 10000);
    expect(projected.last.depth, 9999);
    expect(projected.last.symbol.name, 'needle');
    expect(documentSymbolAtLine(roots, 10000)?.name, 'needle');
  });

  test('input cap counts invalid rows and fails explicitly above 10000', () {
    expect(buildDocumentSymbolTree(List.generate(10000, (_) => {})), isEmpty);
    expect(
      () => buildDocumentSymbolTree(List.generate(10001, (_) => {})),
      throwsA(isA<ArgumentError>().having(
        (error) => error.message.toString(),
        'message',
        contains('10000'),
      )),
    );
  });
}
