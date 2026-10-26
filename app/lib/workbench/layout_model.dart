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

  /// 弹性权重（同轴弹性兄弟间瓜分剩余空间的比例份额）。
  /// 叶子与嵌套 split 都有：split 作为弹性子节点参与父级分配。
  abstract double weight;

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
  WbSplit({
    required this.axis,
    required List<WbNode> children,
    this.weight = 1,
    this.name,
  })  : assert(children.length >= 2, 'split 至少两个子节点'),
        children = List.of(children);

  final Axis axis;
  final List<WbNode> children;

  /// 稳定标识（可选）：调试与测试定位用（分割条 key = wb-div-<左>-<右>）。
  final String? name;

  @override
  double weight;

  @override
  Map<String, Object?> toJson() => {
        't': 'split',
        'axis': axis == Axis.horizontal ? 'h' : 'v',
        if (weight != 1) 'weight': weight,
        if (name != null) 'name': name,
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
      weight: json['weight'] is num ? (json['weight'] as num).toDouble() : 1,
      name: json['name'] is String ? json['name'] as String : null,
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
  @override
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
          weight: 0.7,
          name: 'main-row',
          children: [
            WbLeaf(region: 'activity', fixedExtent: 44),
            WbLeaf(region: 'sidebar', weight: 0.24, minExtent: 170),
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

/// 节点在主轴上是否为弹性（参与权重分配）：
/// 固定/折叠叶子否；嵌套 split 总是弹性（W1 无折叠分支）。
bool isFlexibleNode(WbNode node) {
  final self = node;
  if (self is WbLeaf) return !self.isFixed && !self.collapsed;
  return true;
}

/// 节点主轴最小像素：叶子取 minExtent（折叠为 0，固定取固定值）；
/// split 取各子节点最小值之和。
double nodeMinExtent(WbNode node) {
  final self = node;
  if (self is WbLeaf) {
    if (self.isFixed) return self.fixedExtent!;
    return self.collapsed ? 0 : self.minExtent;
  }
  final split = self as WbSplit; // sealed 层级：非叶必为 split
  var sum = 0.0;
  for (final c in split.children) {
    sum += nodeMinExtent(c);
  }
  return sum;
}

extension WbSplitLayout on WbSplit {
  /// 按当前模型把 [totalExtent] 主轴像素分配给各子节点。
  /// 固定叶子取 fixedExtent，折叠叶子取 0，弹性节点按权重瓜分剩余。
  List<double> extentsFor(double totalExtent) {
    var flexWeight = 0.0;
    var fixedUsed = 0.0;
    for (final c in children) {
      final leaf = c;
      if (leaf is WbLeaf && leaf.collapsed) continue;
      if (leaf is WbLeaf && leaf.isFixed) {
        fixedUsed += leaf.fixedExtent!;
      } else {
        flexWeight += leaf.weight;
      }
    }
    final flexPx = (totalExtent - fixedUsed).clamp(0.0, totalExtent);
    final unit = flexWeight > 0 && flexPx > 0 ? flexPx / flexWeight : 0.0;
    return children.map((c) {
      final leaf = c;
      if (leaf is WbLeaf && leaf.collapsed) return 0.0;
      if (leaf is WbLeaf && leaf.isFixed) return leaf.fixedExtent!;
      return leaf.weight * unit;
    }).toList();
  }

  /// 该 split 的各子节点最小主轴像素。
  List<double> minsFor() =>
      children.map(nodeMinExtent).toList(growable: false);

  /// 拖拽第 [index] 个分割条移动 [deltaPx] 像素（该 split 主轴总长 [totalExtent]）。
  /// 就地更新弹性子节点的权重，其余兄弟像素保持不变。
  void applyDrag(int index, double deltaPx, double totalExtent) {
    if (totalExtent <= 0) return;
    final extents = extentsFor(totalExtent);
    final moved =
        moveDivider(extents: extents, minExtents: minsFor(), index: index, deltaPx: deltaPx);
    if (identical(moved, extents)) return;
    final flexTotal =
        moved.fold(0.0, (s, e) => s + e); // 含固定像素；固定叶子不写回权重
    if (flexTotal <= 0) return;
    for (var i = 0; i < children.length; i++) {
      final c = children[i];
      final leaf = c;
      if (leaf is WbLeaf && (leaf.isFixed || leaf.collapsed)) continue;
      c.weight = moved[i] / flexTotal;
    }
  }
}

/// 树结构变更原语（W2-2 编辑器组拆分）：叶子分裂与摘除。
extension WbSplitTreeOps on WbSplit {
  /// 定位 region 叶子的直接父 split（含 this 自身）。
  WbSplit? parentSplitOf(String region) {
    WbSplit? walk(WbSplit node) {
      for (final c in node.children) {
        final leaf = c;
        if (leaf is WbLeaf && leaf.region == region) return node;
        final split = c;
        if (split is WbSplit) {
          final found = walk(split);
          if (found != null) return found;
        }
      }
      return null;
    }

    return walk(this);
  }

  /// 把 [region] 叶子替换为 [axis] 方向的嵌套分割：原叶子 + 新叶子（权重
  /// [newWeight]）。返回新叶子；region 不存在 / newRegion 已占用时返回 null。
  WbLeaf? splitLeaf(
    String region,
    String newRegion,
    Axis axis, {
    double newWeight = 0.5,
    String? splitName,
  }) {
    if (region == newRegion) return null;
    if (leafOf(newRegion) != null || leafOf(region) == null) return null;
    final parent = parentSplitOf(region);
    if (parent == null) return null;
    final index =
        parent.children.indexWhere((c) => c is WbLeaf && c.region == region);
    if (index < 0) return null;
    final original = parent.children[index] as WbLeaf;
    final outerWeight = original.weight;
    final fresh = WbLeaf(
      region: newRegion,
      weight: newWeight,
      minExtent: original.minExtent,
    );
    original.weight = 1 - newWeight;
    parent.children[index] = WbSplit(
      axis: axis,
      weight: outerWeight,
      name: splitName,
      children: [original, fresh],
    );
    return fresh;
  }

  /// 摘除 [region] 叶子；若父 split 因此只剩一个子节点，则用该子节点把父
  /// split 从树中折叠掉（权重沿用父 split 的）。
  /// 根的直接子节点不在可摘除范围（摘除会使根失效），返回 false。
  bool removeLeaf(String region) {
    if (children.any((c) => c is WbLeaf && c.region == region)) {
      return false; // 根的直接子节点不可摘除
    }
    return _removeLeaf(this, region);
  }

  bool _removeLeaf(WbSplit node, String region) {
    for (var i = 0; i < node.children.length; i++) {
      final c = node.children[i];
      final split = c;
      if (split is! WbSplit) continue;
      final idx =
          split.children.indexWhere((ch) => ch is WbLeaf && ch.region == region);
      if (idx >= 0) {
        split.children.removeAt(idx);
        _collapseIfSingleton(node, i, split);
        return true;
      }
      if (_removeLeaf(split, region)) {
        _collapseIfSingleton(node, i, split);
        return true;
      }
    }
    return false;
  }

  /// split 只剩一个子节点时折叠：唯一子顶替其位置并沿用其权重。
  void _collapseIfSingleton(WbSplit node, int i, WbSplit split) {
    if (split.children.length == 1) {
      final remaining = split.children[0];
      remaining.weight = split.weight;
      node.children[i] = remaining;
    }
  }
}
