import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alula_app/editor/editor_native_text_drag_drop.dart';
import 'package:alula_app/editor/text_drag_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

const _nativeInputChannel = MethodChannel('alula/native_dnd_test');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native macOS drag moves selected text between views of the same document',
    (tester) async {
      final directoryPath = Platform.environment['ALULA_MACOS_DND_DIR'];
      expect(directoryPath, isNotNull);
      final directory = Directory(directoryPath!);
      directory.createSync(recursive: true);

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

      void writeJsonLine(String name, Map<String, Object?> value) {
        File('${directory.path}/$name.jsonl').writeAsStringSync(
          '${jsonEncode(value)}\n',
          mode: FileMode.append,
        );
      }

      void recordPointerEvent(String type, PointerEvent event) {
        writeJsonLine('pointer-events', {
          'type': type,
          'x': event.position.dx,
          'y': event.position.dy,
          'buttons': event.buttons,
          'kind': event.kind.name,
          'timestampMicros': event.timeStamp.inMicroseconds,
        });
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    EditorNativeTextDragDrop(
                      enabled: true,
                      payloadAt: (position) {
                        writeJsonLine('payload-at', {
                          'view': 'source',
                          'x': position.dx,
                          'y': position.dy,
                        });
                        return payload;
                      },
                      buildDropRequest: (_, __, ___) => null,
                      onDrop: (_) {},
                      onDragCompleted: (candidate, operation) {
                        File('${directory.path}/drag-completed.json')
                            .writeAsStringSync(
                          jsonEncode({
                            'selectedText': candidate.selectedText,
                            'operation': operation.name,
                          }),
                        );
                      },
                      child: const SizedBox(
                        key: ValueKey('alula-dnd-source'),
                        width: 240,
                        height: 90,
                        child: Center(child: Text('Drag source')),
                      ),
                    ),
                    const SizedBox(height: 120),
                    EditorNativeTextDragDrop(
                      enabled: true,
                      payloadAt: (_) => null,
                      buildDropRequest: (candidate, position, operation) {
                        writeJsonLine('drop-over', {
                          'x': position.dx,
                          'y': position.dy,
                          'operation': operation.name,
                        });
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
                      onDragCompleted: (_, __) {},
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
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DragItemWidget), findsNWidgets(2));
      expect(find.byType(DropRegion), findsNWidgets(2));

      final source =
          tester.getCenter(find.byKey(const ValueKey('alula-dnd-source')));
      final target =
          tester.getCenter(find.byKey(const ValueKey('alula-dnd-target')));
      File('${directory.path}/layout.json').writeAsStringSync(
        jsonEncode({
          'source': {'x': source.dx, 'y': source.dy},
          'target': {'x': target.dx, 'y': target.dy},
          'devicePixelRatio': tester.view.devicePixelRatio,
          'viewSize': {
            'width':
                tester.view.physicalSize.width / tester.view.devicePixelRatio,
            'height':
                tester.view.physicalSize.height / tester.view.devicePixelRatio,
          },
        }),
      );

      final request = await tester.runAsync(() async {
        await _nativeInputChannel.invokeMethod<void>('scheduleDrag', {
          'sourceX': source.dx,
          'sourceY': source.dy,
          'targetX': target.dx,
          'targetY': target.dy,
        });
        File('${directory.path}/native-input-scheduled')
            .writeAsStringSync('ok');
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (!dropReceived.isCompleted && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        if (!dropReceived.isCompleted) {
          throw TimeoutException(
              'Native AppKit drag/drop did not complete within 20 seconds.');
        }
        return dropReceived.future;
      });
      await tester.pumpAndSettle();

      expect(request, isNotNull);
      final result = jsonDecode(
        File('${directory.path}/drop.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(result['selectedText'], 'alpha');
      expect(result['operation'], EditorTextDropOperation.move.name);
      expect(result['targetOffsetUtf16'], 11);

      final pointerEvents = File('${directory.path}/pointer-events.jsonl')
          .readAsLinesSync()
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList();
      final eventTypes = pointerEvents.map((event) => event['type']).toSet();
      expect(eventTypes, containsAll(['down', 'move', 'up']));
      expect(
          File('${directory.path}/drag-completed.json').existsSync(), isTrue);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
