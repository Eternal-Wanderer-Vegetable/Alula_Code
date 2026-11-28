/// 分割树渲染器（docs/09 W1）。
///
/// grid 不知道区域内容：页面通过 `builders`（region → WidgetBuilder）注入，
/// 便于对布局行为单独做 widget 测试。
///
/// 分割条规则：只渲染在两个相邻「弹性」节点之间（固定叶子如活动栏、
/// 折叠叶子边缘没有分割条）；拖拽回调走 WorkbenchLayout.dragDivider。
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show
        DragStartBehavior,
        PointerDeviceKind,
        kDoubleTapSlop,
        kDoubleTapTimeout,
        kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;

import 'layout_controller.dart';
import 'layout_model.dart';
import 'layout_store.dart';
import 'panel_alignment.dart';
import 'panel_maximize.dart';

/// 分割条主轴占位（含命中区）；视觉线居中 1px。
const double kDividerThickness = workbenchDividerThickness;

const Color _kDividerColor = Color(0xFF2A2E37);

typedef CenteredEditorLayout = ({
  bool enabled,
  CenteredMargins margins,
  ValueChanged<CenteredMargins> onMarginsChanged,
});

class CenteredEditorArea extends StatefulWidget {
  const CenteredEditorArea({
    super.key,
    required this.layout,
    required this.child,
  });

  final CenteredEditorLayout layout;
  final Widget child;

  @override
  State<CenteredEditorArea> createState() => _CenteredEditorAreaState();
}

class _CenteredMarginDrag {
  _CenteredMarginDrag({
    required this.left,
    required this.from,
    required this.width,
    required this.margins,
    required this.independent,
  }) : current = from;

  final bool left;
  final double from;
  final double width;
  final CenteredMargins margins;
  final bool independent;
  double current;
}

class _CenteredEditorAreaState extends State<CenteredEditorArea> {
  static const _minimumMargin = 60.0;
  _CenteredMarginDrag? _drag;
  CenteredMargins? _preview;

  EdgeInsets _marginPixels(double width, CenteredMargins margins) {
    final space = math.max(0.0, width - editorGroupMinimumWidth);
    final minimum = math.min(_minimumMargin, space / 2);
    final useWholePixels = margins == defaultCenteredMargins;
    double extent(double ratio) {
      final pixels = width * ratio;
      return math.max(
          minimum, useWholePixels ? pixels.floorToDouble() : pixels);
    }

    final left = extent(margins.left);
    final right = extent(margins.right);
    if (left + right <= space) return EdgeInsets.only(left: left, right: right);

    // Preserve the two preferred proportions when a narrower area has to
    // reduce its margins to keep the editor usable.
    final available = space - 2 * minimum;
    final desired = left + right - 2 * minimum;
    final fittedLeft = minimum + available * (left - minimum) / desired;
    return EdgeInsets.only(left: fittedLeft, right: space - fittedLeft);
  }

  @override
  void didUpdateWidget(covariant CenteredEditorArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.layout.enabled ||
        oldWidget.layout.margins != widget.layout.margins) {
      _drag = null;
      _preview = null;
    }
  }

  void _startDrag(bool left, double width, double position) {
    if (_drag != null) return;
    _drag = _CenteredMarginDrag(
      left: left,
      from: position,
      width: width,
      margins: widget.layout.margins,
      independent: HardwareKeyboard.instance.isAltPressed,
    );
  }

  void _resizeMargin(bool left, double width, double position) {
    var drag = _drag;
    if (drag == null || drag.left != left) return;
    final independent = HardwareKeyboard.instance.isAltPressed;
    if (drag.width != width || drag.independent != independent) {
      // Continue from the last pointer position when Alt changes mid-drag.
      drag = _CenteredMarginDrag(
        left: left,
        from: drag.current,
        width: width,
        margins: _preview ?? widget.layout.margins,
        independent: independent,
      );
      _drag = drag;
    }
    drag.current = position;
    final padding = _marginPixels(width, drag.margins);
    final own = left ? padding.left : padding.right;
    final opposite = left ? padding.right : padding.left;
    final room =
        math.max(0.0, width - padding.horizontal - editorGroupMinimumWidth);
    final minimum =
        math.min(_minimumMargin, (width - editorGroupMinimumWidth) / 2);
    final limit = independent ? room + opposite - minimum : room / 2;
    final delta = (left ? position - drag.from : drag.from - position)
        .clamp(minimum - own, limit)
        .toDouble();
    final nextOwn = own + delta;
    final nextOpposite = independent
        ? opposite - math.max(0.0, delta - room)
        : math.max(minimum, opposite + delta);
    final next = delta == 0
        ? drag.margins
        : (
            left: (left ? nextOwn : nextOpposite) / width,
            right: (left ? nextOpposite : nextOwn) / width,
          );
    if (next == (_preview ?? widget.layout.margins)) return;
    setState(() => _preview = next);
  }

  void _finishDrag(bool left, {required bool save}) {
    if (_drag?.left != left) return;
    _drag = null;
    final preview = _preview;
    if (preview == null) return;
    setState(() => _preview = null);
    if (save && preview != widget.layout.margins) {
      widget.layout.onMarginsChanged(preview);
    }
  }

  Widget _sash({
    required bool left,
    required double width,
    required double offset,
  }) {
    return Positioned(
      left: left ? offset - kDividerThickness / 2 : null,
      right: left ? null : offset - kDividerThickness / 2,
      top: 0,
      bottom: 0,
      width: kDividerThickness,
      child: MouseRegion(
        key: ValueKey(left
            ? 'centered-editor-margin-left'
            : 'centered-editor-margin-right'),
        cursor: SystemMouseCursors.resizeLeftRight,
        child: TextFieldTapRegion(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onHorizontalDragStart: (details) =>
                _startDrag(left, width, details.globalPosition.dx),
            onHorizontalDragUpdate: (details) =>
                _resizeMargin(left, width, details.globalPosition.dx),
            onHorizontalDragEnd: (_) => _finishDrag(left, save: true),
            onHorizontalDragCancel: () => _finishDrag(left, save: false),
            onDoubleTap: () =>
                widget.layout.onMarginsChanged(defaultCenteredMargins),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final canResize = widget.layout.enabled &&
            constraints.hasBoundedWidth &&
            width > editorGroupMinimumWidth;
        final padding = canResize
            ? _marginPixels(width, _preview ?? widget.layout.margins)
            : EdgeInsets.zero;
        if (!canResize) {
          _drag = null;
          _preview = null;
        }
        return Stack(
          fit: StackFit.passthrough,
          children: [
            Padding(padding: padding, child: widget.child),
            if (canResize) ...[
              _sash(left: true, width: width, offset: padding.left),
              _sash(left: false, width: width, offset: padding.right),
            ],
          ],
        );
      },
    );
  }
}

bool hasHorizontalEditorColumns(WbNode node) =>
    node is WbSplit &&
    ((node.axis == Axis.horizontal && node.editorGroupSpan != null) ||
        node.children.any(hasHorizontalEditorColumns));

class WorkbenchGrid extends StatefulWidget {
  const WorkbenchGrid({
    super.key,
    required this.layout,
    required this.builders,
    this.centeredEditorArea,
  });

  final WorkbenchLayout layout;
  final Map<String, WidgetBuilder> builders;

  // Null uses the ordinary grid. An inactive layout keeps the editor
  // wrapper mounted when centering is temporarily suspended.
  final CenteredEditorLayout? centeredEditorArea;

  @override
  State<WorkbenchGrid> createState() => _WorkbenchGridState();
}

class _WorkbenchGridState extends State<WorkbenchGrid> {
  final Map<String, GlobalKey> _regionKeys = {};

  void _syncRegionKeys() {
    final regions =
        widget.layout.root.leaves.map((leaf) => leaf.region).toSet();
    _regionKeys.removeWhere((region, _) => !regions.contains(region));
    for (final region in regions) {
      _regionKeys.putIfAbsent(
        region,
        () => GlobalKey(debugLabel: 'wb-region-$region'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // The projection is rebuilt with the layout notification so the transient
    // tree always reflects saved Panel/Activity Bar/Side Bar state.
    return ListenableBuilder(
      listenable: widget.layout,
      builder: (context, _) {
        _syncRegionKeys();
        final projection = projectPanelAlignment(widget.layout);
        final node = projection?.tree ?? widget.layout.root;
        final panelBuilder = widget.builders['panel'];
        final panelKey = _regionKeys['panel'];
        if (widget.layout.panelMaximized &&
            !widget.layout.isCollapsed('panel') &&
            widget.layout.canMaximizePanel &&
            panelBuilder != null &&
            panelKey != null) {
          return Stack(
            fit: StackFit.expand,
            children: [
              Offstage(
                offstage: true,
                child: _NodeView(
                  node: node,
                  layout: widget.layout,
                  builders: widget.builders,
                  regionKeys: _regionKeys,
                  projection: projection,
                  omitRegion: 'panel',
                  centeredEditorArea: widget.centeredEditorArea,
                ),
              ),
              Positioned.fill(
                child: KeyedSubtree(
                  key: panelKey,
                  child: KeyedSubtree(
                    key: const ValueKey('wb-region-panel'),
                    child: panelBuilder(context),
                  ),
                ),
              ),
            ],
          );
        }
        return _NodeView(
          node: node,
          layout: widget.layout,
          builders: widget.builders,
          regionKeys: _regionKeys,
          projection: projection,
          centeredEditorArea: widget.centeredEditorArea,
        );
      },
    );
  }
}

/// 分割条两侧节点的稳定标识（用于测试定位与 key）。
String _nodeKey(WbNode node) {
  final leaf = node;
  if (leaf is WbLeaf) return leaf.region;
  final split = leaf as WbSplit;
  return split.name ?? 'group${identityHashCode(node) & 0xFFFF}';
}

class _NodeView extends StatelessWidget {
  const _NodeView({
    required this.node,
    required this.layout,
    required this.builders,
    required this.regionKeys,
    required this.projection,
    this.omitRegion,
    this.centeredEditorArea,
  });

  final WbNode node;
  final WorkbenchLayout layout;
  final Map<String, WidgetBuilder> builders;
  final Map<String, GlobalKey> regionKeys;
  final PanelAlignmentProjection? projection;
  final String? omitRegion;
  final CenteredEditorLayout? centeredEditorArea;

  bool get _isEditorArea {
    var hasEditor = false;
    for (final leaf in node.leaves) {
      if (leaf.collapsed || leaf.region == omitRegion) continue;
      final region = leaf.region;
      if (region != 'editor' && !region.startsWith('editor-')) return false;
      hasEditor = true;
    }
    return hasEditor;
  }

  @override
  Widget build(BuildContext context) {
    final centered = centeredEditorArea;
    if (centered == null || !_isEditorArea) {
      return _buildContents(context, centered);
    }
    return CenteredEditorArea(
      layout: centered,
      child: _buildContents(context, null),
    );
  }

  Widget _buildContents(
      BuildContext context, CenteredEditorLayout? nestedCentering) {
    final leaf = node;
    if (leaf is WbLeaf) {
      if (leaf.region == omitRegion) return const SizedBox.shrink();
      if (leaf.collapsed) return const SizedBox.shrink();
      final build = builders[leaf.region];
      return KeyedSubtree(
        key: regionKeys[leaf.region],
        child: KeyedSubtree(
          key: ValueKey('wb-region-${leaf.region}'),
          child: build?.call(context) ?? const SizedBox.shrink(),
        ),
      );
    }

    final split = leaf as WbSplit;
    final axis = split.axis;
    final maximized = layout.maximizedEditorRegion;
    final span = maximized == null || maximized == omitRegion
        ? null
        : split.editorGroupSpan;
    final expandedLeaf = span == null || maximized == null
        ? null
        : split.children
            .getRange(span.first, span.last + 1)
            .map((child) => child.leafOf(maximized))
            .nonNulls
            .firstOrNull;
    final occupied = expandedLeaf == null ? null : span;

    // 先确定哪些位置有可拖拽分割条，分割条占位要从弹性池里扣除
    final dividerSlots = <int>[];
    for (var i = 1; i < split.children.length; i++) {
      if (isFlexibleNode(split.children[i - 1]) &&
          isFlexibleNode(split.children[i])) {
        dividerSlots.add(i);
      }
    }

    return LayoutBuilder(builder: (context, constraints) {
      final total = axis == Axis.horizontal
          ? constraints.maxWidth
          : constraints.maxHeight;
      final nonNegativeTotal = math.max(0.0, total).toDouble();
      final dividerThickness = dividerSlots.isEmpty
          ? 0.0
          : math
              .min(kDividerThickness, nonNegativeTotal / dividerSlots.length)
              .toDouble();
      final inner = math
          .max(
            0.0,
            nonNegativeTotal - dividerSlots.length * dividerThickness,
          )
          .toDouble();
      final extents = split.extentsFor(inner);

      final items = <Widget>[];
      for (var i = 0; i < split.children.length; i++) {
        if (dividerSlots.contains(i)) {
          if (occupied != null && i > occupied.first && i <= occupied.last) {
            items.add(SizedBox(
              width: axis == Axis.horizontal ? dividerThickness : null,
              height: axis == Axis.vertical ? dividerThickness : null,
            ));
          } else {
            items.add(_Divider(
            key: ValueKey(
                'wb-div-${_nodeKey(split.children[i - 1])}-${_nodeKey(split.children[i])}'),
            axis: axis,
            index: i - 1,
            split: split,
            thickness: dividerThickness,
            innerExtent: inner,
            layout: layout,
              projection: projection,
            ));
          }
        }
        final child = split.children[i];
        final ext = extents[i];
        final hidden =
            occupied != null && i >= occupied.first && i <= occupied.last;
        final view = _NodeView(
          node: child,
          layout: layout,
          builders: builders,
          regionKeys: regionKeys,
          projection: projection,
          omitRegion: hidden ? maximized : omitRegion,
          centeredEditorArea: hidden ? null : nestedCentering,
        );
        items.add(
          SizedBox(
            width: axis == Axis.horizontal ? ext : double.infinity,
            height: axis == Axis.vertical ? ext : double.infinity,
            child: hidden
                ? Offstage(
                    child: ExcludeFocus(
                      child: TickerMode(enabled: false, child: view),
                    ),
                  )
                : view,
          ),
        );
      }

      final grid = Flex(
        direction: axis,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: items,
      );
      if (expandedLeaf == null || occupied == null) return grid;

      // Retain each hidden group's mounted view and its saved geometry. The
      // shared editor area includes the dividers between those groups.
      final before = extents.take(occupied.first).fold(0.0, (a, b) => a + b) +
          dividerSlots.where((slot) => slot <= occupied.first).length *
              dividerThickness;
      final after = extents.skip(occupied.last + 1).fold(0.0, (a, b) => a + b) +
          dividerSlots.where((slot) => slot > occupied.last).length *
              dividerThickness;
      return Stack(
        fit: StackFit.expand,
        children: [
          grid,
          Positioned.fill(
            left: axis == Axis.horizontal ? before : 0,
            right: axis == Axis.horizontal ? after : 0,
            top: axis == Axis.vertical ? before : 0,
            bottom: axis == Axis.vertical ? after : 0,
            child: _NodeView(
              node: expandedLeaf,
              layout: layout,
              builders: builders,
              regionKeys: regionKeys,
              projection: projection,
              centeredEditorArea: nestedCentering,
            ),
          ),
        ],
      );
    });
  }
}

class _Divider extends StatefulWidget {
  const _Divider({
    super.key,
    required this.axis,
    required this.index,
    required this.split,
    required this.thickness,
    required this.innerExtent,
    required this.layout,
    required this.projection,
  });

  final Axis axis;
  final int index;
  final WbSplit split;
  final double thickness;
  final double innerExtent;
  final WorkbenchLayout layout;
  final PanelAlignmentProjection? projection;

  @override
  State<_Divider> createState() => _DividerState();
}

class _DividerState extends State<_Divider> {
  int? _activePointer;
  Offset? _pointerDownPosition;
  bool _pointerMoved = false;
  Duration? _lastTapTime;
  Offset? _lastTapPosition;
  PointerDeviceKind? _lastTapKind;

  void _clearTapState() {
    _lastTapTime = null;
    _lastTapPosition = null;
    _lastTapKind = null;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    _pointerDownPosition = event.position;
    _pointerMoved = false;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer || _pointerDownPosition == null) {
      return;
    }
    if ((event.position - _pointerDownPosition!).distance > kTouchSlop) {
      _pointerMoved = true;
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _pointerDownPosition = null;
    _pointerMoved = false;
    _clearTapState();
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer || _pointerDownPosition == null) {
      return;
    }
    final isTap = !_pointerMoved &&
        (event.position - _pointerDownPosition!).distance <= kTouchSlop;
    _activePointer = null;
    _pointerDownPosition = null;
    _pointerMoved = false;
    if (!isTap) {
      _clearTapState();
      return;
    }

    final previousTime = _lastTapTime;
    final previousPosition = _lastTapPosition;
    final isSecondTap = previousTime != null &&
        previousPosition != null &&
        event.timeStamp >= previousTime &&
        event.timeStamp - previousTime <= kDoubleTapTimeout &&
        (event.position - previousPosition).distance <= kDoubleTapSlop &&
        event.kind == _lastTapKind;
    if (isSecondTap) {
      _clearTapState();
      _reset();
    } else {
      _lastTapTime = event.timeStamp;
      _lastTapPosition = event.position;
      _lastTapKind = event.kind;
    }
  }

  void _drag(double deltaPx) {
    widget.layout.dragDivider(
      widget.split,
      widget.index,
      deltaPx,
      widget.innerExtent,
    );
    widget.projection?.syncAfterDividerDrag(widget.split);
  }

  void _reset() {
    if (!widget.layout.resetDivider(
      widget.split,
      widget.index,
      widget.innerExtent,
    )) {
      return;
    }
    widget.projection?.syncAfterDividerDrag(widget.split);
  }

  @override
  void didUpdateWidget(covariant _Divider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.split, widget.split) ||
        oldWidget.index != widget.index) {
      _clearTapState();
    }
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.axis == Axis.horizontal
        ? const SizedBox(width: 1, child: ColoredBox(color: _kDividerColor))
        : const SizedBox(height: 1, child: ColoredBox(color: _kDividerColor));
    return SizedBox(
      width:
          widget.axis == Axis.horizontal ? widget.thickness : double.infinity,
      height: widget.axis == Axis.vertical ? widget.thickness : double.infinity,
      child: MouseRegion(
        cursor: widget.axis == Axis.horizontal
            ? SystemMouseCursors.resizeLeftRight
            : SystemMouseCursors.resizeUpDown,
        child: Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: widget.axis == Axis.horizontal
                ? (d) => _drag(d.primaryDelta ?? 0)
                : null,
            onVerticalDragUpdate: widget.axis == Axis.vertical
                // 垂直下拖（+dy）→ 下格 b 增大 → 模型侧 a += delta 取负号
                ? (d) => _drag(-(d.primaryDelta ?? 0))
                : null,
            child: Center(child: line),
          ),
        ),
      ),
    );
  }
}
