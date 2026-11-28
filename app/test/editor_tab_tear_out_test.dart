import 'dart:convert';
import 'dart:io';

import 'package:alula_app/editor/rust_text_input_field.dart';
import 'package:alula_app/workbench/auxiliary_focus_context.dart';
import 'package:alula_app/workbench/auxiliary_window.dart';
import 'package:alula_app/workbench/auxiliary_window_transfer.dart';
import 'package:alula_app/workbench/editor_tab_tear_out_policy.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_retriever/screen_retriever.dart' show Display;

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

  group('EditorTabTearOutPolicy', () {
    const bounds = Rect.fromLTWH(-100, 50, 400, 300);

    test('requires a global coordinate backend on Linux', () {
      expect(
        EditorTabTearOutPolicy.supportsGlobalScreenCoordinates(
          isLinux: true,
          waylandDisplay: 'wayland-0',
          gdkBackend: null,
        ),
        isFalse,
      );
      expect(
        EditorTabTearOutPolicy.supportsGlobalScreenCoordinates(
          isLinux: true,
          waylandDisplay: 'wayland-0',
          gdkBackend: 'x11',
        ),
        isTrue,
      );
      expect(
        EditorTabTearOutPolicy.supportsGlobalScreenCoordinates(
          isLinux: true,
          waylandDisplay: null,
          gdkBackend: null,
        ),
        isTrue,
      );
      expect(
        EditorTabTearOutPolicy.supportsGlobalScreenCoordinates(
          isLinux: false,
          waylandDisplay: 'wayland-0',
          gdkBackend: 'wayland',
        ),
        isTrue,
      );
    });

    test('keeps every point on or inside the window bounds', () {
      for (final point in [
        const Offset(-100, 50),
        const Offset(0, 200),
        const Offset(299, 349),
      ]) {
        expect(
          EditorTabTearOutPolicy.shouldTearOut(
            windowBounds: bounds,
            pointerPosition: point,
          ),
          isFalse,
          reason: '$point is inside the half-open window rectangle',
        );
      }
    });

    test('detects releases beyond each edge, including negative coordinates',
        () {
      for (final point in [
        const Offset(-101, 200),
        const Offset(300, 200),
        const Offset(0, 49),
        const Offset(0, 350),
      ]) {
        expect(
          EditorTabTearOutPolicy.shouldTearOut(
            windowBounds: bounds,
            pointerPosition: point,
          ),
          isTrue,
          reason: '$point is outside the window rectangle',
        );
      }
    });

    test('keeps the source when bounds or pointer coordinates are unknown', () {
      expect(
        EditorTabTearOutPolicy.shouldTearOut(
          windowBounds: null,
          pointerPosition: Offset.zero,
        ),
        isFalse,
      );
      expect(
        EditorTabTearOutPolicy.shouldTearOut(
          windowBounds: bounds,
          pointerPosition: null,
        ),
        isFalse,
      );
      expect(
        EditorTabTearOutPolicy.shouldTearOut(
          windowBounds: Rect.zero,
          pointerPosition: Offset.zero,
        ),
        isFalse,
      );
      expect(
        EditorTabTearOutPolicy.shouldTearOut(
          windowBounds: bounds,
          pointerPosition: const Offset(double.nan, 200),
        ),
        isFalse,
      );
    });

    test('window and cursor coordinates remain comparable at different DPRs',
        () {
      for (final scale in [1.0, 1.25, 1.5, 2.0]) {
        final scaledBounds = Rect.fromLTWH(
          -100 * scale,
          50 * scale,
          400 * scale,
          300 * scale,
        );
        expect(
          EditorTabTearOutPolicy.shouldTearOut(
            windowBounds: scaledBounds,
            pointerPosition: Offset(0, 200 * scale),
          ),
          isFalse,
          reason: 'matching screen geometry at DPR $scale remains inside',
        );
        expect(
          EditorTabTearOutPolicy.shouldTearOut(
            windowBounds: scaledBounds,
            pointerPosition: Offset(301 * scale, 200 * scale),
          ),
          isTrue,
          reason: 'matching screen geometry at DPR $scale remains outside',
        );
      }
    });

    test('aligns a macOS cursor from a display below the primary screen', () {
      final aligned = EditorTabTearOutPolicy.alignMacOSCursorWithWindowBounds(
        pointerPosition: const Offset(80, 10),
        displays: [
          const Display(
            id: 'primary',
            size: Size(1920, 1080),
            visiblePosition: Offset(0, 25),
            visibleSize: Size(1920, 1055),
          ),
          const Display(
            id: 'lower',
            size: Size(1280, 720),
            visiblePosition: Offset(1920, 1100),
            visibleSize: Size(1280, 700),
          ),
        ],
      );

      expect(aligned, const Offset(80, 1090));
      expect(
        EditorTabTearOutPolicy.shouldTearOut(
          windowBounds: const Rect.fromLTWH(0, 1080, 300, 300),
          pointerPosition: aligned,
        ),
        isFalse,
        reason: 'a release on the lower display remains inside that window',
      );
    });

    test('cannot normalize macOS coordinates without display geometry', () {
      expect(
        EditorTabTearOutPolicy.alignMacOSCursorWithWindowBounds(
          pointerPosition: Offset.zero,
          displays: const [],
        ),
        isNull,
      );
    });
  });

  group('editor tab tear-out', () {
    late Directory temp;
    late LayoutStore layoutStore;
    late SessionStore sessionStore;
    late String documentPath;
    final createdPayloads = <String>[];
    final auxiliaryTransferCalls = <String>[];
    final nativeAuxiliaryBounds = <String, Rect>{};
    final transferredSourceDocuments = <Map<String, Object?>>[];
    Offset cursorPosition = const Offset(2600, 700);
    Rect windowBounds = const Rect.fromLTWH(100, 200, 2400, 1000);
    bool failCreate = false;
    bool failCursorPosition = false;
    String transferPrepareStatus = 'prepared';
    String transferCommitStatus = 'committed';
    String transferStatusResponse = 'prepared';
    String transferAbortStatus = 'aborted';
    late Map<String, Object?> auxiliaryPreviousDocument;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('alula-tab-tear-out');
      Directory('${temp.path}/workspace').createSync();
      final base = temp.path.replaceAll(r'\', '/');
      documentPath = '$base/tear.rs';
      File(documentPath).writeAsStringSync('disk body');
      layoutStore = LayoutStore(path: '$base/layout.json');
      sessionStore = SessionStore(path: '$base/session.json');
      createdPayloads.clear();
      auxiliaryTransferCalls.clear();
      nativeAuxiliaryBounds.clear();
      transferredSourceDocuments.clear();
      cursorPosition = const Offset(2600, 700);
      windowBounds = const Rect.fromLTWH(100, 200, 2400, 1000);
      failCreate = false;
      failCursorPosition = false;
      transferPrepareStatus = 'prepared';
      transferCommitStatus = 'committed';
      transferStatusResponse = 'prepared';
      transferAbortStatus = 'aborted';
      auxiliaryPreviousDocument = AuxiliaryWindowPayload.forDocument(
        name: 'aux-original.rs',
        text: 'aux original\r\n🪺\n',
        dirty: true,
      ).toMap();
    });

    Future<void> mountWorkbench(WidgetTester tester) async {
      tester.view.physicalSize = const Size(2400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final base = temp.path.replaceAll(r'\', '/');
      File('$base/session.json').writeAsStringSync(jsonEncode({
        'v': 1,
        'editorTabMode': 'multiple',
        'focused': 'editor',
        'groups': [
          {
            'region': 'editor',
            'docs': [
              {
                'id': 10,
                'name': 'tear.rs',
                'path': documentPath,
                'text': 'unsaved body',
              },
            ],
            'active': 10,
          },
        ],
      }));

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('mixin.one/desktop_multi_window'),
        (call) async {
          if (call.method == 'createWindow') {
            final config = call.arguments as Map<dynamic, dynamic>;
            createdPayloads.add(config['arguments'] as String);
            if (failCreate) {
              throw PlatformException(
                code: 'create_failed',
                message: 'synthetic window creation failure',
              );
            }
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
          if (call.method != 'invokeMethod' || call.arguments is! Map) {
            return null;
          }
          final envelope = Map<String, Object?>.from(call.arguments as Map);
          final channel = envelope['channel'] as String?;
          const windowChannel = 'mixin.one/window_controller/';
          if (channel == null || !channel.startsWith('${windowChannel}aux-')) {
            return null;
          }
          final windowId = channel.substring(windowChannel.length);
          final method = envelope['method'] as String?;
          if (method == auxiliaryWindowBoundsQueryMethod) {
            final bounds = nativeAuxiliaryBounds[windowId];
            return bounds == null
                ? null
                : AuxiliaryWindowBounds(
                        windowId: windowId, sequence: 2, bounds: bounds)
                    .toMap();
          }
          if (method == null) return null;
          auxiliaryTransferCalls.add(method);
          final arguments = envelope['arguments'] is Map
              ? Map<String, Object?>.from(envelope['arguments'] as Map)
              : <String, Object?>{};
          switch (method) {
            case auxiliaryDocumentTransferPrepareMethod:
              final document = arguments['document'];
              if (document is Map) {
                transferredSourceDocuments.add(
                  Map<String, Object?>.from(document),
                );
              }
              return {
                'requestId': arguments['requestId'],
                'status': transferPrepareStatus,
                if (transferPrepareStatus == 'prepared')
                  'previousDocument': auxiliaryPreviousDocument,
              };
            case auxiliaryDocumentTransferCommitMethod:
              return {
                'requestId': arguments['requestId'],
                'status': transferCommitStatus,
              };
            case auxiliaryDocumentTransferStatusMethod:
              return {
                'requestId': arguments['requestId'],
                'status': transferStatusResponse,
              };
            case auxiliaryDocumentTransferAbortMethod:
              return {
                'requestId': arguments['requestId'],
                'status': transferAbortStatus,
              };
          }
          return null;
        },
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async {
          if (call.method == 'getBounds') {
            return {
              'x': windowBounds.left,
              'y': windowBounds.top,
              'width': windowBounds.width,
              'height': windowBounds.height,
            };
          }
          return null;
        },
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dev.leanflutter.plugins/screen_retriever'),
        (call) async {
          if (call.method == 'getCursorScreenPoint') {
            if (failCursorPosition) return null;
            return {'dx': cursorPosition.dx, 'dy': cursorPosition.dy};
          }
          if (call.method == 'getAllDisplays') {
            return {
              'displays': [
                {
                  'id': 'primary',
                  'size': {'width': 2400.0, 'height': 1000.0},
                  'visiblePosition': {'dx': 0.0, 'dy': 25.0},
                  'visibleSize': {'width': 2400.0, 'height': 975.0},
                },
              ],
            };
          }
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
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('dev.leanflutter.plugins/screen_retriever'),
          null,
        );
      });

      await tester.pumpWidget(MaterialApp(
        home: WorkbenchPage(
          autoFolder: '$base/workspace',
          layoutStore: layoutStore,
          sessionStore: sessionStore,
          keybindingsStore: KeybindingsStore(path: '$base/keybindings.json'),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey('tab-10')), findsOneWidget);
    }

    Future<void> dragTab(WidgetTester tester, Offset destination) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('tab-10'))),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
      await gesture.moveTo(destination);
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
    }

    Future<void> registerAuxiliaryWindow(
      WidgetTester tester, {
      String windowId = 'aux-1',
      Rect bounds = const Rect.fromLTWH(2550, 300, 900, 800),
    }) async {
      nativeAuxiliaryBounds[windowId] = bounds;
      final event = AuxiliaryFocusContextEvent(
        kind: AuxiliaryFocusEventKind.register,
        windowId: windowId,
        sequence: 1,
        groupId: '$windowId:editor',
        focused: false,
      );
      final registered = await dispatchPlatformMethod(
        tester,
        'mixin.one/desktop_multi_window/channels',
        // The register event's map is built at runtime.
        // ignore: prefer_const_constructors
        MethodCall('methodCall', {
          'channel': 'mixin.one/window_controller/main',
          'method': auxiliaryFocusContextMethod,
          'arguments': event.toMap(),
        }),
      );
      expect(registered, isA<Map>());
      final focused = await dispatchPlatformMethod(
        tester,
        'mixin.one/desktop_multi_window/channels',
        // Event maps are encoded from their typed snapshot.
        // ignore: prefer_const_constructors
        MethodCall('methodCall', {
          'channel': 'mixin.one/window_controller/main',
          'method': auxiliaryFocusContextMethod,
          'arguments': AuxiliaryFocusContextEvent(
            kind: AuxiliaryFocusEventKind.update,
            windowId: windowId,
            sequence: 2,
            groupId: '$windowId:editor',
            focused: true,
          ).toMap(),
        }),
      );
      expect((focused as Map)['windowId'], windowId);
      await dispatchPlatformMethod(
        tester,
        'mixin.one/desktop_multi_window/channels',
        // Bounds are serialized at runtime.
        // ignore: prefer_const_constructors
        MethodCall('methodCall', {
          'channel': 'mixin.one/window_controller/main',
          'method': auxiliaryWindowBoundsMethod,
          'arguments': AuxiliaryWindowBounds(
            windowId: windowId,
            sequence: 1,
            bounds: bounds,
          ).toMap(),
        }),
      );
    }

    testWidgets(
      'outside release creates one auxiliary window with the dirty document',
      (tester) async {
        await mountWorkbench(tester);
        await dragTab(tester, const Offset(2501, 700));

        expect(createdPayloads, hasLength(1));
        final payload = AuxiliaryWindowPayload.fromArguments(
          createdPayloads.single,
        );
        expect(payload.isAuxiliary, isTrue);
        expect(payload.path, documentPath);
        expect(payload.name, 'tear.rs');
        expect(payload.text, 'unsaved body');
        expect(payload.dirty, isTrue);
        expect(find.byKey(const ValueKey('tab-10')), findsNothing);
        final groups = sessionStore.tryLoad()?['groups'] as List;
        final docs = (groups.single as Map)['docs'] as List;
        expect(docs.where((doc) => (doc as Map)['id'] == 10), isEmpty,
            reason: 'the successfully moved source view is removed');
      },
    );

    testWidgets(
      'drop on a registered auxiliary window swaps documents after commit',
      (tester) async {
        await mountWorkbench(tester);
        await registerAuxiliaryWindow(tester);
        await dragTab(tester, const Offset(2600, 700));

        expect(createdPayloads, isEmpty);
        expect(
          auxiliaryTransferCalls,
          containsAll([
            auxiliaryDocumentTransferPrepareMethod,
            auxiliaryDocumentTransferCommitMethod,
          ]),
        );
        expect(transferredSourceDocuments, hasLength(1));
        expect(transferredSourceDocuments.single['path'], documentPath);
        expect(transferredSourceDocuments.single['text'], 'unsaved body');
        expect(transferredSourceDocuments.single['dirty'], isTrue);
        expect(find.byKey(const ValueKey('tab-10')), findsNothing);
        expect(find.text('aux-original.rs •'), findsOneWidget);
        expect(find.text('已与辅助窗口交换文档'), findsOneWidget);
        final input = tester.widget<RustTextInputField>(
          find.byType(RustTextInputField),
        );
        expect(
          input.inputWindow.document.resync().content,
          'aux original\r\n🪺\n',
        );
        expect(input.inputWindow.document.isDirty, isTrue);

        final groups = sessionStore.tryLoad()?['groups'] as List;
        final docs = [
          for (final group in groups) ...((group as Map)['docs'] as List),
        ];
        expect(
          docs.where((doc) => (doc as Map)['path'] == documentPath),
          isEmpty,
        );
        expect(
          docs.where(
            (doc) => (doc as Map)['text'] == 'aux original\r\n🪺\n',
          ),
          hasLength(1),
        );
      },
    );

    testWidgets('fresh bounds reject overlap after an unreported native move',
        (tester) async {
      await mountWorkbench(tester);
      await registerAuxiliaryWindow(tester);
      await registerAuxiliaryWindow(
        tester,
        windowId: 'aux-2',
        bounds: const Rect.fromLTWH(3600, 300, 900, 800),
      );
      nativeAuxiliaryBounds['aux-2'] = nativeAuxiliaryBounds['aux-1']!;

      await dragTab(tester, const Offset(2600, 700));

      expect(auxiliaryTransferCalls,
          isNot(contains(auxiliaryDocumentTransferPrepareMethod)));
      expect(createdPayloads, isEmpty);
      expect(find.byKey(const ValueKey('tab-10')), findsOneWidget);
    });

    testWidgets('missing fresh auxiliary bounds retains the source tab',
        (tester) async {
      await mountWorkbench(tester);
      await registerAuxiliaryWindow(tester);
      nativeAuxiliaryBounds.clear();

      await dragTab(tester, const Offset(2600, 700));

      expect(auxiliaryTransferCalls,
          isNot(contains(auxiliaryDocumentTransferPrepareMethod)));
      expect(createdPayloads, isEmpty);
      expect(find.byKey(const ValueKey('tab-10')), findsOneWidget);
    });

    testWidgets('rejected auxiliary transfer keeps the source tab open',
        (tester) async {
      transferPrepareStatus = 'rejected';
      await mountWorkbench(tester);
      await registerAuxiliaryWindow(tester);
      await dragTab(tester, const Offset(2600, 700));

      expect(auxiliaryTransferCalls,
          contains(auxiliaryDocumentTransferPrepareMethod));
      expect(
        auxiliaryTransferCalls,
        isNot(contains(auxiliaryDocumentTransferCommitMethod)),
      );
      expect(createdPayloads, isEmpty);
      expect(find.byKey(const ValueKey('tab-10')), findsOneWidget);
    });

    testWidgets('aborted auxiliary commit keeps both original documents',
        (tester) async {
      transferCommitStatus = 'rejected';
      transferStatusResponse = 'prepared';
      transferAbortStatus = 'aborted';
      await mountWorkbench(tester);
      await registerAuxiliaryWindow(tester);
      await dragTab(tester, const Offset(2600, 700));

      expect(
        auxiliaryTransferCalls,
        containsAll([
          auxiliaryDocumentTransferPrepareMethod,
          auxiliaryDocumentTransferCommitMethod,
          auxiliaryDocumentTransferStatusMethod,
          auxiliaryDocumentTransferAbortMethod,
        ]),
      );
      expect(find.byKey(const ValueKey('tab-10')), findsOneWidget);
      expect(find.text('aux-original.rs •'), findsNothing);
      expect(createdPayloads, isEmpty);
    });

    testWidgets('unconfirmed auxiliary commit preserves both local snapshots',
        (tester) async {
      transferCommitStatus = 'rejected';
      transferStatusResponse = 'unknown';
      transferAbortStatus = 'unknown';
      await mountWorkbench(tester);
      await registerAuxiliaryWindow(tester);
      await dragTab(tester, const Offset(2600, 700));

      expect(
        auxiliaryTransferCalls,
        containsAll([
          auxiliaryDocumentTransferPrepareMethod,
          auxiliaryDocumentTransferCommitMethod,
          auxiliaryDocumentTransferStatusMethod,
          auxiliaryDocumentTransferAbortMethod,
        ]),
      );
      expect(find.byKey(const ValueKey('tab-10')), findsOneWidget,
          reason: 'an unconfirmed target commit cannot remove the source');
      expect(find.text('aux-original.rs •'), findsOneWidget,
          reason: 'the returned target snapshot remains recoverable');
      expect(createdPayloads, isEmpty);
    });

    testWidgets('closed auxiliary bounds are removed before the next drop',
        (tester) async {
      await mountWorkbench(tester);
      await registerAuxiliaryWindow(tester);
      Future<Object?> confirmReturn(String windowId, int sequence,
              {String body = 'recovered aux text'}) =>
          dispatchPlatformMethod(
            tester,
            'mixin.one/desktop_multi_window/channels',
            MethodCall('methodCall', {
              'channel': 'mixin.one/window_controller/main',
              'method': auxiliaryWindowCloseReturnMethod,
              'arguments': {
                'businessId': AuxiliaryWindowPayload.businessId,
                'windowId': windowId,
                'sequence': sequence,
                'name': 'closed-aux.rs',
                'text': body,
                'dirty': true,
                'selectionBase': 4,
                'selectionExtent': 1,
              },
            }),
          );
      expect(await confirmReturn('unknown-window', 1), isFalse);
      expect(await confirmReturn('aux-1', 1), isTrue);
      expect(await confirmReturn('aux-1', 1), isTrue);
      expect(await confirmReturn('aux-1', 2), isFalse);
      await tester.pump(const Duration(milliseconds: 700));
      final returnedDocs = (sessionStore.tryLoad()!['groups'] as List)
          .cast<Map>()
          .expand((group) => (group['docs'] as List).cast<Map>())
          .where((doc) => doc['text'] == 'recovered aux text');
      expect(returnedDocs, hasLength(1));
      // The source is still alive if the earlier acknowledgement was lost.
      // Removing the earlier main-window view must allow a fresh request.
      final firstReturnId = returnedDocs.single['id'];
      await tester.tap(find.byKey(ValueKey('close-tab-editor-$firstReturnId')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor-close-discard')));
      await tester.pumpAndSettle();
      expect(await confirmReturn('aux-1', 2, body: 'new auxiliary snapshot'),
          isTrue);
      await tester.pumpAndSettle();
      await dragTab(tester, const Offset(2600, 700));

      expect(createdPayloads, hasLength(1),
          reason: 'a closed window cannot remain a drop target');
      expect(
        auxiliaryTransferCalls,
        isNot(contains(auxiliaryDocumentTransferPrepareMethod)),
      );
      expect(find.byKey(const ValueKey('tab-10')), findsNothing);
    });

    testWidgets(
        'overlapping auxiliary bounds keep the source without a new window',
        (tester) async {
      await mountWorkbench(tester);
      const overlap = Rect.fromLTWH(2550, 300, 900, 800);
      await registerAuxiliaryWindow(tester, bounds: overlap);
      await registerAuxiliaryWindow(
        tester,
        windowId: 'aux-2',
        bounds: overlap,
      );
      await dragTab(tester, const Offset(2600, 700));

      expect(createdPayloads, isEmpty);
      expect(
        auxiliaryTransferCalls,
        isNot(contains(auxiliaryDocumentTransferPrepareMethod)),
      );
      expect(find.byKey(const ValueKey('tab-10')), findsOneWidget);
    });

    testWidgets('accepted in-window editor drop never creates a window',
        (tester) async {
      // The native cursor is outside to prove that an accepted editor target
      // wins and cannot create a duplicate auxiliary window.
      cursorPosition = const Offset(2601, 700);
      await mountWorkbench(tester);
      await dragTab(tester, const Offset(1200, 700));

      expect(createdPayloads, isEmpty);
      expect(find.byKey(const ValueKey('tab-10')), findsOneWidget);
    });

    testWidgets('rejected in-window title-bar drop never creates a window',
        (tester) async {
      cursorPosition = const Offset(1200, 210);
      await mountWorkbench(tester);
      await dragTab(tester, const Offset(1200, 10));

      expect(createdPayloads, isEmpty);
      expect(find.byKey(const ValueKey('tab-10')), findsOneWidget);
    });

    testWidgets('failed window creation keeps the source tab open',
        (tester) async {
      failCreate = true;
      await mountWorkbench(tester);
      await dragTab(tester, const Offset(2501, 700));

      expect(createdPayloads, hasLength(1),
          reason: 'the outside drag makes one creation attempt');
      expect(find.byKey(const ValueKey('tab-10')), findsOneWidget,
          reason: 'a failed create does not remove the source document');
    });

    testWidgets('unknown pointer position keeps the source tab open',
        (tester) async {
      failCursorPosition = true;
      await mountWorkbench(tester);
      await dragTab(tester, const Offset(2501, 700));

      expect(createdPayloads, isEmpty);
      expect(find.byKey(const ValueKey('tab-10')), findsOneWidget);
    });
  });
}
