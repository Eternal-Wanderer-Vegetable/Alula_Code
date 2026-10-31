import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pressToggle(WidgetTester tester, TargetPlatform platform) async {
  if (platform == TargetPlatform.macOS) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  } else {
    await tester.sendKeyEvent(LogicalKeyboardKey.insert);
  }
  await tester.pump();
}

Future<void> _pressSave(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _sendCommandKey(
  WidgetTester tester,
  TargetPlatform platform,
  LogicalKeyboardKey key,
) async {
  final modifier = platform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

Future<void> _withTargetPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  for (final platform in const [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    testWidgets('$platform overtype toggles, replaces typed text, and saves',
        (tester) async {
      await _withTargetPlatform(platform, () async {
        final temp = Directory.systemTemp.createTempSync('alula-overtype');
        addTearDown(() async {
          debugDefaultTargetPlatformOverride = null;
          await tester.pumpWidget(const SizedBox.shrink());
          if (temp.existsSync()) temp.deleteSync(recursive: true);
        });

        final workspace = Directory('${temp.path}/workspace')..createSync();
        final file = File('${workspace.path}/sample.txt')
          ..writeAsStringSync('abcd');
        final base = temp.path.replaceAll(r'\', '/');
        await tester.pumpWidget(AlulaApp(
          autoFolder: workspace.path,
          layoutStore: LayoutStore(path: '$base/layout.json'),
          sessionStore: SessionStore(path: '$base/session.json'),
          keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
        ));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.tap(find.text('sample.txt').first);
        await tester.pump(const Duration(milliseconds: 300));

        final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
        await tester.showKeyboard(editor);
        await tester.pump();
        expect(find.byKey(const ValueKey('status-overtype')), findsNothing);

        await _pressToggle(tester, platform);
        expect(find.byKey(const ValueKey('status-overtype')), findsOneWidget);
        var field = tester.widget<RustTextInputField>(
          find.byType(RustTextInputField),
        );
        final document = field.inputWindow.document;
        final controller = tester.widget<TextField>(editor).controller!;
        controller.selection = const TextSelection.collapsed(offset: 1);
        await tester.pump();

        await tester.sendKeyDownEvent(
          LogicalKeyboardKey.keyX,
          character: 'X',
        );
        tester.testTextInput.updateEditingValue(const TextEditingValue(
          text: 'aXbcd',
          selection: TextSelection.collapsed(offset: 2),
        ));
        await tester.pump();
        await tester.pump();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyX);
        expect(controller.text, 'aXcd');
        expect(document.resync().content, 'aXcd');

        // Without a matching printable key event, platform paste remains an
        // insertion even while the global input mode is overtype.
        controller.selection = const TextSelection.collapsed(offset: 2);
        await tester.pump();
        tester.testTextInput.updateEditingValue(const TextEditingValue(
          text: 'aXPQcd',
          selection: TextSelection.collapsed(offset: 4),
        ));
        await tester.pump();
        await tester.pump();
        expect(controller.text, 'aXPQcd');
        expect(document.resync().content, 'aXPQcd');

        await _pressSave(tester);
        expect(file.readAsStringSync(), 'aXPQcd');

        await tester.tap(find.byKey(const ValueKey('status-overtype')));
        await tester.pump();
        expect(find.byKey(const ValueKey('status-overtype')), findsNothing);
        field = tester.widget<RustTextInputField>(
          find.byType(RustTextInputField),
        );
        expect(field.inputWindow.document.resync().content, 'aXPQcd');
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('$platform Ctrl/Cmd+V overwrites text and is undoable',
        (tester) async {
      await _withTargetPlatform(platform, () async {
        final temp =
            Directory.systemTemp.createTempSync('alula-overtype-paste');
        addTearDown(() async {
          debugDefaultTargetPlatformOverride = null;
          tester.binding.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
          await tester.pumpWidget(const SizedBox.shrink());
          if (temp.existsSync()) temp.deleteSync(recursive: true);
        });

        final workspace = Directory('${temp.path}/workspace')..createSync();
        final file = File('${workspace.path}/sample.txt')
          ..writeAsStringSync('abcdef');
        final base = temp.path.replaceAll(r'\', '/');
        Map<dynamic, dynamic> clipboard = const {'text': 'XYZ'};
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => call.method == 'Clipboard.getData' ? clipboard : null,
        );
        await tester.pumpWidget(AlulaApp(
          autoFolder: workspace.path,
          layoutStore: LayoutStore(path: '$base/layout.json'),
          sessionStore: SessionStore(path: '$base/session.json'),
          keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
        ));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.tap(find.text('sample.txt').first);
        await tester.pump(const Duration(milliseconds: 300));

        final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
        await tester.showKeyboard(editor);
        await tester.pump();
        await _pressToggle(tester, platform);
        final field = tester.widget<RustTextInputField>(
          find.byType(RustTextInputField),
        );
        final document = field.inputWindow.document;
        final controller = tester.widget<TextField>(editor).controller!;
        controller.selection = const TextSelection.collapsed(offset: 2);
        await tester.pump();

        await _sendCommandKey(tester, platform, LogicalKeyboardKey.keyV);
        await tester.pump();
        await tester.pump();
        expect(controller.text, 'abXYZf');
        expect(document.resync().content, 'abXYZf');
        expect(document.isDirty, isTrue);

        await _sendCommandKey(tester, platform, LogicalKeyboardKey.keyZ);
        await tester.pump();
        expect(document.resync().content, 'abcdef');
        await _sendCommandKey(tester, platform, LogicalKeyboardKey.keyY);
        await tester.pump();
        expect(document.resync().content, 'abXYZf');

        await _pressSave(tester);
        expect(file.readAsStringSync(), 'abXYZf');
        expect(document.resync().content, file.readAsStringSync());
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets(
        '$platform overtype paste distributes lines to multiple cursors',
        (tester) async {
      await _withTargetPlatform(platform, () async {
        final temp =
            Directory.systemTemp.createTempSync('alula-overtype-multicursor');
        addTearDown(() async {
          debugDefaultTargetPlatformOverride = null;
          tester.binding.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
          await tester.pumpWidget(const SizedBox.shrink());
          if (temp.existsSync()) temp.deleteSync(recursive: true);
        });

        final workspace = Directory('${temp.path}/workspace')..createSync();
        final file = File('${workspace.path}/sample.txt')
          ..writeAsStringSync('foo foo');
        final base = temp.path.replaceAll(r'\', '/');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => call.method == 'Clipboard.getData'
              ? const <String, Object?>{'text': 'X\nYZ'}
              : null,
        );
        await tester.pumpWidget(AlulaApp(
          autoFolder: workspace.path,
          layoutStore: LayoutStore(path: '$base/layout.json'),
          sessionStore: SessionStore(path: '$base/session.json'),
          keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
        ));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.tap(find.text('sample.txt').first);
        await tester.pump(const Duration(milliseconds: 300));

        final editor = find.byKey(const ValueKey('rust-bounded-text-input'));
        await tester.showKeyboard(editor);
        await tester.pump();
        final controller = tester.widget<TextField>(editor).controller!;
        controller.selection =
            const TextSelection(baseOffset: 0, extentOffset: 3);
        await tester.pump();
        await _sendCommandKey(tester, platform, LogicalKeyboardKey.keyD);
        final field = tester.widget<RustTextInputField>(
          find.byType(RustTextInputField),
        );
        expect(field.additionalSelections, hasLength(1));

        await _pressToggle(tester, platform);
        await _sendCommandKey(tester, platform, LogicalKeyboardKey.keyV);
        await tester.pump();
        await tester.pump();
        expect(controller.text, 'X YZ');
        expect(field.inputWindow.document.resync().content, 'X YZ');

        await _sendCommandKey(tester, platform, LogicalKeyboardKey.keyZ);
        await tester.pump();
        expect(field.inputWindow.document.resync().content, 'foo foo');
        await _sendCommandKey(tester, platform, LogicalKeyboardKey.keyY);
        await tester.pump();
        expect(field.inputWindow.document.resync().content, 'X YZ');

        await _pressSave(tester);
        expect(file.readAsStringSync(), 'X YZ');
        expect(tester.takeException(), isNull);
      });
    });
  }
}
