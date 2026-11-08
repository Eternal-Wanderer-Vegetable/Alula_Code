import 'dart:convert';
import 'dart:io';

import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irondash_message_channel/irondash_message_channel.dart';
// Test fixtures need the package's native-channel override, which is test-only.
// ignore: implementation_imports
import 'package:super_native_extensions/src/native/context.dart'
    show setContextOverride;

Future<(Directory, Directory)> _createWorkspace(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1100, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final temp = Directory.systemTemp.createTempSync('alula-tab-preview');
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    if (temp.existsSync()) await temp.delete(recursive: true);
  });
  final workspace = Directory('${temp.path}/workspace')..createSync();
  return (temp, workspace);
}

Future<void> _mountWorkspace(
  WidgetTester tester,
  Directory temp,
  Directory workspace,
  SessionStore sessionStore,
) async {
  final root = temp.path.replaceAll(r'\', '/');
  await tester.pumpWidget(AlulaApp(
    autoFolder: workspace.path,
    layoutStore: LayoutStore(path: '$root/layout.json'),
    sessionStore: sessionStore,
    keybindingsStore: KeybindingsStore(path: '$root/keybindings.json'),
  ));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

Future<void> _finishAsyncIo(WidgetTester tester) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }
}

Finder _tabLabel(String name, {String region = 'editor'}) => find.descendant(
      of: find.byKey(ValueKey('editor-tab-strip-$region')),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>)
                .value
                .startsWith('editor-tab-label-$region-') &&
            widget.data?.startsWith(name) == true,
      ),
    );

Text _labelWidget(WidgetTester tester, String name,
        {String region = 'editor'}) =>
    tester.widget<Text>(_tabLabel(name, region: region));

Future<void> _tapExplorerFile(WidgetTester tester, String path) async {
  await tester.tap(find.byKey(ValueKey('explorer-node:$path')));
  await _finishAsyncIo(tester);
}

Future<void> _doubleTapExplorerFile(WidgetTester tester, String path) async {
  final target = find.byKey(ValueKey('explorer-node:$path'));
  final position = tester.getCenter(target);
  final firstTap = await tester.startGesture(position);
  await firstTap.up();
  final secondTap = await tester.startGesture(position);
  await secondTap.up();
  await tester.pump();
  await _finishAsyncIo(tester);
}

Future<void> _replaceText(WidgetTester tester, String text) async {
  final field = find.byType(RustTextInputField).first;
  await tester.tap(field);
  tester.testTextInput.updateEditingValue(TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  ));
  await tester.pump();
  await tester.pump();
}

Future<void> _pressCtrlS(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await _finishAsyncIo(tester);
}

Future<void> _pressCtrlZ(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(() {
    final mockContext = MockMessageChannelContext();
    for (final channel in ['DragManager', 'DropManager', 'MenuManager']) {
      mockContext.registerMockChannelHandler(
          channel, (_) async => ['ok', null]);
    }
    setContextOverride(mockContext);
    TestWidgetsFlutterBinding.ensureInitialized()
        .defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.irondash.engine_context'),
          (call) async => call.method == 'getEngineHandle' ? 1 : null,
        );
  });

  testWidgets(
    'Explorer previews replace clean tabs; dirty edits pin, save, and survive undo',
    (tester) async {
      final (temp, workspace) = await _createWorkspace(tester);
      final root = temp.path.replaceAll(r'\', '/');
      final alpha = File('${workspace.path}/alpha.rs')
        ..writeAsBytesSync([
          0xef,
          0xbb,
          0xbf,
          ...utf8.encode('fn alpha() {}\r\n// 😀'),
        ]);
      final beta = File('${workspace.path}/beta.rs')
        ..writeAsBytesSync([
          0xef,
          0xbb,
          0xbf,
          ...utf8.encode('fn beta() {}\r\n// 😀'),
        ]);
      final gamma = File('${workspace.path}/gamma.rs')
        ..writeAsStringSync('fn gamma() {}\n');
      final delta = File('${workspace.path}/delta.rs')
        ..writeAsStringSync('fn delta() {}\n');
      final sessionPath = '$root/session.json';
      final sessionStore = SessionStore(path: sessionPath);

      await _mountWorkspace(tester, temp, workspace, sessionStore);
      await _tapExplorerFile(tester, alpha.path);
      expect(_tabLabel('alpha.rs'), findsOneWidget);
      expect(
          _labelWidget(tester, 'alpha.rs').style?.fontStyle, FontStyle.italic);

      await _tapExplorerFile(tester, beta.path);
      expect(_tabLabel('alpha.rs'), findsNothing,
          reason: 'the next clean preview replaces the previous preview');
      expect(
          _labelWidget(tester, 'beta.rs').style?.fontStyle, FontStyle.italic);

      const edited = 'fn beta() { println!("saved 😀"); }\n// final\n';
      await _replaceText(tester, edited);
      final editedFieldState = tester.state<RustTextInputFieldState>(
        find.byType(RustTextInputField).first,
      );
      expect(edited.runes.length, lessThan(edited.length));
      expect(
          editedFieldState.editingValue.selection.extentOffset, edited.length,
          reason: 'the caret remains at the UTF-16 end after a non-BMP emoji');
      expect(_labelWidget(tester, 'beta.rs').style?.fontStyle, FontStyle.normal,
          reason: 'the first text edit pins and de-italicizes the tab');
      expect(_tabLabel('beta.rs •'), findsOneWidget);
      await _pressCtrlS(tester);
      expect(beta.readAsBytesSync(), [
        0xef,
        0xbb,
        0xbf,
        ...utf8.encode('fn beta() { println!("saved 😀"); }\r\n// final\r\n'),
      ]);
      await _pressCtrlZ(tester);
      expect(_labelWidget(tester, 'beta.rs').style?.fontStyle, FontStyle.normal,
          reason: 'undo to a clean savepoint does not unpin the editor');
      expect(_tabLabel('beta.rs •'), findsOneWidget,
          reason: 'undo restores dirty state against the saved bytes');

      await _tapExplorerFile(tester, gamma.path);
      expect(_tabLabel('beta.rs •'), findsOneWidget,
          reason: 'a dirty pinned editor is never replaced');
      expect(
          _labelWidget(tester, 'gamma.rs').style?.fontStyle, FontStyle.italic);

      await _doubleTapExplorerFile(tester, gamma.path);
      expect(
          _labelWidget(tester, 'gamma.rs').style?.fontStyle, FontStyle.normal,
          reason: 'double-clicking an Explorer item pins its preview');

      await _tapExplorerFile(tester, delta.path);
      expect(_tabLabel('gamma.rs'), findsOneWidget,
          reason: 'a double-clicked editor stays open');
      expect(
          _labelWidget(tester, 'delta.rs').style?.fontStyle, FontStyle.italic);

      await tester.pump(const Duration(milliseconds: 600));
      final savedSession = jsonDecode(File(sessionPath).readAsStringSync())
          as Map<String, Object?>;
      final payload = savedSession['payload'] as Map<String, Object?>;
      final savedGroup = (payload['groups'] as List).single as Map;
      expect(savedGroup['preview'], isA<int>());

      await tester.pumpWidget(const SizedBox.shrink());
      await _mountWorkspace(tester, temp, workspace, sessionStore);
      expect(
          _labelWidget(tester, 'delta.rs').style?.fontStyle, FontStyle.italic,
          reason: 'the clean preview is restored from the session journal');
      expect(
          _labelWidget(tester, 'gamma.rs').style?.fontStyle, FontStyle.normal,
          reason: 'the pinned editor remains permanent after restore');
      expect(_tabLabel('beta.rs •'), findsOneWidget,
          reason: 'a dirty restored editor is permanent');
    },
  );

  testWidgets('preview state is isolated and restored per editor group',
      (tester) async {
    final (temp, workspace) = await _createWorkspace(tester);
    final root = temp.path.replaceAll(r'\', '/');
    final pinned = File('${workspace.path}/pinned.rs')
      ..writeAsStringSync('fn pinned() {}\n');
    final preview = File('${workspace.path}/preview.rs')
      ..writeAsStringSync('fn preview() {}\n');
    final nextPreview = File('${workspace.path}/next.rs')
      ..writeAsStringSync('fn next() {}\n');
    final layout = defaultLayout();
    expect(layout.splitLeaf('editor', 'editor-2', Axis.horizontal), isNotNull);
    LayoutStore(path: '$root/layout.json').save(layout);
    final sessionStore = SessionStore(path: '$root/session.json')
      ..save({
        'v': 1,
        'focused': 'editor-2',
        'workspace': workspace.path,
        'groups': [
          {
            'region': 'editor',
            'active': 10,
            'docs': [
              {'id': 10, 'path': pinned.path},
            ],
          },
          {
            'region': 'editor-2',
            'active': 11,
            'preview': 11,
            'docs': [
              {'id': 11, 'path': preview.path},
            ],
          },
        ],
      });

    await _mountWorkspace(tester, temp, workspace, sessionStore);
    expect(_labelWidget(tester, 'pinned.rs', region: 'editor').style?.fontStyle,
        FontStyle.normal);
    expect(
        _labelWidget(tester, 'preview.rs', region: 'editor-2').style?.fontStyle,
        FontStyle.italic);

    await tester.tap(_tabLabel('pinned.rs', region: 'editor'));
    await tester.pump();
    await _tapExplorerFile(tester, pinned.path);
    expect(
      _labelWidget(tester, 'pinned.rs', region: 'editor').style?.fontStyle,
      FontStyle.normal,
      reason: 'single-clicking an already-open permanent tab does not unpin it',
    );

    await tester.tap(_tabLabel('preview.rs', region: 'editor-2'));
    await tester.pump();
    await _tapExplorerFile(tester, nextPreview.path);
    expect(_tabLabel('pinned.rs', region: 'editor'), findsOneWidget,
        reason: 'opening a preview in editor-2 does not change editor state');
    expect(_tabLabel('preview.rs', region: 'editor-2'), findsNothing);
    expect(_labelWidget(tester, 'next.rs', region: 'editor-2').style?.fontStyle,
        FontStyle.italic);
  });
}
