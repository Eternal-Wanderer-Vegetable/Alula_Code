import 'dart:math' as math;
import 'dart:ui' show SemanticsRole;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

class ProblemsTable extends StatefulWidget {
  const ProblemsTable({super.key, required this.body});

  final Widget Function(ProblemsTableSelection) body;

  @override
  State<ProblemsTable> createState() => _ProblemsTableState();
}

class _ProblemsTableState extends State<ProblemsTable> {
  static const _severityWidth = 36.0;
  static const _sashWidth = 9.0;
  static const _defaultShares = [.125, .5, .25, .125];
  static const _minimumWidths = [100.0, 120.0, 120.0, 100.0];
  static const _maximumWidths = [
    300.0,
    double.infinity,
    double.infinity,
    300.0,
  ];
  static const _minimumSpace = 440.0;

  List<double> _shares = _defaultShares;
  late final _selection = ProblemsTableSelection(setState);

  List<double> _minimums(double space) {
    if (space >= _minimumSpace) return _minimumWidths;
    final scale = space / _minimumSpace;
    return [for (final width in _minimumWidths) width * scale];
  }

  List<double> _layoutWidths(
    double space,
    List<double> minimums,
    List<double> shares,
  ) {
    final widths = [
      for (var column = 0; column < shares.length; column++)
        (space * shares[column])
            .clamp(minimums[column], _maximumWidths[column])
            .toDouble(),
    ];
    var remainder = space - widths.fold(0.0, (sum, width) => sum + width);
    // Let text columns absorb changes caused by the code and source bounds.
    for (final column in const [1, 2, 0, 3]) {
      final adjustment = remainder
          .clamp(
            minimums[column] - widths[column],
            _maximumWidths[column] - widths[column],
          )
          .toDouble();
      widths[column] += adjustment;
      remainder -= adjustment;
    }
    return widths;
  }

  void _resize(int column, double delta, double space, {bool reset = false}) {
    final minimums = _minimums(space);
    final widths = _layoutWidths(space, minimums, _shares);
    if (reset) {
      final defaults = _layoutWidths(space, minimums, _defaultShares);
      delta = defaults[column] - widths[column];
    }
    final direction = delta.sign;
    var remaining = delta.abs();

    // Resize the nearest columns first, then use room farther from the sash.
    for (var left = column; left >= 0 && remaining > 0; left--) {
      for (var right = column + 1;
          right < widths.length && remaining > 0;
          right++) {
        final expanding = direction > 0 ? left : right;
        final shrinking = direction > 0 ? right : left;
        final change = math.min(
          remaining,
          math.min(
            _maximumWidths[expanding] - widths[expanding],
            widths[shrinking] - minimums[shrinking],
          ),
        );
        widths[expanding] += change;
        widths[shrinking] -= change;
        remaining -= change;
      }
    }
    if (remaining == delta.abs()) return;
    setState(() {
      _shares = [for (final width in widths) width / space];
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      key: const ValueKey('problems-table'),
      role: SemanticsRole.table,
      container: true,
      explicitChildNodes: true,
      label: '诊断表格',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final severity = math.min(_severityWidth, width);
          final space = width - severity;
          final columns = _layoutWidths(space, _minimums(space), _shares);
          final sashes = <Widget>[];
          if (space > _minimumSpace) {
            var edge = severity;
            for (var column = 0; column < columns.length - 1; column++) {
              edge += columns[column];
              sashes.add(
                Positioned(
                  key: ValueKey('problems-table-column-resize-$column'),
                  left: edge - _sashWidth / 2,
                  top: 0,
                  bottom: 0,
                  width: _sashWidth,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeColumn,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      excludeFromSemantics: true,
                      dragStartBehavior: DragStartBehavior.down,
                      onHorizontalDragUpdate: (details) =>
                          _resize(column, details.delta.dx, space),
                      onDoubleTap: () => _resize(column, 0, space, reset: true),
                      child: Center(
                        child: SizedBox(
                          width: 1,
                          height: double.infinity,
                          child: ColoredBox(color: colors.outlineVariant),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }
          }
          return _ProblemsTableWidths(
            widths: [severity, ...columns],
            child: Stack(
              children: [
                Column(
                  children: [
                    ColoredBox(
                      color: colors.surfaceContainer,
                      child: SizedBox(
                        height: 28,
                        child: ProblemsTableLine(
                          header: true,
                          severity: Semantics(
                            label: '严重级别',
                            child: const SizedBox(),
                          ),
                          code: const Text('代码'),
                          message: const Text('消息'),
                          file: const Text('文件'),
                          source: const Text('来源'),
                        ),
                      ),
                    ),
                    Expanded(child: widget.body(_selection)),
                  ],
                ),
                ...sashes,
              ],
            ),
          );
        },
      ),
    );
  }
}

class ProblemsTableSelection {
  ProblemsTableSelection(this._update);

  final void Function(VoidCallback) _update;
  final Set<Object> _selected = {};
  Object? _anchor;

  bool get hasSelection => _selected.isNotEmpty;
  bool get hasState => hasSelection || _anchor != null;

  bool contains(Object key) => _selected.contains(key);

  static List<Object> rowKeys(List<Map<String, Object?>> diagnostics) {
    final occurrences = <Object, int>{};
    return diagnostics.map<Object>((diagnostic) {
      final marker = (
        document: diagnostic['_documentId'] ?? diagnostic['file'],
        line: diagnostic['line'],
        character: diagnostic['character'],
        endLine: diagnostic['endLine'],
        endCharacter: diagnostic['endCharacter'],
        severity: diagnostic['severity'],
        code: diagnostic['code'],
        source: diagnostic['source'],
        message: diagnostic['message'],
      );
      final occurrence = occurrences.update(
        marker,
        (count) => count + 1,
        ifAbsent: () => 0,
      );
      return (marker, occurrence);
    }).toList(growable: false);
  }

  void retainVisible(List<Object> rows) {
    _selected.retainAll(rows);
    if (_anchor != null && !rows.contains(_anchor)) _anchor = null;
  }

  void select(
    List<Object> rows,
    int index, {
    required bool extend,
    required bool toggle,
    int? focusedIndex,
  }) {
    _update(() {
      final target = rows[index];
      if (!extend) {
        _anchor = target;
        if (!toggle) _selected.clear();
        if (!_selected.remove(target)) _selected.add(target);
        return;
      }

      final currentAnchor = _anchor;
      final anchorIndex =
          currentAnchor == null ? -1 : rows.indexOf(currentAnchor);
      final anchor = anchorIndex >= 0 ? anchorIndex : focusedIndex ?? index;
      _anchor = rows[anchor];

      // Replace the contiguous selection around the anchor and keep other ranges.
      var first = anchor;
      var last = anchor;
      while (first > 0 && _selected.contains(rows[first - 1])) {
        first--;
      }
      while (last + 1 < rows.length && _selected.contains(rows[last + 1])) {
        last++;
      }
      _selected
        ..removeAll(rows.getRange(first, last + 1))
        ..addAll(rows.getRange(
            math.min(anchor, index), math.max(anchor, index) + 1));
    });
  }
}

class _ProblemsTableWidths extends InheritedWidget {
  const _ProblemsTableWidths({required this.widths, required super.child});

  final List<double> widths;

  @override
  bool updateShouldNotify(_ProblemsTableWidths oldWidget) =>
      !listEquals(widths, oldWidget.widths);
}

class ProblemsTableLine extends StatelessWidget {
  const ProblemsTableLine({
    super.key,
    this.header = false,
    required this.severity,
    required this.code,
    required this.message,
    required this.file,
    required this.source,
  });

  final bool header;
  final Widget severity;
  final Widget code;
  final Widget message;
  final Widget file;
  final Widget source;

  @override
  Widget build(BuildContext context) {
    final widths = context
        .dependOnInheritedWidgetOfExactType<_ProblemsTableWidths>()!
        .widths;
    final cells = [Center(child: severity), code, message, file, source];
    return Semantics(
      role: SemanticsRole.row,
      container: true,
      explicitChildNodes: true,
      child: DefaultTextStyle.merge(
        style: TextStyle(
          fontSize: 12,
          fontWeight: header ? FontWeight.w600 : FontWeight.normal,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        child: Row(
          children: [
            for (var column = 0; column < cells.length; column++)
              SizedBox(
                width: widths[column],
                child: Semantics(
                  role:
                      header ? SemanticsRole.columnHeader : SemanticsRole.cell,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: cells[column],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
