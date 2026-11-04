import 'dart:io';

import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/editor/merge_editor_open_request.dart';
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
