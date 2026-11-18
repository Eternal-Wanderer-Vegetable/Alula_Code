import 'dart:io';

import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

RustTextInputField _field(WidgetTester tester, int id) => tester
    .widgetList<RustTextInputField>(find.byType(RustTextInputField))
    .firstWhere((field) => field.inputWindow.document.id == id);

void main() {
  late Directory temp;
  late File mainFile;
  late File otherFile;
  late CommandService commands;

  Future<void> mount(WidgetTester tester) async {
    temp = Directory.systemTemp.createTempSync('alula-group-close-lifetime');
    final workspace = Directory('${temp.path}/workspace')..createSync();
    final src = Directory('${workspace.path}/src')..createSync();
    mainFile = File('${src.path}/main.rs')
      ..writeAsStringSync('fn main() {\r\n    // 😀\r\n}\r\n');
    otherFile = File('${workspace.path}/other.rs')
      ..writeAsStringSync('fn other() {}\n');
    final layout = defaultLayout();
    expect(layout.splitLeaf('editor', 'editor-2', Axis.horizontal), isNotNull);
    final layoutStore = LayoutStore(path: '${temp.path}/layout.json')
      ..save(layout);
    final sessionStore = SessionStore(path: '${temp.path}/session.json')
      ..save({
        'v': 1,
        'focused': 'editor',
        'workspace': workspace.path,
        'groups': [
          {
            'region': 'editor',
            'active': 10,
            'docs': [
              {'id': 10, 'path': mainFile.path},
            ],
          },
          {
            'region': 'editor-2',
            'active': 20,
            'docs': [
              {'id': 20, 'path': otherFile.path},
            ],
          },
        ],
      });
    tester.view.physicalSize = const Size(2400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() async {
        for (var attempt = 0; attempt < 50; attempt++) {
          if (!temp.existsSync()) return;
          try {
            await temp.delete(recursive: true);
            return;
          } on FileSystemException {
            if (attempt == 49) rethrow;
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }
      });
    });
    await tester.pumpWidget(MaterialApp(
      home: WorkbenchPage(
        autoFolder: workspace.path,
        layoutStore: layoutStore,
        sessionStore: sessionStore,
        keybindingsStore: KeybindingsStore(path: '${temp.path}/keys.json'),
        onCommandServiceReady: (service) => commands = service,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    _field(tester, 10).focusNode!.requestFocus();
    await tester.pump();
    expect(
        find.byKey(const ValueKey('editor-tab-strip-editor')), findsOneWidget);
    expect(find.byKey(const ValueKey('editor-tab-strip-editor-2')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  }

  for (final visitBreadcrumbs in [false, true]) {
    testWidgets(
        'closeAllGroups releases mounted split editor views safely '
        '(breadcrumb focus: $visitBreadcrumbs)', (tester) async {
      await mount(tester);
      final mainBytes = mainFile.readAsBytesSync();
      final otherBytes = otherFile.readAsBytesSync();
      final main = _field(tester, 10);
      final other = _field(tester, 20);
      void listener() {}
      if (visitBreadcrumbs) {
        expect(await commands.execute('breadcrumbs.focus'),
            CommandExecutionStatus.executed);
        await tester.pumpAndSettle();
        expect(commands.context['breadcrumbsActive'], isTrue);
        expect(await commands.execute('breadcrumbs.selectEditor'),
            CommandExecutionStatus.executed);
        await tester.pumpAndSettle();
        expect(commands.context['breadcrumbsActive'], isFalse);
      }
      expect(await commands.execute('workbench.action.closeAllGroups'),
          CommandExecutionStatus.executed);
      // Logical close releases Rust documents immediately, but controllers must
      // survive until layout finishes reparenting the retained editor region.
      for (final field in [main, other]) {
        expect(
            () => field.inputWindow.document.resync(),
            throwsA(isA<AlulaException>()
                .having((e) => e.code, 'code', 'UnknownDoc')));
        field.scrollController!.addListener(listener);
        field.scrollController!.removeListener(listener);
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(RustTextInputField), findsNothing);
      // The existing close policy preserves one empty group (here editor-2).
      expect(
          find.byKey(const ValueKey('editor-tab-strip-editor')), findsNothing);
      expect(find.byKey(const ValueKey('editor-tab-strip-editor-2')),
          findsOneWidget);
      for (final field in [main, other]) {
        expect(() => field.scrollController!.addListener(listener),
            throwsAssertionError,
            reason: 'removed view controllers are disposed after the frame');
      }
      expect(mainFile.readAsBytesSync(), mainBytes);
      expect(otherFile.readAsBytesSync(), otherBytes);
    });
  }

  testWidgets('batch close releases a shared document after its final view',
      (tester) async {
    await mount(tester);
    final original = _field(tester, 10);
    expect(await commands.execute('workbench.action.splitEditorRight'),
        CommandExecutionStatus.executed);
    await tester.pumpAndSettle();
    final sharedViews = tester
        .widgetList<RustTextInputField>(find.byType(RustTextInputField))
        .where((field) => field.inputWindow.document.id == 10)
        .toList();
    expect(sharedViews, hasLength(2));
    expect(sharedViews.last.inputWindow.document,
        same(original.inputWindow.document));
    expect(sharedViews.last.scrollController,
        isNot(same(sharedViews.first.scrollController)));
    final fields = tester
        .widgetList<RustTextInputField>(find.byType(RustTextInputField))
        .toList();
    expect(await commands.execute('workbench.action.closeAllGroups'),
        CommandExecutionStatus.executed);
    expect(
        () => original.inputWindow.document.resync(),
        throwsA(
            isA<AlulaException>().having((e) => e.code, 'code', 'UnknownDoc')));
    // Teardown in the pending frame must still dispose every removed view's
    // controller, including both views of the same document.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    void listener() {}
    for (final field in fields) {
      expect(() => field.scrollController!.addListener(listener),
          throwsAssertionError);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('dirty Cancel preserves both split views and their controllers',
      (tester) async {
    await mount(tester);
    final main = _field(tester, 10);
    final other = _field(tester, 20);
    final mainBytes = mainFile.readAsBytesSync();
    final otherBytes = otherFile.readAsBytesSync();
    const edited = 'fn main() {\r\n    // unsaved 😀\r\n}\r\n';
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: edited,
      selection: TextSelection.collapsed(offset: edited.length),
    ));
    await tester.pump();
    await tester.pump();
    expect(main.inputWindow.document.resync().content, edited);
    expect(main.inputWindow.document.isDirty, isTrue);
    final closing = commands.execute('workbench.action.closeAllGroups');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-close-dirty-dialog')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('editor-close-cancel')));
    await tester.pumpAndSettle();
    expect(await closing, CommandExecutionStatus.executed);
    expect(_field(tester, 10).inputWindow, same(main.inputWindow));
    expect(_field(tester, 20).inputWindow, same(other.inputWindow));
    expect(_field(tester, 10).scrollController, same(main.scrollController));
    expect(_field(tester, 20).scrollController, same(other.scrollController));
    expect(main.inputWindow.document.resync().content, edited);
    expect(main.inputWindow.document.isDirty, isTrue);
    void listener() {}
    main.scrollController!.addListener(listener);
    main.scrollController!.removeListener(listener);
    other.scrollController!.addListener(listener);
    other.scrollController!.removeListener(listener);
    expect(mainFile.readAsBytesSync(), mainBytes);
    expect(otherFile.readAsBytesSync(), otherBytes);
    expect(tester.takeException(), isNull);
  });
}
