/// 工作台通知中心（docs/11 LAY-18「通知与进度」）。
///
/// 上游 `INotificationService.notify({severity, message, actions, source})`：通知进入
/// 通知中心列表并在右下角以 toast 呈现；severity 为 info/warning/error；Do Not
/// Disturb 抑制 toast 但通知仍进入中心；按来源过滤。本文件是纯模型（无 UI），
/// 有界列表 + 未读计数 + toast 生命周期，UI 见 notification_widgets.dart。
library;

import 'package:flutter/foundation.dart';

enum WorkbenchNotificationSeverity { info, warning, error }

/// 通知动作（上游 notification action）：按钮标签 + 执行回调。
class WorkbenchNotificationAction {
  const WorkbenchNotificationAction({
    required this.label,
    required this.run,
    this.key,
  });

  final String label;

  /// 稳定的测试/证据后缀（可选）。
  final String? key;
  final Future<void> Function() run;
}

class WorkbenchNotification {
  const WorkbenchNotification({
    required this.id,
    required this.severity,
    required this.message,
    required this.source,
    required this.createdAt,
    this.actions = const <WorkbenchNotificationAction>[],
  });

  final int id;
  final WorkbenchNotificationSeverity severity;
  final String message;

  /// 来源（上游 extension 名称；工作台自身为 `Alula`）。
  final String source;
  final DateTime createdAt;
  final List<WorkbenchNotificationAction> actions;

  bool get hasActions => actions.isNotEmpty;
}

/// 有界、按新到旧排列的通知存储。
class NotificationCenter extends ChangeNotifier {
  NotificationCenter({this.maxNotifications = defaultMaxNotifications});

  static const int defaultMaxNotifications = 100;

  /// 右下角同时可见的 toast 上限（上游同样限制堆叠数量）。
  static const int maxVisibleToasts = 3;

  final int maxNotifications;
  final List<WorkbenchNotification> _items = <WorkbenchNotification>[];
  final Set<int> _unread = <int>{};
  final List<int> _toasts = <int>[]; // 旧 → 新
  var _doNotDisturb = false;
  var _nextId = 1;

  /// 通知列表，新的在前。
  List<WorkbenchNotification> get items => List.unmodifiable(_items);

  /// 当前可见 toast 的 id，旧 → 新。
  List<int> get toastIds => List.unmodifiable(_toasts);

  bool get doNotDisturb => _doNotDisturb;
  int get unreadCount => _unread.length;
  bool get hasUnread => _unread.isNotEmpty;
  bool get isEmpty => _items.isEmpty;

  /// 出现过的来源（按字母序），用于来源过滤。
  List<String> get sources {
    final values = <String>{for (final item in _items) item.source}.toList();
    values.sort();
    return values;
  }

  WorkbenchNotification? byId(int id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  WorkbenchNotification notify({
    required WorkbenchNotificationSeverity severity,
    required String message,
    String source = 'Alula',
    List<WorkbenchNotificationAction> actions =
        const <WorkbenchNotificationAction>[],
    DateTime? createdAt,
  }) {
    final notification = WorkbenchNotification(
      id: _nextId++,
      severity: severity,
      message: message,
      source: source,
      createdAt: createdAt ?? DateTime.now(),
      actions: actions,
    );
    _items.insert(0, notification);
    _unread.add(notification.id);
    if (!_doNotDisturb) {
      _toasts.add(notification.id);
      while (_toasts.length > maxVisibleToasts) {
        _toasts.removeAt(0);
      }
    }
    while (_items.length > maxNotifications) {
      final removed = _items.removeLast();
      _unread.remove(removed.id);
      _toasts.remove(removed.id);
    }
    notifyListeners();
    return notification;
  }

  /// 关闭 toast：只从 toast 层移除，通知仍留在中心。
  void dismissToast(int id) {
    if (_toasts.remove(id)) notifyListeners();
  }

  /// 关闭通知：同时移出列表、未读与 toast。
  void dismiss(int id) {
    final before = _items.length;
    _items.removeWhere((item) => item.id == id);
    _unread.remove(id);
    _toasts.remove(id);
    if (_items.length != before) notifyListeners();
  }

  void clearAll() {
    if (_items.isEmpty && _toasts.isEmpty && _unread.isEmpty) return;
    _items.clear();
    _unread.clear();
    _toasts.clear();
    notifyListeners();
  }

  void markRead(int id) {
    if (_unread.remove(id)) notifyListeners();
  }

  void markAllRead() {
    if (_unread.isEmpty) return;
    _unread.clear();
    notifyListeners();
  }

  void setDoNotDisturb(bool value) {
    if (_doNotDisturb == value) return;
    _doNotDisturb = value;
    if (value) _toasts.clear();
    notifyListeners();
  }

  List<WorkbenchNotification> filtered([String? source]) => source == null
      ? items
      : _items.where((item) => item.source == source).toList(growable: false);
}
