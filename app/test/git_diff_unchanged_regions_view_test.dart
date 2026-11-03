import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alula_app/git/git_diff_patch.dart';
import 'package:alula_app/git/git_diff_patch_view.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('GitDiffPatchView unchanged regions', () {
    testWidgets('folding is opt-in and reveals at most twenty rows',
        (tester) async {
      _setTestSize(tester);
      final patchText = _patchWithContext(30);
      final patch = parseGitDiffPatch(patchText);
      final firstHiddenSourceRow =
          patch.lines.singleWhere((line) => line.text == 'context 4').rowIndex;
      await tester.pumpWidget(_harness(patchText));

      expect(
        find.byKey(const ValueKey('git-diff-toggle-unchanged-regions')),
        findsOneWidget,
      );
      expect(find.text('context 4'), findsOneWidget);
      expect(
        find.byKey(
          ValueKey('git-diff-expand-unchanged-$firstHiddenSourceRow'),
        ),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('git-diff-toggle-unchanged-regions')),
      );
      await tester.pumpAndSettle();
      final expand = find.byKey(
        ValueKey('git-diff-expand-unchanged-$firstHiddenSourceRow'),
      );
      expect(expand, findsOneWidget);
      expect(find.text('context 4'), findsNothing);
      expect(find.text('context 30'), findsOneWidget);
      expect(
        tester.getSemantics(expand),
        matchesSemantics(
          isButton: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
          label: '未变更上下文已折叠，剩余 24 行；激活后最多展开 20 行',
        ),
      );

      await tester.tap(expand);
      await tester.pumpAndSettle();
      expect(find.text('context 4'), findsOneWidget);
      expect(find.text('context 23'), findsOneWidget);
      expect(find.text('context 24'), findsNothing);
      expect(
        find.byKey(
          ValueKey('git-diff-expand-unchanged-$firstHiddenSourceRow'),
        ),
        findsOneWidget,
      );
      expect(find.text('… 展开剩余 4 行未变更内容'), findsOneWidget);
    });

    testWidgets('patch updates reset folding and partial reveal state',
        (tester) async {
      _setTestSize(tester);
      final firstPatch = _patchWithContext(30);
      final firstHiddenSourceRow = parseGitDiffPatch(firstPatch)
          .lines
          .singleWhere((line) => line.text == 'context 4')
          .rowIndex;
      await tester.pumpWidget(_harness(firstPatch));
      await tester.tap(
        find.byKey(const ValueKey('git-diff-toggle-unchanged-regions')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          ValueKey('git-diff-expand-unchanged-$firstHiddenSourceRow'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('… 展开剩余 4 行未变更内容'), findsOneWidget);

      await tester.pumpWidget(_harness(_patchWithContext(30, label: 'next')));
      await tester.pumpAndSettle();

      expect(find.text('context 4'), findsOneWidget);
      expect(find.text('context 24'), findsOneWidget);
      expect(find.textContaining('展开剩余'), findsNothing);
    });

    testWidgets('change navigation highlights visible rows after folding',
        (tester) async {
      _setTestSize(tester);
      final patchText = _patchWithContext(9);
      final secondChangeSourceRow = parseGitDiffPatch(patchText)
          .lines
          .singleWhere((line) => line.text == 'old two')
          .rowIndex;
      await tester.pumpWidget(_harness(patchText));
      await tester.tap(
        find.byKey(const ValueKey('git-diff-toggle-unchanged-regions')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('git-diff-next-change')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('git-diff-next-change')),
      );
      await tester.pumpAndSettle();

      final target =
          find.byKey(ValueKey('git-diff-row-$secondChangeSourceRow'));
      expect(target, findsOneWidget);
      expect(
        tester.widget<Container>(target).foregroundDecoration,
        isNotNull,
      );
    });
  });
}

void _setTestSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(600, 1100);
  tester.view.devicePixelRatio = 1;
}

Widget _harness(String patch) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 600,
          height: 1100,
          child: GitDiffPatchView(
            key: const ValueKey('unchanged-region-view'),
            patch: patch,
          ),
        ),
      ),
    );

String _patchWithContext(int middleContext, {String label = 'file'}) {
  final count = middleContext + 2;
  final lines = <String>[
    'diff --git a/$label.txt b/$label.txt',
    '--- a/$label.txt',
    '+++ b/$label.txt',
    '@@ -1,$count +1,$count @@',
    '-old one',
    '+new one',
    for (var index = 1; index <= middleContext; index++) ' context $index',
    '-old two',
    '+new two',
  ];
  return '${lines.join('\n')}\n';
}
