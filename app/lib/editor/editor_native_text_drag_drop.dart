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

typedef EditorExternalTextDropTargetBuilder = EditorExternalTextDropTarget?
    Function(Offset globalPosition);

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
    this.editorExternalTextDropTargetAt,
    this.onExternalTextDrop,
    required this.child,
  });

  final bool enabled;
  final EditorTextDragPayloadBuilder payloadAt;
  final EditorTextDropRequestBuilder buildDropRequest;
  final ValueChanged<EditorTextDragDropRequest> onDrop;
  final EditorTextDragCompleted onDragCompleted;
  final EditorExternalTextDropTargetBuilder? editorExternalTextDropTargetAt;
  final ValueChanged<EditorExternalTextDropRequest>? onExternalTextDrop;
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

  DropOperation? _chooseExternalPlainTextDropOperation(
    Set<DropOperation> allowed,
  ) {
    if (allowed.contains(DropOperation.copy)) return DropOperation.copy;
    if (allowed.contains(DropOperation.move)) return DropOperation.move;
    return null;
  }

  bool _isAlulaLocalItem(DropItem item) {
    final localData = item.localData;
    return localData is Map &&
        localData['kind'] == EditorTextDragSelection.localDataKind;
  }

  DropItem? _externalPlainTextItem(DropSession session) {
    if (session.items.length != 1) return null;
    final item = session.items.single;
    if (_isAlulaLocalItem(item) || !item.canProvide(Formats.plainText)) {
      return null;
    }
    return item;
  }

  Future<String?> _readPlainText(DropItem item) async {
    final reader = item.dataReader;
    if (reader == null || !reader.canProvide(Formats.plainText)) return null;

    final completer = Completer<String?>();
    final progress = reader.getValue<String>(
      Formats.plainText,
      (value) {
        if (!completer.isCompleted) completer.complete(value);
      },
      onError: (_) {
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    if (progress == null) return null;
    try {
      return await completer.future.timeout(const Duration(seconds: 10));
    } on Object {
      progress.cancel();
      return null;
    }
  }

  DropOperation _onDropOver(DropOverEvent event) {
    final payload = _payloadFromSession(event.session);
    if (payload != null) {
      final operation = _requestedOperation(event.session.allowedOperations);
      if (operation == null) return DropOperation.none;
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

    if (widget.onExternalTextDrop == null ||
        widget.editorExternalTextDropTargetAt == null ||
        _externalPlainTextItem(event.session) == null ||
        widget.editorExternalTextDropTargetAt!(event.position.global) == null) {
      return DropOperation.none;
    }
    return _chooseExternalPlainTextDropOperation(
          event.session.allowedOperations,
        ) ??
        DropOperation.none;
  }

  Future<void> _onPerformDrop(PerformDropEvent event) async {
    final payload = _payloadFromSession(event.session);
    final operation = switch (event.acceptedOperation) {
      DropOperation.move => EditorTextDropOperation.move,
      DropOperation.copy => EditorTextDropOperation.copy,
      _ => null,
    };
    if (payload != null) {
      if (operation == null) return;
      final request = widget.buildDropRequest(
        payload,
        event.position.global,
        operation,
      );
      if (request != null) widget.onDrop(request);
      return;
    }

    final item = _externalPlainTextItem(event.session);
    final target = widget.editorExternalTextDropTargetAt?.call(
      event.position.global,
    );
    if (item == null || target == null || operation == null) return;
    final text = await _readPlainText(item);
    if (text == null) return;
    widget.onExternalTextDrop?.call(
      EditorExternalTextDropRequest(
        externalTextTarget: target,
        plainText: text,
      ),
    );
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
          formats: widget.onExternalTextDrop != null &&
                  widget.editorExternalTextDropTargetAt != null
              ? const [Formats.plainText]
              : const [],
          hitTestBehavior: HitTestBehavior.opaque,
          onDropOver: _onDropOver,
          onPerformDrop: _onPerformDrop,
          child: widget.child,
        ),
      ),
    );
  }
}
