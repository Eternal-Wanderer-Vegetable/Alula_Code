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

  /// 把 [region] 叶子沿 [axis] 分裂出 [newRegion]（W2-2 编辑器组）。
  bool splitRegion(String region, String newRegion, Axis axis,
      {String? splitName}) {
    final fresh = root.splitLeaf(region, newRegion, axis, splitName: splitName);
    if (fresh != null) notifyListeners();
    return fresh != null;
  }

  /// 摘除 [region] 叶子（树会自动折叠单子节点 split）。
  bool removeRegion(String region) {
    if (root.removeLeaf(region)) {
      notifyListeners();
      return true;
    }
    return false;
  }
}
