/// 工作台布局状态：模型实例 + 变更通知 + 区域折叠切换。
///
/// 纯布局状态，不含区域内容；渲染见 layout_grid.dart。
/// W1-4 将在此追加持久化（保存/恢复 JSON）。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Axis;

import 'layout_model.dart';

class WorkbenchLayout extends ChangeNotifier {
  WorkbenchLayout({WbSplit? root}) : root = root ?? defaultLayout();

  WbSplit root;

  // Runtime-only presentation state. The layout store serializes [root] only.
  bool _panelMaximized = false;

  bool get panelMaximized => _panelMaximized;

  /// Updates the transient Panel presentation state without changing the
  /// persisted split tree. [notify] lets a layout transaction emit one update.
  void setPanelMaximized(bool maximized, {bool notify = true}) {
    if (_panelMaximized == maximized) return;
    _panelMaximized = maximized;
    if (notify) notifyListeners();
  }

  String? _maximizedEditorRegion;
  String? get maximizedEditorRegion => _maximizedEditorRegion;

  bool toggleEditorGroupMaximization(String region) {
    if (_maximizedEditorRegion != null) {
      restoreEditorGroups();
      return true;
    }

    bool containsGroup(WbSplit split) {
      final span = split.editorGroupSpan;
      if (span != null &&
          split.children
              .getRange(span.first, span.last + 1)
              .any((child) => child.leafOf(region) != null)) {
        return true;
      }
      return split.children.whereType<WbSplit>().any(containsGroup);
    }

    if (!containsGroup(root)) return false;
    _maximizedEditorRegion = region;
    notifyListeners();
    return true;
  }

  void restoreEditorGroups() {
    if (_maximizedEditorRegion == null) return;
    _maximizedEditorRegion = null;
    notifyListeners();
  }

  void resetEditorGroupSizes() {
    var changed = _maximizedEditorRegion != null;
    _maximizedEditorRegion = null;

    // Consecutive same-axis splits represent columns (or rows) of the same
    // run. An orthogonal child takes one share on this axis.
    int shares(WbNode node, Axis axis) {
      if (node is WbSplit && node.axis == axis) {
        return node.children
            .fold(0, (total, child) => total + shares(child, axis));
      }
      return 1;
    }

    void distribute(WbSplit split) {
      final span = split.editorGroupSpan;
      if (span != null) {
        final groups = split.children.sublist(span.first, span.last + 1);
        final weight = groups.fold(0.0, (sum, node) => sum + node.weight);
        final totalShares =
            groups.fold(0, (sum, node) => sum + shares(node, split.axis));
        for (final node in groups) {
          final next = weight * shares(node, split.axis) / totalShares;
          if ((node.weight - next).abs() > 1e-9) {
            node.weight = next;
            changed = true;
          }
        }
      }
      for (final child in split.children.whereType<WbSplit>()) {
        distribute(child);
      }
    }

    distribute(root);
    if (changed) notifyListeners();
  }

  /// Notify grid renderers after a layout-tree operation performed outside
  /// this controller's built-in split/region methods.
  void notifyLayoutChanged() => notifyListeners();

  WbLeaf? leafOf(String region) => root.leafOf(region);

  bool isCollapsed(String region) => leafOf(region)?.collapsed ?? false;

  /// 切换区域折叠，返回切换后的状态。固定叶子不可折叠。
  bool toggleRegion(String region) {
    final leaf = leafOf(region);
    if (leaf == null || leaf.isFixed) return leaf?.collapsed ?? false;
    if (leaf.collapsed) {
      leaf.weight = leaf.lastWeight ?? leaf.weight;
      leaf.lastWeight = null;
      leaf.collapsed = false;
    } else {
      leaf.lastWeight = leaf.weight;
      leaf.collapsed = true;
    }
    notifyListeners();
    return leaf.collapsed;
  }

  /// 设置区域折叠目标态；fixed leaf 可折叠为零尺寸且恢复原固定尺寸。
  bool setRegionCollapsed(String region, bool collapsed) {
    final leaf = leafOf(region);
    if (leaf == null) return false;
    if (leaf.collapsed == collapsed) return leaf.collapsed;

    if (leaf.isFixed) {
      // fixed extent 不参与权重恢复；lastWeight 仅保留 collapsed leaf 的
      // 序列化不变量，恢复时不改固定宽度。
      leaf.lastWeight = collapsed ? leaf.weight : null;
    } else if (collapsed) {
      leaf.lastWeight = leaf.weight;
    } else {
      leaf.weight = leaf.lastWeight ?? leaf.weight;
      leaf.lastWeight = null;
    }
    leaf.collapsed = collapsed;
    notifyListeners();
    return leaf.collapsed;
  }

  /// 展开区域（已展开则不动）。打开文件夹时唤起侧栏用。
  void showRegion(String region) {
    final leaf = leafOf(region);
    if (leaf == null || !leaf.collapsed) return;
    toggleRegion(region);
  }

  /// 分割条拖拽（由 WorkbenchGrid 调用）。
  void dragDivider(
      WbSplit split, int index, double deltaPx, double totalExtent) {
    split.applyDrag(index, deltaPx, totalExtent);
    notifyListeners();
  }

  /// Double-click reset for a rendered sash; successful resets notify the
  /// grid so persisted layout and dependent projections can be synchronized.
  bool resetDivider(WbSplit split, int index, double totalExtent) {
    if (!split.resetDivider(index, totalExtent)) return false;
    notifyListeners();
    return true;
  }

  /// 把 [region] 叶子沿 [axis] 分裂出 [newRegion]（W2-2 编辑器组）。
  bool splitRegion(String region, String newRegion, Axis axis,
      {bool insertBefore = false, String? splitName}) {
    final fresh = root.splitLeaf(
      region,
      newRegion,
      axis,
      insertBefore: insertBefore,
      splitName: splitName,
    );
    if (fresh != null) notifyListeners();
    return fresh != null;
  }

  /// Move a group leaf as one layout transaction. Its pane and all document
  /// views remain keyed by the same region.
  bool moveEditorGroup(
    String source,
    String target,
    Axis axis, {
    required bool insertBefore,
  }) {
    if (source == target) return false;
    final sourceParent = root.parentSplitOf(source);
    final targetParent = root.parentSplitOf(target);
    final sourceLeaf = root.leafOf(source);
    final targetLeaf = root.leafOf(target);
    if (sourceParent == null ||
        targetParent == null ||
        sourceLeaf == null ||
        targetLeaf == null) {
      return false;
    }

    final sourceIndex = sourceParent.children.indexOf(sourceLeaf);
    if (identical(sourceParent, targetParent) &&
        (sourceParent.axis == axis || sourceParent.children.length == 2)) {
      final targetIndex = sourceParent.children.indexOf(targetLeaf);
      if (sourceParent.axis == axis &&
          sourceIndex == targetIndex + (insertBefore ? -1 : 1)) {
        return false;
      }
      if (sourceParent.axis != axis) {
        final half = (sourceLeaf.weight + targetLeaf.weight) / 2;
        sourceParent.axis = axis;
        sourceLeaf.weight = half;
        targetLeaf.weight = half;
      }
      sourceParent.children.removeAt(sourceIndex);
      final insertAt = sourceParent.children.indexOf(targetLeaf);
      sourceParent.children
          .insert(insertBefore ? insertAt : insertAt + 1, sourceLeaf);
    } else {
      if (identical(sourceParent, root)) {
        if (root.children.length <= 2) return false;
        root.children.removeAt(sourceIndex);
      } else if (!root.removeLeaf(source)) {
        return false;
      }

      // Removing the source can collapse its parent onto the target. Resolve
      // the insertion point in the resulting tree before sharing its space.
      final parent = root.parentSplitOf(target)!;
      final index = parent.children.indexOf(targetLeaf);
      final targetWeight = targetLeaf.weight;
      final span = parent.editorGroupSpan;
      if (parent.axis == axis &&
          span != null &&
          index >= span.first &&
          index <= span.last) {
        sourceLeaf.weight = targetWeight / 2;
        targetLeaf.weight = targetWeight / 2;
        parent.children.insert(insertBefore ? index : index + 1, sourceLeaf);
      } else {
        sourceLeaf.weight = 0.5;
        targetLeaf.weight = 0.5;
        parent.children[index] = WbSplit(
          axis: axis,
          weight: targetWeight,
          children: insertBefore
              ? [sourceLeaf, targetLeaf]
              : [targetLeaf, sourceLeaf],
        );
      }
    }

    _maximizedEditorRegion = null;
    notifyListeners();
    return true;
  }

  /// 摘除 [region] 叶子（树会自动折叠单子节点 split）。
  bool removeRegion(String region) {
    final rootIndex = _rootChildIndex(region);
    if (rootIndex >= 0) {
      // A workbench root usually has several fixed shell regions in addition
      // to editor groups. Removing one of those direct children is safe while
      // at least two root children remain; WbSplit.removeLeaf keeps the more
      // conservative rule because it has no access to controller metadata.
      if (root.children.length <= 2) return false;
      root.children.removeAt(rootIndex);
      notifyListeners();
      return true;
    }
    if (root.removeLeaf(region)) {
      notifyListeners();
      return true;
    }
    return false;
  }

  int _rootChildIndex(String region) => root.children.indexWhere(
        (child) => child is WbLeaf && child.region == region,
      );
}
