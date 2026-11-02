import 'dart:io';

import 'package:alula_app/editor/editor_clipboard.dart';
import 'package:alula_app/editor/paste_as.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Paste As applies one Rust edit that undo and redo restore',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-paste-as-');
    final previousFallback =
        EditorClipboard.forceFlutterClipboardFallbackForTesting;
    EditorClipboard.forceFlutterClipboardFallbackForTesting = true;
    addTearDown(() async {
      EditorClipboard.forceFlutterClipboardFallbackForTesting =
          previousFallback;
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    final workspace = Directory('${temp.path}/workspace')..createSync();
    final file = File('${workspace.path}/sample.txt')
      ..writeAsStringSync('one two');
    final layoutPath = '${temp.path}/layout.json';
    final sessionPath = '${temp.path}/session.json';
    Map<dynamic, dynamic> clipboard = const {'text': 'replacement'};
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') return clipboard;
        if (call.method == 'Clipboard.setData') {
          clipboard = Map<dynamic, dynamic>.from(call.arguments as Map);
        }
        return null;
      },
    );

    await tester.pumpWidget(AlulaApp(
      autoFolder: workspace.path,
      layoutStore: LayoutStore(path: layoutPath),
      sessionStore: SessionStore(path: sessionPath),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('sample.txt').first);
    await tester.pump(const Duration(milliseconds: 200));
    final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
    await tester.showKeyboard(editor);
    final controller = tester.widget<TextField>(editor).controller!;
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
    await tester.pump();

    await _press(tester, LogicalKeyboardKey.keyV);
    expect(controller.text, 'replacement two');
    await _press(tester, LogicalKeyboardKey.keyZ);
    expect(controller.text, 'one two');
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
    await tester.pump();

    await _press(tester, LogicalKeyboardKey.keyV, shift: true);
    expect(find.byKey(const ValueKey('qi-Insert Plain Text')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('qi-Insert Plain Text')));
    await tester.pump();
    await tester.pump();
    expect(controller.text, 'replacement two');

    await _press(tester, LogicalKeyboardKey.keyZ);
    expect(controller.text, 'one two');
    await _press(tester, LogicalKeyboardKey.keyY);
    expect(controller.text, 'replacement two');
    await _press(tester, LogicalKeyboardKey.keyS);
    expect(file.readAsStringSync(), 'replacement two');
  });

  testWidgets('disabling Paste As preserves ordinary plain-text paste',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-paste-as-off-');
    final previousFallback =
        EditorClipboard.forceFlutterClipboardFallbackForTesting;
    EditorClipboard.forceFlutterClipboardFallbackForTesting = true;
    addTearDown(() async {
      EditorClipboard.forceFlutterClipboardFallbackForTesting =
          previousFallback;
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    final workspace = Directory('${temp.path}/workspace')..createSync();
    File('${workspace.path}/sample.txt').writeAsStringSync('one two');
    Map<dynamic, dynamic> clipboard = const {'text': 'replacement'};
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') return clipboard;
        return null;
      },
    );

    await tester.pumpWidget(AlulaApp(
      autoFolder: workspace.path,
      layoutStore: LayoutStore(path: '${temp.path}/layout.json'),
      sessionStore: SessionStore(path: '${temp.path}/session.json'),
      pasteAsConfiguration: const PasteAsConfiguration(enabled: false),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('sample.txt').first);
    await tester.pump(const Duration(milliseconds: 200));
    final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
    await tester.showKeyboard(editor);
    final controller = tester.widget<TextField>(editor).controller!;
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
    await tester.pump();

    await _press(tester, LogicalKeyboardKey.keyV);
    expect(controller.text, 'replacement two');
    await _press(tester, LogicalKeyboardKey.keyV, shift: true);
    expect(find.byKey(const ValueKey('qi-Insert Plain Text')), findsNothing);
  });

  testWidgets('post-paste provider switch remains one undoable edit',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('alula-paste-switch-');
    final previousFallback =
        EditorClipboard.forceFlutterClipboardFallbackForTesting;
    final previousReadOverride =
        EditorClipboard.readForPasteAsOverrideForTesting;
    EditorClipboard.forceFlutterClipboardFallbackForTesting = true;
    EditorClipboard.readForPasteAsOverrideForTesting = () async =>
        EditorPasteAsPayload(
          text: 'plain fallback',
          html: '<b>rich</b>',
          uriList:
              Uri.file('${temp.path}/workspace${Platform.pathSeparator}main.rs')
                  .toString(),
        );
    addTearDown(() async {
      EditorClipboard.forceFlutterClipboardFallbackForTesting =
          previousFallback;
      EditorClipboard.readForPasteAsOverrideForTesting = previousReadOverride;
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      await tester.pumpWidget(const SizedBox.shrink());
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    final workspace = Directory('${temp.path}/workspace')..createSync();
    final file = File('${workspace.path}/main.rs')
      ..writeAsStringSync('old text');
    final clipboard = <String, Object?>{'text': 'native fallback'};
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') return clipboard;
        return null;
      },
    );

    await tester.pumpWidget(AlulaApp(
      autoFolder: workspace.path,
      layoutStore: LayoutStore(path: '${temp.path}/layout.json'),
      sessionStore: SessionStore(path: '${temp.path}/session.json'),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('main.rs').first);
    await tester.pump(const Duration(milliseconds: 200));
    final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
    await tester.showKeyboard(editor);
    final controller = tester.widget<TextField>(editor).controller!;
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 8);
    await tester.pump();

    await _press(tester, LogicalKeyboardKey.keyV);
    final absolutePath = file.absolute.path.replaceAll('\\', '/');
    expect(controller.text, absolutePath);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('paste-as-widget')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('paste-as-widget')));
    await tester.pump();
    expect(
        find.byKey(const ValueKey('qi-Insert Relative Path')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('qi-Insert Relative Path')));
    await tester.pump();
    await tester.pump();
    expect(controller.text, 'main.rs');

    await _press(tester, LogicalKeyboardKey.keyZ);
    expect(controller.text, 'old text');
    await _press(tester, LogicalKeyboardKey.keyY);
    expect(controller.text, 'main.rs');
    await _press(tester, LogicalKeyboardKey.keyS);
    expect(file.readAsStringSync(), 'main.rs');
  });
}
