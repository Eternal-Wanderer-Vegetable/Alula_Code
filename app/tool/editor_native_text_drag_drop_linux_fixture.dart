import 'dart:convert';
import 'dart:io';

import 'package:alula_app/editor/editor_native_text_drag_drop.dart';
import 'package:alula_app/editor/text_drag_drop.dart';
import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final directoryPath = Platform.environment['ALULA_LINUX_DND_DIR'];
  if (directoryPath == null || directoryPath.isEmpty) {
    throw StateError('ALULA_LINUX_DND_DIR is required.');
  }
  final directory = Directory(directoryPath)..createSync(recursive: true);
  runApp(_LinuxNativeDragFixture(directory: directory));
}

class _LinuxNativeDragFixture extends StatefulWidget {
  const _LinuxNativeDragFixture({required this.directory});

  final Directory directory;

  @override
  State<_LinuxNativeDragFixture> createState() =>
      _LinuxNativeDragFixtureState();
}

class _LinuxNativeDragFixtureState extends State<_LinuxNativeDragFixture> {
  final GlobalKey _externalSourceKey = GlobalKey();
  final GlobalKey _internalSourceKey = GlobalKey();
  final GlobalKey _targetKey = GlobalKey();

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
      _writeLayout(view.devicePixelRatio);
      File('${widget.directory.path}/ready').writeAsStringSync('ready');
    });
  }

  void _writeLayout(double devicePixelRatio) {
    Offset centerOf(GlobalKey key) {
      final box = key.currentContext!.findRenderObject()! as RenderBox;
      return box.localToGlobal(box.size.center(Offset.zero));
    }

    Map<String, double> jsonPoint(Offset point) =>
        {'x': point.dx, 'y': point.dy};

    File('${widget.directory.path}/layout.json').writeAsStringSync(
      jsonEncode({
        'source': jsonPoint(centerOf(_internalSourceKey)),
        'externalSource': jsonPoint(centerOf(_externalSourceKey)),
        'target': jsonPoint(centerOf(_targetKey)),
        'devicePixelRatio': devicePixelRatio,
      }),
    );
  }

  bool _isExternalSource(Offset position) {
    final box = _externalSourceKey.currentContext?.findRenderObject();
    if (box is! RenderBox) return false;
    return box.size.contains(box.globalToLocal(position));
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
                return _isExternalSource(position) ? null : _payload;
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
              editorExternalTextDropTargetAt: (position) =>
                  _isExternalSource(position)
                      ? null
                      : const EditorExternalTextDropTarget(
                          targetDocumentId: 7002,
                          targetDocumentVersion: 4,
                          targetOffsetUtf16: 6,
                        ),
              onExternalTextDrop: (request) {
                File('${widget.directory.path}/external-drop.json')
                    .writeAsStringSync(
                  jsonEncode({
                    'text': request.plainText,
                    'targetDocumentId':
                        request.externalTextTarget.targetDocumentId,
                    'targetDocumentVersion':
                        request.externalTextTarget.targetDocumentVersion,
                    'targetOffsetUtf16':
                        request.externalTextTarget.targetOffsetUtf16,
                  }),
                );
              },
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      key: _internalSourceKey,
                      width: 240,
                      height: 90,
                      child: const Center(child: Text('Drag source')),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      key: _externalSourceKey,
                      width: 240,
                      height: 90,
                      child: const _ExternalPlainTextSource(),
                    ),
                    const SizedBox(height: 120),
                    SizedBox(
                      key: _targetKey,
                      width: 240,
                      height: 90,
                      child: const Center(child: Text('Drop target')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class _ExternalPlainTextSource extends StatelessWidget {
  const _ExternalPlainTextSource();

  @override
  Widget build(BuildContext context) => DragItemWidget(
        dragItemProvider: (_) async {
          final item = DragItem();
          item.add(Formats.plainText('external text'));
          return item;
        },
        allowedOperations: () => const [DropOperation.copy],
        child: const DraggableWidget(
          child: Center(child: Text('External text source')),
        ),
      );
}
