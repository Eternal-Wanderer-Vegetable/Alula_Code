// 工作台 UI 冒烟测试：应用能构建并进入 W1 工作台（标题栏 + 五大区），
// 核心加载成功时状态栏就绪；autoFolder 打开 fixture 工程后文件树自动装载根目录条目。
import 'dart:io';

import 'package:alula_app/main.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:alula_app/workbench/session_store.dart';
import 'helpers/temp_repo.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';


/// 带修饰键的按键（tester.sendKeyEvent 在本 SDK 版本无修饰键参数）。
Future<void> pressChord(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
  bool shift = false,
}) async {
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

/// 仓库相对的 fixture 工程（CI 是 Linux，不能写死 Windows 绝对路径）。
final fixtureRoot =
    '${Directory.current.parent.path}/tests/fixtures/rust-mini';

void main() {
  // 布局与会话 journal 都指向临时文件：测试不读写真实 ~/.alula/*
  late Directory tmp;
  late LayoutStore store;
  late SessionStore session;
  late KeybindingsStore keybindings;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('alula_widget_test');
    final base = tmp.path.replaceAll(r'\', '/');
    store = LayoutStore(path: '$base/layout.json');
    session = SessionStore(path: '$base/session.json');
    keybindings = KeybindingsStore(path: '$base/keybindings.json');
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
    await tester.pumpWidget(AlulaApp(
      layoutStore: store,
      sessionStore: session,
      keybindingsStore: keybindings,
      windowControls: true,
    ));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byTooltip('最小化'), findsOneWidget);
    expect(find.byTooltip('最大化'), findsOneWidget);
    expect(find.byTooltip('关闭'), findsOneWidget);
  });

  testWidgets('W2-1 标签条：拖动排序与中键关闭', (tester) async {
    await tester.pumpWidget(AlulaApp(
      autoFolder: fixtureRoot,
      layoutStore: store,
      sessionStore: session,
      keybindingsStore: keybindings,
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
      autoFolder: fixtureRoot,
      layoutStore: store,
      sessionStore: session,
      keybindingsStore: keybindings,
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
      autoFolder: fixtureRoot,
      layoutStore: store,
      sessionStore: session,
      keybindingsStore: keybindings,
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

  testWidgets('W2-4 journal：重启恢复标签与未保存内容', (tester) async {
    await tester.pumpWidget(AlulaApp(
      autoFolder: fixtureRoot,
      layoutStore: store,
      sessionStore: session,
      keybindingsStore: keybindings,
    ));
    await tester.pump(const Duration(milliseconds: 500));

    // 打开 Cargo.toml 并做未保存编辑
    await tester.tap(find.text('Cargo.toml'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), '// dirty edit\n');
    await tester.pump(const Duration(milliseconds: 700)); // 越过 500ms 防抖

    // 卸载（dispose 冲写 journal）→ 「重启」
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(AlulaApp(
      autoFolder: fixtureRoot,
      layoutStore: store,
      sessionStore: session,
      keybindingsStore: keybindings,
    ));
    await tester.pump(const Duration(milliseconds: 600));

    // 标签恢复：树 + 标签 + 面包屑 三处
    expect(find.text('Cargo.toml'), findsNWidgets(3),
        reason: '重启后 Cargo.toml 应自动恢复打开');
    // 未保存内容恢复（脏标记不跨重启保留，内容优先）
    final editor = tester.widget<TextField>(find.byType(TextField));
    expect(editor.controller!.text, contains('// dirty edit'),
        reason: '未保存编辑内容应从 journal 恢复');
  });

  testWidgets('W3-1 命令面板：Ctrl+Shift+P 打开 → 筛选 → 回车执行拆分',
      (tester) async {
    await tester.pumpWidget(AlulaApp(
      autoFolder: fixtureRoot,
      layoutStore: store,
      sessionStore: session,
      keybindingsStore: keybindings,
    ));
    await tester.pump(const Duration(milliseconds: 500));

    await pressChord(tester, LogicalKeyboardKey.keyP, control: true, shift: true);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('quick-input')), findsOneWidget);

    // 输入过滤：'拆分' 应命中「编辑器: 拆分编辑器」
    await tester.enterText(
        find.descendant(
            of: find.byKey(const ValueKey('quick-input')),
            matching: find.byType(TextField)),
        '拆分');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('qi-编辑器: 拆分编辑器')), findsOneWidget);

    // 回车执行 → 出现两个编辑器组（两个拆分按钮）
    await pressChord(tester, LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('quick-input')), findsNothing,
        reason: '执行后面板关闭');
    expect(find.byTooltip('拆分编辑器'), findsNWidgets(2));
  });

  testWidgets('W3-1 快速打开：Ctrl+P → 筛选文件 → 回车打开', (tester) async {
    await tester.pumpWidget(AlulaApp(
      autoFolder: fixtureRoot,
      layoutStore: store,
      sessionStore: session,
      keybindingsStore: keybindings,
    ));
    await tester.pump(const Duration(milliseconds: 500));

    await pressChord(tester, LogicalKeyboardKey.keyP, control: true);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('quick-input')), findsOneWidget);

    await tester.enterText(
        find.descendant(
            of: find.byKey(const ValueKey('quick-input')),
            matching: find.byType(TextField)),
        'main');
    await tester.pump(const Duration(milliseconds: 200));
    await pressChord(tester, LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('quick-input')), findsNothing);
    expect(find.text('main.rs'), findsNWidgets(2),
        reason: '标签 + 面包屑 两处（快速打开不展开文件树，树里没有 main.rs）');
  });

  testWidgets('W3-2 keybindings.json：重绑定与移除', (tester) async {
    File(keybindings.resolvePath()).writeAsStringSync(
        '[{"key":"ctrl+i","command":"view.quickOpen"},'
        '{"key":"ctrl+p","command":"-view.quickOpen"}]');
    await tester.pumpWidget(AlulaApp(
      autoFolder: fixtureRoot,
      layoutStore: store,
      sessionStore: session,
      keybindingsStore: keybindings,
    ));
    await tester.pump(const Duration(milliseconds: 500));

    // 旧键位 Ctrl+P 已被移除：不再打开面板
    await pressChord(tester, LogicalKeyboardKey.keyP, control: true);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('quick-input')), findsNothing,
        reason: '-command 移除后 Ctrl+P 不应触发');

    // 新键位 Ctrl+I 打开快速打开
    await pressChord(tester, LogicalKeyboardKey.keyI, control: true);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('quick-input')), findsOneWidget,
        reason: '重绑定后的 Ctrl+I 应生效');
  });

  testWidgets('feat-010 撤销/重做/查找替换端到端（含 FFI 一致性）', (tester) async {
    await tester.pumpWidget(AlulaApp(
      autoFolder: fixtureRoot,
      layoutStore: store,
      sessionStore: session,
      keybindingsStore: keybindings,
    ));
    await tester.pump(const Duration(milliseconds: 500));

    // 打开 Cargo.toml 并编辑
    await tester.tap(find.text('Cargo.toml'));
    await tester.pump(const Duration(milliseconds: 300));
    final editor = tester.widget<TextField>(find.byType(TextField));
    final before = editor.controller!.text;
    await tester.enterText(find.byType(TextField), '${before}XX');
    await tester.pump(const Duration(milliseconds: 100));

    // 撤销：回退到编辑前
    await pressChord(tester, LogicalKeyboardKey.keyZ, control: true);
    await tester.pump(const Duration(milliseconds: 200));
    expect(
        tester
            .widget<TextField>(find.byType(TextField).first)
            .controller!
            .text,
        before,
        reason: 'Ctrl+Z 应回退到编辑前');

    // 重做：恢复编辑（Ctrl+Shift+Z）
    await pressChord(tester, LogicalKeyboardKey.keyZ,
        control: true, shift: true);
    await tester.pump(const Duration(milliseconds: 200));
    expect(
        tester
            .widget<TextField>(find.byType(TextField).first)
            .controller!
            .text,
        '${before}XX',
        reason: 'Ctrl+Shift+Z 应恢复编辑');

    // 查找替换：Ctrl+H 打开（含替换字段）→ 全部替换 workspace → WORKSPACE
    await pressChord(tester, LogicalKeyboardKey.keyH, control: true);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('find-bar')), findsOneWidget);

    final bar = find.byKey(const ValueKey('find-bar'));
    await tester.enterText(
        find.descendant(of: bar, matching: find.byType(TextField)).first,
        'workspace');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.descendant(of: bar, matching: find.textContaining('/')),
        findsOneWidget,
        reason: '应有匹配计数（x/y）');

    await tester.enterText(
        find.descendant(of: bar, matching: find.byType(TextField)).at(1),
        'WORKSPACE');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('全部替换'));
    await tester.pump(const Duration(milliseconds: 200));

    final after = tester
        .widget<TextField>(find.byType(TextField).first)
        .controller!
        .text;
    expect(after, contains('WORKSPACE'));
    expect(after.contains('workspace'), isFalse,
        reason: '区分大小写模式下 workspace 应全部被替换');

    // FFI 一致性：撤销全部替换 → 文本恢复（经 diff→FFI 反向同步）。
    // 先把焦点点回编辑器（替换输入框的原生 undo 只管自己的文本）。
    await tester.tap(find.byType(TextField).first);
    await tester.pump(const Duration(milliseconds: 100));
    await pressChord(tester, LogicalKeyboardKey.keyZ, control: true);
    await tester.pump(const Duration(milliseconds: 200));
    expect(
        tester
            .widget<TextField>(find.byType(TextField).first)
            .controller!
            .text,
        '${before}XX',
        reason: '撤销应恢复替换前文本（Rust 侧经 diff 反向同步）');
  });

  testWidgets('feat-git 面板：视图切换/状态/暂存/提交', (tester) async {
    // 真实 git 子进程需要 runAsync（widget 测试默认假 async zone）
    await tester.runAsync(() async {
      final repo = await createTempRepo(
          prefix: 'alula_git_widget', extraFiles: {'hello.py': 'print(1)\n'});
      addTearDown(() async {
        if (repo.existsSync()) await repo.delete(recursive: true);
      });
      await tester.pumpWidget(AlulaApp(
        autoFolder: repo.path,
        layoutStore: store,
        sessionStore: session,
        keybindingsStore: keybindings,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await tester.pump();

      // 活动栏切到源代码管理
      await tester.tap(find.byTooltip('源代码管理'));
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.text('源代码管理'), findsWidgets);
      expect(find.text('main'), findsOneWidget, reason: '分支名展示');
      expect(find.text('hello.py'), findsOneWidget, reason: '未跟踪文件列出');
      expect(find.text('更改（1）'), findsOneWidget);

      // 暂存 hello.py
      await tester.tap(find.byTooltip('暂存'));
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('暂存的更改（1）'), findsOneWidget);

      // 提交
      await tester.enterText(
          find.byKey(const ValueKey('commit-input')), 'test: widget 提交');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('commit-button')));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.text('工作区干净'), findsOneWidget, reason: '提交后无更改');

      // 真 git 验证：仓库应有两个提交
      final log = await Process.run('git', ['log', '--oneline'],
          workingDirectory: repo.path);
      final lines = (log.stdout as String)
          .split('\n')
          .where((l) => l.isNotEmpty)
          .length;
      expect(lines, 2);
    });
  });

  testWidgets('feat-search 搜索视图：Ctrl+Shift+F/流式结果/点击跳行', (tester) async {
    await tester.runAsync(() async {
      final repo = await createTempRepo(
          prefix: 'alula_search_widget',
          extraFiles: {'src/needle.py': 'find the needle here\n'});
      addTearDown(() async {
        if (repo.existsSync()) await repo.delete(recursive: true);
      });
      await tester.pumpWidget(AlulaApp(
        autoFolder: repo.path,
        layoutStore: store,
        sessionStore: session,
        keybindingsStore: keybindings,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await tester.pump();

      // 键位 Ctrl+Shift+F 切到搜索视图
      await pressChord(tester, LogicalKeyboardKey.keyF, control: true, shift: true);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.byKey(const ValueKey('search-input')), findsOneWidget);

      // 输入并提交（onSubmitted）
      await tester.enterText(
          find.byKey(const ValueKey('search-input')), 'needle');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await tester.pump();

      expect(find.textContaining('find the needle here'), findsOneWidget,
          reason: '命中行文本应出现在结果列表');
      expect(find.textContaining('needle.py'), findsOneWidget,
          reason: '文件名展示');

      // 点击命中 → 打开文件
      await tester.tap(find.byKey(const ValueKey('search-hit-0')));
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();

      final editor =
          tester.widget<TextField>(find.byType(TextField).last);
      expect(editor.controller!.text, contains('find the needle here'),
          reason: '命中文件应在编辑器打开（.last 排除侧栏搜索框）');
      expect(editor.controller!.selection.baseOffset, 0,
          reason: '命中在第 1 行，光标应跳到行首');
    });
  });

  testWidgets('autoFolder：文件树自动装载 fixture 工程根目录', (tester) async {
    // 依赖 app/native 的核心动态库与 fixture 目录存在（仓库内默认满足）
    await tester.pumpWidget(AlulaApp(
      autoFolder: fixtureRoot,
      layoutStore: store,
      sessionStore: session,
      keybindingsStore: keybindings,
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
