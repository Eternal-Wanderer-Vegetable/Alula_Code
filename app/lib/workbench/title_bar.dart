/// 自定义标题栏（docs/09 W1-3）。
///
/// 应用名 + 三组功能菜单 + （windowControls 开启时）拖拽移动区与窗口控制按钮。
/// 无边框窗口由 main() 的 `TitleBarStyle.hidden` 开启；
/// widget 测试默认 windowControls=false，不触碰 window_manager 插件通道。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 标题栏菜单项。
class TitleMenuItem {
  const TitleMenuItem(this.label, this.onSelected);

  final String label;
  final VoidCallback onSelected;
}

class AlulaTitleBar extends StatefulWidget {
  const AlulaTitleBar({
    super.key,
    required this.menus,
    this.windowControls = false,
    this.onCloseRequested,
  });

  /// 菜单组（标题 → 菜单项列表）。
  final List<(String, List<TitleMenuItem>)> menus;

  /// 是否渲染窗口控制按钮与拖拽移动区（真实窗口开启；测试关闭）。
  final bool windowControls;

  /// 处理系统关闭事件；回调完成后由标题栏销毁窗口。
  final VoidCallback? onCloseRequested;

  @override
  State<AlulaTitleBar> createState() => _AlulaTitleBarState();
}

class _AlulaTitleBarState extends State<AlulaTitleBar> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    if (widget.windowControls) {
      // 当前最大化态探测：测试环境无插件通道，异常静默（保持默认 false）
      windowManager.isMaximized().then((v) {
        if (mounted) setState(() => _maximized = v);
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
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
    try {
      widget.onCloseRequested?.call();
    } finally {
      unawaited(windowManager.destroy());
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Row(
      children: [
        const SizedBox(width: 10),
        const Text('Alula Code',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(width: 10),
        // 菜单按钮要在拖拽区之上，点击不被拖拽手势吃掉
        for (final (title, items) in widget.menus)
          _MenuButton(title: title, items: items),
        const Spacer(),
        if (widget.windowControls) ..._buildWindowButtons(),
      ],
    );

    if (!widget.windowControls) {
      return Container(
        height: 36,
        decoration: const BoxDecoration(color: Color(0xFF1B1E24)),
        child: content,
      );
    }

    return DragToMoveArea(
      // 双击标题栏切换最大化（对标原生窗口行为）
      child: GestureDetector(
        onDoubleTapDown: (_) => windowManager.isMaximized().then((v) {
          v ? windowManager.unmaximize() : windowManager.maximize();
        }),
        onDoubleTap: () {},
        child: Container(
          height: 36,
          decoration: const BoxDecoration(color: Color(0xFF1B1E24)),
          child: content,
        ),
      ),
    );
  }

  List<Widget> _buildWindowButtons() {
    return [
      _WindowButton(
        icon: Icons.horizontal_rule,
        tooltip: '最小化',
        onPressed: windowManager.minimize,
      ),
      _WindowButton(
        icon: _maximized
            ? Icons.filter_none
            : Icons.crop_square_outlined,
        tooltip: _maximized ? '向下还原' : '最大化',
        onPressed: () => windowManager.isMaximized().then((v) {
          v ? windowManager.unmaximize() : windowManager.maximize();
        }),
      ),
      _WindowButton(
        icon: Icons.close,
        tooltip: '关闭',
        hoverColor: const Color(0xFFC42B1C),
        onPressed: windowManager.close,
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
  const _MenuButton({required this.title, required this.items});

  final String title;
  final List<TitleMenuItem> items;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: title,
      position: PopupMenuPosition.under,
      color: const Color(0xFF252932),
      onSelected: (label) {
        for (final item in items) {
          if (item.label == label) item.onSelected();
        }
      },
      itemBuilder: (context) => [
        for (final item in items)
          PopupMenuItem<String>(
            value: item.label,
            height: 34,
            child: Text(item.label, style: const TextStyle(fontSize: 12)),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(title, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}
