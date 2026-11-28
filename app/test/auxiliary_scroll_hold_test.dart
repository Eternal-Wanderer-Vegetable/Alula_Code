import 'dart:convert';
import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/workbench/auxiliary_focus_context.dart';
import 'package:alula_app/workbench/auxiliary_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auxiliary_window_test.dart' show dispatchPlatformMethod;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const focusChannel = MethodChannel('window_manager');
  const windows = MethodChannel('mixin.one/desktop_multi_window');
  const cross = MethodChannel('mixin.one/desktop_multi_window/channels');

  for (final chord in [false, true]) {
    testWidgets(
      'the auxiliary ${chord ? 'chord' : 'single key'} ends on key-up or native blur',
      (tester) async {
        final temp = Directory.systemTemp.createTempSync('alula-aux-hold-');
        addTearDown(() => temp.deleteSync(recursive: true));
        final bindings = File('${temp.path}/hold-keybindings.json');
        bindings.writeAsStringSync(jsonEncode([
          {
            'key': chord ? 'ctrl+k f8' : 'f8',
            'command': 'workbench.action.holdLockedScrolling',
            'when': 'editorTextFocus && !quickInputVisible',
          },
        ]));
        final payload = AuxiliaryWindowPayload.forDocument(
          documentId: 101,
          mainWindowId: 'main',
          name: 'aux-hold.txt',
          text: 'fixture 😀\r\n',
          dirty: false,
        );
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(windows, (call) async {
          if (call.method == 'getWindowDefinition') {
            return {
              'windowId': 'aux-1',
              'windowArgument': payload.toArguments()
            };
          }
          return null;
        });
        messenger.setMockMethodCallHandler(focusChannel, (call) async {
          if (call.method == 'isFocused') return true;
          if (call.method == 'isAlwaysOnTop') return false;
          return null;
        });
        final events = <Map<String, Object?>>[];
        messenger.setMockMethodCallHandler(cross, (call) async {
          if (call.method != 'invokeMethod') return null;
          final request = call.arguments as Map;
          switch (request['method']) {
            case auxiliaryFocusContextMethod:
              return {
                'windowId': 'aux-1',
                'groupId': 'aux-1:editor',
                'revision': 1
              };
            case auxiliaryLockedScrollingMethod:
              return {'revision': 0, 'active': false};
            case auxiliaryLockedScrollHoldMethod:
              final arguments =
                  Map<String, Object?>.from(request['arguments'] as Map);
              expect(arguments['windowId'], 'aux-1');
              if (arguments['keybindings'] == true) return bindings.path;
              events.add(arguments);
              return true;
          }
          return null;
        });
        addTearDown(() {
          for (final channel in [windows, focusChannel, cross]) {
            messenger.setMockMethodCallHandler(channel, null);
          }
        });
        await tester.pumpWidget(AuxiliaryEditorApp(payload: payload));
        await tester.pumpAndSettle();
        final editor =
            tester.widget<RustTextInputField>(find.byType(RustTextInputField));
        editor.focusNode!.requestFocus();
        await tester.pumpAndSettle();

        Future<void> prefix() async {
          if (!chord) return;
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        }

        await prefix();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.f8);
        await tester.pump();
        expect(events.map((e) => e['held']), [true]);
        await tester.sendKeyEvent(LogicalKeyboardKey.f9);
        await tester.pump();
        expect(events.map((e) => e['held']), [true, false]);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.f8);
        await prefix();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.f8);
        await tester.pump();
        await dispatchPlatformMethod(tester, focusChannel.name,
            const MethodCall('onEvent', {'eventName': 'blur'}));
        await tester.pump();
        expect(events.map((e) => e['held']), [true, false, true, false]);
        expect(events.map((e) => e['sequence']), [1, 2, 3, 4]);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.f8);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(events, hasLength(4));
      },
    );
  }
}
