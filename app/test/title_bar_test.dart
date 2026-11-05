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

  setUp(() {
    commands = CommandService();
    window = _FakeWindowChromeDriver();
  });

  tearDown(() {
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
    await tester.pumpWidget(_titleBarApp(
      commands: commands,
      window: window,
      configuration:
          WindowChromeConfiguration.forPlatform(TargetPlatform.macOS),
    ));

    expect(find.text('Alula Code'), findsOneWidget);
    expect(find.byTooltip('最小化'), findsNothing);
    expect(find.byTooltip('最大化'), findsNothing);
    expect(find.byTooltip('关闭'), findsNothing);
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

  testWidgets('double-clicking the title text toggles maximize state',
      (tester) async {
    await tester.pumpWidget(_titleBarApp(
      commands: commands,
      window: window,
      configuration:
          WindowChromeConfiguration.forPlatform(TargetPlatform.linux),
    ));

    final title = find.text('Alula Code');
    await _doubleTap(tester, title);
    await tester.pumpAndSettle();
    expect(window.maximizeCalls, 1);

    await _doubleTap(tester, title);
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

    await tester.drag(find.text('Alula Code'), const Offset(30, 0));
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

    expect(find.text('文件(F)'), findsOneWidget);
    expect(find.byTooltip('文件'), findsOneWidget);
    await tester.tap(find.text('文件(F)'));
    await tester.pumpAndSettle();
    expect(find.text('另存为 & 退出(X)'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(find.text('打开(O)'), findsNothing);

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
  VoidCallback? onCloseRequested,
  bool enableMenuBarMnemonics = true,
  bool customMenuBarAltFocus = true,
}) {
  return MaterialApp(
    home: WindowChromeConfigurationScope(
      configuration: configuration,
      child: Scaffold(
        body: AlulaTitleBar(
          commands: commands,
          menus: menus,
          windowControls: true,
          windowChromeDriver: window,
          onCloseRequested: onCloseRequested,
          enableMenuBarMnemonics: enableMenuBarMnemonics,
          customMenuBarAltFocus: customMenuBarAltFocus,
        ),
      ),
    ),
  );
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

  void emitClose() {
    for (final listener in List<WindowListener>.of(listeners)) {
      listener.onWindowClose();
    }
  }
}
