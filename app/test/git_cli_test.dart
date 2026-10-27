// GitCli 单测：porcelain -z 解析（含 rename/中文路径）+ 命令参数构造 + 错误传播。
// 用假 runner，不碰真实 git。对应 docs/09 W4 Git 面板。
import 'dart:io';

import 'package:alula_app/git/git_cli.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeRunner {
  FakeRunner(this.handler);

  final ProcessResult Function(String exe, List<String> args) handler;
  final List<(String, List<String>)> calls = [];

  Future<ProcessResult> run(String exe, List<String> args,
      {String? workingDirectory}) async {
    calls.add((exe, args));
    return handler(exe, args);
  }
}

ProcessResult ok(String stdout) =>
    ProcessResult(0, 0, stdout, '');

ProcessResult fail(String stderr) =>
    ProcessResult(1, 128, '', stderr);

void main() {
  test('porcelain -z 解析：修改/未跟踪/重命名/中文路径', () async {
    // porcelain -z 的 rename 格式：新路径在前，原路径跟在 NUL 后
    const z = 'M  a.txt\u0000 M src/lib.rs\u0000?? new file.txt\u0000'
        'R  new\u0000old\u0000?? 中文 目录/\u0000\u0000';
    final fake = FakeRunner((exe, args) => ok(z));
    final git = GitCli(root: '/repo', runner: fake.run);
    final entries = await git.status();

    expect(entries.length, 5);
    expect(entries[0].path, 'a.txt');
    expect(entries[0].hasStagedChanges, isTrue);
    expect(entries[0].hasUnstagedChanges, isFalse);
    expect(entries[1].path, 'src/lib.rs');
    expect(entries[1].hasUnstagedChanges, isTrue);
    expect(entries[2].isUntracked, isTrue);
    expect(entries[3].path, 'new'); // rename 新路径
    expect(entries[3].origPath, 'old');
    expect(entries[4].path, '中文 目录');
  });

  test('status 命令参数：--porcelain -z', () async {
    final fake = FakeRunner((exe, args) => ok(''));
    final git = GitCli(root: '/repo', runner: fake.run);
    await git.status();
    expect(fake.calls.single.$2, ['status', '--porcelain', '-z']);
  });

  test('stage/unstage/commit 的参数构造', () async {
    final fake = FakeRunner((exe, args) => ok('[main abc] msg\n'));
    final git = GitCli(root: '/repo', runner: fake.run);

    await git.stage(['a b.txt', '中文.rs']);
    expect(fake.calls.last.$2, ['add', '--', 'a b.txt', '中文.rs']);

    await git.unstage(['a b.txt']);
    expect(fake.calls.last.$2, ['reset', '-q', 'HEAD', '--', 'a b.txt']);

    final summary = await git.commit('修复 中文 问题\n\n正文');
    expect(summary, '[main abc] msg');
    expect(fake.calls.last.$2, ['commit', '-m', '修复 中文 问题\n\n正文']);

    await git.stage([]);
    expect(fake.calls.last.$2, ['commit', '-m', '修复 中文 问题\n\n正文'],
        reason: '空 paths 不发命令');
  });

  test('commit 空信息与 git 失败：抛 GitError', () async {
    final git = GitCli(root: '/repo', runner: FakeRunner((e, a) => ok('')).run);
    expect(() => git.commit('   '), throwsA(isA<GitError>()));

    final failing = GitCli(
        root: '/repo',
        runner: FakeRunner((e, a) => fail(
            'Author identity unknown\n*** Please tell me who you are.'))
            .run);
    await expectLater(failing.commit('x'), throwsA(isA<GitError>()));
  });

  test('isRepo：true / false（rev-parse 失败）', () async {
    final yes = GitCli(root: '/r', runner: FakeRunner((e, a) => ok('true\n')).run);
    expect(await yes.isRepo(), isTrue);
    final no = GitCli(
        root: '/r',
        runner: FakeRunner((e, a) => fail('fatal: not a git repository')).run);
    expect(await no.isRepo(), isFalse);
  });

  test('diff/log 转发', () async {
    final fake = FakeRunner((exe, args) {
      if (args.first == 'diff') return ok('diff --git a/a.txt\n+line\n');
      if (args.first == 'log') return ok('abc123 first\ndef456 second\n');
      return ok('');
    });
    final git = GitCli(root: '/repo', runner: fake.run);
    final d = await git.diff(path: 'a.txt', staged: true);
    expect(d, contains('+line'));
    expect(fake.calls.last.$2,
        ['diff', '--no-color', '--cached', '--', 'a.txt']);

    final log = await git.log(limit: 2);
    expect(log, ['abc123 first', 'def456 second']);
  });
}
