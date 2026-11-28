import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/native_drag_drop.dart';

Finder _row(String region, int id) =>
    find.byKey(ValueKey('open-editors-doc-$region-$id'));

Finder _group(String region) =>
    find.byKey(ValueKey('open-editors-group-$region'));

Finder _tab(String region, int id) => find.descendant(
      of: find.byKey(ValueKey('editor-tab-strip-$region')),
      matching: find.byKey(ValueKey('tab-$id')),
    );

const _dirtyDialog = ValueKey('editor-close-dirty-dialog');
const _closeSaved = ValueKey('open-editors-group-close-saved');
const _closeAll = ValueKey('open-editors-group-close-all');

void main() {
  setUpAll(mockNativeDragDrop);

  late Directory temp;
  late Directory workspace;
  late LayoutStore layoutStore;
  late SessionStore sessionStore;
  late Map<int, File> files;

  String baseOf() => temp.path.replaceAll(r'\', '/');
  String original(int id) => 'fn original_$id() {}\n';

  Future<void> prepare(WidgetTester tester) async {
    temp = Directory.systemTemp.createTempSync('alula-open-editors-close');
    workspace = Directory('${temp.path}/workspace')..createSync();
    layoutStore = LayoutStore(path: '${baseOf()}/layout.json');
    sessionStore = SessionStore(path: '${baseOf()}/session.json');
    files = {};
    tester.view.physicalSize = const Size(2400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => _deleteDirectoryWithRetry(temp));
    });
  }

  void seed({
    required List<int> target,
    List<int> other = const [20],
    List<int> sticky = const [],
    String sortOrder = 'editorOrder',
  }) {
    for (final id in {...target, ...other}) {
      files[id] = File('${workspace.path}/doc_$id.rs')
        ..writeAsStringSync(original(id));
    }
    final layout = defaultLayout();
    expect(layout.splitLeaf('editor', 'editor-2', Axis.horizontal), isNotNull);
    layoutStore.save(layout);
    sessionStore.save({
      'v': 1,
      'focused': 'editor-2',
      'workspace': workspace.path,
      'openEditorsSortOrder': sortOrder,
      'groups': [
        {
          'region': 'editor',
          'active': target.first,
          'sticky': sticky,
          'docs': [
            for (final id in target) {'id': id, 'path': files[id]!.path},
          ],
        },
        {
          'region': 'editor-2',
          'active': other.last,
          'docs': [
            for (final id in other) {'id': id, 'path': files[id]!.path},
          ],
        },
      ],
    });
  }

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: WorkbenchPage(
        autoFolder: workspace.path,
        layoutStore: layoutStore,
        sessionStore: sessionStore,
        keybindingsStore:
            KeybindingsStore(path: '${baseOf()}/keybindings.json'),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
  }

  Future<void> finishIo(WidgetTester tester) async {
    for (var attempt = 0; attempt < 10; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
  }

  Future<void> activate(WidgetTester tester, String region, int id) async {
    await tester.ensureVisible(_row(region, id));
    await tester.tap(_row(region, id));
    await tester.pumpAndSettle();
  }

  Future<void> edit(
      WidgetTester tester, String region, int id, String text) async {
    await activate(tester, region, id);
    final field = tester
        .widgetList<RustTextInputField>(find.byType(RustTextInputField))
        .firstWhere((field) => field.inputWindow.document.id == id);
    field.focusNode!.requestFocus();
    await tester.pump();
    tester.testTextInput.updateEditingValue(TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    ));
    await tester.pump();
    await tester.pump();
    expect(field.inputWindow.document.resync().content, text);
    expect(field.inputWindow.document.isDirty, isTrue);
  }

  Future<void> openMenu(WidgetTester tester, String region) async {
    // ensureVisible on a document row may scroll the lazy list far enough to
    // unmount the first group heading. Reveal it before resolving the finder.
    final scrollable = find.descendant(
      of: find.byKey(const ValueKey('open-editors-section')),
      matching: find.byType(Scrollable),
    );
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pump();
    await tester.ensureVisible(_group(region));
    await tester.tap(_group(region), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.byKey(_closeSaved), findsOneWidget);
    expect(find.byKey(_closeAll), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(_closeSaved)).dy,
        lessThan(tester.getTopLeft(find.byKey(_closeAll)).dy));
    expect(
        find.descendant(
            of: find.byKey(_closeSaved), matching: find.text('关闭已保存')),
        findsOneWidget);
    expect(
        find.descendant(of: find.byKey(_closeAll), matching: find.text('全部关闭')),
        findsOneWidget);
  }

  Future<void> close(WidgetTester tester, ValueKey<String> action) async {
    await openMenu(tester, 'editor');
    await tester.tap(find.byKey(action));
    await tester.pumpAndSettle();
  }

  void expectOpen(String region, Iterable<int> ids) {
    for (final id in ids) {
      expect(_row(region, id), findsOneWidget,
          reason: '$region/$id stays open');
      expect(_tab(region, id), findsOneWidget);
    }
  }

  void expectClosed(String region, Iterable<int> ids) {
    for (final id in ids) {
      expect(_row(region, id), findsNothing, reason: '$region/$id closes');
      expect(_tab(region, id), findsNothing);
    }
  }

  void expectDiskUnchanged() {
    for (final entry in files.entries) {
      expect(entry.value.readAsStringSync(), original(entry.key));
    }
  }

  Finder activeSplit(String region) => find.descendant(
        of: find.byKey(ValueKey('editor-tab-strip-$region')),
        matching: find.byTooltip('拆分编辑器'),
      );

  Future<void> chooseGroupToolbar(
    WidgetTester tester,
    String region,
    String action,
  ) async {
    final button = find.byKey(ValueKey('editor-group-more-actions-$region'));
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('editor-group-more-$action')));
    await tester.pumpAndSettle();
  }

  testWidgets('group toolbar picker uses the clicked group and restores focus',
      (tester) async {
    await prepare(tester);
    seed(target: [10], other: [10, 20]);
    await mount(tester);

    expect(activeSplit('editor-2'), findsOneWidget);
    await chooseGroupToolbar(tester, 'editor', 'show-opened');
    final picker = find.byKey(const ValueKey('quick-input'));
    expect(picker, findsOneWidget);
    final query =
        find.descendant(of: picker, matching: find.byType(EditableText));
    expect(tester.widget<EditableText>(query).controller.text, 'edt active ');
    expect(find.byKey(const ValueKey('qi-doc_10.rs')), findsOneWidget);
    expect(find.byKey(const ValueKey('qi-doc_20.rs')), findsNothing);
    expect(activeSplit('editor'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quick-input')), findsNothing);
    expect(activeSplit('editor-2'), findsOneWidget);

    await chooseGroupToolbar(tester, 'editor', 'show-opened');
    await tester.tap(find.byKey(const ValueKey('qi-doc_10.rs')));
    await tester.pumpAndSettle();
    expect(activeSplit('editor'), findsOneWidget);
    expect(_tab('editor-2', 20), findsOneWidget);
    await activate(tester, 'editor-2', 20);
    await chooseGroupToolbar(tester, 'editor', 'close-saved');
    await finishIo(tester);
    expect(_tab('editor', 10), findsNothing);
    expect(_tab('editor-2', 10), findsOneWidget);
    expect(_tab('editor-2', 20), findsOneWidget);
    for (final entry in files.entries) {
      expect(entry.value.readAsStringSync(), original(entry.key));
    }
  });

  testWidgets(
      'group toolbar closes saved or all views inside the clicked group',
      (tester) async {
    await prepare(tester);
    seed(target: [10, 11, 12], other: [11, 20], sticky: [10]);
    await mount(tester);
    const unsaved = 'fn changed_12() { /* 🐙 */ }\n';
    await edit(tester, 'editor', 12, unsaved);
    await activate(tester, 'editor-2', 20);

    await chooseGroupToolbar(tester, 'editor', 'close-saved');
    await finishIo(tester);
    expect(_tab('editor', 10), findsOneWidget);
    expect(_tab('editor', 11), findsNothing);
    expect(_tab('editor', 12), findsOneWidget);
    expect(_tab('editor-2', 11), findsOneWidget);
    expect(_tab('editor-2', 20), findsOneWidget);
    expect(find.byKey(_dirtyDialog), findsNothing);

    await chooseGroupToolbar(tester, 'editor', 'close-all');
    final dialog = find.byKey(_dirtyDialog);
    expect(dialog, findsOneWidget);
    await tester.tap(find.descendant(of: dialog, matching: find.text('取消')));
    await tester.pumpAndSettle();
    expect(_tab('editor', 10), findsOneWidget);
    expect(_tab('editor', 12), findsOneWidget);
    expect(_tab('editor-2', 11), findsOneWidget);
    expect(files[12]!.readAsStringSync(), original(12));
    expect(activeSplit('editor-2'), findsOneWidget);
  });

  testWidgets(
      'fullPath group close targets the nonfocused group, not its sorted first row',
      (tester) async {
    await prepare(tester);
    seed(target: [11, 10], sortOrder: 'fullPath');
    await mount(tester);
    expect(sessionStore.tryLoad()?['focused'], 'editor-2');
    expect(tester.getTopLeft(_row('editor', 10)).dy,
        lessThan(tester.getTopLeft(_row('editor', 11)).dy));
    expect(tester.getTopLeft(_tab('editor', 11)).dx,
        lessThan(tester.getTopLeft(_tab('editor', 10)).dx));

    await close(tester, _closeAll);
    await finishIo(tester);

    expectClosed('editor', [10, 11]);
    expectOpen('editor-2', [20]);
    expect(find.byKey(_dirtyDialog), findsNothing);
    expect(sessionStore.tryLoad()?['focused'], 'editor-2');
    expect(sessionStore.tryLoad()?['openEditorsSortOrder'], 'fullPath');
    expectDiskUnchanged();
  });

  testWidgets(
      'close saved keeps dirty and sticky editors but closes ordinary pinned editors',
      (tester) async {
    await prepare(tester);
    seed(target: [10, 11, 12], sticky: [10]);
    await mount(tester);
    await edit(tester, 'editor', 11, 'fn unsaved() {}\n// 😀\n');
    await activate(tester, 'editor-2', 20);
    final label = tester
        .widget<Text>(find.byKey(const ValueKey('editor-tab-label-editor-12')));
    expect(label.style?.fontStyle, FontStyle.normal,
        reason: 'the clean candidate is permanent, not a preview');

    await close(tester, _closeSaved);
    await finishIo(tester);

    expectOpen('editor', [10, 11]);
    expectClosed('editor', [12]);
    expectOpen('editor-2', [20]);
    expect(find.byKey(const ValueKey('sticky-tab-indicator-editor-10')),
        findsOneWidget);
    expect(find.byKey(_dirtyDialog), findsNothing);
    expectDiskUnchanged();
    final group = (sessionStore.tryLoad()!['groups'] as List)
        .cast<Map>()
        .firstWhere((group) => group['region'] == 'editor');
    expect(
        (group['docs'] as List)
            .cast<Map>()
            .firstWhere((doc) => doc['id'] == 11)['text'],
        'fn unsaved() {}\n// 😀\n');
  });

  testWidgets(
      'cancel close all atomically preserves clean, dirty, and sticky targets',
      (tester) async {
    await prepare(tester);
    seed(target: [10, 11, 12], sticky: [12]);
    await mount(tester);
    const edited = 'fn cancelled() {}\n';
    await edit(tester, 'editor', 11, edited);
    await activate(tester, 'editor-2', 20);

    await close(tester, _closeAll);
    expect(find.byKey(_dirtyDialog), findsOneWidget);
    expectOpen('editor', [10, 11, 12]);
    await tester.tap(find.byKey(const ValueKey('editor-close-cancel')));
    await finishIo(tester);

    expect(find.byKey(_dirtyDialog), findsNothing);
    expectOpen('editor', [10, 11, 12]);
    expectOpen('editor-2', [20]);
    await activate(tester, 'editor', 11);
    final field = tester
        .widgetList<RustTextInputField>(find.byType(RustTextInputField))
        .firstWhere((field) => field.inputWindow.document.id == 11);
    expect(field.inputWindow.document.resync().content, edited);
    expect(field.inputWindow.document.isDirty, isTrue);
    expectDiskUnchanged();
  });

  testWidgets(
      'discard close all affects only the requested group and leaves disk unchanged',
      (tester) async {
    await prepare(tester);
    seed(target: [10, 11, 12], sticky: [12]);
    await mount(tester);
    await edit(tester, 'editor', 11, 'fn target_dirty() {}\n');
    const otherText = 'fn other_dirty() {}\n';
    await edit(tester, 'editor-2', 20, otherText);

    await close(tester, _closeAll);
    expect(find.byKey(_dirtyDialog), findsOneWidget);
    final dialogText =
        tester.widget<AlertDialog>(find.byKey(_dirtyDialog)).content! as Text;
    expect(dialogText.data, contains('doc_11.rs'));
    expect(dialogText.data, isNot(contains('doc_20.rs')));
    await tester.tap(find.byKey(const ValueKey('editor-close-discard')));
    await finishIo(tester);

    expectClosed('editor', [10, 11]);
    expectOpen('editor', [12]);
    expectOpen('editor-2', [20]);
    final remaining = tester
        .widgetList<RustTextInputField>(find.byType(RustTextInputField))
        .firstWhere((field) => field.inputWindow.document.id == 20);
    expect(remaining.inputWindow.document.resync().content, otherText);
    expect(remaining.inputWindow.document.isDirty, isTrue);
    expectDiskUnchanged();
  });

  testWidgets(
      'save close all writes the target dirty file before closing and preserves other edits',
      (tester) async {
    await prepare(tester);
    seed(target: [10, 11, 12], sticky: [12]);
    await mount(tester);
    const edited = 'fn saved() { println!("😀"); }\n';
    const otherText = 'fn other_unsaved() {}\n';
    await edit(tester, 'editor', 10, edited);
    await edit(tester, 'editor-2', 20, otherText);

    await close(tester, _closeAll);
    expect(find.byKey(_dirtyDialog), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('editor-close-save')));
    await finishIo(tester);

    expect(find.byKey(_dirtyDialog), findsNothing);
    expectClosed('editor', [10, 11]);
    expectOpen('editor', [12]);
    expectOpen('editor-2', [20]);
    expect(files[10]!.readAsStringSync(), edited);
    for (final id in [11, 12, 20]) {
      expect(files[id]!.readAsStringSync(), original(id));
    }
    final remaining = tester
        .widgetList<RustTextInputField>(find.byType(RustTextInputField))
        .firstWhere((field) => field.inputWindow.document.id == 20);
    expect(remaining.inputWindow.document.resync().content, otherText);
    expect(remaining.inputWindow.document.isDirty, isTrue);
  });

  testWidgets(
      'closing one group preserves a shared dirty document and its remaining view',
      (tester) async {
    await prepare(tester);
    seed(target: [10, 11], other: [10, 20]);
    await mount(tester);
    const edited = 'fn shared_dirty() {}\n// 😀\n';
    await edit(tester, 'editor', 10, edited);
    await activate(tester, 'editor-2', 10);
    final remainingBefore = tester
        .widgetList<RustTextInputField>(find.byType(RustTextInputField))
        .lastWhere((field) => field.inputWindow.document.id == 10);
    final inputWindow = remainingBefore.inputWindow;
    expect(inputWindow.document.resync().content, edited);

    await close(tester, _closeAll);
    await finishIo(tester);

    expect(find.byKey(_dirtyDialog), findsNothing,
        reason:
            'closing one of two views does not discard or save the document');
    expectClosed('editor', [10, 11]);
    expectOpen('editor-2', [10, 20]);
    final remainingAfter = tester
        .widgetList<RustTextInputField>(find.byType(RustTextInputField))
        .singleWhere((field) => field.inputWindow.document.id == 10);
    expect(remainingAfter.inputWindow, same(inputWindow));
    expect(inputWindow.document.resync().content, edited);
    expect(inputWindow.document.isDirty, isTrue);
    expectDiskUnchanged();
  });

  testWidgets(
      'only group rows offer group actions and dismissing the menu changes nothing',
      (tester) async {
    await prepare(tester);
    seed(target: [10, 11]);
    await mount(tester);
    final tabPosition = tester.getTopLeft(_tab('editor', 10));

    await tester.tap(find.byKey(const ValueKey('open-editors-header')),
        buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.byKey(_closeSaved), findsNothing);
    expect(find.byKey(_closeAll), findsNothing);

    await tester.tap(_row('editor', 10), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('复制路径'), findsOneWidget);
    expect(find.byKey(_closeSaved), findsNothing);
    expect(find.byKey(_closeAll), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await openMenu(tester, 'editor');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await finishIo(tester);

    expect(find.byKey(_closeSaved), findsNothing);
    expect(find.byKey(_closeAll), findsNothing);
    expectOpen('editor', [10, 11]);
    expectOpen('editor-2', [20]);
    expect(tester.getTopLeft(_tab('editor', 10)), tabPosition);
    expect(sessionStore.tryLoad()?['focused'], 'editor-2');
    expectDiskUnchanged();
  });
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
