// 工作台 UI 冒烟测试：应用能构建并进入编辑页，核心加载成功时状态栏就绪；
// autoFolder 打开 fixture 工程后文件树自动装载根目录条目。
import 'package:alula_app/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('应用构建并显示工作台', (tester) async {
    await tester.pumpWidget(const AlulaApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Alula Code'), findsWidgets);
    expect(find.text('Phase 1'), findsOneWidget);
    expect(find.text('校验一致性'), findsOneWidget);
  });

  testWidgets('autoFolder：文件树自动装载 fixture 工程根目录', (tester) async {
    // 依赖 app/native 的核心动态库与 fixture 目录存在（仓库内默认满足）
    await tester.pumpWidget(const AlulaApp(
      autoFolder: r'E:\Alula_Code\tests\fixtures\rust-mini',
    ));
    // 越过 100ms 延迟触发 + listDir FFI + setState
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('rust-mini'), findsOneWidget,
        reason: '资源管理器标题应为打开的文件夹名');
    expect(find.text('Cargo.toml'), findsOneWidget,
        reason: '树根应列出 Cargo.toml');
    expect(find.text('src'), findsOneWidget, reason: '树根应列出 src 目录');
  });
}
