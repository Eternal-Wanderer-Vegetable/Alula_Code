/// 自定义标题栏（docs/09 W1-3）。
///
/// 应用名 + 主菜单 + （windowControls 开启时）拖拽移动区与窗口控制按钮。
/// 无边框窗口由 main() 的 `TitleBarStyle.hidden` 开启；
/// widget 测试默认 windowControls=false，不触碰 window_manager 插件通道。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'commands.dart';
import 'window_chrome_configuration.dart';
import 'window_chrome_driver.dart';

enum TitleMenuItemKind { command, submenu, separator }

typedef _IndexedTitleMenuItem = ({int sourceIndex, TitleMenuItem item});

/// 标题栏命令、子菜单或分隔线。
class TitleMenuItem {
  const TitleMenuItem(this.label, {required this.commandId, this.arguments})
      : assert(commandId != null),
        children = const [],
        kind = TitleMenuItemKind.command;

  const TitleMenuItem.submenu(this.label, {required this.children})
      : commandId = null,
        arguments = null,
        kind = TitleMenuItemKind.submenu;

  const TitleMenuItem.separator()
      : label = '',
        commandId = null,
        arguments = null,
        children = const [],
        kind = TitleMenuItemKind.separator;

  final String label;
  final String? commandId;
  final Object? arguments;
  final List<TitleMenuItem> children;
  final TitleMenuItemKind kind;

  bool get isSubmenu => kind == TitleMenuItemKind.submenu;
  bool get isSeparator => kind == TitleMenuItemKind.separator;
}

class AlulaTitleBar extends StatefulWidget {
  const AlulaTitleBar({
    super.key,
    required this.menus,
    required this.commands,
    this.windowControls = false,
    this.windowChromeDriver,
    this.onCloseRequested,
    this.enableMenuBarMnemonics = true,
    this.customMenuBarAltFocus = true,
  });

  /// 菜单组（标题 → 菜单项列表）。
  final List<(String, List<TitleMenuItem>)> menus;

  final CommandService commands;

  /// 是否渲染窗口控制按钮与拖拽移动区（真实窗口开启；测试关闭）。
  final bool windowControls;

  /// Optional desktop adapter for deterministic window-control tests.
  final WindowChromeDriver? windowChromeDriver;

  /// 处理系统关闭事件；回调完成后由标题栏销毁窗口。
  final VoidCallback? onCloseRequested;

  /// 与 window.enableMenuBarMnemonics 的默认值一致；设置接入留 P07。
  final bool enableMenuBarMnemonics;

  /// 与 window.customMenuBarAltFocus 的默认值一致；设置接入留 P07。
  final bool customMenuBarAltFocus;

  @override
  State<AlulaTitleBar> createState() => _AlulaTitleBarState();
}

class _AlulaTitleBarState extends State<AlulaTitleBar> with WindowListener {
  late WindowChromeDriver _windowChrome;
  late TargetPlatform _menuPlatform;
  late FocusNode _menuBarFocusNode;
  late List<MenuController> _menuControllers;
  final Map<String, MenuController> _submenuControllers = {};
  bool _maximized = false;
  bool _closeInProgress = false;
  bool _mnemonicsVisible = false;
  bool _altKeyDown = false;
  bool _altChordHasKey = false;
  bool _altPointerActivity = false;
  FocusNode? _focusToReturn;

  @override
  void initState() {
    super.initState();
    _windowChrome =
        widget.windowChromeDriver ?? const PluginWindowChromeDriver();
    _windowChrome.addListener(this);
    _menuBarFocusNode = FocusNode(debugLabel: 'Alula menu bar focus');
    _createMenuControls();
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_handlePointerEvent);
    if (widget.windowControls) {
      unawaited(_refreshMaximized());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final chrome = WindowChromeConfigurationScope.maybeOf(context) ??
        WindowChromeConfiguration.forPlatform(defaultTargetPlatform);
    _menuPlatform = chrome.targetPlatform;
  }

  @override
  void didUpdateWidget(AlulaTitleBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.menus.length != oldWidget.menus.length) {
      _createMenuControls();
    }
    final nextWindowChrome =
        widget.windowChromeDriver ?? const PluginWindowChromeDriver();
    if (!identical(_windowChrome, nextWindowChrome)) {
      _windowChrome.removeListener(this);
      _windowChrome = nextWindowChrome;
      _windowChrome.addListener(this);
      if (widget.windowControls) unawaited(_refreshMaximized());
    }
  }

  Future<void> _refreshMaximized() async {
    try {
      final maximized = await _windowChrome.isMaximized();
      if (mounted) setState(() => _maximized = maximized);
    } catch (_) {
      // Widget tests and unsupported platform channels keep the default state.
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    GestureBinding.instance.pointerRouter
        .removeGlobalRoute(_handlePointerEvent);
    _menuBarFocusNode.dispose();
    _windowChrome.removeListener(this);
    super.dispose();
  }

  void _createMenuControls() {
    _menuControllers = List<MenuController>.generate(
        widget.menus.length, (_) => MenuController());
    _submenuControllers.clear();
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (_menuPlatform == TargetPlatform.macOS ||
        (!widget.customMenuBarAltFocus && !widget.enableMenuBarMnemonics)) {
      return false;
    }

    final isAlt = event.logicalKey == LogicalKeyboardKey.alt ||
        event.logicalKey == LogicalKeyboardKey.altLeft ||
        event.logicalKey == LogicalKeyboardKey.altRight;
    if (event is KeyDownEvent && isAlt) {
      if (!_altKeyDown) {
        _altKeyDown = true;
        _altChordHasKey = false;
        _altPointerActivity = false;
        if (!_mnemonicsVisible &&
            !_menuControllers.any((controller) => controller.isOpen)) {
          _focusToReturn = FocusManager.instance.primaryFocus;
        }
      }
    } else if (event is KeyDownEvent && _altKeyDown) {
      _altChordHasKey = true;
      if (widget.enableMenuBarMnemonics && !_isModifierKey(event.logicalKey)) {
        final pressedKey = event.logicalKey.keyLabel.toLowerCase();
        if (_activateMenuMnemonic(pressedKey)) return true;
      }
    } else if (event is KeyUpEvent && isAlt) {
      final bareAlt = _altKeyDown && !_altChordHasKey && !_altPointerActivity;
      _altKeyDown = false;
      _altChordHasKey = false;
      _altPointerActivity = false;
      if (bareAlt && widget.customMenuBarAltFocus) {
        _mnemonicsVisible = true;
        _menuBarFocusNode.requestFocus();
        if (mounted) setState(() {});
      }
    }
    return false;
  }

  void _handlePointerEvent(PointerEvent event) {
    if (_altKeyDown) _altPointerActivity = true;
  }

  static bool _isModifierKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.alt ||
      key == LogicalKeyboardKey.altLeft ||
      key == LogicalKeyboardKey.altRight ||
      key == LogicalKeyboardKey.control ||
      key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight ||
      key == LogicalKeyboardKey.shift ||
      key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight ||
      key == LogicalKeyboardKey.meta ||
      key == LogicalKeyboardKey.metaLeft ||
      key == LogicalKeyboardKey.metaRight;

  KeyEventResult _handleMenuKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape &&
        _mnemonicsVisible &&
        !_menuControllers.any((controller) => controller.isOpen)) {
      _restoreWorkbenchFocus();
      return KeyEventResult.handled;
    }

    if (!_mnemonicsVisible ||
        !widget.enableMenuBarMnemonics ||
        _menuPlatform == TargetPlatform.macOS ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }

    return _activateMenuMnemonic(event.logicalKey.keyLabel.toLowerCase())
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  bool _activateMenuMnemonic(String pressedKey) {
    int? matchingTopMenu;
    for (var index = 0; index < widget.menus.length; index++) {
      if (_codeOssMnemonicKey(widget.menus[index].$1) == pressedKey &&
          _visibleTitleMenuItems(widget.menus[index].$2, widget.commands)
              .isNotEmpty) {
        matchingTopMenu = index;
      }
    }

    final openTopMenu = _menuControllers.indexWhere((menu) => menu.isOpen);
    if (matchingTopMenu != null) {
      if (matchingTopMenu == openTopMenu) {
        _menuControllers[matchingTopMenu].close();
      } else {
        for (final menu in _menuControllers) {
          if (menu.isOpen) menu.close();
        }
        _menuBarFocusNode.requestFocus();
        _menuControllers[matchingTopMenu].open();
      }
      if (mounted) setState(() => _mnemonicsVisible = true);
      return true;
    }
    if (openTopMenu < 0) return false;

    final submenuPath = _deepestOpenSubmenuPath(
      openTopMenu,
      widget.menus[openTopMenu].$2,
      const [],
    );
    final currentItems = _itemsAtPath(
      widget.menus[openTopMenu].$2,
      submenuPath,
    );
    _IndexedTitleMenuItem? matchingItem;
    for (final candidate
        in _visibleTitleMenuItems(currentItems, widget.commands)) {
      final item = candidate.item;
      if (!item.isSeparator &&
          _codeOssMnemonicKey(item.label) == pressedKey &&
          (item.isSubmenu || widget.commands.isEnabled(item.commandId!))) {
        matchingItem = candidate;
      }
    }
    if (matchingItem == null) return false;

    final item = matchingItem.item;
    final itemPath = [...submenuPath, matchingItem.sourceIndex];
    if (item.isSubmenu) {
      _submenuControllers
          .putIfAbsent(
            _menuControllerKey(openTopMenu, itemPath),
            MenuController.new,
          )
          .open();
    } else {
      unawaited(_executeMnemonic(item));
    }
    return true;
  }

  List<int> _deepestOpenSubmenuPath(
    int rootIndex,
    List<TitleMenuItem> items,
    List<int> parentPath,
  ) {
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      if (!item.isSubmenu) continue;
      final path = [...parentPath, index];
      final controller =
          _submenuControllers[_menuControllerKey(rootIndex, path)];
      if (controller?.isOpen ?? false) {
        return _deepestOpenSubmenuPath(rootIndex, item.children, path);
      }
    }
    return parentPath;
  }

  List<TitleMenuItem> _itemsAtPath(
    List<TitleMenuItem> rootItems,
    List<int> path,
  ) {
    var items = rootItems;
    for (final index in path) {
      if (index < 0 || index >= items.length) return const [];
      final item = items[index];
      if (!item.isSubmenu) return const [];
      items = item.children;
    }
    return items;
  }

  Future<void> _executeMnemonic(TitleMenuItem item) async {
    await widget.commands.execute(
      item.commandId!,
      arguments: item.arguments,
    );
    _restoreWorkbenchFocus();
  }

  void _restoreWorkbenchFocus() {
    final focusToReturn = _focusToReturn;
    _focusToReturn = null;
    for (final controller in _submenuControllers.values) {
      if (controller.isOpen) controller.close();
    }
    for (final controller in _menuControllers) {
      if (controller.isOpen) controller.close();
    }
    if (mounted) setState(() => _mnemonicsVisible = false);
    if (focusToReturn != null && focusToReturn.context != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && focusToReturn.context != null) {
          focusToReturn.requestFocus();
        }
      });
    } else if (_menuBarFocusNode.hasFocus) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _maximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _maximized = false);
  }

  @override
  void onWindowClose() {
    if (_closeInProgress) return;
    _closeInProgress = true;
    unawaited(_closeWindow());
  }

  Future<void> _closeWindow() async {
    try {
      widget.onCloseRequested?.call();
      await _windowChrome.setPreventClose(false);
      await _windowChrome.close();
    } catch (error) {
      _closeInProgress = false;
      debugPrint('关闭窗口失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final chrome = WindowChromeConfigurationScope.maybeOf(context) ??
        WindowChromeConfiguration.forPlatform(defaultTargetPlatform);
    if (!chrome.isCustom && widget.menus.isEmpty) {
      return const SizedBox.shrink();
    }

    final showCustomControls =
        widget.windowControls && chrome.usesCustomWindowControls;
    return Container(
      // Native mode keeps the menu row below the OS title bar.
      height: chrome.isCustom
          ? chrome.titleBarHeight
          : WindowChromeConfiguration.customTitleBarHeight,
      decoration: const BoxDecoration(color: Color(0xFF1B1E24)),
      child: Row(
        children: [
          const SizedBox(width: 10),
          if (chrome.isCustom) ...[
            _dragArea(
              const Text('Alula Code',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ),
            const SizedBox(width: 10),
          ],
          Theme(
            data: Theme.of(context).copyWith(platform: chrome.targetPlatform),
            child: Focus(
              focusNode: _menuBarFocusNode,
              onKeyEvent: _handleMenuKeyEvent,
              child: ListenableBuilder(
                listenable: widget.commands,
                builder: (context, _) => MenuBar(
                  style: _menuBarStyle,
                  children: [
                    for (var index = 0; index < widget.menus.length; index++)
                      _MenuButton(
                        title: widget.menus[index].$1,
                        items: widget.menus[index].$2,
                        commands: widget.commands,
                        controller: _menuControllers[index],
                        submenuControllerForPath: (path) =>
                            _submenuControllers.putIfAbsent(
                          _menuControllerKey(index, path),
                          MenuController.new,
                        ),
                        enableMnemonics: widget.enableMenuBarMnemonics &&
                            chrome.targetPlatform != TargetPlatform.macOS,
                        persistentMnemonics: _mnemonicsVisible,
                        onCommandExecuted: _restoreWorkbenchFocus,
                      ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: chrome.isCustom
                ? _dragArea(const SizedBox.expand())
                : const SizedBox.expand(),
          ),
          if (showCustomControls) ..._buildWindowButtons(),
        ],
      ),
    );
  }

  Widget _dragArea(Widget child) {
    if (!widget.windowControls) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => unawaited(_windowChrome.startDragging()),
      onDoubleTap: () => unawaited(_toggleMaximize()),
      child: child,
    );
  }

  Future<void> _toggleMaximize() async {
    try {
      if (await _windowChrome.isMaximized()) {
        await _windowChrome.unmaximize();
      } else {
        await _windowChrome.maximize();
      }
    } catch (error) {
      debugPrint('切换窗口最大化状态失败：$error');
    }
  }

  List<Widget> _buildWindowButtons() {
    return [
      _WindowButton(
        icon: Icons.horizontal_rule,
        tooltip: '最小化',
        onPressed: _windowChrome.minimize,
      ),
      _WindowButton(
        icon: _maximized ? Icons.filter_none : Icons.crop_square_outlined,
        tooltip: _maximized ? '向下还原' : '最大化',
        onPressed: _toggleMaximize,
      ),
      _WindowButton(
        icon: Icons.close,
        tooltip: '关闭',
        hoverColor: const Color(0xFFC42B1C),
        onPressed: _windowChrome.close,
      ),
    ];
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.hoverColor = const Color(0xFF2A2E37),
  });

  final IconData icon;
  final String tooltip;
  final Future<void> Function() onPressed;
  final Color hoverColor;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        onTap: () => onPressed(),
        hoverColor: hoverColor,
        child: SizedBox(
          width: 40,
          height: 36,
          child: Icon(icon, size: 14, color: Colors.grey.shade300),
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.title,
    required this.items,
    required this.commands,
    required this.controller,
    required this.submenuControllerForPath,
    required this.enableMnemonics,
    required this.persistentMnemonics,
    required this.onCommandExecuted,
  });

  final String title;
  final List<TitleMenuItem> items;
  final CommandService commands;
  final MenuController controller;
  final MenuController Function(List<int> path) submenuControllerForPath;
  final bool enableMnemonics;
  final bool persistentMnemonics;
  final VoidCallback onCommandExecuted;

  static const ButtonStyle _barButtonStyle = ButtonStyle(
    foregroundColor: WidgetStatePropertyAll(Color(0xFFE0E0E0)),
    overlayColor: WidgetStatePropertyAll(Color(0xFF343943)),
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
    minimumSize: WidgetStatePropertyAll(Size(0, 35)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
    textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
  );

  static const MenuStyle _popupMenuStyle = MenuStyle(
    backgroundColor: WidgetStatePropertyAll(Color(0xFF252932)),
    surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
    minimumSize: WidgetStatePropertyAll(Size(180, 0)),
  );

  static const ButtonStyle _popupMenuItemStyle = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(180, 34)),
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
    visualDensity: VisualDensity.compact,
    textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
  );

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _plainTitleMenuLabel(title),
      child: SubmenuButton(
        controller: controller,
        style: _barButtonStyle,
        menuStyle: _popupMenuStyle,
        menuChildren: _buildMenuChildren(
          context,
          _visibleTitleMenuItems(items, commands),
          const [],
        ),
        child: _titleMenuLabel(context, title),
      ),
    );
  }

  Widget _titleMenuLabel(BuildContext context, String label) =>
      _buildTitleMenuLabel(
        context,
        label,
        enabled: enableMnemonics,
        persistent: persistentMnemonics,
      );

  List<Widget> _buildMenuChildren(
    BuildContext context,
    List<_IndexedTitleMenuItem> menuItems,
    List<int> parentPath,
  ) =>
      [
        for (final entry in menuItems)
          if (entry.item.isSeparator)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Divider(height: 1, thickness: 1),
            )
          else if (entry.item.isSubmenu)
            SubmenuButton(
              controller: submenuControllerForPath(
                [...parentPath, entry.sourceIndex],
              ),
              style: _popupMenuItemStyle,
              menuStyle: _popupMenuStyle,
              menuChildren: _buildMenuChildren(
                context,
                _visibleTitleMenuItems(entry.item.children, commands),
                [...parentPath, entry.sourceIndex],
              ),
              child: _titleMenuLabel(context, entry.item.label),
            )
          else
            MenuItemButton(
              style: _popupMenuItemStyle,
              onPressed: commands.isEnabled(entry.item.commandId!)
                  ? () => unawaited(_execute(entry.item))
                  : null,
              child: _titleMenuLabel(context, entry.item.label),
            ),
      ];

  Future<void> _execute(TitleMenuItem item) async {
    await commands.execute(
      item.commandId!,
      arguments: item.arguments,
    );
    onCommandExecuted();
  }
}

List<_IndexedTitleMenuItem> _visibleTitleMenuItems(
  List<TitleMenuItem> source,
  CommandService commands,
) {
  final visible = <_IndexedTitleMenuItem>[];
  var separatorPending = false;
  for (var sourceIndex = 0; sourceIndex < source.length; sourceIndex++) {
    final item = source[sourceIndex];
    if (item.isSeparator) {
      separatorPending = visible.isNotEmpty;
      continue;
    }

    final itemIsVisible = item.isSubmenu
        ? _visibleTitleMenuItems(item.children, commands).isNotEmpty
        : commands.isVisible(item.commandId!);
    if (!itemIsVisible) continue;

    if (separatorPending) {
      visible.add((sourceIndex: -1, item: const TitleMenuItem.separator()));
    }
    visible.add((sourceIndex: sourceIndex, item: item));
    separatorPending = false;
  }
  return visible;
}

String _menuControllerKey(int rootIndex, List<int> path) =>
    '$rootIndex:${path.join("/")}';

Widget _buildTitleMenuLabel(
  BuildContext context,
  String label, {
  required bool enabled,
  required bool persistent,
}) {
  final flutterLabel = _codeOssMenuLabelToFlutter(label);
  var mnemonicIndex = -1;
  final plainLabel = MenuAcceleratorLabel.stripAcceleratorMarkers(
    flutterLabel,
    setIndex: (index) => mnemonicIndex = index,
  );
  if (!enabled ||
      !persistent ||
      mnemonicIndex < 0 ||
      mnemonicIndex >= plainLabel.characters.length) {
    return Text(plainLabel);
  }

  final characters = plainLabel.characters;
  final style = DefaultTextStyle.of(context).style;
  return RichText(
    text: TextSpan(
      children: [
        if (mnemonicIndex > 0)
          TextSpan(
            text: characters.getRange(0, mnemonicIndex).toString(),
            style: style,
          ),
        TextSpan(
          text: characters.characterAt(mnemonicIndex).toString(),
          style: style.copyWith(decoration: TextDecoration.underline),
        ),
        if (mnemonicIndex + 1 < characters.length)
          TextSpan(
            text: characters.getRange(mnemonicIndex + 1).toString(),
            style: style,
          ),
      ],
    ),
  );
}

String _codeOssMenuLabelToFlutter(String label) {
  final characters = label.characters.toList();
  final result = StringBuffer();
  for (var index = 0; index < characters.length; index++) {
    if (characters[index] != '&') {
      result.write(characters[index]);
      continue;
    }

    if (index + 1 < characters.length && characters[index + 1] == '&') {
      if (index + 2 < characters.length &&
          characters[index + 2] != '&' &&
          characters[index + 2].trim().isNotEmpty) {
        result
          ..write('&')
          ..write(characters[index + 2]);
        index += 2;
      } else {
        result.write('&&');
        index += 1;
      }
    } else {
      result.write('&&');
    }
  }
  return result.toString();
}

String? _codeOssMnemonicKey(String label) {
  final characters = label.characters.toList();
  for (var index = 0; index + 2 < characters.length; index++) {
    if (characters[index] == '&' &&
        characters[index + 1] == '&' &&
        characters[index + 2] != '&' &&
        characters[index + 2].trim().isNotEmpty) {
      return characters[index + 2].toLowerCase();
    }
  }
  return null;
}

String _plainTitleMenuLabel(String label) =>
    MenuAcceleratorLabel.stripAcceleratorMarkers(
      _codeOssMenuLabelToFlutter(
        label.replaceAll(RegExp(r'\(&&[^&\s]\)'), ''),
      ),
    );

const MenuStyle _menuBarStyle = MenuStyle(
  backgroundColor: WidgetStatePropertyAll(Colors.transparent),
  padding: WidgetStatePropertyAll(EdgeInsets.zero),
  minimumSize: WidgetStatePropertyAll(Size(0, 35)),
);
