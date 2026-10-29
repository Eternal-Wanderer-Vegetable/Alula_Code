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
const int expectedAbiVersion = 15;
const int maxDocReadRangeUtf16 = 64 * 1024;
const int maxDocReadLines = 256;

enum TextEncoding { utf8, utf16Le, utf16Be, gbk }

extension TextEncodingInfo on TextEncoding {
  String get id => switch (this) {
        TextEncoding.utf8 => 'utf-8',
        TextEncoding.utf16Le => 'utf-16le',
        TextEncoding.utf16Be => 'utf-16be',
        TextEncoding.gbk => 'gbk',
      };

  String label({required bool bom}) => switch (this) {
        TextEncoding.utf8 => bom ? 'UTF-8 with BOM' : 'UTF-8',
        TextEncoding.utf16Le => 'UTF-16 LE${bom ? '' : ' (no BOM)'}',
        TextEncoding.utf16Be => 'UTF-16 BE${bom ? '' : ' (no BOM)'}',
        TextEncoding.gbk => 'GBK',
      };

  static TextEncoding? fromId(String? id) => switch (id?.toLowerCase()) {
        'utf-8' || 'utf8' => TextEncoding.utf8,
        'utf-16le' || 'utf16le' => TextEncoding.utf16Le,
        'utf-16be' || 'utf16be' => TextEncoding.utf16Be,
        'gbk' || 'gb2312' => TextEncoding.gbk,
        _ => null,
      };
}

enum TextLineEnding { lf, crlf }

extension TextLineEndingInfo on TextLineEnding {
  String get id => this == TextLineEnding.crlf ? 'crlf' : 'lf';
  String get label => this == TextLineEnding.crlf ? 'CRLF' : 'LF';

  static TextLineEnding? fromId(String? id) => switch (id?.toLowerCase()) {
        'lf' => TextLineEnding.lf,
        'crlf' => TextLineEnding.crlf,
        _ => null,
      };
}

class TextFileOptions {
  const TextFileOptions({
    required this.encoding,
    required this.bom,
    required this.lineEnding,
  });

  static const defaults = TextFileOptions(
    encoding: TextEncoding.utf8,
    bom: false,
    lineEnding: TextLineEnding.lf,
  );

  final TextEncoding encoding;
  final bool bom;
  final TextLineEnding lineEnding;

  TextFileOptions copyWith({
    TextEncoding? encoding,
    bool? bom,
    TextLineEnding? lineEnding,
  }) =>
      TextFileOptions(
        encoding: encoding ?? this.encoding,
        bom: bom ?? this.bom,
        lineEnding: lineEnding ?? this.lineEnding,
      );

  factory TextFileOptions.fromJson(Map<String, Object?> json) {
    return TextFileOptions(
      encoding: TextEncodingInfo.fromId(json['encoding'] as String?) ??
          TextEncoding.utf8,
      bom: json['bom'] == true,
      lineEnding: TextLineEndingInfo.fromId(json['lineEnding'] as String?) ??
          TextLineEnding.lf,
    );
  }

  Map<String, Object?> toJson() => {
        'encoding': encoding.id,
        'bom': bom,
        'lineEnding': lineEnding.id,
      };

  String get label => encoding.label(bom: bom);

  String get statusLabel => switch (encoding) {
        TextEncoding.utf8 => bom ? 'UTF-8 BOM' : 'UTF-8',
        TextEncoding.utf16Le => bom ? 'UTF-16 LE BOM' : 'UTF-16 LE',
        TextEncoding.utf16Be => bom ? 'UTF-16 BE BOM' : 'UTF-16 BE',
        TextEncoding.gbk => 'GBK',
      };

  @override
  bool operator ==(Object other) =>
      other is TextFileOptions &&
      other.encoding == encoding &&
      other.bom == bom &&
      other.lineEnding == lineEnding;

  @override
  int get hashCode => Object.hash(encoding, bom, lineEnding);
}

class DecodedTextFile {
  const DecodedTextFile({required this.content, required this.options});

  final String content;
  final TextFileOptions options;
}

enum OpType { insert, delete }

/// 单个增量编辑操作（与 Rust editor_buffer::TextOp 的 JSON 序列化一一对应）。
class TextOp {
  final OpType type;
  final int offsetUtf16;
  final String? text; // insert
  final int? lenUtf16; // delete

  const TextOp.insert(this.offsetUtf16, this.text)
      : type = OpType.insert,
        lenUtf16 = null;

  const TextOp.delete(this.offsetUtf16, this.lenUtf16)
      : type = OpType.delete,
        text = null;

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

/// A single document's operation batch inside an atomic workspace transaction.
class AlulaWorkspaceEditDocument {
  const AlulaWorkspaceEditDocument({
    required this.id,
    required this.baseVersion,
    required this.ops,
  });

  final int id;
  final int baseVersion;
  final List<TextOp> ops;

  Map<String, Object?> toJson() => {
        'id': id,
        'base_version': baseVersion,
        'ops': ops.map((op) => op.toJson()).toList(),
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

/// A bounded snapshot from the Rust-authoritative document.
class TextRangeRead {
  final int version;
  final int totalUtf16Length;
  final int lineCount;
  final int startUtf16;
  final int endUtf16;
  final int startLine;
  final int startCharacter;
  final String text;

  const TextRangeRead({
    required this.version,
    required this.totalUtf16Length,
    required this.lineCount,
    required this.startUtf16,
    required this.endUtf16,
    required this.startLine,
    required this.startCharacter,
    required this.text,
  });
}

/// UTF-16 absolute start for a zero-based Rust document line.
class DocumentLineOffset {
  final int version;
  final int totalUtf16Length;
  final int lineCount;
  final int line;
  final int offsetUtf16;

  const DocumentLineOffset({
    required this.version,
    required this.totalUtf16Length,
    required this.lineCount,
    required this.line,
    required this.offsetUtf16,
  });
}

/// One horizontal UTF-16 window from a line in the Rust document.
class DocumentLineWindow {
  final int line;
  final int startUtf16;
  final int endUtf16;
  final String text;

  const DocumentLineWindow({
    required this.line,
    required this.startUtf16,
    required this.endUtf16,
    required this.text,
  });
}

/// Bounded line windows and metadata from one Rust document snapshot.
class DocumentLinesRead {
  final int version;
  final int totalUtf16Length;
  final int lineCount;
  final int firstLine;
  final List<DocumentLineWindow> lines;

  const DocumentLinesRead({
    required this.version,
    required this.totalUtf16Length,
    required this.lineCount,
    required this.firstLine,
    required this.lines,
  });
}

class CompletionResult {
  final int version;
  final List<String> items;

  const CompletionResult(this.version, this.items);
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

  /// 发送 didClose，但保留文档缓冲区以便 URI 改变后重新打开。
  void didClose(int id) {
    _check(_core._ffi.lspDidCloseJson(id));
  }

  /// 最新诊断快照：{severity, line, character, message, source} 列表。
  List<Map<String, Object?>> diagnostics(int id) {
    final r =
        jsonDecode(_core._ffi.diagnosticsJson(id)) as Map<String, Object?>;
    if (r['ok'] != true) return const [];
    return (r['items'] as List).cast<Map<String, Object?>>();
  }

  /// 异步补全；仅在请求进行时每 20ms 检查一次，取消/过期/超时返回 null。
  Future<CompletionResult?> completion(
    int id,
    int offsetUtf16, {
    int timeoutMs = 8000,
  }) async {
    final startJson =
        _core._ffi.completionStartJson(id, offsetUtf16, timeoutMs);
    _check(startJson);
    final start = jsonDecode(startJson) as Map<String, Object?>;
    final requestId = start['requestId'] as int;
    try {
      while (true) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final pollJson = _core._ffi.completionPollJson(requestId);
        _check(pollJson);
        final poll = jsonDecode(pollJson) as Map<String, Object?>;
        switch (poll['status']) {
          case 'pending':
            continue;
          case 'completed':
            return CompletionResult(
              poll['version'] as int,
              (poll['items'] as List).cast<String>(),
            );
          case 'stale':
          case 'timeout':
          case 'cancelled':
            return null;
          default:
            throw StateError('未知补全请求状态：${poll['status']}');
        }
      }
    } finally {
      _core._ffi.completionCancelJson(requestId);
    }
  }

  /// 同步兼容入口；工作台使用上面的异步方法。
  List<String> completionBlocking(int id, int offsetUtf16,
      {int timeoutMs = 8000}) {
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
    final r =
        jsonDecode(_core._ffi.wsListDirJson(path)) as Map<String, Object?>;
    if (r['ok'] != true) {
      final err = r['error'];
      throw AlulaException(
        err is Map ? (err['code'] as String? ?? 'Unknown') : 'Unknown',
        jsonEncode(err),
      );
    }
    return (r['entries'] as List).cast<Map<String, Object?>>();
  }

  /// 读取受支持编码的文本，内容规范化为 LF，并保留编码/BOM/EOL 元数据。
  DecodedTextFile readFileDocument(String path, {TextEncoding? encoding}) {
    final r = jsonDecode(_core._ffi.wsReadFileDocumentJson(path, encoding?.id))
        as Map<String, Object?>;
    if (r['ok'] != true) {
      final err = r['error'];
      throw AlulaException(
        err is Map ? (err['code'] as String? ?? 'Unknown') : 'Unknown',
        jsonEncode(err),
      );
    }
    return DecodedTextFile(
      content: r['content'] as String,
      options: TextFileOptions.fromJson(r),
    );
  }

  String readFile(String path) => readFileDocument(path).content;
}

class AlulaResourceStatus {
  const AlulaResourceStatus({
    required this.pressure,
    required this.totalBytes,
    required this.availableBytes,
    required this.source,
    required this.transitionedToCritical,
    required this.stoppedSearchProcesses,
  });

  final String pressure;
  final int totalBytes;
  final int availableBytes;
  final String source;
  final bool transitionedToCritical;
  final int stoppedSearchProcesses;
}

class AlulaManagedProcess {
  const AlulaManagedProcess({
    required this.rootPid,
    required this.pid,
    required this.parentPid,
    required this.name,
    required this.label,
    required this.kind,
    required this.workspace,
    required this.residentBytes,
  });

  final int rootPid;
  final int pid;
  final int? parentPid;
  final String name;
  final String label;
  final String kind;
  final String? workspace;
  final int residentBytes;
}

/// Process lifecycle and pressure status exposed by the Rust supervisor.
class AlulaRuntime {
  AlulaRuntime._(this._core);

  final AlulaCore _core;

  AlulaResourceStatus sampleResourceStatus() {
    final json = _core._ffi.resourceStatusJson();
    _check(json);
    final r = jsonDecode(json) as Map<String, Object?>;
    return AlulaResourceStatus(
      pressure: r['pressure'] as String,
      totalBytes: r['totalBytes'] as int,
      availableBytes: r['availableBytes'] as int,
      source: r['source'] as String,
      transitionedToCritical: r['transitionedToCritical'] as bool,
      stoppedSearchProcesses: r['stoppedSearchProcesses'] as int,
    );
  }

  List<AlulaManagedProcess> processSnapshot() {
    final json = _core._ffi.processSnapshotJson();
    _check(json);
    final r = jsonDecode(json) as Map<String, Object?>;
    return (r['processes'] as List)
        .cast<Map<String, Object?>>()
        .map((process) => AlulaManagedProcess(
              rootPid: process['rootPid'] as int,
              pid: process['pid'] as int,
              parentPid: process['parentPid'] as int?,
              name: process['name'] as String,
              label: process['label'] as String,
              kind: process['kind'] as String,
              workspace: process['workspace'] as String?,
              residentBytes: process['residentBytes'] as int,
            ))
        .toList(growable: false);
  }

  void registerProcess(int pid, String kind, String label, String? workspace) {
    _check(_core._ffi.processRegisterJson(pid, kind, label, workspace));
  }

  void unregisterProcess(int pid) {
    _check(_core._ffi.processUnregisterJson(pid));
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

  /// Resolve a zero-based line from Rust without scanning the document in Dart.
  DocumentLineOffset lineOffset(int line) {
    if (line < 0) throw RangeError.value(line, 'line', 'must be non-negative');
    final json = core._ffi.docLineOffsetJson(id, line);
    final r = jsonDecode(json) as Map<String, Object?>;
    if (r['ok'] != true) {
      final err = r['error'];
      throw AlulaException(
        err is Map ? (err['code'] as String? ?? 'Unknown') : 'Unknown',
        jsonEncode(err),
      );
    }
    final offset = DocumentLineOffset(
      version: r['version'] as int,
      totalUtf16Length: r['totalUtf16Length'] as int,
      lineCount: r['lineCount'] as int,
      line: r['line'] as int,
      offsetUtf16: r['offsetUtf16'] as int,
    );
    version = offset.version;
    return offset;
  }

  /// Read a bounded batch of line windows without mirroring the document.
  /// The requested worst case must fit within the total UTF-16 response cap.
  DocumentLinesRead readLines({
    required int firstLine,
    required int maxLines,
    int horizontalStartUtf16 = 0,
    int maxLineUtf16 = 2048,
    int maxTotalUtf16 = maxDocReadRangeUtf16,
  }) {
    if (firstLine < 0) {
      throw RangeError.value(firstLine, 'firstLine', 'must be non-negative');
    }
    if (horizontalStartUtf16 < 0) {
      throw RangeError.value(
        horizontalStartUtf16,
        'horizontalStartUtf16',
        'must be non-negative',
      );
    }
    if (maxLines < 1 || maxLines > maxDocReadLines) {
      throw RangeError.range(maxLines, 1, maxDocReadLines, 'maxLines');
    }
    if (maxLineUtf16 < 2 || maxLineUtf16 > maxDocReadRangeUtf16) {
      throw RangeError.range(
        maxLineUtf16,
        2,
        maxDocReadRangeUtf16,
        'maxLineUtf16',
      );
    }
    if (maxTotalUtf16 < 1 || maxTotalUtf16 > maxDocReadRangeUtf16) {
      throw RangeError.range(
        maxTotalUtf16,
        1,
        maxDocReadRangeUtf16,
        'maxTotalUtf16',
      );
    }
    if (maxLineUtf16 * maxLines > maxTotalUtf16) {
      throw RangeError.value(
        maxTotalUtf16,
        'maxTotalUtf16',
        'must cover maxLineUtf16 × maxLines',
      );
    }

    final json = core._ffi.docReadLinesJson(
      id,
      firstLine,
      maxLines,
      horizontalStartUtf16,
      maxLineUtf16,
      maxTotalUtf16,
    );
    final r = jsonDecode(json) as Map<String, Object?>;
    if (r['ok'] != true) {
      final err = r['error'];
      throw AlulaException(
        err is Map ? (err['code'] as String? ?? 'Unknown') : 'Unknown',
        jsonEncode(err),
      );
    }
    final lines = (r['lines'] as List<dynamic>).map((item) {
      final line = item as Map<String, Object?>;
      return DocumentLineWindow(
        line: line['line'] as int,
        startUtf16: line['startUtf16'] as int,
        endUtf16: line['endUtf16'] as int,
        text: line['text'] as String,
      );
    }).toList(growable: false);
    final page = DocumentLinesRead(
      version: r['version'] as int,
      totalUtf16Length: r['totalUtf16Length'] as int,
      lineCount: r['lineCount'] as int,
      firstLine: r['firstLine'] as int,
      lines: lines,
    );
    version = page.version;
    return page;
  }

  /// Read at most [maxLenUtf16] UTF-16 units without transferring the full file.
  /// The returned end is adjusted to a Unicode scalar boundary.
  TextRangeRead readRange(int startUtf16, {required int maxLenUtf16}) {
    final json = core._ffi.docReadRangeJson(id, startUtf16, maxLenUtf16);
    final r = jsonDecode(json) as Map<String, Object?>;
    if (r['ok'] != true) {
      final err = r['error'];
      throw AlulaException(
        err is Map ? (err['code'] as String? ?? 'Unknown') : 'Unknown',
        jsonEncode(err),
      );
    }
    final range = TextRangeRead(
      version: r['version'] as int,
      totalUtf16Length: r['totalUtf16Length'] as int,
      lineCount: r['lineCount'] as int,
      startUtf16: r['startUtf16'] as int,
      endUtf16: r['endUtf16'] as int,
      startLine: r['startLine'] as int,
      startCharacter: r['startCharacter'] as int,
      text: r['text'] as String,
    );
    version = range.version;
    return range;
  }

  /// 提交一批增量操作；成功返回 Rust 确认的版本号（应等于 version + ops 数）。
  int apply(List<TextOp> ops) => applyWith(version, ops);

  /// Replace the Rust-owned savepoint, for example after restoring a dirty
  /// journal entry whose savepoint came from a different on-disk snapshot.
  void setSavepoint(String text) {
    _requireOk(core._ffi.docSetSavepointJson(id, text));
  }

  /// Mark the current Rust text as the savepoint after a successful save.
  void markSaved() {
    _requireOk(core._ffi.docMarkSavedJson(id));
  }

  /// Exact dirty comparison against the Rust-owned savepoint.
  bool get isDirty {
    return _requireOk(core._ffi.docIsDirtyJson(id))['dirty'] as bool;
  }

  /// Compare an external snapshot with the Rust-owned savepoint.
  bool savepointMatches(String text) {
    return _requireOk(core._ffi.docSavepointMatchesJson(id, text))['matches']
        as bool;
  }

  Map<String, Object?> _requireOk(String json) {
    final result = jsonDecode(json) as Map<String, Object?>;
    if (result['ok'] == true) return result;
    final error = result['error'] as Map<String, Object?>?;
    throw AlulaException(
      error?['code'] as String? ?? 'Unknown',
      jsonEncode(error?['detail']),
    );
  }

  /// 以显式 baseVersion 提交（正常编辑走 [apply]；测试与恢复路径用本方法）。
  int applyWith(int baseVersion, List<TextOp> ops) {
    final json = core._ffi.docApplyJson(
        id, baseVersion, jsonEncode(ops.map((o) => o.toJson()).toList()));
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

  /// 原子保存当前全文到路径，并应用编码/BOM/EOL（校验版本；docs/02 §6.3）。
  void saveFile(
    String path, {
    TextFileOptions options = TextFileOptions.defaults,
  }) {
    final json = core._ffi.docSaveFileWithOptionsJson(
      id,
      path,
      version,
      options.encoding.id,
      options.bom,
      options.lineEnding.id,
    );
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

class AlulaWorkspaceEditResult {
  const AlulaWorkspaceEditResult(this.versions);

  final Map<int, int> versions;
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

  /// 子进程生命周期与资源压力入口。
  AlulaRuntime get runtime => AlulaRuntime._(this);

  /// Atomically applies one operation batch to each listed document.
  AlulaWorkspaceEditResult applyWorkspaceEdit(
    List<AlulaWorkspaceEditDocument> documents,
  ) {
    final json = _ffi.workspaceEditTransactionJson(
      jsonEncode(documents.map((document) => document.toJson()).toList()),
    );
    final result = jsonDecode(json) as Map<String, Object?>;
    if (result['ok'] != true) {
      final error = result['error']! as Map<String, Object?>;
      throw AlulaException(
        error['code'] as String? ?? 'Unknown',
        jsonEncode(error['detail']),
      );
    }
    final versions = (result['versions'] as List)
        .cast<Map<String, Object?>>()
        .map((item) => MapEntry(item['id'] as int, item['version'] as int));
    return AlulaWorkspaceEditResult(
        Map.unmodifiable(Map.fromEntries(versions)));
  }

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
