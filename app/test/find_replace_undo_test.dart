// find_replace + undo_stack 纯逻辑单测（feat-010）。
// UTF-16 口径：Dart String 索引天然是 UTF-16 code unit，与 FFI 协议一致；
// 代理对（Emoji）场景必须有专门用例。
import 'package:alula_app/editor/find_replace.dart';
import 'package:alula_app/editor/undo_stack.dart';
import 'package:alula_app/bridge/alula_core.dart' show TextOp;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('findMatches', () {
    test('基本命中与非重叠计数', () {
      final m = findMatches('aXaXa', 'aX');
      expect(m.map((e) => e.start).toList(), [0, 2]);
      expect(m.last.end, 4);
    });

    test('大小写不敏感', () {
      expect(findMatches('Foo foo FOO', 'foo', caseSensitive: false).length, 3);
      expect(findMatches('Foo foo FOO', 'foo', caseSensitive: true).length, 1);
    });

    test('空查询与无命中', () {
      expect(findMatches('abc', ''), isEmpty);
      expect(findMatches('abc', 'zz'), isEmpty);
    });

    test('UTF-16 口径：Emoji（代理对）占 2 个 code unit，偏移不落代理对中间', () {
      const text = '👨a👨b'; // 2*2 + 2 = 6 code units
      final m = findMatches(text, 'a');
      expect(m.single.start, 2, reason: '👨 占 [0,2)，a 在 2');
      final mb = findMatches(text, 'b');
      expect(mb.single.start, 5);
      // 查询串本身含 emoji：整串命中
      final m2 = findMatches('$text👨', '👨');
      expect(m2.length, 3);
    });

    test('CRLF 与换行环境命中', () {
      final m = findMatches('x\r\nyx', 'y');
      expect(m.single.start, 3);
    });

    test('有界输入窗可二分定位首个相交的 UTF-16 命中', () {
      final matches = findMatches('a👨a👨a', 'a');
      expect(firstTextMatchEndingAfter(matches, 0), 0);
      expect(firstTextMatchEndingAfter(matches, 2), 1);
      expect(firstTextMatchEndingAfter(matches, 4), 2);
      expect(firstTextMatchEndingAfter(matches, 7), matches.length);
    });
  });

  group('replaceAllMatches', () {
    test('全部替换与计数', () {
      final r = replaceAllMatches('aXaXa', 'aX', 'Z', caseSensitive: true);
      expect(r.newText, 'ZZa');
      expect(r.count, 2);
    });

    test('大小写不敏感替换', () {
      final r =
          replaceAllMatches('Foo foo FOO', 'foo', 'bar', caseSensitive: false);
      expect(r.count, 3);
      expect(r.newText, 'bar bar bar');
    });

    test('替换串包含查询串不造成重叠误替换', () {
      final r = replaceAllMatches('aa', 'a', 'aa');
      expect(r.newText, 'aaaa');
      expect(r.count, 2);
    });

    test('UTF-16：替换文本含 Emoji', () {
      final r = replaceAllMatches('a-a', 'a', '👨');
      expect(r.newText, '👨-👨');
      expect(r.count, 2);
    });

    test('空查询原样返回', () {
      final r = replaceAllMatches('abc', '', 'x');
      expect(r.newText, 'abc');
      expect(r.count, 0);
    });
  });

  group('UndoStack', () {
    test('push/undo/redo 往返', () {
      final st = UndoStack();
      expect(st.canUndo, isFalse);

      st.push(before: 'v1', caret: 2, coalesce: false);
      st.push(before: 'v2', caret: 3, coalesce: false);
      expect(st.canUndo, isTrue);

      final u1 = st.undo('v3', 3)!;
      expect(u1.text, 'v2');
      final u2 = st.undo('v2', 2)!;
      expect(u2.text, 'v1');
      expect(st.canUndo, isFalse);

      final r1 = st.redo('v1', 0)!;
      expect(r1.text, 'v2');
      final r2 = st.redo('v2', 2)!;
      expect(r2.text, 'v3');
      expect(st.canRedo, isFalse);
    });

    test('格式转换的编码/BOM/EOL 状态可随 undo/redo 往返', () {
      final st = UndoStack();
      st.push(
        before: 'same text',
        caret: 4,
        coalesce: false,
        encoding: 'utf-8',
        bom: false,
        lineEnding: 'lf',
      );

      final undo = st.undo(
        'same text',
        4,
        encoding: 'utf-8',
        bom: false,
        lineEnding: 'crlf',
      )!;
      expect(undo.text, 'same text');
      expect(undo.lineEnding, 'lf');

      final redo = st.redo(
        'same text',
        4,
        encoding: undo.encoding,
        bom: undo.bom,
        lineEnding: undo.lineEnding,
      )!;
      expect(redo.text, 'same text');
      expect(redo.lineEnding, 'crlf');
    });

    test('跨文档事务标识随 undo/redo 历史保留', () {
      final stack = UndoStack();
      stack.push(
        before: 'before',
        caret: 3,
        coalesce: false,
        transactionId: 'workspace-transaction-1',
      );

      final undo = stack.undo('after', 2)!;
      expect(undo.transactionId, 'workspace-transaction-1');
      final redo = stack.redo('before', 3)!;
      expect(redo.transactionId, 'workspace-transaction-1');
    });

    test('coalesce 合并不压新帧：一次撤销回退整段输入', () {
      final st = UndoStack();
      st.push(before: 'base', caret: 4, coalesce: false);
      // 连续打字（合并窗口内）不压新帧
      st.push(before: 'basea', caret: 5, coalesce: true);
      st.push(before: 'baseab', caret: 6, coalesce: true);
      final u = st.undo('baseabc', 7)!;
      expect(u.text, 'base', reason: '整段打字一次回退');
    });

    test(
        'operation frames coalesce and move between undo/redo without snapshots',
        () {
      final budget = UndoHistoryBudget(maxTotalEntries: 10, maxTotalChars: 10);
      final stack = UndoStack(budget: budget);
      stack.pushOperations(
        forward: [const TextOp.insert(3, 'a')],
        inverse: [const TextOp.delete(3, 1)],
        caret: 3,
        coalesce: false,
      );
      stack.pushOperations(
        forward: [const TextOp.insert(4, 'b')],
        inverse: [const TextOp.delete(4, 1)],
        caret: 4,
        coalesce: true,
      );

      expect(budget.totalEntries, 1);
      expect(budget.totalChars, 2);
      final undo = stack.takeOperationUndo()!;
      expect(undo.isOperation, isTrue);
      expect(undo.text, isEmpty, reason: 'no whole-document text is retained');
      expect(
        undo.inverseBatches,
        [
          [const TextOp.delete(4, 1)],
          [const TextOp.delete(3, 1)],
        ],
      );
      expect(stack.canUndo, isFalse);
      expect(stack.canRedo, isTrue);
      expect(budget.totalEntries, 1, reason: 'moving to redo keeps one frame');

      final redo = stack.takeOperationRedo()!;
      expect(
        redo.forwardBatches,
        [
          [const TextOp.insert(3, 'a')],
          [const TextOp.insert(4, 'b')],
        ],
      );
      expect(stack.canUndo, isTrue);
      expect(stack.canRedo, isFalse);
      expect(budget.totalChars, 2);
      stack.dispose();
      expect(budget.totalEntries, 0);
      expect(budget.totalChars, 0);
    });

    test(
        'operation history budget counts inserted UTF-16 payload including deletes',
        () {
      final budget = UndoHistoryBudget(maxTotalEntries: 10, maxTotalChars: 8);
      final stack = UndoStack(budget: budget);
      stack.pushOperations(
        forward: [
          const TextOp.delete(1, 2),
          const TextOp.insert(1, 'x'),
        ],
        inverse: [
          const TextOp.delete(1, 1),
          const TextOp.insert(1, '👨'),
        ],
        caret: 1,
        coalesce: false,
      );

      expect(budget.totalChars, 3, reason: 'emoji is two UTF-16 code units');
      stack.clear();
      expect(budget.totalChars, 0);
      stack.dispose();
    });

    test('新变更作废 redo 栈', () {
      final st = UndoStack();
      st.push(before: 'v1', caret: 2, coalesce: false);
      st.undo('v2', 2);
      expect(st.canRedo, isTrue);
      st.push(before: 'vX', caret: 2, coalesce: false);
      expect(st.canRedo, isFalse, reason: '分叉后 redo 作废');
    });

    test('条数上限淘汰最旧', () {
      final st = UndoStack(maxEntries: 3);
      for (var i = 0; i < 5; i++) {
        st.push(before: 'v$i', caret: 2, coalesce: false);
      }
      expect(st.undo('v5', 2)!.text, 'v4');
      expect(st.undo('v4', 2)!.text, 'v3');
      expect(st.undo('v3', 2)!.text, 'v2', reason: 'v0/v1 已淘汰');
      expect(st.canUndo, isFalse);
    });

    test('总字符上限淘汰最旧历史帧', () {
      final st = UndoStack(maxTotalChars: 10);
      st.push(before: '12345', caret: 5, coalesce: false); // 5
      st.push(before: '67890', caret: 5, coalesce: false); // 10
      st.push(before: 'abc', caret: 3, coalesce: false); // 13 > 10 → 淘汰 12345
      expect(st.undo('x', 1)!.text, 'abc', reason: 'undo 弹栈顶（最新步骤）');
      expect(st.undo('abc', 3)!.text, '67890');
      expect(st.canUndo, isFalse, reason: '最旧帧 12345 已被预算淘汰');
    });

    test('clear 清空双栈', () {
      final st = UndoStack();
      st.push(before: 'v1', caret: 2, coalesce: false);
      st.undo('v2', 2);
      st.clear();
      expect(st.canUndo, isFalse);
      expect(st.canRedo, isFalse);
    });

    test('共享预算跨文档淘汰最旧帧并在关闭时归还额度', () {
      final budget = UndoHistoryBudget(maxTotalEntries: 3, maxTotalChars: 100);
      final a = UndoStack(budget: budget);
      final b = UndoStack(budget: budget);

      a.push(before: 'a0', caret: 2, coalesce: false);
      b.push(before: 'b0', caret: 2, coalesce: false);
      a.push(before: 'a1', caret: 2, coalesce: false);
      b.push(before: 'b1', caret: 2, coalesce: false);

      expect(budget.totalEntries, 3);
      expect(budget.totalChars, 6);
      expect(a.undo('a2', 2)!.text, 'a1');
      expect(a.canUndo, isFalse, reason: '最早的 a0 已由共享预算淘汰');
      expect(b.canUndo, isTrue);

      a.dispose();
      expect(budget.totalEntries, 2);
      expect(budget.totalChars, 4);
      b.dispose();
      expect(budget.totalEntries, 0);
      expect(budget.totalChars, 0);
    });

    test('共享预算将 redo 帧计入总条数', () {
      final budget = UndoHistoryBudget(maxTotalEntries: 2, maxTotalChars: 100);
      final a = UndoStack(budget: budget);
      final b = UndoStack(budget: budget);
      a.push(before: 'a0', caret: 2, coalesce: false);
      b.push(before: 'b0', caret: 2, coalesce: false);
      a.undo('a1', 2);

      expect(a.canRedo, isTrue);
      expect(budget.totalEntries, 2);
      b.push(before: 'b1', caret: 2, coalesce: false);

      expect(a.canRedo, isTrue);
      expect(b.undo('b2', 2)!.text, 'b1');
      expect(b.canUndo, isFalse, reason: 'b0 已按全局最旧帧顺序淘汰');
      expect(budget.totalEntries, 2);
      a.dispose();
      b.dispose();
      expect(budget.totalEntries, 0);
    });
  });
}
