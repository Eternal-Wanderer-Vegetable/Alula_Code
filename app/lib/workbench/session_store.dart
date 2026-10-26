/// 会话 journal（docs/09 W2-4，docs/03 稳定性 DoD「断电恢复未保存内容」）。
///
/// 存储位置：`<home>/.alula/session.json`（`ALULA_SESSION_PATH` 之外还支持构造注入，
/// 测试用临时路径）。内容是页面上报的纯 JSON（组/文档/未保存文本），本类只管
/// 读写与原子替换；损坏一律返回 null，按全新会话启动。
library;

import 'dart:convert';
import 'dart:io';

class SessionStore {
  SessionStore({String? path}) : _overridePath = path;

  final String? _overridePath;

  String resolvePath() {
    if (_overridePath != null) return _overridePath;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    return '$home/.alula/session.json';
  }

  Map<String, Object?>? tryLoad() {
    try {
      final file = File(resolvePath());
      if (!file.existsSync()) return null;
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, Object?>) return null;
      return decoded;
    } catch (_) {
      return null;
    }
  }

  void save(Map<String, Object?> data) {
    try {
      final file = File(resolvePath());
      file.parent.createSync(recursive: true);
      final tmp = '${file.path}.tmp';
      File(tmp).writeAsStringSync(jsonEncode(data));
      if (file.existsSync()) file.deleteSync();
      File(tmp).renameSync(file.path);
    } catch (_) {
      // journal 写失败不影响功能（workspace 文件只经原子保存，无半写风险）
    }
  }
}
