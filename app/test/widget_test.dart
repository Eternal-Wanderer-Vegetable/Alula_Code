// 工作台 UI 冒烟测试：应用能构建并进入 W1 工作台（标题栏 + 五大区），
// 核心加载成功时状态栏就绪；autoFolder 打开 fixture 工程后文件树自动装载根目录条目。
import 'dart:io';

import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 布局持久化指向临时文件：测试不读写真实 ~/.alula/layout.json
  late Directory tmp;
  late LayoutStore store;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('alula_widget_test');
    store = LayoutStore(path: '${tmp.path.replaceAll(r'\', '/')}/layout.json');
  });
  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  testWidgets('应用构建并显示工作台（W1 布局骨架）', (tester) async {
    await tester.pumpWidget(AlulaApp(layoutStore: store));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Alula Code'), findsWidgets); // 标题栏 + MaterialApp.title
    expect(find.text('文件'), findsOneWidget); // 标题栏菜单
    expect(find.byIcon(Icons.fact_check_outlined), findsOneWidget,
        reason: '编辑器动作区应有「校验一致性」');
    expect(find.byIcon(Icons.explore_outlined), findsOneWidget,
        reason: '活动栏应有资源管理器');
  });

  testWidgets('窗口控制按钮：windowControls 开启时渲染（W1-3）', (tester) async {
    await tester.pumpWidget(AlulaApp(layoutStore: store, windowControls: true));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byTooltip('最小化'), findsOneWidget);
    expect(find.byTooltip('最大化'), findsOneWidget);
    expect(find.byTooltip('关闭'), findsOneWidget);
  });

  testWidgets('autoFolder：文件树自动装载 fixture 工程根目录', (tester) async {
    // 依赖 app/native 的核心动态库与 fixture 目录存在（仓库内默认满足）
    await tester.pumpWidget(AlulaApp(
      autoFolder: r'E:\Alula_Code\tests\fixtures\rust-mini',
      layoutStore: store,
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
