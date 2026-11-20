/// 工作台通知中心（docs/11 LAY-18「通知与进度」）。
///
/// 上游 `INotificationService.notify({severity, message, actions, source})`：通知进入
/// 通知中心列表并按位置设置呈现 toast。请勿打扰时普通通知仍进入中心，
/// 新错误照常弹出。本文件是纯模型（无 UI），
/// 有界列表 + 未读计数 + toast 生命周期，UI 见 notification_widgets.dart。
library;

import 'package:flutter/foundation.dart';

enum WorkbenchNotificationSeverity { info, warning, error }

typedef WorkbenchNotificationSourceFilter = ({String label, bool muted});

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
    this.sourceId,
    this.actions = const <WorkbenchNotificationAction>[],
    this.secondaryActions = const <WorkbenchNotificationAction>[],
    this.progress,
    this.banner = false,
  });

  final int id;
  final WorkbenchNotificationSeverity severity;
  final String message;

  /// 来源（上游 extension 名称；工作台自身为 `Alula`）。
  final String source;
  final String? sourceId;
  final DateTime createdAt;
  final List<WorkbenchNotificationAction> actions;
  final List<WorkbenchNotificationAction> secondaryActions;

  /// 进度通知的进度对象（null 表示普通通知）。
  final NotificationProgress? progress;

  /// 以编辑器区上方的内嵌 banner 呈现（不产生 toast）。
  final bool banner;

  bool get hasActions => actions.isNotEmpty;
  bool get hasProgress => progress != null && !progress!.isDone;
}

/// 通知进度（上游 `IProgressOptions`/`IProgressStep`）：有 `total` 时为确定进度，
/// 否则为不确定（转圈）；提供 `onCancel` 时允许取消。`report` 更新后通知监听者，
/// UI 用 `ListenableBuilder` 直接重建进度条。
class NotificationProgress extends ChangeNotifier {
  NotificationProgress({
    int? total,
    int worked = 0,
    bool infinite = false,
    this.onCancel,
  })  : _total = total,
        _worked = worked,
        _infinite = infinite;

  final Future<void> Function()? onCancel;
  int? _total;
  int _worked;
  bool _infinite;
  bool _done = false;
  bool _cancellationPending = false;

  int? get total => _total;
  int get worked => _worked;
  bool get infinite => _infinite;
  bool get isDone => _done;
  bool get cancellationPending => _cancellationPending;
  bool get cancellable => onCancel != null && !_done && !_cancellationPending;

  bool get isDeterminate => !_infinite && _total != null && _total! > 0;

  /// 确定进度 0..1；不确定进度返回 null。
  double? get fraction =>
      isDeterminate ? (_worked / _total!).clamp(0.0, 1.0) : null;

  int? get percent => fraction == null ? null : (fraction! * 100).round();

  void report({int? worked, int? total, bool? infinite}) {
    if (_done) return;
    var changed = false;
    if (worked != null && worked != _worked) {
      _worked = worked;
      changed = true;
    }
    if (total != null && total != _total) {
      _total = total;
      changed = true;
    }
    if (infinite != null && infinite != _infinite) {
      _infinite = infinite;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void done() {
    if (_done) return;
    _done = true;
    _cancellationPending = false;
    notifyListeners();
  }

  Future<void> cancel() async {
    final callback = onCancel;
    if (callback == null || _done || _cancellationPending) return;
    _cancellationPending = true;
    notifyListeners();
    try {
      await callback();
    } catch (_) {
      if (!_done) {
        _cancellationPending = false;
        notifyListeners();
      }
      rethrow;
    }
    if (!_done) {
      _cancellationPending = false;
      notifyListeners();
    }
  }
}

/// 有界、按新到旧排列的通知存储。
class NotificationCenter extends ChangeNotifier {
  NotificationCenter({this.maxNotifications = defaultMaxNotifications});

  static const int defaultMaxNotifications = 100;

  /// 右下角同时可见的 toast 上限（上游同样限制堆叠数量）。
  static const int maxVisibleToasts = 3;

  /// 编辑器区上方同时可见的 banner 上限。
  static const int maxVisibleBanners = 3;

  final int maxNotifications;
  final List<WorkbenchNotification> _items = <WorkbenchNotification>[];
  final Set<int> _unread = <int>{};
  final List<int> _toasts = <int>[]; // 旧 → 新
  final List<int> _banners = <int>[]; // 旧 → 新
  var _doNotDisturb = false;
  Map<String, WorkbenchNotificationSourceFilter> _sourceFilters = const {};

  Map<String, WorkbenchNotificationSourceFilter> get sourceFilters =>
      _sourceFilters;
  var _nextId = 1;

  /// 通知列表，新的在前。
  List<WorkbenchNotification> get items => List.unmodifiable(_items);

  /// 当前可见 toast 的 id，旧 → 新。
  List<int> get toastIds => List.unmodifiable(_toasts);

  /// 当前可见 banner 的通知，旧 → 新。
  List<WorkbenchNotification> get banners => <WorkbenchNotification>[
        for (final id in _banners)
          if (byId(id) case final notification?) notification,
      ];

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
    String? sourceId,
    List<WorkbenchNotificationAction> actions =
        const <WorkbenchNotificationAction>[],
    List<WorkbenchNotificationAction> secondaryActions =
        const <WorkbenchNotificationAction>[],
    DateTime? createdAt,
    NotificationProgress? progress,
    bool banner = false,
  }) {
    _rememberSource(sourceId, source);
    final notification = WorkbenchNotification(
      id: _nextId++,
      severity: severity,
      message: message,
      source: source,
      sourceId: sourceId,
      createdAt: createdAt ?? DateTime.now(),
      actions: actions,
      secondaryActions: List.unmodifiable(secondaryActions),
      progress: progress,
      banner: banner,
    );
    _items.insert(0, notification);
    _unread.add(notification.id);
    if (banner) {
      _banners.add(notification.id);
      while (_banners.length > maxVisibleBanners) {
        _banners.removeAt(0);
      }
    } else if (severity == WorkbenchNotificationSeverity.error ||
        (!_doNotDisturb && _sourceFilters[sourceId]?.muted != true)) {
      _toasts.add(notification.id);
      while (_toasts.length > maxVisibleToasts) {
        _toasts.removeAt(0);
      }
    }
    while (_items.length > maxNotifications) {
      final removed = _items.removeLast();
      _unread.remove(removed.id);
      _toasts.remove(removed.id);
      _banners.remove(removed.id);
    }
    notifyListeners();
    return notification;
  }

  Future<void> runSecondaryAction(
    WorkbenchNotification notification,
    WorkbenchNotificationAction action,
  ) async {
    if (!identical(byId(notification.id), notification) ||
        !notification.secondaryActions.contains(action)) {
      return;
    }
    try {
      await action.run();
    } catch (error) {
      notify(
        severity: WorkbenchNotificationSeverity.error,
        message: '通知操作“${action.label}”失败：$error',
        source: notification.source,
        sourceId: notification.sourceId,
      );
    }
  }

  /// 关闭 toast：只从 toast 层移除，通知仍留在中心。
  void dismissToast(int id) {
    if (_toasts.remove(id)) notifyListeners();
  }

  /// 关闭通知：同时移出列表、未读、toast 与 banner。
  void dismiss(int id) {
    final before = _items.length;
    _items.removeWhere((item) => item.id == id);
    _unread.remove(id);
    _toasts.remove(id);
    _banners.remove(id);
    if (_items.length != before) notifyListeners();
  }

  /// Returns whether the notification belonged to this center and was cleared.
  bool clearNotification(WorkbenchNotification notification) {
    if (notification.hasProgress ||
        !identical(byId(notification.id), notification)) {
      return false;
    }
    dismiss(notification.id);
    return true;
  }

  bool get canClearAll => _items.any((item) => !item.hasProgress);

  /// Clear completed and ordinary notifications and return the cleared count.
  int clearAll() {
    final clearedIds = <int>{
      for (final item in _items)
        if (!item.hasProgress) item.id,
    };
    if (clearedIds.isEmpty) return 0;

    _items.removeWhere((item) => clearedIds.contains(item.id));
    _unread.removeAll(clearedIds);
    _toasts.removeWhere(clearedIds.contains);
    _banners.removeWhere(clearedIds.contains);
    notifyListeners();
    return clearedIds.length;
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

  Map<String, Object?> encodeSourceFilters() => _sourceFilters.map(
        (id, filter) =>
            MapEntry(id, {'label': filter.label, 'muted': filter.muted}),
      );

  void restoreSourceFilters(Object? saved) {
    if (saved is! Map) return;
    final filters = <String, WorkbenchNotificationSourceFilter>{};
    for (final entry in saved.entries) {
      if (filters.length == defaultMaxNotifications) break;
      final id = entry.key;
      final value = entry.value;
      if (id is! String || id.isEmpty || value is! Map) continue;
      final label = value['label'];
      final muted = value['muted'];
      if (label is String && label.isNotEmpty && muted is bool) {
        filters[id] = (label: label, muted: muted);
      }
    }
    for (final entry in _sourceFilters.entries) {
      final saved = filters[entry.key];
      if (saved != null) {
        filters[entry.key] = (label: entry.value.label, muted: saved.muted);
      } else if (filters.length < defaultMaxNotifications) {
        filters[entry.key] = entry.value;
      }
    }
    _applySourceFilters(filters);
  }

  void setSourceDoNotDisturb(Map<String, bool> changes) {
    final filters = Map.of(_sourceFilters);
    for (final entry in changes.entries) {
      if (filters[entry.key] case final source?) {
        filters[entry.key] = (label: source.label, muted: entry.value);
      }
    }
    _applySourceFilters(filters);
  }

  void _rememberSource(String? id, String label) {
    if (id == null || id.isEmpty || label.isEmpty) return;
    final current = _sourceFilters[id];
    if (current?.label == label ||
        (current == null && _sourceFilters.length == defaultMaxNotifications)) {
      return;
    }
    _sourceFilters = Map.unmodifiable({
      ..._sourceFilters,
      id: (label: label, muted: current?.muted ?? false),
    });
  }

  void _applySourceFilters(
      Map<String, WorkbenchNotificationSourceFilter> filters) {
    if (mapEquals(_sourceFilters, filters)) return;
    _sourceFilters = Map.unmodifiable(filters);
    _toasts.removeWhere((id) {
      final entry = byId(id);
      return entry != null &&
          entry.severity != WorkbenchNotificationSeverity.error &&
          _sourceFilters[entry.sourceId]?.muted == true;
    });
    notifyListeners();
  }

  List<WorkbenchNotification> filtered([String? source]) => source == null
      ? items
      : _items.where((item) => item.source == source).toList(growable: false);
}
