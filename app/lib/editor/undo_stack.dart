/// 撤销/重做栈（docs/09 feat-010 / docs/03 Phase 1「撤销重做 UI 化」）。
///
/// 设计要点：
/// - **纯 Dart、文本快照制**：不依赖 TextField 内建 UndoHistory（它锁死编辑器
///   组件选型，且在测试环境会死锁）；撤销 = 把快照写回 controller，经既有
///   「diff → FFI → Rust」通路同步，一致性天然成立。
/// - **连续打字合并**：调用方按时间窗判断 continuation，合并期不压新栈帧
///   （一次撤销回退整段输入而非单字符）。
/// - **低内存纪律**（docs/04）：条数与总字符双上限，超限淘汰最旧。
///   快照是全文本——上限保证最坏内存 ≈ maxTotalChars。
library;

class UndoEntry {
  const UndoEntry({required this.text, required this.caret});

  /// 该步骤的「变更前」全文（undo 目标态）。
  final String text;

  /// 变更前的光标位（UTF-16 偏移）。
  final int caret;
}

class UndoStack {
  UndoStack({this.maxEntries = 100, this.maxTotalChars = 2000000});

  final int maxEntries;
  final int maxTotalChars;

  final List<UndoEntry> _undo = [];
  final List<UndoEntry> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// 用户编辑产生的新变更。
  ///
  /// [before] 是变更前全文；[coalesce] 为 true 表示与上一步属同一串输入
  /// （调用方按时间窗判断），此时不压新帧——撤销时直接回到更早的快照。
  /// 新变更永远作废整个 redo 栈。
  void push({
    required String before,
    required int caret,
    required bool coalesce,
  }) {
    if (coalesce && _undo.isNotEmpty) return;
    _undo.add(UndoEntry(text: before, caret: caret));
    _redo.clear();
    _evictOldest();
  }

  /// 撤销：返回要恢复的快照；栈空返回 null。
  /// [currentText]/[currentCaret] 压入 redo 栈。
  UndoEntry? undo(String currentText, int currentCaret) {
    if (_undo.isEmpty) return null;
    final entry = _undo.removeLast();
    _redo.add(UndoEntry(text: currentText, caret: currentCaret));
    return entry;
  }

  /// 重做：对称返回 redo 栈顶的快照；栈空返回 null。
  UndoEntry? redo(String currentText, int currentCaret) {
    if (_redo.isEmpty) return null;
    final entry = _redo.removeLast();
    _undo.add(UndoEntry(text: currentText, caret: currentCaret));
    return entry;
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }

  /// 条数/总字符双上限：从最旧开始淘汰（保留栈底之前的平衡裁剪）。
  void _evictOldest() {
    while (_undo.length > maxEntries) {
      _undo.removeAt(0);
    }
    var total = 0;
    for (final e in _undo) {
      total += e.text.length;
    }
    var drop = 0;
    while (total > maxTotalChars && drop < _undo.length - 1) {
      total -= _undo[drop].text.length;
      drop++;
    }
    if (drop > 0) {
      _undo.removeRange(0, drop);
    }
  }
}
