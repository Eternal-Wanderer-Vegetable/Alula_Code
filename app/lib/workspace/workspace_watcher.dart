/// 工作区文件监视（feat-filewatch）：递归监视 + 防抖回调。
///
/// 用 dart:io `Directory.watch(recursive: true)`（Windows/Linux 原生递归），
/// 不引第三方依赖（低内存纪律）。事件洪峰（构建/保存风暴）经防抖收敛成
/// 单次回调；watcher 自身错误静默降级为「无监视」，不影响编辑功能。
library;

import 'dart:async';
import 'dart:io';

class WorkspaceWatcher {
  WorkspaceWatcher({
    required this.root,
    required this.onChanged,
    this.debounce = const Duration(milliseconds: 600),
  });

  final String root;
  final void Function() onChanged;
  final Duration debounce;

  StreamSubscription<FileSystemEvent>? _sub;
  Timer? _timer;
  bool _started = false;

  bool get isWatching => _started;

  Future<void> start() async {
    if (_started) return;
    try {
      _sub = Directory(root)
          .watch(recursive: true)
          .listen((_) => _poke(),
              onError: (Object _) {
        // 事件洪峰/平台限制等错误：丢弃事件但不打断（防抖回调已足够）
      });
      _started = true;
    } catch (_) {
      _started = false; // 平台不支持：静默降级为无监视
    }
  }

  void _poke() {
    _timer?.cancel();
    _timer = Timer(debounce, onChanged);
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _timer?.cancel();
    _timer = null;
    _started = false;
  }
}
