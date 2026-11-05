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
    store =
        SessionStore(path: '${tmp.path.replaceAll('\\', '/')}/session.json');
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

  test('legacy journal 可读取并在下一次保存时升级为带版本与校验的新格式', () {
    File(store.resolvePath()).writeAsStringSync(jsonEncode(_sampleSession()));

    final loaded = store.tryLoad();
    expect(loaded, isNotNull);
    expect(store.lastLoadStatus, SessionLoadStatus.legacy);
    expect(store.save(loaded!), isTrue);

    final envelope =
        jsonDecode(File(store.resolvePath()).readAsStringSync()) as Map;
    expect(envelope['_alulaJournal'], 'alula-session');
    expect(envelope['version'], 1);
    expect(envelope['checksum'], isA<String>());
    expect(store.tryLoad()!['focused'], 'editor');
    expect(store.lastLoadStatus, SessionLoadStatus.loaded);
  });

  test('payload 被改动但 checksum 未更新时拒绝恢复', () {
    store.save({'v': 1, 'value': 'accepted'});
    final file = File(store.resolvePath());
    final envelope = jsonDecode(file.readAsStringSync()) as Map;
    (envelope['payload'] as Map)['value'] = 'tampered';
    file.writeAsStringSync(jsonEncode(envelope));

    expect(store.tryLoad(), isNull);
    expect(store.lastLoadStatus, SessionLoadStatus.invalid);
  });

  test('未知 journal 版本显式报告且不载入 payload', () {
    store.save({'v': 1, 'value': 'accepted'});
    final file = File(store.resolvePath());
    final envelope = jsonDecode(file.readAsStringSync()) as Map;
    envelope['version'] = 99;
    file.writeAsStringSync(jsonEncode(envelope));

    expect(store.tryLoad(), isNull);
    expect(store.lastLoadStatus, SessionLoadStatus.unsupportedVersion);
  });

  test('损坏的主 journal 回退到校验通过的上一代备份', () {
    store.save({'v': 1, 'value': 'previous'});
    store.save({'v': 1, 'value': 'latest'});
    File(store.resolvePath()).writeAsStringSync('{broken primary');

    expect(store.tryLoad()!['value'], 'previous');
    expect(store.lastLoadStatus, SessionLoadStatus.recoveredFromBackup);
  });

  test('有效主文件优先于不完整临时文件，所有副本损坏时显式报告', () {
    store.save({'v': 1, 'value': 'saved'});
    File('${store.resolvePath()}.tmp').writeAsStringSync('{partial');
    expect(store.tryLoad()!['value'], 'saved');
    expect(store.lastLoadStatus, SessionLoadStatus.loaded);

    File(store.resolvePath()).writeAsStringSync('{broken primary');
    File('${store.resolvePath()}.bak').writeAsStringSync('{broken backup');
    expect(store.tryLoad(), isNull);
    expect(store.lastLoadStatus, SessionLoadStatus.invalid);
  });

  test('超过原 2M 阈值的脏文本通过流式 journal 往返', () {
    final text = List<String>.filled(2001, 'x' * 1000).join();
    expect(text.length, greaterThan(2000000));

    expect(store.save({'v': 1, 'text': text}), isTrue);
    expect(store.tryLoad()!['text'], text);
    expect(store.lastLoadStatus, SessionLoadStatus.loaded);
  });

  test('进程在临时 journal flush 后被强杀，重启可恢复最新一代', () async {
    store.save({'v': 1, 'value': 'previous'});
    final writer =
        File('test/helpers/session_store_crash_writer.dart').absolute.path;
    final child = await Process.start(
      Platform.isWindows ? 'dart.exe' : 'dart',
      [writer, store.resolvePath()],
      workingDirectory: Directory.current.path,
    );
    final stderr = StringBuffer();
    child.stderr.transform(utf8.decoder).listen(stderr.write);
    final ready = child.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .firstWhere((line) => line == 'SESSION_TEMP_FLUSHED')
        .timeout(const Duration(seconds: 15));

    expect(await ready, 'SESSION_TEMP_FLUSHED');
    try {
      child.kill(ProcessSignal.sigkill);
    } on ArgumentError {
      child.kill();
    }
    await child.exitCode.timeout(const Duration(seconds: 15));

    expect(store.tryLoad(), containsPair('value', 'written by child process'),
        reason: '有效临时副本比旧主文件更新，应恢复已 flush 的新一代');
    expect(store.lastLoadStatus, SessionLoadStatus.recoveredFromTemporary);
    expect(stderr.toString(), isEmpty);
  });

  test('journal 写入失败返回 false 并保留错误状态', () {
    final blocker = File('${tmp.path}/not-a-directory')..writeAsStringSync('x');
    store = SessionStore(path: '${blocker.path}/session.json');

    expect(store.save(_sampleSession()), isFalse);
    expect(store.lastSaveError, isNotNull);
  });
}
