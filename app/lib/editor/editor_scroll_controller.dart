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

  ({double min, double max})? _textExtent;
  double _trailingExtent = 0;

  double get unpaddedMaxScrollExtent => _textExtent?.max ?? maxScrollExtent;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    _textExtent = (min: minScrollExtent, max: maxScrollExtent);
    return super.applyContentDimensions(
      minScrollExtent,
      maxScrollExtent + _trailingExtent,
    );
  }

  void reserveTrailingExtent(double extent) {
    if (extent == _trailingExtent) return;
    _trailingExtent = extent;
    if (_textExtent case final textExtent?) {
      final maximum = textExtent.max + extent;
      if (hasPixels && pixels > maximum) jumpTo(maximum);
      super.applyContentDimensions(textExtent.min, maximum);
    }
  }
}
