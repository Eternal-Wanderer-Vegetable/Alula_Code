import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/explorer_preview.dart';

Future<void> _deleteDirectoryWithRetry(Directory directory) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (!directory.existsSync()) return;
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 49) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}

Future<void> _unmountAndDeleteTempDirectory(
  WidgetTester tester,
  Directory directory,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await _deleteDirectoryWithRetry(directory);
}

RustTextInputField _fieldForDocument(WidgetTester tester, int documentId) =>
    tester
        .widgetList<RustTextInputField>(find.byType(RustTextInputField))
        .firstWhere(
          (field) => field.inputWindow.document.id == documentId,
        );

RustTextInputField _fieldWithLabel(WidgetTester tester, String label) => tester
    .widgetList<RustTextInputField>(find.byType(RustTextInputField))
    .firstWhere((field) => field.semanticsLabel == label);

void main() {
  testWidgets('split in group shares text and retains the focused view on join',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-split-in-group');
    addTearDown(() => _unmountAndDeleteTempDirectory(tester, temp));
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final folder = Directory('${temp.path}/workspace')..createSync();
    final file = File('${folder.path}/split.txt');
    final content = List.generate(250, (i) => 'line $i').join('\n');
    file.writeAsStringSync(content);
    final base = temp.path.replaceAll(r'\', '/');
    final layoutStore = LayoutStore(path: '$base/layout.json')
      ..save(defaultLayout());
    final sessionStore = SessionStore(path: '$base/session.json');
    CommandService? commands;
    Widget workbench() => MaterialApp(
          home: WorkbenchPage(
            autoFolder: folder.path,
            layoutStore: layoutStore,
            sessionStore: sessionStore,
            keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
            onCommandServiceReady: (service) => commands = service,
          ),
        );
    await tester.pumpWidget(workbench());
    await tester.pump(const Duration(milliseconds: 700));
    Future<void> execute(String id) async {
      expect(await commands!.execute(id), CommandExecutionStatus.executed);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
    }

    Finder pane(String side) =>
        find.byKey(ValueKey('split-editor-editor-$side'));
    Finder editor(String side) => find.descendant(
          of: pane(side),
          matching: find.byType(RustTextInputField),
        );

    await execute('workbench.action.closeActiveEditor');
    await openPinnedExplorerFile(tester, find.text('split.txt').first);
    await tester.pump(const Duration(milliseconds: 700));
    await execute('workbench.action.splitEditorInGroup');
    expect(pane('first'), findsOneWidget);
    expect(pane('second'), findsOneWidget);
    expect(tester.getRect(pane('first')).right,
        lessThan(tester.getRect(pane('second')).left));
    expect(
        layoutStore.tryLoad()!.leaves.where((leaf) =>
            leaf.region == 'editor' || leaf.region.startsWith('editor-')),
        hasLength(1));
    final left = tester.widget<RustTextInputField>(editor('first'));
    final right = tester.widget<RustTextInputField>(editor('second'));
    expect(left.inputWindow.document.id, right.inputWindow.document.id);
    expect(left.inputWindow, isNot(same(right.inputWindow)));
    expect(left.scrollController, isNot(same(right.scrollController)));
    expect(right.focusNode?.hasPrimaryFocus, isTrue);

    await execute('workbench.action.focusFirstSideEditor');
    final editable = find.descendant(
      of: editor('first'),
      matching: find.byType(EditableText),
    );
    final edited = 'edited 😀 $content';
    await tester.enterText(editable, edited);
    await tester.pump(const Duration(milliseconds: 700));
    expect(left.inputWindow.text, edited);
    expect(tester.widget<RustTextInputField>(editor('second')).inputWindow.text,
        edited);
    expect(file.readAsStringSync(), content);

    final close = commands!.execute('workbench.action.closeActiveEditor');
    await tester.pumpAndSettle();
    expect(find.text('取消'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await close, CommandExecutionStatus.executed);
    expect(pane('first'), findsOneWidget);
    expect(file.readAsStringSync(), content);

    await execute('workbench.action.focusOtherSideEditor');
    expect(right.focusNode?.hasPrimaryFocus, isTrue);
    right.scrollController!.jumpTo(880);
    await tester.pump();
    expect(left.scrollController!.offset, isNot(880));
    await execute('workbench.action.toggleSplitEditorInGroupLayout');
    expect(tester.getRect(pane('first')).bottom,
        lessThan(tester.getRect(pane('second')).top));
    expect(right.scrollController!.offset, closeTo(880, 1));

    final sash = find.byKey(const ValueKey('split-editor-sash-editor'));
    final priorHeight = tester.getSize(pane('first')).height;
    await tester.drag(sash, const Offset(0, 65));
    await tester.pumpAndSettle();
    expect(tester.getSize(pane('first')).height, greaterThan(priorHeight + 20));
    expect(right.focusNode?.hasPrimaryFocus, isTrue);


    await execute('workbench.action.focusFirstSideEditor');
    await execute('workbench.action.joinEditorInGroup');
    expect(pane('first'), findsNothing);
    expect(pane('second'), findsNothing);
    final joined =
        tester.widget<RustTextInputField>(find.byType(RustTextInputField));
    expect(joined.inputWindow, same(left.inputWindow));
    expect(joined.focusNode?.hasPrimaryFocus, isTrue);
    expect(joined.inputWindow.text, edited);
    await execute('file.save');
    expect(file.readAsStringSync(), edited);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.backslash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(pane('first'), findsOneWidget);
    await execute('workbench.action.duplicateActiveEditorGroupRight');
    expect(find.byType(RustTextInputField), findsNWidgets(4));
    expect(
        tester
            .widgetList<RustTextInputField>(find.byType(RustTextInputField))
            .map((view) => view.inputWindow.document.id)
            .toSet(),
        {left.inputWindow.document.id});
    await execute('workbench.action.focusFirstSideEditor');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(workbench());
    await tester.pumpAndSettle();
    expect(find.byType(RustTextInputField), findsNWidgets(4));
    expect(tester.getRect(pane('first')).bottom,
        lessThan(tester.getRect(pane('second')).top));
    final restoredFirst = tester.widget<RustTextInputField>(find.descendant(
      of: find.byKey(const ValueKey('split-editor-editor-2-first')),
      matching: find.byType(RustTextInputField),
    ));
    await execute('workbench.action.joinEditorInGroup');
    expect(find.byType(RustTextInputField), findsNWidgets(3));
    expect(restoredFirst.focusNode!.hasPrimaryFocus, isTrue);
    expect(
        tester
            .widgetList<RustTextInputField>(find.byType(RustTextInputField))
            .every((view) => view.inputWindow.text == edited),
        isTrue);
  });

  testWidgets('group expansion keeps peers visible and can hide both side bars',
      (tester) async {
    final temp =
        Directory.systemTemp.createTempSync('alula-expand-editor-group');
    addTearDown(() => _unmountAndDeleteTempDirectory(tester, temp));
    tester.view.physicalSize = const Size(1700, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final base = temp.path.replaceAll(r'\', '/');
    final layoutStore = LayoutStore(path: '$base/layout.json')
      ..save(defaultLayout());
    CommandService? commands;
    await tester.pumpWidget(MaterialApp(
      home: WorkbenchPage(
        layoutStore: layoutStore,
        sessionStore: SessionStore(path: '$base/session.json'),
        keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
        onCommandServiceReady: (service) => commands = service,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 700));

    const toggle = 'workbench.action.toggleEditorWidths';
    const hide = 'workbench.action.minimizeOtherEditorsHideSidebar';
    Future<void> execute(String id) async {
      expect(await commands!.execute(id), CommandExecutionStatus.executed);
      await tester.pump(const Duration(milliseconds: 700));
    }

    Finder pane(String name) => find.byKey(ValueKey('wb-region-$name'));
    Finder field(String name) => find.descendant(
          of: pane(name),
          matching: find.byType(RustTextInputField),
        );
    Rect area(String name) => tester.getRect(pane(name));

    expect(commands!.isEnabled(hide), isTrue);
    await execute(hide);
    expect(pane('sidebar'), findsNothing);
    expect(commands!.isEnabled(hide), isFalse);
    await execute('view.toggleSidebar');
    await execute('workbench.action.toggleAuxiliaryBar');
    await execute('workbench.action.splitEditorRight');
    await execute('workbench.action.splitEditorDown');
    final primary = area('sidebar');
    final secondary = area('secondarySidebar');
    final regions = ['editor', 'editor-2', 'editor-3'];
    final views = {
      for (final region in regions)
        region: tester.state<RustTextInputFieldState>(field(region))
    };

    final divider = Offset(
      area('editor-2').center.dx,
      (area('editor-2').bottom + area('editor-3').top) / 2,
    );
    await tester.dragFrom(divider, const Offset(0, -100));
    await tester.pump(const Duration(milliseconds: 700));
    final rightHeight = area('editor-2').height;

    await tester.tap(field('editor'));
    await tester.pump();
    await execute(toggle);
    expect(area('editor-2').width, closeTo(220, 1));
    expect(area('editor-2').height, closeTo(rightHeight, 1));
    expect(area('sidebar'), primary);
    expect(area('secondarySidebar'), secondary);
    expect(pane('editor-3'), findsOneWidget);

    await execute(toggle);
    expect(area('editor').width, closeTo(area('editor-2').width, 1));
    expect(area('editor-2').height, closeTo(area('editor-3').height, 1));

    await tester.tap(field('editor-2'));
    await tester.pump();
    await execute(toggle);
    expect(area('editor').width, closeTo(220, 1));
    expect(area('editor-3').height, closeTo(70, 1));
    final expandedWidth = area('editor-2').width;
    await execute(hide);
    expect(pane('sidebar'), findsNothing);
    expect(pane('secondarySidebar'), findsNothing);
    expect(area('editor-2').width, greaterThan(expandedWidth + 200));
    expect(area('editor-3').height, closeTo(70, 1));
    for (final region in regions) {
      expect(tester.state<RustTextInputFieldState>(field(region)),
          same(views[region]));
    }
    final saved = layoutStore.tryLoad()!;
    expect(saved.leafOf('sidebar')!.collapsed, isTrue);
    expect(saved.leafOf('secondarySidebar')!.collapsed, isTrue);
  });

  testWidgets('locked groups route implicit opens and restore session state',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-locked-group');
    addTearDown(() => _unmountAndDeleteTempDirectory(tester, temp));
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final workspace = Directory('${temp.path}/workspace')..createSync();
    const fileNames = [
      'source-a.txt',
      'source-b.txt',
      'fallback.txt',
      'third.txt',
      'after-unlock.txt'
    ];
    for (final name in fileNames) {
      File('${workspace.path}/$name')
          .writeAsStringSync('$name synthetic content');
    }

    final base = temp.path.replaceAll(r'\', '/');
    final layoutStore = LayoutStore(path: '$base/layout.json')
      ..save(defaultLayout());
    final sessionStore = SessionStore(path: '$base/session.json');
    CommandService? commands;

    Future<void> mount() async {
      await tester.pumpWidget(MaterialApp(
        home: WorkbenchPage(
          autoFolder: workspace.path,
          layoutStore: layoutStore,
          sessionStore: sessionStore,
          keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
          onCommandServiceReady: (service) => commands = service,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 700));
    }

    Future<void> execute(String id) async {
      expect(await commands!.execute(id), CommandExecutionStatus.executed);
      await tester.pump(const Duration(milliseconds: 700));
    }

    Finder pane(String name) => find.byKey(ValueKey('wb-region-$name'));
    Finder file(String name) => find.descendant(
          of: pane('sidebar'),
          matching: find.text(name),
        );
    Future<void> open(String name) async {
      await tester.tap(file(name));
      await tester.pump(const Duration(milliseconds: 700));
    }

    List<Map<String, Object?>> groups() =>
        (sessionStore.tryLoad()!['groups'] as List)
            .cast<Map<String, Object?>>();
    Map<String, Object?> group(String region) =>
        groups().singleWhere((record) => record['region'] == region);

    Future<void> activate(String name) async {
      final id = group(name)['active'];
      await tester.tap(find.byKey(ValueKey('editor-tab-label-$name-$id')));
      await tester.pump(const Duration(milliseconds: 700));
      expect(sessionStore.tryLoad()?['focused'], name);
    }

    List<String?> paths(String region) => (group(region)['docs'] as List)
        .cast<Map<String, Object?>>()
        .map((doc) => doc['path'] as String?)
        .toList();

    const lock = 'workbench.action.lockEditorGroup';
    const unlock = 'workbench.action.unlockEditorGroup';
    await mount();
    expect(commands!.isEnabled(lock), isTrue);
    expect(commands!.isEnabled(unlock), isFalse);
    await execute('workbench.action.closeActiveEditor');
    await open('source-a.txt');
    final original = paths('editor');
    await execute(lock);
    expect(group('editor')['locked'], isTrue);
    expect(find.byKey(const ValueKey('unlock-editor-group-editor')),
        findsOneWidget);
    expect(commands!.isEnabled(lock), isFalse);
    expect(commands!.isEnabled(unlock), isTrue);

    await open('source-b.txt');
    expect(groups(), hasLength(2));
    expect(paths('editor'), original);
    expect(paths('editor-2').single, endsWith('source-b.txt'));
    expect(group('editor-2')['locked'], isNull);

    await activate('editor');
    await open('fallback.txt');
    expect(groups(), hasLength(2));
    expect(sessionStore.tryLoad()?['focused'], 'editor-2');
    expect(paths('editor-2').last, endsWith('fallback.txt'));
    await execute('workbench.action.toggleEditorGroupLock');
    expect(group('editor-2')['locked'], isTrue);

    await open('source-a.txt');
    expect(groups(), hasLength(2));
    expect(sessionStore.tryLoad()?['focused'], 'editor');
    expect(paths('editor'), original);

    await open('third.txt');
    expect(groups(), hasLength(3));
    expect(sessionStore.tryLoad()?['focused'], 'editor-3');
    expect(paths('editor-3').single, endsWith('third.txt'));
    expect(tester.getRect(pane('editor-3')).left,
        greaterThan(tester.getRect(pane('editor')).right));

    await activate('editor-2');
    final before = paths('editor-2');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await mount();
    expect(group('editor')['locked'], isTrue);
    expect(group('editor-2')['locked'], isTrue);
    expect(group('editor-3')['locked'], isNull);
    expect(paths('editor-2'), before);
    expect(commands!.isEnabled(unlock), isTrue);

    await execute('workbench.action.files.newUntitledFile');
    expect(groups(), hasLength(3));
    expect(paths('editor-2'), before);
    expect(paths('editor-3'), contains(null));

    await activate('editor-2');
    await execute(unlock);
    await open('after-unlock.txt');
    expect(groups(), hasLength(3));
    expect(group('editor-2')['locked'], isNull);
    expect(paths('editor-2').last, endsWith('after-unlock.txt'));
  });

  testWidgets('group maximization restores nested sizes and live editor views',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-group-sizes');
    addTearDown(() => _unmountAndDeleteTempDirectory(tester, temp));
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final base = temp.path.replaceAll(r'\', '/');
    final layoutStore = LayoutStore(path: '$base/layout.json')
      ..save(defaultLayout());
    CommandService? commands;
    await tester.pumpWidget(MaterialApp(
      home: WorkbenchPage(
        layoutStore: layoutStore,
        sessionStore: SessionStore(path: '$base/session.json'),
        keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
        onCommandServiceReady: (service) => commands = service,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 700));

    const maximize = 'workbench.action.toggleMaximizeEditorGroup';
    const reset = 'workbench.action.evenEditorWidths';
    Future<void> execute(String id) async {
      expect(await commands!.execute(id), CommandExecutionStatus.executed);
      await tester.pump(const Duration(milliseconds: 700));
    }

    expect(commands!.isEnabled(maximize), isFalse);
    await execute('workbench.action.splitEditorRight');
    await execute('workbench.action.splitEditorDown');
    expect(commands!.isEnabled(maximize), isTrue);

    const regions = ['editor', 'editor-2', 'editor-3'];
    Finder region(String name, {bool skipOffstage = true}) =>
        find.byKey(ValueKey('wb-region-$name'), skipOffstage: skipOffstage);
    Rect rect(String name) => tester.getRect(region(name));
    Finder field(String name, {bool skipOffstage = true}) => find.descendant(
          of: region(name, skipOffstage: skipOffstage),
          matching: find.byType(RustTextInputField, skipOffstage: skipOffstage),
        );

    final outerSash = Offset((rect('editor').right + rect('editor-2').left) / 2,
        rect('editor-2').center.dy);
    await tester.dragFrom(outerSash, const Offset(-125, 0));
    await tester.pump();
    final innerSash = Offset(rect('editor-2').center.dx,
        (rect('editor-2').bottom + rect('editor-3').top) / 2);
    await tester.dragFrom(innerSash, const Offset(0, -115));
    await tester.pump(const Duration(milliseconds: 700));
    expect(
        (rect('editor').width - rect('editor-2').width).abs(), greaterThan(60));
    expect((rect('editor-2').height - rect('editor-3').height).abs(),
        greaterThan(60));

    final dragged = {for (final name in regions) name: rect(name)};
    final shell = rect('sidebar');
    final before = layoutStore.tryLoad()!.toJson();
    final states = {
      for (final name in regions)
        name: tester.state<RustTextInputFieldState>(field(name)),
    };
    await tester.tap(field('editor-2'));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 700));

    expect(region('editor'), findsNothing);
    expect(region('editor-3'), findsNothing);
    expect(rect('editor-2'),
        dragged['editor']!.expandToInclude(dragged['editor-3']!));
    expect(rect('sidebar'), shell);
    expect(layoutStore.tryLoad()!.toJson(), before);
    for (final name in regions) {
      expect(
          tester
              .state<RustTextInputFieldState>(field(name, skipOffstage: false)),
          same(states[name]));
    }

    await tester
        .tap(find.byKey(const ValueKey('restore-editor-group-editor-2')));
    await tester.pump(const Duration(milliseconds: 700));
    for (final name in regions) {
      expect(rect(name), dragged[name]);
      expect(tester.state<RustTextInputFieldState>(field(name)),
          same(states[name]));
    }
    expect(
        tester
            .widget<RustTextInputField>(field('editor-2'))
            .focusNode
            ?.hasFocus,
        isTrue);

    await execute(maximize);
    await execute(reset);
    expect(rect('editor').width, closeTo(rect('editor-2').width, 1));
    expect(rect('editor-2').height, closeTo(rect('editor-3').height, 1));
    expect(rect('sidebar'), shell);
    expect(layoutStore.tryLoad()!.toJson(), isNot(before));
    for (final name in regions) {
      expect(tester.state<RustTextInputFieldState>(field(name)),
          same(states[name]));
    }

    await execute(maximize);
    expect(region('editor'), findsNothing);
    await execute('workbench.action.splitEditorRight');
    expect(region('editor-4'), findsOneWidget);
    for (final name in regions) {
      expect(tester.state<RustTextInputFieldState>(field(name)),
          same(states[name]));
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
      'whole group transfer preserves tabs, scroll, and shared documents',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-group-transfer');
    addTearDown(() => _unmountAndDeleteTempDirectory(tester, temp));
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final workspace = Directory('${temp.path}/workspace')..createSync();
    File('${workspace.path}/source-a.txt')
        .writeAsStringSync('first synthetic source');
    final shared = File('${workspace.path}/source-b.txt');
    shared.writeAsStringSync(
        List.generate(250, (i) => 'source line $i').join('\n'));
    final base = temp.path.replaceAll(r'\', '/');
    final layoutStore = LayoutStore(path: '$base/layout.json')
      ..save(defaultLayout());
    final sessionStore = SessionStore(path: '$base/session.json');
    CommandService? commands;
    await tester.pumpWidget(MaterialApp(
      home: WorkbenchPage(
        autoFolder: workspace.path,
        layoutStore: layoutStore,
        sessionStore: sessionStore,
        keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
        onCommandServiceReady: (service) => commands = service,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 700));

    Future<void> execute(String id) async {
      expect(await commands!.execute(id), CommandExecutionStatus.executed);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
    }

    Finder pane(String name) => find.byKey(ValueKey('wb-region-$name'));
    Finder field(String name) => find.descendant(
          of: pane(name),
          matching: find.byType(RustTextInputField),
        );
    Rect area(String name) => tester.getRect(pane(name));
    Map<String, Object?> group(String name) =>
        (sessionStore.tryLoad()!['groups'] as List)
            .cast<Map<String, Object?>>()
            .singleWhere((group) => group['region'] == name);

    await tester.tap(find.byKey(const ValueKey('close-tab-editor-1')));
    await tester.pump(const Duration(milliseconds: 500));
    await openPinnedExplorerFile(tester, find.text('source-a.txt').first);
    await tester.pump(const Duration(milliseconds: 500));
    await execute('workbench.action.toggleEditorSticky');
    await openPinnedExplorerFile(tester, find.text('source-b.txt').first);
    await tester.pump(const Duration(milliseconds: 700));
    final source = tester.widget<RustTextInputField>(field('editor'));
    source.scrollController!.jumpTo(840);
    await tester.pump();
    final originalArea = area('editor');
    final shell = area('sidebar');
    final originalTabs = group('editor');
    expect((originalTabs['docs'] as List), hasLength(2));
    expect((originalTabs['sticky'] as List), hasLength(1));
    expect(source.scrollController!.offset, closeTo(840, 1));

    final singleLayout = layoutStore.tryLoad()!.toJson();
    await execute('workbench.action.moveActiveEditorGroupLeft');
    expect(layoutStore.tryLoad()!.toJson(), singleLayout);
    await execute('workbench.action.duplicateActiveEditorGroupRight');
    final copied = tester.widget<RustTextInputField>(field('editor-2'));
    final copiedState =
        tester.state<RustTextInputFieldState>(field('editor-2'));
    expect(copied.inputWindow.document.id, source.inputWindow.document.id);
    expect(copied.inputWindow, isNot(same(source.inputWindow)));
    expect(copied.scrollController, isNot(same(source.scrollController)));
    expect(copied.scrollController!.offset, closeTo(840, 1));
    expect(copied.focusNode?.hasFocus, isTrue);
    expect(area('editor-2').right, originalArea.right);
    final copiedMetadata = group('editor-2');
    expect(copiedMetadata['sticky'], originalTabs['sticky']);
    expect(copiedMetadata['active'], originalTabs['active']);
    expect(copiedMetadata['docs'], originalTabs['docs']);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(area('editor-2').right, lessThan(area('editor').left));
    await execute('workbench.action.moveActiveEditorGroupUp');
    expect(area('editor-2').bottom, lessThan(area('editor').top));
    await execute('workbench.action.moveActiveEditorGroupDown');
    expect(area('editor-2').top, greaterThan(area('editor').bottom));
    await execute('workbench.action.moveActiveEditorGroupRight');
    expect(area('editor-2').left, greaterThan(area('editor').right));
    expect(area('sidebar'), shell);
    expect(tester.state<RustTextInputFieldState>(field('editor-2')),
        same(copiedState));
    expect(
        tester
            .widget<RustTextInputField>(field('editor-2'))
            .scrollController!
            .offset,
        closeTo(840, 1));
    expect(layoutStore.tryLoad()!.parentSplitOf('editor-2')!.axis,
        Axis.horizontal);

    await execute('workbench.action.closeActiveEditor');
    await execute('workbench.action.toggleEditorSticky');
    await execute('workbench.action.closeActiveEditor');
    expect(pane('editor-2'), findsNothing);
    final live = tester.widget<RustTextInputField>(field('editor'));
    expect(live.inputWindow, same(source.inputWindow));
    final editable = find.descendant(
        of: field('editor'), matching: find.byType(EditableText));
    await tester.enterText(editable, 'Shared document remains editable 😀');
    await tester.pump(const Duration(milliseconds: 700));
    await execute('file.save');
    expect(shared.readAsStringSync(), 'Shared document remains editable 😀');
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
    'directional move reuses editor views, creates groups, and deduplicates shared documents',
    (tester) async {
      final temp =
          Directory.systemTemp.createTempSync('alula-directional-move');
      addTearDown(() => _unmountAndDeleteTempDirectory(tester, temp));
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final workspace = Directory('${temp.path}/workspace')..createSync();
      File('${workspace.path}/main.rs')
          .writeAsStringSync('fn main() { println!("main"); }');
      File('${workspace.path}/other.rs')
          .writeAsStringSync('fn helper() { println!("other"); }');
      final base = temp.path.replaceAll(r'\', '/');
      final initialLayout = defaultLayout();
      final layoutStore = LayoutStore(path: '$base/layout.json')
        ..save(initialLayout);
      final sessionStore = SessionStore(path: '$base/session.json');
      CommandService? commands;

      await tester.pumpWidget(MaterialApp(
        home: WorkbenchPage(
          autoFolder: workspace.path,
          layoutStore: layoutStore,
          sessionStore: sessionStore,
          keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
          onCommandServiceReady: (service) => commands = service,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 600));
      expect(commands, isNotNull);

      Future<void> execute(String command) async {
        expect(
          await commands!.execute(command),
          CommandExecutionStatus.executed,
          reason: '$command is registered and callable',
        );
        await tester.pump(const Duration(milliseconds: 700));
      }

      Future<void> expectViewPreserved(
        RustTextInputField before,
        RustTextInputFieldState beforeState,
        int documentId,
      ) async {
        final after =
            tester.widget<RustTextInputField>(find.byKey(before.key!));
        expect(after.key, same(before.key));
        expect(after.inputWindow.document.id, documentId);
        expect(after.inputWindow, same(before.inputWindow));
        expect(after.focusNode, same(before.focusNode));
        expect(after.scrollController, same(before.scrollController));
        expect(
          tester.state<RustTextInputFieldState>(find.byKey(before.key!)),
          same(beforeState),
          reason: 'the same keyed input state carries selection and IME state',
        );
      }

      // Registered commands are no-ops when the focused group has no editor.
      await tester.tap(find.byKey(const ValueKey('close-tab-editor-1')));
      await tester.pump(const Duration(milliseconds: 600));
      final noActiveLayout = layoutStore.tryLoad()!.toJson();
      await execute('workbench.action.moveEditorToRightGroup');
      expect(layoutStore.tryLoad()!.toJson(), noActiveLayout);
      expect(find.byType(RustTextInputField), findsNothing);

      await openPinnedExplorerFile(tester, find.text('main.rs').first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('other.rs').first);
      await tester.pump(const Duration(milliseconds: 300));
      final otherBeforeRight = tester.widget<RustTextInputField>(
        find.byType(RustTextInputField),
      );
      final otherStateBeforeRight = tester.state<RustTextInputFieldState>(
        find.byKey(otherBeforeRight.key!),
      );
      final otherId = otherBeforeRight.inputWindow.document.id;

      await execute('workbench.action.moveEditorToRightGroup');
      await expectViewPreserved(
        otherBeforeRight,
        otherStateBeforeRight,
        otherId,
      );
      expect(sessionStore.tryLoad()?['focused'], 'editor-2');
      expect(
        tester
            .widget<Text>(
              find.byKey(ValueKey('editor-tab-label-editor-2-$otherId')),
            )
            .style
            ?.fontStyle,
        FontStyle.italic,
        reason: 'moving a clean preview preserves its preview label state',
      );
      final movedGroups = (sessionStore.tryLoad()!['groups'] as List)
          .cast<Map<String, Object?>>();
      expect(
        movedGroups
            .singleWhere((group) => group['region'] == 'editor-2')['preview'],
        otherId,
        reason: 'the destination group persists the moved preview identity',
      );
      var savedRoot = layoutStore.tryLoad()!;
      expect(savedRoot.parentSplitOf('editor-2')!.axis, Axis.horizontal);
      expect(
        savedRoot
            .parentSplitOf('editor-2')!
            .children
            .map((node) => (node as WbLeaf).region),
        ['editor', 'editor-2'],
      );
      expect(find.byType(RustTextInputField), findsNWidgets(2));

      // Move left into an existing group with a different document.
      final otherBeforeLeft = _fieldForDocument(tester, otherId);
      final otherStateBeforeLeft = tester.state<RustTextInputFieldState>(
        find.byKey(otherBeforeLeft.key!),
      );
      await execute('workbench.action.moveEditorToLeftGroup');
      await expectViewPreserved(
        otherBeforeLeft,
        otherStateBeforeLeft,
        otherId,
      );
      expect(sessionStore.tryLoad()?['focused'], 'editor');
      savedRoot = layoutStore.tryLoad()!;
      expect(
        savedRoot.leaves.where((leaf) => leaf.region.startsWith('editor')),
        hasLength(1),
      );

      // With no group above, moving up creates one above and preserves the view.
      final otherBeforeUp = _fieldForDocument(tester, otherId);
      final otherStateBeforeUp = tester.state<RustTextInputFieldState>(
        find.byKey(otherBeforeUp.key!),
      );
      await execute('workbench.action.moveEditorToAboveGroup');
      await expectViewPreserved(otherBeforeUp, otherStateBeforeUp, otherId);
      expect(sessionStore.tryLoad()?['focused'], 'editor-2');
      savedRoot = layoutStore.tryLoad()!;
      expect(savedRoot.parentSplitOf('editor-2')!.axis, Axis.vertical);
      expect(
        savedRoot
            .parentSplitOf('editor-2')!
            .children
            .map((node) => (node as WbLeaf).region),
        ['editor-2', 'editor'],
      );

      // Moving down finds the existing group and removes the empty source leaf.
      final otherBeforeDown = _fieldForDocument(tester, otherId);
      final otherStateBeforeDown = tester.state<RustTextInputFieldState>(
        find.byKey(otherBeforeDown.key!),
      );
      await execute('workbench.action.moveEditorToBelowGroup');
      await expectViewPreserved(otherBeforeDown, otherStateBeforeDown, otherId);
      expect(sessionStore.tryLoad()?['focused'], 'editor');
      savedRoot = layoutStore.tryLoad()!;
      expect(
        savedRoot.leaves.where((leaf) => leaf.region.startsWith('editor')),
        hasLength(1),
      );
      expect(
        (WbNode.fromJson(savedRoot.toJson()) as WbSplit).toJson(),
        savedRoot.toJson(),
      );

      // Splitting copies a view; moving it back to its existing document
      // focuses that view and closes the duplicate safely.
      await execute('workbench.action.splitEditorRight');
      expect(sessionStore.tryLoad()?['focused'], 'editor-2');
      expect(find.byType(RustTextInputField), findsNWidgets(2));
      await execute('workbench.action.splitEditorDown');
      expect(sessionStore.tryLoad()?['focused'], 'editor-3');
      expect(find.byType(RustTextInputField), findsNWidgets(3));

      await tester.tap(find.bySemanticsLabel('other.rs 编辑器 2'));
      await tester.pump(const Duration(milliseconds: 100));
      final belowTarget = _fieldWithLabel(tester, 'other.rs 编辑器 3');
      final belowTargetState = tester.state<RustTextInputFieldState>(
        find.byKey(belowTarget.key!),
      );
      await execute('workbench.action.moveEditorToBelowGroup');
      expect(sessionStore.tryLoad()?['focused'], 'editor-3');
      await expectViewPreserved(belowTarget, belowTargetState, otherId);

      final leftTarget = _fieldWithLabel(tester, 'other.rs 主编辑器');
      final leftTargetState = tester.state<RustTextInputFieldState>(
        find.byKey(leftTarget.key!),
      );
      await execute('workbench.action.moveEditorToLeftGroup');
      expect(sessionStore.tryLoad()?['focused'], 'editor');
      await expectViewPreserved(leftTarget, leftTargetState, otherId);
      expect(find.byType(RustTextInputField), findsOneWidget);
      expect(
        layoutStore
            .tryLoad()!
            .leaves
            .where((leaf) => leaf.region.startsWith('editor')),
        hasLength(1),
      );

      final savedSession = sessionStore.tryLoad()!;
      final groups =
          (savedSession['groups'] as List).cast<Map<String, Object?>>();
      final editor = groups.singleWhere((group) => group['region'] == 'editor');
      final paths = (editor['docs'] as List)
          .cast<Map<String, Object?>>()
          .map((doc) => doc['path'])
          .toList();
      expect(paths, hasLength(2),
          reason: 'the document appears only once in the target group');
    },
  );
}
