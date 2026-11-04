import 'dart:io';

import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/editor/merge_editor_open_request.dart';
import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/status_bar.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _base = 'head\nold\ntail\n';
const _input1 = 'head\nours\ntail\n';
const _input2 = 'head\ntheirs\ntail\n';

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

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('alula_merge_open_');
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
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: WorkbenchPage(
        autoFolder: workspace.path,
        layoutStore: layoutStore,
        sessionStore: sessionStore,
        keybindingsStore: keybindingsStore,
        onCommandServiceReady: (service) => commands = service,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
  }

  MergeEditorOpenRequest request({
    Uri? base,
    Uri? input1,
    Uri? input2,
    Uri? result,
  }) =>
      MergeEditorOpenRequest(
        baseUri: base ?? Uri.file(baseFile.path),
        input1Uri: input1 ?? Uri.file(input1File.path),
        input2Uri: input2 ?? Uri.file(input2File.path),
        resultUri: result ?? Uri.file(resultFile.path),
      );

  Future<CommandExecutionStatus> openMergeEditor(
    MergeEditorOpenRequest openRequest,
  ) =>
      commands!.execute('_open.mergeEditor', arguments: openRequest);

  void expectStatusDetail(WidgetTester tester, String expected) {
    final statusBar = tester.widget<AlulaStatusBar>(
      find.byType(AlulaStatusBar),
    );
    expect(statusBar.detail, contains(expected));
  }

  testWidgets('opens the projected result and repeated requests reuse it',
      (tester) async {
    await mount(tester);

    expect(
      await openMergeEditor(request()),
      CommandExecutionStatus.executed,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey('merge-editor-pane-input1')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('tab-2')), findsOneWidget);

    expect(
      await openMergeEditor(request()),
      CommandExecutionStatus.executed,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byKey(const ValueKey('merge-editor-pane-input1')),
      findsOneWidget,
    );
    expect(resultFile.readAsStringSync(), initialResult);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('navigates and accepts a conflict through F1 actions',
      (tester) async {
    await mount(tester);
    expect(commands!.isVisible('merge.goToNextUnhandledConflict'), isFalse);
    expect(
      await openMergeEditor(request()),
      CommandExecutionStatus.executed,
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(commands!.isVisible('merge.goToNextUnhandledConflict'), isTrue);
    expect(commands!.isEnabled('merge.goToNextUnhandledConflict'), isTrue);
    expect(commands!.isEnabled('merge.toggleActiveConflictInput1'), isFalse);
    expect(find.text('1 unresolved conflict'), findsOneWidget);

    await commands!.execute('merge.goToNextUnhandledConflict');
    await tester.pump();
    final editorFinder = find.byKey(const ValueKey('rust-bounded-text-input'));
    var field = tester.widget<TextField>(editorFinder);
    expect(field.controller!.selection.extentOffset, 5);
    expect(commands!.isEnabled('merge.toggleActiveConflictInput1'), isTrue);

    await commands!.execute('merge.toggleActiveConflictInput1');
    await tester.pump(const Duration(milliseconds: 100));
    field = tester.widget<TextField>(editorFinder);
    expect(field.controller!.text, _input1);
    expect(find.text('All 1 conflict handled'), findsOneWidget);
    expect(commands!.isEnabled('merge.toggleActiveConflictInput1'), isTrue);
    expect(commands!.isEnabled('merge.toggleActiveConflictInput2'), isTrue);
    expect(resultFile.readAsStringSync(), initialResult);

    expect(
      await commands!.execute('file.save'),
      CommandExecutionStatus.executed,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(resultFile.readAsStringSync(), _input1);

    await commands!.execute('editor.undo');
    await tester.pump(const Duration(milliseconds: 100));
    field = tester.widget<TextField>(editorFinder);
    expect(field.controller!.text, initialResult);
    expect(find.textContaining('1 unresolved'), findsOneWidget);
    expect(resultFile.readAsStringSync(), _input1);

    await commands!.execute('editor.redo');
    await tester.pump(const Duration(milliseconds: 100));
    field = tester.widget<TextField>(editorFinder);
    expect(field.controller!.text, _input1);
    expect(find.text('All 1 conflict handled'), findsOneWidget);
    expect(resultFile.readAsStringSync(), _input1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'bulk side actions override mixed choices in one undoable split edit and save',
      (tester) async {
    const bulkBase = '\u{feff}😀\r\nstart\r\nfirst\r\nkeep1\r\n'
        'second\r\nkeep2\r\nthird\r\nend\r\n';
    const bulkInput1 = '\u{feff}😀\r\nstart\r\nours1\r\nkeep1\r\n'
        'ours2\r\nkeep2\r\nours3\r\nend\r\n';
    const bulkInput2 = '\u{feff}😀\r\nstart\r\ntheirs1\r\nkeep1\r\n'
        'theirs2\r\nkeep2\r\ntheirs3\r\nend\r\n';
    baseFile.writeAsStringSync(bulkBase);
    input1File.writeAsStringSync(bulkInput1);
    input2File.writeAsStringSync(bulkInput2);
    final core = AlulaCore.load();
    final decodedBase = core.workspace.readFileDocument(baseFile.path).content;
    final decodedInput1 =
        core.workspace.readFileDocument(input1File.path).content;
    final decodedInput2 =
        core.workspace.readFileDocument(input2File.path).content;
    final initialProjection = core.merge.project(
      base: decodedBase,
      input1: decodedInput1,
      input2: decodedInput2,
    );
    expect(initialProjection.conflicts, hasLength(3));
    initialResult = initialProjection.result;
    resultFile.writeAsStringSync(initialResult);

    await mount(tester);
    expect(commands!.isVisible('merge.acceptAllInput1'), isFalse);
    expect(commands!.isVisible('merge.acceptAllInput2'), isFalse);
    expect(
      await openMergeEditor(request()),
      CommandExecutionStatus.executed,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(commands!.isVisible('merge.acceptAllInput1'), isTrue);
    expect(commands!.isVisible('merge.acceptAllInput2'), isTrue);
    expect(commands!.isEnabled('merge.acceptAllInput1'), isTrue);
    expect(commands!.isEnabled('merge.acceptAllInput2'), isTrue);
    expect(
      find.byTooltip('Accept All Incoming Changes from Left'),
      findsOneWidget,
    );
    expect(
      find.byTooltip('Accept All Current Changes from Right'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('拆分编辑器').first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('result.txt').first);
    await tester.pump(const Duration(milliseconds: 350));
    final mergeViews = find.byType(RustTextInputField);
    expect(mergeViews, findsNWidgets(2));
    final textFields = find.descendant(
      of: mergeViews,
      matching: find.byType(TextField),
    );
    expect(textFields, findsNWidgets(2));
    final documentIds = tester
        .widgetList<RustTextInputField>(mergeViews)
        .map((view) => view.inputWindow.document.id)
        .toSet();
    expect(documentIds, hasLength(1));

    await commands!.execute('merge.goToNextUnhandledConflict');
    await tester.pump();
    await commands!.execute('merge.toggleActiveConflictInput2');
    await tester.pump(const Duration(milliseconds: 100));
    await commands!.execute('merge.goToNextUnhandledConflict');
    await tester.pump();
    await commands!.execute('merge.toggleActiveConflictInput1');
    await tester.pump(const Duration(milliseconds: 100));
    expect(commands!.isEnabled('merge.goToNextUnhandledConflict'), isTrue);

    final mixedProjection = core.merge.project(
      base: decodedBase,
      input1: decodedInput1,
      input2: decodedInput2,
      resolutions: {
        initialProjection.conflicts[0].id: AlulaMergeSide.input2,
        initialProjection.conflicts[1].id: AlulaMergeSide.input1,
      },
    );
    final editorTextFields = tester.widgetList<TextField>(textFields).toList();
    expect(editorTextFields.map((field) => field.controller!.text),
        everyElement(mixedProjection.result));

    expect(
      await commands!.execute('merge.acceptAllInput1'),
      CommandExecutionStatus.executed,
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('All 3 conflicts handled'), findsNWidgets(2));
    expect(commands!.isEnabled('merge.acceptAllInput1'), isTrue);
    expect(commands!.isEnabled('merge.acceptAllInput2'), isTrue);
    expect(
      tester.widgetList<TextField>(textFields).map(
            (field) => field.controller!.text,
          ),
      everyElement(decodedInput1),
    );

    await commands!.execute('editor.undo');
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      tester.widgetList<TextField>(textFields).map(
            (field) => field.controller!.text,
          ),
      everyElement(mixedProjection.result),
    );
    expect(commands!.isEnabled('merge.goToNextUnhandledConflict'), isTrue);

    await commands!.execute('editor.redo');
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      tester.widgetList<TextField>(textFields).map(
            (field) => field.controller!.text,
          ),
      everyElement(decodedInput1),
    );

    expect(
      await commands!.execute('merge.acceptAllInput2'),
      CommandExecutionStatus.executed,
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      tester.widgetList<TextField>(textFields).map(
            (field) => field.controller!.text,
          ),
      everyElement(decodedInput2),
    );
    expect(
      await commands!.execute('file.save'),
      CommandExecutionStatus.executed,
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(resultFile.readAsStringSync(), decodedInput2);
    expect(
      core.workspace.readFileDocument(resultFile.path).content,
      decodedInput2,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('bulk side actions disable for stale conflict ranges',
      (tester) async {
    await mount(tester);
    await openMergeEditor(request());
    await tester.pump(const Duration(milliseconds: 300));
    final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
    await tester.enterText(editor, 'manual result\n');
    await tester.pump(const Duration(milliseconds: 100));
    expect(commands!.isVisible('merge.acceptAllInput1'), isTrue);
    expect(commands!.isEnabled('merge.acceptAllInput1'), isFalse);
    expect(commands!.isEnabled('merge.acceptAllInput2'), isFalse);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('merge-editor-accept-all-input1')),
          )
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('bulk side actions disable without conflicts and hide on close',
      (tester) async {
    baseFile.writeAsStringSync(_base);
    input1File.writeAsStringSync(_base);
    input2File.writeAsStringSync(_base);
    initialResult = _base;
    resultFile.writeAsStringSync(initialResult);
    await mount(tester);
    await openMergeEditor(request());
    await tester.pump(const Duration(milliseconds: 300));
    expect(commands!.isVisible('merge.acceptAllInput1'), isTrue);
    expect(commands!.isEnabled('merge.acceptAllInput1'), isFalse);
    expect(commands!.isEnabled('merge.acceptAllInput2'), isFalse);
    expect(find.text('No conflicts'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('close-tab-editor-2')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(commands!.isVisible('merge.acceptAllInput1'), isFalse);
    expect(commands!.isVisible('merge.acceptAllInput2'), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('wraps navigation and skips conflicts already resolved',
      (tester) async {
    const multiBase = '\u{feff}😀\r\nstart\r\nfirst\r\nkeep1\r\n'
        'second\r\nkeep2\r\nthird\r\nend\r\n';
    const multiInput1 = '\u{feff}😀\r\nstart\r\nours1\r\nkeep1\r\n'
        'ours2\r\nkeep2\r\nours3\r\nend\r\n';
    const multiInput2 = '\u{feff}😀\r\nstart\r\ntheirs1\r\nkeep1\r\n'
        'theirs2\r\nkeep2\r\ntheirs3\r\nend\r\n';
    baseFile.writeAsStringSync(multiBase);
    input1File.writeAsStringSync(multiInput1);
    input2File.writeAsStringSync(multiInput2);
    final core = AlulaCore.load();
    final decodedBase = core.workspace.readFileDocument(baseFile.path).content;
    final decodedInput1 =
        core.workspace.readFileDocument(input1File.path).content;
    final decodedInput2 =
        core.workspace.readFileDocument(input2File.path).content;
    final projection = core.merge.project(
      base: decodedBase,
      input1: decodedInput1,
      input2: decodedInput2,
    );
    expect(projection.conflicts, hasLength(3));
    initialResult = projection.result;
    resultFile.writeAsStringSync(initialResult);

    await mount(tester);
    expect(
      await openMergeEditor(request()),
      CommandExecutionStatus.executed,
    );
    await tester.pump(const Duration(milliseconds: 300));

    final editorFinder = find.byKey(const ValueKey('rust-bounded-text-input'));
    await commands!.execute('merge.goToNextUnhandledConflict');
    await tester.pump();
    var field = tester.widget<TextField>(editorFinder);
    expect(field.controller!.selection.extentOffset,
        projection.conflicts[0].resultStartUtf16);
    expect(find.text('Conflict 1 of 3 · 3 unresolved'), findsOneWidget);

    await commands!.execute('merge.goToPreviousUnhandledConflict');
    await tester.pump();
    field = tester.widget<TextField>(editorFinder);
    expect(field.controller!.selection.extentOffset,
        projection.conflicts[2].resultStartUtf16);
    expect(find.text('Conflict 3 of 3 · 3 unresolved'), findsOneWidget);

    await commands!.execute('merge.goToNextUnhandledConflict');
    await tester.pump();
    expect(find.text('Conflict 1 of 3 · 3 unresolved'), findsOneWidget);
    await commands!.execute('merge.toggleActiveConflictInput1');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Conflict 1 of 3 · 2 unresolved'), findsOneWidget);
    final afterFirstAccepted = core.merge.project(
      base: decodedBase,
      input1: decodedInput1,
      input2: decodedInput2,
      resolutions: {
        projection.conflicts[0].id: AlulaMergeSide.input1,
      },
    );

    await commands!.execute('merge.goToNextUnhandledConflict');
    await tester.pump();
    expect(find.text('Conflict 2 of 3 · 2 unresolved'), findsOneWidget);
    field = tester.widget<TextField>(editorFinder);
    expect(field.controller!.selection.extentOffset,
        afterFirstAccepted.conflicts[1].resultStartUtf16);
    await commands!.execute('merge.goToNextUnhandledConflict');
    await tester.pump();
    expect(find.text('Conflict 3 of 3 · 2 unresolved'), findsOneWidget);
    await commands!.execute('merge.goToNextUnhandledConflict');
    await tester.pump();
    expect(find.text('Conflict 2 of 3 · 2 unresolved'), findsOneWidget);

    await commands!.execute('merge.goToPreviousUnhandledConflict');
    await tester.pump();
    expect(find.text('Conflict 3 of 3 · 2 unresolved'), findsOneWidget);
    await commands!.execute('merge.toggleActiveConflictInput2');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Conflict 3 of 3 · 1 unresolved'), findsOneWidget);
    await commands!.execute('merge.goToPreviousUnhandledConflict');
    await tester.pump();
    expect(find.text('Conflict 2 of 3 · 1 unresolved'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('navigates to and accepts a zero-width insertion conflict',
      (tester) async {
    const insertionBase = '\u{feff}😀\r\nbefore\nafter\n';
    const insertionInput1 = '\u{feff}😀\r\nbefore\nours\nafter\n';
    const insertionInput2 = '\u{feff}😀\r\nbefore\ntheirs\nafter\n';
    baseFile.writeAsStringSync(insertionBase);
    input1File.writeAsStringSync(insertionInput1);
    input2File.writeAsStringSync(insertionInput2);
    final core = AlulaCore.load();
    final decodedBase = core.workspace.readFileDocument(baseFile.path).content;
    final decodedInput1 =
        core.workspace.readFileDocument(input1File.path).content;
    final decodedInput2 =
        core.workspace.readFileDocument(input2File.path).content;
    final projection = core.merge.project(
      base: decodedBase,
      input1: decodedInput1,
      input2: decodedInput2,
    );
    expect(projection.conflicts, hasLength(1));
    expect(projection.conflicts.single.resultStartUtf16,
        projection.conflicts.single.resultEndUtf16);
    initialResult = projection.result;
    resultFile.writeAsStringSync(initialResult);

    await mount(tester);
    await openMergeEditor(request());
    await tester.pump(const Duration(milliseconds: 300));
    await commands!.execute('merge.goToNextUnhandledConflict');
    await tester.pump();

    final editorFinder = find.byKey(const ValueKey('rust-bounded-text-input'));
    var field = tester.widget<TextField>(editorFinder);
    expect(field.controller!.selection.extentOffset,
        projection.conflicts.single.resultStartUtf16);
    expect(commands!.isEnabled('merge.toggleActiveConflictInput1'), isTrue);
    await commands!.execute('merge.toggleActiveConflictInput2');
    await tester.pump(const Duration(milliseconds: 100));
    field = tester.widget<TextField>(editorFinder);
    expect(field.controller!.text, decodedInput2);
    expect(find.text('All 1 conflict handled'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('manual result edits disable actions for stale conflict ranges',
      (tester) async {
    await mount(tester);
    await openMergeEditor(request());
    await tester.pump(const Duration(milliseconds: 300));

    final editorFinder = find.byKey(const ValueKey('rust-bounded-text-input'));
    await tester.enterText(editorFinder, 'manual result\n');
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Conflict locations are out of date'), findsOneWidget);
    expect(commands!.isEnabled('merge.goToNextUnhandledConflict'), isFalse);
    expect(commands!.isEnabled('merge.toggleActiveConflictInput1'), isFalse);
    expect(resultFile.readAsStringSync(), initialResult);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('rejects a mismatching result without opening or writing it',
      (tester) async {
    const mismatchingText = 'preexisting output, keep this text\n';
    resultFile.writeAsStringSync(mismatchingText);
    await mount(tester);

    expect(
      await openMergeEditor(request()),
      CommandExecutionStatus.executed,
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('merge-editor-pane-input1')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('tab-2')), findsNothing);
    expect(resultFile.readAsStringSync(), mismatchingText);
    expectStatusDetail(tester, 'result 文本与 Rust 三方合并投影不一致或已变化');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('uses current Rust text from an already open input',
      (tester) async {
    const liveInput1 = 'head\nours with an unsaved edit\ntail\n';
    final projection = AlulaCore.load().merge.project(
          base: _base,
          input1: liveInput1,
          input2: _input2,
        );
    resultFile.writeAsStringSync(projection.result);
    await mount(tester);

    await tester.tap(find.text('input1.txt').first);
    await tester.pump(const Duration(milliseconds: 200));
    final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
    await tester.enterText(editor, liveInput1);
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      await openMergeEditor(request()),
      CommandExecutionStatus.executed,
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(liveInput1), findsOneWidget);
    expect(
      find.byKey(const ValueKey('merge-editor-pane-input1')),
      findsOneWidget,
    );
    expect(input1File.readAsStringSync(), _input1);
    expect(resultFile.readAsStringSync(), projection.result);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('rejects an aliased result URI before changing documents',
      (tester) async {
    await mount(tester);

    expect(
      await openMergeEditor(request(result: Uri.file(baseFile.path))),
      CommandExecutionStatus.executed,
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('tab-2')), findsNothing);
    expect(
      find.byKey(const ValueKey('merge-editor-pane-input1')),
      findsNothing,
    );
    expect(baseFile.readAsStringSync(), _base);
    expectStatusDetail(tester, 'result 必须与 base');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reports missing arguments and rejects non-file resources',
      (tester) async {
    await mount(tester);

    expect(
      await commands!.execute('_open.mergeEditor'),
      CommandExecutionStatus.executed,
    );
    await tester.pump();
    expectStatusDetail(tester, '需要 base、input1');

    expect(
      await openMergeEditor(
        request(base: Uri.parse('https://example.invalid/base.txt')),
      ),
      CommandExecutionStatus.executed,
    );
    await tester.pump();

    expectStatusDetail(tester, '只接受绝对本地 file URI');
    expect(find.byKey(const ValueKey('tab-2')), findsNothing);
    expect(
        find.byKey(const ValueKey('merge-editor-pane-input1')), findsNothing);
    expect(resultFile.readAsStringSync(), initialResult);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('missing result resource is not created by the open route',
      (tester) async {
    final missingResult = File('${workspace.path}/missing-result.txt');
    await mount(tester);

    expect(
      await openMergeEditor(request(result: Uri.file(missingResult.path))),
      CommandExecutionStatus.executed,
    );
    await tester.pump();

    expect(missingResult.existsSync(), isFalse);
    expect(find.byKey(const ValueKey('tab-2')), findsNothing);
    expect(
        find.byKey(const ValueKey('merge-editor-pane-input1')), findsNothing);
    expectStatusDetail(tester, '读取 Merge Editor result 失败');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('rejects a dirty result document without losing its edits',
      (tester) async {
    await mount(tester);
    await tester.tap(find.text('result.txt').first);
    await tester.pump(const Duration(milliseconds: 200));
    final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
    await tester.enterText(editor, 'unsaved result text\n');
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      await openMergeEditor(request()),
      CommandExecutionStatus.executed,
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('merge-editor-pane-input1')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('tab-2')), findsOneWidget);
    expect(resultFile.readAsStringSync(), initialResult);
    expectStatusDetail(tester, 'result 文档有未保存修改');

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
