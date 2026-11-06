import 'dart:ui' show CheckedState, SemanticsAction;

import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/title_bar.dart';
import 'package:alula_app/workbench/window_chrome_configuration.dart';
import 'package:alula_app/workbench/window_chrome_driver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  late CommandService commands;
  late _FakeWindowChromeDriver window;
  late _RecordingPlatformMenuDelegate platformMenus;
  late PlatformMenuDelegate originalPlatformMenuDelegate;

  setUp(() {
    commands = CommandService();
    window = _FakeWindowChromeDriver();
    platformMenus = _RecordingPlatformMenuDelegate();
    originalPlatformMenuDelegate = WidgetsBinding.instance.platformMenuDelegate;
    WidgetsBinding.instance.platformMenuDelegate = platformMenus;
  });

  tearDown(() {
    WidgetsBinding.instance.platformMenuDelegate = originalPlatformMenuDelegate;
    commands.dispose();
  });

  testWidgets(
      'Linux custom title bar renders bounded controls and routes actions',
      (tester) async {
    await tester.pumpWidget(_titleBarApp(
      commands: commands,
      window: window,
      configuration:
          WindowChromeConfiguration.forPlatform(TargetPlatform.linux),
    ));
    await tester.pump();

    expect(tester.getSize(find.byType(AlulaTitleBar)).height, 35);
    expect(find.byTooltip('最小化'), findsOneWidget);
    expect(find.byTooltip('最大化'), findsOneWidget);
    expect(find.byTooltip('关闭'), findsOneWidget);

    await tester.tap(find.byTooltip('最小化'));
    await tester.pump();
    expect(window.minimizeCalls, 1);

    await tester.tap(find.byTooltip('最大化'));
    await tester.pumpAndSettle();
    expect(window.maximizeCalls, 1);
    expect(find.byTooltip('向下还原'), findsOneWidget);

    await tester.tap(find.byTooltip('向下还原'));
    await tester.pumpAndSettle();
    expect(window.unmaximizeCalls, 1);
    expect(find.byTooltip('最大化'), findsOneWidget);
  });

  testWidgets('macOS custom title bar leaves caption controls to the OS',
      (tester) async {
    for (final (id, title) in [
      ('view.toggleSidebar', '切换侧栏'),
      ('view.togglePanel', '切换面板'),
    ]) {
      commands.register(Command(
        id: id,
        title: title,
        category: '查看',
        run: () async {},
      ));
    }
    await tester.pumpWidget(_titleBarApp(
      commands: commands,
      window: window,
      configuration:
          WindowChromeConfiguration.forPlatform(TargetPlatform.macOS),
      layoutControlsBuilder: () => const [
        TitleMenuItem('侧栏', commandId: 'view.toggleSidebar'),
        TitleMenuItem('面板', commandId: 'view.togglePanel'),
      ],
    ));

    expect(find.text('Alula Code'), findsOneWidget);
    expect(find.byTooltip('最小化'), findsNothing);
    expect(find.byTooltip('最大化'), findsNothing);
    expect(find.byTooltip('关闭'), findsNothing);
    expect(find.byType(PlatformMenuBar), findsOneWidget);
    expect(find.byType(MenuBar), findsNothing);
    expect(
        find.byKey(const ValueKey('layout-controls-control')), findsOneWidget);
    expect(
      _allPlatformMenuItems(platformMenus.menus)
          .where((item) => item.label == '布局控制' || item.label == '侧栏'),
      isEmpty,
      reason: 'macOS 原生菜单栏不重复绘制标题栏布局控制',
    );
    expect(tester.getSize(find.byType(AlulaTitleBar)).height, 35);
  });

  testWidgets('title bar refreshes the visible and native window title',
      (tester) async {
    const firstTitle = '● note.txt - sample - Alula Code';
    const nextTitle = 'saved.txt - sample - Alula Code';
    await tester.pumpWidget(_titleBarApp(
      commands: commands,
      window: window,
      configuration:
          WindowChromeConfiguration.forPlatform(TargetPlatform.linux),
      windowTitle: firstTitle,
    ));
    await tester.pump();

    expect(find.text(firstTitle), findsOneWidget);
    expect(window.windowTitles, [firstTitle]);

    await tester.pumpWidget(_titleBarApp(
      commands: commands,
      window: window,
      configuration:
          WindowChromeConfiguration.forPlatform(TargetPlatform.linux),
      windowTitle: nextTitle,
    ));
    await tester.pump();

    expect(find.text(nextTitle), findsOneWidget);
    expect(window.windowTitles, [firstTitle, nextTitle]);
  });

  testWidgets('custom window title is a keyboard-accessible Command Center',
      (tester) async {
    var paletteCalls = 0;
    const title = '● notes.md - sample - Alula Code';
    commands.register(Command(
      id: 'view.commandPalette',
      title: '命令面板',
      category: '查看',
      shortcut: 'Ctrl+Shift+P',
      run: () async {
        paletteCalls++;
      },
    ));
    await tester.pumpWidget(_titleBarApp(
      commands: commands,
      window: window,
      configuration:
          WindowChromeConfiguration.forPlatform(TargetPlatform.linux),
      windowTitle: title,
    ));
    await tester.pump();

    final commandCenter = find.byKey(const ValueKey('command-center'));
    final commandCenterControl =
        find.byKey(const ValueKey('command-center-control'));
    expect(find.text(title), findsOneWidget);
    final semantics = tester.getSemantics(commandCenter).getSemanticsData();
    expect(semantics.label, contains('命令中心'));
    expect(semantics.label, contains(title));
    expect(semantics.flagsCollection.isButton, isTrue);
    expect(semantics.hasAction(SemanticsAction.tap), isTrue);
    expect(commands.isEnabled('view.commandPalette'), isTrue);

    await tester.tap(commandCenterControl);
    await tester.pumpAndSettle();
    expect(tester.widget<InkWell>(commandCenterControl).onTap, isNotNull);
    expect(window.dragCalls, 0);
    expect(paletteCalls, 1);

    final focusNode = tester.widget<InkWell>(commandCenterControl).focusNode!;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(focusNode.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(paletteCalls, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(paletteCalls, 3);
  });

  testWidgets('custom layout controls reflect command visibility and state',
      (tester) async {
    var sidebarCalls = 0;
    var panelCalls = 0;
    var sidebarVisible = true;
    commands.register(Command(
      id: 'view.toggleSidebar',
      title: '切换侧栏',
      category: '查看',
      run: () async => sidebarCalls++,
    ));
    commands.register(Command(
      id: 'view.togglePanel',
      title: '切换面板',
      category: '查看',
      enablement: 'panelToggleEnabled',
      run: () async => panelCalls++,
    ));
    commands.register(Command(
      id: 'view.hiddenLayoutAction',
      title: '隐藏布局动作',
      category: '查看',
      when: 'hiddenLayoutActionVisible',
      run: () async {},
    ));

    List<TitleMenuItem> layoutControls() => [
          TitleMenuItem(
            '侧栏',
            commandId: 'view.toggleSidebar',
            checked: sidebarVisible,
          ),
          const TitleMenuItem.separator(),
          const TitleMenuItem('面板', commandId: 'view.togglePanel'),
          const TitleMenuItem(
            '隐藏布局动作',
            commandId: 'view.hiddenLayoutAction',
          ),
        ];

    commands.context.setValue('panelToggleEnabled', false);
    await tester.pumpWidget(_titleBarApp(
      commands: commands,
      window: window,
      configuration:
          WindowChromeConfiguration.forPlatform(TargetPlatform.linux),
      layoutControlsBuilder: layoutControls,
    ));

    final control = find.byKey(const ValueKey('layout-controls-control'));
    expect(control, findsOneWidget);
    expect(find.byTooltip('布局控制'), findsOneWidget);
    final semantics = tester
        .getSemantics(find.byKey(const ValueKey('layout-controls')))
        .getSemanticsData();
    expect(semantics.label, '布局控制');
    expect(semantics.hint, '打开侧栏与面板布局菜单');
    expect(semantics.hasAction(SemanticsAction.tap), isTrue);

    await tester.tap(control);
    await tester.pumpAndSettle();
    final sidebarItem = tester.widget<MenuItemButton>(
      find.byKey(const ValueKey('layout-control-view.toggleSidebar')),
    );
    expect(sidebarItem.enabled, isTrue);
    expect(sidebarItem.leadingIcon, isA<Icon>());
    final sidebarSemantics =
        tester.getSemantics(find.byKey(sidebarItem.key!)).getSemanticsData();
    expect(
      sidebarSemantics.flagsCollection.isChecked,
      CheckedState.isTrue,
    );
    final panelItem = tester.widget<MenuItemButton>(
      find.byKey(const ValueKey('layout-control-view.togglePanel')),
    );
    expect(panelItem.enabled, isFalse);
    expect(find.text('隐藏布局动作'), findsNothing);

    await tester.tap(find.byKey(
      const ValueKey('layout-control-view.toggleSidebar'),
    ));
    await tester.pumpAndSettle();
    expect(sidebarCalls, 1);
    expect(panelCalls, 0);

    sidebarVisible = false;
    await tester.tap(control);
    await tester.pumpAndSettle();
    final updatedSidebarItem = tester.widget<MenuItemButton>(
      find.byKey(const ValueKey('layout-control-view.toggleSidebar')),
    );
    expect(updatedSidebarItem.leadingIcon, isA<SizedBox>());

    await tester.pumpWidget(_titleBarApp(
      commands: commands,
      window: window,
      configuration: const WindowChromeConfiguration(
        mode: WorkbenchTitleBarMode.native,
        targetPlatform: TargetPlatform.linux,
      ),
      layoutControlsBuilder: layoutControls,
    ));
    expect(find.byKey(const ValueKey('layout-controls-control')), findsNothing);
  });

  testWidgets('layout controls open and return focus with keyboard input',
      (tester) async {
    var selected = '';
    for (final (id, title) in [
      ('view.toggleSidebar', '侧栏'),
      ('view.togglePanel', '面板'),
    ]) {
      commands.register(Command(
        id: id,
        title: title,
        category: '查看',
        run: () async => selected = title,
      ));
    }

    await tester.pumpWidget(_titleBarApp(
      commands: commands,
      window: window,
      configuration:
          WindowChromeConfiguration.forPlatform(TargetPlatform.linux),
      layoutControlsBuilder: () => const [
        TitleMenuItem('侧栏', commandId: 'view.toggleSidebar'),
        TitleMenuItem('面板', commandId: 'view.togglePanel'),
      ],
    ));
    final control = tester.widget<IconButton>(
      find.byKey(const ValueKey('layout-controls-control')),
    );
    final focusNode = control.focusNode!;

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('layout-control-view.toggleSidebar')),
        findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('layout-control-view.toggleSidebar')),
        findsNothing);
    expect(focusNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, '面板');
    expect(focusNode.hasFocus, isTrue);
  });

  testWidgets('macOS native menu routes visible commands and live state',
      (tester) async {
    final executed = <String>[];
    commands.register(Command(
      id: 'workbench.action.files.newUntitledFile',
      title: '新建文本文件',
      category: '文件',
      shortcut: 'Meta+N',
      run: () async => executed.add('new'),
    ));
    commands.register(Command(
      id: 'file.save',
      title: '保存',
      category: '文件',
      shortcut: 'Meta+S',
      enablement: 'editorActive',
      run: () async => executed.add('save'),
    ));
    commands.register(Command(
      id: 'file.workspaceOnly',
      title: '工作区动作',
      category: '文件',
      when: 'workspaceOpen',
      run: () async => executed.add('workspace'),
    ));
    commands.register(Command(
      id: 'view.toggleSidebar',
      title: '切换侧栏',
      category: '查看',
      run: () async => executed.add('sidebar'),
    ));
    commands.register(Command(
      id: 'help.about',
      title: '关于 Alula Code',
      category: '帮助',
      run: () async => executed.add('about'),
    ));

    await tester.pumpWidget(_titleBarApp(
      commands: commands,
      window: window,
      configuration:
          WindowChromeConfiguration.forPlatform(TargetPlatform.macOS),
      menus: const [
        (
          '文件(&&F)',
          [
            TitleMenuItem(
              '新建文本文件(&&N)    Meta+N',
              commandId: 'workbench.action.files.newUntitledFile',
            ),
            TitleMenuItem.separator(),
            TitleMenuItem('保存(&&S)    Meta+S', commandId: 'file.save'),
            TitleMenuItem('工作区动作(&&W)', commandId: 'file.workspaceOnly'),
          ],
        ),
        (
          '查看(&&V)',
          [
            TitleMenuItem.submenu('外观(&&A)', children: [
              TitleMenuItem('切换侧栏(&&S)', commandId: 'view.toggleSidebar'),
            ]),
          ],
        ),
        (
          '帮助(&&H)',
          [TitleMenuItem('关于 Alula Code(&&A)', commandId: 'help.about')],
        ),
      ],
    ));
    await tester.pump();

    expect(find.byType(PlatformMenuBar), findsOneWidget);
    expect(find.byType(MenuBar), findsNothing);
    expect(
      platformMenus.menus.whereType<PlatformMenu>().map((menu) => menu.label),
      ['Alula Code', '文件', '查看'],
    );

    var nativeItems = _allPlatformMenuItems(platformMenus.menus).toList();
    final newFile = nativeItems.singleWhere(
      (item) => item.label == '新建文本文件',
    );
    expect(newFile.shortcut, isA<SingleActivator>());
    expect((newFile.shortcut! as SingleActivator).meta, isTrue);
    expect(nativeItems.where((item) => item.label == '工作区动作'), isEmpty);
    expect(
      nativeItems.singleWhere((item) => item.label == '保存').onSelected,
      isNull,
    );
    expect(nativeItems.where((item) => item.label == '关于 Alula Code'),
        hasLength(1));

    newFile.onSelected!();
    await tester.pump();
    expect(executed, ['new']);

    commands.context.setValue('workspaceOpen', true);
    commands.context.setValue('editorActive', true);
    await tester.pump();
    nativeItems = _allPlatformMenuItems(platformMenus.menus).toList();
    expect(nativeItems.where((item) => item.label == '工作区动作'), hasLength(1));
    expect(
      nativeItems.singleWhere((item) => item.label == '保存').onSelected,
      isNotNull,
    );
    expect(
      nativeItems.where((item) => item.label == '切换侧栏'),
      hasLength(1),
    );
    nativeItems
        .singleWhere((item) => item.label == '关于 Alula Code')
        .onSelected!();
    await tester.pump();
    expect(executed.last, 'about');
  });

  testWidgets('macOS native title bar omits client menu row and quits cleanly',
      (tester) async {
    var closeRequested = 0;
    commands.register(Command(
      id: 'help.about',
      title: '关于 Alula Code',
      category: '帮助',
      run: () async {},
    ));
    await tester.pumpWidget(_titleBarApp(
      commands: commands,
      window: window,
      configuration: const WindowChromeConfiguration(
        mode: WorkbenchTitleBarMode.native,
        targetPlatform: TargetPlatform.macOS,
      ),
      onCloseRequested: () => closeRequested++,
      menus: const [
        ('文件(&&F)', [TitleMenuItem('保存(&&S)', commandId: 'file.save')]),
      ],
    ));

    expect(find.byType(PlatformMenuBar), findsOneWidget);
    expect(tester.getSize(find.byType(AlulaTitleBar)).height, 0);
    final quit = _allPlatformMenuItems(platformMenus.menus)
        .singleWhere((item) => item.label == 'Quit Alula Code');
    quit.onSelected!();
    await tester.pumpAndSettle();

    expect(closeRequested, 1);
    expect(window.preventCloseValues, [false]);
    expect(window.closeCalls, 1);
  });

  testWidgets('native title bar keeps menu row and close handling',
      (tester) async {
    var closeRequested = 0;
    await tester.pumpWidget(_titleBarApp(
      commands: commands,
      window: window,
      configuration: const WindowChromeConfiguration(
        mode: WorkbenchTitleBarMode.native,
        targetPlatform: TargetPlatform.windows,
      ),
      menus: const [
        ('文件', [TitleMenuItem('打开文件夹', commandId: 'file.openFolder')]),
      ],
      onCloseRequested: () => closeRequested++,
    ));

    expect(find.text('Alula Code'), findsNothing);
    expect(find.byKey(const ValueKey('command-center')), findsNothing);
    expect(find.text('文件'), findsOneWidget);
    expect(tester.getSize(find.byType(AlulaTitleBar)).height, 35);
    expect(find.byTooltip('最小化'), findsNothing);
    expect(window.listeners, hasLength(1));

    window.emitClose();
    await tester.pump();
    await tester.pump();

    expect(closeRequested, 1);
    expect(window.preventCloseValues, [false]);
    expect(window.closeCalls, 1);
  });

  testWidgets('double-clicking the free title-bar area toggles maximize state',
      (tester) async {
    await tester.pumpWidget(_titleBarApp(
      commands: commands,
      window: window,
      configuration:
          WindowChromeConfiguration.forPlatform(TargetPlatform.linux),
    ));

    final dragRegion = find.byKey(const ValueKey('titlebar-drag-region'));
    await _doubleTap(tester, dragRegion);
    await tester.pumpAndSettle();
    expect(window.maximizeCalls, 1);

    await _doubleTap(tester, dragRegion);
    await tester.pumpAndSettle();
    expect(window.unmaximizeCalls, 1);
  });

  testWidgets('drag region moves the window while menu interaction does not',
      (tester) async {
    var commandCalls = 0;
    commands.register(Command(
      id: 'test.action',
      title: 'Run test action',
      category: 'Test',
      run: () async {
        commandCalls++;
      },
    ));
    await tester.pumpWidget(MaterialApp(
      home: WindowChromeConfigurationScope(
        configuration:
            WindowChromeConfiguration.forPlatform(TargetPlatform.linux),
        child: Scaffold(
          body: AlulaTitleBar(
            commands: commands,
            menus: const [
              ('文件', [TitleMenuItem('运行', commandId: 'test.action')]),
            ],
            windowControls: true,
            windowChromeDriver: window,
          ),
        ),
      ),
    ));

    await tester.drag(find.byKey(const ValueKey('titlebar-drag-region')),
        const Offset(30, 0));
    expect(window.dragCalls, 1);

    await tester.tap(find.text('文件'));
    await tester.pumpAndSettle();
    expect(window.dragCalls, 1);
    await tester.tap(find.text('运行'));
    await tester.pumpAndSettle();
    expect(commandCalls, 1);
    expect(window.dragCalls, 1);
  });

  testWidgets('nested menu filters commands and routes action arguments',
      (tester) async {
    final executedArguments = <Object?>[];
    var disabledCalls = 0;
    commands.register(Command(
      id: 'view.toggleSidebar',
      title: 'Toggle sidebar',
      category: 'View',
      run: () async {},
      runWithArguments: (arguments) async {
        executedArguments.add(arguments);
      },
    ));
    commands.register(Command(
      id: 'view.hiddenAction',
      title: 'Hidden action',
      category: 'View',
      when: 'menuItemVisible',
      run: () async {},
    ));
    commands.register(Command(
      id: 'view.disabledAction',
      title: 'Disabled action',
      category: 'View',
      enablement: 'menuActionEnabled',
      run: () async {
        disabledCalls++;
      },
    ));
    await tester.pumpWidget(_titleBarApp(
      commands: commands,
      window: window,
      configuration:
          WindowChromeConfiguration.forPlatform(TargetPlatform.linux),
      menus: const [
        (
          '查看',
          [
            TitleMenuItem.submenu('外观', children: [
              TitleMenuItem.separator(),
              TitleMenuItem('切换侧栏',
                  commandId: 'view.toggleSidebar', arguments: 'primary'),
              TitleMenuItem.separator(),
              TitleMenuItem('隐藏动作', commandId: 'view.hiddenAction'),
              TitleMenuItem('禁用动作', commandId: 'view.disabledAction'),
              TitleMenuItem.separator(),
            ]),
          ],
        ),
      ],
    ));

    await tester.tap(find.text('查看'));
    await tester.pumpAndSettle();
    expect(find.text('外观'), findsOneWidget);
    await tester.tap(find.text('外观'));
    await tester.pumpAndSettle();

    expect(find.text('切换侧栏'), findsOneWidget);
    expect(find.text('隐藏动作'), findsNothing);
    expect(find.text('禁用动作'), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
    final disabledButton = tester.widget<MenuItemButton>(find.ancestor(
      of: find.text('禁用动作'),
      matching: find.byType(MenuItemButton),
    ));
    expect(disabledButton.enabled, isFalse);

    await tester.tap(find.text('切换侧栏'));
    await tester.pumpAndSettle();
    expect(executedArguments, ['primary']);
    expect(disabledCalls, 0);
  });

  testWidgets('keyboard opens nested menu and activates a leaf command',
      (tester) async {
    var commandCalls = 0;
    commands.register(Command(
      id: 'view.toggleSidebar',
      title: 'Toggle sidebar',
      category: 'View',
      run: () async {
        commandCalls++;
      },
    ));
    await tester.pumpWidget(_titleBarApp(
      commands: commands,
      window: window,
      configuration:
          WindowChromeConfiguration.forPlatform(TargetPlatform.linux),
      menus: const [
        (
          '查看',
          [
            TitleMenuItem.submenu('外观', children: [
              TitleMenuItem('切换侧栏', commandId: 'view.toggleSidebar'),
            ]),
          ],
        ),
      ],
    ));

    await tester.tap(find.text('查看'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('切换侧栏'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(commandCalls, 1);
  });

  testWidgets('Alt mnemonic opens nested menus and invokes the marked command',
      (tester) async {
    var commandCalls = 0;
    commands.register(Command(
      id: 'file.save',
      title: 'Save',
      category: 'File',
      run: () async {
        commandCalls++;
      },
    ));
    await tester.pumpWidget(_titleBarApp(
      commands: commands,
      window: window,
      configuration:
          WindowChromeConfiguration.forPlatform(TargetPlatform.windows),
      menus: const [
        (
          '文件(&&F)',
          [
            TitleMenuItem.submenu('外观(&&A)', children: [
              TitleMenuItem('保存(&&S)', commandId: 'file.save'),
            ]),
          ],
        ),
      ],
    ));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
    expect(
      tester
          .widget<SubmenuButton>(find.byType(SubmenuButton).first)
          .controller!
          .isOpen,
      isTrue,
    );
    expect(find.byType(SubmenuButton), findsNWidgets(2));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(commandCalls, 1);
  });

  testWidgets('bare Alt focuses the menu and bare mnemonic opens it',
      (tester) async {
    final editorFocus = FocusNode(debugLabel: 'editor focus');
    var openCalls = 0;
    commands.register(Command(
      id: 'file.open',
      title: 'Open',
      category: 'File',
      run: () async {
        openCalls++;
      },
    ));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            WindowChromeConfigurationScope(
              configuration:
                  WindowChromeConfiguration.forPlatform(TargetPlatform.linux),
              child: AlulaTitleBar(
                commands: commands,
                menus: const [
                  (
                    '文件(&&F)',
                    [
                      TitleMenuItem('打开(&&O)', commandId: 'file.open'),
                    ]
                  ),
                ],
                windowChromeDriver: window,
              ),
            ),
            Expanded(child: TextField(focusNode: editorFocus)),
          ],
        ),
      ),
    ));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(editorFocus.hasFocus, isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(openCalls, 1);
    expect(editorFocus.hasFocus, isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Alula menu bar focus',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SubmenuButton>(find.byType(SubmenuButton).first)
          .controller!
          .isOpen,
      isTrue,
    );
    expect(find.byType(MenuItemButton), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(editorFocus.hasFocus, isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.tap(find.byType(TextField));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(editorFocus.hasFocus, isTrue);
    expect(find.byType(MenuItemButton), findsNothing);

    editorFocus.dispose();
  });

  testWidgets('mnemonics skip disabled and hidden menu commands',
      (tester) async {
    var commandCalls = 0;
    commands.register(Command(
      id: 'test.disabledMenuCommand',
      title: 'Disabled',
      category: 'Test',
      enablement: 'menuActionEnabled',
      run: () async {
        commandCalls++;
      },
    ));
    commands.register(Command(
      id: 'test.hiddenMenuCommand',
      title: 'Hidden',
      category: 'Test',
      when: 'showHiddenMenuAction',
      run: () async {
        commandCalls++;
      },
    ));
    await tester.pumpWidget(_titleBarApp(
      commands: commands,
      window: window,
      configuration:
          WindowChromeConfiguration.forPlatform(TargetPlatform.windows),
      menus: const [
        (
          '测试(&&T)',
          [
            TitleMenuItem('禁用(&&D)', commandId: 'test.disabledMenuCommand'),
            TitleMenuItem('隐藏(&&H)', commandId: 'test.hiddenMenuCommand'),
          ],
        ),
      ],
    ));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(find.text('隐藏(H)'), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(commandCalls, 0);
    expect(find.byType(MenuItemButton), findsOneWidget);
  });

  testWidgets('Alt mnemonic works when custom bare-Alt focus is disabled',
      (tester) async {
    commands.register(Command(
      id: 'file.open',
      title: 'Open',
      category: 'File',
      run: () async {},
    ));
    await tester.pumpWidget(_titleBarApp(
      commands: commands,
      window: window,
      configuration:
          WindowChromeConfiguration.forPlatform(TargetPlatform.windows),
      customMenuBarAltFocus: false,
      menus: const [
        ('文件(&&F)', [TitleMenuItem('打开(&&O)', commandId: 'file.open')]),
      ],
    ));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      isNot('Alula menu bar focus'),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsOneWidget);
  });

  testWidgets('macOS and disabled settings strip markers without access keys',
      (tester) async {
    commands.register(Command(
      id: 'file.open',
      title: 'Open',
      category: 'File',
      run: () async {},
    ));
    await tester.pumpWidget(_titleBarApp(
      commands: commands,
      window: window,
      configuration:
          WindowChromeConfiguration.forPlatform(TargetPlatform.macOS),
      menus: const [
        (
          '文件(&&F)',
          [
            TitleMenuItem('打开(&&O)', commandId: 'file.open'),
            TitleMenuItem('另存为 && 退出(&&X)', commandId: 'file.open'),
          ],
        ),
      ],
    ));

    expect(find.byType(PlatformMenuBar), findsOneWidget);
    expect(find.byType(MenuBar), findsNothing);
    expect(
      platformMenus.menus.whereType<PlatformMenu>().map((menu) => menu.label),
      ['Alula Code', '文件'],
    );
    final nativeLabels = _allPlatformMenuItems(platformMenus.menus)
        .map((item) => item.label)
        .toList();
    expect(nativeLabels, contains('打开'));
    expect(nativeLabels, contains('另存为 & 退出'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);

    await tester.pumpWidget(_titleBarApp(
      commands: commands,
      window: window,
      configuration:
          WindowChromeConfiguration.forPlatform(TargetPlatform.windows),
      enableMenuBarMnemonics: false,
      menus: const [
        ('文件(&&F)', [TitleMenuItem('打开(&&O)', commandId: 'file.open')]),
      ],
    ));
    expect(find.text('文件(F)'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Alula menu bar focus',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
  });

  testWidgets('checked nested menu state refreshes and reaches macOS labels',
      (tester) async {
    var hidden = false;
    commands.register(Command(
      id: 'test.activityBarSide',
      title: 'Move Activity Bar to Side',
      category: 'View',
      run: () async {
        hidden = false;
      },
    ));
    commands.register(Command(
      id: 'test.activityBarHidden',
      title: 'Hide Activity Bar',
      category: 'View',
      run: () async {
        hidden = true;
      },
    ));

    final menus = [
      (
        'View',
        [
          TitleMenuItem.submenu('Appearance', children: [
            TitleMenuItem.submenu('Activity Bar Position', children: [
              TitleMenuItem('Side',
                  commandId: 'test.activityBarSide',
                  checkedBuilder: () => !hidden),
              TitleMenuItem('Hidden',
                  commandId: 'test.activityBarHidden',
                  checkedBuilder: () => hidden),
            ]),
          ]),
        ],
      ),
    ];
    await tester.pumpWidget(_titleBarApp(
      commands: commands,
      window: window,
      configuration:
          WindowChromeConfiguration.forPlatform(TargetPlatform.linux),
      menus: menus,
    ));
    await tester.pump();

    Future<void> openActivityPositionMenu() async {
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activity Bar Position'));
      await tester.pumpAndSettle();
    }

    Finder itemButton(String label) => find
        .ancestor(
          of: find.text(label),
          matching: find.byType(MenuItemButton),
        )
        .first;

    await openActivityPositionMenu();
    expect(
      tester.widget<MenuItemButton>(itemButton('Side')).leadingIcon,
      isA<Icon>(),
    );
    expect(
      tester
          .getSemantics(find.text('Side'))
          .getSemanticsData()
          .flagsCollection
          .isChecked,
      CheckedState.isTrue,
    );
    await tester.tap(find.text('Hidden'));
    await tester.pumpAndSettle();
    expect(hidden, isTrue);

    await openActivityPositionMenu();
    expect(
      tester.widget<MenuItemButton>(itemButton('Side')).leadingIcon,
      isA<SizedBox>(),
    );
    expect(
      tester.widget<MenuItemButton>(itemButton('Hidden')).leadingIcon,
      isA<Icon>(),
    );

    await tester.pumpWidget(_titleBarApp(
      commands: commands,
      window: window,
      configuration:
          WindowChromeConfiguration.forPlatform(TargetPlatform.macOS),
      menus: menus,
    ));
    await tester.pump();
    final nativeLabels = _allPlatformMenuItems(platformMenus.menus)
        .map((item) => item.label)
        .toList();
    expect(nativeLabels, contains('✓ Hidden'));
    expect(nativeLabels, contains('Side'));
  });
}

Future<void> _doubleTap(WidgetTester tester, Finder finder) async {
  final position = tester.getCenter(finder);
  final gesture = await tester.startGesture(position);
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 80));
  await gesture.down(position);
  await gesture.up();
  await tester.pump();
  await gesture.removePointer();
}

Widget _titleBarApp({
  required CommandService commands,
  required _FakeWindowChromeDriver window,
  required WindowChromeConfiguration configuration,
  List<(String, List<TitleMenuItem>)> menus = const [],
  List<TitleMenuItem> Function()? layoutControlsBuilder,
  VoidCallback? onCloseRequested,
  bool enableMenuBarMnemonics = true,
  bool customMenuBarAltFocus = true,
  String windowTitle = 'Alula Code',
}) {
  return MaterialApp(
    home: WindowChromeConfigurationScope(
      configuration: configuration,
      child: Scaffold(
        body: AlulaTitleBar(
          commands: commands,
          menus: menus,
          layoutControlsBuilder: layoutControlsBuilder,
          windowControls: true,
          windowTitle: windowTitle,
          windowChromeDriver: window,
          onCloseRequested: onCloseRequested,
          enableMenuBarMnemonics: enableMenuBarMnemonics,
          customMenuBarAltFocus: customMenuBarAltFocus,
        ),
      ),
    ),
  );
}

Iterable<PlatformMenuItem> _allPlatformMenuItems(
  Iterable<PlatformMenuItem> items,
) sync* {
  for (final item in items) {
    yield item;
    if (item is PlatformMenu) {
      yield* _allPlatformMenuItems(item.menus);
    } else if (item is PlatformMenuItemGroup) {
      yield* _allPlatformMenuItems(item.members);
    }
  }
}

class _RecordingPlatformMenuDelegate extends PlatformMenuDelegate {
  List<PlatformMenuItem> menus = const [];

  @override
  void setMenus(List<PlatformMenuItem> topLevelMenus) {
    menus = List<PlatformMenuItem>.unmodifiable(topLevelMenus);
  }

  @override
  void clearMenus() {
    menus = const [];
  }

  @override
  bool debugLockDelegate(BuildContext context) => true;

  @override
  bool debugUnlockDelegate(BuildContext context) => true;
}

class _FakeWindowChromeDriver implements WindowChromeDriver {
  final List<WindowListener> listeners = [];
  final List<bool> preventCloseValues = [];
  bool maximized = false;
  int minimizeCalls = 0;
  int maximizeCalls = 0;
  int unmaximizeCalls = 0;
  int dragCalls = 0;
  int closeCalls = 0;
  final List<String> windowTitles = [];

  @override
  void addListener(WindowListener listener) => listeners.add(listener);

  @override
  void removeListener(WindowListener listener) => listeners.remove(listener);

  @override
  Future<bool> isMaximized() async => maximized;

  @override
  Future<void> minimize() async {
    minimizeCalls++;
  }

  @override
  Future<void> maximize() async {
    maximizeCalls++;
    maximized = true;
    for (final listener in List<WindowListener>.of(listeners)) {
      listener.onWindowMaximize();
    }
  }

  @override
  Future<void> unmaximize() async {
    unmaximizeCalls++;
    maximized = false;
    for (final listener in List<WindowListener>.of(listeners)) {
      listener.onWindowUnmaximize();
    }
  }

  @override
  Future<void> startDragging() async {
    dragCalls++;
  }

  @override
  Future<void> close() async {
    closeCalls++;
  }

  @override
  Future<void> setPreventClose(bool preventClose) async {
    preventCloseValues.add(preventClose);
  }

  @override
  Future<void> setTitle(String title) async {
    windowTitles.add(title);
  }

  void emitClose() {
    for (final listener in List<WindowListener>.of(listeners)) {
      listener.onWindowClose();
    }
  }
}
