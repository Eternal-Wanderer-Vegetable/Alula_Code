/// 布局持久化（docs/09 W1-4）：分割树 JSON 落盘与重启恢复。
///
/// 存储位置：`<home>/.alula/layout.json`（可用 `ALULA_LAYOUT_PATH` 覆盖，测试注入临时路径）。
/// 布局不是关键数据：读失败/文件损坏一律回退默认布局，写失败静默。
library;

import 'dart:convert';
import 'dart:io';

import 'layout_model.dart';
import 'secondary_sidebar_layout.dart';

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
    final path = _peekLayoutPath;
    final file = File(path);
    final temporary =
        File('$path.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp');
    try {
      file.parent.createSync(recursive: true);
      temporary.writeAsStringSync(
          jsonEncode({
            'previewRatio': layout.previewRatio,
            'heightInLines': layout.heightInLines,
          }),
          flush: true);
      temporary.renameSync(path);
    } on FileSystemException {
      // The in-memory layout remains usable if its preference cannot be saved.
      try {
        if (temporary.existsSync()) temporary.deleteSync();
      } on FileSystemException {
        // Leave the previous preference intact.
      }
    }
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
