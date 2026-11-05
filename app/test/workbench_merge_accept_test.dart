import 'dart:io';

import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/editor/merge_editor_open_request.dart';
import 'package:alula_app/editor/merge_result_session.dart';
import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _base = 'head\nold\ntail\n';
const _input1 = 'head\nours\ntail\n';
const _input2 = 'head\ntheirs\ntail\n';

Future<void> _pressAcceptShortcut(WidgetTester tester) async {
  final modifier = defaultTargetPlatform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
  await tester.pump();
}

void main() {
  late Directory temp;
  late Directory workspace;
  late File baseFile;
  late File input1File;
  late File input2File;
  late File resultFile;
  late String initialResult;
  late LayoutStore layoutStore;
  late SessionStore sessionStore;
  late KeybindingsStore keybindingsStore;
  CommandService? commands;
  MergeResultSession? openedSession;
  AlulaDoc? openedDocument;
  OpenDoc? openedView;
  bool Function(MergeResultEditPlan plan)? applyMergePlan;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('alula_merge_accept_');
    workspace = Directory('${temp.path}/workspace')..createSync();
    baseFile = File('${workspace.path}/base.txt')..writeAsStringSync(_base);
    input1File = File('${workspace.path}/input1.txt')
      ..writeAsStringSync(_input1);
    input2File = File('${workspace.path}/input2.txt')
      ..writeAsStringSync(_input2);
    final projection = AlulaCore.load().merge.project(
          base: _base,
          input1: _input1,
          input2: _input2,
        );
    initialResult = projection.result;
    resultFile = File('${workspace.path}/result.txt')
      ..writeAsStringSync(initialResult);
    final root = temp.path.replaceAll(r'\', '/');
    layoutStore = LayoutStore(path: '$root/layout.json');
    sessionStore = SessionStore(path: '$root/session.json');
    keybindingsStore = KeybindingsStore(path: '$root/keybindings.json');
    commands = null;
    openedSession = null;
    openedDocument = null;
    openedView = null;
    applyMergePlan = null;
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  Future<void> mountAndOpen(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: WorkbenchPage(
        autoFolder: workspace.path,
        layoutStore: layoutStore,
        sessionStore: sessionStore,
        keybindingsStore: keybindingsStore,
        onCommandServiceReady: (service) => commands = service,
        mergeResultSessionFactory: (core, resultDocument, applyPlan) {
          if (resultDocument.name != 'result.txt') return null;
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
          return session;
        },
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    expect(commands!.isVisible('mergeEditor.acceptMerge'), isFalse);
    final request = MergeEditorOpenRequest(
      baseUri: Uri.file(baseFile.path),
      input1Uri: Uri.file(input1File.path),
      input2Uri: Uri.file(input2File.path),
      resultUri: Uri.file(resultFile.path),
    );
    expect(
      await commands!.execute('_open.mergeEditor', arguments: request),
      CommandExecutionStatus.executed,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(RustTextInputField), findsOneWidget);
    expect(commands!.isVisible('mergeEditor.acceptMerge'), isTrue);
    expect(commands!.isEnabled('mergeEditor.acceptMerge'), isTrue);
  }

  Future<void> focusResultEditor(WidgetTester tester) async {
    await tester.tap(find.byType(TextField).last);
    await tester.pump();
  }

  testWidgets('Ctrl+Enter confirms or cancels unresolved completion safely',
      (tester) async {
    await mountAndOpen(tester);
    final session = openedSession!;
    final document = openedDocument!;
    await focusResultEditor(tester);

    await _pressAcceptShortcut(tester);
    expect(find.byKey(const ValueKey('merge-editor-accept-merge-dialog')),
        findsOneWidget);
    expect(find.textContaining('是否完成“result.txt”'), findsOneWidget);
    expect(find.text('仍有冲突也完成合并'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('merge-editor-accept-merge-cancel')),
    );
    await tester.pump();
    expect(resultFile.readAsStringSync(), initialResult);
    expect(document.resync().content, initialResult);
    expect(document.isDirty, isFalse);
    expect(session.isDisposed, isFalse);
    expect(find.byType(RustTextInputField), findsOneWidget);

    await _pressAcceptShortcut(tester);
    await tester.tap(
      find.byKey(const ValueKey('merge-editor-accept-merge-confirm')),
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(resultFile.readAsStringSync(), initialResult);
    expect(session.isDisposed, isTrue);
    expect(
        find.byKey(const ValueKey('merge-editor-pane-input1')), findsNothing);
    expect(commands!.isVisible('mergeEditor.acceptMerge'), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('resolved dirty result saves without confirmation then closes',
      (tester) async {
    await mountAndOpen(tester);
    final session = openedSession!;
    final applyPlan = applyMergePlan!;
    expect(session.unresolvedConflictCount, 1);
    final plan = session.planAcceptAll(AlulaMergeSide.input1);
    expect(applyPlan(plan), isTrue);
    expect(session.unresolvedConflictCount, 0);
    expect(session.isDirty, isTrue);
    await focusResultEditor(tester);

    await _pressAcceptShortcut(tester);
    expect(find.byKey(const ValueKey('merge-editor-accept-merge-dialog')),
        findsNothing);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(resultFile.readAsStringSync(), _input1);
    expect(session.isDisposed, isTrue);
    expect(
        find.byKey(const ValueKey('merge-editor-pane-input1')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('external disk conflict cancellation keeps Merge Editor open',
      (tester) async {
    await mountAndOpen(tester);
    final session = openedSession!;
    final applyPlan = applyMergePlan!;
    final plan = session.planAcceptAll(AlulaMergeSide.input1);
    expect(applyPlan(plan), isTrue);
    expect(session.unresolvedConflictCount, 0);
    await focusResultEditor(tester);

    const externalText = 'changed outside Alula\n';
    resultFile.writeAsStringSync(externalText);
    openedView!.diskState = DiskDocumentState.conflict;

    await _pressAcceptShortcut(tester);
    expect(
        find.byKey(const ValueKey('external-conflict-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('external-conflict-cancel')));
    await tester.pump(const Duration(milliseconds: 150));

    expect(resultFile.readAsStringSync(), externalText);
    expect(session.isDisposed, isFalse);
    expect(find.byType(RustTextInputField), findsOneWidget);
    expect(commands!.isVisible('mergeEditor.acceptMerge'), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
