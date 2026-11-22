import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import 'auxiliary_window_transfer.dart';
import 'editor_drop_overlay.dart';

/// Presents a native drop target for an auxiliary editor tab.
class AuxiliaryTabDropTarget extends StatefulWidget {
  const AuxiliaryTabDropTarget({
    super.key,
    required this.keyPrefix,
    required this.mode,
    required this.canAccept,
    required this.onDrop,
    required this.child,
    this.bodyOverlayAt,
  });

  final String keyPrefix;
  final EditorDropOverlayMode mode;
  final EditorDropOverlayMode Function(Offset, bool disableSplit)?
      bodyOverlayAt;
  final bool Function(AuxiliaryTabDragTicket) canAccept;
  final Future<void> Function(
    AuxiliaryTabDragTicket,
    bool insertAfter,
    Offset position,
    bool disableSplit,
  ) onDrop;
  final Widget child;

  @override
  State<AuxiliaryTabDropTarget> createState() => _AuxiliaryTabDropTargetState();
}

class _AuxiliaryTabDropTargetState extends State<AuxiliaryTabDropTarget> {
  static const _inputChannel = MethodChannel('alula/drag_input');

  EditorDropOverlayMode? _hoverMode;
  int _hoverRevision = 0;

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

  void _setHoverMode(EditorDropOverlayMode? mode) {
    if (mounted && _hoverMode != mode) setState(() => _hoverMode = mode);
  }

  void _clearHover() {
    _hoverRevision++;
    _setHoverMode(null);
  }

  Future<bool> _splitTogglePressed() async {
    try {
      final pressed = await _inputChannel
          .invokeMethod<bool>('splitTogglePressed')
          .timeout(const Duration(milliseconds: 150), onTimeout: () => null);
      if (pressed != null) return pressed;
    } on MissingPluginException {
      // The native runner is absent in widget tests and embedded workbenches.
    } on PlatformException {
      // Fall back to the available Flutter keyboard state.
    }
    final keyboard = HardwareKeyboard.instance;
    return defaultTargetPlatform == TargetPlatform.macOS
        ? keyboard.isShiftPressed
        : keyboard.isAltPressed;
  }

  @override
  Widget build(BuildContext context) {
    final hoverMode = _hoverMode;
    return DropRegion(
      formats: const [],
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: (event) async {
        if (_acceptedTicket(event.session) == null) {
          _clearHover();
          return DropOperation.none;
        }
        final bodyOverlayAt = widget.bodyOverlayAt;
        final revision = ++_hoverRevision;
        final disableSplit =
            bodyOverlayAt != null && await _splitTogglePressed();
        if (!mounted || revision != _hoverRevision) return DropOperation.none;
        _setHoverMode(
            bodyOverlayAt?.call(event.position.global, disableSplit) ??
                widget.mode);
        return DropOperation.move;
      },
      onDropLeave: (_) => _clearHover(),
      onDropEnded: (_) => _clearHover(),
      onPerformDrop: (event) async {
        _clearHover();
        final ticket = _acceptedTicket(event.session);
        if (ticket == null || event.acceptedOperation != DropOperation.move) {
          return;
        }
        final insertAfter = widget.mode == EditorDropOverlayMode.tab &&
            event.position.local.dx > (context.size?.width ?? 0) / 2;
        final disableSplit =
            widget.bodyOverlayAt != null && await _splitTogglePressed();
        if (!mounted || !widget.canAccept(ticket)) return;
        await widget.onDrop(
          ticket,
          insertAfter,
          event.position.global,
          disableSplit,
        );
      },
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          if (hoverMode != null)
            Positioned.fill(
              child: IgnorePointer(
                child: EditorDropOverlay(
                  keyPrefix: widget.keyPrefix,
                  mode: hoverMode,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
