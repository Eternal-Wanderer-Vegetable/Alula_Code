// 布局树模型单测：序列化往返、divider 拖拽数学（含最小尺寸钳制）、折叠记忆。
// 对应 docs/09 W1-1；纯 Dart，无 FFI 依赖。
import 'package:flutter/painting.dart' show Axis;
import 'package:flutter_test/flutter_test.dart';

import 'package:alula_app/workbench/layout_model.dart';

void main() {
  group('JSON 序列化往返', () {
    test('默认布局 round-trip 逐字段相等', () {
      final original = defaultLayout();
      final restored =
          WbNode.fromJson(original.toJson()) as WbSplit;
      expect(restored.axis, original.axis);
      expect(restored.children.length, original.children.length);
      final inner = restored.children.first as WbSplit;
      expect(inner.axis, Axis.horizontal);
      final sidebar = inner.leafOf('sidebar')!;
      expect(sidebar.collapsed, isTrue);
      expect(sidebar.lastWeight, closeTo(0.24, 1e-9));
      expect(sidebar.minExtent, 170);
      expect(inner.leafOf('activity')!.fixedExtent, 44);
    });

    test('叶子权重/折叠态 round-trip', () {
      final leaf = WbLeaf(
          region: 'panel',
          weight: 0.3,
          minExtent: 120,
          collapsed: true,
          lastWeight: 0.3);
      final back = WbLeaf.fromJson(leaf.toJson());
      expect(back.region, 'panel');
      expect(back.weight, closeTo(0.3, 1e-9));
      expect(back.minExtent, 120);
      expect(back.collapsed, isTrue);
      expect(back.lastWeight, closeTo(0.3, 1e-9));
    });

    test('损坏输入抛 FormatException（store 层负责回退默认布局）', () {
      expect(() => WbNode.fromJson({'t': 'bogus'}),
          throwsA(isA<FormatException>()));
      expect(() => WbNode.fromJson({'t': 'split', 'children': []}),
          throwsA(isA<FormatException>()));
      expect(() => WbLeaf.fromJson({'t': 'leaf'}),
          throwsA(isA<FormatException>()));
    });
  });

  group('moveDivider 拖拽数学', () {
    test('普通移动：其余兄弟像素不变', () {
      // [a=100, b=100, c=100] 拖 divider0 右移 30
      final out = moveDivider(
        extents: [100, 100, 100],
        minExtents: [50, 50, 50],
        index: 0,
        deltaPx: 30,
      );
      expect(out[0], 130);
      expect(out[1], 70);
      expect(out[2], 100); // 第三格不动
    });

    test('左移为负 delta', () {
      final out = moveDivider(
        extents: [100, 100, 100],
        minExtents: [50, 50, 50],
        index: 0,
        deltaPx: -40,
      );
      expect(out[0], 60);
      expect(out[1], 140);
    });

    test('钳制：触及 a 的最小尺寸', () {
      final out = moveDivider(
        extents: [100, 100],
        minExtents: [50, 50],
        index: 0,
        deltaPx: -100,
      );
      expect(out[0], 50);
      expect(out[1], 150);
    });

    test('钳制：b 不得被压破最小尺寸', () {
      final out = moveDivider(
        extents: [100, 100],
        minExtents: [50, 50],
        index: 0,
        deltaPx: 100,
      );
      expect(out[0], 150);
      expect(out[1], 50);
    });

    test('两端同时触底时 a 取可达边界', () {
      // a+b=60，minA=40、minB=40：可调空间为 0，原样返回
      final out = moveDivider(
        extents: [30, 30],
        minExtents: [40, 40],
        index: 0,
        deltaPx: 10,
      );
      expect(out[0], 30);
      expect(out[1], 30);
    });

    test('非法输入原样返回', () {
      final out = moveDivider(
        extents: [100, 100],
        minExtents: [50, 50],
        index: 5,
        deltaPx: 10,
      );
      expect(out, [100, 100]);
    });
  });

  group('权重 ⇄ 像素换算', () {
    test('weightsToExtents：固定/折叠/弹性', () {
      final leaves = [
        WbLeaf(region: 'activity', fixedExtent: 44),
        WbLeaf(
            region: 'sidebar',
            weight: 0.25,
            collapsed: true,
            lastWeight: 0.25),
        WbLeaf(region: 'editor', weight: 0.75),
      ];
      final px = weightsToExtents(leaves, 1000);
      expect(px[0], 44); // 固定
      expect(px[1], 0); // 折叠
      expect(px[2], 956); // 1000-44 全给弹性
    });

    test('extentsToWeights 归一化且固定为 0，回到 weightsToExtents 尺寸稳定', () {
      final leaves = [
        WbLeaf(region: 'activity', fixedExtent: 44),
        WbLeaf(region: 'sidebar', weight: 0.5, minExtent: 170),
        WbLeaf(region: 'editor', weight: 0.5),
      ];
      const total = 800.0;
      final px1 = weightsToExtents(leaves, total);
      final w = extentsToWeights(px1, [true, false, false]);
      expect(w[0], 0);
      expect(w[1] + w[2], closeTo(1, 1e-9));
      // 写回后再分配，像素应与 px1 一致（无漂移）
      leaves[1].weight = w[1];
      leaves[2].weight = w[2];
      final px2 = weightsToExtents(leaves, total);
      expect(px2[1], closeTo(px1[1], 1e-6));
      expect(px2[2], closeTo(px1[2], 1e-6));
    });

    test('拖拽数学接入换算：其余格子像素严格不动（docs/09 验收点）', () {
      final leaves = [
        WbLeaf(region: 'sidebar', weight: 0.3, minExtent: 170),
        WbLeaf(region: 'editor', weight: 0.7),
      ];
      const total = 1000.0;
      var px = weightsToExtents(leaves, total);
      px = moveDivider(extents: px, minExtents: [170, 320], index: 0, deltaPx: 100);
      final w = extentsToWeights(px, [false, false]);
      leaves[0].weight = w[0];
      leaves[1].weight = w[1];
      final px2 = weightsToExtents(leaves, total);
      expect(px2[0], closeTo(px[0], 1e-6));
      expect(px2[1], closeTo(px[1], 1e-6));
    });
  });

  group('叶子查找与折叠记忆', () {
    test('leafOf 命中与未命中', () {
      final root = defaultLayout();
      expect(root.leafOf('editor'), isNotNull);
      expect(root.leafOf('nope'), isNull);
    });

    test('折叠恢复还原折叠前权重（折叠记忆）', () {
      final root = defaultLayout();
      final sidebar = root.leafOf('sidebar')!;
      expect(sidebar.collapsed, isTrue);
      // 恢复：还原 lastWeight，清空记忆
      sidebar.weight = sidebar.lastWeight!;
      sidebar.lastWeight = null;
      sidebar.collapsed = false;
      expect(sidebar.weight, closeTo(0.24, 1e-9));
      expect(sidebar.collapsed, isFalse);
      // 再折叠：把当前权重存进 lastWeight
      sidebar.lastWeight = sidebar.weight;
      sidebar.collapsed = true;
      expect(sidebar.lastWeight, closeTo(0.24, 1e-9));
    });
  });
}
