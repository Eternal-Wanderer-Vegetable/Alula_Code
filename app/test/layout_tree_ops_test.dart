// 布局树结构变更原语测试（W2-2 编辑器组拆分）：splitLeaf / removeLeaf / 折叠。
// 对应 docs/09 W2-2；纯模型测试。
import 'package:alula_app/workbench/layout_model.dart';
import 'package:flutter/painting.dart' show Axis;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('splitLeaf', () {
    test('默认布局上分裂 editor：嵌套分割 + 权重交接', () {
      final root = defaultLayout();
      final fresh = root.splitLeaf('editor', 'editor-2', Axis.horizontal);
      expect(fresh, isNotNull);
      expect(fresh!.region, 'editor-2');
      expect(fresh.weight, closeTo(0.5, 1e-9));

      // 原位置被嵌套 split 顶替
      final row = root.children.first as WbSplit;
      final editorSlot = row.children.last;
      expect(editorSlot, isA<WbSplit>());
      final nest = editorSlot as WbSplit;
      expect(nest.axis, Axis.horizontal);
      expect((nest.children[0] as WbLeaf).region, 'editor');
      expect((nest.children[1] as WbLeaf).region, 'editor-2');
      // 外层权重交接：split 拿走原 editor 的 0.76
      expect(nest.weight, closeTo(0.76, 1e-9));
      expect((nest.children[0] as WbLeaf).weight, closeTo(0.5, 1e-9));
    });

    test('再分裂 editor-2 → 三组链式嵌套', () {
      final root = defaultLayout();
      root.splitLeaf('editor', 'editor-2', Axis.horizontal);
      final fresh = root.splitLeaf('editor-2', 'editor-3', Axis.horizontal);
      expect(fresh, isNotNull);
      expect(root.leafOf('editor-3'), isNotNull);
      expect(root.leaves.where((l) => l.region.startsWith('editor')).length, 3);
    });

    test('重复 region / 不存在 region → null', () {
      final root = defaultLayout();
      expect(root.splitLeaf('editor', 'panel', Axis.horizontal), isNull,
          reason: 'newRegion 已被占用');
      expect(root.splitLeaf('nope', 'x-1', Axis.horizontal), isNull,
          reason: 'region 不存在');
      expect(root.splitLeaf('editor', 'editor', Axis.horizontal), isNull,
          reason: '同名');
    });
  });

  group('removeLeaf', () {
    test('摘除嵌套叶子：父 split 自动折叠（唯一子顶替，权重沿用）', () {
      final root = defaultLayout();
      root.splitLeaf('editor', 'editor-2', Axis.horizontal);
      expect(root.removeLeaf('editor-2'), isTrue);

      final row = root.children.first as WbSplit;
      final editorSlot = row.children.last;
      expect(editorSlot, isA<WbLeaf>(),
          reason: '折叠后 editor 叶子顶回原位置');
      expect((editorSlot as WbLeaf).region, 'editor');
      expect(editorSlot.weight, closeTo(0.76, 1e-9),
          reason: '折叠沿用外层权重');
    });

    test('摘除兄弟尚存的叶子：不折叠', () {
      final root = defaultLayout();
      root.splitLeaf('editor', 'editor-2', Axis.horizontal);
      root.splitLeaf('editor-2', 'editor-3', Axis.horizontal);
      expect(root.removeLeaf('editor-3'), isTrue);
      // editor-2 所在 split 还有 editor → 不折叠
      final row = root.children.first as WbSplit;
      expect(row.children.last, isA<WbSplit>());
      expect(root.leafOf('editor-2'), isNotNull);
      expect(root.leafOf('editor-3'), isNull);
    });

    test('根的直接子节点不可摘除（根不能失效）', () {
      final root = defaultLayout();
      expect(root.removeLeaf('panel'), isFalse,
          reason: 'panel 是根的直接子节点，摘除会使根只剩一个子节点');
      expect(root.leafOf('panel'), isNotNull);
      // sidebar 嵌套在 main-row 内：模型层允许摘除；
      // 「哪些区域可摘」是页面层（编辑器组）的守则，不归模型管
      expect(root.removeLeaf('sidebar'), isTrue);
      expect(root.leafOf('sidebar'), isNull);
      expect(root.leafOf('editor'), isNotNull, reason: 'main-row 折叠后其余成员保留');
    });

    test('摘除后 JSON round-trip 保持折叠结构', () {
      final root = defaultLayout();
      root.splitLeaf('editor', 'editor-2', Axis.horizontal);
      root.removeLeaf('editor-2');
      final back = WbNode.fromJson(root.toJson()) as WbSplit;
      expect(back.leafOf('editor-2'), isNull);
      expect(back.leafOf('editor'), isNotNull);
    });
  });
}
