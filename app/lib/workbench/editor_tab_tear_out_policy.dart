import 'dart:ui';

import 'package:screen_retriever/screen_retriever.dart';

/// Decides whether a released editor tab is outside the native workbench
/// window. Both inputs use desktop logical screen coordinates.
class EditorTabTearOutPolicy {
  const EditorTabTearOutPolicy._();

  static bool supportsGlobalScreenCoordinates({
    required bool isLinux,
    required String? waylandDisplay,
    required String? gdkBackend,
  }) {
    if (!isLinux) return true;
    final backend = gdkBackend?.split(',').first.trim().toLowerCase();
    if (backend != null && backend.isNotEmpty) return backend == 'x11';
    return waylandDisplay == null || waylandDisplay.isEmpty;
  }

  static bool shouldTearOut({
    required Rect? windowBounds,
    required Offset? pointerPosition,
  }) {
    if (windowBounds == null || pointerPosition == null) return false;
    if (windowBounds.isEmpty ||
        !windowBounds.left.isFinite ||
        !windowBounds.top.isFinite ||
        !windowBounds.right.isFinite ||
        !windowBounds.bottom.isFinite ||
        !pointerPosition.dx.isFinite ||
        !pointerPosition.dy.isFinite) {
      return false;
    }
    return !windowBounds.contains(pointerPosition);
  }

  /// Aligns screen_retriever's macOS cursor Y origin with window_manager's.
  ///
  /// window_manager reports window bounds from the primary screen's top edge;
  /// screen_retriever reports cursor coordinates from the lowest display edge.
  /// The display list exposes each visible frame in primary-screen coordinates,
  /// which lets us recover that origin shift without guessing the title-bar size.
  static Offset? alignMacOSCursorWithWindowBounds({
    required Offset pointerPosition,
    required List<Display> displays,
  }) {
    if (displays.isEmpty ||
        !pointerPosition.dx.isFinite ||
        !pointerPosition.dy.isFinite) {
      return null;
    }

    final primaryHeight = displays.first.size.height;
    if (!primaryHeight.isFinite || primaryHeight <= 0) return null;
    var lowestFrameMaxY = double.infinity;
    for (final display in displays) {
      final visiblePosition = display.visiblePosition;
      final visibleSize = display.visibleSize;
      if (!display.size.height.isFinite ||
          display.size.height <= 0 ||
          visiblePosition == null ||
          visibleSize == null ||
          !visiblePosition.dy.isFinite ||
          !visibleSize.height.isFinite ||
          visibleSize.height <= 0) {
        return null;
      }
      final frameOriginY =
          primaryHeight - visiblePosition.dy - visibleSize.height;
      final frameMaxY = frameOriginY + display.size.height;
      if (!frameMaxY.isFinite) return null;
      if (frameMaxY < lowestFrameMaxY) lowestFrameMaxY = frameMaxY;
    }
    if (!lowestFrameMaxY.isFinite) return null;

    return Offset(
      pointerPosition.dx,
      pointerPosition.dy + primaryHeight - lowestFrameMaxY,
    );
  }
}
