import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/editor/rust_text_input_window.dart';
import 'package:alula_app/workbench/auxiliary_focus_context.dart';
import 'package:alula_app/workbench/auxiliary_window.dart';
import 'package:alula_app/workbench/auxiliary_window_transfer.dart';
import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
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

class _AuxiliaryDragSession extends Fake implements DragSession {
  @override
  final ValueNotifier<DropOperation?> dragCompleted = ValueNotifier(null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuxiliaryWindowPayload', () {
    test('document payload round-trips through arguments', () {
      final payload = AuxiliaryWindowPayload.forDocument(
        documentId: 100,
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
      expect(parsed.documentId, 100);
      expect(parsed.name, 'main.rs');
      expect(parsed.text, 'fn main() {}');
      expect(parsed.dirty, isTrue);
    });

    test('untitled payloads keep a null path', () {
      final payload = AuxiliaryWindowPayload.forDocument(
        documentId: 100,
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
          documentId: 100,
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
        documentId: 100,
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
          documentId: 100,
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
      'routes focus metadata and locked scrolling without changing the document',
      (tester) async {
        const body = 'dirty\r\nemoji 😀\n';
        const selection = TextSelection(baseOffset: 1, extentOffset: 4);
        final payload = AuxiliaryWindowPayload.forDocument(
          documentId: 100,
          name: 'notes.txt',
          mainWindowId: 'main',
          text: body,
          dirty: true,
        );
        final originalArguments = payload.toArguments();
        final focusEvents = <Map<String, Object?>>[];
        var nativeFocused = false;
        final lockRequests = <Map<String, Object?>>[];
        var ownerRevision = 1;
        var ownerLocked = false;

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
              if (request['method'] == auxiliaryLockedScrollingMethod) {
                final args = Map<String, Object?>.from(
                  request['arguments'] as Map,
                );
                lockRequests.add(args);
                if (args['toggle'] == true) {
                  ownerLocked = !ownerLocked;
                  ownerRevision++;
                }
                return {'revision': ownerRevision, 'active': ownerLocked};
              }
              if (request['method'] == auxiliaryFocusContextMethod) {
                final event = Map<String, Object?>.from(
                  request['arguments'] as Map,
                );
                focusEvents.add(event);
                return {
                  'windowId': event['focused'] == true ? 'aux-1' : 'main',
                  'groupId':
                      event['focused'] == true ? 'aux-1:editor' : 'main:editor',
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
              'focused',
            ]));
        expect(focusEvents.first, isNot(contains('documentId')));
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

        final status = find.byKey(
          const ValueKey('status-bar-locked-scrolling'),
        );
        expect(status, findsNothing);
        expect(lockRequests, [
          {'windowId': 'aux-1', 'toggle': false},
        ]);
        Future<void> publish(int revision, Object active) async {
          await dispatchPlatformMethod(
            tester,
            'mixin.one/desktop_multi_window/channels',
            MethodCall('methodCall', {
              'channel': 'mixin.one/window_controller/aux-1',
              'method': auxiliaryLockedScrollingMethod,
              'arguments': {'revision': revision, 'active': active},
            }),
          );
          await tester.pumpAndSettle();
        }

        ownerRevision = 3;
        ownerLocked = true;
        await publish(ownerRevision, ownerLocked);
        expect(status, findsOneWidget);
        await publish(2, false);
        await publish(4, 'invalid');
        expect(
          status,
          findsOneWidget,
          reason: 'stale and malformed snapshots are ignored',
        );

        await tester.tap(status);
        await tester.pumpAndSettle();
        expect(lockRequests.last, {'windowId': 'aux-1', 'toggle': true});
        expect(status, findsNothing);
        field.widget.focusNode!.requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.f1);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('qi-查看: 切换锁定滚动')));
        await tester.pumpAndSettle();
        expect(lockRequests, hasLength(3));
        expect(lockRequests.last, {'windowId': 'aux-1', 'toggle': true});
        expect(status, findsOneWidget);
        expect(document.resync().content, body);
        expect(document.isDirty, savepointState);
        expect(payload.toArguments(), originalArguments);
      },
    );
  });

  group('auxiliary document transfer protocol', () {
    const windowManagerChannel = MethodChannel('window_manager');
    const windowsChannel = MethodChannel('mixin.one/desktop_multi_window');
    const crossWindowChannel =
        MethodChannel('mixin.one/desktop_multi_window/channels');

    testWidgets('prepares, aborts, and commits without losing either document',
        (tester) async {
      const previousText = 'target dirty\r\n😀\n';
      const incomingText = 'source dirty\r\n🪺\n';
      final initialPayload = AuxiliaryWindowPayload.forDocument(
        documentId: 100,
        mainWindowId: 'main',
        name: 'target.txt',
        text: previousText,
        dirty: true,
      );
      final incomingPayload = AuxiliaryWindowPayload.forDocument(
        documentId: 101,
        mainWindowId: 'main',
        name: 'source.txt',
        text: incomingText,
        dirty: true,
      );
      final outboundBounds = <Map<String, Object?>>[];
      final returnedDocuments = <Map<String, Object?>>[];
      final nativeTitles = <String>[];
      final nativeCloseCalls = <String>[];
      var reportedBounds = const Rect.fromLTWH(500, 100, 640, 480);

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        windowsChannel,
        (call) async {
          if (call.method == 'getWindowDefinition') {
            return {
              'windowId': 'aux-1',
              'windowArgument': initialPayload.toArguments(),
            };
          }
          if (call.method == 'getAllWindows') {
            return [
              {'windowId': 'main', 'windowArgument': ''},
              {
                'windowId': 'aux-1',
                'windowArgument': initialPayload.toArguments(),
              },
            ];
          }
          return null;
        },
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        crossWindowChannel,
        (call) async {
          if (call.method == 'invokeMethod') {
            final request = Map<String, Object?>.from(call.arguments as Map);
            if (request['method'] == auxiliaryFocusContextMethod) {
              final event = Map<String, Object?>.from(
                request['arguments'] as Map,
              );
              return {
                'windowId': 'main',
                'groupId': 'main:editor',
                'revision': event['sequence'],
              };
            }
            if (request['method'] == auxiliaryWindowBoundsMethod) {
              outboundBounds.add(
                Map<String, Object?>.from(request['arguments'] as Map),
              );
            }
            if (request['method'] == auxiliaryWindowCloseReturnMethod) {
              returnedDocuments.add(
                Map<String, Object?>.from(request['arguments'] as Map),
              );
              return true;
            }
          }
          return null;
        },
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        windowManagerChannel,
        (call) async {
          if (call.method == 'isAlwaysOnTop') return false;
          if (call.method == 'isFocused') return false;
          if (call.method == 'setPreventClose') return null;
          if (call.method == 'hide' ||
              call.method == 'close' ||
              call.method == 'destroy') {
            nativeCloseCalls.add(call.method);
          }
          if (call.method == 'getBounds') {
            return {
              'x': reportedBounds.left,
              'y': reportedBounds.top,
              'width': reportedBounds.width,
              'height': reportedBounds.height,
            };
          }
          if (call.method == 'setTitle') {
            nativeTitles.add(
              (call.arguments as Map)['title'] as String,
            );
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          windowsChannel,
          null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          crossWindowChannel,
          null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          windowManagerChannel,
          null,
        );
      });

      await tester.pumpWidget(
        MaterialApp(home: AuxiliaryEditorApp(payload: initialPayload)),
      );
      await tester.pumpAndSettle();
      expect(outboundBounds, hasLength(1));
      expect(outboundBounds.single['windowId'], 'aux-1');
      expect(outboundBounds.single['left'], 500.0);

      reportedBounds = const Rect.fromLTWH(720, 180, 680, 500);
      await dispatchPlatformMethod(
        tester,
        windowManagerChannel.name,
        const MethodCall('onEvent', {'eventName': 'moved'}),
      );
      await tester.pumpAndSettle();
      expect(outboundBounds, hasLength(2));
      expect(outboundBounds.last['sequence'], 2);
      expect(outboundBounds.last['left'], 720.0);

      reportedBounds = const Rect.fromLTWH(720, 180, 900, 620);
      await dispatchPlatformMethod(
        tester,
        windowManagerChannel.name,
        const MethodCall('onEvent', {'eventName': 'resized'}),
      );
      await tester.pumpAndSettle();
      expect(outboundBounds, hasLength(3));
      expect(outboundBounds.last['sequence'], 3);
      expect(outboundBounds.last['width'], 900.0);

      final prepareMethod = MethodCall('methodCall', {
        'channel': 'mixin.one/window_controller/aux-1',
        'method': auxiliaryDocumentTransferPrepareMethod,
        'arguments': {
          'requestId': 'main:1',
          'document': incomingPayload.toMap(),
        },
      });
      for (final invalidId in [null, initialPayload.documentId]) {
        final rejected = await dispatchPlatformMethod(
          tester,
          crossWindowChannel.name,
          MethodCall('methodCall', {
            'channel': 'mixin.one/window_controller/aux-1',
            'method': auxiliaryDocumentTransferPrepareMethod,
            'arguments': {
              'requestId': 'main:1',
              'document': {...incomingPayload.toMap(), 'documentId': invalidId},
            },
          }),
        ) as Map;
        expect(rejected['status'], 'rejected');
      }
      final prepared = await dispatchPlatformMethod(
        tester,
        crossWindowChannel.name,
        prepareMethod,
      ) as Map;
      expect(prepared['status'], 'prepared');
      final returned = AuxiliaryWindowPayload.fromArguments(
        jsonEncode(prepared['previousDocument']),
      );
      expect(returned.name, 'target.txt');
      expect(returned.text, previousText);
      expect(returned.dirty, isTrue);
      expect(
        tester
            .widget<RustTextInputField>(find.byType(RustTextInputField))
            .inputWindow
            .document
            .resync()
            .content,
        previousText,
        reason: 'prepare must leave the target document visible and intact',
      );

      final targetEditorBeforeTransfer =
          tester.widget<RustTextInputField>(find.byType(RustTextInputField));
      final targetDocumentBeforeTransfer =
          targetEditorBeforeTransfer.inputWindow.document;
      expect(targetDocumentBeforeTransfer.id, initialPayload.documentId);
      final delayedInputDelta = RustTextInputDelta(
        operations: const [TextOp.insert(0, 'late ')],
        version: targetEditorBeforeTransfer.inputWindow.version,
        documentLengthUtf16: previousText.length + 'late '.length,
        selection: const TextSelection.collapsed(offset: 5),
        selectionWindow: const TextSelection.collapsed(offset: 5),
        composingWindow: null,
        replacedDocumentRange: null,
      );
      targetEditorBeforeTransfer.onDelta!(delayedInputDelta);
      expect(
        targetDocumentBeforeTransfer.resync().content,
        previousText,
        reason: 'late input must not mutate a document while prepared',
      );

      final aborted = await dispatchPlatformMethod(
        tester,
        crossWindowChannel.name,
        const MethodCall('methodCall', {
          'channel': 'mixin.one/window_controller/aux-1',
          'method': auxiliaryDocumentTransferAbortMethod,
          'arguments': {'requestId': 'main:1'},
        }),
      ) as Map;
      expect(aborted['status'], 'aborted');
      expect(
        tester
            .widget<RustTextInputField>(find.byType(RustTextInputField))
            .inputWindow
            .document
            .resync()
            .content,
        previousText,
      );

      final preparedAgain = await dispatchPlatformMethod(
        tester,
        crossWindowChannel.name,
        MethodCall('methodCall', {
          'channel': 'mixin.one/window_controller/aux-1',
          'method': auxiliaryDocumentTransferPrepareMethod,
          'arguments': {
            'requestId': 'main:2',
            'document': incomingPayload.toMap(),
          },
        }),
      ) as Map;
      expect(preparedAgain['status'], 'prepared');
      final committed = await dispatchPlatformMethod(
        tester,
        crossWindowChannel.name,
        const MethodCall('methodCall', {
          'channel': 'mixin.one/window_controller/aux-1',
          'method': auxiliaryDocumentTransferCommitMethod,
          'arguments': {'requestId': 'main:2'},
        }),
      ) as Map;
      expect(committed['status'], 'committed');
      await tester.pumpAndSettle();

      final input = tester.widget<RustTextInputField>(
        find.byType(RustTextInputField),
      );
      expect(input.inputWindow.document.resync().content, incomingText);
      expect(input.inputWindow.document.isDirty, isTrue);
      expect(find.text('source.txt'), findsOneWidget);
      final tab = find.byKey(const ValueKey('auxiliary-editor-active-tab'));
      final closeAction =
          find.byKey(const ValueKey('auxiliary-editor-tab-close'));
      expect(
          tester.getSemantics(tab).getSemanticsData().label, 'source.txt，未保存');
      expect(
        find.descendant(of: closeAction, matching: find.byIcon(Icons.circle)),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      expect(nativeTitles, contains('source.txt'));
      targetEditorBeforeTransfer.onDelta!(delayedInputDelta);
      expect(
        input.inputWindow.document.resync().content,
        incomingText,
        reason: 'a stale editor callback must not mutate the incoming document',
      );

      final repeatedCommit = await dispatchPlatformMethod(
        tester,
        crossWindowChannel.name,
        const MethodCall('methodCall', {
          'channel': 'mixin.one/window_controller/aux-1',
          'method': auxiliaryDocumentTransferCommitMethod,
          'arguments': {'requestId': 'main:2'},
        }),
      ) as Map;
      expect(repeatedCommit['status'], 'committed',
          reason:
              'the commit response is idempotent after an acknowledgement loss');

      await tester.tap(find.byKey(const ValueKey('auxiliary-close-button')));
      await tester.pumpAndSettle();
      expect(returnedDocuments.single['text'], incomingText);
      expect(returnedDocuments.single['dirty'], isTrue);
      expect(nativeCloseCalls, [
        if (defaultTargetPlatform == TargetPlatform.linux) 'hide',
        defaultTargetPlatform == TargetPlatform.windows ? 'close' : 'destroy',
      ]);
      expect(input.inputWindow.document.resync, throwsA(isA<AlulaException>()));
    },
        variant: const TargetPlatformVariant({
          TargetPlatform.linux,
          TargetPlatform.windows,
        }));
  });

  testWidgets(
    'auxiliary return abort keeps the source and commit waits for native drag completion',
    (tester) async {
      const windowsChannel = MethodChannel('mixin.one/desktop_multi_window');
      const crossWindowChannel =
          MethodChannel('mixin.one/desktop_multi_window/channels');
      const windowManagerChannel = MethodChannel('window_manager');
      const body = 'source dirty\r\n😀\n';
      final payload = AuxiliaryWindowPayload.forDocument(
        documentId: 902001,
        mainWindowId: 'main',
        name: 'return.txt',
        text: body,
        dirty: true,
      );
      final nativeCloseCalls = <String>[];
      final legacyReturns = <Object?>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(windowsChannel, (call) async {
        if (call.method == 'getWindowDefinition') {
          return {
            'windowId': 'aux-return',
            'windowArgument': payload.toArguments()
          };
        }
        return null;
      });
      messenger.setMockMethodCallHandler(crossWindowChannel, (call) async {
        if (call.method != 'invokeMethod' || call.arguments is! Map) {
          return null;
        }
        final args = call.arguments as Map;
        if (args['method'] == auxiliaryFocusContextMethod) {
          return {'windowId': 'main', 'groupId': 'main:editor', 'revision': 1};
        }
        if (args['method'] == auxiliaryWindowCloseReturnMethod) {
          legacyReturns.add(args['arguments']);
        }
        return null;
      });
      messenger.setMockMethodCallHandler(windowManagerChannel, (call) async {
        if (call.method == 'isAlwaysOnTop' || call.method == 'isFocused') {
          return false;
        }
        if (call.method == 'hide' ||
            call.method == 'close' ||
            call.method == 'destroy') {
          nativeCloseCalls.add(call.method);
        }
        return null;
      });
      addTearDown(() {
        for (final channel in [
          windowsChannel,
          crossWindowChannel,
          windowManagerChannel
        ]) {
          messenger.setMockMethodCallHandler(channel, null);
        }
      });
      await tester.pumpWidget(AuxiliaryEditorApp(payload: payload));
      await tester.pumpAndSettle();

      final source = tester.widget<DragItemWidget>(find.byType(DragItemWidget));
      final close = find.byKey(const ValueKey('auxiliary-close-button'));
      final field =
          tester.widget<RustTextInputField>(find.byType(RustTextInputField));
      Future<Object?> message(String method, Object? args) =>
          dispatchPlatformMethod(
              tester,
              crossWindowChannel.name,
              MethodCall(
                'methodCall',
                {
                  'channel': 'mixin.one/window_controller/aux-return',
                  'method': method,
                  'arguments': args
                },
              ));

      Future<(AuxiliaryTabDragTicket, _AuxiliaryDragSession)> begin() async {
        final session = _AuxiliaryDragSession();
        addTearDown(session.dragCompleted.dispose);
        final drag = await source.dragItemProvider(
          DragItemRequest(location: const Offset(20, 40), session: session),
        );
        expect(drag, isNotNull);
        final localData = drag!.localData as Map;
        expect(
            localData.keys, unorderedEquals(['kind', 'windowId', 'sequence']));
        final ticket = AuxiliaryTabDragTicket.tryParse(localData);
        expect(ticket?.windowId, 'aux-return');
        return (ticket!, session);
      }

      final (cancelTicket, canceled) = await begin();
      expect(
          await message(
              auxiliaryTabReturnPrepareMethod, cancelTicket.sequence + 1),
          isNull);
      final prepared =
          await message(auxiliaryTabReturnPrepareMethod, cancelTicket.sequence)
              as Map;
      expect(prepared['text'], body);
      expect(prepared['dirty'], isTrue);
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(close).onPressed, isNull);
      expect(
          await message(auxiliaryTabReturnFinishMethod, {
            'sequence': cancelTicket.sequence,
            'accepted': false,
          }),
          isTrue);
      canceled.dragCompleted.value = DropOperation.none;
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(close).onPressed, isNotNull);
      expect(field.inputWindow.document.resync().content, body);
      expect(nativeCloseCalls, isEmpty);

      final (timeoutTicket, timedOut) = await begin();
      expect(
        await message(auxiliaryTabReturnPrepareMethod, timeoutTicket.sequence),
        isA<Map>(),
      );
      expect(
          await message(auxiliaryTabReturnFinishMethod, {
            'sequence': timeoutTicket.sequence,
            'accepted': true,
          }),
          isTrue);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      timedOut.dragCompleted.value = DropOperation.move;
      expect(tester.widget<IconButton>(close).onPressed, isNotNull);
      expect(field.inputWindow.document.resync().content, body);
      expect(nativeCloseCalls, isEmpty);

      final (moveTicket, moved) = await begin();
      final movedSnapshot =
          await message(auxiliaryTabReturnPrepareMethod, moveTicket.sequence)
              as Map;
      expect(movedSnapshot['text'], body);
      expect(
          await message(auxiliaryTabReturnFinishMethod, {
            'sequence': moveTicket.sequence,
            'accepted': true,
          }),
          isTrue);
      expect(nativeCloseCalls, isEmpty);
      moved.dragCompleted.value = DropOperation.move;
      await tester.pumpAndSettle();
      expect(nativeCloseCalls, [
        if (defaultTargetPlatform == TargetPlatform.linux) 'hide',
        defaultTargetPlatform == TargetPlatform.windows ? 'close' : 'destroy',
      ]);
      expect(legacyReturns, isEmpty);
      expect(field.inputWindow.document.resync, throwsA(isA<AlulaException>()));
    },
    variant: const TargetPlatformVariant(
        {TargetPlatform.windows, TargetPlatform.linux}),
  );

  testWidgets(
    'normal auxiliary close keeps dirty text until the main window confirms it',
    (tester) async {
      const windowsChannel = MethodChannel('mixin.one/desktop_multi_window');
      const crossWindowChannel =
          MethodChannel('mixin.one/desktop_multi_window/channels');
      const nativeWindowChannel = MethodChannel('window_manager');
      const focusChannel = MethodChannel('alula/auxiliary_close_focus');
      final messenger = tester.binding.defaultBinaryMessenger;
      const body = 'dirty 😀\r\nSecond line\n';
      final payload = AuxiliaryWindowPayload.forDocument(
        documentId: 902051,
        mainWindowId: 'main',
        name: 'unsaved-close.txt',
        text: body,
        dirty: true,
      );
      final nativeCloseCalls = <String>[];
      final requests = <Map<String, Object?>>[];
      var reply = 'unavailable';
      final lateConfirmation = Completer<bool>();
      messenger.setMockMethodCallHandler(windowsChannel, (call) async {
        if (call.method == 'getWindowDefinition') {
          return {
            'windowId': 'aux-close',
            'windowArgument': payload.toArguments(),
          };
        }
        return null;
      });
      messenger.setMockMethodCallHandler(crossWindowChannel, (call) async {
        if (call.method != 'invokeMethod') return null;
        final request = call.arguments as Map;
        if (request['method'] == auxiliaryFocusContextMethod) {
          return {'windowId': 'main', 'groupId': 'main:editor', 'revision': 1};
        }
        if (request['method'] == auxiliaryWindowCloseReturnMethod) {
          requests.add(Map<String, Object?>.from(request['arguments'] as Map));
          if (reply == 'unavailable') {
            throw PlatformException(code: 'main-unavailable');
          }
          return reply == 'pending'
              ? lateConfirmation.future
              : reply == 'accepted';
        }
        return null;
      });
      messenger.setMockMethodCallHandler(nativeWindowChannel, (call) async {
        if (call.method == 'isAlwaysOnTop' || call.method == 'isFocused') {
          return false;
        }
        if (call.method == 'setPreventClose' &&
            (call.arguments as Map)['isPreventClose'] != false) {
          return null;
        }
        if (const {'hide', 'setPreventClose', 'close', 'destroy'}
            .contains(call.method)) {
          nativeCloseCalls.add(call.method);
        }
        return null;
      });
      messenger.setMockMethodCallHandler(focusChannel, (call) async {
        nativeCloseCalls.add(call.method);
        throw PlatformException(code: 'focus-unavailable');
      });
      addTearDown(() {
        for (final channel in [
          windowsChannel,
          crossWindowChannel,
          nativeWindowChannel,
          focusChannel,
        ]) {
          messenger.setMockMethodCallHandler(channel, null);
        }
      });
      await tester.pumpWidget(AuxiliaryEditorApp(payload: payload));
      await tester.pumpAndSettle();
      final input =
          tester.widget<RustTextInputField>(find.byType(RustTextInputField));
      final tabClose = find.byKey(const ValueKey('auxiliary-editor-tab-close'));
      final titleClose = find.byKey(const ValueKey('auxiliary-close-button'));

      await tester.tap(tabClose);
      await tester.pumpAndSettle();
      expect(nativeCloseCalls, isEmpty);
      expect(input.inputWindow.document.resync().content, body);
      expect(input.inputWindow.document.isDirty, isTrue);
      expect(find.byType(RustTextInputField), findsOneWidget);
      expect(input.focusNode?.hasFocus, isTrue);

      const more = 'still working 😀\r\nSecond line\n';
      await tester.enterText(find.byType(TextField), more);
      await tester.pumpAndSettle();
      expect(input.inputWindow.document.resync().content, more);

      reply = 'rejected';
      await tester.tap(titleClose);
      await tester.pumpAndSettle();
      expect(nativeCloseCalls, isEmpty);
      expect(input.inputWindow.document.resync().content, more);

      reply = 'pending';
      final listener =
          tester.state(find.byType(AuxiliaryEditorApp)) as WindowListener;
      final beforeTimeout = requests.length;
      await tester.tap(titleClose);
      await tester.pump();
      listener.onWindowClose();
      await tester.pump();
      expect(requests, hasLength(beforeTimeout + 1));
      expect(nativeCloseCalls, isEmpty);
      expect(tester.widget<IconButton>(titleClose).onPressed, isNull);
      await tester.pump(const Duration(seconds: 2));
      expect(requests, hasLength(beforeTimeout + 2));
      final sequence = requests.last['sequence'];
      expect(requests[beforeTimeout]['sequence'], sequence);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(nativeCloseCalls, isEmpty);
      expect(input.inputWindow.document.resync().content, more);

      lateConfirmation.complete(true);
      await tester.pumpAndSettle();
      expect(nativeCloseCalls, isEmpty,
          reason: 'late acknowledgements cannot close a retriable window');

      reply = 'accepted';
      listener.onWindowClose();
      await tester.pumpAndSettle();
      expect(requests.last['sequence'], sequence);
      expect(requests.last['text'], more);
      expect(requests.last['dirty'], isTrue);
      expect(
        nativeCloseCalls,
        [
          if (defaultTargetPlatform == TargetPlatform.linux) 'hide',
          'setPreventClose',
          if (defaultTargetPlatform == TargetPlatform.windows)
            'restoreMainIfSourceForeground',
          defaultTargetPlatform == TargetPlatform.windows ? 'close' : 'destroy',
        ],
      );
      expect(input.inputWindow.document.resync, throwsA(isA<AlulaException>()));
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.linux,
      TargetPlatform.windows,
    }),
  );

  group('main-window move flow', () {
    late Directory temp;
    late LayoutStore layoutStore;
    late SessionStore sessionStore;
    final createdPayloads = <String>[];
    final auxiliarySnapshotMessages = <Map<String, Object?>>[];
    final scrollSnapshots = <Map<String, Object?>>[];
    CommandService? commands;

    String baseOf() => temp.path.replaceAll(r'\', '/');

    setUp(() {
      temp = Directory.systemTemp.createTempSync('alula-aux-window');
      Directory('${temp.path}/workspace').createSync();
      layoutStore = LayoutStore(path: '${baseOf()}/layout.json');
      sessionStore = SessionStore(path: '${baseOf()}/session.json');
      createdPayloads.clear();
      auxiliarySnapshotMessages.clear();
      scrollSnapshots.clear();
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
              if (request['method'] == auxiliaryLockedScrollingMethod) {
                expect(request['channel'], 'mixin.one/window_controller/aux-1');
                scrollSnapshots.add(
                  Map<String, Object?>.from(request['arguments'] as Map),
                );
              }
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
        expect(parsed.documentId, greaterThan(10));
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
            focused: true,
          )),
        );
        expect(activeSnapshot?.windowId, 'aux-1');
        expect(auxiliarySnapshotMessages, hasLength(1));
        expect(auxiliarySnapshotMessages.single.keys.toSet(), {
          'windowId',
          'groupId',
          'revision',
        });
        expect(auxiliarySnapshotMessages.single, isNot(contains('documentId')));
        expect(auxiliarySnapshotMessages.single['windowId'], 'aux-1');

        final staleSnapshot = AuxiliaryFocusContextSnapshot.tryParse(
          await sendFocusEvent(const AuxiliaryFocusContextEvent(
            kind: AuxiliaryFocusEventKind.update,
            windowId: 'aux-1',
            sequence: 1,
            groupId: 'aux-1:stale',
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

        Future<Object?> sendLockRequest(String windowId, Object toggle) =>
            dispatchPlatformMethod(
              tester,
              'mixin.one/desktop_multi_window/channels',
              MethodCall('methodCall', {
                'channel': 'mixin.one/window_controller/main',
                'method': auxiliaryLockedScrollingMethod,
                'arguments': {'windowId': windowId, 'toggle': toggle},
              }),
            );

        final status = find.byKey(
          const ValueKey('status-bar-locked-scrolling'),
        );
        expect(await sendLockRequest('unknown', true), isNull);
        expect(await sendLockRequest('aux-1', 'invalid'), isNull);
        expect(await sendLockRequest('aux-1', false), {
          'revision': 0,
          'active': false,
        });
        expect(status, findsNothing);
        await commands!.execute('workbench.action.toggleLockedScrolling');
        await tester.pumpAndSettle();
        expect(status, findsOneWidget);
        expect(scrollSnapshots.single, {'revision': 1, 'active': true});
        expect(await sendLockRequest('aux-1', true), {
          'revision': 2,
          'active': false,
        });
        await tester.pumpAndSettle();
        expect(status, findsNothing);
        expect(scrollSnapshots.last, {'revision': 2, 'active': false});
        await tester.pumpWidget(const SizedBox.shrink());
        expect(windowManager.listeners, isNot(contains(mainWindowState)),
            reason: 'the main focus listener must be removed on dispose');
      },
    );
  });
}
