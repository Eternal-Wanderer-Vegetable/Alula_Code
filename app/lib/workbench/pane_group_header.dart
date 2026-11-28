import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

class PaneGroupHeader extends StatefulWidget {
  const PaneGroupHeader({
    super.key,
    required this.semanticsKey,
    required this.label,
    required this.collapsed,
    required this.onSetCollapsed,
    required this.onFocus,
    this.compactIcon,
  });

  final Key semanticsKey;
  final String label;
  final bool collapsed;
  final ValueChanged<bool> onSetCollapsed;
  final VoidCallback onFocus;
  final IconData? compactIcon;

  @override
  State<PaneGroupHeader> createState() => _PaneGroupHeaderState();
}

class _PaneGroupHeaderState extends State<PaneGroupHeader> {
  final _focus = FocusNode();

  void _toggle() {
    _focus.requestFocus();
    widget.onSetCollapsed(!widget.collapsed);
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: widget.semanticsKey,
      label: widget.compactIcon == null ? null : widget.label,
      button: true,
      expanded: !widget.collapsed,
      onTap: _toggle,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              widget.onSetCollapsed(true),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              widget.onSetCollapsed(false),
        },
        child: Material(
          color: const Color(0xFF252932),
          child: InkWell(
            focusNode: _focus,
            excludeFromSemantics: true,
            onFocusChange: (focused) {
              if (focused) widget.onFocus();
            },
            onTap: _toggle,
            child: widget.compactIcon != null
                ? Tooltip(
                    message: widget.label,
                    excludeFromSemantics: true,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Icon(widget.compactIcon, size: 16),
                      ),
                    ),
                  )
                : ClipRect(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          Icon(
                            widget.collapsed
                                ? Icons.chevron_right
                                : Icons.expand_more,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              widget.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
  }
}
