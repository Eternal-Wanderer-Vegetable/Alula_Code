// 候选 2：re_editor 0.10.0（MIT，Reqable 出品，虚拟化渲染）
//
// 评测项：大文档载入/编辑耗时、undo/redo 行为验证、widget 冒烟、
// API 面证据（补全模块 / 折叠 / 查找控制器均存在；多光标未见公开 API）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('re_editor · controller 层大文档性能', () {
    test('10k 行：fromText 载入 / 中部插入 / undo / redo', () {
      final doc = makeDoc(10000);

      final (loadMs, controller) = timedMs(
        () => CodeLineEditingController.fromText(doc),
      );
      expect(controller.text.length, doc.length);

      final mid = doc.length ~/ 2;
      final (editMs, _) = timedMs(() {
        controller.text = doc.substring(0, mid) + '// 插入行\n' + doc.substring(mid);
      });

      // undo/redo 是 controller 的公开方法——行为级验证
      final afterEdit = controller.text;
      final (undoMs, _) = timedMs(() => controller.undo());
      final textAfterUndo = controller.text;
      final (redoMs, _) = timedMs(() => controller.redo());
      final textAfterRedo = controller.text;

      debugPrint(
        're_editor 10k行: 载入=${loadMs.toStringAsFixed(1)}ms '
        '重设=${editMs.toStringAsFixed(1)}ms '
        'undo=${undoMs.toStringAsFixed(1)}ms redo=${redoMs.toStringAsFixed(1)}ms',
      );
      debugPrint(
        're_editor undo/redo 行为: undo还原=${textAfterUndo == doc} '
        'redo还原=${textAfterRedo == afterEdit}',
      );
      // 行为断言：undo 应还原到编辑前，redo 应恢复编辑后
      expect(textAfterUndo, doc, reason: 'undo 应还原重设前的全文');
      expect(textAfterRedo, afterEdit, reason: 'redo 应恢复编辑后的全文');

      controller.dispose();
    });

    test('5 万行压力：fromText 载入不崩溃', () {
      final doc = makeDoc(50000);
      final (loadMs, controller) = timedMs(
        () => CodeLineEditingController.fromText(doc),
      );
      debugPrint('re_editor 50k行: 载入=${loadMs.toStringAsFixed(1)}ms');
      expect(controller.text.length, doc.length);
      controller.dispose();
    });
  });

  group('re_editor · widget 冒烟（10k 行）', () {
    testWidgets('CodeEditor 可构建并显示内容', (tester) async {
      final doc = makeDoc(10000);
      final controller = CodeLineEditingController.fromText(doc);
      final buildSw = Stopwatch()..start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: CodeEditor(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 5));
      buildSw.stop();
      debugPrint('re_editor widget 首帧构建: ${buildSw.elapsedMilliseconds}ms');
      expect(find.byType(CodeEditor), findsOneWidget);
      controller.dispose();
    });
  });
}
