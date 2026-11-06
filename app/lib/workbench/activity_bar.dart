/// 活动栏（VS Code 最左列图标条，docs/09 W1）。
///
/// 提供 Explorer、Search、Outline 与 Source Control 视图动作；Manage 仍是占位。
library;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart'
    show PointerDownEvent, kSecondaryMouseButton;
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
    this.order = activityBarViewOrder,
    this.pinnedViews = activityBarViewOrder,
    this.onSizeChanged,
    this.onOrderChanged,
    this.onPinnedViewsChanged,
  });

  /// 当前侧栏视图；侧栏折叠时仍保留上次视图。
  final String activeView;
  final bool sidebarCollapsed;
  final Axis axis;
  final ActivityBarSize size;
  final List<String> order;
  final List<String> pinnedViews;

  /// 点击图标：切换视图；重复点当前视图则折叠/展开侧栏。
  final ValueChanged<String> onSelectView;

  /// Changes the selected Activity Bar size from its side-position menu.
  final ValueChanged<ActivityBarSize>? onSizeChanged;

  /// Changes the order of two existing view actions by drag-and-drop.
  final ValueChanged<List<String>>? onOrderChanged;

  /// Changes the set of pinned view actions.
  final ValueChanged<List<String>>? onPinnedViewsChanged;

  @override
  State<ActivityBar> createState() => _ActivityBarState();
}

class _ActivityBarState extends State<ActivityBar> {
  static const _viewLabels = {
    'explorer': '资源管理器',
    'search': '搜索',
    'outline': '大纲',
    'git': '源代码管理',
  };
  static const _viewNames = {
    'explorer': 'Explorer',
    'search': 'Search',
    'outline': 'Outline',
    'git': 'Source Control',
  };
  static const _viewIcons = {
    'explorer': Icons.explore_outlined,
    'search': Icons.search,
    'outline': Icons.format_list_bulleted,
    'git': Icons.account_tree_outlined,
  };
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

  late final Map<String, GlobalKey> _viewItemKeys = {
    for (final id in activityBarViewOrder)
      id: GlobalKey(debugLabel: 'Activity Bar $id drop target'),
  };

  late final Map<String, MenuController> _itemMenuControllers = {
    for (final id in activityBarViewOrder) id: MenuController(),
  };

  late final List<FocusNode> _viewFocusNodes = List.generate(
    activityBarViewOrder.length,
    (index) =>
        FocusNode(debugLabel: 'Activity Bar ${activityBarViewOrder[index]}'),
  );

  @override
  void dispose() {
    for (final node in _viewFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Widget _viewItem({required String id}) {
    final focusIndex = activityBarViewOrder.indexOf(id);
    final icon = _viewIcons[id]!;
    final item = _Item(
      icon: icon,
      tooltip: _viewLabels[id]!,
      active: !widget.sidebarCollapsed && widget.activeView == id,
      focusNode: _viewFocusNodes[focusIndex],
      horizontal: widget.axis == Axis.horizontal,
      itemExtent: widget.size.itemExtent,
      iconSize: widget.axis == Axis.vertical ? widget.size.iconSize : 20,
      onFocusChange: (_) => setState(() {}),
      onKeyEvent: (node, event) => _handleViewKey(id, event),
      onTap: () => widget.onSelectView(id),
    );

    final pinnedViews = _pinnedViewOrder;
    final isPinned = pinnedViews.contains(id);
    final canTogglePin = widget.onPinnedViewsChanged != null &&
        (!isPinned || pinnedViews.length > 1);
    final itemMenu = MenuAnchor(
      key: ValueKey('activity-bar-item-menu-anchor-$id'),
      controller: _itemMenuControllers[id],
      style: _menuStyle,
      menuChildren: [
        MenuItemButton(
          key: ValueKey('activity-bar-item-pin-$id'),
          style: _menuItemStyle,
          onPressed: canTogglePin ? () => _togglePinnedView(id) : null,
          child: Text('${isPinned ? 'Hide' : 'Keep'} ${_viewNames[id]}'),
        ),
      ],
      child: item,
    );

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          widget.onOrderChanged != null &&
          details.data != id &&
          normalizeActivityBarViewOrder(widget.order).contains(details.data),
      onAcceptWithDetails: (details) => _handleViewDrop(
        draggedId: details.data,
        targetId: id,
        globalPosition: details.offset,
      ),
      builder: (context, candidates, rejected) => Draggable<String>(
        data: id,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        maxSimultaneousDrags: widget.onOrderChanged == null ? 0 : 1,
        feedback: Material(
          color: Colors.transparent,
          child: Icon(
            icon,
            size: widget.axis == Axis.vertical ? widget.size.iconSize : 20,
            color: Colors.white,
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: item),
        child: SizedBox(key: _viewItemKeys[id], child: itemMenu),
      ),
    );
  }

  List<String> get _pinnedViewOrder => normalizeActivityBarPinnedViews(
        widget.pinnedViews,
        order: widget.order,
      );

  List<String> get _visibleViewOrder {
    final pinned = _pinnedViewOrder.toSet();
    return normalizeActivityBarViewOrder(widget.order)
        .where((id) => pinned.contains(id) || id == widget.activeView)
        .toList();
  }

  void _togglePinnedView(String id) {
    final pinned = _pinnedViewOrder;
    final next = List<String>.of(pinned);
    if (pinned.contains(id)) {
      if (pinned.length <= 1) return;
      next.remove(id);
    } else {
      next.add(id);
    }
    widget.onPinnedViewsChanged?.call(
      normalizeActivityBarPinnedViews(next, order: widget.order),
    );
  }

  void _handleContextMenuPointerDown(
    PointerDownEvent event, {
    required MenuController barController,
    required BuildContext barContext,
  }) {
    if ((event.buttons & kSecondaryMouseButton) == 0) return;

    final horizontal = widget.axis == Axis.horizontal;
    for (final id in _visibleViewOrder) {
      final renderObject =
          _viewItemKeys[id]?.currentContext?.findRenderObject();
      if (renderObject is! RenderBox) continue;
      final localPosition = renderObject.globalToLocal(event.position);
      if (!(Offset.zero & renderObject.size).contains(localPosition)) continue;

      final itemMenuWidth = horizontal
          ? (renderObject.size.width < 48 ? renderObject.size.width : 48.0)
          : renderObject.size.width;
      final itemMenuRect = Rect.fromLTWH(
        horizontal ? (renderObject.size.width - itemMenuWidth) / 2 : 0,
        0,
        itemMenuWidth,
        renderObject.size.height,
      );
      if (!itemMenuRect.contains(localPosition)) continue;

      _itemMenuControllers[id]!.open(position: localPosition);
      return;
    }

    final renderObject = barContext.findRenderObject();
    if (renderObject is RenderBox) {
      barController.open(
        position: renderObject.globalToLocal(event.position),
      );
    } else {
      barController.open();
    }
  }

  void _handleViewDrop({
    required String draggedId,
    required String targetId,
    required Offset globalPosition,
  }) {
    if (draggedId == targetId || widget.onOrderChanged == null) return;

    final order = normalizeActivityBarViewOrder(widget.order);
    if (!order.contains(draggedId) || !order.contains(targetId)) return;

    final targetRenderObject =
        _viewItemKeys[targetId]?.currentContext?.findRenderObject();
    if (targetRenderObject is! RenderBox) return;

    final localPosition = targetRenderObject.globalToLocal(globalPosition);
    final after = widget.axis == Axis.vertical
        ? localPosition.dy >= targetRenderObject.size.height / 2
        : localPosition.dx >= targetRenderObject.size.width / 2;

    final reordered = List<String>.of(order)..remove(draggedId);
    final targetIndex = reordered.indexOf(targetId);
    final insertionIndex = targetIndex + (after ? 1 : 0);
    reordered.insert(insertionIndex, draggedId);
    if (!listEquals(order, reordered)) {
      widget.onOrderChanged!(List.unmodifiable(reordered));
    }
  }

  KeyEventResult _handleViewKey(String id, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final viewOrder = _visibleViewOrder;
    final index = viewOrder.indexOf(id);
    late final String nextId;
    final previousKey = widget.axis == Axis.vertical
        ? LogicalKeyboardKey.arrowUp
        : LogicalKeyboardKey.arrowLeft;
    final nextKey = widget.axis == Axis.vertical
        ? LogicalKeyboardKey.arrowDown
        : LogicalKeyboardKey.arrowRight;
    if (event.logicalKey == previousKey) {
      if (index == 0) return KeyEventResult.handled;
      nextId = viewOrder[index - 1];
    } else if (event.logicalKey == nextKey) {
      if (index == viewOrder.length - 1) {
        return KeyEventResult.handled;
      }
      nextId = viewOrder[index + 1];
    } else {
      return KeyEventResult.ignored;
    }

    _viewFocusNodes[activityBarViewOrder.indexOf(nextId)].requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.axis == Axis.horizontal;
    final viewOrder = _visibleViewOrder;
    final pinnedViews = _pinnedViewOrder.toSet();
    final viewItems = [
      for (final id in viewOrder) _viewItem(id: id),
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
      key: const ValueKey('activity-bar-checklist-menu'),
      controller: _menuController,
      style: _menuStyle,
      menuChildren: [
        for (final id in normalizeActivityBarViewOrder(widget.order))
          MenuItemButton(
            key: ValueKey('activity-bar-checklist-$id'),
            style: _menuItemStyle,
            leadingIcon: pinnedViews.contains(id)
                ? const Icon(Icons.check, size: 16)
                : const SizedBox(width: 16),
            onPressed: widget.onPinnedViewsChanged == null ||
                    (pinnedViews.contains(id) && pinnedViews.length <= 1)
                ? null
                : () {
                    _togglePinnedView(id);
                    _menuController.close();
                  },
            child: Semantics(
              label: _viewNames[id],
              checked: pinnedViews.contains(id),
              child: Text(_viewNames[id]!),
            ),
          ),
        if (!horizontal && widget.onSizeChanged != null) ...[
          const Divider(height: 8),
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
      ],
      builder: (context, controller, child) => Builder(
        builder: (anchorContext) => Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) => _handleContextMenuPointerDown(
            event,
            barController: controller,
            barContext: anchorContext,
          ),
          child: child!,
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
