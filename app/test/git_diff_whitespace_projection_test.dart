import 'package:flutter_test/flutter_test.dart';

import 'package:alula_app/git/git_diff_patch.dart';
import 'package:alula_app/git/git_diff_whitespace_projection.dart';

void main() {
  group('projectGitDiffPatchIgnoringTrimWhitespace', () {
    test('folds trim-equivalent lines but keeps internal whitespace changes',
        () {
      const patch = 'diff --git a/file.txt b/file.txt\n'
          '@@ -1,3 +1,3 @@\n'
          '-  leading\n'
          '+leading\n'
          '-trailing  \t\n'
          '+trailing\n'
          '-internal  gap\n'
          '+internal gap\n';

      final result = projectGitDiffPatchIgnoringTrimWhitespace(
        parseGitDiffPatch(patch),
      );

      expect(result.canRender, isTrue);
      expect(result.rows.map((row) => row.kind), [
        GitDiffProjectionRowKind.metadata,
        GitDiffProjectionRowKind.hunk,
        GitDiffProjectionRowKind.context,
        GitDiffProjectionRowKind.context,
        GitDiffProjectionRowKind.changed,
      ]);
      final neutralRows = result.rows
          .where((row) => row.kind == GitDiffProjectionRowKind.context)
          .toList();
      expect(
          neutralRows.map((row) => row.trimWhitespaceEquivalent), [true, true]);
      expect(neutralRows[0].originalLine!.text, '  leading');
      expect(neutralRows[0].modifiedLine!.text, 'leading');
      expect(neutralRows[0].originalLine!.originalLineNumber, 1);
      expect(neutralRows[0].modifiedLine!.modifiedLineNumber, 1);
      expect(neutralRows[0].originalWordChanges, isEmpty);
      expect(neutralRows[0].modifiedWordChanges, isEmpty);
      final internalChange = result.rows
          .singleWhere((row) => row.kind == GitDiffProjectionRowKind.changed);
      expect(internalChange.originalLine!.text, 'internal  gap');
      expect(internalChange.modifiedLine!.text, 'internal gap');

      expect(result.inlineRows.map((row) => row.line.text), [
        'diff --git a/file.txt b/file.txt',
        '@@ -1,3 +1,3 @@',
        'leading',
        'trailing',
        'internal  gap',
        'internal gap',
      ]);
      expect(result.changes, hasLength(1));
      expect(result.changes.single.originalLineNumber, 3);
      expect(result.changes.single.modifiedLineNumber, 3);
    });

    test('keeps hunk boundaries and unmatched source rows independent', () {
      const patch = 'diff --git a/file.txt b/file.txt\n'
          '@@ -1,3 +1,2 @@ first\n'
          '-old one\n'
          '-old two\n'
          '+new one\n'
          ' context\n'
          '@@ -8 +7,0 @@ second\n'
          '-removed later\n';

      final result = projectGitDiffPatchIgnoringTrimWhitespace(
        parseGitDiffPatch(patch),
      );

      expect(result.canRender, isTrue);
      expect(
        result.rows
            .where((row) => row.kind == GitDiffProjectionRowKind.hunk)
            .map((row) => row.fullWidthLine!.text),
        ['@@ -1,3 +1,2 @@ first', '@@ -8 +7,0 @@ second'],
      );
      final changed = result.rows
          .where((row) => row.kind == GitDiffProjectionRowKind.changed)
          .toList();
      expect(changed, hasLength(1));
      expect(changed.single.originalLine!.text, 'old one');
      expect(changed.single.modifiedLine!.text, 'new one');
      final deleted = result.rows
          .where((row) => row.kind == GitDiffProjectionRowKind.deleted)
          .toList();
      expect(deleted.map((row) => row.originalLine!.text),
          ['old two', 'removed later']);
      expect(deleted.every((row) => row.modifiedLine == null), isTrue);
      expect(result.changes, hasLength(2));
      expect(result.inlineRows.map((row) => row.line.text), [
        'diff --git a/file.txt b/file.txt',
        '@@ -1,3 +1,2 @@ first',
        'old one',
        'old two',
        'new one',
        'context',
        '@@ -8 +7,0 @@ second',
        'removed later',
      ]);
    });

    test('preserves marker source order, CRLF, BOM, and emoji text', () {
      const patch = 'diff --git a/file.txt b/file.txt\r\n'
          '@@ -1 +1 @@\r\n'
          '-\uFEFFold 😀\r\n'
          r'\ No newline at end of file'
          '\r\n'
          '+\uFEFFnew 😀\r\n'
          r'\ No newline at end of file'
          '\r\n';

      final result = projectGitDiffPatchIgnoringTrimWhitespace(
        parseGitDiffPatch(patch),
      );

      expect(result.canRender, isTrue, reason: '${result.fallbackReason}');
      expect(result.inlineRows.map((row) => row.line.kind), [
        GitDiffPatchLineKind.metadata,
        GitDiffPatchLineKind.hunk,
        GitDiffPatchLineKind.removed,
        GitDiffPatchLineKind.marker,
        GitDiffPatchLineKind.added,
        GitDiffPatchLineKind.marker,
      ]);
      expect(result.inlineRows.map((row) => row.line.text), [
        'diff --git a/file.txt b/file.txt\r',
        '@@ -1 +1 @@\r',
        '\uFEFFold 😀\r',
        '\\ No newline at end of file\r',
        '\uFEFFnew 😀\r',
        '\\ No newline at end of file\r',
      ]);
      expect(
          result.rows
              .where((row) => row.kind == GitDiffProjectionRowKind.marker),
          hasLength(2));
    });

    test('falls back atomically when a line-model budget is exhausted', () {
      const patch = 'diff --git a/file.txt b/file.txt\n'
          '@@ -1 +1 @@\n'
          '-old\n'
          '+new\n';

      final result = projectGitDiffPatchIgnoringTrimWhitespace(
        parseGitDiffPatch(patch),
        options: const GitDiffProjectionOptions(maxLineDiffTraceCells: 0),
      );

      expect(result.canRender, isFalse);
      expect(
          result.fallbackReason, GitDiffProjectionFallbackReason.modelFallback);
      expect(result.rows, isEmpty);
      expect(result.inlineRows, isEmpty);
      expect(result.changes, isEmpty);
    });
  });
}
