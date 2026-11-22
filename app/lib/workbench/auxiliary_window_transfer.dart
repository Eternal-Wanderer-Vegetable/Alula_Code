import 'dart:collection';

import 'package:flutter/painting.dart';

const auxiliaryWindowBoundsMethod = 'alula_auxiliary_window_bounds';
const auxiliaryWindowBoundsQueryMethod = 'alula_auxiliary_window_bounds_query';
const auxiliaryDocumentTransferPrepareMethod =
    'alula_auxiliary_document_transfer_prepare';
const auxiliaryDocumentTransferCommitMethod =
    'alula_auxiliary_document_transfer_commit';
const auxiliaryDocumentTransferAbortMethod =
    'alula_auxiliary_document_transfer_abort';
const auxiliaryDocumentTransferStatusMethod =
    'alula_auxiliary_document_transfer_status';
const auxiliaryTabReturnPrepareMethod = 'alula_auxiliary_tab_return_prepare';
const auxiliaryTabReturnFinishMethod = 'alula_auxiliary_tab_return_finish';
const maxAuxiliaryWindowBounds = 32;

/// Only a same-application drag can carry this ticket. The document stays in
/// the auxiliary engine until the drop target requests it over the window channel.
class AuxiliaryTabDragTicket {
  const AuxiliaryTabDragTicket(this.windowId, this.sequence);

  static const _kind = 'alula.auxiliaryEditorTab';

  final String windowId;
  final int sequence;

  Map<String, Object?> toLocalData() => {
        'kind': _kind,
        'windowId': windowId,
        'sequence': sequence,
      };

  static AuxiliaryTabDragTicket? tryParse(Object? value) {
    if (value is! Map || value['kind'] != _kind) return null;
    final windowId = value['windowId'];
    final sequence = value['sequence'];
    if (windowId is! String ||
        windowId.isEmpty ||
        sequence is! int ||
        sequence <= 0) {
      return null;
    }
    return AuxiliaryTabDragTicket(windowId, sequence);
  }
}

class AuxiliaryWindowBounds {
  const AuxiliaryWindowBounds({
    required this.windowId,
    required this.sequence,
    required this.bounds,
  });

  final String windowId;
  final int sequence;
  final Rect bounds;

  Map<String, Object?> toMap() => {
        'windowId': windowId,
        'sequence': sequence,
        'left': bounds.left,
        'top': bounds.top,
        'width': bounds.width,
        'height': bounds.height,
      };

  static AuxiliaryWindowBounds? tryParse(Object? value) {
    if (value is! Map) return null;
    final windowId = value['windowId'];
    final sequence = value['sequence'];
    final left = value['left'];
    final top = value['top'];
    final width = value['width'];
    final height = value['height'];
    if (windowId is! String ||
        windowId.isEmpty ||
        sequence is! int ||
        sequence <= 0 ||
        left is! num ||
        top is! num ||
        width is! num ||
        height is! num) {
      return null;
    }
    final x = left.toDouble();
    final y = top.toDouble();
    final w = width.toDouble();
    final h = height.toDouble();
    if (!x.isFinite ||
        !y.isFinite ||
        !w.isFinite ||
        !h.isFinite ||
        w <= 0 ||
        h <= 0) {
      return null;
    }
    return AuxiliaryWindowBounds(
      windowId: windowId,
      sequence: sequence,
      bounds: Rect.fromLTWH(x, y, w, h),
    );
  }
}

/// Event-driven, bounded bounds registry used only to route an editor drop.
/// Ambiguous overlap is rejected so the caller can keep the source document.
class AuxiliaryWindowBoundsRegistry {
  AuxiliaryWindowBoundsRegistry({this.capacity = maxAuxiliaryWindowBounds})
      : assert(capacity > 0);

  final int capacity;
  final LinkedHashMap<String, AuxiliaryWindowBounds> _windows =
      LinkedHashMap<String, AuxiliaryWindowBounds>();

  int get length => _windows.length;

  bool update(AuxiliaryWindowBounds bounds) {
    final existing = _windows[bounds.windowId];
    if (existing != null && bounds.sequence <= existing.sequence) return false;
    if (existing == null && _windows.length >= capacity) return false;
    _windows[bounds.windowId] = bounds;
    return true;
  }

  bool remove(String windowId) => _windows.remove(windowId) != null;

  void clear() => _windows.clear();

  int windowCountAt(Offset pointer) {
    if (!pointer.dx.isFinite || !pointer.dy.isFinite) return 0;
    var matches = 0;
    for (final bounds in _windows.values) {
      if (bounds.bounds.contains(pointer)) matches++;
    }
    return matches;
  }

  String? uniqueWindowAt(Offset pointer) {
    if (!pointer.dx.isFinite || !pointer.dy.isFinite) return null;
    String? match;
    for (final entry in _windows.entries) {
      if (!entry.value.bounds.contains(pointer)) continue;
      if (match != null) return null;
      match = entry.key;
    }
    return match;
  }
}
