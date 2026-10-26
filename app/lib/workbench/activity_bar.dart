/// 活动栏（VS Code 最左列图标条，docs/09 W1）。
///
/// W1 只有资源管理器一个可用视图（点击切换侧栏显隐）；
/// 搜索/源代码管理/设置是 W4/W6 的占位。
library;

import 'package:flutter/material.dart';

class ActivityBar extends StatelessWidget {
  const ActivityBar({
    super.key,
    required this.sidebarCollapsed,
    required this.onToggleSidebar,
  });

  final bool sidebarCollapsed;
  final VoidCallback onToggleSidebar;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Color(0xFF1B1E24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Item(
            icon: Icons.explore_outlined,
            tooltip: '资源管理器',
            active: !sidebarCollapsed,
            onTap: onToggleSidebar,
          ),
          const _Item(
              icon: Icons.search, tooltip: '搜索（W4）', active: false),
          const _Item(
              icon: Icons.account_tree_outlined,
              tooltip: '源代码管理（W4）',
              active: false),
          const Spacer(),
          const _Item(icon: Icons.settings_outlined, tooltip: '管理（W6）', active: false),
        ],
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.tooltip,
    required this.active,
    this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.white : Colors.grey.shade500;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: color),
                if (active)
                  Container(
                    margin: const EdgeInsets.only(top: 3),
                    width: 14,
                    height: 2,
                    decoration: BoxDecoration(
                      color: Colors.blueAccent,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
