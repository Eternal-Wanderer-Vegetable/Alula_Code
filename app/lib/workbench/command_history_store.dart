/// 命令面板 MRU 历史的持久化（docs/11 LAY-17「历史」）。
///
/// 与 VS Code 的 storage 一致，命令历史是全局的（不分工作区），只有面板接受会
/// 写入。使用 [SessionStore] 的原子 journal 写入（同目录临时文件 + 校验），
/// 读取时校验格式/版本并过滤非法项；任何读取失败都回退为空历史，不影响启动。
library;

import 'dart:io';

import 'command_history.dart';
import 'session_store.dart';

/// 单条历史文件的字节上限：50 个命令 id 远小于此值，超限视为损坏并回退空历史。
const int maxCommandHistoryRecordBytes = 64 * 1024;

class CommandHistoryStore {
  CommandHistoryStore({required this.path});

  /// journal 文件路径；默认由 workbench 放在会话 journal 旁的
  /// `<session.json>.command-history`。
  final String path;

  CommandHistory load() {
    if (_oversized()) return CommandHistory();
    final data = SessionStore(path: path).tryLoad();
    if (data == null ||
        data['format'] != 'alula-command-history' ||
        data['version'] != 1) {
      return CommandHistory();
    }
    return CommandHistory.fromJson(data);
  }

  /// 保存整份快照；返回是否写入成功。
  bool save(CommandHistory history) {
    final payload = <String, Object?>{
      'format': 'alula-command-history',
      'version': 1,
      'entries': history.commandIds,
    };
    return SessionStore(path: path).save(payload);
  }

  bool _oversized() {
    for (final file in [File(path), File('$path.bak'), File('$path.tmp')]) {
      try {
        if (file.existsSync() &&
            file.lengthSync() > maxCommandHistoryRecordBytes) {
          return true;
        }
      } on FileSystemException {
        return true;
      }
    }
    return false;
  }
}
