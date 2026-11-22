import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import 'auxiliary_window_transfer.dart';
import 'editor_drop_overlay.dart';

/// Presents the native counterpart of an editor group's tab or body target.
class AuxiliaryTabDropTarget extends StatefulWidget {
  const AuxiliaryTabDropTarget({
    super.key,
    required this.keyPrefix,
    required this.mode,
    required this.canAccept,
    required this.onDrop,
    required this.child,
  });

  final String keyPrefix;
  final EditorDropOverlayMode mode;
  final bool Function(AuxiliaryTabDragTicket) canAccept;
  final Future<void> Function(AuxiliaryTabDragTicket, bool insertAfter) onDrop;
  final Widget child;

  @override
  State<AuxiliaryTabDropTarget> createState() => _AuxiliaryTabDropTargetState();
}

class _AuxiliaryTabDropTargetState extends State<AuxiliaryTabDropTarget> {
  bool _hovered = false;

  AuxiliaryTabDragTicket? _acceptedTicket(DropSession session) {
    final keyboard = HardwareKeyboard.instance;
    final copy = defaultTargetPlatform == TargetPlatform.macOS
        ? keyboard.isAltPressed
        : keyboard.isControlPressed;
    if (copy ||
        session.items.length != 1 ||
        !session.allowedOperations.contains(DropOperation.move)) {
      return null;
    }
    final ticket =
        AuxiliaryTabDragTicket.tryParse(session.items.single.localData);
    return ticket != null && widget.canAccept(ticket) ? ticket : null;
  }

  void _setHovered(bool value) {
    if (mounted && _hovered != value) setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    return DropRegion(
      formats: const [],
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: (event) => _acceptedTicket(event.session) == null
          ? DropOperation.none
          : DropOperation.move,
      onDropEnter: (_) => _setHovered(true),
      onDropLeave: (_) => _setHovered(false),
      onDropEnded: (_) => _setHovered(false),
      onPerformDrop: (event) async {
        _setHovered(false);
        final ticket = _acceptedTicket(event.session);
        if (ticket == null || event.acceptedOperation != DropOperation.move) {
          return;
        }
        final insertAfter =
            event.position.local.dx >= (context.size?.width ?? 0) / 2;
        await widget.onDrop(ticket, insertAfter);
      },
      child: EditorDropOverlay(
        keyPrefix: widget.keyPrefix,
        mode: _hovered ? widget.mode : null,
        child: widget.child,
      ),
    );
  }
}
