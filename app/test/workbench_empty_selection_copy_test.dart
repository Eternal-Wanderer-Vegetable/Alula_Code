import 'dart:io';

import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cases = <({TargetPlatform platform, String source, String expected})>[
    (
      platform: TargetPlatform.windows,
      source: 'head\nlast',
      expected: 'last\r\n',
    ),
    (
      platform: TargetPlatform.linux,
      source: 'head\nlast',
      expected: 'last\n',
    ),
    (
      platform: TargetPlatform.macOS,
      source: 'head\r\nlast',
      expected: 'last\r\n',
    ),
  ];

  for (final testCase in cases) {
    testWidgets(
      'TargetPlatform.${testCase.platform.name} copies the current line at an empty selection',
      (tester) async {
        final originalPlatform = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = testCase.platform;
        final temp = Directory.systemTemp.createTempSync('alula-copy-line');
        final workspace = Directory('${temp.path}/workspace')..createSync();
        final file = File('${workspace.path}/sample.txt')
          ..writeAsStringSync(testCase.source);
        final originalBytes = file.readAsBytesSync();
        final base = temp.path.replaceAll(r'\', '/');
        Map<dynamic, dynamic> clipboard = const {};
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboard = Map<dynamic, dynamic>.from(call.arguments as Map);
            }
            if (call.method == 'Clipboard.getData') return clipboard;
            return null;
          },
        );
        addTearDown(() async {
          debugDefaultTargetPlatformOverride = originalPlatform;
          tester.binding.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
          await tester.pumpWidget(const SizedBox.shrink());
          if (temp.existsSync()) temp.deleteSync(recursive: true);
        });

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
        expect(controller.text, 'head\nlast');
        controller.selection = TextSelection.collapsed(
          offset: controller.text.indexOf('last') + 2,
        );
        await tester.pump();

        final modifier = testCase.platform == TargetPlatform.macOS
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(modifier);
        await tester.pump();
        await tester.pump();
        debugDefaultTargetPlatformOverride = originalPlatform;

        expect(clipboard['text'], testCase.expected);
        expect(controller.text, 'head\nlast');
        expect(file.readAsBytesSync(), originalBytes);
      },
    );
  }
}
