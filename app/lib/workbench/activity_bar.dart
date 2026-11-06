/// 活动栏（VS Code 最左列图标条，docs/09 W1）。
///
/// 提供 Explorer、Search、Outline 与 Source Control 视图动作；Manage 仍是占位。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'layout_model.dart';

class ActivityBar extends StatefulWidget {
  const ActivityBar({
    super.key,
    required this.activeView,
    required this.sidebarCollapsed,
    required this.onSelectView,
    this.axis = Axis.vertical,
    this.size = ActivityBarSize.defaultSize,
    this.onSizeChanged,
  });

  /// 当前侧栏视图；侧栏折叠时仍保留上次视图。
  final String activeView;
  final bool sidebarCollapsed;
  final Axis axis;
  final ActivityBarSize size;

  /// 点击图标：切换视图；重复点当前视图则折叠/展开侧栏。
  final ValueChanged<String> onSelectView;

  /// Changes the selected Activity Bar size from its side-position menu.
  final ValueChanged<ActivityBarSize>? onSizeChanged;

  @override
  State<ActivityBar> createState() => _ActivityBarState();
}

class _ActivityBarState extends State<ActivityBar> {
  static const _viewIds = ['explorer', 'search', 'outline', 'git'];
  static const _viewLabels = ['资源管理器', '搜索', '大纲', '源代码管理'];
  static const _menuStyle = MenuStyle(
    backgroundColor: WidgetStatePropertyAll(Color(0xFF252932)),
    surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
    minimumSize: WidgetStatePropertyAll(Size(190, 0)),
  );
  static const _menuItemStyle = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(190, 34)),
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
    visualDensity: VisualDensity.compact,
    textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
  );

  final MenuController _menuController = MenuController();

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
      horizontal: widget.axis == Axis.horizontal,
      itemExtent: widget.size.itemExtent,
      iconSize: widget.axis == Axis.vertical ? widget.size.iconSize : 20,
      onFocusChange: (_) => setState(() {}),
      onKeyEvent: (node, event) => _handleViewKey(index, event),
      onTap: () => widget.onSelectView(id),
    );
  }

  KeyEventResult _handleViewKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    late final int nextIndex;
    final previousKey = widget.axis == Axis.vertical
        ? LogicalKeyboardKey.arrowUp
        : LogicalKeyboardKey.arrowLeft;
    final nextKey = widget.axis == Axis.vertical
        ? LogicalKeyboardKey.arrowDown
        : LogicalKeyboardKey.arrowRight;
    if (event.logicalKey == previousKey) {
      if (index == 0) return KeyEventResult.handled;
      nextIndex = index - 1;
    } else if (event.logicalKey == nextKey) {
      if (index == _viewFocusNodes.length - 1) {
        return KeyEventResult.handled;
      }
      nextIndex = index + 1;
    } else {
      return KeyEventResult.ignored;
    }

    _viewFocusNodes[nextIndex].requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.axis == Axis.horizontal;
    final viewItems = [
      _viewItem(index: 0, id: 'explorer', icon: Icons.explore_outlined),
      _viewItem(index: 1, id: 'search', icon: Icons.search),
      _viewItem(
        index: 2,
        id: 'outline',
        icon: Icons.format_list_bulleted,
      ),
      _viewItem(index: 3, id: 'git', icon: Icons.account_tree_outlined),
    ];
    final activityBar = FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: Container(
        decoration: const BoxDecoration(color: Color(0xFF1B1E24)),
        child: Flex(
          direction: widget.axis,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (horizontal)
              for (final item in viewItems) Expanded(child: item)
            else
              ...viewItems,
            if (horizontal)
              const SizedBox(
                width: 40,
                child: _Item(
                  icon: Icons.settings_outlined,
                  tooltip: '管理（W6）',
                  active: false,
                  horizontal: true,
                ),
              )
            else
              const Spacer(),
            if (!horizontal)
              _Item(
                icon: Icons.settings_outlined,
                tooltip: '管理（W6）',
                active: false,
                itemExtent: widget.size.itemExtent,
                iconSize: widget.size.iconSize,
              ),
          ],
        ),
      ),
    );

    return MenuAnchor(
      controller: _menuController,
      style: _menuStyle,
      menuChildren: [
        SubmenuButton(
          style: _menuItemStyle,
          menuStyle: _menuStyle,
          key: const ValueKey('activity-bar-size-submenu'),
          menuChildren: [
            for (final size in ActivityBarSize.values)
              MenuItemButton(
                key: ValueKey('activity-bar-size-${size.jsonValue}'),
                style: _menuItemStyle,
                leadingIcon: widget.size == size
                    ? const Icon(Icons.check, size: 16)
                    : const SizedBox(width: 16),
                onPressed: () {
                  widget.onSizeChanged?.call(size);
                  _menuController.close();
                },
                child: Semantics(
                  checked: widget.size == size,
                  child: Text(switch (size) {
                    ActivityBarSize.defaultSize => 'Default',
                    ActivityBarSize.compact => 'Compact',
                  }),
                ),
              ),
          ],
          child: const Text('Activity Bar Size'),
        ),
      ],
      builder: (context, controller, child) => Builder(
        builder: (anchorContext) => GestureDetector(
          onSecondaryTapDown: horizontal || widget.onSizeChanged == null
              ? null
              : (details) {
                  final renderObject = anchorContext.findRenderObject();
                  if (renderObject is RenderBox) {
                    controller.open(
                      position: renderObject.globalToLocal(
                        details.globalPosition,
                      ),
                    );
                  } else {
                    controller.open();
                  }
                },
          child: child,
        ),
      ),
      child: activityBar,
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.tooltip,
    required this.active,
    this.focusNode,
    this.horizontal = false,
    this.itemExtent = 48,
    this.iconSize = 20,
    this.onFocusChange,
    this.onKeyEvent,
    this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final FocusNode? focusNode;
  final bool horizontal;
  final double itemExtent;
  final double iconSize;
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
                child: SizedBox(
                  width: horizontal ? null : itemExtent,
                  height: horizontal ? null : itemExtent,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: horizontal ? 8 : 0),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: iconSize, color: color),
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
      ),
    );
  }
}
