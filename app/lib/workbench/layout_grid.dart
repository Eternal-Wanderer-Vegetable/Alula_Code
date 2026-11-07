/// 分割树渲染器（docs/09 W1）。
///
/// grid 不知道区域内容：页面通过 `builders`（region → WidgetBuilder）注入，
/// 便于对布局行为单独做 widget 测试。
///
/// 分割条规则：只渲染在两个相邻「弹性」节点之间（固定叶子如活动栏、
/// 折叠叶子边缘没有分割条）；拖拽回调走 WorkbenchLayout.dragDivider。
library;

import 'dart:math' as math;

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

class _Divider extends StatelessWidget {
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

  void _drag(double deltaPx) {
    layout.dragDivider(split, index, deltaPx, innerExtent);
    projection?.syncAfterDividerDrag(split);
  }

  @override
  Widget build(BuildContext context) {
    final line = axis == Axis.horizontal
        ? const SizedBox(width: 1, child: ColoredBox(color: _kDividerColor))
        : const SizedBox(height: 1, child: ColoredBox(color: _kDividerColor));
    return SizedBox(
      width: axis == Axis.horizontal ? thickness : double.infinity,
      height: axis == Axis.vertical ? thickness : double.infinity,
      child: MouseRegion(
        cursor: axis == Axis.horizontal
            ? SystemMouseCursors.resizeLeftRight
            : SystemMouseCursors.resizeUpDown,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: axis == Axis.horizontal
              ? (d) => _drag(d.primaryDelta ?? 0)
              : null,
          onVerticalDragUpdate: axis == Axis.vertical
              // 垂直下拖（+dy）→ 下格 b 增大 → 模型侧 a += delta 取负号
              ? (d) => _drag(-(d.primaryDelta ?? 0))
              : null,
          child: Center(child: line),
        ),
      ),
    );
  }
}
