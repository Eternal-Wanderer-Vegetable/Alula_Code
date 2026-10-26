// WorkbenchGrid 交互测试：分割条拖拽改变区域尺寸、min 钳制、折叠/恢复。
// 不依赖 FFI（builders 注入占位内容），对应 docs/09 W1-2。
import 'package:alula_app/workbench/layout_controller.dart';
import 'package:alula_app/workbench/layout_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(WorkbenchLayout layout) => MaterialApp(
      home: Scaffold(
        body: WorkbenchGrid(layout: layout, builders: {
          for (final region in ['activity', 'sidebar', 'editor', 'panel'])
            region: (_) => ColoredBox(
                  key: ValueKey('probe-$region'),
                  color: Colors.blue,
                ),
        }),
      ),
    );

double _width(WidgetTester tester, String region) =>
    tester.getSize(find.byKey(ValueKey('probe-$region'))).width;

double _height(WidgetTester tester, String region) =>
    tester.getSize(find.byKey(ValueKey('probe-$region'))).height;

void main() {
  testWidgets('默认布局：活动栏固定宽，侧栏/编辑器按权重分配', (tester) async {
    final layout = WorkbenchLayout();
    await tester.pumpWidget(_host(layout));
    await tester.pump();

    // 测试窗口 800×600。activity 固定 44；侧栏 0.24/(0.24+0.76)*(800-44)（activity 与 sidebar 之间无分割条，
    // sidebar 与 editor 之间有 1 条 4px 分割条 → 弹性池 800-44-4=752）
    expect(_width(tester, 'activity'), 44);
    expect(_width(tester, 'sidebar'), closeTo(752 * 0.24, 1.5));
    expect(_width(tester, 'editor'),
        closeTo(752 - 752 * 0.24, 1.5));
  });

  testWidgets('拖拽分割条：侧栏变宽、编辑器等量变窄', (tester) async {
    final layout = WorkbenchLayout();
    await tester.pumpWidget(_host(layout));
    await tester.pump();

    final before = _width(tester, 'sidebar');
    await tester.drag(find.byKey(const ValueKey('wb-div-sidebar-editor')),
        const Offset(60, 0));
    await tester.pump();

    final after = _width(tester, 'sidebar');
    expect(after, closeTo(before + 60, 1.5));
    expect(
        _width(tester, 'editor'), closeTo(752 - after, 1.5),
        reason: '编辑器应等量收窄（其余兄弟像素不变）');
  });

  testWidgets('min 钳制：侧栏不会被拖到低于最小宽度', (tester) async {
    final layout = WorkbenchLayout();
    await tester.pumpWidget(_host(layout));
    await tester.pump();

    await tester.drag(find.byKey(const ValueKey('wb-div-sidebar-editor')),
        const Offset(-2000, 0));
    await tester.pump();

    expect(_width(tester, 'sidebar'), closeTo(170, 1.5),
        reason: 'sidebar minExtent=170');
    expect(_width(tester, 'editor'), closeTo(752 - 170, 1.5));
  });

  testWidgets('面板折叠/恢复：高度出现且可拖拽', (tester) async {
    // 默认布局各 min 之和 654px > 600px 默认测试窗口，会触发「无合法区间」
    // 保护；面板拖拽用例用 1200×900 窗口。
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final layout = WorkbenchLayout();
    await tester.pumpWidget(_host(layout));
    await tester.pump();

    expect(find.byKey(const ValueKey('probe-panel')), findsNothing,
        reason: '面板默认折叠');

    expect(layout.toggleRegion('panel'), isFalse);
    await tester.pump();
    expect(find.byKey(const ValueKey('probe-panel')), findsOneWidget);
    // 主列弹性池 = 900 - 4（panel 上方分割条）
    expect(_height(tester, 'panel'), closeTo((900 - 4) * 0.3, 1.5));
    expect(_height(tester, 'activity'), closeTo((900 - 4) * 0.7, 1.5),
        reason: '上半区（main-row 权重 0.7）');

    // 拖面板分割条：向下 60px → 面板变高
    final divFinder = find.byKey(const ValueKey('wb-div-main-row-panel'));
    await tester.drag(divFinder, const Offset(0, 60));
    await tester.pump();
    expect(_height(tester, 'panel'), closeTo((900 - 4) * 0.3 + 60, 2.0));

    expect(layout.toggleRegion('panel'), isTrue);
    await tester.pump();
    expect(find.byKey(const ValueKey('probe-panel')), findsNothing);
  });

  testWidgets('侧栏折叠/恢复（活动栏按钮路径）', (tester) async {
    final layout = WorkbenchLayout();
    await tester.pumpWidget(_host(layout));
    await tester.pump();

    expect(layout.toggleRegion('sidebar'), isTrue);
    await tester.pump();
    expect(find.byKey(const ValueKey('probe-sidebar')), findsNothing);
    expect(_width(tester, 'editor'), closeTo(756, 1.5),
        reason: '侧栏折叠后分割条一并消失，编辑器占满 800-44');

    expect(layout.toggleRegion('sidebar'), isFalse);
    await tester.pump();
    expect(_width(tester, 'sidebar'), closeTo(752 * 0.24, 1.5),
        reason: '恢复时应还原折叠前权重');
  });
}
