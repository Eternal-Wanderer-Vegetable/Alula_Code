import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alula_app/git/git_diff_patch.dart';
import 'package:alula_app/git/git_diff_patch_view.dart';

void main() {
  const oldLines = [
    '  final firstValue = 1; ',
    '\tfinal secondValue = 2;\t',
    'final thirdValue = 3;',
  ];
  const newLines = [
    'final firstValue = 1;',
    'final secondValue = 2;',
    'final thirdValue = 3;',
  ];

  testWidgets(
      'moved-block borders and connectors default off, opt in only for side-by-side',
      (tester) async {
    _setDesktopSize(tester);
    final patch = _splitHunkPatch(oldLines: oldLines, newLines: newLines);
    final parsed = parseGitDiffPatch(patch);
    final removed = parsed.lines.firstWhere(
      (line) => line.kind == GitDiffPatchLineKind.removed,
    );
    final added = parsed.lines.firstWhere(
      (line) => line.kind == GitDiffPatchLineKind.added,
    );
    await tester.pumpWidget(_app(patch));

    await tester.tap(find.text('并排'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('git-diff-toggle-moved-blocks')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('git-diff-moved-block-connectors')),
        findsNothing);
    expect(
      find.byKey(ValueKey('git-diff-moved-old-cell-${removed.rowIndex}')),
      findsNothing,
    );

    await tester
        .tap(find.byKey(const ValueKey('git-diff-toggle-moved-blocks')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('git-diff-moved-block-connectors')),
        findsOneWidget);
    final oldCell = tester.widget<Container>(
      find.byKey(ValueKey('git-diff-moved-old-cell-${removed.rowIndex}')),
    );
    final newCell = tester.widget<Container>(
      find.byKey(ValueKey('git-diff-moved-new-cell-${added.rowIndex}')),
    );
    expect(oldCell.foregroundDecoration, isA<BoxDecoration>());
    expect(newCell.foregroundDecoration, isA<BoxDecoration>());

    await tester.tap(find.text('内联'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('git-diff-patch-rows')), findsOneWidget);
    expect(find.byKey(const ValueKey('git-diff-moved-block-connectors')),
        findsNothing);

    await tester.tap(find.text('并排'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('git-diff-moved-block-connectors')),
        findsOneWidget);
  });

  testWidgets('patch updates clear prior moved-block overlays', (tester) async {
    _setDesktopSize(tester);
    var patch = _splitHunkPatch(oldLines: oldLines, newLines: newLines);
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return Scaffold(body: GitDiffPatchView(patch: patch));
        },
      ),
    ));

    await tester.tap(find.text('并排'));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('git-diff-toggle-moved-blocks')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('git-diff-moved-block-connectors')),
        findsOneWidget);

    update(() {
      patch = _sameHunkPatch(oldLines);
    });
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('git-diff-moved-block-connectors')),
        findsNothing);
    expect(find.byKey(const ValueKey('git-diff-side-by-side-rows')),
        findsOneWidget);
  });

  testWidgets('parser fallback never exposes moved-block decorations',
      (tester) async {
    _setDesktopSize(tester);
    const patch = 'diff --git a/image.png b/image.png\nGIT binary patch\n';
    await tester.pumpWidget(_app(patch));

    expect(find.byKey(const ValueKey('git-diff-raw-fallback')), findsOneWidget);
    expect(find.byKey(const ValueKey('git-diff-toggle-moved-blocks')),
        findsNothing);
    expect(find.byKey(const ValueKey('git-diff-moved-block-connectors')),
        findsNothing);
  });
}

Widget _app(String patch) => MaterialApp(
      home: Scaffold(body: GitDiffPatchView(patch: patch)),
    );

void _setDesktopSize(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 700);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

String _splitHunkPatch({
  required List<String> oldLines,
  required List<String> newLines,
}) =>
    [
      'diff --git a/lib/move.dart b/lib/move.dart',
      'index 1111111..2222222 100644',
      '--- a/lib/move.dart',
      '+++ b/lib/move.dart',
      '@@ -10,${oldLines.length + 1} +2,1 @@',
      ...oldLines.map((line) => '-$line'),
      ' keep-before',
      '@@ -30,1 +40,${newLines.length + 1} @@',
      ' keep-after',
      ...newLines.map((line) => '+$line'),
    ].join('\n');

String _sameHunkPatch(List<String> lines) => [
      'diff --git a/lib/move.dart b/lib/move.dart',
      '--- a/lib/move.dart',
      '+++ b/lib/move.dart',
      '@@ -10,${lines.length} +40,${lines.length} @@',
      ...lines.map((line) => '-$line'),
      ...lines.map((line) => '+$line'),
    ].join('\n');
