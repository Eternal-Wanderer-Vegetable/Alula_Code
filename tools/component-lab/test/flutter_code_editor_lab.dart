// 候选 3：flutter_code_editor 0.3.5（Apache-2.0/MIT，Akvelon，2025-09 后停更）
//
// 评测项：大文档载入/编辑耗时、widget 冒烟（CodeField 基于 TextField，
// 系统级 IME 支持由架构保证）。
// 注意：该包 13 个月未发布新版本——维护活跃度是主要风险项。
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('flutter_code_editor · controller 层大文档性能', () {
    test('10k 行：构造载入 / 重设', () {
      final doc = makeDoc(10000);
      final (loadMs, controller) = timedMs(() => CodeController(text: doc));
      expect(controller.text.length, doc.length);

      final mid = doc.length ~/ 2;
      final (editMs, _) = timedMs(() {
        controller.text = doc.substring(0, mid) + '// 插入行\n' + doc.substring(mid);
      });
      debugPrint(
        'flutter_code_editor 10k行: 载入=${loadMs.toStringAsFixed(1)}ms '
        '重设=${editMs.toStringAsFixed(1)}ms',
      );
      // CodeController 继承 TextEditingController：高亮分析在变更后异步触发，
      // 这里只验证不崩溃与内容正确。
    });

    test('5 万行压力：构造载入不崩溃', () {
      final doc = makeDoc(50000);
      final (loadMs, controller) = timedMs(() => CodeController(text: doc));
      debugPrint('flutter_code_editor 50k行: 载入=${loadMs.toStringAsFixed(1)}ms');
      expect(controller.text.length, doc.length);
    });
  });

  group('flutter_code_editor · widget 冒烟', () {
    // 已知缺陷（评测证据，2026-10-26 实测）：CodeField 内部为无虚拟化的
    // Column + 单子视口，100 行即垂直溢出 1856px，10k 行溢出 ~239,456px。
    // 渲染异常会使 widget 测试直接失败，故跳过并保留 controller 层测试。
    // 布局溢出日志：Column ← IntrinsicWidth ← Padding ← _SingleChildViewport
    //   （flutter_code_editor-0.3.5/lib/src/code_field/code_field.dart:373:14）
    testWidgets('大文档渲染评估（已知溢出缺陷，跳过）', (tester) async {
      final controller = CodeController(text: makeDoc(100));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: CodeField(controller: controller),
            ),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(TextField), findsOneWidget);
    }, skip: true); // 已知缺陷：无虚拟化渲染，100 行即溢出 1856px（评测报告有记录）
  });
}
