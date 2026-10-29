/// Rust 核心（alula_core）的 dart:ffi 原始绑定与动态库加载。
///
/// ABI 定义见 crates/editor-core/src/ffi.rs；
/// 语义封装（JSON 解析、版本管理）在 alula_core.dart，UI 不要直接使用本文件。
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// 按平台返回动态库文件名。
String alulaLibName() {
  if (Platform.isWindows) return 'alula_core.dll';
  if (Platform.isMacOS) return 'libalula_core.dylib';
  return 'libalula_core.so';
}

/// 在若干候选路径中加载核心库：
/// 1. 环境变量 ALULA_CORE_PATH（显式指定，优先）
/// 2. exe 同目录（Windows 构建安装步骤会把 DLL 放在这里）
/// 3. app/native/（scripts/build_core 脚本的产物位置，flutter test 场景）
/// 4. target/{release,debug}/（直接使用 cargo 产物，方便开发调试）
DynamicLibrary loadAlulaCore() {
  final name = alulaLibName();
  final env = Platform.environment['ALULA_CORE_PATH'];
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final candidates = [
    if (env != null && env.isNotEmpty) env,
    '$exeDir/$name',
    'native/$name',
    '../target/release/$name',
    '../target/debug/$name',
  ];
  Object? lastError;
  for (final path in candidates) {
    try {
      return DynamicLibrary.open(path);
    } catch (e) {
      lastError = e;
    }
  }
  throw StateError(
    '无法加载 Alula 核心（$name）。请先在仓库根目录运行 scripts/build_core 构建并拷贝。\n'
    '最后错误：$lastError',
  );
}

/// C 导出函数的原始绑定。
class AlulaFfi {
  final DynamicLibrary lib;

  late final int Function() abiVersion = lib
      .lookupFunction<Uint32 Function(), int Function()>('alula_abi_version');

  // *mut c_char 返回值一律视为调用方持有，读取后必须 stringFree。
  late final Pointer<Utf8> Function(int, Pointer<Utf8>) _docOpen = lib
      .lookupFunction<
        Pointer<Utf8> Function(Uint64, Pointer<Utf8>),
        Pointer<Utf8> Function(int, Pointer<Utf8>)
      >('alula_doc_open');

  late final Pointer<Utf8> Function(int, int, Pointer<Utf8>) _docApply = lib
      .lookupFunction<
        Pointer<Utf8> Function(Uint64, Uint64, Pointer<Utf8>),
        Pointer<Utf8> Function(int, int, Pointer<Utf8>)
      >('alula_doc_apply');

  late final Pointer<Utf8> Function(int) _docResync = lib
      .lookupFunction<Pointer<Utf8> Function(Uint64), Pointer<Utf8> Function(int)>(
        'alula_doc_resync',
      );

  late final Pointer<Utf8> Function(int) _docClose = lib
      .lookupFunction<Pointer<Utf8> Function(Uint64), Pointer<Utf8> Function(int)>(
        'alula_doc_close',
      );

  late final Pointer<Utf8> Function(int, Pointer<Utf8>) _docSetUri = lib
      .lookupFunction<
        Pointer<Utf8> Function(Uint64, Pointer<Utf8>),
        Pointer<Utf8> Function(int, Pointer<Utf8>)
      >('alula_doc_set_uri');

  late final Pointer<Utf8> Function(int, Pointer<Utf8>, Pointer<Utf8>) _lspStart = lib
      .lookupFunction<
        Pointer<Utf8> Function(Uint64, Pointer<Utf8>, Pointer<Utf8>),
        Pointer<Utf8> Function(int, Pointer<Utf8>, Pointer<Utf8>)
      >('alula_lsp_start');

  late final Pointer<Utf8> Function(Pointer<Utf8>) _lspShutdownWorkspace = lib
      .lookupFunction<
        Pointer<Utf8> Function(Pointer<Utf8>),
        Pointer<Utf8> Function(Pointer<Utf8>)
      >('alula_lsp_shutdown_workspace');

  late final Pointer<Utf8> Function(int, Pointer<Utf8>) _lspDidOpen = lib
      .lookupFunction<
        Pointer<Utf8> Function(Uint64, Pointer<Utf8>),
        Pointer<Utf8> Function(int, Pointer<Utf8>)
      >('alula_lsp_did_open');

  late final Pointer<Utf8> Function(int) _diagnostics = lib
      .lookupFunction<Pointer<Utf8> Function(Uint64), Pointer<Utf8> Function(int)>(
        'alula_diagnostics',
      );

  late final Pointer<Utf8> Function(int, int, int) _completion = lib
      .lookupFunction<
        Pointer<Utf8> Function(Uint64, Uint64, Uint64),
        Pointer<Utf8> Function(int, int, int)
      >('alula_completion');

  late final Pointer<Utf8> Function(int, int, int) _completionStart = lib
      .lookupFunction<
        Pointer<Utf8> Function(Uint64, Uint64, Uint64),
        Pointer<Utf8> Function(int, int, int)
      >('alula_completion_start');

  late final Pointer<Utf8> Function(int) _completionPoll = lib
      .lookupFunction<Pointer<Utf8> Function(Uint64), Pointer<Utf8> Function(int)>(
        'alula_completion_poll',
      );

  late final Pointer<Utf8> Function(int) _completionCancel = lib
      .lookupFunction<Pointer<Utf8> Function(Uint64), Pointer<Utf8> Function(int)>(
        'alula_completion_cancel',
      );

  late final Pointer<Utf8> Function(int) _syntax = lib
      .lookupFunction<Pointer<Utf8> Function(Uint64), Pointer<Utf8> Function(int)>(
        'alula_syntax',
      );

  late final Pointer<Utf8> Function(int) _symbols = lib
      .lookupFunction<Pointer<Utf8> Function(Uint64), Pointer<Utf8> Function(int)>(
        'alula_symbols',
      );

  late final Pointer<Utf8> Function(Pointer<Utf8>) _wsListDir = lib
      .lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>),
          Pointer<Utf8> Function(Pointer<Utf8>)>('alula_ws_list_dir');

  late final Pointer<Utf8> Function(Pointer<Utf8>) _wsReadFile = lib
      .lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>),
          Pointer<Utf8> Function(Pointer<Utf8>)>('alula_ws_read_file');

  late final Pointer<Utf8> Function(int, Pointer<Utf8>, int) _docSaveFile = lib
      .lookupFunction<
        Pointer<Utf8> Function(Uint64, Pointer<Utf8>, Uint64),
        Pointer<Utf8> Function(int, Pointer<Utf8>, int)
      >('alula_doc_save_file');

  late final Pointer<Utf8> Function(int) _lspDidSave = lib
      .lookupFunction<Pointer<Utf8> Function(Uint64), Pointer<Utf8> Function(int)>(
        'alula_lsp_did_save',
      );

  late final void Function(Pointer<Utf8>) _stringFree = lib
      .lookupFunction<Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>(
        'alula_string_free',
      );

  AlulaFfi(this.lib);

  /// 读取返回的 JSON 字符串并立即释放 Rust 侧内存。
  String _takeJson(Pointer<Utf8> ptr) {
    assert(ptr != nullptr);
    final s = ptr.toDartString();
    _stringFree(ptr);
    return s;
  }

  String docOpenJson(int id, String content) {
    final p = content.toNativeUtf8();
    try {
      return _takeJson(_docOpen(id, p));
    } finally {
      malloc.free(p);
    }
  }

  String docApplyJson(int id, int baseVersion, String opsJson) {
    final p = opsJson.toNativeUtf8();
    try {
      return _takeJson(_docApply(id, baseVersion, p));
    } finally {
      malloc.free(p);
    }
  }

  String docResyncJson(int id) => _takeJson(_docResync(id));

  String docCloseJson(int id) => _takeJson(_docClose(id));

  String docSetUriJson(int id, String uri) {
    final p = uri.toNativeUtf8();
    try {
      return _takeJson(_docSetUri(id, p));
    } finally {
      malloc.free(p);
    }
  }

  String lspStartJson(int id, String workspaceRoot, String cmdJson) {
    final r = workspaceRoot.toNativeUtf8();
    final c = cmdJson.toNativeUtf8();
    try {
      return _takeJson(_lspStart(id, r, c));
    } finally {
      malloc.free(r);
      malloc.free(c);
    }
  }

  String lspShutdownWorkspaceJson(String workspaceRoot) {
    final root = workspaceRoot.toNativeUtf8();
    try {
      return _takeJson(_lspShutdownWorkspace(root));
    } finally {
      malloc.free(root);
    }
  }

  String lspDidOpenJson(int id, String languageId) {
    final p = languageId.toNativeUtf8();
    try {
      return _takeJson(_lspDidOpen(id, p));
    } finally {
      malloc.free(p);
    }
  }

  String diagnosticsJson(int id) => _takeJson(_diagnostics(id));

  String completionJson(int id, int offsetUtf16, int timeoutMs) =>
      _takeJson(_completion(id, offsetUtf16, timeoutMs));

  String completionStartJson(int id, int offsetUtf16, int timeoutMs) =>
      _takeJson(_completionStart(id, offsetUtf16, timeoutMs));

  String completionPollJson(int requestId) => _takeJson(_completionPoll(requestId));

  String completionCancelJson(int requestId) => _takeJson(_completionCancel(requestId));

  String syntaxJson(int id) => _takeJson(_syntax(id));

  String symbolsJson(int id) => _takeJson(_symbols(id));

  String wsListDirJson(String path) {
    final p = path.toNativeUtf8();
    try {
      return _takeJson(_wsListDir(p));
    } finally {
      malloc.free(p);
    }
  }

  String wsReadFileJson(String path) {
    final p = path.toNativeUtf8();
    try {
      return _takeJson(_wsReadFile(p));
    } finally {
      malloc.free(p);
    }
  }

  String docSaveFileJson(int id, String path, int baseVersion) {
    final p = path.toNativeUtf8();
    try {
      return _takeJson(_docSaveFile(id, p, baseVersion));
    } finally {
      malloc.free(p);
    }
  }

  String lspDidSaveJson(int id) => _takeJson(_lspDidSave(id));
}
