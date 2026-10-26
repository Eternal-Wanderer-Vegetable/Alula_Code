/// 自定义标题栏（docs/09 W1）。
///
/// W1-2：应用名 + 三组功能菜单（纯 Flutter，三平台一致）。
/// W1-3：接入 window_manager 后追加拖拽区与窗口控制按钮（- □ ×）。
library;

import 'package:flutter/material.dart';

/// 标题栏菜单项。
class TitleMenuItem {
  const TitleMenuItem(this.label, this.onSelected);

  final String label;
  final VoidCallback onSelected;
}

class AlulaTitleBar extends StatelessWidget {
  const AlulaTitleBar({
    super.key,
    required this.menus,
    this.trailing,
  });

  /// 菜单组（标题 → 菜单项列表）。
  final List<(String, List<TitleMenuItem>)> menus;

  /// 尾部区（W1-3 放窗口控制按钮）。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: const BoxDecoration(color: Color(0xFF1B1E24)),
      child: Row(
        children: [
          const SizedBox(width: 10),
          const Text('Alula Code',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(width: 10),
          for (final (title, items) in menus) _MenuButton(title: title, items: items),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
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
