/// 分割树渲染器（docs/09 W1）。
///
/// grid 不知道区域内容：页面通过 `builders`（region → WidgetBuilder）注入，
/// 便于对布局行为单独做 widget 测试。
///
/// 分割条规则：只渲染在两个相邻「弹性」节点之间（固定叶子如活动栏、
/// 折叠叶子边缘没有分割条）；拖拽回调走 WorkbenchLayout.dragDivider。
library;

import 'package:flutter/material.dart';

import 'layout_controller.dart';
import 'layout_model.dart';

/// 分割条主轴占位（含命中区）；视觉线居中 1px。
const double kDividerThickness = 4.0;

const Color _kDividerColor = Color(0xFF2A2E37);

class WorkbenchGrid extends StatelessWidget {
  const WorkbenchGrid({
    super.key,
    required this.layout,
    required this.builders,
  });

  final WorkbenchLayout layout;
  final Map<String, WidgetBuilder> builders;

  @override
  Widget build(BuildContext context) {
    // grid 自行监听布局变更：任何拖拽/折叠后整体重排
    return ListenableBuilder(
      listenable: layout,
      builder: (context, _) => _NodeView(
        node: layout.root,
        layout: layout,
        builders: builders,
      ),
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
  });

  final WbNode node;
  final WorkbenchLayout layout;
  final Map<String, WidgetBuilder> builders;

  @override
  Widget build(BuildContext context) {
    final leaf = node;
    if (leaf is WbLeaf) {
      if (leaf.collapsed) return const SizedBox.shrink();
      final build = builders[leaf.region];
      return KeyedSubtree(
        key: ValueKey('wb-region-${leaf.region}'),
        child: build?.call(context) ?? const SizedBox.shrink(),
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
      final inner = total - dividerSlots.length * kDividerThickness;
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
            innerExtent: inner,
            layout: layout,
          ));
        }
        final child = split.children[i];
        final ext = extents[i];
        items.add(
          SizedBox(
            width: axis == Axis.horizontal ? ext : double.infinity,
            height: axis == Axis.vertical ? ext : double.infinity,
            child: _NodeView(node: child, layout: layout, builders: builders),
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
    required this.innerExtent,
    required this.layout,
  });

  final Axis axis;
  final int index;
  final WbSplit split;
  final double innerExtent;
  final WorkbenchLayout layout;

  @override
  Widget build(BuildContext context) {
    final line = axis == Axis.horizontal
        ? const SizedBox(width: 1, child: ColoredBox(color: _kDividerColor))
        : const SizedBox(height: 1, child: ColoredBox(color: _kDividerColor));
    return SizedBox(
      width: axis == Axis.horizontal ? kDividerThickness : double.infinity,
      height: axis == Axis.vertical ? kDividerThickness : double.infinity,
      child: MouseRegion(
        cursor: axis == Axis.horizontal
            ? SystemMouseCursors.resizeLeftRight
            : SystemMouseCursors.resizeUpDown,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: axis == Axis.horizontal
              ? (d) => layout.dragDivider(
                  split, index, d.primaryDelta ?? 0, innerExtent)
              : null,
          onVerticalDragUpdate: axis == Axis.vertical
              // 垂直下拖（+dy）→ 下格 b 增大 → 模型侧 a += delta 取负号
              ? (d) => layout.dragDivider(
                  split, index, -(d.primaryDelta ?? 0), innerExtent)
              : null,
          child: Center(child: line),
        ),
      ),
    );
  }
}
