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
    show PointerDeviceKind, kDoubleTapSlop, kDoubleTapTimeout, kTouchSlop;
import 'package:flutter/material.dart';

import 'layout_controller.dart';
import 'layout_model.dart';
import 'panel_alignment.dart';
import 'panel_maximize.dart';

/// 分割条主轴占位（含命中区）；视觉线居中 1px。
const double kDividerThickness = workbenchDividerThickness;

const Color _kDividerColor = Color(0xFF2A2E37);

class WorkbenchGrid extends StatefulWidget {
  const WorkbenchGrid({
    super.key,
    required this.layout,
    required this.builders,
  });

  final WorkbenchLayout layout;
  final Map<String, WidgetBuilder> builders;

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
  });

  final WbNode node;
  final WorkbenchLayout layout;
  final Map<String, WidgetBuilder> builders;
  final Map<String, GlobalKey> regionKeys;
  final PanelAlignmentProjection? projection;
  final String? omitRegion;

  @override
  Widget build(BuildContext context) {
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
        final child = split.children[i];
        final ext = extents[i];
        items.add(
          SizedBox(
            width: axis == Axis.horizontal ? ext : double.infinity,
            height: axis == Axis.vertical ? ext : double.infinity,
            child: _NodeView(
              node: child,
              layout: layout,
              builders: builders,
              regionKeys: regionKeys,
              projection: projection,
              omitRegion: omitRegion,
            ),
          ),
        );
      }

      return Flex(
        direction: axis,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: items,
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
