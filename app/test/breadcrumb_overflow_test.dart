import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/workbench/breadcrumb_navigation.dart';
import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _segment(String region, int index) =>
    find.byKey(ValueKey('breadcrumbs-segment-$region-$index'));

Finder _viewport(String region) => find.descendant(
      of: find.byWidgetPredicate((widget) =>
          widget is BreadcrumbNavigation && widget.region == region),
      matching: find.byType(SingleChildScrollView),
    );

void _expectVisible(WidgetTester tester, String region, int index,
    {bool oversized = false}) {
  final viewport = tester.getRect(_viewport(region));
  final segment = tester.getRect(_segment(region, index));
  expect(segment.left, greaterThanOrEqualTo(viewport.left - 1));
  if (oversized) {
    expect(segment.left, lessThan(viewport.right));
  } else {
    expect(segment.right, lessThanOrEqualTo(viewport.right + 1));
  }
  expect(tester.widget<Semantics>(_segment(region, index)).properties.selected,
      isTrue);
}

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

void main() {
  testWidgets(
      'horizontal scrolling retains every segment and reveals last and previous focus',
      (tester) async {
    final navigation = BreadcrumbNavigationController();
    addTearDown(navigation.dispose);
    final longComponent = List.filled(24, 'long😀component').join();
    final segments = ['C:', 'workspace', longComponent, 'src', 'main.rs'];
    final selected = <int>[];
    var width = 180.0;
    var resource = 'first';
    late StateSetter rebuild;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          rebuild = setState;
          return SizedBox(
            width: width,
            height: 22,
            child: BreadcrumbNavigation(
              region: 'test',
              resource: resource,
              segments: segments,
              controller: navigation,
              onSelect: (index) async => selected.add(index),
              onRevealDirectory: (_) async {},
              onSelectEditor: () {},
            ),
          );
        }),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(_viewport('test')).width, width);
    final scrollView = tester.widget<SingleChildScrollView>(_viewport('test'));
    expect(scrollView.scrollDirection, Axis.horizontal);
    final scroll = scrollView.controller!;
    expect(scroll.position.maxScrollExtent, greaterThan(width));
    for (final segment in segments) {
      expect(find.text(segment), findsOneWidget);
    }
    final initialEnd = tester.getRect(_segment('test', 4)).left;
    await tester.drag(_viewport('test'), const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    expect(tester.getRect(_segment('test', 4)).left, lessThan(initialEnd));
    navigation.focusLast('test');
    await tester.pumpAndSettle();
    _expectVisible(tester, 'test', 4);
    navigation.move(-1);
    await tester.pumpAndSettle();
    _expectVisible(tester, 'test', 3);
    navigation.move(-1);
    await tester.pumpAndSettle();
    _expectVisible(tester, 'test', 2, oversized: true);
    // The full oversized label remains reachable by a pointer scroll.
    final beforeDrag = scroll.offset;
    await tester.drag(_viewport('test'), const Offset(-100, 0));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(beforeDrag));
    final manuallyScrolled = scroll.offset;
    await tester.pump(const Duration(seconds: 2));
    expect(scroll.offset, manuallyScrolled,
        reason:
            'focus reveal is event-driven and does not fight manual scroll');
    navigation.move(-1);
    await tester.pumpAndSettle();
    _expectVisible(tester, 'test', 1);
    navigation.move(-1);
    await tester.pumpAndSettle();
    _expectVisible(tester, 'test', 0);
    navigation.move(-1);
    await tester.pumpAndSettle();
    _expectVisible(tester, 'test', 0);
    for (var index = 0; index < segments.length; index++) {
      if (index > 0) navigation.move(1);
      await tester.pumpAndSettle();
      navigation.selectFocused();
      await tester.pumpAndSettle();
    }
    expect(selected, [0, 1, 2, 3, 4]);
    rebuild(() => width = 100);
    await tester.pumpAndSettle();
    _expectVisible(tester, 'test', 4);
    navigation.move(-1);
    navigation.move(-1);
    navigation.focusLast('test');
    await tester.pumpAndSettle();
    _expectVisible(tester, 'test', 4);
    final focus = tester
        .widget<Focus>(find.byKey(const ValueKey('breadcrumbs-focus-test')))
        .focusNode!;
    // A queued reveal must not address a resource replaced before layout.
    navigation.move(-1);
    rebuild(() {
      resource = 'second';
      segments.replaceRange(0, segments.length, ['new😀.rs']);
    });
    await tester.pumpAndSettle();
    expect(navigation.isActive, isFalse);
    expect(tester.takeException(), isNull);
    navigation.focusLast('test');
    await tester.pumpAndSettle();
    _expectVisible(tester, 'test', 0);
    // Also dispose with a pending post-frame reveal.
    navigation.move(-1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(scroll.hasClients, isFalse);
    expect(() => scroll.addListener(() {}), throwsAssertionError);
    expect(() => focus.addListener(() {}), throwsAssertionError);
    navigation.focusLast('test');
    expect(navigation.isActive, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'two groups retain old absolute paths after sibling workspace switch without breadcrumb overflow',
      (tester) async {
    final temp =
        Directory.systemTemp.createTempSync('alula-breadcrumb-overflow');
    final workspace = Directory('${temp.path}/workspace')..createSync();
    final sibling = Directory('${temp.path}/sibling')..createSync();
    final longComponent = List.filled(10, 'wide😀name').join();
    final src = Directory('${workspace.path}/$longComponent')..createSync();
    const original = 'fn main() {\r\n    // 😀\r\n}\r\n';
    const edited = 'fn main() {\r\n    // unsaved 😀\r\n}\r\n';
    final mainFile = File('${src.path}/main.rs')..writeAsStringSync(original);
    final otherFile = File('${src.path}/other.rs')
      ..writeAsStringSync('fn other() {}\r\n');
    final disk = mainFile.readAsBytesSync();
    final otherDisk = otherFile.readAsBytesSync();
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
    tester.view.physicalSize = const Size(4000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => _deleteDirectoryWithRetry(temp));
    });
    late CommandService commands;
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
    expect(tester.takeException(), isNull);
    RustTextInputField field(int id) => tester
        .widgetList<RustTextInputField>(find.byType(RustTextInputField))
        .firstWhere((field) => field.inputWindow.document.id == id);
    final editor = field(10);
    final window = editor.inputWindow;
    final originalContent = window.document.resync().content;
    final otherWindow = field(20).inputWindow;
    editor.focusNode!.requestFocus();
    await tester.pump();
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: edited,
      selection: TextSelection(baseOffset: 25, extentOffset: 27),
    ));
    await tester.pump();
    await tester.pump();
    final before = window.document.resync();
    expect(before.content, edited);
    final selection = window.initialValue.selection;
    final undo = commands.context['editorCanUndo'];
    final redo = commands.context['editorCanRedo'];

    final switching = commands.execute('file.openFolder');
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byWidgetPredicate((widget) =>
            widget is TextField && widget.decoration?.labelText == '文件夹路径'),
        sibling.path);
    await tester.tap(find.widgetWithText(FilledButton, '打开'));
    await tester.pumpAndSettle();
    expect(await switching, CommandExecutionStatus.executed);
    for (var attempt = 0; attempt < 10; attempt++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }
    expect(sessionStore.tryLoad()?['workspace'], sibling.path);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1400, 1000);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final region in ['editor', 'editor-2']) {
      final breadcrumbs = tester.widget<BreadcrumbNavigation>(
          find.byWidgetPredicate((widget) =>
              widget is BreadcrumbNavigation && widget.region == region));
      expect(breadcrumbs.segments, contains(longComponent));
      expect(breadcrumbs.segments.length, greaterThan(2),
          reason: 'old resources outside the sibling root use absolute paths');
      expect(_viewport(region), findsOneWidget);
      final scrollable = find.descendant(
          of: _viewport(region), matching: find.byType(Scrollable));
      expect(tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
          greaterThan(0));
      breadcrumbs.controller.focusLast(region);
      await tester.pumpAndSettle();
      _expectVisible(tester, region, breadcrumbs.segments.length - 1);
      breadcrumbs.controller.move(-1);
      await tester.pumpAndSettle();
      _expectVisible(tester, region, breadcrumbs.segments.length - 2,
          oversized: true);
      breadcrumbs.controller.selectEditor();
      await tester.pumpAndSettle();
    }
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('editor-tab-strip-editor')),
      matching: find.byKey(const ValueKey('tab-10')),
    ));
    await tester.pumpAndSettle();
    expect(field(10).inputWindow, same(window));
    expect(field(20).inputWindow, same(otherWindow));
    expect(window.document.resync().content, before.content);
    expect(window.document.version, before.version);
    expect(window.initialValue.selection, selection);
    expect(window.document.isDirty, isTrue);
    expect(commands.context['editorCanUndo'], undo);
    expect(commands.context['editorCanRedo'], redo);
    expect(mainFile.readAsBytesSync(), disk);
    expect(otherFile.readAsBytesSync(), otherDisk);
    await commands.execute('editor.undo');
    await tester.pumpAndSettle();
    expect(window.document.resync().content, originalContent);
    await commands.execute('editor.redo');
    await tester.pumpAndSettle();
    expect(window.document.resync().content, edited);
  });
}
