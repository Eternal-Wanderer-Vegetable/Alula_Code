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
  UndoEntry({
    required this.text,
    required this.caret,
    this.encoding,
    this.bom,
    this.lineEnding,
    this.transactionId,
  }) : sequence = _nextUndoSequence++;

  /// 该步骤的「变更前」全文（undo 目标态）。
  final String text;

  /// 变更前的光标位（UTF-16 偏移）。
  final int caret;

  /// 文档文件格式状态；普通编辑历史也携带这些值，以便与格式转换组合撤销。
  final String? encoding;
  final bool? bom;
  final String? lineEnding;

  /// Shared identity for edits originating from one multi-document operation.
  final String? transactionId;

  /// 跨文档的创建顺序，供共享预算从最旧的历史帧开始回收。
  final int sequence;
}

int _nextUndoSequence = 0;

/// 多文档 undo/redo 共用的内存与条数预算。
///
/// 每个文档保留独立栈；超出工作台预算时，从所有文档中回收最旧历史帧。
class UndoHistoryBudget {
  UndoHistoryBudget({this.maxTotalEntries = 100, this.maxTotalChars = 2000000});

  final int maxTotalEntries;
  final int maxTotalChars;
  final Set<UndoStack> _stacks = {};
  int _totalEntries = 0;
  int _totalChars = 0;
  bool _enforcing = false;

  int get totalEntries => _totalEntries;
  int get totalChars => _totalChars;

  void _attach(UndoStack stack) => _stacks.add(stack);

  void _added(UndoEntry entry) {
    _totalEntries++;
    _totalChars += entry.text.length;
    _enforce();
  }

  void _removed(UndoEntry entry) {
    _totalEntries--;
    _totalChars -= entry.text.length;
  }

  void _detach(UndoStack stack) => _stacks.remove(stack);

  void _enforce() {
    if (_enforcing) return;
    _enforcing = true;
    try {
      while (_totalEntries > maxTotalEntries || _totalChars > maxTotalChars) {
        UndoStack? owner;
        UndoEntry? oldest;
        for (final stack in _stacks) {
          final candidate = stack._oldestEntry;
          if (candidate != null &&
              (oldest == null || candidate.sequence < oldest.sequence)) {
            owner = stack;
            oldest = candidate;
          }
        }
        if (owner == null || oldest == null) break;
        owner._evictEntry(oldest);
      }
    } finally {
      _enforcing = false;
    }
  }
}

class UndoStack {
  UndoStack({
    this.maxEntries = 100,
    this.maxTotalChars = 2000000,
    UndoHistoryBudget? budget,
  }) : _budget = budget {
    _budget?._attach(this);
  }

  final int maxEntries;
  final int maxTotalChars;
  final UndoHistoryBudget? _budget;

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
    String? encoding,
    bool? bom,
    String? lineEnding,
    String? transactionId,
  }) {
    if (coalesce && _undo.isNotEmpty) return;
    _clearRedo();
    final entry = UndoEntry(
      text: before,
      caret: caret,
      encoding: encoding,
      bom: bom,
      lineEnding: lineEnding,
      transactionId: transactionId,
    );
    _undo.add(entry);
    _budget?._added(entry);
    _evictOldest();
  }

  /// 撤销：返回要恢复的快照；栈空返回 null。
  /// [currentText]/[currentCaret] 压入 redo 栈。
  UndoEntry? undo(
    String currentText,
    int currentCaret, {
    String? encoding,
    bool? bom,
    String? lineEnding,
  }) {
    if (_undo.isEmpty) return null;
    final entry = _undo.removeLast();
    _budget?._removed(entry);
    final redoEntry = UndoEntry(
      text: currentText,
      caret: currentCaret,
      encoding: encoding,
      bom: bom,
      lineEnding: lineEnding,
      transactionId: entry.transactionId,
    );
    _redo.add(redoEntry);
    _budget?._added(redoEntry);
    _evictOldest();
    return entry;
  }

  /// 重做：对称返回 redo 栈顶的快照；栈空返回 null。
  UndoEntry? redo(
    String currentText,
    int currentCaret, {
    String? encoding,
    bool? bom,
    String? lineEnding,
  }) {
    if (_redo.isEmpty) return null;
    final entry = _redo.removeLast();
    _budget?._removed(entry);
    final undoEntry = UndoEntry(
      text: currentText,
      caret: currentCaret,
      encoding: encoding,
      bom: bom,
      lineEnding: lineEnding,
      transactionId: entry.transactionId,
    );
    _undo.add(undoEntry);
    _budget?._added(undoEntry);
    _evictOldest();
    return entry;
  }

  void clear() {
    for (final entry in _undo) {
      _budget?._removed(entry);
    }
    for (final entry in _redo) {
      _budget?._removed(entry);
    }
    _undo.clear();
    _redo.clear();
  }

  /// 关闭文档时释放栈并从工作台的共享预算中解除登记。
  void dispose() {
    clear();
    _budget?._detach(this);
  }

  UndoEntry? get _oldestEntry {
    if (_undo.isEmpty) return _redo.isEmpty ? null : _redo.first;
    if (_redo.isEmpty) return _undo.first;
    return _undo.first.sequence < _redo.first.sequence
        ? _undo.first
        : _redo.first;
  }

  void _evictEntry(UndoEntry entry) {
    if (!_undo.remove(entry)) _redo.remove(entry);
    _budget?._removed(entry);
  }

  void _clearRedo() {
    for (final entry in _redo) {
      _budget?._removed(entry);
    }
    _redo.clear();
  }

  /// 条数/总字符双上限同时计算 undo 与 redo 历史。
  void _evictOldest() {
    var total = _undo.fold<int>(0, (sum, entry) => sum + entry.text.length) +
        _redo.fold<int>(0, (sum, entry) => sum + entry.text.length);
    while (_undo.length + _redo.length > maxEntries || total > maxTotalChars) {
      final oldest = _oldestEntry;
      if (oldest == null) break;
      total -= oldest.text.length;
      _evictEntry(oldest);
    }
  }
}
