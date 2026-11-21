import 'package:alula_app/workbench/editor_tab_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps unique and pathless labels unchanged', () {
    expect(
      EditorTabLabelPolicy.labelsFor(const [
        EditorTabLabelInput(
            name: 'main.dart', path: '/workspace/lib/main.dart'),
        EditorTabLabelInput(name: 'untitled'),
      ]),
      ['main.dart', 'untitled'],
    );
  });

  test('adds the shortest parent path for two and three collisions', () {
    expect(
      EditorTabLabelPolicy.labelsFor(const [
        EditorTabLabelInput(
            name: 'main.dart', path: '/workspace/lib/main.dart'),
        EditorTabLabelInput(
            name: 'main.dart', path: '/workspace/test/main.dart'),
      ]),
      ['main.dart — lib', 'main.dart — test'],
    );
    expect(
      EditorTabLabelPolicy.labelsFor(const [
        EditorTabLabelInput(
          name: 'model.dart',
          path: '/workspace/alpha/src/model.dart',
        ),
        EditorTabLabelInput(
          name: 'model.dart',
          path: '/workspace/beta/src/model.dart',
        ),
        EditorTabLabelInput(
          name: 'model.dart',
          path: '/workspace/gamma/domain/model.dart',
        ),
      ]),
      [
        'model.dart — alpha/src',
        'model.dart — beta/src',
        'model.dart — domain',
      ],
    );
  });

  test('extends matching parent suffixes only as far as necessary', () {
    expect(
      EditorTabLabelPolicy.labelsFor(const [
        EditorTabLabelInput(name: 'readme.md', path: '/one/docs/readme.md'),
        EditorTabLabelInput(name: 'readme.md', path: '/two/docs/readme.md'),
        EditorTabLabelInput(name: 'readme.md'),
      ]),
      [
        'readme.md — one/docs',
        'readme.md — two/docs',
        'readme.md',
      ],
    );
  });

  test('uses root markers for root-level files and same-parent collisions', () {
    expect(
      EditorTabLabelPolicy.labelsFor(const [
        EditorTabLabelInput(name: 'config.json', path: '/config.json'),
        EditorTabLabelInput(name: 'config.json', path: '/etc/config.json'),
      ]),
      ['config.json — /', 'config.json — etc'],
    );
    expect(
      EditorTabLabelPolicy.labelsFor(const [
        EditorTabLabelInput(
          name: 'main.dart',
          path: '/project-one/src/main.dart',
        ),
        EditorTabLabelInput(
          name: 'main.dart',
          path: '/project-two/src/main.dart',
        ),
      ]),
      ['main.dart — project-one/src', 'main.dart — project-two/src'],
    );
  });

  test('normalizes mixed separators and dot segments', () {
    expect(
      EditorTabLabelPolicy.labelsFor(const [
        EditorTabLabelInput(
          name: 'lib.rs',
          path: r'C:\workspace\alpha\.\src\lib.rs',
        ),
        EditorTabLabelInput(
          name: 'lib.rs',
          path: 'C:/workspace/beta/src/../src/lib.rs',
        ),
      ]),
      ['lib.rs — alpha/src', 'lib.rs — beta/src'],
    );
  });

  test('retains Unicode path components', () {
    expect(
      EditorTabLabelPolicy.labelsFor(const [
        EditorTabLabelInput(name: '数据.json', path: '/工作区/甲/数据.json'),
        EditorTabLabelInput(name: '数据.json', path: '/工作区/乙/数据.json'),
      ]),
      ['数据.json — 甲', '数据.json — 乙'],
    );
  });

  test('uses the requested platform case behavior', () {
    const documents = [
      EditorTabLabelInput(name: 'Readme.md', path: '/one/Readme.md'),
      EditorTabLabelInput(name: 'README.MD', path: '/two/README.MD'),
    ];
    expect(
      EditorTabLabelPolicy.labelsFor(documents, caseSensitive: true),
      ['Readme.md', 'README.MD'],
    );
    expect(
      EditorTabLabelPolicy.labelsFor(documents, caseSensitive: false),
      ['Readme.md — one', 'README.MD — two'],
    );

    const paths = [
      EditorTabLabelInput(name: 'index.ts', path: r'C:\work\one\src\index.ts'),
      EditorTabLabelInput(name: 'index.ts', path: r'c:\work\two\SRC\index.ts'),
    ];
    expect(
      EditorTabLabelPolicy.labelsFor(paths, caseSensitive: false),
      ['index.ts — one/src', 'index.ts — two/SRC'],
      reason:
          'Windows path comparison extends past case-only directory matches',
    );
    expect(
      EditorTabLabelPolicy.labelsFor(paths, caseSensitive: true),
      ['index.ts — src', 'index.ts — SRC'],
      reason: 'Unix-style case-sensitive comparison distinguishes the suffixes',
    );
  });

  test('leaves indistinguishable paths and pathless collisions honest', () {
    expect(
      EditorTabLabelPolicy.labelsFor(const [
        EditorTabLabelInput(name: 'same.rs'),
        EditorTabLabelInput(name: 'same.rs'),
      ]),
      ['same.rs', 'same.rs'],
    );
    expect(
      EditorTabLabelPolicy.labelsFor(const [
        EditorTabLabelInput(name: 'same.rs', path: '/workspace/src/same.rs'),
        EditorTabLabelInput(name: 'same.rs', path: '/workspace/src/same.rs'),
      ]),
      ['same.rs — /workspace/src', 'same.rs — /workspace/src'],
    );
  });
}
