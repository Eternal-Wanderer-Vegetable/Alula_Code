// 评测公共工具：大文档生成与计时。
library;

/// 生成 lines 行的测试文档，混合中英文，模拟真实代码密度。
String makeDoc(int lines) {
  final sb = StringBuffer();
  for (var i = 0; i < lines; i++) {
    switch (i % 5) {
      case 0:
        sb.writeln('/// 函数 $i：计算第 $i 个斐波那契数值并返回结果。');
      case 1:
        sb.writeln('fn sample_$i(x: i32) -> i32 {');
      case 2:
        sb.writeln('    let delta = x * $i + "注释$i".len() as i32;');
      case 3:
        sb.writeln('    return delta - $i; // trailing comment');
      default:
        sb.writeln('}');
    }
  }
  return sb.toString();
}

typedef TimedFn<T> = T Function();

/// 返回 (结果, 耗时毫秒)。
(double, T) timedMs<T>(TimedFn<T> fn) {
  final sw = Stopwatch()..start();
  final result = fn();
  sw.stop();
  return (sw.elapsedMicroseconds / 1000.0, result);
}
