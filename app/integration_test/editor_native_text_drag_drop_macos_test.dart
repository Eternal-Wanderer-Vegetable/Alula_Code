import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alula_app/editor/editor_native_text_drag_drop.dart';
import 'package:alula_app/editor/text_drag_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native macOS drag drops local text into the same editor region',
    (tester) async {
      final directoryPath = Platform.environment['ALULA_MACOS_DND_DIR'];
      expect(directoryPath, isNotNull);
      final directory = Directory(directoryPath!);
      directory.createSync(recursive: true);
      final semanticsHandle = tester.ensureSemantics();
      var semanticsHandleActive = true;
      void disposeSemanticsHandle() {
        if (!semanticsHandleActive) return;
        semanticsHandleActive = false;
        semanticsHandle.dispose();
      }

      addTearDown(disposeSemanticsHandle);

      const payload = EditorTextDragPayload(
        selection: EditorTextDragSelection(
          documentId: 7001,
          documentVersion: 3,
          startUtf16: 0,
          endUtf16: 5,
        ),
        selectedText: 'alpha',
        token: 41,
      );
      final dropReceived = Completer<EditorTextDragDropRequest>();
      void recordPointerEvent(String type, PointerEvent event) {
        File('${directory.path}/pointer-events.jsonl').writeAsStringSync(
          '${jsonEncode({
                'type': type,
                'x': event.position.dx,
                'y': event.position.dy,
                'buttons': event.buttons,
                'kind': event.kind.name,
                'timestampMicros': event.timeStamp.inMicroseconds,
              })}\n',
          mode: FileMode.append,
        );
      }

      void pointerRoute(PointerEvent event) {
        recordPointerEvent('router', event);
      }

      GestureBinding.instance.pointerRouter.addGlobalRoute(pointerRoute);
      addTearDown(
        () => GestureBinding.instance.pointerRouter.removeGlobalRoute(
          pointerRoute,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Listener(
                key: const ValueKey('alula-pointer-logger'),
                behavior: HitTestBehavior.translucent,
                onPointerDown: (event) => recordPointerEvent('down', event),
                onPointerMove: (event) => recordPointerEvent('move', event),
                onPointerUp: (event) => recordPointerEvent('up', event),
                onPointerCancel: (event) => recordPointerEvent('cancel', event),
                child: EditorNativeTextDragDrop(
                  enabled: true,
                  payloadAt: (position) {
                    File('${directory.path}/payload-at.jsonl')
                        .writeAsStringSync(
                      '${jsonEncode({'x': position.dx, 'y': position.dy})}\n',
                      mode: FileMode.append,
                    );
                    return payload;
                  },
                  buildDropRequest: (candidate, position, operation) {
                    File('${directory.path}/drop-over.jsonl').writeAsStringSync(
                      '${jsonEncode({
                            'x': position.dx,
                            'y': position.dy,
                            'operation': operation.name,
                          })}\n',
                      mode: FileMode.append,
                    );
                    return EditorTextDragDropRequest(
                      payload: candidate,
                      targetDocumentId: candidate.selection.documentId,
                      targetDocumentVersion:
                          candidate.selection.documentVersion,
                      targetOffsetUtf16: 11,
                      operation: operation,
                    );
                  },
                  onDrop: (request) {
                    if (!dropReceived.isCompleted) {
                      dropReceived.complete(request);
                    }
                    File('${directory.path}/drop.json').writeAsStringSync(
                      jsonEncode({
                        'selectedText': request.payload.selectedText,
                        'operation': request.operation.name,
                        'targetOffsetUtf16': request.targetOffsetUtf16,
                      }),
                    );
                  },
                  onDragCompleted: (candidate, operation) {
                    File('${directory.path}/drag-completed.json')
                        .writeAsStringSync(
                      jsonEncode({
                        'selectedText': candidate.selectedText,
                        'operation': operation.name,
                      }),
                    );
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        container: true,
                        identifier: 'alula-dnd-source',
                        label: 'ALULA DND SOURCE',
                        child: const SizedBox(
                          key: ValueKey('alula-dnd-source'),
                          width: 240,
                          height: 90,
                          child: Center(child: Text('Drag source')),
                        ),
                      ),
                      const SizedBox(height: 120),
                      Semantics(
                        container: true,
                        identifier: 'alula-dnd-target',
                        label: 'ALULA DND TARGET',
                        child: const SizedBox(
                          key: ValueKey('alula-dnd-target'),
                          width: 240,
                          height: 90,
                          child: Center(child: Text('Drop target')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final pointerLoggerRect =
          tester.getRect(find.byKey(const ValueKey('alula-pointer-logger')));
      File('${directory.path}/layout.json').writeAsStringSync(
        jsonEncode({
          'source': {
            'x': tester
                .getCenter(find.byKey(const ValueKey('alula-dnd-source')))
                .dx,
            'y': tester
                .getCenter(find.byKey(const ValueKey('alula-dnd-source')))
                .dy,
          },
          'target': {
            'x': tester
                .getCenter(find.byKey(const ValueKey('alula-dnd-target')))
                .dx,
            'y': tester
                .getCenter(find.byKey(const ValueKey('alula-dnd-target')))
                .dy,
          },
          'devicePixelRatio': tester.view.devicePixelRatio,
          'pointerLoggerRect': {
            'left': pointerLoggerRect.left,
            'top': pointerLoggerRect.top,
            'right': pointerLoggerRect.right,
            'bottom': pointerLoggerRect.bottom,
          },
        }),
      );
      File('${directory.path}/ready').writeAsStringSync('ready');

      final inputRouteUnavailable =
          File('${directory.path}/input-route-unavailable');
      final request = await tester.runAsync<EditorTextDragDropRequest?>(
        () async {
          final deadline = DateTime.now().add(const Duration(seconds: 40));
          while (!dropReceived.isCompleted &&
              !inputRouteUnavailable.existsSync() &&
              DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          if (inputRouteUnavailable.existsSync()) {
            disposeSemanticsHandle();
            markTestSkipped(
              'Hosted macOS runner did not route synthetic pointer events to Flutter.',
            );
            return null;
          }
          if (!dropReceived.isCompleted) {
            throw TimeoutException(
              'Native drag/drop did not complete within 40 seconds.',
            );
          }
          return dropReceived.future;
        },
      );
      if (inputRouteUnavailable.existsSync()) return;
      await tester.pump();

      expect(request, isNotNull);
      final result = jsonDecode(
        File('${directory.path}/drop.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(result['selectedText'], 'alpha');
      expect(result['operation'], EditorTextDropOperation.move.name);
      expect(result['targetOffsetUtf16'], 11);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
