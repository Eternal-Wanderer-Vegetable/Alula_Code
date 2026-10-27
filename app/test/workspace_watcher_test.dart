// WorkspaceWatcher 单测：真实文件系统事件、防抖收敛、stop 后不再回调。
import 'dart:io';

import 'package:alula_app/workspace/workspace_watcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('alula_watch_test');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('多次写入防抖收敛为单次回调', () async {
    var calls = 0;
    final w = WorkspaceWatcher(
        root: dir.path,
        debounce: const Duration(milliseconds: 150),
        onChanged: () => calls++);
    await w.start();

    File('${dir.path}${Platform.pathSeparator}a.txt').writeAsStringSync('1');
    File('${dir.path}${Platform.pathSeparator}b.txt').writeAsStringSync('2');
    File('${dir.path}${Platform.pathSeparator}c.txt').writeAsStringSync('3');
    await Future<void>.delayed(const Duration(milliseconds: 600));

    expect(calls, 1, reason: '防抖窗口内的多次事件只触发一次回调');
    await w.stop();
  });

  test('stop 后外部变更不再触发', () async {
    var calls = 0;
    final w = WorkspaceWatcher(
        root: dir.path,
        debounce: const Duration(milliseconds: 100),
        onChanged: () => calls++);
    await w.start();
    await w.stop();

    File('${dir.path}${Platform.pathSeparator}x.txt').writeAsStringSync('x');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(calls, 0, reason: 'stop 后不再回调');
  });

  test('子目录事件也触发（递归）', () async {
    var calls = 0;
    final w = WorkspaceWatcher(
        root: dir.path,
        debounce: const Duration(milliseconds: 100),
        onChanged: () => calls++);
    await w.start();

    final sub = Directory('${dir.path}${Platform.pathSeparator}sub')
      ..createSync();
    File('${sub.path}${Platform.pathSeparator}f.txt').writeAsStringSync('x');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(calls, greaterThanOrEqualTo(1), reason: '递归监视应捕获子目录事件');
    await w.stop();
  });
}
