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

  test('Rust 示例词删除通过 FFI 可撤销并保存回读', () async {
    final core = _bootstrap.core!;
    const sample = 'fn main() { println!("linux-save-ok"); }\n';
    final doc = core.openDoc(9009, sample);
    final wordEnd = sample.indexOf('linux') + 'linux'.length;
    final resolved = doc.wordDeleteRanges([wordEnd], left: true);
    expect(resolved.version, 1);
    expect(resolved.ranges, hasLength(1));
    expect(resolved.ranges.single.startUtf16, wordEnd - 'linux'.length);
    expect(resolved.ranges.single.endUtf16, wordEnd);

    final range = resolved.ranges.single;
    doc.apply(
        [TextOp.delete(range.startUtf16, range.endUtf16 - range.startUtf16)]);
    final edited = sample.replaceRange(range.startUtf16, range.endUtf16, '');
    expect(doc.resync().content, edited);

    final temporary =
        await Directory.systemTemp.createTemp('alula_word_delete');
    final path = '${temporary.path}${Platform.pathSeparator}main.rs';
    addTearDown(() async {
      doc.close();
      if (temporary.existsSync()) await temporary.delete(recursive: true);
    });
    doc.saveFile(path);
    expect(await File(path).readAsString(), edited);

    doc.apply([TextOp.insert(range.startUtf16, 'linux')]);
    expect(doc.resync().content, sample);
    doc.saveFile(path);
    expect(await File(path).readAsString(), sample);
  }, skip: skip);

  test('Rust 示例行边界删除通过 FFI 标脏并保存回读', () async {
    final core = _bootstrap.core!;
    const sample = 'fn main() { println!("linux-save-ok"); }\n';
    final doc = core.openDoc(9040, sample);
    final selectedEnd = sample.indexOf('println!') + 'println!'.length;
    final resolved = doc.lineDeleteRanges(
      [DocumentDeleteRange(startUtf16: selectedEnd - 2, endUtf16: selectedEnd)],
      left: true,
    );
    expect(resolved.version, 1);
    expect(resolved.ranges, hasLength(1));
    expect(resolved.ranges.single.startUtf16, 0);
    expect(resolved.ranges.single.endUtf16, selectedEnd);

    final range = resolved.ranges.single;
    doc.apply(
      [TextOp.delete(range.startUtf16, range.endUtf16 - range.startUtf16)],
    );
    final edited = sample.replaceRange(range.startUtf16, range.endUtf16, '');
    expect(doc.resync().content, edited);
    expect(doc.isDirty, isTrue);

    final temporary =
        await Directory.systemTemp.createTemp('alula_line_delete');
    final path = '${temporary.path}${Platform.pathSeparator}main.rs';
    addTearDown(() async {
      doc.close();
      if (temporary.existsSync()) await temporary.delete(recursive: true);
    });
    doc.saveFile(path);
    doc.markSaved();
    expect(await File(path).readAsString(), edited);
    expect(doc.isDirty, isFalse);
  }, skip: skip);

  test('Rust 覆写粘贴范围通过 FFI 保留 UTF-16、BOM、emoji 与 CRLF', () {
    final core = _bootstrap.core!;
    final doc = core.openDoc(9070, '\uFEFFa🦊b\r\nxyz');
    final resolved = doc.overtypePasteRanges(const [
      DocumentOvertypePasteSelection(
        startUtf16: 2,
        endUtf16: 2,
        insertedUtf16: 2,
      ),
      DocumentOvertypePasteSelection(
        startUtf16: 2,
        endUtf16: 4,
        insertedUtf16: 1,
      ),
      DocumentOvertypePasteSelection(
        startUtf16: 4,
        endUtf16: 4,
        insertedUtf16: 99,
      ),
      DocumentOvertypePasteSelection(
        startUtf16: 7,
        endUtf16: 7,
        insertedUtf16: 1,
      ),
    ]);
    expect(resolved.version, 1);
    expect(
      resolved.ranges
          .map((range) => (range.startUtf16, range.endUtf16))
          .toList(),
      const [(2, 4), (2, 4), (4, 5), (7, 8)],
    );
    expect(
      () => doc.overtypePasteRanges(const [
        DocumentOvertypePasteSelection(
          startUtf16: 3,
          endUtf16: 3,
          insertedUtf16: 1,
        ),
      ]),
      throwsA(isA<AlulaException>()),
    );
    doc.close();
  }, skip: skip);

  test('didClose 只关闭语言文档，不释放 Rust 文本缓冲区', () {
    final core = _bootstrap.core!;
    final doc = core.openDoc(9006, 'kept after didClose');
    core.lsp.setUri(doc.id, 'file:///kept-after-did-close.txt');
    core.lsp.didClose(doc.id);
    expect(doc.resync().content, 'kept after didClose');
    doc.close();
  }, skip: skip);

  test('LSP position conversions keep UTF-16, BOM, emoji and CRLF semantics',
      () {
    final core = _bootstrap.core!;
    final doc = core.openDoc(9008, '\uFEFFa🦊\r\nb\n');

    final afterEmoji = doc.positionAt(4);
    expect(afterEmoji.version, 1);
    expect(afterEmoji.line, 0);
    expect(afterEmoji.character, 4);

    final splitPair = doc.positionOffset(0, 3);
    expect(splitPair.offsetUtf16, 2);
    expect(splitPair.character, 2);
    expect(doc.positionOffset(0, 99).offsetUtf16, 4);
    expect(doc.positionOffset(1, 1).offsetUtf16, 7);
    expect(doc.positionOffset(2, 0).offsetUtf16, 8);
    expect(() => doc.positionAt(3), throwsA(isA<AlulaException>()));
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

  test('Rust 按行 UTF-16 起点定位支持 BOM、emoji、CRLF 和末尾空行', () {
    final doc = _bootstrap.core!.openDoc(9032, '\u{FEFF}a🦊\r\nb\n');
    final first = doc.lineOffset(0);
    final second = doc.lineOffset(1);
    final finalEmpty = doc.lineOffset(2);

    expect(first.offsetUtf16, 0);
    expect(second.offsetUtf16, 6);
    expect(finalEmpty.offsetUtf16, 8);
    expect(finalEmpty.totalUtf16Length, 8);
    expect(finalEmpty.lineCount, 3);
    expect(finalEmpty.version, 1);
    expect(
      doc.readRange(second.offsetUtf16, maxLenUtf16: 2).text,
      'b\n',
    );
    expect(
      () => doc.lineOffset(3),
      throwsA(
          isA<AlulaException>().having((e) => e.code, 'code', 'InvalidLine')),
    );
    expect(() => doc.lineOffset(-1), throwsRangeError);
    doc.close();
  }, skip: skip);

  test('Rust 一次返回有界矩形选择并保持 UTF-16 标量边界', () {
    final doc = _bootstrap.core!.openDoc(9033, '\u{FEFF}a\n🦊xy\r\nz');
    final result = doc.columnSelectionsUtf16(
      anchorLine: 0,
      anchorColumnUtf16: 0,
      activeLine: 2,
      activeColumnUtf16: 1,
      maxSelections: 10,
    );

    expect(result.version, 1);
    expect(
      result.selections
          .map((selection) => (
                selection.line,
                selection.baseOffsetUtf16,
                selection.extentOffsetUtf16,
              ))
          .toList(),
      [(2, 9, 10), (0, 0, 1), (1, 3, 5)],
    );
    expect(
      () => doc.columnSelectionsUtf16(
        anchorLine: 0,
        anchorColumnUtf16: 0,
        activeLine: 2,
        activeColumnUtf16: 1,
        maxSelections: 2,
      ),
      throwsA(
        isA<AlulaException>().having(
          (error) => error.code,
          'code',
          'ReadLineCountTooLarge',
        ),
      ),
    );
    doc.close();
  }, skip: skip);

  test('Rust 行边界按 UTF-16 返回 smart Home、End 与 CRLF 位置', () {
    final doc = _bootstrap.core!.openDoc(9039, '\t 🦊value\r\nnext\n');
    final first = doc.lineBoundary(5);
    expect(first.version, 1);
    expect(first.line, 0);
    expect(first.startUtf16, 0);
    expect(first.firstNonWhitespaceUtf16, 2);
    expect(first.endUtf16, 9);

    final nextLine = doc.lineBoundary(12);
    expect(nextLine.line, 1);
    expect(nextLine.startUtf16, 11);
    expect(nextLine.firstNonWhitespaceUtf16, 11);
    expect(nextLine.endUtf16, 15);

    expect(
      () => doc.lineBoundary(3),
      throwsA(isA<AlulaException>()
          .having((error) => error.code, 'code', 'InvalidUtf16Offset')),
    );
    doc.close();
  }, skip: skip);

  test('Rust 可视区批量按行读取保留 UTF-16 边界并支持长行窗口', () {
    final doc = _bootstrap.core!.openDoc(9033, '\u{FEFF}a🦊\r\nsecond\n');
    final page = doc.readLines(
      firstLine: 0,
      maxLines: 2,
      horizontalStartUtf16: 0,
      maxLineUtf16: 8,
      maxTotalUtf16: 16,
    );
    expect(page.version, 1);
    expect(page.totalUtf16Length, 13);
    expect(page.lineCount, 3);
    expect(page.lines.map((line) => line.text), ['\u{FEFF}a🦊', 'second']);
    expect(
      page.lines.map((line) => (line.startUtf16, line.endUtf16)),
      [(0, 4), (6, 12)],
    );

    final horizontal = doc.readLines(
      firstLine: 0,
      maxLines: 2,
      horizontalStartUtf16: 3,
      maxLineUtf16: 8,
      maxTotalUtf16: 16,
    );
    expect(horizontal.lines[0].text, '🦊');
    expect(horizontal.lines[0].startUtf16, 2);
    expect(horizontal.lines[1].text, 'ond');

    final longLine = _bootstrap.core!.openDoc(9034, '${'x' * 90000}🦊tail');
    final tail = longLine.readLines(
      firstLine: 0,
      maxLines: 1,
      horizontalStartUtf16: 90000,
      maxLineUtf16: 2048,
      maxTotalUtf16: 2048,
    );
    expect(tail.lines.single.text, '🦊tail');
    expect(tail.lines.single.startUtf16, 90000);
    expect(tail.lines.single.endUtf16, 90006);
    doc.close();
    longLine.close();
  }, skip: skip);

  test('Rust minimap 抽样按文档版本返回有界均匀行前缀', () {
    final wideLine = 'x' * 80;
    final content = [
      '\u{FEFF}🦊 first',
      for (var line = 1; line < 999; line++) 'line-$line $wideLine',
      'last\r',
      '',
    ].join('\n');
    final doc = _bootstrap.core!.openDoc(9035, content);

    final sample = doc.readMinimapSample();

    expect(sample.version, doc.version);
    expect(sample.lineCount, 1001);
    expect(sample.totalUtf16Length, content.length);
    expect(sample.lines, hasLength(maxDocMinimapSampleLines));
    expect(sample.lines.first.line, 0);
    expect(sample.lines.last.line, 1000);
    expect(sample.lines.first.startUtf16, 0);
    expect(sample.lines[1].line, 1);
    expect(sample.lines[1].startUtf16, content.split('\n').first.length + 1);
    expect(sample.lines.last.startUtf16, content.length);
    expect(
      sample.lines.every((line) => line.text.length <= 48),
      isTrue,
    );
    expect(sample.lines.first.text, '\u{FEFF}🦊 first');
    expect(sample.lines.first.utf16Length, '\u{FEFF}🦊 first'.length);
    expect(
      sample.lines.skip(1).every((line) =>
          line.line > sample.lines[sample.lines.indexOf(line) - 1].line),
      isTrue,
    );
    doc.close();
  }, skip: skip);

  test('Rust 符号 FFI 返回包含 BOM emoji CRLF 的闭合行范围', () {
    const content =
        '\u{FEFF}// 🦊\r\nfn outer() {\r\n    fn inner() {}\r\n}\r\n';
    final doc = _bootstrap.core!.openDoc(9036, content);
    final result = doc.core.lsp.symbols(doc.id)!;
    final outer =
        result.symbols.singleWhere((symbol) => symbol['name'] == 'outer');
    final inner =
        result.symbols.singleWhere((symbol) => symbol['name'] == 'inner');

    expect(result.version, doc.version);
    expect(outer['line'], 2);
    expect(outer['end_line'], 4);
    expect(outer['start_utf16'], '\u{FEFF}// 🦊\r\n'.length);
    expect(inner['line'], 3);
    expect(inner['end_line'], 3);
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
