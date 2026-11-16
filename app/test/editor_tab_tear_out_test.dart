import 'dart:convert';
import 'dart:io';

import 'package:alula_app/workbench/auxiliary_window.dart';
import 'package:alula_app/workbench/editor_tab_tear_out_policy.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'package:alula_app/workbench/workbench_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_retriever/screen_retriever.dart' show Display;

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
    Offset cursorPosition = const Offset(2600, 700);
    Rect windowBounds = const Rect.fromLTWH(100, 200, 2400, 1000);
    bool failCreate = false;
    bool failCursorPosition = false;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('alula-tab-tear-out');
      Directory('${temp.path}/workspace').createSync();
      final base = temp.path.replaceAll(r'\', '/');
      documentPath = '$base/tear.rs';
      File(documentPath).writeAsStringSync('disk body');
      layoutStore = LayoutStore(path: '$base/layout.json');
      sessionStore = SessionStore(path: '$base/session.json');
      createdPayloads.clear();
      cursorPosition = const Offset(2600, 700);
      windowBounds = const Rect.fromLTWH(100, 200, 2400, 1000);
      failCreate = false;
      failCursorPosition = false;
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
