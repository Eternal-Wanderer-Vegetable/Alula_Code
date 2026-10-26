// 工作台 UI 冒烟测试：应用能构建并进入 W1 工作台（标题栏 + 五大区），
// 核心加载成功时状态栏就绪；autoFolder 打开 fixture 工程后文件树自动装载根目录条目。
import 'dart:io';

import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:flutter/gestures.dart';
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

  testWidgets('W2-1 标签条：拖动排序与中键关闭', (tester) async {
    await tester.pumpWidget(AlulaApp(
      autoFolder: r'E:\Alula_Code\tests\fixtures\rust-mini',
      layoutStore: store,
    ));
    await tester.pump(const Duration(milliseconds: 500));

    // 打开两个文件（+ 未命名）→ 3 个标签；docId：未命名=1、Cargo.toml=2、main.rs=3
    await tester.tap(find.text('Cargo.toml'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('src'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('main.rs'));
    await tester.pump(const Duration(milliseconds: 300));

    double leftOf(String key) =>
        tester.getTopLeft(find.byKey(ValueKey(key))).dx;
    expect(leftOf('tab-1'), lessThan(leftOf('tab-2')),
        reason: '初始顺序：未命名 在 Cargo.toml 前');

    // 鼠标拖 tab-3（main.rs）到 tab-1（未命名）上 → 变为第一个
    await tester.drag(find.byKey(const ValueKey('tab-3')), const Offset(-260, 0),
        kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(leftOf('tab-3'), lessThan(leftOf('tab-1')),
        reason: '拖动排序后 main.rs 应在 未命名 前');
    expect(leftOf('tab-2'), greaterThan(leftOf('tab-1')),
        reason: 'Cargo.toml 排在 未命名 后（相对顺序保持）');

    // 中键关闭 tab-1（未命名）
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('tab-1'))),
      buttons: kMiddleMouseButton,
    );
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('tab-1')), findsNothing,
        reason: '中键应关闭标签');
    expect(find.byKey(const ValueKey('tab-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-3')), findsOneWidget);
  });

  testWidgets('W2-2 编辑器组：拆分获焦/文档入新组/清空自动并组', (tester) async {
    await tester.pumpWidget(AlulaApp(
      autoFolder: r'E:\Alula_Code\tests\fixtures\rust-mini',
      layoutStore: store,
    ));
    await tester.pump(const Duration(milliseconds: 500));

    // 组 1 打开 Cargo.toml
    await tester.tap(find.text('Cargo.toml'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('打开文件夹后，从文件树选择文件'), findsNothing);

    // 拆分 → 新组 editor-2 获焦（空占位出现），两组各有一个拆分按钮
    await tester.tap(find.byTooltip('拆分编辑器'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('打开文件夹后，从文件树选择文件'), findsOneWidget,
        reason: '新组应为空占位');
    expect(find.byTooltip('拆分编辑器'), findsNWidgets(2));

    // 文件打开进「焦点组」（新组）
    await tester.tap(find.text('src'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('main.rs'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('main.rs'), findsNWidgets(3),
        reason: '树 + 新组标签 + 面包屑各一处');
    expect(find.text('打开文件夹后，从文件树选择文件'), findsNothing);

    // 中键关闭新组唯一文档 → 组清空 → 自动摘除并组
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('tab-3'))),
      buttons: kMiddleMouseButton,
    );
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('tab-3')), findsNothing);
    expect(find.byTooltip('拆分编辑器'), findsOneWidget,
        reason: '空组应自动摘除');
    expect(find.text('打开文件夹后，从文件树选择文件'), findsNothing,
        reason: '回到单组且组 1 仍有 Cargo.toml');
  });

  testWidgets('W2-3 面包屑：路径段展示 + 点击文件夹段展开文件树', (tester) async {
    await tester.pumpWidget(AlulaApp(
      autoFolder: r'E:\Alula_Code\tests\fixtures\rust-mini',
      layoutStore: store,
    ));
    await tester.pump(const Duration(milliseconds: 500));

    // 展开并打开 main.rs → 面包屑出现 src › main.rs（工作区根以下，对标 VS Code）
    await tester.tap(find.text('src').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('main.rs').first);
    await tester.pump(const Duration(milliseconds: 300));

    final bc = find.byKey(const ValueKey('breadcrumb-editor'));
    expect(bc, findsOneWidget);
    expect(find.descendant(of: bc, matching: find.text('src')), findsOneWidget);
    expect(
        find.descendant(of: bc, matching: find.text('main.rs')),
        findsOneWidget);

    // 在文件树里收起 src → main.rs 只剩面包屑一处
    await tester.tap(find.text('src').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('main.rs'), findsNWidgets(2),
        reason: '树已收起，剩标签 + 面包屑两处');

    // 点击面包屑的 src 段 → 文件树重新展开到该目录
    await tester.tap(find.descendant(of: bc, matching: find.text('src')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('main.rs'), findsNWidgets(3),
        reason: '面包屑点击应展开文件树，main.rs 回到 树+标签+面包屑 三处');
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
