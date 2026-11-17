/// 通知 UI（docs/11 LAY-18a）：右下角 toast 堆叠与通知中心面板。
///
/// toast 与中心共享 [NotificationCenter]：关闭 toast 只影响 toast 层，中心里的
/// 条目仍在；Do Not Disturb 只抑制 toast。两者都带 live region 与可读名称。
library;

import 'package:flutter/material.dart';

import 'notifications.dart';

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

/// 右下角 toast 堆叠（旧在上、新在下；数量由中心限制）。
class WorkbenchNotificationToasts extends StatelessWidget {
  const WorkbenchNotificationToasts({
    super.key,
    required this.center,
    required this.onDismissToast,
  });

  final NotificationCenter center;
  final void Function(int id) onDismissToast;

  @override
  Widget build(BuildContext context) {
    final visible = <WorkbenchNotification>[
      for (final id in center.toastIds)
        if (center.byId(id) case final notification?) notification,
    ];
    if (visible.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final notification in visible)
          _NotificationToast(
            key: ValueKey('notification-toast-${notification.id}'),
            notification: notification,
            onDismiss: () => onDismissToast(notification.id),
          ),
      ],
    );
  }
}

class _NotificationToast extends StatelessWidget {
  const _NotificationToast({
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
        width: 340,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        decoration: BoxDecoration(
          color: const Color(0xFF252932),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF3A4150)),
          boxShadow: const [BoxShadow(blurRadius: 12, color: Colors.black54)],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(style.icon, size: 15, color: style.color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.message,
                    style: const TextStyle(fontSize: 12, height: 1.3),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.source,
                    style:
                        TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
                  ),
                  if (notification.hasProgress)
                    _NotificationProgressLine(
                      notification: notification,
                      cancelKeyPrefix: 'notification-toast-cancel',
                    ),
                  if (notification.hasActions)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          for (final (index, action)
                              in notification.actions.indexed)
                            TextButton(
                              key: ValueKey(
                                  'notification-toast-action-${notification.id}-$index'),
                              style: TextButton.styleFrom(
                                minimumSize: const Size(0, 26),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                textStyle: const TextStyle(fontSize: 11.5),
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
              key: ValueKey('notification-toast-close-${notification.id}'),
              tooltip: '关闭通知',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              onPressed: onDismiss,
              icon: Icon(Icons.close, size: 13, color: Colors.grey.shade400),
            ),
          ],
        ),
      ),
    );
  }
}

/// 通知中心面板：列表、逐条关闭、全部清除、Do Not Disturb、来源过滤。
class WorkbenchNotificationCenter extends StatelessWidget {
  const WorkbenchNotificationCenter({
    super.key,
    required this.center,
    required this.sourceFilter,
    required this.onSourceFilterChanged,
    required this.onDismiss,
    required this.onClearAll,
    required this.onToggleDoNotDisturb,
    required this.onClose,
  });

  final NotificationCenter center;
  final String? sourceFilter;
  final ValueChanged<String?> onSourceFilterChanged;
  final void Function(int id) onDismiss;
  final VoidCallback onClearAll;
  final VoidCallback onToggleDoNotDisturb;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final notifications = center.filtered(sourceFilter);
    return Semantics(
      container: true,
      label: '通知中心',
      child: Container(
        key: const ValueKey('notification-center'),
        width: 380,
        constraints: const BoxConstraints(maxHeight: 360),
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
              padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
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
                    onPressed: onToggleDoNotDisturb,
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
                  IconButton(
                    key: const ValueKey('notification-clear-all'),
                    tooltip: '全部清除',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: center.isEmpty ? null : onClearAll,
                    icon: Icon(Icons.clear_all,
                        size: 16, color: Colors.grey.shade400),
                  ),
                  IconButton(
                    key: const ValueKey('notification-center-close'),
                    tooltip: '关闭通知中心',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: onClose,
                    icon: Icon(Icons.close,
                        size: 15, color: Colors.grey.shade400),
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
                          value: sourceFilter,
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
                          onChanged: onSourceFilterChanged,
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
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: notifications.length,
                  itemBuilder: (context, index) {
                    final notification = notifications[index];
                    return _NotificationCenterRow(
                      notification: notification,
                      onDismiss: () => onDismiss(notification.id),
                    );
                  },
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
    required this.onDismiss,
  });

  final WorkbenchNotification notification;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final style = _NotificationStyle.of(notification.severity);
    return Container(
      key: ValueKey('notification-item-${notification.id}'),
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
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
                    cancelKeyPrefix: 'notification-cancel',
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
                                'notification-action-${notification.id}-$index'),
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
            key: ValueKey('notification-dismiss-${notification.id}'),
            tooltip: '清除通知',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
            onPressed: onDismiss,
            icon: Icon(Icons.close, size: 12, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

/// 进度条 + 百分比 + 取消按钮（toast / 中心 / banner 共用）。
class _NotificationProgressLine extends StatelessWidget {
  const _NotificationProgressLine({
    required this.notification,
    required this.cancelKeyPrefix,
  });

  final WorkbenchNotification notification;
  final String cancelKeyPrefix;

  @override
  Widget build(BuildContext context) {
    final progress = notification.progress!;
    return ListenableBuilder(
      listenable: progress,
      builder: (context, _) {
        if (progress.isDone) return const SizedBox.shrink();
        final fraction = progress.fraction;
        return Semantics(
          label: '进度',
          value: progress.percent == null ? '进行中' : '${progress.percent}%',
          child: Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    key: ValueKey('notification-progress-${notification.id}'),
                    value: fraction,
                    minHeight: 4,
                    backgroundColor: const Color(0xFF3A4150),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF0E639C)),
                  ),
                ),
              ),
              if (progress.percent case final percent?) ...[
                const SizedBox(width: 8),
                Text(
                  '$percent%',
                  key: ValueKey(
                      'notification-progress-percent-${notification.id}'),
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                ),
              ],
              if (progress.onCancel != null && !progress.isDone) ...[
                const SizedBox(width: 4),
                TextButton(
                  key: ValueKey('$cancelKeyPrefix-${notification.id}'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 22),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 10.5),
                  ),
                  onPressed:
                      progress.cancellable ? () => progress.cancel() : null,
                  child: Text(progress.cancellationPending ? '正在取消…' : '取消'),
                ),
              ],
            ],
          ),
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
