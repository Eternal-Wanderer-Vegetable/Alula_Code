import 'dart:io';

import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/editor/merge_result_session.dart';
import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show kMiddleMouseButton;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _base = 'head\nold\ntail\n';
const _input1 = 'head\nours\ntail\n';
const _input2 = 'head\ntheirs\ntail\n';

Future<void> _pressControl(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.pump();
}

void main() {
  late Directory temp;
  late Directory workspace;
  late File resultFile;
  late String initialResult;
  late LayoutStore layoutStore;
  late SessionStore sessionStore;
  late KeybindingsStore keybindingsStore;
  late CommandService commands;
  MergeResultSession? openedSession;
  AlulaCore? openedCore;
  AlulaDoc? openedDocument;
  OpenDoc? openedView;
  late bool Function(MergeResultEditPlan plan) applyMergePlan;

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
    openedDocument = null;
    openedView = null;
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  Future<void> mountAndOpen(
    WidgetTester tester, {
    bool makeDirty = false,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: WorkbenchPage(
        autoFolder: workspace.path,
        layoutStore: layoutStore,
        sessionStore: sessionStore,
        keybindingsStore: keybindingsStore,
        onCommandServiceReady: (service) => commands = service,
        mergeResultSessionFactory: (core, resultDocument, applyPlan) {
          if (resultDocument.name != 'merge.txt') return null;
          openedCore = core;
          final session = MergeResultSession.open(
            mergeApi: core.merge,
            resultDocument: resultDocument.doc,
            base: _base,
            input1: _input1,
            input2: _input2,
          );
          openedSession = session;
          openedDocument = resultDocument.doc;
          openedView = resultDocument;
          applyMergePlan = applyPlan;
          if (makeDirty) {
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
    await mountAndOpen(tester);
    final session = openedSession!;
    final plan = session.planResolveConflict(
      session.conflicts.single.id,
      AlulaMergeSide.input1,
    );
    expect(applyMergePlan(plan), isTrue);
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
    expect(
      () => openedDocument!.resync(),
      throwsA(isA<AlulaException>().having(
        (error) => error.code,
        'code',
        'UnknownDoc',
      )),
    );
    final releasedIdReplacement =
        openedCore!.openDoc(openedDocument!.id, initialResult);
    expect(releasedIdReplacement.resync().content, initialResult);
    releasedIdReplacement.close();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the visible result editor saves through the Rust document',
      (tester) async {
    await mountAndOpen(tester);
    final session = openedSession!;
    final field = find.descendant(
      of: find.byType(RustTextInputField),
      matching: find.byType(TextField),
    );
    final controller = tester.widget<TextField>(field).controller!;
    const editedResult = 'saved from merge result\n';
    controller.value = const TextEditingValue(
      text: editedResult,
      selection: TextSelection.collapsed(offset: editedResult.length),
    );
    await tester.pump();
    await tester.pump();
    expect(openedDocument!.resync().content, editedResult);
    expect(session.isDirty, isTrue);
    expect(session.input1Text, _input1);
    expect(session.input2Text, _input2);

    await _pressControl(tester, LogicalKeyboardKey.keyS);
    await tester.pump(const Duration(milliseconds: 350));
    expect(resultFile.readAsStringSync(), editedResult);
    expect(openedDocument!.resync().content, editedResult);
    expect(session.isDirty, isFalse);
    expect(session.input1Text, _input1);
    expect(session.input2Text, _input2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('merge plan uses undo edits and synchronizes split views',
      (tester) async {
    await mountAndOpen(tester);
    final session = openedSession!;

    expect(
        find.byKey(const ValueKey('merge-editor-pane-input1')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('merge-editor-pane-input2')), findsOneWidget);
    expect(find.byKey(const ValueKey('merge-editor-pane-base')), findsNothing);
    expect(find.byKey(const ValueKey('merge-editor-pane-result-frame')),
        findsOneWidget);

    await tester.tap(find.byTooltip('拆分编辑器').first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('merge.txt').first);
    await tester.pump(const Duration(milliseconds: 350));

    final fieldsFinder = find.byType(RustTextInputField);
    expect(fieldsFinder, findsNWidgets(2));
    expect(find.byKey(const ValueKey('merge-editor-pane-input1')),
        findsNWidgets(2));
    expect(find.byKey(const ValueKey('merge-editor-pane-input2')),
        findsNWidgets(2));
    var views = tester.widgetList<RustTextInputField>(fieldsFinder).toList();
    final documentId = views.first.inputWindow.document.id;
    expect(views[1].inputWindow.document.id, documentId);

    final plan = session.planResolveConflict(
      session.conflicts.single.id,
      AlulaMergeSide.input1,
    );
    expect(applyMergePlan(plan), isTrue);
    await tester.pump(const Duration(milliseconds: 100));

    views = tester.widgetList<RustTextInputField>(fieldsFinder).toList();
    expect(views.map((view) => view.inputWindow.document.id).toSet(),
        {documentId});
    expect(openedDocument!.resync().content, plan.projection.result);
    for (var index = 0; index < views.length; index++) {
      final textField = find.descendant(
        of: fieldsFinder.at(index),
        matching: find.byType(TextField),
      );
      expect(
        tester.widget<TextField>(textField).controller!.text,
        plan.projection.result,
      );
    }
    expect(session.unresolvedConflictCount, 0);

    final activeEditor = find.descendant(
      of: fieldsFinder.last,
      matching: find.byType(TextField),
    );
    await tester.showKeyboard(activeEditor);
    await _pressControl(tester, LogicalKeyboardKey.keyZ);
    expect(openedDocument!.resync().content, initialResult);
    expect(session.unresolvedConflictCount, 1);
    for (var index = 0; index < 2; index++) {
      final textField = find.descendant(
        of: fieldsFinder.at(index),
        matching: find.byType(TextField),
      );
      expect(
          tester.widget<TextField>(textField).controller!.text, initialResult);
    }

    await _pressControl(tester, LogicalKeyboardKey.keyY);
    expect(openedDocument!.resync().content, plan.projection.result);
    expect(session.unresolvedConflictCount, 0);
    for (var index = 0; index < 2; index++) {
      final textField = find.descendant(
        of: fieldsFinder.at(index),
        matching: find.byType(TextField),
      );
      expect(
        tester.widget<TextField>(textField).controller!.text,
        plan.projection.result,
      );
    }

    final firstEditor = find.descendant(
      of: fieldsFinder.first,
      matching: find.byType(TextField),
    );
    final firstController = tester.widget<TextField>(firstEditor).controller!;
    const manualText = 'manual edit\\nhead\\nours\\ntail\\n';
    firstController.value = const TextEditingValue(
      text: manualText,
      selection: TextSelection.collapsed(offset: manualText.length),
    );
    await tester.pump();
    await tester.pump();
    expect(openedDocument!.resync().content, manualText);
    expect(session.closePrompt.unresolvedConflictCount, 1);

    await _pressControl(tester, LogicalKeyboardKey.keyZ);
    expect(openedDocument!.resync().content, plan.projection.result);
    expect(session.unresolvedConflictCount, 0);

    await tester.tap(
      find.byKey(ValueKey('tab-$documentId')).last,
      buttons: kMiddleMouseButton,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(fieldsFinder, findsOneWidget);
    expect(
        find.byKey(const ValueKey('merge-editor-pane-input1')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('merge-editor-pane-input2')), findsOneWidget);
    expect(session.isDisposed, isFalse);
    expect(openedDocument!.resync().content, plan.projection.result);

    await tester.tap(find.byKey(ValueKey('close-tab-editor-$documentId')));
    await tester.pump();
    expect(find.byKey(const ValueKey('merge-result-close-dialog')),
        findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('merge-result-close-discard')),
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(session.isDisposed, isTrue);
    expect(
      () => openedDocument!.resync(),
      throwsA(isA<AlulaException>().having(
        (error) => error.code,
        'code',
        'UnknownDoc',
      )),
    );
    final releasedIdReplacement =
        openedCore!.openDoc(documentId, initialResult);
    expect(releasedIdReplacement.resync().content, initialResult);
    releasedIdReplacement.close();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'workspace switch invalidates inline merge group close before discard or save',
      (tester) async {
    tester.view.physicalSize = const Size(2400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final layout = defaultLayout();
    expect(layout.splitLeaf('editor', 'editor-2', Axis.horizontal), isNotNull);
    layoutStore.save(layout);
    await mountAndOpen(tester);
    final session = openedSession!;
    final document = openedDocument!;
    final field = find.descendant(
      of: find.byType(RustTextInputField),
      matching: find.byType(TextField),
    );
    const editedResult = 'unsaved merge result 😀\r\n';
    tester.widget<TextField>(field).controller!.value = const TextEditingValue(
      text: editedResult,
      selection: TextSelection.collapsed(offset: editedResult.length),
    );
    await tester.pump();
    await tester.pump();
    expect(document.resync().content, editedResult);
    expect(session.isDirty, isTrue);

    Future<void> switchWorkspace(Directory directory) async {
      final switching = commands.execute('file.openFolder');
      await tester.pumpAndSettle();
      final folderPath = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == '文件夹路径',
      );
      await tester.enterText(folderPath, directory.path);
      await tester.tap(find.widgetWithText(FilledButton, '打开'));
      await tester.pumpAndSettle();
      expect(await switching, CommandExecutionStatus.executed);
      for (var attempt = 0; attempt < 10; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();
      }
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(sessionStore.tryLoad()?['workspace'], directory.path);
    }

    for (final action in ['discard', 'save', 'overwrite']) {
      if (action != 'discard') await switchWorkspace(workspace);
      final expectedDisk = action == 'overwrite'
          ? 'external merge result 😀\r\n'
          : initialResult;
      if (action == 'overwrite') {
        resultFile.writeAsStringSync(expectedDisk);
        openedView!.diskState = DiskDocumentState.conflict;
      }
      final closeGroup =
          find.byKey(const ValueKey('open-editors-close-group-editor'));
      await tester.ensureVisible(closeGroup);
      await tester.tap(closeGroup);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('merge-result-close-dialog')),
          findsOneWidget);

      if (action == 'overwrite') {
        await tester.tap(find.byKey(const ValueKey('merge-result-close-save')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('external-conflict-dialog')),
            findsOneWidget);
      }
      // A different parent root keeps the surviving file breadcrumb relative.
      await switchWorkspace(workspace.parent);
      final pendingDialog = action == 'overwrite'
          ? 'external-conflict-dialog'
          : 'merge-result-close-dialog';
      expect(find.byKey(ValueKey(pendingDialog)), findsOneWidget);
      final confirm = action == 'overwrite'
          ? 'external-conflict-confirm-overwrite'
          : 'merge-result-close-$action';
      await tester.tap(find.byKey(ValueKey(confirm)));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('merge-result-close-dialog')),
          findsNothing);
      expect(openedSession, same(session));
      expect(session.isDisposed, isFalse);
      expect(session.isDirty, isTrue);
      expect(document.resync().content, editedResult);
      expect(document.isDirty, isTrue);
      expect(session.latestSavedResult, initialResult);
      expect(find.byKey(const ValueKey('editor-tab-strip-editor')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('open-editors-group-editor')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('tab-2')), findsOneWidget);
      expect(closeGroup, findsOneWidget);
      expect(resultFile.readAsStringSync(), expectedDisk);
      expect(
          find.byKey(const ValueKey('external-conflict-dialog')), findsNothing);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
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
