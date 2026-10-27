// 临时 Git 仓库助手：集成测试与 widget 测试共用。
import 'dart:io';

/// 创建带一次初始提交的临时仓库，返回仓库目录。
/// [extraFiles] 额外写入的未跟踪文件（相对路径 → 内容）。
Future<Directory> createTempRepo(
    {required String prefix, Map<String, String> extraFiles = const {}}) async {
  final dir = await Directory.systemTemp.createTemp(prefix);
  await _run(dir, ['init', '-b', 'main']);
  await _run(dir, ['config', 'user.email', 'alula-test@example.com']);
  await _run(dir, ['config', 'user.name', 'Alula Test']);
  File('${dir.path}${Platform.pathSeparator}README.md')
      .writeAsStringSync('# temp repo\n');
  await _run(dir, ['add', '.']);
  await _run(dir, ['commit', '-m', 'init']);
  for (final e in extraFiles.entries) {
    final f = File('${dir.path}${Platform.pathSeparator}'
        '${e.key.replaceAll('/', Platform.pathSeparator)}');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(e.value);
  }
  return dir;
}

Future<void> _run(Directory dir, List<String> args) async {
  final r = await Process.run('git', args, workingDirectory: dir.path);
  if (r.exitCode != 0) {
    throw StateError('git ${args.first} 失败: ${r.stderr}');
  }
}
