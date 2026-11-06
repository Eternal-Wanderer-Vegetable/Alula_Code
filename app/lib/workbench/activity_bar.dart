/// 活动栏（VS Code 最左列图标条，docs/09 W1）。
///
/// W1 只有资源管理器一个可用视图（点击切换侧栏显隐）；
/// 搜索/源代码管理/设置是 W4/W6 的占位。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ActivityBar extends StatefulWidget {
  const ActivityBar({
    super.key,
    required this.activeView,
    required this.sidebarCollapsed,
    required this.onSelectView,
  });

  /// 当前侧栏视图（'explorer' / 'git'）；侧栏折叠时仍保留上次视图。
  final String activeView;
  final bool sidebarCollapsed;

  /// 点击图标：切换视图；重复点当前视图则折叠/展开侧栏。
  final ValueChanged<String> onSelectView;

  @override
  State<ActivityBar> createState() => _ActivityBarState();
}

class _ActivityBarState extends State<ActivityBar> {
  static const _viewIds = ['explorer', 'search', 'outline', 'git'];
  static const _viewLabels = ['资源管理器', '搜索', '大纲', '源代码管理'];

  late final List<FocusNode> _viewFocusNodes = List.generate(
    _viewIds.length,
    (index) => FocusNode(debugLabel: 'Activity Bar ${_viewIds[index]}'),
  );

  @override
  void dispose() {
    for (final node in _viewFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Widget _viewItem({
    required int index,
    required String id,
    required IconData icon,
  }) {
    return _Item(
      icon: icon,
      tooltip: _viewLabels[index],
      active: !widget.sidebarCollapsed && widget.activeView == id,
      focusNode: _viewFocusNodes[index],
      onFocusChange: (_) => setState(() {}),
      onKeyEvent: (node, event) => _handleViewKey(index, event),
      onTap: () => widget.onSelectView(id),
    );
  }

  KeyEventResult _handleViewKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final nextIndex = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp =>
        (index - 1 + _viewFocusNodes.length) % _viewFocusNodes.length,
      LogicalKeyboardKey.arrowDown => (index + 1) % _viewFocusNodes.length,
      _ => null,
    };
    if (nextIndex == null) return KeyEventResult.ignored;

    _viewFocusNodes[nextIndex].requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: Container(
        decoration: const BoxDecoration(color: Color(0xFF1B1E24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _viewItem(
              index: 0,
              id: 'explorer',
              icon: Icons.explore_outlined,
            ),
            _viewItem(index: 1, id: 'search', icon: Icons.search),
            _viewItem(
              index: 2,
              id: 'outline',
              icon: Icons.format_list_bulleted,
            ),
            _viewItem(
              index: 3,
              id: 'git',
              icon: Icons.account_tree_outlined,
            ),
            const Spacer(),
            const _Item(
              icon: Icons.settings_outlined,
              tooltip: '管理（W6）',
              active: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.tooltip,
    required this.active,
    this.focusNode,
    this.onFocusChange,
    this.onKeyEvent,
    this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;
  final FocusOnKeyEventCallback? onKeyEvent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final focused = focusNode?.hasFocus ?? false;
    final color = active || focused ? Colors.white : Colors.grey.shade500;
    return Focus(
      canRequestFocus: false,
      onKeyEvent: onKeyEvent,
      child: Semantics(
        label: tooltip,
        button: onTap != null,
        enabled: onTap != null,
        selected: active,
        focusable: focusNode != null,
        focused: focused,
        onTap: onTap,
        child: ExcludeSemantics(
          child: Tooltip(
            message: tooltip,
            excludeFromSemantics: true,
            waitDuration: const Duration(milliseconds: 500),
            child: InkWell(
              focusNode: focusNode,
              canRequestFocus: focusNode != null,
              onFocusChange: onFocusChange,
              onTap: onTap,
              child: Container(
                decoration: BoxDecoration(
                  border: focused
                      ? Border.all(color: Colors.white70, width: 1)
                      : null,
                  borderRadius: BorderRadius.circular(3),
                ),
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
            ),
          ),
        ),
      ),
    );
  }
}
