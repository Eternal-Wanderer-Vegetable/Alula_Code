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

import 'dart:math' as math;

import 'package:flutter/painting.dart' show Axis;

/// Divider space shared by split layout calculation and grid rendering.
const double workbenchDividerThickness = 4.0;

/// Code-OSS Panel view minimums in logical pixels.
const double panelMinimumWidth = 300.0;
const double panelMinimumHeight = 77.0;

const double _legacyDefaultPanelMinimumExtent = 120.0;

/// Primary Activity Bar placement, persisted with the layout tree.
enum ActivityBarLocation { side, top, bottom, hidden }

/// Primary Side Bar placement, persisted with the root layout node.
enum SideBarPosition {
  left,
  right;

  static SideBarPosition? fromJson(Object? raw) => switch (raw) {
        'left' => SideBarPosition.left,
        'right' => SideBarPosition.right,
        _ => null,
      };
}

/// Horizontal alignment for a top/bottom Panel. Missing legacy JSON defaults
/// to Center, matching the fixed Code-OSS workbench default.
enum PanelAlignment {
  left,
  right,
  center,
  justify;

  static PanelAlignment? fromJson(Object? raw) => switch (raw) {
        'left' => PanelAlignment.left,
        'right' => PanelAlignment.right,
        'center' => PanelAlignment.center,
        'justify' => PanelAlignment.justify,
        _ => null,
      };
}

/// Activity Bar density. The horizontal Activity Bar keeps its legacy 44 px
/// height; these dimensions apply when it is placed on the side.
enum ActivityBarSize {
  defaultSize('default', 48, 48, 24),
  compact('compact', 36, 28, 16);

  const ActivityBarSize(
    this.jsonValue,
    this.sideExtent,
    this.itemExtent,
    this.iconSize,
  );

  final String jsonValue;
  final double sideExtent;
  final double itemExtent;
  final double iconSize;

  static ActivityBarSize? fromJson(Object? raw) => switch (raw) {
        'default' => ActivityBarSize.defaultSize,
        'compact' => ActivityBarSize.compact,
        _ => null,
      };
}

/// Stable IDs for the built-in Activity Bar view actions.
const activityBarViewOrder = ['explorer', 'search', 'outline', 'git'];

/// Root layout metadata values for built-in view locations.
const primarySidebarViewLocation = 'primary';
const secondarySidebarViewLocation = 'secondary';

/// Normalize built-in view location metadata. Layouts predating view movement
/// omit this field and are handled as all views belonging to the Primary Side
/// Bar by [WbSplit].
Map<String, String> normalizeSidebarViewLocations(Object? raw) {
  final locations = <String, String>{};
  if (raw is Map) {
    for (final entry in raw.entries) {
      final id = entry.key;
      final location = entry.value;
      if (id is String &&
          activityBarViewOrder.contains(id) &&
          (location == primarySidebarViewLocation ||
              location == secondarySidebarViewLocation)) {
        locations[id] = location as String;
      }
    }
  }
  for (final id in activityBarViewOrder) {
    locations.putIfAbsent(id, () => primarySidebarViewLocation);
  }
  return locations;
}

/// Canonicalize persisted or caller-supplied Activity Bar order metadata.
/// Unknown IDs and duplicates are discarded; missing built-in views are
/// appended in their default order.
List<String> normalizeActivityBarViewOrder(Object? raw) {
  final order = <String>[];
  if (raw is List) {
    for (final item in raw) {
      if (item is String &&
          activityBarViewOrder.contains(item) &&
          !order.contains(item)) {
        order.add(item);
      }
    }
  }
  for (final id in activityBarViewOrder) {
    if (!order.contains(id)) order.add(id);
  }
  return order;
}

/// Canonicalize persisted Activity Bar pin metadata. Missing, empty, or wholly
/// invalid values fall back to the built-in set so the bar always has an
/// available view. Returned IDs follow the current view order.
List<String> normalizeActivityBarPinnedViews(
  Object? raw, {
  Object? order,
}) {
  final orderedViews = normalizeActivityBarViewOrder(order);
  if (raw is! List) return orderedViews;

  final requested = <String>{
    for (final item in raw)
      if (item is String && activityBarViewOrder.contains(item)) item,
  };
  if (requested.isEmpty) return orderedViews;
  return orderedViews.where(requested.contains).toList();
}

/// Canonicalize Activity Bar view IDs whose badges are hidden. Unlike pins,
/// an empty disabled set is valid and means that badges are enabled everywhere.
List<String> normalizeActivityBarBadgesDisabled(Object? raw, {Object? order}) {
  final orderedViews = normalizeActivityBarViewOrder(order);
  if (raw is! List) return const [];

  final requested = <String>{
    for (final item in raw)
      if (item is String && activityBarViewOrder.contains(item)) item,
  };
  return orderedViews.where(requested.contains).toList();
}

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
    this.activityBarLocation,
    this.sideBarPosition,
    this.panelAlignment,
    this.activityBarSize,
    this.activityBarAccountsVisible,
    List<String>? activityBarOrder,
    List<String>? activityBarPinned,
    List<String>? activityBarBadgesDisabled,
    Map<String, String>? sidebarViewLocations,
    this.primarySidebarView,
    this.secondarySidebarView,
  })  : assert(children.length >= 2, 'split 至少两个子节点'),
        children = List.of(children),
        activityBarOrder = activityBarOrder == null
            ? null
            : normalizeActivityBarViewOrder(activityBarOrder),
        activityBarPinned = activityBarPinned == null
            ? null
            : normalizeActivityBarPinnedViews(
                activityBarPinned,
                order: activityBarOrder,
              ),
        activityBarBadgesDisabled = activityBarBadgesDisabled == null
            ? null
            : normalizeActivityBarBadgesDisabled(
                activityBarBadgesDisabled,
                order: activityBarOrder,
              ),
        sidebarViewLocations = sidebarViewLocations == null
            ? null
            : normalizeSidebarViewLocations(sidebarViewLocations);

  /// Split direction. The root can change orientation when the Panel moves
  /// between horizontal and vertical positions; child identity and weights
  /// remain stable across that transition.
  Axis axis;
  final List<WbNode> children;

  /// 稳定标识（可选）：调试与测试定位用（分割条 key = wb-div-<左>-<右>）。
  final String? name;

  /// Root-only Activity Bar placement metadata. Null identifies legacy JSON.
  ActivityBarLocation? activityBarLocation;

  /// Root-only Primary Side Bar placement. Null migrates old layouts to Left.
  SideBarPosition? sideBarPosition;

  /// Root-only Panel alignment. Null migrates legacy layouts to Center.
  PanelAlignment? panelAlignment;

  /// Root-only Activity Bar size metadata. Null identifies JSON written before
  /// the size setting was introduced.
  ActivityBarSize? activityBarSize;

  /// Root-only Accounts global action preference. Null keeps the legacy
  /// default, where Accounts is visible.
  bool? activityBarAccountsVisible;

  /// Root-only Activity Bar view ordering. Null preserves legacy default JSON.
  List<String>? activityBarOrder;

  /// Root-only IDs of pinned Activity Bar views. Null defaults legacy layouts
  /// to all built-in views pinned.
  List<String>? activityBarPinned;

  /// Root-only IDs whose Activity Bar badges are hidden. Null keeps the
  /// default where every view is allowed to show badges.
  List<String>? activityBarBadgesDisabled;

  /// Root-only mapping from built-in Activity Bar view IDs to a side bar.
  /// Null identifies a legacy layout where all built-in views are in Primary.
  Map<String, String>? sidebarViewLocations;

  /// Root-only selected view IDs; null identifies legacy/default selection.
  String? primarySidebarView;
  String? secondarySidebarView;

  @override
  double weight;

  @override
  Map<String, Object?> toJson() => {
        't': 'split',
        'axis': axis == Axis.horizontal ? 'h' : 'v',
        if (weight != 1) 'weight': weight,
        if (name != null) 'name': name,
        if (activityBarLocation != null)
          'activityBarLocation': activityBarLocation!.name,
        if (sideBarPosition != null) 'sideBarPosition': sideBarPosition!.name,
        if (panelAlignment != null) 'panelAlignment': panelAlignment!.name,
        if (activityBarSize != null)
          'activityBarSize': activityBarSize!.jsonValue,
        if (activityBarAccountsVisible != null)
          'activityBarAccountsVisible': activityBarAccountsVisible,
        if (activityBarOrder != null)
          'activityBarOrder': normalizeActivityBarViewOrder(activityBarOrder),
        if (activityBarPinned != null)
          'activityBarPinned': normalizeActivityBarPinnedViews(
            activityBarPinned,
            order: activityBarOrder,
          ),
        if (activityBarBadgesDisabled != null &&
            normalizeActivityBarBadgesDisabled(
              activityBarBadgesDisabled,
              order: activityBarOrder,
            ).isNotEmpty)
          'activityBarBadgesDisabled': normalizeActivityBarBadgesDisabled(
            activityBarBadgesDisabled,
            order: activityBarOrder,
          ),
        if (sidebarViewLocations != null) ...{
          'sidebarViewLocations':
              normalizeSidebarViewLocations(sidebarViewLocations),
          'primarySidebarView': primarySidebarView,
          'secondarySidebarView': secondarySidebarView,
        },
        'children': children.map((c) => c.toJson()).toList(),
      };

  factory WbSplit.fromJson(Map<String, Object?> json) {
    final axis = json['axis'] == 'v' ? Axis.vertical : Axis.horizontal;
    final raw = json['children'];
    if (raw is! List || raw.length < 2) {
      throw const FormatException('split 子节点不足');
    }
    final split = WbSplit(
      axis: axis,
      weight: json['weight'] is num ? (json['weight'] as num).toDouble() : 1,
      name: json['name'] is String ? json['name'] as String : null,
      activityBarLocation:
          _activityBarLocationFromJson(json['activityBarLocation']),
      sideBarPosition: SideBarPosition.fromJson(json['sideBarPosition']),
      panelAlignment: PanelAlignment.fromJson(json['panelAlignment']),
      activityBarSize: ActivityBarSize.fromJson(json['activityBarSize']),
      activityBarAccountsVisible: json['activityBarAccountsVisible'] is bool
          ? json['activityBarAccountsVisible'] as bool
          : null,
      activityBarOrder: json.containsKey('activityBarOrder')
          ? normalizeActivityBarViewOrder(json['activityBarOrder'])
          : null,
      activityBarPinned: json.containsKey('activityBarPinned')
          ? normalizeActivityBarPinnedViews(
              json['activityBarPinned'],
              order: json['activityBarOrder'],
            )
          : null,
      activityBarBadgesDisabled: json.containsKey('activityBarBadgesDisabled')
          ? normalizeActivityBarBadgesDisabled(
              json['activityBarBadgesDisabled'],
              order: json['activityBarOrder'],
            )
          : null,
      sidebarViewLocations: json.containsKey('sidebarViewLocations')
          ? normalizeSidebarViewLocations(json['sidebarViewLocations'])
          : null,
      primarySidebarView: json['primarySidebarView'] is String
          ? json['primarySidebarView'] as String
          : null,
      secondarySidebarView: json['secondarySidebarView'] is String
          ? json['secondarySidebarView'] as String
          : null,
      children: raw
          .map((e) => WbNode.fromJson((e as Map).cast<String, Object?>()))
          .toList(),
    );
    // P05.12 layouts persisted Activity Bar placement but had no size field.
    // Upgrade those root layouts to Default while preserving the existing
    // horizontal bar height; Side receives the new 48 px default width.
    if (json.containsKey('activityBarLocation') &&
        split.activityBarSize == null) {
      split.activityBarSize = ActivityBarSize.defaultSize;
      if (split.activityBarLocation == ActivityBarLocation.side) {
        final activity = split.leafOf('activity');
        if (activity != null) {
          activity.fixedExtent = ActivityBarSize.defaultSize.sideExtent;
        }
      }
    }
    return split;
  }
}

ActivityBarLocation? _activityBarLocationFromJson(Object? raw) {
  for (final location in ActivityBarLocation.values) {
    if (location.name == raw) return location;
  }
  return null;
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
  double? fixedExtent;

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
    final serializedMinimum = _toDouble(json['min']) ?? 0;
    return WbLeaf(
      region: region,
      fixedExtent: _toDouble(json['fixed']),
      weight: _toDouble(json['weight']) ?? 1,
      minExtent: region == 'panel' &&
              serializedMinimum == _legacyDefaultPanelMinimumExtent
          ? panelMinimumHeight
          : serializedMinimum,
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
///   horizontal: [
///     activity(48px 固定), sidebar(弹性), editor(弹性),
///     secondarySidebar(弹性, 默认折叠),
///   ],
///   panel(弹性, 默认折叠, 可折叠)
/// ]
/// ```
/// 标题栏与状态栏在网格之外（不可拖拽调尺寸）。
WbSplit defaultLayout() => WbSplit(
      axis: Axis.vertical,
      activityBarLocation: ActivityBarLocation.side,
      activityBarSize: ActivityBarSize.defaultSize,
      children: [
        WbSplit(
          axis: Axis.horizontal,
          weight: 0.7,
          name: 'main-row',
          children: [
            WbLeaf(region: 'activity', fixedExtent: 48),
            WbLeaf(region: 'sidebar', weight: 0.24, minExtent: 170),
            WbLeaf(region: 'editor', weight: 0.76, minExtent: 320),
            WbLeaf(
              region: 'secondarySidebar',
              weight: 0.26,
              minExtent: 170,
              collapsed: true,
              lastWeight: 0.26,
            ),
          ],
        ),
        WbLeaf(
          region: 'panel',
          weight: 0.3,
          minExtent: panelMinimumHeight,
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

/// 节点沿 [axis] 的最小像素尺寸。
///
/// 叶子沿当前方向使用自身下限；Panel 另有 Code-OSS 的宽/高下限。
/// 同轴 split 的下限为子项之和及其分割条占位，正交 split 取子项最大值。
double nodeMinExtent(WbNode node, Axis axis) {
  final self = node;
  if (self is WbLeaf) {
    if (self.collapsed) return 0;
    final minimum = self.isFixed ? self.fixedExtent! : self.minExtent;
    final nonNegativeMinimum = math.max(0.0, minimum).toDouble();
    if (self.region == 'panel') {
      final panelMinimum =
          axis == Axis.horizontal ? panelMinimumWidth : panelMinimumHeight;
      return math.max(nonNegativeMinimum, panelMinimum).toDouble();
    }
    return nonNegativeMinimum;
  }
  final split = self as WbSplit; // sealed 层级：非叶必为 split
  final childMinimums = [
    for (final child in split.children) nodeMinExtent(child, axis),
  ];
  if (split.axis != axis) {
    var maximum = 0.0;
    for (final minimum in childMinimums) {
      if (minimum > maximum) maximum = minimum;
    }
    return maximum;
  }

  var sum = childMinimums.fold(0.0, (total, minimum) => total + minimum);
  for (var i = 1; i < split.children.length; i++) {
    if (isFlexibleNode(split.children[i - 1]) &&
        isFlexibleNode(split.children[i])) {
      sum += workbenchDividerThickness;
    }
  }
  return sum;
}

extension WbSplitLayout on WbSplit {
  /// 按当前模型把 [totalExtent] 主轴像素分配给各子节点。
  /// 最小值可满足时先保障下限，再按权重分配剩余；空间不足时按下限比例压缩。
  /// 该计算只影响当前几何，不会改写保存的权重。
  List<double> extentsFor(double totalExtent) {
    final extents = List<double>.filled(children.length, 0);
    if (totalExtent <= 0) return extents;

    final visibleIndices = <int>[];
    final minima = List<double>.filled(children.length, 0);
    var minimumTotal = 0.0;
    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      if (child case WbLeaf(collapsed: true)) continue;
      visibleIndices.add(i);
      final minimum = nodeMinExtent(child, axis);
      minima[i] = minimum;
      minimumTotal += minimum;
    }

    if (minimumTotal > totalExtent) {
      // No layout can satisfy every minimum in this viewport. Compress the
      // minima proportionally, without changing the user's stored weights.
      for (final i in visibleIndices) {
        extents[i] = totalExtent * minima[i] / minimumTotal;
      }
      return extents;
    }

    final flexibleIndices = <int>[];
    var fixedUsed = 0.0;
    for (final i in visibleIndices) {
      final child = children[i];
      if (child case WbLeaf(isFixed: true)) {
        extents[i] = child.fixedExtent!;
        fixedUsed += child.fixedExtent!;
      } else {
        flexibleIndices.add(i);
      }
    }

    final flexibleNodes = [for (final i in flexibleIndices) children[i]];
    final flexibleMinimums = [for (final i in flexibleIndices) minima[i]];
    final flexibleExtents = _allocateWeightedWithMinimums(
      nodes: flexibleNodes,
      minimums: flexibleMinimums,
      available: math.max(0.0, totalExtent - fixedUsed).toDouble(),
    );
    for (var i = 0; i < flexibleIndices.length; i++) {
      extents[flexibleIndices[i]] = flexibleExtents[i];
    }
    return extents;
  }

  /// 该 split 的各子节点最小主轴像素。
  List<double> minsFor() => children
      .map((child) => nodeMinExtent(child, axis))
      .toList(growable: false);

  /// 拖拽第 [index] 个分割条移动 [deltaPx] 像素（该 split 主轴总长 [totalExtent]）。
  /// 就地更新弹性子节点的权重，其余兄弟像素保持不变。
  void applyDrag(int index, double deltaPx, double totalExtent) {
    if (totalExtent <= 0) return;
    final extents = extentsFor(totalExtent);
    final moved = moveDivider(
        extents: extents,
        minExtents: minsFor(),
        index: index,
        deltaPx: deltaPx);
    if (moved.length != extents.length) return;
    if (List.generate(extents.length, (i) => moved[i] == extents[i])
        .every((unchanged) => unchanged)) {
      return;
    }
    final flexTotal = moved.fold(0.0, (s, e) => s + e); // 含固定像素；固定叶子不写回权重
    if (flexTotal <= 0) return;
    for (var i = 0; i < children.length; i++) {
      final c = children[i];
      final leaf = c;
      if (leaf is WbLeaf && (leaf.isFixed || leaf.collapsed)) continue;
      c.weight = moved[i] / flexTotal;
    }
  }

  /// Reset the sash at [index] by balancing its adjacent flexible children.
  /// Other siblings keep their current pixel extents. Returns whether the
  /// persisted weights changed.
  bool resetDivider(int index, double totalExtent) {
    if (totalExtent <= 0 || index < 0 || index + 1 >= children.length) {
      return false;
    }
    if (!isFlexibleNode(children[index]) ||
        !isFlexibleNode(children[index + 1])) {
      return false;
    }

    final current = extentsFor(totalExtent);
    final pairExtent = current[index] + current[index + 1];
    final minFirst = nodeMinExtent(children[index], axis);
    final minSecond = nodeMinExtent(children[index + 1], axis);
    if (pairExtent < minFirst + minSecond) return false;

    final firstExtent =
        (pairExtent / 2).clamp(minFirst, pairExtent - minSecond).toDouble();
    final secondExtent = pairExtent - firstExtent;
    if (firstExtent == current[index] && secondExtent == current[index + 1]) {
      return false;
    }

    final reset = List<double>.of(current)
      ..[index] = firstExtent
      ..[index + 1] = secondExtent;
    final flexTotal = reset.fold<double>(0, (sum, extent) => sum + extent);
    if (flexTotal <= 0) return false;
    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      if (child is WbLeaf && (child.isFixed || child.collapsed)) continue;
      child.weight = reset[i] / flexTotal;
    }
    return true;
  }
}

List<double> _allocateWeightedWithMinimums({
  required List<WbNode> nodes,
  required List<double> minimums,
  required double available,
}) {
  final extents = List<double>.filled(nodes.length, 0);
  var active = List<int>.generate(nodes.length, (index) => index);
  var remaining = available;

  while (active.isNotEmpty) {
    var weightTotal = 0.0;
    for (final i in active) {
      weightTotal += math.max(0.0, nodes[i].weight).toDouble();
    }
    final equalWeights = weightTotal <= 0;
    final proposed = <int, double>{};
    final belowMinimum = <int>[];
    for (final i in active) {
      final weight =
          equalWeights ? 1.0 : math.max(0.0, nodes[i].weight).toDouble();
      final proposal =
          remaining * weight / (equalWeights ? active.length : weightTotal);
      proposed[i] = proposal;
      if (proposal + 1e-9 < minimums[i]) belowMinimum.add(i);
    }

    if (belowMinimum.isEmpty) {
      for (final i in active) {
        extents[i] = proposed[i]!;
      }
      break;
    }

    for (final i in belowMinimum) {
      extents[i] = minimums[i];
      remaining -= minimums[i];
    }
    remaining = math.max(0.0, remaining).toDouble();
    active = active.where((i) => !belowMinimum.contains(i)).toList();
  }

  return extents;
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

  /// 把 [region] 叶子替换为 [axis] 方向的嵌套分割，并按需将新叶子放在
  /// 原叶子之前。权重由 [newWeight] 与剩余部分组成；返回新叶子，非法区域返回 null。
  WbLeaf? splitLeaf(
    String region,
    String newRegion,
    Axis axis, {
    double newWeight = 0.5,
    bool insertBefore = false,
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
      children: insertBefore ? [fresh, original] : [original, fresh],
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
      final idx = split.children
          .indexWhere((ch) => ch is WbLeaf && ch.region == region);
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
