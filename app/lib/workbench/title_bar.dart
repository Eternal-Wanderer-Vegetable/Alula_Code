/// 自定义标题栏（docs/09 W1-3）。
///
/// 应用名 + 主菜单 + （windowControls 开启时）拖拽移动区与窗口控制按钮。
/// 无边框窗口由 main() 的 `TitleBarStyle.hidden` 开启；
/// widget 测试默认 windowControls=false，不触碰 window_manager 插件通道。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'commands.dart';
import 'window_chrome_configuration.dart';
import 'window_chrome_driver.dart';

enum TitleMenuItemKind { command, submenu, separator }

/// 标题栏命令、子菜单或分隔线。
class TitleMenuItem {
  const TitleMenuItem(this.label,
      {required this.commandId, this.arguments})
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

  @override
  State<AlulaTitleBar> createState() => _AlulaTitleBarState();
}

class _AlulaTitleBarState extends State<AlulaTitleBar> with WindowListener {
  late WindowChromeDriver _windowChrome;
  bool _maximized = false;
  bool _closeInProgress = false;

  @override
  void initState() {
    super.initState();
    _windowChrome =
        widget.windowChromeDriver ?? const PluginWindowChromeDriver();
    _windowChrome.addListener(this);
    if (widget.windowControls) {
      unawaited(_refreshMaximized());
    }
  }

  @override
  void didUpdateWidget(AlulaTitleBar oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    _windowChrome.removeListener(this);
    super.dispose();
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
          ListenableBuilder(
            listenable: widget.commands,
            builder: (context, _) => MenuBar(
              style: _menuBarStyle,
              children: [
                for (final (title, items) in widget.menus)
                  _MenuButton(
                    title: title,
                    items: items,
                    commands: widget.commands,
                  ),
              ],
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
  });

  final String title;
  final List<TitleMenuItem> items;
  final CommandService commands;

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
      message: title,
      child: SubmenuButton(
        style: _barButtonStyle,
        menuStyle: _popupMenuStyle,
        menuChildren: _buildMenuChildren(_visibleItems(items)),
        child: Text(title),
      ),
    );
  }

  List<TitleMenuItem> _visibleItems(List<TitleMenuItem> source) {
    final visible = <TitleMenuItem>[];
    var separatorPending = false;
    for (final item in source) {
      if (item.isSeparator) {
        separatorPending = visible.isNotEmpty;
        continue;
      }

      final visibleItem = item.isSubmenu
          ? _visibleSubmenu(item)
          : commands.isVisible(item.commandId!)
              ? item
              : null;
      if (visibleItem == null) continue;

      if (separatorPending) {
        visible.add(const TitleMenuItem.separator());
      }
      visible.add(visibleItem);
      separatorPending = false;
    }
    return visible;
  }

  TitleMenuItem? _visibleSubmenu(TitleMenuItem item) {
    final children = _visibleItems(item.children);
    if (children.isEmpty) return null;
    return TitleMenuItem.submenu(item.label, children: children);
  }

  List<Widget> _buildMenuChildren(List<TitleMenuItem> menuItems) => [
        for (final item in menuItems)
          if (item.isSeparator)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Divider(height: 1, thickness: 1),
            )
          else if (item.isSubmenu)
            SubmenuButton(
              style: _popupMenuItemStyle,
              menuStyle: _popupMenuStyle,
              menuChildren: _buildMenuChildren(item.children),
              child: Text(item.label),
            )
          else
            MenuItemButton(
              style: _popupMenuItemStyle,
              onPressed: commands.isEnabled(item.commandId!)
                  ? () => unawaited(
                        commands.execute(
                          item.commandId!,
                          arguments: item.arguments,
                        ),
                      )
                  : null,
              child: Text(item.label),
            ),
      ];
}

const MenuStyle _menuBarStyle = MenuStyle(
  backgroundColor: WidgetStatePropertyAll(Colors.transparent),
  padding: WidgetStatePropertyAll(EdgeInsets.zero),
  minimumSize: WidgetStatePropertyAll(Size(0, 35)),
);
