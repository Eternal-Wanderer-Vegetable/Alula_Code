/// 工作台布局树（docs/09 W1）。
///
/// W1 只做「分割树」不做自由网格：每个 split 节点沿单一轴排布若干子节点；
/// 叶子是一个停靠区域（region id）。区域尺寸有三种形态：
/// - 固定像素（`fixedExtent`，如活动栏/状态栏）：不参与拖拽与权重分配；
/// - 弹性权重（`weight`）：同轴兄弟按权重瓜分剩余空间；
/// - 折叠（`collapsed`）：渲染为 0 尺寸，记住折叠前权重以便恢复。
///
/// 本文件全部是纯模型与纯函数（可单测），不含 Flutter widget；
/// 渲染见 layout_grid.dart，状态与持久化见 layout_controller.dart。
library;

import 'package:flutter/painting.dart' show Axis;

/// 布局树节点。
sealed class WbNode {
  const WbNode();

  Map<String, Object?> toJson();

  static WbNode fromJson(Map<String, Object?> json) {
    switch (json['t']) {
      case 'split':
        return WbSplit.fromJson(json);
      case 'leaf':
        return WbLeaf.fromJson(json);
      default:
        throw const FormatException('未知节点类型');
    }
  }

  /// 深度优先收集所有叶子。
  Iterable<WbLeaf> get leaves sync* {
    final self = this;
    if (self is WbLeaf) {
      yield self;
    } else if (self is WbSplit) {
      for (final c in self.children) {
        yield* c.leaves;
      }
    }
  }

  /// 按区域 id 查找叶子。
  WbLeaf? leafOf(String region) {
    for (final l in leaves) {
      if (l.region == region) return l;
    }
    return null;
  }
}

/// 分支节点：沿 [axis] 排布的若干子节点。
class WbSplit extends WbNode {
  WbSplit({required this.axis, required List<WbNode> children})
      : assert(children.length >= 2, 'split 至少两个子节点'),
        children = List.of(children);

  final Axis axis;
  final List<WbNode> children;

  @override
  Map<String, Object?> toJson() => {
        't': 'split',
        'axis': axis == Axis.horizontal ? 'h' : 'v',
        'children': children.map((c) => c.toJson()).toList(),
      };

  factory WbSplit.fromJson(Map<String, Object?> json) {
    final axis = json['axis'] == 'v' ? Axis.vertical : Axis.horizontal;
    final raw = json['children'];
    if (raw is! List || raw.length < 2) {
      throw const FormatException('split 子节点不足');
    }
    return WbSplit(
      axis: axis,
      children: raw
          .map((e) =>
              WbNode.fromJson((e as Map).cast<String, Object?>()))
          .toList(),
    );
  }
}

/// 叶子节点：一个停靠区域。
class WbLeaf extends WbNode {
  WbLeaf({
    required this.region,
    this.fixedExtent,
    this.weight = 1,
    this.minExtent = 0,
    this.collapsed = false,
    this.lastWeight,
  })  : assert(weight >= 0),
        assert(fixedExtent == null || fixedExtent > 0),
        assert(!collapsed || lastWeight != null || fixedExtent == null,
            '可折叠叶子须记住折叠前权重');

  /// 区域 id（workbench 约定：activity / sidebar / editor / panel …）。
  final String region;

  /// 固定像素宽度（主轴方向）。非 null 时该叶子不参与拖拽与权重分配。
  final double? fixedExtent;

  /// 弹性权重（同轴兄弟间瓜分剩余空间的比例份额）。
  double weight;

  /// 主轴最小像素尺寸（拖拽钳制下限）。
  double minExtent;

  /// 是否折叠（渲染为 0 尺寸）。
  bool collapsed;

  /// 折叠前的权重，恢复时还原。
  double? lastWeight;

  bool get isFixed => fixedExtent != null;

  @override
  Map<String, Object?> toJson() => {
        't': 'leaf',
        'region': region,
        if (fixedExtent != null) 'fixed': fixedExtent,
        'weight': weight,
        if (minExtent != 0) 'min': minExtent,
        if (collapsed) 'collapsed': true,
        if (lastWeight != null) 'last': lastWeight,
      };

  factory WbLeaf.fromJson(Map<String, Object?> json) {
    final region = json['region'];
    if (region is! String || region.isEmpty) {
      throw const FormatException('leaf 缺少 region');
    }
    return WbLeaf(
      region: region,
      fixedExtent: _toDouble(json['fixed']),
      weight: _toDouble(json['weight']) ?? 1,
      minExtent: _toDouble(json['min']) ?? 0,
      collapsed: json['collapsed'] == true,
      lastWeight: _toDouble(json['last']),
    );
  }
}

double? _toDouble(Object? v) => v is num ? v.toDouble() : null;

/// W1 默认布局（对标 VS Code 五大区）：
///
/// ```
/// vertical: [
///   horizontal: [ activity(48px 固定), sidebar(弹性, 可折叠), editor(弹性) ],
///   panel(弹性, 默认折叠, 可折叠)
/// ]
/// ```
/// 标题栏与状态栏在网格之外（不可拖拽调尺寸）。
WbSplit defaultLayout() => WbSplit(
      axis: Axis.vertical,
      children: [
        WbSplit(
          axis: Axis.horizontal,
          children: [
            WbLeaf(region: 'activity', fixedExtent: 44),
            WbLeaf(
              region: 'sidebar',
              weight: 0.24,
              minExtent: 170,
              collapsed: true,
              lastWeight: 0.24,
            ),
            WbLeaf(region: 'editor', weight: 0.76, minExtent: 320),
          ],
        ),
        WbLeaf(
          region: 'panel',
          weight: 0.3,
          minExtent: 120,
          collapsed: true,
          lastWeight: 0.3,
        ),
      ],
    );

/// 拖拽分割条：把 [index] 与 [index+1] 两个相邻叶子之间的分界移动 [deltaPx]
/// 像素（主轴方向），其余兄弟像素尺寸保持不变。
///
/// [extents] 为全部子节点当前主轴像素（与 split.children 一一对应），
/// [minExtents] 为各叶子像素下限（固定叶子传自身 fixedExtent 即可，函数不触碰）。
/// 返回调整后的全部像素；非法输入（索引越界/长度不符）原样返回。
List<double> moveDivider({
  required List<double> extents,
  required List<double> minExtents,
  required int index,
  required double deltaPx,
}) {
  if (index < 0 || index + 1 >= extents.length) return extents;
  if (extents.length != minExtents.length) return extents;
  final out = List<double>.of(extents);
  final a = out[index];
  final b = out[index + 1];
  final minA = minExtents[index];
  final minB = minExtents[index + 1];
  // 无合法区间（两叶最小尺寸之和超过两叶总和）：不动
  if (minA > a + b - minB) return out;
  // 钳制：a 不低于 minA，同时 b 不得被压破 minB
  final newA = (a + deltaPx).clamp(minA, a + b - minB);
  out[index] = newA;
  out[index + 1] = a + b - newA;
  return out;
}

/// 把主轴像素列表换算回弹性权重（固定叶子按 0 处理，不参与权重）。
///
/// [fixed] 标记对应位置是否固定叶子。总和归一后写回各叶子。
List<double> extentsToWeights(List<double> extents, List<bool> fixed) {
  var flexTotal = 0.0;
  for (var i = 0; i < extents.length; i++) {
    if (!fixed[i]) flexTotal += extents[i];
  }
  if (flexTotal <= 0) return List.filled(extents.length, 0.0);
  return List.generate(extents.length, (i) {
    if (fixed[i]) return 0.0;
    return extents[i] / flexTotal;
  });
}

/// 按权重把 [totalExtent] 像素分配给各子节点（固定叶子取 fixedExtent，
/// 折叠叶子取 0）。要求 [leaves] 与返回一一对应。
List<double> weightsToExtents(List<WbLeaf> leaves, double totalExtent) {
  var flexWeight = 0.0;
  var fixedUsed = 0.0;
  for (final l in leaves) {
    if (l.collapsed) continue;
    if (l.isFixed) {
      fixedUsed += l.fixedExtent!;
    } else {
      flexWeight += l.weight;
    }
  }
  final flexPx = (totalExtent - fixedUsed).clamp(0.0, totalExtent);
  double? unit;
  if (flexWeight > 0 && flexPx > 0) unit = flexPx / flexWeight;
  return leaves.map((l) {
    if (l.collapsed) return 0.0;
    if (l.isFixed) return l.fixedExtent!;
    return (l.weight * (unit ?? 0));
  }).toList();
}
