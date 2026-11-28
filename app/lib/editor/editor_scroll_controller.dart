import 'package:flutter/widgets.dart';

/// Per-editor vertical scroll controller with optional temporary end padding.
class EditorScrollController extends ScrollController {
  EditorScrollController({super.initialScrollOffset});

  @override
  EditorScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) =>
      EditorScrollPosition(
        physics: physics,
        context: context,
        oldPosition: oldPosition,
        initialPixels: initialScrollOffset,
        keepScrollOffset: keepScrollOffset,
        debugLabel: debugLabel,
      );
}

class EditorScrollPosition extends ScrollPositionWithSingleContext {
  EditorScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    super.initialPixels,
    super.keepScrollOffset,
    super.debugLabel,
  });

  double? _textMaxScrollExtent;
  double _trailingExtent = 0;

  double get unpaddedMaxScrollExtent => _textMaxScrollExtent ?? maxScrollExtent;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    _textMaxScrollExtent = maxScrollExtent;
    return super.applyContentDimensions(
      minScrollExtent,
      maxScrollExtent + _trailingExtent,
    );
  }

  /// The caller invalidates the editor layout when the reservation changes.
  /// Scrollable updates its drag recognizers during that layout.
  bool reserveTrailingExtent(double extent) {
    if (extent == _trailingExtent) return false;
    _trailingExtent = extent;
    if (_textMaxScrollExtent case final textMax?) {
      final maximum = textMax + extent;
      if (hasPixels && pixels > maximum) jumpTo(maximum);
    }
    return true;
  }
}
