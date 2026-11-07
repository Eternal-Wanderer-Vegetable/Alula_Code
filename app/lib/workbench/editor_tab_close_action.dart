import 'package:flutter/material.dart';

/// Close action for an ordinary, closeable editor tab.
///
/// The action slot stays in the layout when the glyph is transparent, matching
/// Code-OSS's default reserved action area. A disabled action is also removed
/// from pointer and keyboard focus navigation.
class EditorTabCloseAction extends StatefulWidget {
  const EditorTabCloseAction({
    super.key,
    required this.actionKey,
    required this.enabled,
    required this.emphasized,
    required this.onPressed,
  });

  final Key actionKey;
  final bool enabled;
  final bool emphasized;
  final VoidCallback onPressed;

  @override
  State<EditorTabCloseAction> createState() => _EditorTabCloseActionState();
}

class _EditorTabCloseActionState extends State<EditorTabCloseAction> {
  late final FocusNode _focusNode = FocusNode(
    debugLabel: 'editor tab close action',
  );

  @override
  void didUpdateWidget(covariant EditorTabCloseAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    _focusNode.canRequestFocus = widget.enabled;
    if (!widget.enabled && _focusNode.hasFocus) _focusNode.unfocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showGlyph =
        widget.enabled && (widget.emphasized || _focusNode.hasFocus);
    return SizedBox(
      width: 12,
      height: 20,
      child: ExcludeSemantics(
        excluding: !widget.enabled,
        child: Semantics(
          label: '关闭',
          button: true,
          enabled: widget.enabled,
          onTap: widget.enabled ? widget.onPressed : null,
          child: IgnorePointer(
            ignoring: !widget.enabled,
            child: Opacity(
              opacity: showGlyph ? 1 : 0,
              child: InkWell(
                key: widget.actionKey,
                focusNode: _focusNode,
                canRequestFocus: widget.enabled,
                excludeFromSemantics: true,
                onFocusChange: (_) {
                  if (mounted) setState(() {});
                },
                onTap: widget.enabled ? widget.onPressed : null,
                child: const Icon(
                  Icons.close,
                  size: 12,
                  color: Colors.grey,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
