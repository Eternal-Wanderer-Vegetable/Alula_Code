import 'package:flutter/material.dart';

/// Visual intent for an editor tab drop target. This only previews the
/// operation already selected by the workbench's existing drop handlers.
enum EditorDropOverlayMode {
  group,
  tab,
  center,
  splitLeft,
  splitRight,
  splitUp,
  splitDown,
}

/// Non-interactive hover feedback for editor tab drag targets.
///
/// The overlay deliberately ignores pointers so nested DragTargets continue to
/// receive drag updates, matching VS Code's editor group overlay behavior.
class EditorDropOverlay extends StatelessWidget {
  const EditorDropOverlay({
    required this.keyPrefix,
    required this.child,
    this.mode,
    this.copyRequested = false,
    super.key,
  });

  final String keyPrefix;
  final Widget child;
  final EditorDropOverlayMode? mode;
  final bool copyRequested;

  @override
  Widget build(BuildContext context) {
    final currentMode = mode;
    if (currentMode == null) return child;

    final isHorizontalSplit = currentMode == EditorDropOverlayMode.splitLeft ||
        currentMode == EditorDropOverlayMode.splitRight;
    final isVerticalSplit = currentMode == EditorDropOverlayMode.splitUp ||
        currentMode == EditorDropOverlayMode.splitDown;
    final alignment = switch (currentMode) {
      EditorDropOverlayMode.splitLeft => Alignment.centerLeft,
      EditorDropOverlayMode.splitRight => Alignment.centerRight,
      EditorDropOverlayMode.splitUp => Alignment.topCenter,
      EditorDropOverlayMode.splitDown => Alignment.bottomCenter,
      _ => Alignment.center,
    };
    final icon = switch (currentMode) {
      EditorDropOverlayMode.splitLeft => Icons.arrow_left,
      EditorDropOverlayMode.splitRight => Icons.arrow_right,
      EditorDropOverlayMode.splitUp => Icons.arrow_upward,
      EditorDropOverlayMode.splitDown => Icons.arrow_downward,
      EditorDropOverlayMode.group => Icons.drive_file_move_outline,
      EditorDropOverlayMode.tab => Icons.compare_arrows,
      EditorDropOverlayMode.center => Icons.move_to_inbox_outlined,
    };
    final label = switch (currentMode) {
      EditorDropOverlayMode.group => '移入此编辑器组',
      EditorDropOverlayMode.tab => '放到此标签',
      EditorDropOverlayMode.center => '移入此编辑器组',
      EditorDropOverlayMode.splitLeft => '拆分到左侧',
      EditorDropOverlayMode.splitRight => '拆分到右侧',
      EditorDropOverlayMode.splitUp => '拆分到上方',
      EditorDropOverlayMode.splitDown => '拆分到下方',
    };

    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedAlign(
                    alignment: alignment,
                    duration: const Duration(milliseconds: 70),
                    curve: Curves.easeOut,
                    child: FractionallySizedBox(
                      widthFactor: isHorizontalSplit ? 0.5 : 1,
                      heightFactor: isVerticalSplit ? 0.5 : 1,
                      child: Container(
                        key: ValueKey('$keyPrefix-overlay-${currentMode.name}'),
                        decoration: BoxDecoration(
                          color: const Color.fromRGBO(0, 122, 204, 0.18),
                          border: Border.all(
                            color: const Color(0xFF55B8FF),
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color.fromRGBO(20, 22, 26, 0.82),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(icon,
                                      size: 18, color: const Color(0xFF9DD6FF)),
                                  const SizedBox(width: 6),
                                  Text(
                                    label,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (copyRequested)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: DecoratedBox(
                        key: ValueKey('$keyPrefix-copy-badge'),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1F6F43),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: const Color(0xFF72D59A),
                          ),
                        ),
                        child: const Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.copy, size: 13, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                '复制',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
