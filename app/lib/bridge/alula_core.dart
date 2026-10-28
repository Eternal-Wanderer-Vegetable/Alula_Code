/// Alula 核心的语义封装：TextOp 模型、版本管理、同步协议（docs/02 §2）。
///
/// 协议要点：
/// - 本地编辑先行（UI 不等待 FFI），随后以增量 op + baseVersion 提交；
/// - Rust 侧版本不符抛 [SyncMismatchException]，调用方应 [resync] 重建；
/// - 所有 offset 为 UTF-16 code unit（Dart String 与 LSP 的天然口径）。
library;

import 'dart:convert';

import 'alula_ffi.dart';

/// ABI/协议版本，与 crates/editor-core/src/ffi.rs 的 ALULA_ABI_VERSION 对应，
/// 加载时校验，防止 Rust 与 Dart 协议错位。
const int expectedAbiVersion = 5;

enum OpType { insert, delete }

/// 单个增量编辑操作（与 Rust editor_buffer::TextOp 的 JSON 序列化一一对应）。
class TextOp {
  final OpType type;
  final int offsetUtf16;
  final String? text; // insert
  final int? lenUtf16; // delete

  const TextOp.insert(this.offsetUtf16, this.text) : type = OpType.insert, lenUtf16 = null;

  const TextOp.delete(this.offsetUtf16, this.lenUtf16) : type = OpType.delete, text = null;

  Map<String, Object?> toJson() => switch (type) {
        OpType.insert => {
            'type': 'insert',
            'offset_utf16': offsetUtf16,
            'text': text,
          },
        OpType.delete => {
            'type': 'delete',
            'offset_utf16': offsetUtf16,
            'len_utf16': lenUtf16,
          },
      };
}

class SyncMismatchException implements Exception {
  /// Rust 侧当前版本，resync 前可用来判断落后程度。
  final int current;

  SyncMismatchException(this.current);

  @override
  String toString() => 'SyncMismatchException(Rust 侧版本已到 v$current)';
}

class AlulaException implements Exception {
  final String code;
  final String detail;

  AlulaException(this.code, this.detail);

  @override
  String toString() => 'AlulaException($code): $detail';
}

class ResyncResult {
  final int version;
  final String content;

  const ResyncResult(this.version, this.content);
}

/// LSP / 语法能力的语义封装（轮询式过渡方案，见 docs/02 §2.2）。
class AlulaLsp {
  final AlulaCore _core;

  AlulaLsp._(this._core);

  static AlulaLsp of(AlulaCore core) => AlulaLsp._(core);

  /// 启动语言服务器并挂接到文档。
  void start(int id, String workspaceRoot, List<String> cmd) {
    _check(_core._ffi.lspStartJson(id, workspaceRoot, jsonEncode(cmd)));
  }

  /// 关闭工作区服务及其所有关联文档。
  void shutdownWorkspace(String workspaceRoot) {
    _check(_core._ffi.lspShutdownWorkspaceJson(workspaceRoot));
  }

  /// 声明文档 URI（file:/// 形式）。
  void setUri(int id, String uri) {
    _check(_core._ffi.docSetUriJson(id, uri));
  }

  /// 以当前全文发送 didOpen。
  void didOpen(int id, {String languageId = 'rust'}) {
    _check(_core._ffi.lspDidOpenJson(id, languageId));
  }

  /// 最新诊断快照：{severity, line, character, message, source} 列表。
  List<Map<String, Object?>> diagnostics(int id) {
    final r = jsonDecode(_core._ffi.diagnosticsJson(id)) as Map<String, Object?>;
    if (r['ok'] != true) return const [];
    return (r['items'] as List).cast<Map<String, Object?>>();
  }

  /// 同步补全请求（阻塞至响应或超时；MVP 过渡，FRB 迁移后异步化）。
  List<String> completion(int id, int offsetUtf16, {int timeoutMs = 8000}) {
    final r = jsonDecode(_core._ffi.completionJson(id, offsetUtf16, timeoutMs))
        as Map<String, Object?>;
    if (r['ok'] != true) return const [];
    return (r['items'] as List).cast<String>();
  }

  /// 文档符号定义（大纲）：[{kind, name, start_utf16, line}]。
  ({int version, List<Map<String, Object?>> symbols})? symbols(int id) {
    final r = jsonDecode(_core._ffi.symbolsJson(id)) as Map<String, Object?>;
    if (r['ok'] != true) return null;
    return (
      version: r['version'] as int,
      symbols: (r['symbols'] as List).cast<Map<String, Object?>>(),
    );
  }

  /// Tree-sitter 语法 token：[{start_utf16, end_utf16, kind}]。
  ({int version, List<Map<String, Object?>> tokens})? syntax(int id) {
    final r = jsonDecode(_core._ffi.syntaxJson(id)) as Map<String, Object?>;
    if (r['ok'] != true) return null;
    return (
      version: r['version'] as int,
      tokens: (r['tokens'] as List).cast<Map<String, Object?>>(),
    );
  }

  /// didSave：触发 flycheck（cargo check 等）。
  void didSave(int id) {
    _check(_core._ffi.lspDidSaveJson(id));
  }
}

/// 工作区文件系统：目录枚举、文本文件读取。
class AlulaWorkspace {
  final AlulaCore _core;

  AlulaWorkspace._(this._core);

  static AlulaWorkspace of(AlulaCore core) => AlulaWorkspace._(core);

  /// 枚举目录：[{name, path, is_dir, size}]（目录在前）。
  List<Map<String, Object?>> listDir(String path) {
    final r = jsonDecode(_core._ffi.wsListDirJson(path)) as Map<String, Object?>;
    if (r['ok'] != true) {
      final err = r['error'];
      throw AlulaException(
        err is Map ? (err['code'] as String? ?? 'Unknown') : 'Unknown',
        jsonEncode(err),
      );
    }
    return (r['entries'] as List).cast<Map<String, Object?>>();
  }

  /// 读取 UTF-8 文本文件；二进制/非 UTF-8 抛 AlulaException('BinaryFile')。
  String readFile(String path) {
    final r = jsonDecode(_core._ffi.wsReadFileJson(path)) as Map<String, Object?>;
    if (r['ok'] != true) {
      final err = r['error'];
      throw AlulaException(
        err is Map ? (err['code'] as String? ?? 'Unknown') : 'Unknown',
        jsonEncode(err),
      );
    }
    return r['content'] as String;
  }
}

void _check(String json) {
  final r = jsonDecode(json) as Map<String, Object?>;
  if (r['ok'] != true) {
    final err = r['error'];
    throw AlulaException(
      err is Map ? (err['code'] as String? ?? 'Unknown') : 'Unknown',
      jsonEncode(err),
    );
  }
}

/// 文档句柄：封装 id 与本地版本号，提交增量操作。
class AlulaDoc {
  final AlulaCore core;
  final int id;

  /// 本地视角的当前版本（与 Rust 侧确认过的最新版本一致）。
  int version;

  AlulaDoc._(this.core, this.id, this.version);

  /// 提交一批增量操作；成功返回 Rust 确认的版本号（应等于 version + ops 数）。
  int apply(List<TextOp> ops) => applyWith(version, ops);

  /// 以显式 baseVersion 提交（正常编辑走 [apply]；测试与恢复路径用本方法）。
  int applyWith(int baseVersion, List<TextOp> ops) {
    final json = core._ffi
        .docApplyJson(id, baseVersion, jsonEncode(ops.map((o) => o.toJson()).toList()));
    final r = jsonDecode(json) as Map<String, Object?>;
    if (r['ok'] == true) {
      version = r['version'] as int;
      return version;
    }
    final err = r['error']! as Map<String, Object?>;
    if (err['code'] == 'VersionMismatch') {
      throw SyncMismatchException((err['detail'] as Map)['current'] as int);
    }
    throw AlulaException(err['code'] as String, jsonEncode(err['detail']));
  }

  /// 原子保存当前全文到路径（校验版本；docs/02 §6.3）。
  void saveFile(String path) {
    final json = core._ffi.docSaveFileJson(id, path, version);
    final r = jsonDecode(json) as Map<String, Object?>;
    if (r['ok'] != true) {
      final err = r['error']! as Map<String, Object?>;
      if (err['code'] == 'VersionMismatch') {
        throw SyncMismatchException((err['detail'] as Map)['current'] as int);
      }
      throw AlulaException(err['code'] as String, jsonEncode(err['detail']));
    }
  }

  /// 全量重同步：拉取 Rust 侧权威版本与全文。
  ResyncResult resync() {
    final r = jsonDecode(core._ffi.docResyncJson(id)) as Map<String, Object?>;
    if (r['ok'] == true) {
      version = r['version'] as int;
      return ResyncResult(version, r['content'] as String);
    }
    final err = r['error']! as Map<String, Object?>;
    throw AlulaException(err['code'] as String, jsonEncode(err['detail']));
  }

  void close() {
    core._ffi.docCloseJson(id);
  }
}

class AlulaCore {
  final AlulaFfi _ffi;

  AlulaCore._(this._ffi);

  /// 核心 ABI 版本（加载时已校验）。
  int get abiVersion => _ffi.abiVersion();

  /// LSP / 语法能力入口。
  AlulaLsp get lsp => AlulaLsp.of(this);

  /// 工作区文件系统入口。
  AlulaWorkspace get workspace => AlulaWorkspace.of(this);

  /// 加载动态库并校验 ABI 版本。
  factory AlulaCore.load() {
    final ffi = AlulaFfi(loadAlulaCore());
    final abi = ffi.abiVersion();
    if (abi != expectedAbiVersion) {
      throw StateError('Alula 核心 ABI 版本不匹配：期望 $expectedAbiVersion，实际 $abi。'
          '请重新运行 scripts/build_core。');
    }
    return AlulaCore._(ffi);
  }

  /// 打开文档（初始全量传输仅此一次）。
  AlulaDoc openDoc(int id, String content) {
    final r = jsonDecode(_ffi.docOpenJson(id, content)) as Map<String, Object?>;
    if (r['ok'] != true) {
      final err = r['error']! as Map<String, Object?>;
      throw AlulaException(err['code'] as String, jsonEncode(err['detail']));
    }
    return AlulaDoc._(this, id, r['version'] as int);
  }
}
