/// 自定义标题栏（docs/09 W1-3）。
///
/// 应用名 + 三组功能菜单 + （windowControls 开启时）拖拽移动区与窗口控制按钮。
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

/// 标题栏菜单项。
class TitleMenuItem {
  const TitleMenuItem(this.label, {required this.commandId, this.arguments});

  final String label;
  final String commandId;
  final Object? arguments;
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
      // Native mode keeps the existing menu entry row below the OS title bar.
      // The menu hierarchy will be expanded in the separate menu parity slice.
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
          for (final (title, items) in widget.menus)
            _MenuButton(title: title, items: items, commands: widget.commands),
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: commands,
      builder: (context, _) => PopupMenuButton<String>(
        tooltip: title,
        position: PopupMenuPosition.under,
        color: const Color(0xFF252932),
        onSelected: (commandId) {
          final item =
              items.firstWhere((entry) => entry.commandId == commandId);
          unawaited(commands.execute(commandId, arguments: item.arguments));
        },
        itemBuilder: (context) => [
          for (final item
              in items.where((entry) => commands.isVisible(entry.commandId)))
            PopupMenuItem<String>(
              value: item.commandId,
              enabled: commands.isEnabled(item.commandId),
              height: 34,
              child: Text(item.label, style: const TextStyle(fontSize: 12)),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(title, style: const TextStyle(fontSize: 12)),
        ),
      ),
    );
  }
}
