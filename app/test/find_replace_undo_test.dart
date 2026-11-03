// find_replace + undo_stack 纯逻辑单测（feat-010）。
// UTF-16 口径：Dart String 索引天然是 UTF-16 code unit，与 FFI 协议一致；
// 代理对（Emoji）场景必须有专门用例。
import 'dart:async';

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

    test('全字匹配遵循分隔符并保持 Emoji 与 CRLF 的 UTF-16 偏移', () {
      const text = '👨foo foo_bar foo-bar\r\nfoo';
      expect(findMatches(text, 'foo'), hasLength(4));
      expect(
        findMatches(text, 'foo', wholeWord: true)
            .map((match) => (match.start, match.end))
            .toList(),
        [(14, 17), (23, 26)],
      );
    });

    test('大小写不敏感匹配返回原文 UTF-16 偏移', () {
      const text = '\u0130foo FOO';
      expect(
        findMatches(text, 'foo').map((match) => match.start).toList(),
        [1, 5],
      );
    });

    test('BOM 作为空白边界支持全字匹配', () {
      expect(findMatches('\uFEFFword\uFEFF', 'word', wholeWord: true),
          hasLength(1));
    });

    test('选区范围裁剪并保留 Unicode、CRLF 原文 UTF-16 偏移', () {
      const text = '👨foo\r\nfoo';
      final scopes = [
        const TextMatchScope(2, 5),
        const TextMatchScope(7, 10),
      ];
      expect(
        findMatches(text, 'foo', scopes: scopes)
            .map((match) => (match.start, match.end))
            .toList(),
        [(2, 5), (7, 10)],
      );
    });

    test('独立相邻选区不能拼成跨边界命中，重叠选区不重复命中', () {
      expect(
        findMatches(
          'foo',
          'foo',
          scopes: const [TextMatchScope(0, 2), TextMatchScope(2, 3)],
        ),
        isEmpty,
      );
      expect(
        findMatches(
          'foo foo',
          'foo',
          scopes: const [
            TextMatchScope(0, 4),
            TextMatchScope(1, 5),
            TextMatchScope(4, 7),
          ],
        ).map((match) => match.start).toList(),
        [0, 4],
      );
    });

    test('selection capture trims trailing CRLF and keeps disjoint selections',
        () {
      expect(
        findScopesFromSelections(
          'foo\r\nbar\n',
          const [TextMatchScope(0, 5), TextMatchScope(5, 9)],
        ).map((scope) => (scope.start, scope.end)).toList(),
        [(0, 3), (5, 8)],
      );
    });

    test('有界输入窗可二分定位首个相交的 UTF-16 命中', () {
      final matches = findMatches('a👨a👨a', 'a');
      expect(firstTextMatchEndingAfter(matches, 0), 0);
      expect(firstTextMatchEndingAfter(matches, 2), 1);
      expect(firstTextMatchEndingAfter(matches, 4), 2);
      expect(firstTextMatchEndingAfter(matches, 7), matches.length);
    });
  });

  group('findRegexMatches', () {
    test('line anchors work on each CRLF line with original UTF-16 offsets',
        () async {
      final result = await findRegexMatches('👨foo\r\nfoo-bar\r\nfoo', r'^foo');
      expect(result.error, isNull);
      expect(
        result.matches.map((match) => (match.start, match.end)).toList(),
        [(7, 10), (16, 19)],
      );
    });

    test('explicit multiline expression normalizes CRLF and maps full ranges',
        () async {
      final result = await findRegexMatches('foo\r\nbar', r'foo\nbar');
      expect(result.error, isNull);
      expect(result.matches.map((match) => (match.start, match.end)).toList(),
          [(0, 8)]);
    });

    test('case and whole-word switches filter regex matches independently',
        () async {
      final result = await findRegexMatches(
        'Aba ab AB',
        'ab',
        caseSensitive: false,
        wholeWord: true,
      );
      expect(result.error, isNull);
      expect(result.matches.map((match) => (match.start, match.end)).toList(),
          [(4, 6), (7, 9)]);
    });

    test('selection scopes filter regex results without joining boundaries',
        () async {
      final crossing = await findRegexMatches(
        'foo\nbar',
        r'foo\nbar',
        scopes: const [TextMatchScope(0, 3), TextMatchScope(4, 7)],
      );
      expect(crossing.error, isNull);
      expect(crossing.matches, isEmpty);

      final scoped = await findRegexMatches(
        '👨foo\r\nbar',
        r'foo\nbar',
        scopes: const [TextMatchScope(2, 10)],
      );
      expect(scoped.error, isNull);
      expect(
        scoped.matches.map((match) => (match.start, match.end)).toList(),
        [(2, 10)],
      );
    });

    test('zero-width regex matches progress across UTF-16 text', () async {
      final result = await findRegexMatches('👨aa', r'(?=a)');
      expect(result.error, isNull);
      expect(result.matches.map((match) => (match.start, match.end)).toList(),
          [(2, 2), (3, 3)]);
    });

    test('invalid and overlong patterns return visible errors', () async {
      final invalid = await findRegexMatches('abc', '[');
      expect(invalid.error, isNotNull);
      final tooLong = await findRegexMatches(
        'abc',
        'a' * (maxFindRegexPatternUtf16 + 1),
      );
      expect(tooLong.error, contains('长度限制'));
    });

    test('match collection is capped and marks truncated results', () async {
      final result = await findRegexMatches('a' * 20001, 'a');
      expect(result.matches, hasLength(maxFindRegexMatches));
      expect(result.truncated, isTrue);
    });

    test('timed-out workers return without exposing partial results', () async {
      final result = await findRegexMatches(
        '${'a' * 20000}b',
        r'^(a+)+$',
        timeout: const Duration(milliseconds: 15),
      );
      expect(result.timedOut, isTrue);
      expect(result.matches, isEmpty);
    });

    test('superseded worker can be cancelled immediately', () async {
      final cancel = Completer<void>();
      final pending = findRegexMatches(
        'a' * 10000,
        r'^(a+)+$',
        cancelSignal: cancel.future,
      );
      cancel.complete();
      final result = await pending;
      expect(result.cancelled, isTrue);
      expect(result.matches, isEmpty);
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

    test('全字替换不改写单词内部的相同子串', () {
      final r = replaceAllMatches(
        'foo foobar foo_bar foo-bar\r\nfoo',
        'foo',
        'X',
        wholeWord: true,
      );
      expect(r.count, 3);
      expect(r.newText, 'X foobar foo_bar X-bar\r\nX');
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

    test('选区内全部替换保留范围外文本', () {
      final r = replaceAllMatches(
        'foo foo',
        'foo',
        'X',
        scopes: const [TextMatchScope(0, 3)],
      );
      expect(r.newText, 'X foo');
      expect(r.count, 1);
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

    test('linked workspace history clears both document frames together', () {
      final budget = UndoHistoryBudget(maxTotalEntries: 10, maxTotalChars: 100);
      final source = UndoStack(budget: budget);
      final target = UndoStack(budget: budget);
      const linkedIds = [31, 32];

      source.pushOperations(
        forward: const [TextOp.delete(2, 3)],
        inverse: const [TextOp.insert(2, 'abc')],
        caret: 2,
        coalesce: false,
        transactionId: 'move-1',
        linkedDocumentIds: linkedIds,
      );
      target.pushOperations(
        forward: const [TextOp.insert(4, 'abc')],
        inverse: const [TextOp.delete(4, 3)],
        caret: 4,
        coalesce: false,
        transactionId: 'move-1',
        linkedDocumentIds: linkedIds,
      );
      expect(budget.totalEntries, 2);

      source.dispose();

      expect(source.canUndo, isFalse);
      expect(target.canUndo, isFalse);
      expect(budget.totalEntries, 0);
      expect(budget.totalChars, 0);
      target.dispose();
    });

    test('linked redo is removed from both stacks when either side branches',
        () {
      final budget = UndoHistoryBudget(maxTotalEntries: 10, maxTotalChars: 100);
      final source = UndoStack(budget: budget);
      final target = UndoStack(budget: budget);
      const linkedIds = [41, 42];

      source.pushOperations(
        forward: const [TextOp.delete(0, 1)],
        inverse: const [TextOp.insert(0, 'x')],
        caret: 0,
        coalesce: false,
        transactionId: 'move-2',
        linkedDocumentIds: linkedIds,
      );
      target.pushOperations(
        forward: const [TextOp.insert(0, 'x')],
        inverse: const [TextOp.delete(0, 1)],
        caret: 1,
        coalesce: false,
        transactionId: 'move-2',
        linkedDocumentIds: linkedIds,
      );
      source.takeOperationUndo();
      target.takeOperationUndo();
      expect(source.canRedo, isTrue);
      expect(target.canRedo, isTrue);

      source.push(before: 'branched', caret: 0, coalesce: false);

      expect(source.canRedo, isFalse);
      expect(target.canRedo, isFalse);
      expect(source.canUndo, isTrue, reason: '新的分支帧仍保留');
      expect(budget.totalEntries, 1);
      source.dispose();
      target.dispose();
    });

    test('shared budget eviction removes a linked pair atomically', () {
      final budget = UndoHistoryBudget(maxTotalEntries: 1, maxTotalChars: 100);
      final source = UndoStack(budget: budget);
      final target = UndoStack(budget: budget);
      const linkedIds = [51, 52];

      budget.beginBatch();
      try {
        source.pushOperations(
          forward: const [TextOp.delete(0, 1)],
          inverse: const [TextOp.insert(0, 'x')],
          caret: 0,
          coalesce: false,
          transactionId: 'move-3',
          linkedDocumentIds: linkedIds,
        );
        target.pushOperations(
          forward: const [TextOp.insert(0, 'x')],
          inverse: const [TextOp.delete(0, 1)],
          caret: 1,
          coalesce: false,
          transactionId: 'move-3',
          linkedDocumentIds: linkedIds,
        );
      } finally {
        budget.endBatch();
      }

      expect(source.canUndo, isFalse);
      expect(target.canUndo, isFalse);
      expect(budget.totalEntries, 0);
      source.dispose();
      target.dispose();
    });
  });
}
