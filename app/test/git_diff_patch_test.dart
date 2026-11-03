import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alula_app/git/git_diff_patch.dart';
import 'package:alula_app/git/git_diff_patch_view.dart';

void main() {
  group('parseGitDiffPatch', () {
    test('parses metadata, multiple hunks, source rows, and line numbers', () {
      const patch = 'diff --git a/file.txt b/file.txt\n'
          'index 1234567..abcdef0 100644\n'
          '--- a/file.txt\n'
          '+++ b/file.txt\n'
          '@@ -1,3 +1,3 @@ heading\n'
          ' first\n'
          '-old\n'
          '+new\n'
          ' last\n'
          '@@ -10 +10 @@\n'
          '-before\n'
          '+after\n'
          r'\ No newline at end of file'
          '\n';

      final result = parseGitDiffPatch(patch);

      expect(result.canRender, isTrue);
      expect(result.lines.first.kind, GitDiffPatchLineKind.metadata);
      final sourceRows = result.lines
          .where((line) =>
              line.kind == GitDiffPatchLineKind.context ||
              line.kind == GitDiffPatchLineKind.added ||
              line.kind == GitDiffPatchLineKind.removed)
          .toList();
      expect(sourceRows.map((line) => line.kind), [
        GitDiffPatchLineKind.context,
        GitDiffPatchLineKind.removed,
        GitDiffPatchLineKind.added,
        GitDiffPatchLineKind.context,
        GitDiffPatchLineKind.removed,
        GitDiffPatchLineKind.added,
      ]);
      expect(sourceRows.map((line) => line.originalLineNumber),
          [1, 2, null, 3, 10, null]);
      expect(sourceRows.map((line) => line.modifiedLineNumber),
          [1, null, 2, 3, null, 10]);
      expect(result.lines.last.kind, GitDiffPatchLineKind.marker);
      expect(result.lines.map((line) => line.rowIndex),
          List<int>.generate(result.lines.length, (index) => index));
    });

    test('supports zero-count insertions and deletion-only hunks', () {
      final inserted = parseGitDiffPatch(
        'diff --git a/new b/new\n'
        '@@ -0,0 +1,2 @@\n'
        '+one\n'
        '+two\n',
      );
      expect(inserted.canRender, isTrue);
      expect(
        inserted.lines
            .where((line) => line.kind == GitDiffPatchLineKind.added)
            .map((line) => line.modifiedLineNumber),
        [1, 2],
      );

      final deleted = parseGitDiffPatch(
        'diff --git a/gone b/gone\n'
        '@@ -2,1 +1,0 @@\n'
        '-gone\n',
      );
      expect(deleted.canRender, isTrue);
      final removal = deleted.lines.last;
      expect(removal.kind, GitDiffPatchLineKind.removed);
      expect(removal.originalLineNumber, 2);
      expect(removal.modifiedLineNumber, isNull);
    });

    test('preserves BOM, emoji, and CR from CRLF source content', () {
      final result = parseGitDiffPatch(
        'diff --git a/u.txt b/u.txt\n'
        '@@ -1 +1 @@\n'
        '-\uFEFFold😀\r\n'
        '+\uFEFFnew😃\r\n',
      );

      expect(result.canRender, isTrue);
      expect(result.lines[2].text, '\uFEFFold😀\r');
      expect(result.lines[3].text, '\uFEFFnew😃\r');
    });

    test(
        'returns complete-input fallback for metadata-only and malformed patch',
        () {
      final metadata = parseGitDiffPatch(
        'diff --git a/file b/file\nGIT binary patch\n',
      );
      expect(metadata.canRender, isFalse);
      expect(metadata.fallbackReason, GitDiffPatchFallbackReason.noTextHunks);
      expect(metadata.lines, isEmpty);

      final malformed = parseGitDiffPatch(
        'diff --git a/file b/file\n@@ -1,2 +1,1 @@\n-old\n+new\n',
      );
      expect(malformed.canRender, isFalse);
      expect(malformed.fallbackReason, GitDiffPatchFallbackReason.malformed);
      expect(malformed.lines, isEmpty);
    });

    test('falls back without partial rows when input or row budget is exceeded',
        () {
      final inputLimited = parseGitDiffPatch(
        'diff --git a/file b/file\n@@ -1 +1 @@\n-old\n+new\n',
        options: const GitDiffPatchOptions(maxInputCodeUnits: 10),
      );
      expect(
          inputLimited.fallbackReason, GitDiffPatchFallbackReason.inputLimit);
      expect(inputLimited.lines, isEmpty);

      final rowLimited = parseGitDiffPatch(
        'diff --git a/file b/file\n@@ -1 +1 @@\n-old\n+new\n',
        options: const GitDiffPatchOptions(maxRows: 2),
      );
      expect(rowLimited.fallbackReason, GitDiffPatchFallbackReason.rowLimit);
      expect(rowLimited.lines, isEmpty);
    });
  });

  group('GitDiffPatchView', () {
    testWidgets('renders hunk and colored, numbered source rows lazily',
        (tester) async {
      const patch = 'diff --git a/file.txt b/file.txt\n'
          '@@ -1 +1 @@\n'
          '-old\n'
          '+new\n';
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: GitDiffPatchView(patch: patch)),
      ));

      expect(find.byKey(const ValueKey('git-diff-patch-rows')), findsOneWidget);
      expect(find.text('@@ -1 +1 @@'), findsOneWidget);
      expect(find.text('old'), findsOneWidget);
      expect(find.text('new'), findsOneWidget);
      final removed = tester.widget<Container>(
        find.byKey(const ValueKey('git-diff-row-2')),
      );
      final added = tester.widget<Container>(
        find.byKey(const ValueKey('git-diff-row-3')),
      );
      expect(removed.color, const Color(0x33CF222E));
      expect(added.color, const Color(0x332DA44E));
    });

    testWidgets('keeps the full raw patch visible on parser fallback',
        (tester) async {
      const patch = 'diff --git a/image.png b/image.png\nGIT binary patch\n';
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: GitDiffPatchView(patch: patch)),
      ));

      expect(
          find.byKey(const ValueKey('git-diff-raw-fallback')), findsOneWidget);
      expect(find.textContaining('GIT binary patch'), findsOneWidget);
      expect(find.byKey(const ValueKey('git-diff-patch-rows')), findsNothing);
    });
  });
}
