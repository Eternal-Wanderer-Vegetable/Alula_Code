import 'dart:ui' show SemanticsAction;

import 'package:alula_app/workbench/status_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final status = find.byKey(const ValueKey('status-problems'));

  Widget bar(ProblemsStatusCounts counts, VoidCallback toggle) {
    return MaterialApp(
      home: Scaffold(
        bottomNavigationBar: AlulaStatusBar(
          state: WbSyncState.synced,
          detail: '就绪',
          lspStatus: 'LSP 在线',
          problems: counts,
          tabCount: 1,
          abiVersion: 46,
          syncCount: 0,
          panelCollapsed: true,
          onTogglePanel: () {},
          onToggleProblems: toggle,
        ),
      ),
    );
  }

  List<String> countText(WidgetTester tester) => tester
      .widgetList<Text>(
          find.descendant(of: status, matching: find.byType(Text)))
      .map((text) => text.data!)
      .toList();

  test('counts errors, warnings and information from one diagnostic snapshot',
      () {
    final counts = ProblemsStatusCounts.fromDiagnostics(const [
      {'severity': 1},
      {'severity': 1},
      {'severity': 2},
      {'severity': 3},
      {},
      {'severity': 4},
      {'severity': 9},
    ]);

    expect((counts.errors, counts.warnings, counts.infos), (2, 1, 2));
    expect(counts.total, 5);
    expect(counts.description, '错误 2，警告 1，信息 2');
  });

  testWidgets('shows zero errors and warnings with an actionable status entry',
      (tester) async {
    var toggles = 0;
    await tester.pumpWidget(bar(const ProblemsStatusCounts(), () => toggles++));

    expect(countText(tester), ['0', '0']);
    expect(find.byIcon(Icons.info_outline), findsNothing);
    expect(find.byTooltip('没有问题'), findsOneWidget);

    final label = find.bySemanticsLabel('没有问题');
    expect(label, findsOneWidget);
    expect(
        tester.getSemantics(label).getSemanticsData().hasAction(
              SemanticsAction.tap,
            ),
        isTrue);
    await tester.tap(status);
    expect(toggles, 1);
  });

  testWidgets('packs large counts while keeping exact hover and spoken totals',
      (tester) async {
    await tester.pumpWidget(bar(
      const ProblemsStatusCounts(errors: 999, warnings: 1000, infos: 9999),
      () {},
    ));

    expect(countText(tester), ['999', '1K', '9K']);
    const first = '错误 999，警告 1000，信息 9999';
    expect(find.byTooltip(first), findsOneWidget);
    expect(find.bySemanticsLabel(first), findsOneWidget);

    await tester.pumpWidget(bar(
      const ProblemsStatusCounts(errors: 0, warnings: 10000, infos: 12000),
      () {},
    ));
    expect(countText(tester), ['0', '10K+', '10K+']);
    const second = '警告 10000，信息 12000';
    expect(find.byTooltip(second), findsOneWidget);
    expect(find.bySemanticsLabel(second), findsOneWidget);
    expect(find.bySemanticsLabel(first), findsNothing);
  });
}
