import 'dart:io';

import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/editor/merge_result_session.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _base = 'head\nold\ntail\n';
const _input1 = 'head\nours\ntail\n';
const _input2 = 'head\ntheirs\ntail\n';

void main() {
  late Directory temp;
  late Directory workspace;
  late File resultFile;
  late String initialResult;
  late LayoutStore layoutStore;
  late SessionStore sessionStore;
  late KeybindingsStore keybindingsStore;
  MergeResultSession? openedSession;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('alula_merge_close_');
    workspace = Directory('${temp.path}/workspace')..createSync();
    final projection = AlulaCore.load().merge.project(
          base: _base,
          input1: _input1,
          input2: _input2,
        );
    initialResult = projection.result;
    resultFile = File('${workspace.path}/merge.txt')
      ..writeAsStringSync(initialResult);
    final root = temp.path.replaceAll(r'\', '/');
    layoutStore = LayoutStore(path: '$root/layout.json');
    sessionStore = SessionStore(path: '$root/session.json');
    keybindingsStore = KeybindingsStore(path: '$root/keybindings.json');
    openedSession = null;
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  Future<void> mountAndOpen(
    WidgetTester tester, {
    bool makeDirty = false,
    bool resolveConflict = false,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: WorkbenchPage(
        autoFolder: workspace.path,
        layoutStore: layoutStore,
        sessionStore: sessionStore,
        keybindingsStore: keybindingsStore,
        mergeResultSessionFactory: (core, resultDocument) {
          if (resultDocument.name != 'merge.txt') return null;
          final session = MergeResultSession.open(
            mergeApi: core.merge,
            resultDocument: resultDocument.doc,
            base: _base,
            input1: _input1,
            input2: _input2,
          );
          openedSession = session;
          if (resolveConflict) {
            final plan = session.planResolveConflict(
              session.conflicts.single.id,
              AlulaMergeSide.input1,
            );
            final version = resultDocument.doc.applyWith(
              plan.baseVersion,
              plan.operations,
            );
            session.applyPlan(plan, appliedVersion: version);
            resultDocument.replaceInputWindow(0);
          } else if (makeDirty) {
            resultDocument.doc.setSavepoint('different saved text');
          }
          return session;
        },
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('merge.txt').first);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(const ValueKey('tab-2')), findsOneWidget);
  }

  Future<void> requestClose(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('close-tab-editor-2')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('merge-result-close-dialog')),
      findsOneWidget,
    );
  }

  testWidgets('dirty unresolved result can cancel then save with conflicts',
      (tester) async {
    await mountAndOpen(tester, makeDirty: true);
    final session = openedSession!;

    await requestClose(tester);
    expect(find.text('保存并保留未解冲突'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('merge-result-close-cancel')),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('tab-2')), findsOneWidget);
    expect(session.isDisposed, isFalse);

    await requestClose(tester);
    await tester.tap(find.byKey(const ValueKey('merge-result-close-save')));
    await tester.pump(const Duration(milliseconds: 350));

    expect(resultFile.readAsStringSync(), initialResult);
    expect(find.byKey(const ValueKey('tab-2')), findsNothing);
    expect(session.isDisposed, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('discard restores the latest saved merge result before close',
      (tester) async {
    await mountAndOpen(tester, resolveConflict: true);
    final session = openedSession!;
    expect(session.isDirty, isTrue);
    expect(session.unresolvedConflictCount, 0);

    await requestClose(tester);
    await tester.tap(
      find.byKey(const ValueKey('merge-result-close-discard')),
    );
    await tester.pump(const Duration(milliseconds: 350));

    expect(resultFile.readAsStringSync(), initialResult);
    expect(find.byKey(const ValueKey('tab-2')), findsNothing);
    expect(session.isDisposed, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('clean result with unresolved conflicts requires confirmation',
      (tester) async {
    await mountAndOpen(tester);
    final session = openedSession!;
    expect(session.isDirty, isFalse);
    expect(session.unresolvedConflictCount, greaterThan(0));

    await requestClose(tester);
    await tester.tap(
      find.byKey(const ValueKey('merge-result-close-with-conflicts')),
    );
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(const ValueKey('tab-2')), findsNothing);
    expect(session.isDisposed, isTrue);

    await tester.tap(find.text('merge.txt').first);
    await tester.pump(const Duration(milliseconds: 350));
    final reopenedSession = openedSession!;
    expect(identical(reopenedSession, session), isFalse);
    expect(reopenedSession.isDisposed, isFalse);
    await tester.tap(find.byKey(const ValueKey('close-tab-editor-3')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('merge-result-close-with-conflicts')),
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(const ValueKey('tab-3')), findsNothing);
    expect(reopenedSession.isDisposed, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
