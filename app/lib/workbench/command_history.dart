/// 命令面板最近使用（MRU）历史（docs/11 LAY-17「历史」）。
///
/// 上游 `CommandsHistory` 记录经命令面板接受的命令 id，按最近使用排序参与面板
/// 结果，并有上限。本实现是纯模型：最近使用在最前、记录时去重前移、按
/// [maxCommandHistoryEntries] 裁剪；序列化读取时过滤非字符串/空/超长/重复项。
/// 只有面板接受会写入历史（菜单与键位执行不计，与上游一致）。
library;

/// 上游 `CommandsHistory` 的上限（50 条）。
const int maxCommandHistoryEntries = 50;

/// 命令 id 的长度上限：正常 id 远小于此值，超长项直接忽略，避免异常输入撑大
/// 持久化文件。
const int maxCommandHistoryEntryLength = 256;

/// 命令面板 MRU 历史。
class CommandHistory {
  CommandHistory({Iterable<String> commandIds = const []}) {
    _entries.addAll(sanitizeCommandHistoryEntries(commandIds));
  }

  /// 从持久化载荷恢复；格式不符或字段缺失时返回空历史。
  factory CommandHistory.fromJson(Object? raw) {
    if (raw is! Map) return CommandHistory();
    return CommandHistory(
        commandIds: sanitizeCommandHistoryEntries(raw['entries']));
  }

  final List<String> _entries = <String>[];

  /// 最近使用在前。
  List<String> get commandIds => List.unmodifiable(_entries);

  bool get isEmpty => _entries.isEmpty;

  int get length => _entries.length;

  /// 记录一次面板接受：去重后前移，并裁剪到上限。
  void record(String commandId) {
    if (commandId.isEmpty || commandId.length > maxCommandHistoryEntryLength) {
      return;
    }
    _entries.remove(commandId);
    _entries.insert(0, commandId);
    if (_entries.length > maxCommandHistoryEntries) {
      _entries.removeRange(maxCommandHistoryEntries, _entries.length);
    }
  }

  /// 按「历史顺序在前、其余保持 [ids] 原顺序」重排；历史中已不存在的 id 跳过。
  List<String> order(List<String> ids) {
    final remaining = <String>[...ids];
    final ordered = <String>[];
    for (final id in _entries) {
      if (remaining.remove(id)) ordered.add(id);
    }
    ordered.addAll(remaining);
    return ordered;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'version': 1,
        'entries': _entries.toList(growable: false),
      };
}

/// 过滤持久化/构造输入：只保留字符串、非空、长度合规且不重复的 id，最多
/// [maxCommandHistoryEntries] 条（保留靠前的项，即最近的项）。
List<String> sanitizeCommandHistoryEntries(Object? raw) {
  if (raw is! List) return const <String>[];
  final accepted = <String>[];
  final seen = <String>{};
  for (final entry in raw) {
    if (entry is! String) continue;
    if (entry.isEmpty || entry.length > maxCommandHistoryEntryLength) continue;
    if (!seen.add(entry)) continue;
    accepted.add(entry);
    if (accepted.length >= maxCommandHistoryEntries) break;
  }
  return accepted;
}
