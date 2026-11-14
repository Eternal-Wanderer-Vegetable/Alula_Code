/// 活动栏（VS Code 最左列图标条，docs/09 W1）。
///
/// 提供内置视图项及 Accounts/Manage 全局动作。
library;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart'
    show PointerDownEvent, kSecondaryMouseButton;
import 'package:flutter/services.dart';

import 'activity_bar_badges.dart';
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
    this.badges = const {},
    this.badgeDisabledViews = const [],
    this.accountsVisible = true,
    this.onSizeChanged,
    this.onOrderChanged,
    this.onPinnedViewsChanged,
    this.onBadgeDisabledViewsChanged,
    this.onAccountsVisibilityChanged,
    this.onManageCommand,
  });

  /// 当前侧栏视图；侧栏折叠时仍保留上次视图。
  final String activeView;
  final bool sidebarCollapsed;
  final Axis axis;
  final ActivityBarSize size;
  final List<String> order;
  final List<String> pinnedViews;
  final Map<String, ActivityBarBadge> badges;
  final List<String> badgeDisabledViews;
  final bool accountsVisible;

  /// 点击图标：切换视图；重复点当前视图则折叠/展开侧栏。
  final ValueChanged<String> onSelectView;

  /// Changes the selected Activity Bar size from its side-position menu.
  final ValueChanged<ActivityBarSize>? onSizeChanged;

  /// Changes the order of two existing view actions by drag-and-drop.
  final ValueChanged<List<String>>? onOrderChanged;

  /// Changes the set of pinned view actions.
  final ValueChanged<List<String>>? onPinnedViewsChanged;

  /// Changes the set of views whose provider badges are hidden.
  final ValueChanged<List<String>>? onBadgeDisabledViewsChanged;

  /// Changes the Accounts global action visibility preference.
  final ValueChanged<bool>? onAccountsVisibilityChanged;

  /// Dispatches one currently registered Manage action.
  final ValueChanged<String>? onManageCommand;

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
  final MenuController _accountsMenuController = MenuController();
  final MenuController _manageMenuController = MenuController();
  final GlobalKey _accountsItemKey =
      GlobalKey(debugLabel: 'Activity Bar Accounts action');
  bool _accountsMenuContextOnly = false;

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
  late final Map<String, FocusNode> _globalActionFocusNodes = {
    'accounts': FocusNode(debugLabel: 'Activity Bar Accounts'),
    'manage': FocusNode(debugLabel: 'Activity Bar Manage'),
  };

  @override
  void dispose() {
    for (final node in _viewFocusNodes) {
      node.dispose();
    }
    for (final node in _globalActionFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Widget _viewItem({required String id}) {
    final focusIndex = activityBarViewOrder.indexOf(id);
    final icon = _viewIcons[id]!;
    final badge =
        _visibleBadgesDisabled.contains(id) ? null : widget.badges[id];
    final label = _viewLabels[id]!;
    final itemLabel = badge == null || !badge.hasVisibleContent
        ? label
        : '$label, ${badge.accessibleDescription}';
    final item = _Item(
      icon: icon,
      tooltip: itemLabel,
      active: !widget.sidebarCollapsed && widget.activeView == id,
      badge: badge,
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
    final disabledBadges = _visibleBadgesDisabled;
    final badgeIsHidden = disabledBadges.contains(id);
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
        MenuItemButton(
          key: ValueKey('activity-bar-item-badge-$id'),
          style: _menuItemStyle,
          onPressed: widget.onBadgeDisabledViewsChanged == null
              ? null
              : () => _toggleBadge(id),
          child: Text('${badgeIsHidden ? 'Show' : 'Hide'} Badge'),
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

  List<String> get _visibleBadgesDisabled => normalizeActivityBarBadgesDisabled(
        widget.badgeDisabledViews,
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

  void _toggleBadge(String id) {
    final disabled = _visibleBadgesDisabled;
    if (disabled.contains(id)) {
      disabled.remove(id);
    } else {
      disabled.add(id);
    }
    widget.onBadgeDisabledViewsChanged?.call(
      normalizeActivityBarBadgesDisabled(disabled, order: widget.order),
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

    if (widget.accountsVisible) {
      final accountsRenderObject =
          _accountsItemKey.currentContext?.findRenderObject();
      if (accountsRenderObject is RenderBox) {
        final localPosition =
            accountsRenderObject.globalToLocal(event.position);
        if ((Offset.zero & accountsRenderObject.size).contains(localPosition)) {
          _accountsMenuContextOnly = true;
          _accountsMenuController.open(position: localPosition);
          return;
        }
      }
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

  KeyEventResult _handleGlobalActionKey(String id, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final actionOrder = widget.accountsVisible
        ? const ['accounts', 'manage']
        : const ['manage'];
    final index = actionOrder.indexOf(id);
    final previousKey = widget.axis == Axis.vertical
        ? LogicalKeyboardKey.arrowUp
        : LogicalKeyboardKey.arrowLeft;
    final nextKey = widget.axis == Axis.vertical
        ? LogicalKeyboardKey.arrowDown
        : LogicalKeyboardKey.arrowRight;
    if (event.logicalKey == previousKey) {
      if (index > 0) {
        _globalActionFocusNodes[actionOrder[index - 1]]!.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == nextKey) {
      if (index >= 0 && index < actionOrder.length - 1) {
        _globalActionFocusNodes[actionOrder[index + 1]]!.requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _accountsAction({required bool horizontal}) {
    final focusNode = _globalActionFocusNodes['accounts']!;
    final menuChildren = _accountsMenuContextOnly
        ? [
            MenuItemButton(
              key: const ValueKey('activity-bar-accounts-hide'),
              style: _menuItemStyle,
              onPressed: widget.onAccountsVisibilityChanged == null
                  ? null
                  : () {
                      widget.onAccountsVisibilityChanged!(false);
                      _accountsMenuController.close();
                    },
              child: const Text('Hide Accounts'),
            ),
          ]
        : [
            const MenuItemButton(
              key: ValueKey('activity-bar-accounts-no-provider'),
              style: _menuItemStyle,
              onPressed: null,
              leadingIcon: Icon(Icons.info_outline, size: 16),
              child: Text('暂无可用帐户提供程序'),
            ),
          ];

    return MenuAnchor(
      key: const ValueKey('activity-bar-accounts-menu-anchor'),
      controller: _accountsMenuController,
      childFocusNode: focusNode,
      style: _menuStyle,
      onOpen: () => setState(() {}),
      onClose: () => setState(() => _accountsMenuContextOnly = false),
      menuChildren: menuChildren,
      child: _Item(
        key: _accountsItemKey,
        icon: Icons.account_circle_outlined,
        tooltip: 'Accounts',
        active: _accountsMenuController.isOpen,
        expanded: _accountsMenuController.isOpen,
        focusNode: focusNode,
        horizontal: horizontal,
        itemExtent: widget.size.itemExtent,
        iconSize: horizontal ? 20 : widget.size.iconSize,
        onFocusChange: (_) => setState(() {}),
        onKeyEvent: (node, event) => _handleGlobalActionKey('accounts', event),
        onTap: () {
          _accountsMenuContextOnly = false;
          _accountsMenuController.open();
        },
      ),
    );
  }

  Widget _manageAction({required bool horizontal}) {
    final focusNode = _globalActionFocusNodes['manage']!;
    return MenuAnchor(
      key: const ValueKey('activity-bar-manage-menu-anchor'),
      controller: _manageMenuController,
      childFocusNode: focusNode,
      style: _menuStyle,
      onOpen: () => setState(() {}),
      onClose: () => setState(() {}),
      menuChildren: [
        MenuItemButton(
          key: const ValueKey('activity-bar-manage-command-palette'),
          style: _menuItemStyle,
          onPressed: widget.onManageCommand == null
              ? null
              : () => widget.onManageCommand!('view.commandPalette'),
          child: const Text('命令面板'),
        ),
        const Divider(height: 8),
        MenuItemButton(
          key: const ValueKey('activity-bar-manage-toggle-sidebar'),
          style: _menuItemStyle,
          onPressed: widget.onManageCommand == null
              ? null
              : () => widget.onManageCommand!('view.toggleSidebar'),
          child: const Text('切换侧栏'),
        ),
        MenuItemButton(
          key: const ValueKey('activity-bar-manage-toggle-panel'),
          style: _menuItemStyle,
          onPressed: widget.onManageCommand == null
              ? null
              : () => widget.onManageCommand!('view.togglePanel'),
          child: const Text('切换面板'),
        ),
        const Divider(height: 8),
        MenuItemButton(
          key: const ValueKey('activity-bar-manage-about'),
          style: _menuItemStyle,
          onPressed: widget.onManageCommand == null
              ? null
              : () => widget.onManageCommand!('help.about'),
          child: const Text('关于 Alula Code'),
        ),
      ],
      child: _Item(
        icon: Icons.settings_outlined,
        tooltip: 'Manage',
        active: _manageMenuController.isOpen,
        expanded: _manageMenuController.isOpen,
        focusNode: focusNode,
        horizontal: horizontal,
        itemExtent: widget.size.itemExtent,
        iconSize: horizontal ? 20 : widget.size.iconSize,
        onFocusChange: (_) => setState(() {}),
        onKeyEvent: (node, event) => _handleGlobalActionKey('manage', event),
        onTap: () => _manageMenuController.open(),
      ),
    );
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
            if (!horizontal) const Spacer(),
            if (widget.accountsVisible)
              if (horizontal)
                SizedBox(width: 40, child: _accountsAction(horizontal: true))
              else
                _accountsAction(horizontal: false),
            if (horizontal)
              SizedBox(width: 40, child: _manageAction(horizontal: true))
            else
              _manageAction(horizontal: false),
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
        const Divider(height: 8),
        MenuItemButton(
          key: const ValueKey('activity-bar-checklist-accounts'),
          style: _menuItemStyle,
          leadingIcon: widget.accountsVisible
              ? const Icon(Icons.check, size: 16)
              : const SizedBox(width: 16),
          onPressed: widget.onAccountsVisibilityChanged == null
              ? null
              : () {
                  widget.onAccountsVisibilityChanged!(
                    !widget.accountsVisible,
                  );
                  _menuController.close();
                },
          child: Semantics(
            label: 'Accounts',
            checked: widget.accountsVisible,
            child: const Text('Accounts'),
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
    super.key,
    required this.icon,
    required this.tooltip,
    required this.active,
    this.badge,
    this.expanded,
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
  final ActivityBarBadge? badge;
  final bool? expanded;
  final FocusNode? focusNode;
  final bool horizontal;
  final double itemExtent;
  final double iconSize;
  final ValueChanged<bool>? onFocusChange;
  final FocusOnKeyEventCallback? onKeyEvent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final visibleBadge = badge;
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
        expanded: expanded,
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
                    child: Stack(
                      fit: StackFit.expand,
                      clipBehavior: Clip.none,
                      children: [
                        Center(
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
                        if (visibleBadge != null &&
                            visibleBadge.hasVisibleContent)
                          Positioned(
                            top: 1,
                            right: horizontal ? 6 : 3,
                            child: ExcludeSemantics(
                              child: _Badge(badge: visibleBadge),
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

class _Badge extends StatelessWidget {
  const _Badge({required this.badge});

  final ActivityBarBadge badge;

  @override
  Widget build(BuildContext context) {
    final content = switch (badge.type) {
      ActivityBarBadgeType.number => Text(
          badge.numberText!,
          maxLines: 1,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            height: 1,
            fontWeight: FontWeight.w600,
          ),
        ),
      ActivityBarBadgeType.icon => Icon(
          badge.icon,
          size: 11,
          color: Colors.white,
        ),
      ActivityBarBadgeType.progress => const SizedBox.square(
          dimension: 10,
          child: CircularProgressIndicator(
            value: 0.25,
            strokeWidth: 1.7,
            color: Colors.white,
            backgroundColor: Color(0x66FFFFFF),
          ),
        ),
    };

    return Container(
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      padding: badge.type == ActivityBarBadgeType.number
          ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2)
          : const EdgeInsets.all(3),
      decoration: const BoxDecoration(
        color: Color(0xFFC74E39),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: content,
    );
  }
}
