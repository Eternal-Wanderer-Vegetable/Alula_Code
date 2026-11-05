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
  int _generation = 0;

  bool get isWatching => _started;

  Future<void> start() async {
    if (_started) return;
    final generation = ++_generation;
    _started = true;
    try {
      final subscription = Directory(root).watch(recursive: true).listen((_) {
        if (generation == _generation && _started) _poke(generation);
      }, onError: (Object _) {
        // 事件洪峰/平台限制等错误：丢弃事件但不打断（防抖回调已足够）
      });
      if (generation != _generation) {
        await subscription.cancel();
        return;
      }
      _sub = subscription;
    } catch (_) {
      _sub = null;
      _started = false; // 平台不支持：静默降级为无监视
    }
  }

  void _poke(int generation) {
    _timer?.cancel();
    _timer = Timer(debounce, () {
      if (generation == _generation && _started) onChanged();
    });
  }

  Future<void> stop() async {
    ++_generation;
    _started = false;
    _timer?.cancel();
    _timer = null;
    final subscription = _sub;
    _sub = null;
    await subscription?.cancel();
  }
}
