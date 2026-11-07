/// Width strategy for the ordinary editor tabs in a workbench group.
enum EditorTabSizing {
  fit,
  shrink,
  fixed;

  static EditorTabSizing fromSessionValue(Object? value) => switch (value) {
        'shrink' => EditorTabSizing.shrink,
        'fixed' => EditorTabSizing.fixed,
        'fit' => EditorTabSizing.fit,
        _ => EditorTabSizing.fit,
      };
}

/// Computes bounded tab widths without depending on a widget tree.
class EditorTabWidthPolicy {
  const EditorTabWidthPolicy._();

  static const double fixedMinWidth = 50;
  static const double fixedMaxWidth = 160;
  static const double shrinkMinWidth = 80;

  static List<double> layout({
    required List<double> contentWidths,
    required double availableWidth,
    required EditorTabSizing sizing,
    bool wrapping = false,
  }) {
    if (contentWidths.isEmpty) return const [];

    final widths = contentWidths
        .map((width) => width.isFinite && width > 0 ? width : 0.0)
        .toList(growable: false);
    final available =
        availableWidth.isFinite && availableWidth > 0 ? availableWidth : 0.0;

    if (wrapping) {
      return switch (sizing) {
        EditorTabSizing.fit => widths
            .map((width) => width > available ? available : width)
            .toList(growable: false),
        EditorTabSizing.shrink => widths.map((width) {
            final minimumBounded =
                width < shrinkMinWidth ? shrinkMinWidth : width;
            if (minimumBounded <= available) return minimumBounded;
            return available < shrinkMinWidth ? shrinkMinWidth : available;
          }).toList(growable: false),
        EditorTabSizing.fixed => List<double>.filled(
            widths.length,
            _clamp(
              available,
              fixedMinWidth,
              fixedMaxWidth,
            ),
            growable: false),
      };
    }

    return switch (sizing) {
      EditorTabSizing.fit => widths,
      EditorTabSizing.fixed => _fixed(widths.length, available),
      EditorTabSizing.shrink => _shrink(widths, available),
    };
  }

  static List<double> _fixed(int count, double available) {
    final width = _clamp(available / count, fixedMinWidth, fixedMaxWidth);
    return List<double>.filled(count, width, growable: false);
  }

  static double _clamp(double value, double min, double max) => value < min
      ? min
      : value > max
          ? max
          : value;

  static List<double> _shrink(List<double> widths, double available) {
    final maximums = widths
        .map((width) => width < shrinkMinWidth ? shrinkMinWidth : width)
        .toList(growable: false);
    final minimumTotal = shrinkMinWidth * widths.length;
    if (minimumTotal > available) {
      return List<double>.filled(widths.length, shrinkMinWidth,
          growable: false);
    }
    final maximumTotal = maximums.fold<double>(0, (sum, width) => sum + width);
    if (maximumTotal <= available) return maximums;

    var low = shrinkMinWidth;
    var high = maximums.reduce((a, b) => a > b ? a : b);
    for (var i = 0; i < 48; i++) {
      final candidate = (low + high) / 2;
      final total = maximums.fold<double>(
        0,
        (sum, width) => sum + (width < candidate ? width : candidate),
      );
      if (total > available) {
        high = candidate;
      } else {
        low = candidate;
      }
    }
    return maximums
        .map((width) => width < low ? width : low)
        .toList(growable: false);
  }
}
