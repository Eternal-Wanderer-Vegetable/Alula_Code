// SessionStore 单测：journal 保存/恢复往返、损坏回退、原子写盘。
// 纯 Dart IO（注入临时路径）。对应 docs/09 W2-4。
import 'dart:convert';
import 'dart:io';

import 'package:alula_app/workbench/session_store.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _sampleSession() => {
      'v': 1,
      'focused': 'editor',
      'workspace': r'E:\Alula_Code\tests\fixtures\rust-mini',
      'groups': [
        {
          'region': 'editor',
          'active': 2,
          'docs': [
            {'id': 1, 'text': '// untitled\n'},
            {'id': 2, 'path': r'E:\x\Cargo.toml'},
          ],
        }
      ],
    };

void main() {
  late Directory tmp;
  late SessionStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('alula_session_test');
    store = SessionStore(path: '${tmp.path.replaceAll('\\', '/')}/session.json');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('无文件 → tryLoad 返回 null（按全新会话启动）', () {
    expect(store.tryLoad(), isNull);
  });

  test('save → tryLoad 往返：结构逐字段一致（含中文与反斜杠路径）', () {
    final data = _sampleSession();
    store.save(data);
    final loaded = store.tryLoad();
    expect(loaded, isNotNull);
    expect(loaded!['focused'], 'editor');
    final groups = loaded['groups'] as List;
    expect((groups[0] as Map)['region'], 'editor');
    final docs = (groups[0] as Map)['docs'] as List;
    expect((docs[0] as Map)['text'], '// untitled\n');
    expect((docs[1] as Map)['path'], r'E:\x\Cargo.toml');
  });

  test('损坏文件 → tryLoad 返回 null 不抛异常', () {
    File(store.resolvePath()).writeAsStringSync('{"groups": [oops');
    expect(store.tryLoad(), isNull);
    File(store.resolvePath()).writeAsStringSync('[1,2,3]'); // 非 object
    expect(store.tryLoad(), isNull);
    File(store.resolvePath())
        .writeAsStringSync(jsonEncode('just a string')); // 非 object
    expect(store.tryLoad(), isNull);
  });

  test('覆盖保存不留 .tmp（原子替换）', () {
    store.save(_sampleSession());
    store.save(_sampleSession());
    final leftovers =
        tmp.listSync().where((e) => e.path.endsWith('.tmp')).toList();
    expect(leftovers, isEmpty);
    expect(store.tryLoad(), isNotNull);
  });
}
