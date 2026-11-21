import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/breadcrumb_navigation.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _reveal = 'breadcrumbs.revealFocused';
const _original = 'fn main() {\r\n    // 😀\r\n}\r\n';
const _library = 'fn library() {}\n';
const _other = 'fn other() {}\n';
final _pickerItems = find.byType(PopupMenuItem<String>);

Finder _pickerEntry(String name) =>
    find.descendant(of: _pickerItems, matching: find.text(name));

Finder _selectedSegment(int index) => find.descendant(
      of: find.byKey(ValueKey('breadcrumbs-segment-editor-$index')),
      matching: find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.selected == true,
      ),
      matchRoot: true,
    );

RustTextInputField _field(WidgetTester tester, int id) => tester
    .widgetList<RustTextInputField>(find.byType(RustTextInputField))
    .firstWhere((field) => field.inputWindow.document.id == id);

FontStyle? _mainTabStyle(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('editor-tab-label-editor-10')))
    .style
    ?.fontStyle;

Future<void> _deleteDirectoryWithRetry(Directory directory) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (!directory.existsSync()) return;
      if (attempt == 49) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

void main() {
  late File mainFile;
  late File libFile;
  late File otherFile;
  late CommandService commands;

  Future<void> mount(
    WidgetTester tester, {
    bool preview = false,
    bool nestedMain = false,
    String? mainSource,
  }) async {
    final temp = Directory.systemTemp.createTempSync('alula-breadcrumb-reveal');
    final workspace = Directory('${temp.path}/workspace')..createSync();
    final src = Directory('${workspace.path}/src')..createSync();
    final nested = Directory('${src.path}/nested')..createSync();
    File('${nested.path}/util.rs').writeAsStringSync('fn util() {}\n');
    mainFile = File('${nestedMain ? nested.path : src.path}/main.rs')
      ..writeAsStringSync(mainSource ?? _original);
    libFile = File('${src.path}/lib.rs')..writeAsStringSync(_library);
    otherFile = File('${workspace.path}/other.rs')..writeAsStringSync(_other);

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
            if (preview) 'preview': 10,
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

  Future<void> focusBreadcrumbs(WidgetTester tester, int index) async {
    final navigation = tester.widget<BreadcrumbNavigation>(
      find.byWidgetPredicate((widget) =>
          widget is BreadcrumbNavigation && widget.region == 'editor'),
    );
    expect(await commands.execute('breadcrumbs.focus'),
        CommandExecutionStatus.executed);
    await tester.pumpAndSettle();
    expect(commands.context['breadcrumbsActive'], isTrue);
    for (var focused = navigation.segments.length - 1;
        focused > index;
        focused--) {
      await _key(tester, LogicalKeyboardKey.arrowLeft);
    }
    expect(_selectedSegment(index), findsOneWidget);
  }

  void expectReturnedToOwner(WidgetTester tester) {
    expect(_pickerItems, findsNothing);
    expect(commands.context['breadcrumbsActive'], isFalse);
    expect(_field(tester, 10).focusNode!.hasFocus, isTrue);
    expect(_field(tester, 20).focusNode!.hasFocus, isFalse);
  }

  testWidgets('reveal is disabled until breadcrumb navigation has focus',
      (tester) async {
    await mount(tester);
    expect(commands.byId(_reveal), isNotNull);
    expect(commands.context['breadcrumbsVisible'], isTrue);
    expect(commands.context['breadcrumbsActive'], isFalse);
    expect(commands.isEnabled(_reveal), isFalse);
    expect(await commands.execute(_reveal),
        anyOf(CommandExecutionStatus.hidden, CommandExecutionStatus.disabled));
    expectReturnedToOwner(tester);

    await focusBreadcrumbs(tester, 1);
    expect(commands.isEnabled(_reveal), isTrue);
    expect(await commands.execute(_reveal), CommandExecutionStatus.executed);
    await tester.pumpAndSettle();
    expectReturnedToOwner(tester);
    expect(commands.isEnabled(_reveal), isFalse);
  });

  testWidgets('Space on a file preserves the dirty editor and its undo history',
      (tester) async {
    await mount(tester);
    final window = _field(tester, 10).inputWindow;
    final document = window.document;
    final original = document.resync().content;
    final disk = mainFile.readAsBytesSync();
    const edited = 'fn main() {\r\n    // unsaved 😀\r\n}\r\n';
    const selection = TextSelection(baseOffset: 3, extentOffset: 7);
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: edited,
      selection: selection,
    ));
    await tester.pump();
    await tester.pump();
    final before = document.resync();
    expect(before.content, edited);
    expect(window.initialValue.selection, selection);
    expect(document.isDirty, isTrue);
    expect(commands.context['editorCanUndo'], isTrue);
    expect(commands.context['editorCanRedo'], isFalse);
    expect(_mainTabStyle(tester), FontStyle.normal);

    await focusBreadcrumbs(tester, 1);
    await _key(tester, LogicalKeyboardKey.space);

    expectReturnedToOwner(tester);
    expect(_selectedSegment(1), findsNothing);
    expect(_field(tester, 10).inputWindow, same(window));
    expect(document.resync().content, before.content);
    expect(document.version, before.version);
    expect(window.initialValue.selection, selection);
    expect(document.isDirty, isTrue);
    expect(commands.context['editorCanUndo'], isTrue);
    expect(commands.context['editorCanRedo'], isFalse);
    expect(_mainTabStyle(tester), FontStyle.normal);
    expect(mainFile.readAsBytesSync(), disk);

    await commands.execute('editor.undo');
    await tester.pumpAndSettle();
    expect(document.resync().content, original);
    await commands.execute('editor.redo');
    await tester.pumpAndSettle();
    expect(document.resync().content, edited);
    expect(mainFile.readAsBytesSync(), disk);
  });

  testWidgets('CtrlCmd+Enter on a file restores focus and keeps its preview',
      (tester) async {
    await mount(tester, preview: true);
    final window = _field(tester, 10).inputWindow;
    final document = window.document;
    final before = document.resync();
    final selection = window.initialValue.selection;
    final disk = mainFile.readAsBytesSync();
    expect(_mainTabStyle(tester), FontStyle.italic);
    await focusBreadcrumbs(tester, 1);

    final modifier = defaultTargetPlatform == TargetPlatform.macOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(modifier);
    await tester.pumpAndSettle();

    expectReturnedToOwner(tester);
    expect(_field(tester, 10).inputWindow, same(window));
    expect(document.resync().content, before.content);
    expect(document.version, before.version);
    expect(window.initialValue.selection, selection);
    expect(document.isDirty, isFalse);
    expect(_mainTabStyle(tester), FontStyle.italic);
    expect(mainFile.readAsBytesSync(), disk);
  });

  testWidgets('Space on a folder selects the next segment and lists siblings',
      (tester) async {
    await mount(tester);
    final otherWindow = _field(tester, 20).inputWindow;
    await focusBreadcrumbs(tester, 1);
    await _key(tester, LogicalKeyboardKey.arrowLeft);
    expect(_selectedSegment(0), findsOneWidget);
    await _key(tester, LogicalKeyboardKey.space);

    expect(_selectedSegment(0), findsNothing);
    expect(_selectedSegment(1), findsOneWidget);
    expect(_pickerItems, findsNWidgets(3));
    expect(_pickerEntry('main.rs'), findsOneWidget);
    expect(_pickerEntry('lib.rs'), findsOneWidget);
    expect(_pickerEntry('nested/'), findsOneWidget);
    await tester.tap(_pickerEntry('lib.rs'));
    final libraryBreadcrumb = find.descendant(
      of: find.byKey(const ValueKey('breadcrumb-editor')),
      matching: find.text('lib.rs'),
    );
    Iterable<RustTextInputField> libraryFields() => tester
        .widgetList<RustTextInputField>(find.byType(RustTextInputField))
        .where((field) => field.semanticsLabel?.startsWith('lib.rs') == true);
    for (var attempt = 0; attempt < 50; attempt++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
      if (libraryFields().any((field) => field.focusNode!.hasFocus)) break;
    }

    expect(libraryBreadcrumb, findsOneWidget);
    expect(_pickerItems, findsNothing);
    expect(commands.context['breadcrumbsActive'], isFalse);
    final library = libraryFields().single;
    expect(library.focusNode!.hasFocus, isTrue);
    expect(library.inputWindow.document.resync().content, _library);
    expect(_field(tester, 20).inputWindow, same(otherWindow));
    expect(_field(tester, 20).focusNode!.hasFocus, isFalse);
    expect(mainFile.readAsStringSync(), _original);
    expect(libFile.readAsStringSync(), _library);
    expect(otherFile.readAsStringSync(), _other);
  });

  testWidgets('Space on a symbol ancestor advances to its nested symbol',
      (tester) async {
    const source = 'mod outer {\n    fn inner() {}\n}\n';
    await mount(tester, mainSource: source);
    final owner = _field(tester, 10);
    final document = owner.inputWindow.document;
    final version = document.version;
    final innerStart = source.substring(0, source.indexOf('fn inner')).length;
    owner.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.pump();
    final navigation = tester.widget<BreadcrumbNavigation>(
      find.byWidgetPredicate((widget) =>
          widget is BreadcrumbNavigation && widget.region == 'editor'),
    );
    expect(navigation.segments, ['src', 'main.rs', 'outer', 'inner']);

    await focusBreadcrumbs(tester, navigation.segments.length - 1);
    await _key(tester, LogicalKeyboardKey.arrowLeft);
    expect(_selectedSegment(2), findsOneWidget,
        reason: 'the symbol parent is the active breadcrumb segment');
    await _key(tester, LogicalKeyboardKey.space);

    expect(_selectedSegment(3), findsOneWidget,
        reason: 'reveal advances to the nested symbol');
    expect(owner.inputWindow.initialValue.selection.extentOffset, innerStart);
    expect(document.resync().content, source);
    expect(document.version, version);
    expect(document.isDirty, isFalse);
    expect(mainFile.readAsStringSync(), source);
  });

  testWidgets(
      'folder reveal cancels back to its owner or preserves other focus',
      (tester) async {
    await mount(tester, nestedMain: true);
    final owner = _field(tester, 10);
    final other = _field(tester, 20);

    Future<void> revealSrc() async {
      await focusBreadcrumbs(tester, 2);
      await _key(tester, LogicalKeyboardKey.arrowLeft);
      await _key(tester, LogicalKeyboardKey.arrowLeft);
      expect(_selectedSegment(0), findsOneWidget);
      await _key(tester, LogicalKeyboardKey.space);
      expect(_selectedSegment(1), findsOneWidget);
      expect(_pickerEntry('lib.rs'), findsOneWidget);
      expect(_pickerEntry('nested/'), findsOneWidget);
      expect(_pickerEntry('util.rs'), findsNothing);
    }

    await revealSrc();
    await _key(tester, LogicalKeyboardKey.escape);
    expectReturnedToOwner(tester);
    expect(_field(tester, 10).inputWindow, same(owner.inputWindow));

    // The test never expanded nested in the Explorer. Its children must
    // still be available when revealing that directory segment.
    await focusBreadcrumbs(tester, 2);
    await _key(tester, LogicalKeyboardKey.arrowLeft);
    expect(_selectedSegment(1), findsOneWidget);
    await _key(tester, LogicalKeyboardKey.space);
    expect(_selectedSegment(2), findsOneWidget);
    expect(_pickerEntry('main.rs'), findsOneWidget);
    expect(_pickerEntry('util.rs'), findsOneWidget);
    expect(_pickerEntry('lib.rs'), findsNothing);
    other.focusNode!.requestFocus();
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.byKey(other.key!)));
    await tester.pumpAndSettle();
    expect(_pickerItems, findsNothing);
    expect(commands.context['breadcrumbsActive'], isFalse);
    expect(other.focusNode!.hasFocus, isTrue);
    expect(owner.focusNode!.hasFocus, isFalse);
  });
}
