import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _segment(String region, int index) =>
    find.byKey(ValueKey('breadcrumbs-segment-$region-$index'));

RustTextInputField _field(WidgetTester tester, int id) => tester
    .widgetList<RustTextInputField>(find.byType(RustTextInputField))
    .firstWhere((field) => field.inputWindow.document.id == id);

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
  late Directory temp;
  late Directory workspace;
  late File mainFile;
  late File otherFile;
  late CommandService commands;

  Future<void> mount(WidgetTester tester) async {
    temp = Directory.systemTemp.createTempSync('alula-breadcrumb-keyboard');
    workspace = Directory('${temp.path}/workspace')..createSync();
    final src = Directory('${workspace.path}/src')..createSync();
    mainFile = File('${src.path}/main.rs')
      ..writeAsStringSync('fn main() {\r\n    // 😀\r\n}\r\n');
    File('${src.path}/lib.rs').writeAsStringSync('fn library() {}\n');
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
      await tester.runAsync(() => _deleteDirectoryWithRetry(temp));
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
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  Future<void> shortcut(WidgetTester tester, LogicalKeyboardKey key) async {
    final modifier = defaultTargetPlatform == TargetPlatform.macOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(modifier);
    await tester.pumpAndSettle();
  }

  void expectSelected(WidgetTester tester, int index) {
    final selected = find.descendant(
      of: _segment('editor', index),
      matching: find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.selected == true,
      ),
      matchRoot: true,
    );
    expect(selected, findsOneWidget);
  }

  Future<void> editMain(WidgetTester tester) async {
    _field(tester, 10).focusNode!.requestFocus();
    await tester.pump();
    const text = 'fn main() {\r\n    // unsaved 😀\r\n}\r\n';
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    ));
    await tester.pump();
    await tester.pump();
    expect(_field(tester, 10).inputWindow.document.resync().content, text);
    expect(commands.context['editorDirty'], isTrue);
  }

  testWidgets('registers six breadcrumb commands with live context guards',
      (tester) async {
    await mount(tester);
    const ids = [
      'breadcrumbs.focus',
      'breadcrumbs.focusAndSelect',
      'breadcrumbs.focusNext',
      'breadcrumbs.focusPrevious',
      'breadcrumbs.selectFocused',
      'breadcrumbs.selectEditor',
    ];
    for (final id in ids) {
      expect(commands.byId(id), isNotNull, reason: '$id is registered');
      expect(
          commands.byId(id)!.when ?? commands.byId(id)!.enablement, isNotEmpty);
    }
    expect(commands.context['breadcrumbsPossible'], isTrue);
    expect(commands.context['breadcrumbsVisible'], isTrue);
    expect(commands.context['breadcrumbsActive'], isFalse);
    expect(await commands.execute('breadcrumbs.focusNext'),
        CommandExecutionStatus.disabled);
    expect(await commands.execute('breadcrumbs.focus'),
        CommandExecutionStatus.executed);
    await tester.pumpAndSettle();
    expect(commands.context['breadcrumbsActive'], isTrue);
    expect(commands.isEnabled('breadcrumbs.selectFocused'), isTrue);
    expect(await commands.execute('breadcrumbs.selectEditor'),
        CommandExecutionStatus.executed);
    await tester.pumpAndSettle();
    expect(commands.context['breadcrumbsActive'], isFalse);
    expect(commands.isEnabled('breadcrumbs.selectFocused'), isFalse);
    await commands.execute('workbench.action.files.newUntitledFile');
    await tester.pumpAndSettle();
    expect(commands.context['breadcrumbsPossible'], isFalse);
    expect(commands.context['breadcrumbsVisible'], isFalse);
    expect(await commands.execute('breadcrumbs.focus'),
        CommandExecutionStatus.hidden);
  });

  testWidgets(
      'focus shortcut selects last segment and arrows stop at both ends',
      (tester) async {
    await mount(tester);
    final original = _field(tester, 10).inputWindow.document.resync().content;
    await editMain(tester);
    final field = _field(tester, 10);
    final window = field.inputWindow;
    final document = window.document;
    final before = document.resync();
    final selection = window.initialValue.selection;
    final undo = commands.context['editorCanUndo'];
    final redo = commands.context['editorCanRedo'];
    final disk = mainFile.readAsBytesSync();
    await shortcut(tester, LogicalKeyboardKey.semicolon);
    expect(
        find.byKey(const ValueKey('breadcrumbs-focus-editor')), findsOneWidget);
    expectSelected(tester, 1);
    expect(find.byType(PopupMenuItem<String>), findsNothing);
    expect(field.focusNode!.hasFocus, isFalse);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expectSelected(tester, 1);
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expectSelected(tester, 0);
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expectSelected(tester, 0);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expectSelected(tester, 1);
    await key(tester, LogicalKeyboardKey.escape);

    expect(field.focusNode!.hasFocus, isTrue);
    expect(_field(tester, 10).inputWindow, same(window));
    expect(document.resync().content, before.content);
    expect(document.version, before.version);
    expect(window.initialValue.selection, selection);
    expect(document.isDirty, isTrue);
    expect(commands.context['editorCanUndo'], undo);
    expect(commands.context['editorCanRedo'], redo);
    expect(mainFile.readAsBytesSync(), disk);
    expect(otherFile.readAsStringSync(), 'fn other() {}\n');
    await commands.execute('editor.undo');
    await tester.pumpAndSettle();
    expect(document.resync().content, original,
        reason: 'breadcrumb navigation did not add an undo transaction');
    await commands.execute('editor.redo');
    await tester.pumpAndSettle();
    expect(document.resync().content, before.content);
  });

  testWidgets(
      'focus and select shortcut opens symbols and Escape restores owner',
      (tester) async {
    await mount(tester);
    final owner = _field(tester, 10);
    final before = owner.inputWindow.document.resync();
    await shortcut(tester, LogicalKeyboardKey.period);
    expect(find.byType(PopupMenuItem<String>), findsWidgets);
    expect(owner.focusNode!.hasFocus, isFalse);
    await key(tester, LogicalKeyboardKey.escape);
    expect(find.byType(PopupMenuItem<String>), findsNothing);
    expect(owner.focusNode!.hasFocus, isTrue);
    expect(_field(tester, 20).focusNode!.hasFocus, isFalse);
    expect(commands.context['breadcrumbsActive'], isFalse);
    expect(owner.inputWindow.document.resync().content, before.content);
    expect(owner.inputWindow.document.version, before.version);
    expect(owner.inputWindow.document.isDirty, isFalse);
  });

  testWidgets(
      'Enter and Down open folder picker and picked file keeps its group',
      (tester) async {
    await mount(tester);
    for (final openKey in [
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.arrowDown,
    ]) {
      await shortcut(tester, LogicalKeyboardKey.semicolon);
      await key(tester, LogicalKeyboardKey.arrowLeft);
      await key(tester, LogicalKeyboardKey.arrowLeft);
      await key(tester, openKey);
      expect(find.text('lib.rs'), findsOneWidget);
      if (openKey == LogicalKeyboardKey.enter) {
        await key(tester, LogicalKeyboardKey.escape);
        expect(_field(tester, 10).focusNode!.hasFocus, isTrue);
      }
    }
    await tester.tap(find.text('lib.rs'));
    for (var attempt = 0; attempt < 50; attempt++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
      if (tester
          .widgetList<RustTextInputField>(find.byType(RustTextInputField))
          .any((field) => field.semanticsLabel?.startsWith('lib.rs') == true)) {
        break;
      }
    }
    expect(
        find.descendant(
          of: find.byKey(const ValueKey('breadcrumb-editor')),
          matching: find.text('lib.rs'),
        ),
        findsOneWidget);
    expect(
        find.descendant(
          of: find.byKey(const ValueKey('breadcrumb-editor-2')),
          matching: find.text('other.rs'),
        ),
        findsOneWidget);
    expect(_field(tester, 20).inputWindow.document.resync().content,
        'fn other() {}\n');
    expect(File('${workspace.path}/src/lib.rs').readAsStringSync(),
        'fn library() {}\n');
    expect(mainFile.readAsStringSync(), 'fn main() {\r\n    // 😀\r\n}\r\n');
  });

  testWidgets('mouse activates a nonfocused owner before awaiting its picker',
      (tester) async {
    await mount(tester);
    await editMain(tester);
    await tester
        .tap(find.byKey(const ValueKey('open-editors-doc-editor-2-20')));
    await tester.pumpAndSettle();
    expect(commands.context['editorDirty'], isFalse);

    await tester.tap(_segment('editor', 0));
    await tester.pumpAndSettle();
    expect(find.text('lib.rs'), findsOneWidget);
    expect(commands.context['editorDirty'], isTrue,
        reason: 'the picker owner is active before its pending result');
    await key(tester, LogicalKeyboardKey.escape);
    expect(_field(tester, 10).focusNode!.hasFocus, isTrue);
    expect(_field(tester, 20).focusNode!.hasFocus, isFalse);
    expect(_field(tester, 10).inputWindow.document.isDirty, isTrue);
    expect(mainFile.readAsStringSync(), 'fn main() {\r\n    // 😀\r\n}\r\n');
  });

  testWidgets(
      'outside dismissal preserves another editor focus and clears state',
      (tester) async {
    await mount(tester);
    await shortcut(tester, LogicalKeyboardKey.period);
    expect(find.byType(PopupMenuItem<String>), findsWidgets);
    final other = _field(tester, 20);
    other.focusNode!.requestFocus();
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.byKey(other.key!)));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<String>), findsNothing);
    expect(other.focusNode!.hasFocus, isTrue);
    expect(_field(tester, 10).focusNode!.hasFocus, isFalse);
    expect(commands.context['breadcrumbsActive'], isFalse);
    expect(commands.isEnabled('breadcrumbs.focusNext'), isFalse);
    expect(other.inputWindow.document.isDirty, isFalse);
    expect(otherFile.readAsStringSync(), 'fn other() {}\n');
  });

  testWidgets('Tab focuses a picker item and Escape still returns to its owner',
      (tester) async {
    await mount(tester);
    final owner = _field(tester, 10);
    await shortcut(tester, LogicalKeyboardKey.semicolon);
    await key(tester, LogicalKeyboardKey.arrowLeft);
    await key(tester, LogicalKeyboardKey.arrowLeft);
    await key(tester, LogicalKeyboardKey.enter);
    expect(find.text('lib.rs'), findsOneWidget);
    await key(tester, LogicalKeyboardKey.tab);
    final focused = FocusManager.instance.primaryFocus;
    expect(focused, isNotNull);
    final inkWell = find.ancestor(
      of: find.byElementPredicate((element) => element == focused!.context),
      matching: find.byType(InkWell),
    );
    expect(inkWell, findsOneWidget,
        reason: 'Tab reached the menu item rather than its inner autofocus');
    expect(owner.focusNode!.hasFocus, isFalse);
    await key(tester, LogicalKeyboardKey.escape);
    expect(find.byType(PopupMenuItem<String>), findsNothing);
    expect(owner.focusNode!.hasFocus, isTrue);
    expect(commands.context['breadcrumbsActive'], isFalse);
  });

  testWidgets(
      'resource invalidation removes a covered picker but keeps its dialog',
      (tester) async {
    await mount(tester);
    final oldFocus = _field(tester, 10).focusNode!;
    await shortcut(tester, LogicalKeyboardKey.period);
    final entries = find.byType(PopupMenuItem<String>);
    expect(entries, findsWidgets);
    final pickerRoute = ModalRoute.of(tester.element(entries.first))!;
    final dialogClosed = showDialog<void>(
      context: tester.element(find.byType(WorkbenchPage)),
      builder: (context) => AlertDialog(
        key: const ValueKey('breadcrumb-cover-dialog'),
        title: const Text('Keep this dialog'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Dismiss cover'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final dialog = find.byKey(const ValueKey('breadcrumb-cover-dialog'));
    final dialogRoute = ModalRoute.of(tester.element(dialog))!;
    expect(dialogRoute.isCurrent, isTrue);
    expect(pickerRoute.isActive, isTrue);
    await commands.execute('workbench.action.files.newUntitledFile');
    await tester.pumpAndSettle();
    expect(dialog, findsOneWidget);
    expect(dialogRoute.isCurrent, isTrue,
        reason: 'invalidation removes the captured picker, not the top dialog');
    expect(pickerRoute.isActive, isFalse);
    expect(
        find.byType(PopupMenuItem<String>, skipOffstage: false), findsNothing);
    await tester.tap(find.text('Dismiss cover'));
    await tester.pumpAndSettle();
    await dialogClosed;
    expect(dialog, findsNothing);
    expect(
        find.byType(PopupMenuItem<String>, skipOffstage: false), findsNothing);
    expect(oldFocus.hasFocus, isFalse);
    expect(commands.context['breadcrumbsActive'], isFalse);
    expect(commands.context['breadcrumbsPossible'], isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing the picker resource clears stale breadcrumb state',
      (tester) async {
    await mount(tester);
    final oldFocus = _field(tester, 10).focusNode!;
    await shortcut(tester, LogicalKeyboardKey.period);
    expect(find.byType(PopupMenuItem<String>), findsWidgets);
    await commands.execute('workbench.action.files.newUntitledFile');
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.escape);
    expect(find.byType(PopupMenuItem<String>), findsNothing);
    expect(oldFocus.hasFocus, isFalse);
    expect(find.byKey(const ValueKey('breadcrumb-editor')), findsNothing);
    expect(commands.context['breadcrumbsActive'], isFalse);
    expect(commands.context['breadcrumbsPossible'], isFalse);
    expect(await commands.execute('breadcrumbs.focus'),
        CommandExecutionStatus.hidden);
    expect(tester.takeException(), isNull);
    expect(mainFile.readAsStringSync(), 'fn main() {\r\n    // 😀\r\n}\r\n');
    expect(otherFile.readAsStringSync(), 'fn other() {}\n');
  });
}
