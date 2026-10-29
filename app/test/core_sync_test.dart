// Dart ↔ Rust 闭环集成测试：加载动态库，走「打开→增量应用→失配→resync」全流程。
//
// 前置条件：已运行 scripts/build_core（或 cargo build -p editor-core）。
// 库缺失时整组测试自动跳过，不作为失败。
import 'dart:io';

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

  test('didClose 只关闭语言文档，不释放 Rust 文本缓冲区', () {
    final core = _bootstrap.core!;
    final doc = core.openDoc(9006, 'kept after didClose');
    core.lsp.setUri(doc.id, 'file:///kept-after-did-close.txt');
    core.lsp.didClose(doc.id);
    expect(doc.resync().content, 'kept after didClose');
    doc.close();
  }, skip: skip);

  test('资源状态与进程登记桥接可往返', () {
    final core = _bootstrap.core!;
    final status = core.runtime.sampleResourceStatus();
    expect({'normal', 'warn', 'critical'}, contains(status.pressure));
    expect(status.totalBytes, greaterThan(0));
    expect(status.availableBytes, lessThanOrEqualTo(status.totalBytes));

    const pid = 4000000000;
    core.runtime.registerProcess(pid, 'task', 'bridge fixture', null);
    try {
      expect(core.runtime.processSnapshot(), isA<List<AlulaManagedProcess>>());
    } finally {
      core.runtime.unregisterProcess(pid);
    }
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

  test('Rust 权威文档 UTF-16 范围读取有界且不拆代理对', () {
    final doc = _bootstrap.core!.openDoc(9030, '\u{FEFF}甲🦊\r\nsecond');

    final first = doc.readRange(0, maxLenUtf16: 3);
    expect(first.text, '\u{FEFF}甲');
    expect(first.version, 1);
    expect(first.totalUtf16Length, 12);
    expect(first.lineCount, 2);
    expect(first.startUtf16, 0);
    expect(first.endUtf16, 2);
    expect((first.startLine, first.startCharacter), (0, 0));

    final emoji = doc.readRange(2, maxLenUtf16: 1);
    expect(emoji.text, '🦊');
    expect(emoji.endUtf16, 4);
    expect((emoji.startLine, emoji.startCharacter), (0, 2));

    final secondLine = doc.readRange(6, maxLenUtf16: 6);
    expect(secondLine.text, 'second');
    expect((secondLine.startLine, secondLine.startCharacter), (1, 0));

    expect(
      () => doc.readRange(3, maxLenUtf16: 1),
      throwsA(isA<AlulaException>()
          .having((e) => e.code, 'code', 'InvalidUtf16Offset')),
    );
    expect(
      () => doc.readRange(0, maxLenUtf16: maxDocReadRangeUtf16 + 1),
      throwsA(isA<AlulaException>()
          .having((e) => e.code, 'code', 'ReadRangeTooLarge')),
    );

    doc.apply([const TextOp.insert(0, 'x')]);
    expect(doc.readRange(0, maxLenUtf16: 1).version, 2);
    doc.close();
  }, skip: skip);

  test('超长单行可按 UTF-16 页读取而不返回全文', () {
    final doc = _bootstrap.core!.openDoc(9031, List.filled(100000, 'x').join());
    final page = doc.readRange(49000, maxLenUtf16: 4096);
    expect(page.text, List.filled(4096, 'x').join());
    expect(page.totalUtf16Length, 100000);
    expect(page.lineCount, 1);
    expect(page.endUtf16, 53096);
    doc.close();
  }, skip: skip);

  test('过期版本被拒绝并给出 Rust 当前版本', () {
    final doc = _bootstrap.core!.openDoc(9002, 'x');
    expect(
      () => doc.applyWith(0, []),
      throwsA(
          isA<SyncMismatchException>().having((e) => e.current, 'current', 1)),
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

  test('跨文档 FFI 事务成功提交且版本失败时整体不变', () {
    final core = _bootstrap.core!;
    final first = core.openDoc(9020, 'alpha');
    final second = core.openDoc(9021, 'beta');
    try {
      final result = core.applyWorkspaceEdit([
        AlulaWorkspaceEditDocument(
          id: first.id,
          baseVersion: first.version,
          ops: const [TextOp.insert(5, '!')],
        ),
        AlulaWorkspaceEditDocument(
          id: second.id,
          baseVersion: second.version,
          ops: const [TextOp.insert(0, 'new ')],
        ),
      ]);
      first.version = result.versions[first.id]!;
      second.version = result.versions[second.id]!;
      expect(first.resync().content, 'alpha!');
      expect(second.resync().content, 'new beta');

      expect(
        () => core.applyWorkspaceEdit([
          AlulaWorkspaceEditDocument(
            id: first.id,
            baseVersion: first.version,
            ops: const [TextOp.insert(0, 'changed ')],
          ),
          AlulaWorkspaceEditDocument(
            id: second.id,
            baseVersion: 1,
            ops: const [TextOp.insert(0, 'changed ')],
          ),
        ]),
        throwsA(isA<AlulaException>().having(
          (error) => error.code,
          'code',
          'VersionMismatch',
        )),
      );
      expect(first.resync().content, 'alpha!');
      expect(second.resync().content, 'new beta');
    } finally {
      first.close();
      second.close();
    }
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

  test('文件 FFI 往返保留 UTF-16 BOM 与 CRLF 元数据', () async {
    final core = _bootstrap.core!;
    final temp = await Directory.systemTemp.createTemp('alula_codec_');
    try {
      final source = File('${temp.path}/source.txt');
      await source.writeAsBytes([
        0xFF, 0xFE, // UTF-16 LE BOM
        0x41, 0x00, // A
        0x0D, 0x00, // CR
        0x0A, 0x00, // LF
        0x42, 0x00, // B
      ]);
      final decoded = core.workspace.readFileDocument(source.path);
      expect(decoded.content, 'A\nB');
      expect(decoded.options.encoding, TextEncoding.utf16Le);
      expect(decoded.options.bom, isTrue);
      expect(decoded.options.lineEnding, TextLineEnding.crlf);

      final doc = core.openDoc(9010, decoded.content);
      final target = '${temp.path}/roundtrip.txt';
      doc.saveFile(target, options: decoded.options);
      expect(await File(target).readAsBytes(), await source.readAsBytes());
      doc.close();
    } finally {
      await temp.delete(recursive: true);
    }
  }, skip: skip);

  test('GBK 编码保存遇到不可表示字符时不覆盖目标文件', () async {
    final core = _bootstrap.core!;
    final temp = await Directory.systemTemp.createTemp('alula_gbk_');
    final target = File('${temp.path}/keep.txt')..writeAsStringSync('keep');
    final doc = core.openDoc(9011, '🚀');
    try {
      expect(
        () => doc.saveFile(
          target.path,
          options: const TextFileOptions(
            encoding: TextEncoding.gbk,
            bom: false,
            lineEnding: TextLineEnding.lf,
          ),
        ),
        throwsA(isA<AlulaException>().having(
          (error) => error.code,
          'code',
          'UnrepresentableCharacter',
        )),
      );
      expect(target.readAsStringSync(), 'keep');
    } finally {
      doc.close();
      await temp.delete(recursive: true);
    }
  }, skip: skip);
}
