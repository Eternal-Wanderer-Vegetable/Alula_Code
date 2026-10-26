// Dart ↔ Rust 闭环集成测试：加载动态库，走「打开→增量应用→失配→resync」全流程。
//
// 前置条件：已运行 scripts/build_core（或 cargo build -p editor-core）。
// 库缺失时整组测试自动跳过，不作为失败。
import 'package:alula_app/bridge/alula_core.dart';
import 'package:flutter_test/flutter_test.dart';

class _Bootstrap {
  final AlulaCore? core;
  final String? error;

  _Bootstrap._(this.core, this.error);

  factory _Bootstrap() {
    try {
      return _Bootstrap._(AlulaCore.load(), null);
    } catch (e) {
      return _Bootstrap._(
          null, 'alula_core 动态库未构建：请先运行 scripts/build_core（$e）');
    }
  }
}

final _Bootstrap _bootstrap = _Bootstrap();
final skip = _bootstrap.error;

void main() {
  test('ABI 版本匹配', () {
    expect(_bootstrap.core!.abiVersion, expectedAbiVersion);
  }, skip: skip);

  test('打开→插入→版本回执→resync 全文一致', () {
    final doc = _bootstrap.core!.openDoc(9001, 'fn main() {}\n');
    expect(doc.version, 1);

    final v = doc.apply([
      const TextOp.insert(11, '// hello'),
    ]);
    expect(v, 2);
    expect(doc.version, 2);

    final r = doc.resync();
    expect(r.version, 2);
    expect(r.content, 'fn main() {// hello}\n');
  }, skip: skip);

  test('过期版本被拒绝并给出 Rust 当前版本', () {
    final doc = _bootstrap.core!.openDoc(9002, 'x');
    expect(
      () => doc.applyWith(0, []),
      throwsA(isA<SyncMismatchException>()
          .having((e) => e.current, 'current', 1)),
    );
  }, skip: skip);

  test('中文与 emoji 混排增量在 FFI 边界正确', () {
    const initial = '运行 🚀 model\n';
    final doc = _bootstrap.core!.openDoc(9003, initial);

    // 删除 🚀（UTF-16 3..5），插入 🛰️
    doc.apply([
      const TextOp.delete(3, 2),
      const TextOp.insert(3, '🛰️'),
    ]);
    final r = doc.resync();
    expect(r.content, '运行 🛰️ model\n');
    expect(r.version, 3);
  }, skip: skip);

  test('先删后插的 op 序列在 Rust 侧按序生效', () {
    final doc = _bootstrap.core!.openDoc(9004, '{}');
    doc.apply([
      const TextOp.insert(1, 'a'),
      const TextOp.insert(2, 'b'),
      const TextOp.delete(1, 2),
      const TextOp.insert(1, 'c'),
    ]);
    expect(doc.resync().content, '{c}');
  }, skip: skip);

  test('非法 UTF-16 边界（代理对中间）被 Rust 拒绝', () {
    final doc = _bootstrap.core!.openDoc(9005, 'a🚀b');
    // 🚀 占 UTF-16 1..3，offset 2 在代理对中间
    expect(
      () => doc.applyWith(1, [const TextOp.insert(2, 'z')]),
      throwsA(
          isA<AlulaException>().having((e) => e.code, 'code', 'BufferError')),
    );
    // 失败后版本未变，后续正常编辑不受影响
    final v = doc.apply([const TextOp.insert(0, 'z')]);
    expect(v, 2);
  }, skip: skip);
}
