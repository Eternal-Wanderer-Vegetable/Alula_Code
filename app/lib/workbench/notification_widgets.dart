/// 通知 UI（docs/11 LAY-18）：toast 堆叠与通知中心面板。
///
/// toast 与中心共享 [NotificationCenter]：关闭 toast 只影响 toast 层，中心里的
/// 条目仍在；Do Not Disturb 只抑制 toast。两者都带 live region 与可读名称。
library;

import 'dart:async';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import 'notifications.dart';

const _notificationSurfaceWidth = 450.0;

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
    required this.unreadCount,
    required this.visible,
    required this.doNotDisturb,
    required this.onPressed,
  });

  final int unreadCount;
  final bool visible;
  final bool doNotDisturb;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: Tooltip(
        message: unreadCount > 0 ? '通知（$unreadCount 条未读）' : '通知',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              doNotDisturb
                  ? Icons.notifications_off
                  : visible
                      ? Icons.notifications
                      : Icons.notifications_none,
              size: 14,
              color: visible ? Colors.lightBlueAccent : Colors.grey.shade400,
            ),
            if (unreadCount > 0) ...[
              const SizedBox(width: 4),
              Container(
                key: const ValueKey('status-notifications-badge'),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                decoration: BoxDecoration(
                  color: const Color(0xFF0E639C),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  '$unreadCount',
                  style: const TextStyle(fontSize: 9, color: Colors.white),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
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

class _NotificationItemFocus extends Focus {
  _NotificationItemFocus({
    super.key,
    required this.notification,
    this.isToast = false,
    super.autofocus,
    super.onFocusChange,
    required VoidCallback onMiddleClick,
    required Widget child,
  }) : super(
          child: _NotificationMiddleClick(
            onClear: onMiddleClick,
            child: child,
          ),
        );

  final WorkbenchNotification notification;
  final bool isToast;
}

class _NotificationMiddleClick extends StatelessWidget {
  const _NotificationMiddleClick({required this.onClear, required this.child});

  final VoidCallback onClear;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      supportedDevices: const {PointerDeviceKind.mouse},
      onTertiaryTapUp: (details) {
        final box = context.findRenderObject();
        if (box is RenderBox &&
            (Offset.zero & box.size)
                .contains(box.globalToLocal(details.globalPosition))) {
          onClear();
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
        spacing: 8,
        children: [
          for (final notification in visible)
            _NotificationToast(
              key: ValueKey('notification-toast-${notification.id}'),
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
    required this.notification,
    required this.windowFocused,
    required this.expandsDown,
    required this.onDismiss,
    required this.onMiddleClick,
  });

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
    final notification = widget.notification;
    final sticky = notification.hasProgress ||
        (notification.severity == WorkbenchNotificationSeverity.error &&
            notification.hasActions);
    if (sticky || _hovered || _descendantFocused) {
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
      child: _NotificationItemFocus(
        notification: notification,
        isToast: true,
        onMiddleClick: widget.onMiddleClick,
        onFocusChange: (focused) => _descendantFocused = focused,
        child: Semantics(
          liveRegion: true,
          container: true,
          label: '${notification.source} 通知：${notification.message}',
          child: Container(
            width: _notificationSurfaceWidth,
            decoration: BoxDecoration(
              color: const Color(0xFF252932),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF3A4150)),
              boxShadow: const [
                BoxShadow(blurRadius: 12, color: Colors.black54),
              ],
            ),
            child: _NotificationContent(
              notification: notification,
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
  final WorkbenchNotificationPosition position;
  final ValueChanged<WorkbenchNotificationPosition>? onPositionChanged;
  final VoidCallback onClose;

  @override
  State<WorkbenchNotificationCenter> createState() =>
      _WorkbenchNotificationCenterState();
}

class _WorkbenchNotificationCenterState
    extends State<WorkbenchNotificationCenter> {
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
        constraints: const BoxConstraints(maxHeight: 436),
        decoration: BoxDecoration(
          color: const Color(0xFF1F232B),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF3A4150)),
          boxShadow: const [BoxShadow(blurRadius: 18, color: Colors.black54)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
              child: Row(
                children: [
                  const Text('通知',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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
                  IconButton(
                    key: const ValueKey('notification-dnd-toggle'),
                    tooltip: center.doNotDisturb ? '请勿打扰：开' : '请勿打扰：关',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: widget.onToggleDoNotDisturb,
                    icon: Icon(
                      center.doNotDisturb
                          ? Icons.notifications_off
                          : Icons.notifications_active_outlined,
                      size: 15,
                      color: center.doNotDisturb
                          ? Colors.orangeAccent
                          : Colors.grey.shade400,
                    ),
                  ),
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
                  if (widget.onPositionChanged != null)
                    PopupMenuButton<WorkbenchNotificationPosition>(
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
            const Divider(height: 1),
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
                  child: ListView.builder(
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
                      return _NotificationItemFocus(
                        key: ValueKey(notification.id),
                        notification: notification,
                        autofocus: autofocus,
                        onMiddleClick: () =>
                            center.clearNotification(notification),
                        child: _NotificationCenterRow(
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
          ],
        ),
      ),
    );
  }
}

class _NotificationCenterRow extends StatelessWidget {
  const _NotificationCenterRow({
    required this.notification,
    required this.showDivider,
    required this.expandsDown,
    required this.onDismiss,
  });

  final WorkbenchNotification notification;
  final bool showDivider;
  final bool expandsDown;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('notification-item-${notification.id}'),
      decoration: showDivider
          ? const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF3A4150))),
            )
          : null,
      foregroundDecoration: Focus.of(context).hasFocus
          ? BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.primary),
            )
          : null,
      child: _NotificationContent(
        notification: notification,
        expandsDown: expandsDown,
        onDismiss: onDismiss,
      ),
    );
  }
}

class _NotificationContent extends StatefulWidget {
  const _NotificationContent({
    required this.notification,
    required this.expandsDown,
    required this.onDismiss,
    this.isToast = false,
  });

  final WorkbenchNotification notification;
  final VoidCallback onDismiss;
  final bool isToast;
  final bool expandsDown;

  @override
  State<_NotificationContent> createState() => _NotificationContentState();
}

class _NotificationContentState extends State<_NotificationContent> {
  // Toast and center display the same notification object. Overrides disappear
  // with that object, including when the center evicts an old notification.
  static final _expandedByNotification = Expando<bool>();
  static const _messageStyle = TextStyle(fontSize: 13, height: 1.35);
  static const _actionStyle = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(0, 26)),
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.standard,
    textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
  );

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

  Widget _buildContent(BuildContext context) {
    final notification = widget.notification;
    final style = _NotificationStyle.of(notification.severity);
    final hasProgress = notification.hasProgress;
    final hasPrimaryActions = notification.hasActions ||
        (hasProgress && notification.progress!.onCancel != null);
    final expanded =
        hasPrimaryActions || (_expandedByNotification[notification] ?? false);
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
                    if (showDisclosure)
                      _toolbarButton(
                        key: ValueKey('$prefix-toggle-${notification.id}'),
                        icon: expanded == widget.expandsDown
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        tooltip: expanded ? '折叠通知' : '展开通知',
                        onPressed: () => setState(() {
                          _expandedByNotification[notification] = !expanded;
                        }),
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
    final text = TextPainter(
      text: TextSpan(
        text: widget.notification.message,
        style: DefaultTextStyle.of(context).style.merge(_messageStyle),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout(maxWidth: (width - 22 - (hasProgress ? 0 : 24)).clamp(0, width));
    final overflows = text.didExceedMaxLines;
    text.dispose();
    return overflows;
  }

  Widget _toolbarButton({
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 24,
      height: 32,
      child: IconButton(
        key: key,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
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
    return primary
        ? FilledButton(
            key: key,
            style: _actionStyle,
            onPressed: action.run,
            child: label,
          )
        : OutlinedButton(
            key: key,
            style: _actionStyle,
            onPressed: action.run,
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
