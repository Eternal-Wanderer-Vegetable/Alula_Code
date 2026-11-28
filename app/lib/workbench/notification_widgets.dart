/// 通知 UI（docs/11 LAY-18）：toast 堆叠与通知中心面板。
///
/// toast 与中心共享 [NotificationCenter]：关闭 toast 只影响 toast 层，中心里的
/// 条目仍在；Do Not Disturb 只抑制 toast。两者都带 live region 与可读名称。
library;

import 'dart:async';

import 'package:flutter/gestures.dart' show PointerDeviceKind, kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'notifications.dart';

// The shared frame includes a one-pixel border on either side of the content.
const _notificationSurfaceWidth = 452.0;

enum WorkbenchNotificationPosition {
  bottomRight('bottom-right', '右下角', Alignment.bottomRight),
  bottomLeft('bottom-left', '左下角', Alignment.bottomLeft),
  topRight('top-right', '右上角', Alignment.topRight);

  const WorkbenchNotificationPosition(this.value, this.label, this.alignment);

  final String value;
  final String label;
  final Alignment alignment;

  String get commandId => 'workbench.action.setNotificationsPosition.$name';
  bool get atTop => this == topRight;

  static WorkbenchNotificationPosition parse(Object? value) => switch (value) {
        'bottom-left' => bottomLeft,
        'top-right' => topRight,
        _ => bottomRight,
      };
}

class WorkbenchNotificationBell extends StatelessWidget {
  const WorkbenchNotificationBell({
    super.key,
    required this.center,
    required this.inTitleBar,
    required this.onPressed,
  });

  final NotificationCenter center;
  final bool inTitleBar;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (inTitleBar) return _button(label: '切换通知', tooltip: '切换通知');
    final items = center.items;
    final progress = <NotificationProgress>[
      if (!center.centerVisible && !center.hasToasts)
        for (final item in items)
          if (item.hasProgress) item.progress!,
    ];
    return ListenableBuilder(
      listenable: Listenable.merge(progress),
      builder: (context, _) {
        final running = progress.where((item) => !item.isDone).length;
        return _button(
          label: center.doNotDisturb ? '请勿打扰' : '通知',
          tooltip: _statusTooltip(running, hasItems: items.isNotEmpty),
          quiet: center.doNotDisturb,
          active: center.centerVisible,
          hasIndicator: center.hasUnread || running > 0,
        );
      },
    );
  }

  String _statusTooltip(int running, {required bool hasItems}) {
    if (center.doNotDisturb) return '请勿打扰已启用';
    if (center.centerVisible) return '隐藏通知';
    if (!hasItems) return '没有通知';
    final unread = center.unreadCount;
    final message = unread == 0 ? '没有新通知' : '$unread 条新通知';
    return running == 0 ? message : '$message（$running 项正在进行）';
  }

  Widget _button({
    required String label,
    required String tooltip,
    bool quiet = false,
    bool active = false,
    bool hasIndicator = false,
  }) {
    final foreground = Colors.grey.shade400;
    final height = inTitleBar ? 14.0 : 24.0;
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 14,
            height: height,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Icon(
                  quiet
                      ? Icons.notifications_off_outlined
                      : Icons.notifications_none,
                  size: 14,
                  color: foreground,
                ),
                if (hasIndicator)
                  Positioned(
                    right: 0,
                    bottom: (height - 14) / 2 + 1,
                    child: Container(
                      key: const ValueKey('status-notifications-indicator'),
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: foreground,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                if (active)
                  const Positioned(
                    top: -5,
                    child: ClipPath(
                      key: ValueKey('status-notifications-beak'),
                      clipper: _NotificationBellBeak(),
                      child: SizedBox(
                        width: 10,
                        height: 5,
                        child: ColoredBox(color: Color(0xFF1B1E24)),
                      ),
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

class _NotificationBellBeak extends CustomClipper<Path> {
  const _NotificationBellBeak();

  @override
  Path getClip(Size size) => Path()
    ..moveTo(size.width / 2, 0)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(covariant _NotificationBellBeak oldClipper) => false;
}

class _NotificationStyle {
  const _NotificationStyle(this.icon, this.color);

  final IconData icon;
  final Color color;

  static _NotificationStyle of(WorkbenchNotificationSeverity severity) =>
      switch (severity) {
        WorkbenchNotificationSeverity.info =>
          const _NotificationStyle(Icons.info_outline, Color(0xFF75BEFF)),
        WorkbenchNotificationSeverity.warning => const _NotificationStyle(
            Icons.warning_amber_rounded, Color(0xFFCCA700)),
        WorkbenchNotificationSeverity.error =>
          const _NotificationStyle(Icons.error_outline, Color(0xFFF48771)),
      };
}

/// Resolve the item that owns the primary focus, including its action buttons.
({WorkbenchNotification notification, bool isToast})?
    focusedWorkbenchNotification() {
  for (var node = FocusManager.instance.primaryFocus;
      node != null;
      node = node.parent) {
    if (node.context?.widget
        case _NotificationItemFocus(
          :final notification,
          :final isToast,
        )) {
      return (notification: notification, isToast: isToast);
    }
  }
  return null;
}

bool hasNotificationRowFocus() =>
    FocusManager.instance.primaryFocus?.context?.widget
        is _NotificationItemFocus;

/// Focus an attached toast row and keep the row in the visible viewport.
void requestNotificationToastFocus(
  FocusNode surface,
  WorkbenchNotification notification,
) {
  for (final node in surface.traversalDescendants) {
    final context = node.context;
    if (context == null || !context.mounted) continue;
    if (context.widget
        case _NotificationItemFocus(isToast: true, notification: final item)
        when identical(item, notification)) {
      node.requestFocus();
      unawaited(Scrollable.ensureVisible(context));
      return;
    }
  }
}

class _NotificationItemActions extends StatefulWidget {
  const _NotificationItemActions({
    super.key,
    required this.center,
    required this.notification,
    required this.onMiddleClick,
    required this.child,
    this.isToast = false,
    this.autofocus = false,
    this.onFocusChange,
    this.onContextMenuVisibilityChanged,
  });

  final NotificationCenter center;
  final WorkbenchNotification notification;
  final VoidCallback onMiddleClick;
  final Widget child;
  final bool isToast;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChange;
  final ValueChanged<bool>? onContextMenuVisibilityChanged;

  @override
  State<_NotificationItemActions> createState() =>
      _NotificationItemActionsState();
}

class _NotificationItemActionsState extends State<_NotificationItemActions> {
  final _rowFocus = FocusNode();
  final _menu = MenuController();

  @override
  void dispose() {
    _rowFocus.dispose();
    super.dispose();
  }

  void _openContextMenu([Offset? position]) {
    _rowFocus.requestFocus();
    _menu.open(position: position);
  }

  Future<void> _copyMessage() async {
    final notification = widget.notification;
    if (!identical(widget.center.byId(notification.id), notification) ||
        (widget.isToast && !widget.center.toastIds.contains(notification.id))) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: notification.message));
  }

  @override
  Widget build(BuildContext context) {
    final prefix = widget.isToast ? 'notification-toast' : 'notification';
    return Stack(
      children: [
        // A sibling anchor keeps the action toolbar's own menu independent.
        Positioned.fill(
          child: MenuAnchor(
            controller: _menu,
            childFocusNode: _rowFocus,
            onOpen: () => widget.onContextMenuVisibilityChanged?.call(true),
            onClose: () => widget.onContextMenuVisibilityChanged?.call(false),
            menuChildren: [
              MenuItemButton(
                key: ValueKey('$prefix-copy-${widget.notification.id}'),
                autofocus: true,
                onPressed: _copyMessage,
                child: const Text('复制文本'),
              ),
            ],
            child: const SizedBox.expand(),
          ),
        ),
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.contextMenu):
                _openContextMenu,
            const SingleActivator(LogicalKeyboardKey.f10, shift: true):
                _openContextMenu,
          },
          child: _NotificationItemFocus(
            notification: widget.notification,
            isToast: widget.isToast,
            autofocus: widget.autofocus,
            focusNode: _rowFocus,
            onFocusChange: widget.onFocusChange,
            onContextMenu: _openContextMenu,
            onMiddleClick: widget.onMiddleClick,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

class _NotificationItemFocus extends Focus {
  _NotificationItemFocus({
    required this.notification,
    this.isToast = false,
    super.autofocus,
    super.onFocusChange,
    super.focusNode,
    required ValueChanged<Offset> onContextMenu,
    required VoidCallback onMiddleClick,
    required Widget child,
  }) : super(
          child: _NotificationMiddleClick(
            onClear: onMiddleClick,
            onContextMenu: onContextMenu,
            child: child,
          ),
        );

  final WorkbenchNotification notification;
  final bool isToast;
}

class _NotificationMiddleClick extends StatelessWidget {
  const _NotificationMiddleClick({
    required this.onClear,
    required this.onContextMenu,
    required this.child,
  });

  final VoidCallback onClear;
  final ValueChanged<Offset> onContextMenu;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    bool isInRow(Offset globalPosition) {
      final box = context.findRenderObject();
      return box is RenderBox &&
          (Offset.zero & box.size).contains(box.globalToLocal(globalPosition));
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      supportedDevices: const {PointerDeviceKind.mouse},
      onTertiaryTapUp: (details) {
        if (isInRow(details.globalPosition)) onClear();
      },
      onSecondaryTapUp: (details) {
        if (isInRow(details.globalPosition)) {
          onContextMenu(details.localPosition);
        }
      },
      child: child,
    );
  }
}

/// Toast 堆叠（新在上、旧在下；数量由中心限制）。
class WorkbenchNotificationToasts extends StatelessWidget {
  const WorkbenchNotificationToasts({
    super.key,
    required this.center,
    required this.onDismissToast,
    this.windowFocused = true,
    this.position = WorkbenchNotificationPosition.bottomRight,
  });

  final NotificationCenter center;
  final void Function(int id) onDismissToast;

  final WorkbenchNotificationPosition position;

  /// 由宿主窗口的焦点事件更新；到期后失焦的 toast 等恢复焦点再计时。
  final bool windowFocused;

  @override
  Widget build(BuildContext context) {
    final visible = <WorkbenchNotification>[
      for (final id in center.toastIds.reversed)
        if (center.byId(id) case final notification?) notification,
    ];
    if (visible.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      primary: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        spacing: 4,
        children: [
          for (final notification in visible)
            _NotificationToast(
              key: ValueKey('notification-toast-${notification.id}'),
              center: center,
              notification: notification,
              windowFocused: windowFocused,
              expandsDown: position.atTop,
              onDismiss: () => onDismissToast(notification.id),
              onMiddleClick: () {
                if (center.toastIds.contains(notification.id)) {
                  center.clearNotification(notification);
                }
              },
            ),
        ],
      ),
    );
  }
}

class _NotificationToast extends StatefulWidget {
  const _NotificationToast({
    super.key,
    required this.center,
    required this.notification,
    required this.windowFocused,
    required this.expandsDown,
    required this.onDismiss,
    required this.onMiddleClick,
  });

  final NotificationCenter center;
  final WorkbenchNotification notification;
  final bool windowFocused;
  final bool expandsDown;
  final VoidCallback onDismiss;
  final VoidCallback onMiddleClick;

  @override
  State<_NotificationToast> createState() => _NotificationToastState();
}

class _NotificationToastState extends State<_NotificationToast> {
  Timer? _timer;
  bool _hovered = false;
  bool _descendantFocused = false;
  bool _secondaryMenuOpen = false;
  bool _contextMenuOpen = false;
  bool _waitingForWindowFocus = false;

  Duration get _interval => switch (widget.notification.severity) {
        WorkbenchNotificationSeverity.info => const Duration(seconds: 10),
        WorkbenchNotificationSeverity.warning => const Duration(seconds: 12),
        WorkbenchNotificationSeverity.error => const Duration(seconds: 15),
      };

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant _NotificationToast oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_waitingForWindowFocus && widget.windowFocused) {
      _waitingForWindowFocus = false;
      _schedule();
    }
  }

  void _schedule() {
    _timer = Timer(_interval, _onDeadline);
  }

  // 对齐固定版本 notificationsToasts.ts：只在截止时重评 sticky/交互状态。
  // hover 离开、进度完成和普通 rebuild 都不重置当前完整间隔。
  void _onDeadline() {
    _timer = null;
    if (!mounted) return;
    if (!widget.windowFocused) {
      _waitingForWindowFocus = true;
      return;
    }
    if (widget.center.isSticky(widget.notification) ||
        _hovered ||
        _descendantFocused ||
        _secondaryMenuOpen ||
        _contextMenuOpen) {
      _schedule();
    } else {
      widget.onDismiss();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notification = widget.notification;
    return MouseRegion(
      onEnter: (_) => _hovered = true,
      onExit: (_) => _hovered = false,
      child: _NotificationItemActions(
        center: widget.center,
        notification: notification,
        isToast: true,
        onContextMenuVisibilityChanged: (visible) => _contextMenuOpen = visible,
        onMiddleClick: widget.onMiddleClick,
        onFocusChange: (focused) {
          if (!mounted || _descendantFocused == focused) return;
          setState(() => _descendantFocused = focused);
        },
        child: Semantics(
          liveRegion: true,
          container: true,
          label: '${notification.source} 通知：${notification.message}',
          child: Container(
            key: ValueKey('notification-toast-frame-${notification.id}'),
            width: _notificationSurfaceWidth,
            decoration: BoxDecoration(
              color: const Color(0xFF252932),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _descendantFocused
                    ? Theme.of(context).colorScheme.primary
                    : const Color(0xFF3A4150),
              ),
              boxShadow: const [
                BoxShadow(blurRadius: 12, color: Colors.black54),
              ],
            ),
            child: _NotificationContent(
              center: widget.center,
              notification: notification,
              onSecondaryMenuVisibilityChanged: (visible) =>
                  _secondaryMenuOpen = visible,
              isToast: true,
              expandsDown: widget.expandsDown,
              onDismiss: widget.onDismiss,
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationCenterScrollView extends StatefulWidget {
  const _NotificationCenterScrollView({required this.child});

  final Widget child;

  @override
  State<_NotificationCenterScrollView> createState() =>
      _NotificationCenterScrollViewState();
}

class _NotificationCenterScrollViewState
    extends State<_NotificationCenterScrollView> {
  final _controller = ScrollController();
  bool _pointerInside = false;
  bool _thumbPressed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _pointerInside = true),
        onExit: (_) => setState(() => _pointerInside = false),
        child: ScrollConfiguration(
          // The notification center supplies its own overlay on every platform.
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: PrimaryScrollController(
            controller: _controller,
            child: _NotificationCenterScrollbar(
              controller: _controller,
              thumbVisibility: _pointerInside || _thumbPressed,
              onThumbPressed: (pressed) =>
                  setState(() => _thumbPressed = pressed),
              child: widget.child,
            ),
          ),
        ),
      );
}

class _NotificationCenterScrollbar extends RawScrollbar {
  const _NotificationCenterScrollbar({
    required super.controller,
    required super.thumbVisibility,
    required this.onThumbPressed,
    required super.child,
  }) : super(
          thickness: 8,
          padding: EdgeInsets.zero,
          scrollbarOrientation: ScrollbarOrientation.right,
          fadeDuration: const Duration(milliseconds: 180),
          timeToFade: const Duration(milliseconds: 500),
        );

  final ValueChanged<bool> onThumbPressed;

  @override
  RawScrollbarState<_NotificationCenterScrollbar> createState() =>
      _NotificationCenterScrollbarState();
}

class _NotificationCenterScrollbarState
    extends RawScrollbarState<_NotificationCenterScrollbar> {
  bool _hoveringThumb = false;
  int? _pressPointer;

  void _updateColor() {
    scrollbarPainter.color = switch ((_pressPointer != null, _hoveringThumb)) {
      (true, _) => const Color.fromRGBO(168, 169, 170, 0.61),
      (false, true) => const Color.fromRGBO(168, 169, 170, 0.56),
      (false, false) => const Color.fromRGBO(168, 169, 170, 0.52),
    };
  }

  @override
  void updateScrollbarPainter() {
    super.updateScrollbarPainter();
    _updateColor();
  }

  @override
  void handleHover(PointerHoverEvent event) {
    super.handleHover(event);
    _hoveringThumb = isPointerOverThumb(event.position, event.kind);
    _updateColor();
  }

  @override
  void handleHoverExit(PointerExitEvent event) {
    super.handleHoverExit(event);
    _hoveringThumb = false;
    _updateColor();
  }

  void _press(PointerDownEvent event) {
    if (mounted &&
        _pressPointer == null &&
        event.buttons == kPrimaryButton &&
        isPointerOverThumb(event.position, event.kind)) {
      _pressPointer = event.pointer;
      widget.onThumbPressed(true);
      _updateColor();
    }
  }

  void _release(PointerEvent event) {
    if (!mounted || _pressPointer != event.pointer) return;
    _pressPointer = null;
    widget.onThumbPressed(false);
    _hoveringThumb = event is PointerUpEvent &&
        event.kind == PointerDeviceKind.mouse &&
        isPointerOverThumb(event.position, event.kind);
    _updateColor();
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: _press,
        onPointerUp: _release,
        onPointerCancel: _release,
        child: super.build(context),
      );
}

/// 通知中心面板：列表、逐条关闭、全部清除、Do Not Disturb、来源过滤。
class WorkbenchNotificationCenter extends StatefulWidget {
  const WorkbenchNotificationCenter({
    super.key,
    required this.center,
    required this.sourceFilter,
    required this.onSourceFilterChanged,
    required this.onDismiss,
    required this.onClearAll,
    required this.onToggleDoNotDisturb,
    required this.onConfigureDoNotDisturbSources,
    this.position = WorkbenchNotificationPosition.bottomRight,
    this.onPositionChanged,
    required this.onClose,
  });

  final NotificationCenter center;
  final String? sourceFilter;
  final ValueChanged<String?> onSourceFilterChanged;
  final void Function(int id) onDismiss;
  final VoidCallback onClearAll;
  final VoidCallback onToggleDoNotDisturb;
  final VoidCallback onConfigureDoNotDisturbSources;
  final WorkbenchNotificationPosition position;
  final ValueChanged<WorkbenchNotificationPosition>? onPositionChanged;
  final VoidCallback onClose;

  @override
  State<WorkbenchNotificationCenter> createState() =>
      _WorkbenchNotificationCenterState();
}

class _WorkbenchNotificationCenterState
    extends State<WorkbenchNotificationCenter> {
  static const _maxSourcesInMenu = 10;
  static const _headerHeight = 35.0;
  // The list viewport is 400 px with a 1 px frame on each edge.
  static const _maxPanelHeight = _headerHeight + 400 + 2;

  bool _focusOnOpen = true;

  @override
  Widget build(BuildContext context) {
    final center = widget.center;
    final notifications = center.filtered(widget.sourceFilter);
    if (notifications.isEmpty) _focusOnOpen = false;
    return Semantics(
      container: true,
      label: '通知中心',
      child: Container(
        key: const ValueKey('notification-center'),
        width: _notificationSurfaceWidth,
        constraints: const BoxConstraints(maxHeight: _maxPanelHeight),
        decoration: BoxDecoration(
          color: const Color(0xFF1F232B),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF3A4150)),
          boxShadow: const [BoxShadow(blurRadius: 18, color: Colors.black54)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              key: const ValueKey('notification-center-header'),
              height: _headerHeight,
              padding: const EdgeInsets.only(left: 8, right: 2),
              child: Row(
                children: [
                  const Text('通知', style: TextStyle(fontSize: 11)),
                  if (center.hasUnread) ...[
                    const SizedBox(width: 6),
                    Text(
                      '${center.unreadCount} 未读',
                      key: const ValueKey('notification-center-unread'),
                      style: TextStyle(
                          fontSize: 10.5, color: Colors.grey.shade400),
                    ),
                  ],
                  const Spacer(),
                  ListenableBuilder(
                    listenable: Listenable.merge([
                      if (!center.canClearAll)
                        for (final notification in center.items)
                          notification.progress,
                    ]),
                    builder: (context, _) => IconButton(
                      key: const ValueKey('notification-clear-all'),
                      tooltip: '全部清除',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 24, minHeight: 24),
                      color: Colors.grey.shade400,
                      onPressed: center.canClearAll ? widget.onClearAll : null,
                      icon: const Icon(Icons.clear_all, size: 16),
                    ),
                  ),
                  _buildDoNotDisturbMenu(),
                  if (widget.onPositionChanged != null)
                    SizedBox.square(
                      dimension: 24,
                      child: PopupMenuButton<WorkbenchNotificationPosition>(
                        key: const ValueKey('notification-position'),
                        tooltip: '通知位置',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 140),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(24, 24),
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: Icon(Icons.open_with,
                            size: 15, color: Colors.grey.shade400),
                        onSelected: widget.onPositionChanged,
                        itemBuilder: (context) => [
                          for (final position
                              in WorkbenchNotificationPosition.values)
                            CheckedPopupMenuItem(
                              key: ValueKey(
                                  'notification-position-${position.name}'),
                              value: position,
                              checked: position == widget.position,
                              child: Text(position.label),
                            ),
                        ],
                      ),
                    ),
                  IconButton(
                    key: const ValueKey('notification-center-close'),
                    tooltip: '关闭通知中心',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: widget.onClose,
                    icon: Icon(
                      widget.position.atTop
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 17,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            ),
            if (center.sources.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          key: const ValueKey('notification-source-filter'),
                          value: widget.sourceFilter,
                          isDense: true,
                          dropdownColor: const Color(0xFF252932),
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white70),
                          items: [
                            const DropdownMenuItem<String?>(
                                value: null, child: Text('全部来源')),
                            for (final source in center.sources)
                              DropdownMenuItem<String?>(
                                  value: source, child: Text(source)),
                          ],
                          onChanged: widget.onSourceFilterChanged,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (notifications.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '没有通知',
                  key: const ValueKey('notification-empty'),
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
                ),
              )
            else
              Flexible(
                child: FocusScope(
                  child: _NotificationCenterScrollView(
                    child: ListView.builder(
                      primary: true,
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: notifications.length,
                      findChildIndexCallback: (key) {
                        if (key is! ValueKey<int>) return null;
                        final index = notifications.indexWhere(
                          (notification) => notification.id == key.value,
                        );
                        return index < 0 ? null : index;
                      },
                      itemBuilder: (context, index) {
                        final notification = notifications[index];
                        final autofocus = _focusOnOpen && index == 0;
                        if (autofocus) _focusOnOpen = false;
                        return _NotificationItemActions(
                          key: ValueKey(notification.id),
                          center: center,
                          notification: notification,
                          autofocus: autofocus,
                          onMiddleClick: () =>
                              center.clearNotification(notification),
                          child: _NotificationCenterRow(
                            center: center,
                            notification: notification,
                            showDivider: index < notifications.length - 1,
                            expandsDown: widget.position.atTop,
                            onDismiss: () => widget.onDismiss(notification.id),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoNotDisturbMenu() {
    final center = widget.center;
    return SizedBox.square(
      dimension: 24,
      child: PopupMenuButton<VoidCallback>(
        key: const ValueKey('notification-dnd-toggle'),
        tooltip: '配置请勿打扰',
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          minimumSize: const Size(24, 24),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: Icon(
          center.doNotDisturb
              ? Icons.notifications_off
              : Icons.notifications_active_outlined,
          size: 15,
          color:
              center.doNotDisturb ? Colors.orangeAccent : Colors.grey.shade400,
        ),
        onSelected: (action) => action(),
        itemBuilder: (_) {
          final sources = center.orderedSourceFilters;
          return [
            PopupMenuItem<VoidCallback>(
              key: const ValueKey('notification-dnd-global'),
              value: widget.onToggleDoNotDisturb,
              child: Text(center.doNotDisturb ? '关闭请勿打扰' : '开启请勿打扰'),
            ),
            if (sources.isNotEmpty) const PopupMenuDivider(),
            for (final source in sources.take(_maxSourcesInMenu))
              CheckedPopupMenuItem<VoidCallback>(
                key: ValueKey('notification-dnd-source-${source.key}'),
                checked: !source.value.muted,
                value: () {
                  final current = center.sourceFilters[source.key];
                  if (current != null) {
                    center.setSourceDoNotDisturb({source.key: !current.muted});
                  }
                },
                child: Tooltip(
                  message: source.key,
                  child:
                      Text(source.value.label, overflow: TextOverflow.ellipsis),
                ),
              ),
            if (sources.length > _maxSourcesInMenu) ...[
              const PopupMenuDivider(),
              PopupMenuItem<VoidCallback>(
                key: const ValueKey('notification-dnd-more'),
                value: widget.onConfigureDoNotDisturbSources,
                child: const Text('更多来源…'),
              ),
            ],
          ];
        },
      ),
    );
  }
}

class _NotificationCenterRow extends StatelessWidget {
  const _NotificationCenterRow({
    required this.center,
    required this.notification,
    required this.showDivider,
    required this.expandsDown,
    required this.onDismiss,
  });

  final NotificationCenter center;
  final WorkbenchNotification notification;
  final bool showDivider;
  final bool expandsDown;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('notification-item-${notification.id}'),
      foregroundDecoration: BoxDecoration(
        border: Focus.of(context).hasFocus
            ? Border.all(color: Theme.of(context).colorScheme.primary)
            : showDivider
                ? const Border(bottom: BorderSide(color: Color(0xFF3A4150)))
                : null,
      ),
      child: _NotificationContent(
        center: center,
        notification: notification,
        expandsDown: expandsDown,
        onDismiss: onDismiss,
      ),
    );
  }
}

class _NotificationContent extends StatefulWidget {
  const _NotificationContent({
    required this.center,
    required this.notification,
    required this.expandsDown,
    required this.onDismiss,
    this.isToast = false,
    this.onSecondaryMenuVisibilityChanged,
  });

  final NotificationCenter center;
  final WorkbenchNotification notification;
  final ValueChanged<bool>? onSecondaryMenuVisibilityChanged;
  final VoidCallback onDismiss;
  final bool isToast;
  final bool expandsDown;

  @override
  State<_NotificationContent> createState() => _NotificationContentState();
}

class _NotificationContentState extends State<_NotificationContent> {
  static const _messageStyle = TextStyle(fontSize: 13, height: 1.35);
  static const _actionStyle = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(0, 26)),
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.standard,
    textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
  );

  FocusNode? _secondaryMenuFocusNode;

  @override
  void dispose() {
    _secondaryMenuFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.notification.progress;
    return progress == null
        ? _buildContent(context)
        : ListenableBuilder(
            listenable: progress,
            builder: (context, _) => _buildContent(context),
          );
  }

  void _toggleExpanded() {
    final notification = widget.notification;
    final center = widget.center;
    if (center.setExpanded(notification, !center.isExpanded(notification))) {
      setState(() {});
    }
  }

  Widget _buildContent(BuildContext context) {
    final notification = widget.notification;
    final style = _NotificationStyle.of(notification.severity);
    final hasProgress = notification.hasProgress;
    final hasPrimaryActions = notification.hasPrimaryActions;
    final expanded = widget.center.isExpanded(notification);
    final prefix = widget.isToast ? 'notification-toast' : 'notification';
    final details =
        expanded && (notification.source.isNotEmpty || notification.hasActions)
            ? _details(notification, prefix)
            : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final showDisclosure = !hasPrimaryActions &&
                  (expanded ||
                      notification.source.isNotEmpty ||
                      _messageOverflows(
                          context, constraints.maxWidth, hasProgress));
              return ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 34),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 9),
                      child: Icon(style.icon, size: 16, color: style.color),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        excludeFromSemantics: true,
                        onDoubleTap: hasPrimaryActions ? null : _toggleExpanded,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            notification.message,
                            style: _messageStyle,
                            maxLines: expanded ? null : 1,
                            overflow: expanded
                                ? TextOverflow.clip
                                : TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    if (notification.secondaryActions.isNotEmpty)
                      _secondaryMenu(notification, prefix),
                    if (showDisclosure)
                      _toolbarButton(
                        key: ValueKey('$prefix-toggle-${notification.id}'),
                        icon: expanded == widget.expandsDown
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        tooltip: expanded ? '折叠通知' : '展开通知',
                        onPressed: _toggleExpanded,
                      ),
                    if (!hasProgress)
                      _toolbarButton(
                        key: ValueKey(widget.isToast
                            ? 'notification-toast-close-${notification.id}'
                            : 'notification-dismiss-${notification.id}'),
                        icon: Icons.close,
                        tooltip: widget.isToast ? '关闭通知' : '清除通知',
                        onPressed: widget.onDismiss,
                      ),
                  ],
                ),
              );
            },
          ),
          if (hasProgress)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: _NotificationProgressLine(
                notification: notification,
                cancelKeyPrefix: '$prefix-cancel',
                inFooter: true,
                leading: details == null
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(left: 22),
                        child: details,
                      ),
              ),
            )
          else if (details != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 0, 7),
              child: details,
            ),
        ],
      ),
    );
  }

  bool _messageOverflows(BuildContext context, double width, bool hasProgress) {
    final toolbarWidth = (hasProgress ? 0 : 24) +
        (widget.notification.secondaryActions.isEmpty ? 0 : 24);
    final text = TextPainter(
      text: TextSpan(
        text: widget.notification.message,
        style: DefaultTextStyle.of(context).style.merge(_messageStyle),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout(maxWidth: (width - 22 - toolbarWidth).clamp(0, width));
    final overflows = text.didExceedMaxLines;
    text.dispose();
    return overflows;
  }

  Widget _secondaryMenu(WorkbenchNotification notification, String prefix) {
    final focusNode = _secondaryMenuFocusNode ??= FocusNode();
    final sourceId = notification.sourceId;
    final source = widget.center.sourceFilters[sourceId];
    return MenuAnchor(
      childFocusNode: focusNode,
      onOpen: () => widget.onSecondaryMenuVisibilityChanged?.call(true),
      onClose: () => widget.onSecondaryMenuVisibilityChanged?.call(false),
      menuChildren: [
        if (sourceId != null && source != null) ...[
          MenuItemButton(
            key: ValueKey('$prefix-source-dnd-${notification.id}'),
            onPressed: () => widget.center.setSourceDoNotDisturb({
              sourceId: !source.muted,
            }),
            child: Text(
              source.muted
                  ? '接收来自“${source.label}”的所有通知'
                  : '关闭来自“${source.label}”的信息和警告',
            ),
          ),
          const Divider(height: 1),
        ],
        for (final (index, action) in notification.secondaryActions.indexed)
          MenuItemButton(
            key: ValueKey('$prefix-secondary-${notification.id}-$index'),
            onPressed: () => unawaited(
              widget.center.runSecondaryAction(notification, action),
            ),
            child: Text(action.label),
          ),
      ],
      builder: (context, controller, _) => _toolbarButton(
        key: ValueKey('$prefix-more-${notification.id}'),
        icon: Icons.settings_outlined,
        tooltip: '更多操作',
        focusNode: focusNode,
        onPressed: controller.isOpen ? controller.close : controller.open,
      ),
    );
  }

  Widget _toolbarButton({
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    FocusNode? focusNode,
  }) {
    return SizedBox(
      width: 24,
      height: 32,
      child: IconButton(
        key: key,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        focusNode: focusNode,
        onPressed: onPressed,
        icon: Icon(icon, size: 15, color: Colors.grey.shade400),
      ),
    );
  }

  Widget _details(WorkbenchNotification notification, String prefix) {
    final source = notification.source;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (source.isNotEmpty)
          Expanded(
            child: Tooltip(
              message: source,
              child: Text(
                '来源：$source',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
              ),
            ),
          ),
        if (notification.hasActions)
          Flexible(
            flex: 2,
            fit: source.isEmpty ? FlexFit.loose : FlexFit.tight,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 5,
              runSpacing: 4,
              children: [
                for (final (index, action) in notification.actions.indexed)
                  _actionButton(
                    action,
                    ValueKey('$prefix-action-${notification.id}-$index'),
                    primary: index == 0,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _actionButton(
    WorkbenchNotificationAction action,
    Key key, {
    required bool primary,
  }) {
    final label =
        Text(action.label, maxLines: 1, overflow: TextOverflow.ellipsis);
    final notification = widget.notification;
    void runAction() =>
        unawaited(widget.center.runPrimaryAction(notification, action));
    return primary
        ? FilledButton(
            key: key,
            style: _actionStyle,
            onPressed: runAction,
            child: label,
          )
        : OutlinedButton(
            key: key,
            style: _actionStyle,
            onPressed: runAction,
            child: label,
          );
  }
}

/// 进度条 + 百分比 + 取消按钮（toast / 中心 / banner 共用）。
class _NotificationProgressLine extends StatelessWidget {
  const _NotificationProgressLine({
    required this.notification,
    required this.cancelKeyPrefix,
    this.inFooter = false,
    this.leading,
  });

  final WorkbenchNotification notification;
  final String cancelKeyPrefix;
  final bool inFooter;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final progress = notification.progress!;
    return ListenableBuilder(
      listenable: progress,
      builder: (context, _) {
        if (progress.isDone) return const SizedBox.shrink();
        final track = ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            key: ValueKey('notification-progress-${notification.id}'),
            value: progress.fraction,
            minHeight: 4,
            backgroundColor: const Color(0xFF3A4150),
            valueColor: const AlwaysStoppedAnimation(Color(0xFF0E639C)),
          ),
        );
        final percent = progress.percent;
        final cancel = progress.onCancel == null
            ? null
            : TextButton(
                key: ValueKey('$cancelKeyPrefix-${notification.id}'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 22),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: 10.5),
                  backgroundColor: inFooter
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                ),
                onPressed:
                    progress.cancellable ? () => progress.cancel() : null,
                child: Text(progress.cancellationPending ? '正在取消…' : '取消'),
              );
        final information = Row(
          children: [
            Expanded(
                child: inFooter ? (leading ?? const SizedBox.shrink()) : track),
            if (percent != null) ...[
              const SizedBox(width: 8),
              Text(
                '$percent%',
                key: ValueKey(
                    'notification-progress-percent-${notification.id}'),
                style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
              ),
            ],
            if (cancel != null) ...[
              const SizedBox(width: 4),
              cancel,
            ],
          ],
        );
        return Semantics(
          label: '进度',
          value: percent == null ? '进行中' : '$percent%',
          child: inFooter
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (leading != null ||
                        percent != null ||
                        cancel != null) ...[
                      information,
                      const SizedBox(height: 4),
                    ],
                    track,
                  ],
                )
              : information,
        );
      },
    );
  }
}

/// 编辑器区上方的内嵌 banner 层（上游 view banner）：空时零高度，zen 模式由工作台
/// 隐藏整个层。
class WorkbenchNotificationBanners extends StatelessWidget {
  const WorkbenchNotificationBanners({
    super.key,
    required this.center,
    required this.onDismiss,
  });

  final NotificationCenter center;
  final void Function(int id) onDismiss;

  @override
  Widget build(BuildContext context) {
    final banners = center.banners;
    if (banners.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final notification in banners)
          _NotificationBanner(
            key: ValueKey('notification-banner-${notification.id}'),
            notification: notification,
            onDismiss: () => onDismiss(notification.id),
          ),
      ],
    );
  }
}

class _NotificationBanner extends StatelessWidget {
  const _NotificationBanner({
    super.key,
    required this.notification,
    required this.onDismiss,
  });

  final WorkbenchNotification notification;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final style = _NotificationStyle.of(notification.severity);
    return Semantics(
      liveRegion: true,
      container: true,
      label: '${notification.source} 通知：${notification.message}',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
        decoration: BoxDecoration(
          color: const Color(0xFF20242C),
          border: Border(left: BorderSide(color: style.color, width: 3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(style.icon, size: 14, color: style.color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(notification.message,
                      style: const TextStyle(fontSize: 11.5, height: 1.3)),
                  const SizedBox(height: 2),
                  Text(notification.source,
                      style:
                          TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                  if (notification.hasProgress)
                    _NotificationProgressLine(
                      notification: notification,
                      cancelKeyPrefix: 'notification-banner-cancel',
                    ),
                  if (notification.hasActions)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          for (final (index, action)
                              in notification.actions.indexed)
                            TextButton(
                              key: ValueKey(
                                  'notification-banner-action-${notification.id}-$index'),
                              style: TextButton.styleFrom(
                                minimumSize: const Size(0, 24),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                textStyle: const TextStyle(fontSize: 11),
                              ),
                              onPressed: () => action.run(),
                              child: Text(action.label),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              key: ValueKey('notification-banner-close-${notification.id}'),
              tooltip: '关闭横幅',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              onPressed: onDismiss,
              icon: Icon(Icons.close, size: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}
