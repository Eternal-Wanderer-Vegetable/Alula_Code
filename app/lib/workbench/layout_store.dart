/// 布局持久化（docs/09 W1-4）：分割树 JSON 落盘与重启恢复。
///
/// 存储位置：`<home>/.alula/layout.json`（可用 `ALULA_LAYOUT_PATH` 覆盖，测试注入临时路径）。
/// 布局不是关键数据：读失败/文件损坏一律回退默认布局，写失败静默。
library;

import 'dart:convert';
import 'dart:io';

import '../bridge/alula_core.dart' show HierarchyDirection, HierarchyKind;
import 'layout_model.dart';
import 'secondary_sidebar_layout.dart';
import 'workspace_state.dart';

typedef PeekLayout = ({double previewRatio, int heightInLines});

const defaultPeekLayout = (previewRatio: 0.7, heightInLines: 18);
const minPeekHeightInLines = 6;
const maxPeekHeightInLines = 34;

class LayoutStore {
  LayoutStore({String? path}) : _overridePath = path;

  final String? _overridePath;

  String resolvePath() {
    if (_overridePath != null) return _overridePath;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    return '$home/.alula/layout.json';
  }

  String get _peekLayoutPath => '${resolvePath()}.peek.json';

  PeekLayout loadPeekLayout() {
    try {
      final data = jsonDecode(File(_peekLayoutPath).readAsStringSync());
      if (data is! Map<String, Object?>) return defaultPeekLayout;
      final ratio = data['previewRatio'];
      final height = data['heightInLines'];
      return (
        previewRatio: ratio is num && ratio > 0 && ratio < 1
            ? ratio.toDouble()
            : defaultPeekLayout.previewRatio,
        heightInLines: height is int &&
                height >= minPeekHeightInLines &&
                height <= maxPeekHeightInLines
            ? height
            : defaultPeekLayout.heightInLines,
      );
    } on FileSystemException {
      return defaultPeekLayout;
    } on FormatException {
      return defaultPeekLayout;
    }
  }

  void savePeekLayout(PeekLayout layout) {
    _writePreference(_peekLayoutPath, {
      'previewRatio': layout.previewRatio,
      'heightInLines': layout.heightInLines,
    });
  }

  String _hierarchyDirectionPath(HierarchyKind kind) =>
      '${resolvePath()}.${kind.name}-hierarchy.json';

  HierarchyDirection? loadHierarchyDirection(HierarchyKind kind) {
    try {
      final value = jsonDecode(
        File(_hierarchyDirectionPath(kind)).readAsStringSync(),
      );
      return switch ((kind, value)) {
        (HierarchyKind.call, 'incoming') => HierarchyDirection.incoming,
        (HierarchyKind.call, 'outgoing') => HierarchyDirection.outgoing,
        (HierarchyKind.type, 'supertypes') => HierarchyDirection.supertypes,
        (HierarchyKind.type, 'subtypes') => HierarchyDirection.subtypes,
        _ => null,
      };
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  bool saveHierarchyDirection(HierarchyDirection direction) {
    final kind = switch (direction) {
      HierarchyDirection.incoming ||
      HierarchyDirection.outgoing =>
        HierarchyKind.call,
      HierarchyDirection.supertypes ||
      HierarchyDirection.subtypes =>
        HierarchyKind.type,
    };
    return _writePreference(_hierarchyDirectionPath(kind), direction.name);
  }

  bool _writePreference(String path, Object value) {
    final file = File(path);
    final temporary =
        File('$path.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp');
    try {
      file.parent.createSync(recursive: true);
      temporary.writeAsStringSync(jsonEncode(value), flush: true);
      temporary.renameSync(path);
      return true;
    } on FileSystemException {
      try {
        if (temporary.existsSync()) temporary.deleteSync();
      } on FileSystemException {
        // Leave the previous preference intact.
      }
      return false;
    }
  }

  static const _centeredLayoutMaxBytes = 256 * 1024;

  String _centeredLayoutPath(String identity) =>
      '${resolvePath()}.centered/${workspaceStateFileKey(identity)}.json';

  Map<String, Object?>? _readCenteredLayout(String path) {
    try {
      final file = File(path).openSync();
      try {
        final length = file.lengthSync();
        if (length > _centeredLayoutMaxBytes) return null;
        final bytes = file.readSync(length);
        final decoded = jsonDecode(utf8.decode(bytes));
        return decoded is Map<String, Object?> ? decoded : null;
      } finally {
        file.closeSync();
      }
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  bool loadCenteredLayout(String? workspaceRoot) {
    final identity = workspaceStateIdentity(workspaceRoot);
    final value = _readCenteredLayout(_centeredLayoutPath(identity));
    return value?['workspace'] == identity && value?['centered'] == true;
  }

  bool saveCenteredLayout(String? workspaceRoot, bool centered) {
    final identity = workspaceStateIdentity(workspaceRoot);
    final path = _centeredLayoutPath(identity);
    final owner = _readCenteredLayout(path)?['workspace'];
    if (owner != null && owner != identity) return false;
    return _writePreference(path, {'workspace': identity, 'centered': centered});
  }

  /// 读取已保存布局；不存在或损坏返回 null（调用方回退 defaultLayout）。
  WbSplit? tryLoad() {
    try {
      final file = File(resolvePath());
      if (!file.existsSync()) return null;
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, Object?>) return null;
      final node = WbNode.fromJson(decoded);
      if (node is! WbSplit) return null;
      node.ensureSecondarySidebar();
      return node;
    } catch (_) {
      return null;
    }
  }

  /// 保存布局（尽力而为；调用方在布局变更防抖后触发）。
  void save(WbSplit root) {
    try {
      final file = File(resolvePath());
      file.parent.createSync(recursive: true);
      final tmp = '${file.path}.tmp';
      File(tmp).writeAsStringSync(jsonEncode(root.toJson()));
      // 原子替换：避免半写文件（与 editor-doc 原子保存同思路）
      if (file.existsSync()) file.deleteSync();
      File(tmp).renameSync(file.path);
    } catch (_) {
      // 布局保存失败不影响功能
    }
  }
}
