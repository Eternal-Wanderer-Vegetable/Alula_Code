import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alula_app/git/git_diff_patch.dart';
import 'package:alula_app/git/git_diff_patch_view.dart';
import 'package:alula_app/git/git_diff_word_highlights.dart';

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

  group('computeGitDiffPatchWordChanges', () {
    test('pairs replaced rows and maps UTF-16 ranges to both sides', () {
      final patch = parseGitDiffPatch(
        'diff --git a/file.rs b/file.rs\n'
        '@@ -1 +1 @@\n'
        '-😀 oldValue\n'
        '+😀 newValue\n',
      );

      final result = computeGitDiffPatchWordChanges(patch);
      final removed = result.changesForRow(2)!;
      final added = result.changesForRow(3)!;

      expect(result.pairedCount, 1);
      expect(result.computedPairCount, 1);
      expect(result.fallbackPairCount, 0);
      expect(removed.fallbackReason, isNull);
      expect(added.fallbackReason, isNull);
      expect(removed.ranges.single.startUtf16, 3);
      expect(added.ranges.single.startUtf16, 3);
      expect(removed.ranges.single.endUtf16, '😀 oldValue'.length);
      expect(added.ranges.single.endUtf16, '😀 newValue'.length);
    });

    test('pairs rows only within each contiguous change block', () {
      final patch = parseGitDiffPatch(
        'diff --git a/file.txt b/file.txt\n'
        '@@ -1,3 +1,3 @@\n'
        '-oldA\n'
        '+newA\n'
        ' same\n'
        '-oldB\n'
        '+newB\n',
      );

      final result = computeGitDiffPatchWordChanges(patch);

      expect(result.pairedCount, 2);
      expect(result.changesForRow(2), isNotNull);
      expect(result.changesForRow(3), isNotNull);
      expect(result.changesForRow(5), isNotNull);
      expect(result.changesForRow(6), isNotNull);
      expect(result.changesForRow(4), isNull);
    });

    test('keeps excess insertions and deletions unpaired', () {
      final patch = parseGitDiffPatch(
        'diff --git a/file.txt b/file.txt\n'
        '@@ -1,1 +1,2 @@\n'
        '-old\n'
        '+first\n'
        '+second\n',
      );

      final result = computeGitDiffPatchWordChanges(patch);

      expect(result.pairedCount, 1);
      expect(result.changesForRow(2), isNotNull);
      expect(result.changesForRow(3), isNotNull);
      expect(result.changesForRow(4), isNull);
    });

    test('keeps no-newline markers inside the replacement block', () {
      final patch = parseGitDiffPatch(
        'diff --git a/file.txt b/file.txt\n'
        '@@ -1 +1 @@\n'
        '-old'
        '\n\\ No newline at end of file\n'
        '+new'
        '\n\\ No newline at end of file\n',
      );

      final result = computeGitDiffPatchWordChanges(patch);

      expect(result.pairedCount, 1);
      expect(result.changesForRow(2), isNotNull);
      expect(result.changesForRow(4), isNotNull);
    });

    test('falls back to full paired lines when aggregate input is exceeded',
        () {
      final patch = parseGitDiffPatch(
        'diff --git a/file.txt b/file.txt\n'
        '@@ -1 +1 @@\n'
        '-old text\n'
        '+new text\n',
      );

      final result = computeGitDiffPatchWordChanges(
        patch,
        options: const GitDiffPatchWordOptions(
          maxAggregateInputCodeUnits: 2,
        ),
      );

      final removed = result.changesForRow(2)!;
      final added = result.changesForRow(3)!;
      expect(result.computedPairCount, 0);
      expect(result.fallbackPairCount, 1);
      expect(
        removed.fallbackReason,
        GitDiffPatchWordFallbackReason.aggregateInputLimit,
      );
      expect(removed.ranges.single.endUtf16, 'old text'.length);
      expect(added.ranges.single.endUtf16, 'new text'.length);
    });

    test('records per-pair work fallback as whole-line changes', () {
      final patch = parseGitDiffPatch(
        'diff --git a/file.txt b/file.txt\n'
        '@@ -1 +1 @@\n'
        '-old text\n'
        '+new text\n',
      );

      final result = computeGitDiffPatchWordChanges(
        patch,
        options: const GitDiffPatchWordOptions(maxAggregateWork: 1),
      );

      expect(result.fallbackPairCount, 1);
      expect(
        result.changesForRow(2)!.fallbackReason,
        GitDiffPatchWordFallbackReason.wordWorkLimit,
      );
      expect(result.changesForRow(2)!.ranges.single.endUtf16, 8);
    });

    test('caps paired rows and marks remaining pairs explicitly', () {
      final patch = parseGitDiffPatch(
        'diff --git a/file.txt b/file.txt\n'
        '@@ -1,2 +1,2 @@\n'
        '-oldA\n'
        '+newA\n'
        '-oldB\n'
        '+newB\n',
      );

      final result = computeGitDiffPatchWordChanges(
        patch,
        options: const GitDiffPatchWordOptions(
          maxPairs: 1,
          maxAggregateWork: 1000,
        ),
      );

      expect(result.pairedCount, 2);
      expect(result.computedPairCount, 1);
      expect(result.fallbackPairCount, 1);
      expect(
        result.changesForRow(4)!.fallbackReason,
        GitDiffPatchWordFallbackReason.pairLimit,
      );
      expect(result.changesForRow(4)!.ranges.single.endUtf16, 4);
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

    testWidgets('renders changed word portions in selectable source rows',
        (tester) async {
      const patch = 'diff --git a/file.txt b/file.txt\n'
          '@@ -1 +1 @@\n'
          '-fooBar\n'
          '+fooBaz\n';
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: GitDiffPatchView(patch: patch)),
      ));

      final removed = tester.widget<SelectableText>(
        find.byKey(const ValueKey('git-diff-text-2')),
      );
      final added = tester.widget<SelectableText>(
        find.byKey(const ValueKey('git-diff-text-3')),
      );
      final removedSpans = removed.textSpan!.children!.cast<TextSpan>();
      final addedSpans = added.textSpan!.children!.cast<TextSpan>();

      expect(removed.textSpan!.toPlainText(), 'fooBar');
      expect(added.textSpan!.toPlainText(), 'fooBaz');
      expect(
        removedSpans.any(
            (span) => span.style?.backgroundColor == const Color(0xFF70272B)),
        isTrue,
      );
      expect(
        addedSpans.any(
            (span) => span.style?.backgroundColor == const Color(0xFF285E37)),
        isTrue,
      );
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
