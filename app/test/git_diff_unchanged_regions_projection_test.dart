import 'package:flutter_test/flutter_test.dart';

import 'package:alula_app/git/git_diff_patch.dart';
import 'package:alula_app/git/git_diff_unchanged_regions_projection.dart';
import 'package:alula_app/git/git_diff_whitespace_projection.dart';

void main() {
  group('projectGitDiffInlineUnchangedRegions', () {
    test('folds only the middle of nine context rows between two changes', () {
      final patch = parseGitDiffPatch(_patchWithContext(9));
      final whitespaceProjection =
          projectGitDiffPatchIgnoringTrimWhitespace(patch);
      final result = projectGitDiffInlineUnchangedRegions(
        patch,
        whitespaceProjection,
      );

      expect(result.canRender, isTrue);
      expect(result.regionStartSourceRowIndices, hasLength(1));
      final collapsed = result.rows.singleWhere((row) => row.isCollapsedRegion);
      expect(collapsed.hiddenLineCount, 3);
      expect(collapsed.totalHiddenLineCount, 3);

      final visibleContext = result.rows
          .where(
              (row) => row.inlineRow?.line.kind == GitDiffPatchLineKind.context)
          .map((row) => row.inlineRow!.line.text)
          .toList();
      expect(visibleContext, [
        'context 1',
        'context 2',
        'context 3',
        'context 7',
        'context 8',
        'context 9',
      ]);
    });

    test('does not fold below threshold or fold hunk-edge context', () {
      final belowThreshold = _project(_patchWithContext(8));
      expect(belowThreshold.regionStartSourceRowIndices, isEmpty);
      expect(
          belowThreshold.rows.where((row) => row.isCollapsedRegion), isEmpty);

      final withEdges = _project(
        _patchWithContext(9, leadingContext: 2, trailingContext: 2),
      );
      expect(withEdges.regionStartSourceRowIndices, hasLength(1));
      final visible = withEdges.rows
          .where(
              (row) => row.inlineRow?.line.kind == GitDiffPatchLineKind.context)
          .map((row) => row.inlineRow!.line.text)
          .toList();
      expect(visible.take(2), ['leading 1', 'leading 2']);
      expect(visible.skip(2).take(3), ['context 1', 'context 2', 'context 3']);
      expect(visible.skip(5).take(3), ['context 7', 'context 8', 'context 9']);
      expect(visible.skip(8), ['trailing 1', 'trailing 2']);
    });

    test('keeps context runs separate at hunk boundaries', () {
      final patch = parseGitDiffPatch(_twoHunkBoundaryPatch());
      final projection = projectGitDiffPatchIgnoringTrimWhitespace(patch);
      final result = projectGitDiffInlineUnchangedRegions(patch, projection);

      expect(result.canRender, isTrue);
      expect(result.regionStartSourceRowIndices, isEmpty);
      expect(result.rows.where((row) => row.isCollapsedRegion), isEmpty);
    });

    test('does not join context across file metadata', () {
      final patch = parseGitDiffPatch(_twoFileBoundaryPatch());
      final projection = projectGitDiffPatchIgnoringTrimWhitespace(patch);
      final result = projectGitDiffInlineUnchangedRegions(patch, projection);

      expect(result.canRender, isTrue);
      expect(result.regionStartSourceRowIndices, isEmpty);
      expect(result.rows.where((row) => row.isCollapsedRegion), isEmpty);
    });

    test('reveals at most twenty rows at a time and can reveal all rows', () {
      final patch = parseGitDiffPatch(_patchWithContext(30));
      final projection = projectGitDiffPatchIgnoringTrimWhitespace(patch);
      final initial = projectGitDiffInlineUnchangedRegions(patch, projection);
      final key = initial.regionStartSourceRowIndices.single;
      final firstReveal = projectGitDiffInlineUnchangedRegions(
        patch,
        projection,
        revealedLineCountByRegionStart: {key: 20},
      );
      final remaining =
          firstReveal.rows.singleWhere((row) => row.isCollapsedRegion);
      expect(remaining.hiddenLineCount, 4);
      expect(remaining.totalHiddenLineCount, 24);

      final allRevealed = projectGitDiffInlineUnchangedRegions(
        patch,
        projection,
        revealedLineCountByRegionStart: {key: 24},
      );
      expect(allRevealed.rows.where((row) => row.isCollapsedRegion), isEmpty);
      expect(
        allRevealed.rows.map((row) => row.inlineRow!.line.rowIndex),
        projection.inlineRows.map((row) => row.line.rowIndex),
      );
      expect(
        allRevealed.rows.map((row) => row.inlineRow!.line.text),
        projection.inlineRows.map((row) => row.line.text),
      );
    });

    test('falls back as a whole when a context source mapping disagrees', () {
      final sourcePatch = parseGitDiffPatch(_patchWithContext(9));
      final otherPatch = parseGitDiffPatch(
        _patchWithContext(9).replaceFirst(' context 5\n', ' altered 5\n'),
      );
      final mismatchedProjection =
          projectGitDiffPatchIgnoringTrimWhitespace(otherPatch);
      final result = projectGitDiffInlineUnchangedRegions(
        sourcePatch,
        mismatchedProjection,
      );

      expect(
        result.fallbackReason,
        GitDiffUnchangedRegionsFallbackReason.sourceMapping,
      );
      expect(result.regionStartSourceRowIndices, isEmpty);
      expect(result.rows.where((row) => row.isCollapsedRegion), isEmpty);
      expect(
        result.rows.map((row) => row.inlineRow?.line.text),
        mismatchedProjection.inlineRows.map((row) => row.line.text),
      );
    });
  });
}

GitDiffUnchangedRegionsProjectionResult _project(String patchText) {
  final patch = parseGitDiffPatch(patchText);
  return projectGitDiffInlineUnchangedRegions(
    patch,
    projectGitDiffPatchIgnoringTrimWhitespace(patch),
  );
}

String _patchWithContext(
  int middleContext, {
  int leadingContext = 0,
  int trailingContext = 0,
}) {
  final count = middleContext + leadingContext + trailingContext + 2;
  final lines = <String>[
    'diff --git a/file.txt b/file.txt',
    '--- a/file.txt',
    '+++ b/file.txt',
    '@@ -1,$count +1,$count @@',
    for (var index = 1; index <= leadingContext; index++) ' leading $index',
    '-old one',
    '+new one',
    for (var index = 1; index <= middleContext; index++) ' context $index',
    '-old two',
    '+new two',
    for (var index = 1; index <= trailingContext; index++) ' trailing $index',
  ];
  return '${lines.join('\n')}\n';
}

String _twoHunkBoundaryPatch() => 'diff --git a/file.txt b/file.txt\n'
    '--- a/file.txt\n'
    '+++ b/file.txt\n'
    '@@ -1,6 +1,6 @@\n'
    '-old one\n'
    '+new one\n'
    ' context 1\n'
    ' context 2\n'
    ' context 3\n'
    ' context 4\n'
    ' context 5\n'
    '@@ -20,6 +20,6 @@\n'
    ' context 6\n'
    ' context 7\n'
    ' context 8\n'
    ' context 9\n'
    ' context 10\n'
    '-old two\n'
    '+new two\n';

String _twoFileBoundaryPatch() => 'diff --git a/first.txt b/first.txt\n'
    '--- a/first.txt\n'
    '+++ b/first.txt\n'
    '@@ -1,6 +1,6 @@\n'
    '-old one\n'
    '+new one\n'
    ' context 1\n'
    ' context 2\n'
    ' context 3\n'
    ' context 4\n'
    ' context 5\n'
    'diff --git a/second.txt b/second.txt\n'
    '--- a/second.txt\n'
    '+++ b/second.txt\n'
    '@@ -20,6 +20,6 @@\n'
    ' context 6\n'
    ' context 7\n'
    ' context 8\n'
    ' context 9\n'
    ' context 10\n'
    '-old two\n'
    '+new two\n';
