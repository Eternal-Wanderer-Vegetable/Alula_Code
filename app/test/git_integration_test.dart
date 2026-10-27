// GitCli 真 git 集成测试：临时仓库全流程（status→stage→diff→commit→log）。
// GitHub Actions 与本机都有 git；仓库内已配置局部 user（不依赖全局配置）。
import 'dart:io';

import 'package:alula_app/git/git_cli.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/temp_repo.dart';

void main() {
  late Directory repo;
  late GitCli git;

  setUp(() async {
    repo = await createTempRepo(prefix: 'alula_git_it', extraFiles: {
      'src/main.rs': 'fn main() {}\n',
      'notes.txt': 'hello\n',
    });
    git = GitCli(root: repo.path);
  });

  tearDown(() async {
    if (repo.existsSync()) await repo.delete(recursive: true);
  });

  test('全流程：status → stage → diff → commit → log → 干净', () async {
    expect(await git.isRepo(), isTrue);
    expect(await git.currentBranch(), 'main');

    // 初始：2 个未跟踪条目（notes.txt + src/ 目录折叠；README 已提交）
    final initial = await git.status();
    expect(initial.where((e) => e.isUntracked).length, 2);

    // stage 两个文件
    await git.stage(['notes.txt', 'src/main.rs']);
    final staged = await git.status();
    expect(staged.where((e) => e.hasStagedChanges).length, 2);

    // 暂存 diff 非空
    final d = await git.diff(path: 'notes.txt', staged: true);
    expect(d, contains('+hello'));

    // 提交
    final summary = await git.commit('feat: 初始内容');
    expect(summary, contains('feat: 初始内容'));

    final clean = await git.status();
    expect(clean, isEmpty, reason: '提交后工作区干净');

    final log = await git.log(limit: 5);
    expect(log.length, 2, reason: 'init + feat 两次提交');
    expect(log.first, contains('feat: 初始内容'));
  });

  test('unstage：暂存后可退回', () async {
    await git.stage(['notes.txt']);
    expect((await git.status()).where((e) => e.hasStagedChanges).length, 1);
    await git.unstage(['notes.txt']);
    expect((await git.status()).where((e) => e.hasStagedChanges).length, 0);
  });

  test('修改已跟踪文件：unstaged diff', () async {
    File('${repo.path}${Platform.pathSeparator}README.md')
        .writeAsStringSync('# changed\n');
    final entries = await git.status();
    final m = entries.where((e) => e.path == 'README.md').single;
    expect(m.hasUnstagedChanges, isTrue);
    expect(m.hasUnstagedChanges, isTrue);
    final d = await git.diff(path: 'README.md');
    expect(d, contains('# changed'));
  });

  test('非仓库：isRepo false', () async {
    final notRepo = await Directory.systemTemp.createTemp('not_repo');
    try {
      expect(await GitCli(root: notRepo.path).isRepo(), isFalse);
    } finally {
      await notRepo.delete(recursive: true);
    }
  });
}
