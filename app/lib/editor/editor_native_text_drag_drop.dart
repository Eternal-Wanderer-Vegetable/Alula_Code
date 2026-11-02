import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:irondash_engine_context/irondash_engine_context.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import 'text_drag_drop.dart';

typedef EditorTextDragPayloadBuilder = EditorTextDragPayload? Function(
  Offset globalPosition,
);

typedef EditorTextDropRequestBuilder = EditorTextDragDropRequest? Function(
  EditorTextDragPayload payload,
  Offset globalPosition,
  EditorTextDropOperation operation,
);

typedef EditorTextDragCompleted = void Function(
  EditorTextDragPayload payload,
  EditorTextDropOperation operation,
);

/// Native desktop drag/drop shell for bounded editor text selections.
///
/// The editor owns document validation and text hit testing. This widget only
/// adapts the native drag session and never reads or mutates document state.
class EditorNativeTextDragDrop extends StatefulWidget {
  const EditorNativeTextDragDrop({
    super.key,
    required this.enabled,
    required this.payloadAt,
    required this.buildDropRequest,
    required this.onDrop,
    required this.onDragCompleted,
    required this.child,
  });

  final bool enabled;
  final EditorTextDragPayloadBuilder payloadAt;
  final EditorTextDropRequestBuilder buildDropRequest;
  final ValueChanged<EditorTextDragDropRequest> onDrop;
  final EditorTextDragCompleted onDragCompleted;
  final Widget child;

  @override
  State<EditorNativeTextDragDrop> createState() =>
      _EditorNativeTextDragDropState();
}

class _EditorNativeTextDragDropState extends State<EditorNativeTextDragDrop> {
  bool _nativeDragDropReady = defaultTargetPlatform != TargetPlatform.macOS;
  EditorTextDragPayload? _pendingPayload;

  @override
  void initState() {
    super.initState();
    if (!_nativeDragDropReady) {
      unawaited(_waitForEngineContext());
    }
  }

  Future<void> _waitForEngineContext() async {
    try {
      await EngineContext.instance.getEngineHandle();
    } on Object catch (error) {
      debugPrint('macOS native drag/drop is unavailable: $error');
      return;
    }
    if (mounted) setState(() => _nativeDragDropReady = true);
  }

  bool _isLocationDraggable(Offset globalPosition) {
    final payload = widget.payloadAt(globalPosition);
    _pendingPayload = payload;
    return payload != null;
  }

  Future<DragItem?> _provideDragItem(DragItemRequest request) async {
    final payload = _pendingPayload;
    if (payload == null) return null;
    final item = DragItem(localData: payload.toLocalData());
    item.add(Formats.plainText(payload.selectedText));
    void onCompleted() {
      final operation = request.session.dragCompleted.value;
      if (operation == null) return;
      request.session.dragCompleted.removeListener(onCompleted);
      if (mounted && _pendingPayload?.token == payload.token) {
        _pendingPayload = null;
      }
      final mappedOperation = switch (operation) {
        DropOperation.move => EditorTextDropOperation.move,
        DropOperation.copy => EditorTextDropOperation.copy,
        _ => null,
      };
      if (mounted && mappedOperation != null) {
        widget.onDragCompleted(payload, mappedOperation);
      }
    }

    request.session.dragCompleted.addListener(onCompleted);
    return item;
  }

  EditorTextDragPayload? _payloadFromSession(DropSession session) {
    if (session.items.length != 1) return null;
    return EditorTextDragPayload.tryParseLocalData(
      session.items.single.localData,
    );
  }

  EditorTextDropOperation? _requestedOperation(Set<DropOperation> allowed) {
    final copyModifier = defaultTargetPlatform == TargetPlatform.macOS
        ? HardwareKeyboard.instance.isAltPressed
        : HardwareKeyboard.instance.isControlPressed;
    final requested = copyModifier
        ? EditorTextDropOperation.copy
        : EditorTextDropOperation.move;
    final nativeOperation = requested == EditorTextDropOperation.copy
        ? DropOperation.copy
        : DropOperation.move;
    return allowed.contains(nativeOperation) ? requested : null;
  }

  DropOperation _onDropOver(DropOverEvent event) {
    final payload = _payloadFromSession(event.session);
    final operation = _requestedOperation(event.session.allowedOperations);
    if (payload == null || operation == null) return DropOperation.none;
    final request = widget.buildDropRequest(
      payload,
      event.position.global,
      operation,
    );
    if (request == null) return DropOperation.none;
    return operation == EditorTextDropOperation.copy
        ? DropOperation.copy
        : DropOperation.move;
  }

  Future<void> _onPerformDrop(PerformDropEvent event) async {
    final payload = _payloadFromSession(event.session);
    final operation = switch (event.acceptedOperation) {
      DropOperation.move => EditorTextDropOperation.move,
      DropOperation.copy => EditorTextDropOperation.copy,
      _ => null,
    };
    if (payload == null || operation == null) return;
    final request = widget.buildDropRequest(
      payload,
      event.position.global,
      operation,
    );
    if (request != null) widget.onDrop(request);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || !_nativeDragDropReady) return widget.child;
    return DragItemWidget(
      dragItemProvider: _provideDragItem,
      allowedOperations: () => const [DropOperation.move, DropOperation.copy],
      child: DraggableWidget(
        isLocationDraggable: _isLocationDraggable,
        child: DropRegion(
          formats: const [],
          hitTestBehavior: HitTestBehavior.opaque,
          onDropOver: _onDropOver,
          onPerformDrop: _onPerformDrop,
          child: widget.child,
        ),
      ),
    );
  }
}
