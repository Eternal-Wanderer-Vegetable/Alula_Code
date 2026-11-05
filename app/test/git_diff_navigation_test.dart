import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alula_app/git/git_diff_navigation.dart';
import 'package:alula_app/git/git_diff_patch.dart';
import 'package:alula_app/git/git_diff_patch_view.dart';
import 'package:alula_app/git/git_diff_side_by_side.dart';

void main() {
  group('computeGitDiffPatchChanges', () {
    test('groups contiguous replacements and splits at context rows', () {
      const patch = 'diff --git a/file.txt b/file.txt\n'
          'index 1..2 100644\n'
          '--- a/file.txt\n'
          '+++ b/file.txt\n'
          '@@ -1,4 +1,4 @@\n'
          '-old one\n'
          '+new one\n'
          ' context\n'
          '-old two\n'
          '+new two\n'
          ' tail\n';

      final result = parseGitDiffPatch(patch);
      final changes = computeGitDiffPatchChanges(result);

      expect(result.canRender, isTrue);
      expect(changes, hasLength(2));
      expect(changes[0].originalLineNumber, 1);
      expect(changes[0].modifiedLineNumber, 1);
      expect(changes[1].originalLineNumber, 3);
      expect(changes[1].modifiedLineNumber, 3);
      expect(
        changes.map((change) => change.firstRowIndex),
        orderedEquals([5, 8]),
      );
    });

    test('keeps no-newline markers inside a change block', () {
      const patch = 'diff --git a/file.txt b/file.txt\n'
          '--- a/file.txt\n'
          '+++ b/file.txt\n'
          '@@ -1 +1 @@\n'
          '-old\n'
          '\\ No newline at end of file\n'
          '+new\n';

      final changes = computeGitDiffPatchChanges(parseGitDiffPatch(patch));

      expect(changes, hasLength(1));
      expect(changes.single.originalLineNumber, 1);
      expect(changes.single.modifiedLineNumber, 1);
    });

    test('finds pure insertion and deletion changes across hunks', () {
      const patch = 'diff --git a/file.txt b/file.txt\n'
          '--- a/file.txt\n'
          '+++ b/file.txt\n'
          '@@ -1 +1,2 @@\n'
          ' context\n'
          '+inserted\n'
          '@@ -9 +10,0 @@\n'
          '-deleted\n';

      final changes = computeGitDiffPatchChanges(parseGitDiffPatch(patch));

      expect(changes, hasLength(2));
      expect(changes[0].originalLineNumber, isNull);
      expect(changes[0].modifiedLineNumber, 2);
      expect(changes[1].originalLineNumber, 9);
      expect(changes[1].modifiedLineNumber, isNull);
    });

    test('returns no targets for unchanged text or parser fallback', () {
      const unchanged = 'diff --git a/file.txt b/file.txt\n'
          '--- a/file.txt\n'
          '+++ b/file.txt\n'
          '@@ -1 +1 @@\n'
          ' same\n';
      const unsupported = 'diff --git a/image.png b/image.png\n'
          'GIT binary patch\n';

      expect(
        computeGitDiffPatchChanges(parseGitDiffPatch(unchanged)),
        isEmpty,
      );
      expect(
        computeGitDiffPatchChanges(parseGitDiffPatch(unsupported)),
        isEmpty,
      );
    });
  });

  group('GitDiffPatchView navigation', () {
    testWidgets('buttons wrap and reveal the current inline change',
        (tester) async {
      final patch = _twoChangePatch();
      final changes = computeGitDiffPatchChanges(parseGitDiffPatch(patch));
      await tester.pumpWidget(_navigationHarness(patch));

      final next = find.byKey(const ValueKey('git-diff-next-change'));
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);
      expect(
        _inlineRow(changes[0].firstRowIndex).evaluate().single.widget,
        isA<Container>().having(
          (container) => container.foregroundDecoration,
          'current change decoration',
          isNotNull,
        ),
      );
      _expectCentered(
        tester,
        _inlineRow(changes[0].firstRowIndex),
        find.byKey(const ValueKey('git-diff-patch-rows')),
      );

      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      final secondTarget = _inlineRow(changes[1].firstRowIndex);
      expect(secondTarget, findsOneWidget);
      _expectCentered(
        tester,
        secondTarget,
        find.byKey(const ValueKey('git-diff-patch-rows')),
      );

      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('git-diff-previous-change')));
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
    });

    testWidgets('F7 and Shift+F7 navigate and announce the active change',
        (tester) async {
      final patch = _twoChangePatch();
      final changes = computeGitDiffPatchChanges(parseGitDiffPatch(patch));
      await tester.pumpWidget(_navigationHarness(patch));

      await tester.sendKeyEvent(LogicalKeyboardKey.f7);
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);
      final semantics = tester.widget<Semantics>(
        find.byKey(const ValueKey('git-diff-change-count')),
      );
      expect(semantics.properties.liveRegion, isTrue);
      expect(semantics.properties.label, contains('差异 1 / 2'));
      expect(
        semantics.properties.label,
        contains('原文第 ${changes[0].originalLineNumber} 行'),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f7);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      expect(_inlineRow(changes[1].firstRowIndex), findsOneWidget);
    });

    testWidgets('navigation targets the aligned row in side-by-side mode',
        (tester) async {
      final patch = _twoChangePatch();
      final changes = computeGitDiffPatchChanges(parseGitDiffPatch(patch));
      final rows = computeGitDiffSideBySideRows(parseGitDiffPatch(patch)).rows;
      final targetIndex = rows.indexWhere(
        (row) =>
            row.originalLine?.rowIndex == changes[1].firstRowIndex ||
            row.modifiedLine?.rowIndex == changes[1].firstRowIndex,
      );
      await tester.pumpWidget(_navigationHarness(patch));
      await tester.tap(find.text('并排'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('git-diff-next-change')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('git-diff-next-change')));
      await tester.pumpAndSettle();

      expect(find.text('2 / 2'), findsOneWidget);
      final target = find.byKey(
        ValueKey('git-diff-side-by-side-row-$targetIndex'),
      );
      expect(target, findsOneWidget);
      final container = tester.widget<Container>(target);
      expect(container.foregroundDecoration, isNotNull);
      _expectCentered(
        tester,
        target,
        find.byKey(const ValueKey('git-diff-side-by-side-rows')),
      );
    });

    testWidgets('patch updates reset the selected index and disable empty diff',
        (tester) async {
      await tester.pumpWidget(_navigationHarness(_twoChangePatch()));
      await tester.tap(find.byKey(const ValueKey('git-diff-next-change')));
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);

      await tester.pumpWidget(_navigationHarness(_unchangedPatch()));
      expect(find.text('0 / 0'), findsOneWidget);
      final next = tester.widget<IconButton>(
        find.byKey(const ValueKey('git-diff-next-change')),
      );
      expect(next.onPressed, isNull);
      final previous = tester.widget<IconButton>(
        find.byKey(const ValueKey('git-diff-previous-change')),
      );
      expect(previous.onPressed, isNull);
    });
  });
}

Widget _navigationHarness(String patch) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 760,
          height: 180,
          child: GitDiffPatchView(patch: patch),
        ),
      ),
    );

Finder _inlineRow(int rowIndex) =>
    find.byKey(ValueKey('git-diff-row-$rowIndex'));

void _expectCentered(
  WidgetTester tester,
  Finder target,
  Finder list,
) {
  final difference =
      (tester.getCenter(target).dy - tester.getCenter(list).dy).abs();
  expect(difference, lessThanOrEqualTo(10));
}

String _twoChangePatch() {
  final lines = <String>[
    'diff --git a/file.txt b/file.txt',
    '--- a/file.txt',
    '+++ b/file.txt',
    '@@ -1,24 +1,24 @@',
  ];
  for (var line = 1; line <= 24; line++) {
    if (line == 2 || line == 22) {
      lines
        ..add('-old line $line')
        ..add('+new line $line');
    } else {
      lines.add(' context $line');
    }
  }
  return '${lines.join('\n')}\n';
}

String _unchangedPatch() => 'diff --git a/file.txt b/file.txt\n'
    '--- a/file.txt\n'
    '+++ b/file.txt\n'
    '@@ -1 +1 @@\n'
    ' same\n';
