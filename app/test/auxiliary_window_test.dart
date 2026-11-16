import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/workbench/auxiliary_focus_context.dart';
import 'package:alula_app/workbench/auxiliary_window.dart';
import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

Future<Object?> dispatchPlatformMethod(
  WidgetTester tester,
  String channel,
  MethodCall call,
) async {
  const codec = StandardMethodCodec();
  final response =
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    channel,
    codec.encodeMethodCall(call),
    null,
  );
  return response == null ? null : codec.decodeEnvelope(response);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuxiliaryWindowPayload', () {
    test('document payload round-trips through arguments', () {
      final payload = AuxiliaryWindowPayload.forDocument(
        path: 'C:/ws/src/main.rs',
        mainWindowId: 'main-0',
        name: 'main.rs',
        text: 'fn main() {}',
        dirty: true,
      );
      final parsed = AuxiliaryWindowPayload.fromArguments(
        payload.toArguments(),
      );
      expect(parsed.isAuxiliary, isTrue);
      expect(parsed.path, 'C:/ws/src/main.rs');
      expect(parsed.mainWindowId, 'main-0');
      expect(parsed.name, 'main.rs');
      expect(parsed.text, 'fn main() {}');
      expect(parsed.dirty, isTrue);
    });

    test('untitled payloads keep a null path', () {
      final payload = AuxiliaryWindowPayload.forDocument(
        name: '未命名',
        text: 'body',
        dirty: false,
      );
      final parsed = AuxiliaryWindowPayload.fromArguments(
        payload.toArguments(),
      );
      expect(parsed.path, isNull);
      expect(parsed.text, 'body');
      expect(parsed.dirty, isFalse);
    });

    test('main-window arguments parse as non-auxiliary', () {
      expect(
        AuxiliaryWindowPayload.fromArguments('--lsp-auto').isAuxiliary,
        isFalse,
      );
      expect(AuxiliaryWindowPayload.fromArguments('').isAuxiliary, isFalse);
    });
  });

  group('auxiliary always-on-top control', () {
    const windowManagerChannel = MethodChannel('window_manager');

    Future<void> mountAuxiliary(
      WidgetTester tester,
      AuxiliaryWindowPayload payload,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: AuxiliaryEditorApp(payload: payload)),
      );
      await tester.pumpAndSettle();
    }

    Finder auxiliaryPinSemantics() =>
        find.byKey(const ValueKey('auxiliary-always-on-top-semantics'));

    void expectWindowStateErrorAnnounced(
      WidgetTester tester,
      String messageFragment,
    ) {
      final error = tester.getSemantics(
        find.byKey(const ValueKey('auxiliary-window-state-error')),
      );
      final message = error.getSemanticsData().label;
      expect(message, contains(messageFragment));
      expect(
        error,
        matchesSemantics(label: message, isLiveRegion: true),
      );
    }

    void expectAuxiliaryDocumentUnchanged(
      WidgetTester tester,
      AuxiliaryWindowPayload payload,
      String originalArguments,
    ) {
      final editor = tester.widget<RustTextInputField>(
        find.byType(RustTextInputField),
      );
      expect(editor.inputWindow.text, payload.text);
      expect(editor.inputWindow.document.resync().content, payload.text);
      expect(editor.inputWindow.document.isDirty, payload.dirty);
      expect(payload.toArguments(), originalArguments,
          reason: 'pinning must not rewrite the transferred session payload');
    }

    testWidgets(
      'reads native state and waits for successful on/off changes without touching the document',
      (tester) async {
        const body = 'first line\r\nsecond 😀 line\n';
        final payload = AuxiliaryWindowPayload.forDocument(
          name: 'notes.txt',
          mainWindowId: 'main',
          text: body,
          dirty: true,
        );
        final originalArguments = payload.toArguments();
        final calls = <MethodCall>[];
        final setValues = <bool>[];
        var nativeAlwaysOnTop = false;
        var blockNextSet = false;
        final nativeSetGate = Completer<void>();

        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          windowManagerChannel,
          (call) async {
            calls.add(call);
            if (call.method == 'isAlwaysOnTop') return nativeAlwaysOnTop;
            if (call.method == 'isFocused') return false;
            if (call.method == 'setPreventClose') return null;
            if (call.method == 'setAlwaysOnTop') {
              final desired = (call.arguments as Map)['isAlwaysOnTop'] as bool;
              setValues.add(desired);
              if (blockNextSet) {
                blockNextSet = false;
                await nativeSetGate.future;
              }
              nativeAlwaysOnTop = desired;
              return null;
            }
            fail('Unexpected window_manager method: ${call.method}');
          },
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            windowManagerChannel,
            null,
          );
        });

        await mountAuxiliary(tester, payload);
        expect(calls.map((call) => call.method), contains('isAlwaysOnTop'));
        expect(
          tester.getSemantics(auxiliaryPinSemantics()),
          matchesSemantics(
            label: '始终置顶',
            isButton: true,
            hasEnabledState: true,
            hasTapAction: true,
            hasToggledState: true,
            isToggled: false,
            isEnabled: true,
          ),
        );
        expect(find.byTooltip('始终置顶'), findsOneWidget);
        expectAuxiliaryDocumentUnchanged(tester, payload, originalArguments);

        blockNextSet = true;
        await tester.tap(
          find.byKey(const ValueKey('auxiliary-always-on-top-button')),
        );
        await tester.pump();
        expect(setValues, [true]);
        expect(
          tester.getSemantics(auxiliaryPinSemantics()),
          matchesSemantics(
            label: '始终置顶',
            isButton: true,
            hasEnabledState: true,
            hasTapAction: false,
            hasToggledState: true,
            isToggled: false,
            isEnabled: false,
          ),
          reason: 'the visible check state waits for the platform call',
        );

        nativeSetGate.complete();
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(auxiliaryPinSemantics()),
          matchesSemantics(
            label: '始终置顶',
            isButton: true,
            hasEnabledState: true,
            hasTapAction: true,
            hasToggledState: true,
            isToggled: true,
            isEnabled: true,
          ),
        );
        expect(find.byTooltip('取消始终置顶'), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('auxiliary-always-on-top-button')),
        );
        await tester.pumpAndSettle();
        expect(setValues, [true, false]);
        expect(
          tester.getSemantics(auxiliaryPinSemantics()),
          matchesSemantics(
            label: '始终置顶',
            isButton: true,
            hasEnabledState: true,
            hasTapAction: true,
            hasToggledState: true,
            isToggled: false,
            isEnabled: true,
          ),
        );
        expectAuxiliaryDocumentUnchanged(tester, payload, originalArguments);
      },
    );

    testWidgets(
        'a failed native change keeps the prior state and shows an error',
        (tester) async {
      const body = 'unsaved text';
      final payload = AuxiliaryWindowPayload.forDocument(
        name: 'draft.txt',
        text: body,
        dirty: true,
      );
      final originalArguments = payload.toArguments();

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        windowManagerChannel,
        (call) async {
          if (call.method == 'isFocused') return false;
          if (call.method == 'setPreventClose') return null;
          if (call.method == 'isAlwaysOnTop') return true;
          if (call.method == 'setAlwaysOnTop') {
            throw PlatformException(code: 'test-failure');
          }
          fail('Unexpected window_manager method: ${call.method}');
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          windowManagerChannel,
          null,
        );
      });

      await mountAuxiliary(tester, payload);
      expect(
        tester.getSemantics(auxiliaryPinSemantics()),
        matchesSemantics(
          label: '始终置顶',
          isButton: true,
          hasEnabledState: true,
          hasTapAction: true,
          hasToggledState: true,
          isToggled: true,
          isEnabled: true,
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('auxiliary-always-on-top-button')),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(auxiliaryPinSemantics()),
        matchesSemantics(
          label: '始终置顶',
          isButton: true,
          hasEnabledState: true,
          hasTapAction: true,
          hasToggledState: true,
          isToggled: true,
          isEnabled: true,
        ),
      );
      expect(find.textContaining('置顶切换失败'), findsOneWidget);
      expectWindowStateErrorAnnounced(tester, '置顶切换失败');
      expect(find.byTooltip('取消始终置顶'), findsOneWidget);
      expectAuxiliaryDocumentUnchanged(tester, payload, originalArguments);
    });

    testWidgets(
        'an unreadable initial state disables the toggle and reports why',
        (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        windowManagerChannel,
        (call) async => throw PlatformException(code: 'state-unavailable'),
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          windowManagerChannel,
          null,
        );
      });

      await mountAuxiliary(
        tester,
        AuxiliaryWindowPayload.forDocument(
          name: 'unavailable.txt',
          text: 'content',
          dirty: false,
        ),
      );

      expect(
        tester.getSemantics(auxiliaryPinSemantics()),
        matchesSemantics(
          label: '始终置顶',
          isButton: true,
          hasEnabledState: true,
          hasTapAction: false,
          hasToggledState: false,
          isEnabled: false,
        ),
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('auxiliary-always-on-top-button')),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('读取置顶状态失败'), findsOneWidget);
      expectWindowStateErrorAnnounced(tester, '读取置顶状态失败');
    });
  });

  group('auxiliary active focus context', () {
    testWidgets(
      'sends focus metadata without changing text, selection, savepoint, or payload',
      (tester) async {
        const body = 'dirty\r\nemoji 😀\n';
        const selection = TextSelection(baseOffset: 1, extentOffset: 4);
        final payload = AuxiliaryWindowPayload.forDocument(
          name: 'notes.txt',
          mainWindowId: 'main',
          text: body,
          dirty: true,
        );
        final originalArguments = payload.toArguments();
        final focusEvents = <Map<String, Object?>>[];
        var nativeFocused = false;

        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('mixin.one/desktop_multi_window'),
          (call) async {
            if (call.method == 'getWindowDefinition') {
              return {
                'windowId': 'aux-1',
                'windowArgument': originalArguments,
              };
            }
            if (call.method == 'getAllWindows') {
              return [
                {'windowId': 'main', 'windowArgument': ''},
                {
                  'windowId': 'aux-1',
                  'windowArgument': originalArguments,
                },
              ];
            }
            return null;
          },
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('mixin.one/desktop_multi_window/channels'),
          (call) async {
            if (call.method == 'invokeMethod') {
              final request = Map<String, Object?>.from(
                call.arguments as Map,
              );
              if (request['method'] == auxiliaryFocusContextMethod) {
                final event = Map<String, Object?>.from(
                  request['arguments'] as Map,
                );
                focusEvents.add(event);
                return {
                  'windowId': event['focused'] == true ? 'aux-1' : 'main',
                  'groupId':
                      event['focused'] == true ? 'aux-1:editor' : 'main:editor',
                  'documentId': null,
                  'revision': focusEvents.length,
                };
              }
            }
            return null;
          },
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (call) async {
            if (call.method == 'isAlwaysOnTop') return false;
            if (call.method == 'isFocused') return nativeFocused;
            if (call.method == 'setPreventClose') return null;
            return null;
          },
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('mixin.one/desktop_multi_window'),
            null,
          );
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('mixin.one/desktop_multi_window/channels'),
            null,
          );
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('window_manager'),
            null,
          );
        });

        await tester.pumpWidget(
          MaterialApp(home: AuxiliaryEditorApp(payload: payload)),
        );
        await tester.pumpAndSettle();
        expect(focusEvents.first['type'], 'register');
        expect(
            focusEvents.first.keys,
            containsAll([
              'protocol',
              'type',
              'windowId',
              'sequence',
              'groupId',
              'documentId',
              'focused',
            ]));
        expect(focusEvents.first, isNot(contains('text')));
        expect(focusEvents.first, isNot(contains('dirty')));

        final field = tester.state<RustTextInputFieldState>(
          find.byType(RustTextInputField),
        );
        field.setSelection(selection);
        await tester.pump();
        final document = field.widget.inputWindow.document;
        final savepointState = document.isDirty;

        nativeFocused = true;
        await dispatchPlatformMethod(
          tester,
          'window_manager',
          const MethodCall('onEvent', {'eventName': 'focus'}),
        );
        await tester.pumpAndSettle();
        await dispatchPlatformMethod(
          tester,
          'window_manager',
          const MethodCall('onEvent', {'eventName': 'blur'}),
        );
        await tester.pumpAndSettle();

        final updates =
            focusEvents.where((event) => event['type'] == 'update').toList();
        expect(updates.map((event) => event['focused']), [false, true, false]);
        expect(field.widget.inputWindow.text, body);
        expect(document.resync().content, body);
        expect(field.editingValue.selection, selection);
        expect(document.isDirty, savepointState);
        expect(payload.toArguments(), originalArguments);
      },
    );
  });

  group('main-window move flow', () {
    late Directory temp;
    late LayoutStore layoutStore;
    late SessionStore sessionStore;
    final createdPayloads = <String>[];
    final auxiliarySnapshotMessages = <Map<String, Object?>>[];
    CommandService? commands;

    String baseOf() => temp.path.replaceAll(r'\', '/');

    setUp(() {
      temp = Directory.systemTemp.createTempSync('alula-aux-window');
      Directory('${temp.path}/workspace').createSync();
      layoutStore = LayoutStore(path: '${baseOf()}/layout.json');
      sessionStore = SessionStore(path: '${baseOf()}/session.json');
      createdPayloads.clear();
      auxiliarySnapshotMessages.clear();
    });

    Future<void> mountWorkbench(WidgetTester tester) async {
      tester.view.physicalSize = const Size(2400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final untitled = File('${temp.path}/journal-copy.txt')
        ..writeAsStringSync('moved body');
      File('${baseOf()}/session.json').writeAsStringSync(jsonEncode({
        'v': 1,
        'editorTabMode': 'multiple',
        'focused': 'editor',
        'groups': [
          {
            'region': 'editor',
            'docs': [
              {
                'id': 10,
                'name': 'journal-copy.txt',
                'path': untitled.path,
                'text': 'moved body',
              },
            ],
            'active': 10,
          },
        ],
      }));
      await tester.pumpWidget(MaterialApp(
        home: WorkbenchPage(
          autoFolder: '${temp.path}/workspace',
          layoutStore: layoutStore,
          sessionStore: sessionStore,
          keybindingsStore:
              KeybindingsStore(path: '${baseOf()}/keybindings.json'),
          onCommandServiceReady: (service) => commands = service,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 600));
      expect(commands, isNotNull);
    }

    testWidgets(
      'the command captures the document payload and removes the source view',
      (tester) async {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('mixin.one/desktop_multi_window'),
          (call) async {
            if (call.method == 'createWindow') {
              final config = call.arguments as Map<dynamic, dynamic>;
              createdPayloads.add(config['arguments'] as String);
              return 'aux-1';
            }
            if (call.method == 'getWindowDefinition') {
              return {'windowId': 'main', 'windowArgument': ''};
            }
            return null;
          },
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('mixin.one/desktop_multi_window/channels'),
          (call) async {
            if (call.method == 'invokeMethod') {
              final request = Map<String, Object?>.from(
                call.arguments as Map,
              );
              if (request['method'] == auxiliaryFocusContextMethod) {
                auxiliarySnapshotMessages.add(
                  Map<String, Object?>.from(request['arguments'] as Map),
                );
              }
            }
            return null;
          },
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (call) async => throw PlatformException(code: 'focus-unavailable'),
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('mixin.one/desktop_multi_window'),
            null,
          );
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('mixin.one/desktop_multi_window/channels'),
            null,
          );
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('window_manager'),
            null,
          );
        });

        await mountWorkbench(tester);
        final mainWindowState = tester.state(find.byType(WorkbenchPage));
        expect(
          windowManager.listeners,
          contains(mainWindowState),
          reason: 'the main workbench must observe native focus changes',
        );
        expect(find.byKey(const ValueKey('tab-10')), findsOneWidget);

        await commands!.execute('workbench.action.moveEditorToNewWindow');
        await tester.pumpAndSettle();
        // 推进 500ms 会话保存防抖，使断言读到持久化状态。
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pumpAndSettle();

        expect(createdPayloads, hasLength(1),
            reason: 'the move creates one auxiliary window');
        final parsed = AuxiliaryWindowPayload.fromArguments(
          createdPayloads.single,
        );
        expect(parsed.isAuxiliary, isTrue);
        expect(parsed.mainWindowId, 'main');
        expect(parsed.name, 'journal-copy.txt');
        expect(parsed.text, 'moved body',
            reason: 'the document text travels with the window');
        expect(find.byKey(const ValueKey('tab-10')), findsNothing,
            reason: 'the source group loses the moved view');
        final groups = (sessionStore.tryLoad()?['groups'] as List).cast<Map>();
        expect(groups, hasLength(1),
            reason: 'the focused group remains (welcome untitled)');
        final docs = (groups.single['docs'] as List).cast<Map>();
        expect(docs.where((doc) => doc['id'] == 10), isEmpty,
            reason: 'the moved document no longer belongs to any group');
        auxiliarySnapshotMessages.clear();

        Future<Object?> sendFocusEvent(AuxiliaryFocusContextEvent event) =>
            dispatchPlatformMethod(
              tester,
              'mixin.one/desktop_multi_window/channels',
              MethodCall('methodCall', {
                'channel': 'mixin.one/window_controller/main',
                'method': auxiliaryFocusContextMethod,
                'arguments': event.toMap(),
              }),
            );

        final registeredSnapshot = AuxiliaryFocusContextSnapshot.tryParse(
          await sendFocusEvent(const AuxiliaryFocusContextEvent(
            kind: AuxiliaryFocusEventKind.register,
            windowId: 'aux-1',
            sequence: 1,
            groupId: 'aux-1:editor',
            documentId: 'file:/workspace/aux.dart',
            focused: false,
          )),
        );
        expect(registeredSnapshot?.windowId, 'main');

        final activeSnapshot = AuxiliaryFocusContextSnapshot.tryParse(
          await sendFocusEvent(const AuxiliaryFocusContextEvent(
            kind: AuxiliaryFocusEventKind.update,
            windowId: 'aux-1',
            sequence: 2,
            groupId: 'aux-1:editor',
            documentId: 'file:/workspace/aux.dart',
            focused: true,
          )),
        );
        expect(activeSnapshot?.windowId, 'aux-1');
        expect(auxiliarySnapshotMessages, hasLength(1));
        expect(auxiliarySnapshotMessages.single.keys.toSet(), {
          'windowId',
          'groupId',
          'documentId',
          'revision',
        });
        expect(auxiliarySnapshotMessages.single['windowId'], 'aux-1');

        final staleSnapshot = AuxiliaryFocusContextSnapshot.tryParse(
          await sendFocusEvent(const AuxiliaryFocusContextEvent(
            kind: AuxiliaryFocusEventKind.update,
            windowId: 'aux-1',
            sequence: 1,
            groupId: 'aux-1:stale',
            documentId: 'file:/workspace/stale.dart',
            focused: false,
          )),
        );
        expect(staleSnapshot?.windowId, 'aux-1');
        expect(staleSnapshot?.groupId, 'aux-1:editor');
        expect(auxiliarySnapshotMessages, hasLength(1),
            reason: 'stale events do not rebroadcast');
        expect(createdPayloads.single, parsed.toArguments());

        await dispatchPlatformMethod(
          tester,
          'window_manager',
          const MethodCall('onEvent', {'eventName': 'focus'}),
        );
        await tester.pumpAndSettle();
        expect(auxiliarySnapshotMessages, hasLength(2));
        expect(auxiliarySnapshotMessages.last['windowId'], 'main',
            reason: 'main native focus must reclaim the active owner');

        await tester.pumpWidget(const SizedBox.shrink());
        expect(windowManager.listeners, isNot(contains(mainWindowState)),
            reason: 'the main focus listener must be removed on dispose');
      },
    );
  });
}
