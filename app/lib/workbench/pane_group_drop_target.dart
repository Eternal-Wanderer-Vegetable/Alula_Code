import 'package:flutter/material.dart';

class PaneGroupDropTarget<T extends Object> extends StatefulWidget {
  const PaneGroupDropTarget({
    super.key,
    required this.axis,
    required this.view,
    required this.highlightKeyPrefix,
    required this.sourceFor,
    required this.onReorder,
    required this.child,
  });

  final Axis axis;
  final String view;
  final String highlightKeyPrefix;
  final String? Function(T data) sourceFor;
  final void Function(String source, String target, bool before) onReorder;
  final Widget child;

  @override
  State<PaneGroupDropTarget<T>> createState() => _PaneGroupDropTargetState<T>();
}

class _PaneGroupDropTargetState<T extends Object>
    extends State<PaneGroupDropTarget<T>> {
  bool _before = true;

  String? _source(T data) {
    final source = widget.sourceFor(data);
    return source == widget.view ? null : source;
  }

  bool _isBefore(Offset position) {
    final target = context.findRenderObject()! as RenderBox;
    final local = target.globalToLocal(position);
    return widget.axis == Axis.vertical
        ? local.dy < target.size.height / 2
        : local.dx < target.size.width / 2;
  }

  @override
  Widget build(BuildContext context) {
    final vertical = widget.axis == Axis.vertical;
    return DragTarget<T>(
      onWillAcceptWithDetails: (details) => _source(details.data) != null,
      onMove: (details) {
        if (_source(details.data) == null) return;
        final before = _isBefore(details.offset);
        if (_before != before) setState(() => _before = before);
      },
      onAcceptWithDetails: (details) {
        final source = _source(details.data);
        if (source != null) {
          widget.onReorder(source, widget.view, _isBefore(details.offset));
        }
      },
      builder: (context, candidates, _) => Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (candidates.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: FractionallySizedBox(
                  widthFactor: vertical ? null : 0.5,
                  heightFactor: vertical ? 0.5 : null,
                  alignment: vertical
                      ? (_before ? Alignment.topCenter : Alignment.bottomCenter)
                      : (_before
                          ? Alignment.centerLeft
                          : Alignment.centerRight),
                  child: DecoratedBox(
                    key: ValueKey(
                      '${widget.highlightKeyPrefix}-'
                      '${_before ? 'before' : 'after'}',
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0x30007ACC),
                      border: Border.fromBorderSide(
                        BorderSide(color: Color(0xFF55B8FF)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
