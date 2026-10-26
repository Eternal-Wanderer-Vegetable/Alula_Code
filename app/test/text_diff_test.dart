// diff → op 计算的单元测试（纯 Dart，无需动态库）。
import 'package:alula_app/bridge/alula_core.dart';
import 'package:alula_app/editor/text_diff.dart';
import 'package:flutter_test/flutter_test.dart';

bool _isHighSurrogate(int cu) => cu >= 0xD800 && cu <= 0xDBFF;
bool _isLowSurrogate(int cu) => cu >= 0xDC00 && cu <= 0xDFFF;

List<TextOp> _ops(String a, String b) => diffToOps(a, b);

/// 用 op 序列重建文本，验证 diff 正确性（String.replaceRange 按 UTF-16 code unit 运算）。
String _replay(String oldText, List<TextOp> ops) {
  var s = oldText;
  for (final op in ops) {
    switch (op.type) {
      case OpType.delete:
        s = s.replaceRange(op.offsetUtf16, op.offsetUtf16 + op.lenUtf16!, '');
      case OpType.insert:
        s = s.replaceRange(op.offsetUtf16, op.offsetUtf16, op.text!);
    }
  }
  return s;
}

void main() {
  test('相同文本返回空操作', () {
    expect(_ops('abc', 'abc'), isEmpty);
  });

  test('尾部插入', () {
    final ops = _ops('hello', 'hello world');
    expect(ops, hasLength(1));
    expect(ops.first.type, OpType.insert);
    expect(ops.first.offsetUtf16, 5);
    expect(_replay('hello', ops), 'hello world');
  });

  test('中间替换 = 删除+插入', () {
    // 公共前缀 'print(h'（7），公共后缀 ')'（1）：实际只替换 'i' → 'ey'
    final ops = _ops('print(hi)', 'print(hey)');
    expect(ops, hasLength(2));
    expect(ops[0].type, OpType.delete);
    expect(ops[0].offsetUtf16, 7);
    expect(ops[0].lenUtf16, 1);
    expect(ops[1].type, OpType.insert);
    expect(ops[1].offsetUtf16, 7);
    expect(ops[1].text, 'ey');
    expect(_replay('print(hi)', ops), 'print(hey)');
  });

  test('中文与 emoji 混排：边界不切代理对', () {
    const a = '运行 🚀 model';
    const b = '运行 🚀 models!';
    final ops = _ops(a, b);
    expect(_replay(a, ops), b);
    // 所有 offset 必须落在合法 UTF-16 边界上
    for (final op in ops) {
      expect(_isValidBoundary(a, op.offsetUtf16), isTrue,
          reason: 'op offset ${op.offsetUtf16} 落在代理对中间');
    }
  });

  test('整段替换一个 emoji（前缀与后缀都含代理对）', () {
    const a = '前🚀后';
    const b = '前🛰️后';
    final ops = _ops(a, b);
    expect(_replay(a, ops), b);
  });

  test('清空与全量重写', () {
    expect(_replay('abc', _ops('abc', '')), '');
    expect(_replay('', _ops('', '新内容')), '新内容');
  });

  test('随机对拍：100 组编辑前后文本的 diff 均可精确重建', () {
    final rng = _Rng(20261025);
    for (var i = 0; i < 100; i++) {
      final a = _randomText(rng);
      final b = _mutate(a, rng);
      final ops = _ops(a, b);
      expect(_replay(a, ops), b, reason: '第 $i 组失败\n  a=$a\n  b=$b');
    }
  });
}

bool _isValidBoundary(String s, int offset) {
  if (offset <= 0 || offset >= s.length) return true;
  return !(_isLowSurrogate(s.codeUnitAt(offset)) &&
      _isHighSurrogate(s.codeUnitAt(offset - 1)));
}

String _randomText(_Rng rng) {
  const pool = ['a', 'b', '中', '文', '🚀', 'x', '\n', ' ', 'é'];
  final n = rng.nextInt(20);
  final sb = StringBuffer();
  for (var i = 0; i < n; i++) {
    sb.write(pool[rng.nextInt(pool.length)]);
  }
  return sb.toString();
}

String _mutate(String s, _Rng rng) {
  if (s.isEmpty) return 'seed';
  final kind = rng.nextInt(3);
  final pos = rng.nextInt(s.length + 1);
  switch (kind) {
    case 0: // 插入
      return s.replaceRange(pos, pos, '新🚀');
    case 1: // 删除
      final end = pos + 1 > s.length ? s.length : pos + 1;
      return s.replaceRange(pos, end, '');
    default: // 替换
      final end = pos + 2 > s.length ? s.length : pos + 2;
      return s.replaceRange(pos, end, '改');
  }
}

class _Rng {
  int _state;
  _Rng(this._state);

  int nextInt(int max) {
    _state = (_state * 1103515245 + 12345) & 0x7FFFFFFF;
    return _state % max;
  }
}
