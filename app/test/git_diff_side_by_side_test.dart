import 'package:flutter_test/flutter_test.dart';

import 'package:alula_app/git/git_diff_patch.dart';
import 'package:alula_app/git/git_diff_side_by_side.dart';

void main() {
  group('computeGitDiffSideBySideRows', () {
    test('pairs changed rows and keeps no-newline markers full-width', () {
      const patchText = 'diff --git a/file.txt b/file.txt\n'
          '@@ -1,3 +1,4 @@\n'
          ' context\n'
          '-old\n'
          r'\ No newline at end of file'
          '\n'
          '+new\n'
          '+extra\n'
          ' tail\n';
      final patch = parseGitDiffPatch(patchText);
      final result = computeGitDiffSideBySideRows(patch);

      expect(result.canRender, isTrue);
      expect(result.rows.map((row) => row.rowIndex), [0, 1, 2, 3, 4, 5, 6]);
      expect(result.rows[0].kind, GitDiffSideBySideRowKind.metadata);
      expect(result.rows[1].kind, GitDiffSideBySideRowKind.hunk);
      expect(result.rows[2].originalLine?.text, 'context');
      expect(result.rows[2].modifiedLine?.text, 'context');
      expect(result.rows[3].kind, GitDiffSideBySideRowKind.changed);
      expect(result.rows[3].originalLine?.text, 'old');
      expect(result.rows[3].modifiedLine?.text, 'new');
      expect(result.rows[4].kind, GitDiffSideBySideRowKind.marker);
      expect(
          result.rows[4].fullWidthLine?.text, r'\ No newline at end of file');
      expect(result.rows[5].originalLine, isNull);
      expect(result.rows[5].modifiedLine?.text, 'extra');
      expect(result.rows[6].originalLine?.text, 'tail');
      expect(result.rows[6].modifiedLine?.text, 'tail');
    });

    test('does not pair removals and additions across context or hunk rows',
        () {
      const patchText = 'diff --git a/file.txt b/file.txt\n'
          '@@ -1,2 +1,2 @@\n'
          '-before\n'
          ' context\n'
          '+after\n'
          '@@ -8 +8 @@\n'
          '-last-old\n'
          '+last-new\n';
      final result = computeGitDiffSideBySideRows(parseGitDiffPatch(patchText));
      final changes = result.rows
          .where((row) => row.kind == GitDiffSideBySideRowKind.changed)
          .toList();

      expect(result.canRender, isTrue);
      expect(changes, hasLength(3));
      expect(changes[0].originalLine?.text, 'before');
      expect(changes[0].modifiedLine, isNull);
      expect(changes[1].originalLine, isNull);
      expect(changes[1].modifiedLine?.text, 'after');
      expect(changes[2].originalLine?.text, 'last-old');
      expect(changes[2].modifiedLine?.text, 'last-new');
    });

    test('keeps pure insertion and deletion on their own side', () {
      final insertion = computeGitDiffSideBySideRows(parseGitDiffPatch(
        'diff --git a/file.txt b/file.txt\n'
        '@@ -0,0 +1,2 @@\n'
        '+first\n'
        '+second\n',
      ));
      final deletion = computeGitDiffSideBySideRows(parseGitDiffPatch(
        'diff --git a/file.txt b/file.txt\n'
        '@@ -1,2 +0,0 @@\n'
        '-first\n'
        '-second\n',
      ));

      final inserted = insertion.rows
          .where((row) => row.kind == GitDiffSideBySideRowKind.changed)
          .toList();
      final deleted = deletion.rows
          .where((row) => row.kind == GitDiffSideBySideRowKind.changed)
          .toList();
      expect(inserted, hasLength(2));
      expect(inserted.every((row) => row.originalLine == null), isTrue);
      expect(
          inserted.map((row) => row.modifiedLine?.text), ['first', 'second']);
      expect(deleted, hasLength(2));
      expect(deleted.every((row) => row.modifiedLine == null), isTrue);
      expect(deleted.map((row) => row.originalLine?.text), ['first', 'second']);
    });

    test('returns explicit fallback for unsupported and over-budget patches',
        () {
      final unsupported = computeGitDiffSideBySideRows(
        parseGitDiffPatch('GIT binary patch\n'),
      );
      final rowLimited = computeGitDiffSideBySideRows(
        parseGitDiffPatch(
          'diff --git a/file.txt b/file.txt\n@@ -1 +1 @@\n-old\n+new\n',
        ),
        options: const GitDiffSideBySideOptions(maxRows: 1),
      );

      expect(
        unsupported.fallbackReason,
        GitDiffSideBySideFallbackReason.unsupportedPatch,
      );
      expect(
          rowLimited.fallbackReason, GitDiffSideBySideFallbackReason.rowLimit);
      expect(unsupported.rows, isEmpty);
      expect(rowLimited.rows, isEmpty);
    });

    test('preserves emoji, BOM, CRLF payloads without copying source text', () {
      const patchText = 'diff --git a/file.txt b/file.txt\r\n'
          '@@ -1 +1 @@\r\n'
          '-\uFEFFold😀\r\n'
          '+\uFEFFnew😀\r\n';
      final patch = parseGitDiffPatch(patchText);
      final result = computeGitDiffSideBySideRows(patch);
      final changed = result.rows.singleWhere(
        (row) => row.kind == GitDiffSideBySideRowKind.changed,
      );

      expect(changed.originalLine, same(patch.lines[2]));
      expect(changed.modifiedLine, same(patch.lines[3]));
      expect(changed.originalLine?.text, '\uFEFFold😀\r');
      expect(changed.modifiedLine?.text, '\uFEFFnew😀\r');
    });
  });
}
