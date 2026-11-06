// 布局树模型单测：序列化往返、divider 拖拽数学（含最小尺寸钳制）、折叠记忆。
// 对应 docs/09 W1-1；纯 Dart，无 FFI 依赖。
import 'package:flutter/painting.dart' show Axis;
import 'package:flutter_test/flutter_test.dart';

import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/layout_controller.dart';
import 'package:alula_app/workbench/activity_bar_size.dart';
import 'package:alula_app/workbench/activity_bar_order.dart';
import 'package:alula_app/workbench/activity_bar_pins.dart';
import 'package:alula_app/workbench/activity_bar_badges.dart';
import 'package:alula_app/workbench/activity_bar_global_actions.dart';

void main() {
  group('JSON 序列化往返', () {
    test('默认布局 round-trip 逐字段相等', () {
      final original = defaultLayout();
      final restored = WbNode.fromJson(original.toJson()) as WbSplit;
      expect(restored.axis, original.axis);
      expect(restored.activityBarLocation, ActivityBarLocation.side);
      expect(restored.activityBarSize, ActivityBarSize.defaultSize);
      expect(restored.activityBarOrder, isNull,
          reason: 'default layouts omit optional ordering metadata');
      expect(normalizeActivityBarViewOrder(restored.activityBarOrder),
          activityBarViewOrder);
      expect(restored.activityBarPinned, isNull,
          reason: 'default layouts keep legacy all-pinned JSON compact');
      final restoredLayout = WorkbenchLayout(root: restored);
      expect(restoredLayout.activityBarPinnedViews, activityBarViewOrder);
      restoredLayout.dispose();
      expect(restored.children.length, original.children.length);
      final inner = restored.children.first as WbSplit;
      expect(inner.axis, Axis.horizontal);
      final sidebar = inner.leafOf('sidebar')!;
      expect(sidebar.collapsed, isFalse, reason: '侧栏默认展开');
      expect(sidebar.weight, closeTo(0.24, 1e-9));
      expect(sidebar.minExtent, 170);
      final panel = restored.leafOf('panel')!;
      expect(panel.collapsed, isTrue, reason: '面板默认收起');
      expect(panel.lastWeight, closeTo(0.3, 1e-9));
      expect(inner.leafOf('activity')!.fixedExtent, 48);
    });

    test('P05.12 布局迁移到 Default，Compact 大小可往返', () {
      final p05_12 = defaultLayout();
      p05_12.leafOf('activity')!.fixedExtent = 44;
      final oldLayout = p05_12.toJson()..remove('activityBarSize');
      final migrated = WbNode.fromJson(oldLayout) as WbSplit;
      expect(migrated.activityBarSize, ActivityBarSize.defaultSize);
      expect(migrated.leafOf('activity')!.fixedExtent, 48);

      final layout = WorkbenchLayout(root: defaultLayout());
      expect(layout.setActivityBarSize(ActivityBarSize.compact), isTrue);
      final restored = WbNode.fromJson(layout.root.toJson()) as WbSplit;
      expect(restored.activityBarSize, ActivityBarSize.compact);
      expect(restored.leafOf('activity')!.fixedExtent, 36);
      layout.dispose();
    });

    test('Activity Bar order round-trip and malformed value migration', () {
      final root = defaultLayout()
        ..activityBarOrder = const ['git', 'explorer', 'search', 'outline'];
      final restored = WbNode.fromJson(root.toJson()) as WbSplit;
      expect(
          restored.activityBarOrder, ['git', 'explorer', 'search', 'outline']);

      final oldLayout = root.toJson()..remove('activityBarOrder');
      final migrated = WbNode.fromJson(oldLayout) as WbSplit;
      expect(migrated.activityBarOrder, isNull);
      expect(normalizeActivityBarViewOrder(migrated.activityBarOrder),
          activityBarViewOrder);

      final malformed = root.toJson()
        ..['activityBarOrder'] = ['git', 'git', 'unknown', 42];
      final canonical = WbNode.fromJson(malformed) as WbSplit;
      expect(
          canonical.activityBarOrder, ['git', 'explorer', 'search', 'outline']);
      expect(canonical.toJson()['activityBarOrder'],
          ['git', 'explorer', 'search', 'outline']);
    });

    test('Activity Bar pin round-trip, legacy defaults and malformed values',
        () {
      final root = defaultLayout()
        ..activityBarOrder = const ['git', 'explorer', 'search', 'outline']
        ..activityBarPinned = const ['search', 'git', 'git', 'unknown'];
      final restored = WbNode.fromJson(root.toJson()) as WbSplit;
      expect(restored.activityBarPinned, ['git', 'search']);
      expect(restored.toJson()['activityBarPinned'], ['git', 'search']);

      final legacyJson = root.toJson()..remove('activityBarPinned');
      final legacy = WbNode.fromJson(legacyJson) as WbSplit;
      expect(legacy.activityBarPinned, isNull);
      final legacyLayout = WorkbenchLayout(root: legacy);
      expect(legacyLayout.activityBarPinnedViews,
          ['git', 'explorer', 'search', 'outline']);
      legacyLayout.dispose();

      final malformedJson = root.toJson()
        ..['activityBarPinned'] = ['unknown', 42, 'git', 'git'];
      final malformed = WbNode.fromJson(malformedJson) as WbSplit;
      expect(malformed.activityBarPinned, ['git']);

      final emptyJson = root.toJson()..['activityBarPinned'] = [];
      final empty = WbNode.fromJson(emptyJson) as WbSplit;
      expect(empty.activityBarPinned, ['git', 'explorer', 'search', 'outline'],
          reason: 'invalid empty state must leave a usable pinned view set');
    });

    test('layout setter notifies once and preserves canonical default state',
        () {
      final layout = WorkbenchLayout(root: defaultLayout());
      var changes = 0;
      layout.addListener(() => changes++);

      expect(layout.activityBarOrder, activityBarViewOrder);
      expect(layout.setActivityBarOrder(activityBarViewOrder), isFalse);
      expect(layout.setActivityBarOrder(['git', 'explorer']), isTrue);
      expect(layout.activityBarOrder, ['git', 'explorer', 'search', 'outline']);
      expect(changes, 1);
      expect(layout.setActivityBarOrder(['git', 'explorer']), isFalse);
      expect(changes, 1);
      layout.dispose();
    });

    test('pin setter notifies and rejects attempts to hide the last view', () {
      final layout = WorkbenchLayout(root: defaultLayout());
      var changes = 0;
      layout.addListener(() => changes++);

      expect(layout.activityBarPinnedViews, activityBarViewOrder);
      expect(layout.setActivityBarPinnedViews(activityBarViewOrder), isFalse);
      expect(layout.setActivityBarPinnedViews(['git']), isTrue);
      expect(layout.activityBarPinnedViews, ['git']);
      expect(layout.setActivityBarPinnedViews([]), isFalse);
      expect(layout.activityBarPinnedViews, ['git']);
      expect(changes, 1);
      layout.dispose();
    });

    test('badge disabled IDs round-trip, normalize and default to enabled', () {
      final root = defaultLayout()
        ..activityBarOrder = const ['git', 'explorer', 'search', 'outline']
        ..activityBarBadgesDisabled = const ['search', 'git', 'git', 'unknown'];
      final restored = WbNode.fromJson(root.toJson()) as WbSplit;
      expect(restored.activityBarBadgesDisabled, ['git', 'search']);
      expect(restored.toJson()['activityBarBadgesDisabled'], ['git', 'search']);

      final legacyJson = root.toJson()..remove('activityBarBadgesDisabled');
      final legacy = WbNode.fromJson(legacyJson) as WbSplit;
      expect(legacy.activityBarBadgesDisabled, isNull);
      final legacyLayout = WorkbenchLayout(root: legacy);
      expect(legacyLayout.activityBarBadgesDisabledViews, isEmpty);
      legacyLayout.dispose();

      final malformedJson = root.toJson()
        ..['activityBarBadgesDisabled'] = ['unknown', 42, 'search', 'search'];
      final malformed = WbNode.fromJson(malformedJson) as WbSplit;
      expect(malformed.activityBarBadgesDisabled, ['search']);

      final emptyJson = root.toJson()..['activityBarBadgesDisabled'] = [];
      final empty = WbNode.fromJson(emptyJson) as WbSplit;
      expect(empty.activityBarBadgesDisabled, isEmpty);
      expect(empty.toJson().containsKey('activityBarBadgesDisabled'), isFalse,
          reason: 'the default all-enabled state remains compact JSON');
    });

    test('badge visibility setter persists normalized IDs and notifies once',
        () {
      final layout = WorkbenchLayout(root: defaultLayout());
      var changes = 0;
      layout.addListener(() => changes++);

      expect(layout.activityBarBadgesDisabledViews, isEmpty);
      expect(
          layout.setActivityBarBadgesDisabledViews(['search', 'git']), isTrue);
      expect(layout.activityBarBadgesDisabledViews, ['search', 'git']);
      expect(
        (WbNode.fromJson(layout.root.toJson()) as WbSplit)
            .activityBarBadgesDisabled,
        ['search', 'git'],
      );
      expect(changes, 1);
      expect(
          layout.setActivityBarBadgesDisabledViews(['search', 'git']), isFalse);
      expect(layout.setActivityBarBadgesDisabledViews([]), isTrue);
      expect(layout.activityBarBadgesDisabledViews, isEmpty);
      expect(changes, 2);
      layout.dispose();
    });

    test('Accounts visibility defaults on and persists explicit changes', () {
      final layout = WorkbenchLayout(root: defaultLayout());
      var changes = 0;
      layout.addListener(() => changes++);

      expect(layout.activityBarAccountsVisible, isTrue);
      expect(layout.root.activityBarAccountsVisible, isNull,
          reason: 'new layouts keep the default visible state compact');
      expect(layout.setActivityBarAccountsVisible(false), isTrue);
      expect(layout.activityBarAccountsVisible, isFalse);
      expect(layout.root.activityBarAccountsVisible, isFalse);
      final restored = WbNode.fromJson(layout.root.toJson()) as WbSplit;
      expect(restored.activityBarAccountsVisible, isFalse);
      final restoredLayout = WorkbenchLayout(root: restored);
      expect(restoredLayout.activityBarAccountsVisible, isFalse);
      restoredLayout.dispose();
      expect(layout.setActivityBarAccountsVisible(false), isFalse);
      expect(layout.setActivityBarAccountsVisible(true), isTrue);
      expect(layout.activityBarAccountsVisible, isTrue);
      expect(layout.root.toJson()['activityBarAccountsVisible'], isTrue);
      expect(changes, 2);
      layout.dispose();
    });

    test('legacy and malformed Accounts preferences default to visible', () {
      final legacyJson = defaultLayout().toJson()
        ..remove('activityBarAccountsVisible');
      final legacy = WbNode.fromJson(legacyJson) as WbSplit;
      expect(legacy.activityBarAccountsVisible, isNull);
      final legacyLayout = WorkbenchLayout(root: legacy);
      expect(legacyLayout.activityBarAccountsVisible, isTrue);
      legacyLayout.dispose();

      final malformedJson = defaultLayout().toJson()
        ..['activityBarAccountsVisible'] = 'hidden';
      final malformed = WbNode.fromJson(malformedJson) as WbSplit;
      expect(malformed.activityBarAccountsVisible, isNull);
      final malformedLayout = WorkbenchLayout(root: malformed);
      expect(malformedLayout.activityBarAccountsVisible, isTrue);
      malformedLayout.dispose();
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

  group('权重 ⇄ 像素换算（WbSplitLayout）', () {
    test('extentsFor：固定/折叠/弹性', () {
      final split = WbSplit(axis: Axis.horizontal, children: [
        WbLeaf(region: 'activity', fixedExtent: 44),
        WbLeaf(
            region: 'sidebar', weight: 0.25, collapsed: true, lastWeight: 0.25),
        WbLeaf(region: 'editor', weight: 0.75),
      ]);
      final px = split.extentsFor(1000);
      expect(px[0], 44); // 固定
      expect(px[1], 0); // 折叠
      expect(px[2], 956); // 1000-44 全给弹性
    });

    test('extentsFor：嵌套 split 作为弹性子节点参与分配', () {
      final root = WbSplit(axis: Axis.vertical, children: [
        WbSplit(axis: Axis.horizontal, weight: 0.7, children: [
          WbLeaf(region: 'a'),
          WbLeaf(region: 'b'),
        ]),
        WbLeaf(region: 'panel', weight: 0.3),
      ]);
      final px = root.extentsFor(1000);
      expect(px[0], closeTo(700, 1e-9));
      expect(px[1], closeTo(300, 1e-9));
    });

    test('minsFor：嵌套 split 取子节点最小值之和', () {
      final root = WbSplit(axis: Axis.vertical, children: [
        WbSplit(axis: Axis.horizontal, children: [
          WbLeaf(region: 'a', minExtent: 100),
          WbLeaf(region: 'b', minExtent: 50),
        ]),
        WbLeaf(region: 'panel', minExtent: 120),
      ]);
      expect(root.minsFor(), [150, 120]);
    });

    test('applyDrag：其余兄弟像素严格不动（docs/09 验收点）', () {
      final split = WbSplit(axis: Axis.horizontal, children: [
        WbLeaf(region: 'sidebar', weight: 0.3, minExtent: 170),
        WbLeaf(region: 'editor', weight: 0.7),
      ]);
      const total = 1000.0;
      final before = split.extentsFor(total);
      split.applyDrag(0, 100, total);
      final after = split.extentsFor(total);
      expect(after[0], closeTo(before[0] + 100, 1e-6));
      expect(after[1], closeTo(before[1] - 100, 1e-6));
    });

    test('applyDrag：min 钳制生效', () {
      final split = WbSplit(axis: Axis.horizontal, children: [
        WbLeaf(region: 'sidebar', weight: 0.3, minExtent: 170),
        WbLeaf(region: 'editor', weight: 0.7),
      ]);
      split.applyDrag(0, -1000, 1000);
      final px = split.extentsFor(1000);
      expect(px[0], 170);
      expect(px[1], 830);
    });

    test('applyDrag：拖嵌套 split 与叶子的分界 → 只改两者权重', () {
      final inner = WbSplit(axis: Axis.horizontal, weight: 0.7, children: [
        WbLeaf(region: 'a'),
        WbLeaf(region: 'b'),
      ]);
      final panel = WbLeaf(region: 'panel', weight: 0.3);
      final root = WbSplit(axis: Axis.vertical, children: [inner, panel]);
      root.applyDrag(0, 100, 1000);
      final px = root.extentsFor(1000);
      expect(px[0], closeTo(800, 1e-6));
      expect(px[1], closeTo(200, 1e-6));
      // inner 内部两个叶子等分，不受父级拖拽影响
      final innerPx = inner.extentsFor(px[0]);
      expect(innerPx[0], closeTo(innerPx[1], 1e-6));
    });

    test('权重往返无漂移：extentsFor → applyDrag(0) → extentsFor 恒等', () {
      final split = WbSplit(axis: Axis.horizontal, children: [
        WbLeaf(region: 'activity', fixedExtent: 44),
        WbLeaf(region: 'sidebar', weight: 0.4, minExtent: 170),
        WbLeaf(region: 'editor', weight: 0.6),
      ]);
      const total = 800.0;
      final before = split.extentsFor(total);
      split.applyDrag(1, 0, total); // delta 0：写回权重后应无漂移
      final after = split.extentsFor(total);
      expect(after[0], closeTo(before[0], 1e-6));
      expect(after[1], closeTo(before[1], 1e-6));
      expect(after[2], closeTo(before[2], 1e-6));
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
      expect(sidebar.collapsed, isFalse, reason: '侧栏默认展开');
      // 折叠：记住当前权重
      sidebar.lastWeight = sidebar.weight;
      sidebar.collapsed = true;
      expect(sidebar.lastWeight, closeTo(0.24, 1e-9));
      // 恢复：还原 lastWeight，清空记忆
      sidebar.weight = sidebar.lastWeight!;
      sidebar.lastWeight = null;
      sidebar.collapsed = false;
      expect(sidebar.weight, closeTo(0.24, 1e-9));
      expect(sidebar.collapsed, isFalse);
    });
  });
}
