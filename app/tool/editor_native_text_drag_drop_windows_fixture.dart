import 'dart:convert';
import 'dart:io';

import 'package:alula_app/editor/editor_native_text_drag_drop.dart';
import 'package:alula_app/editor/text_drag_drop.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final directoryPath = Platform.environment['ALULA_WINDOWS_DND_DIR'];
  if (directoryPath == null || directoryPath.isEmpty) {
    throw StateError('ALULA_WINDOWS_DND_DIR is required.');
  }
  final directory = Directory(directoryPath)..createSync(recursive: true);
  runApp(_WindowsNativeDragFixture(directory: directory));
}

class _WindowsNativeDragFixture extends StatefulWidget {
  const _WindowsNativeDragFixture({required this.directory});

  final Directory directory;

  @override
  State<_WindowsNativeDragFixture> createState() =>
      _WindowsNativeDragFixtureState();
}

class _WindowsNativeDragFixtureState extends State<_WindowsNativeDragFixture> {
  static const _payload = EditorTextDragPayload(
    selection: EditorTextDragSelection(
      documentId: 7001,
      documentVersion: 3,
      startUtf16: 0,
      endUtf16: 5,
    ),
    selectedText: 'alpha',
    token: 41,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      _writeLayout(
          view.physicalSize / view.devicePixelRatio, view.devicePixelRatio);
      File('${widget.directory.path}/ready').writeAsStringSync('ready');
    });
  }

  void _writeLayout(Size logicalSize, double devicePixelRatio) {
    final left = logicalSize.width / 2 - 120;
    final top = logicalSize.height / 2 - 195;
    File('${widget.directory.path}/layout.json').writeAsStringSync(
      jsonEncode({
        'source': {'x': left + 120, 'y': top + 45},
        'target': {'x': left + 120, 'y': top + 90 + 120 + 45},
        'devicePixelRatio': devicePixelRatio,
      }),
    );
  }

  void _recordPointer(String type, PointerEvent event) {
    File('${widget.directory.path}/pointer-events.jsonl').writeAsStringSync(
      '${jsonEncode({
            'type': type,
            'x': event.position.dx,
            'y': event.position.dy,
            'buttons': event.buttons,
            'kind': event.kind.name,
          })}\n',
      mode: FileMode.append,
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) => _recordPointer('down', event),
            onPointerMove: (event) => _recordPointer('move', event),
            onPointerUp: (event) => _recordPointer('up', event),
            onPointerCancel: (event) => _recordPointer('cancel', event),
            child: EditorNativeTextDragDrop(
              enabled: true,
              payloadAt: (position) {
                File('${widget.directory.path}/payload-at.jsonl')
                    .writeAsStringSync(
                  '${jsonEncode({'x': position.dx, 'y': position.dy})}\n',
                  mode: FileMode.append,
                );
                return _payload;
              },
              buildDropRequest: (payload, position, operation) {
                File('${widget.directory.path}/drop-over.jsonl')
                    .writeAsStringSync(
                  '${jsonEncode({
                        'x': position.dx,
                        'y': position.dy,
                        'operation': operation.name,
                      })}\n',
                  mode: FileMode.append,
                );
                return EditorTextDragDropRequest(
                  payload: payload,
                  targetDocumentId: payload.selection.documentId,
                  targetDocumentVersion: payload.selection.documentVersion,
                  targetOffsetUtf16: 11,
                  operation: operation,
                );
              },
              onDrop: (request) {
                File('${widget.directory.path}/drop.json').writeAsStringSync(
                  jsonEncode({
                    'selectedText': request.payload.selectedText,
                    'operation': request.operation.name,
                    'targetOffsetUtf16': request.targetOffsetUtf16,
                  }),
                );
              },
              onDragCompleted: (payload, operation) {
                File('${widget.directory.path}/drag-completed.json')
                    .writeAsStringSync(
                  jsonEncode({
                    'selectedText': payload.selectedText,
                    'operation': operation.name,
                  }),
                );
              },
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      key: ValueKey('alula-dnd-source'),
                      width: 240,
                      height: 90,
                      child: Center(child: Text('Drag source')),
                    ),
                    SizedBox(height: 120),
                    SizedBox(
                      key: ValueKey('alula-dnd-target'),
                      width: 240,
                      height: 90,
                      child: Center(child: Text('Drop target')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
