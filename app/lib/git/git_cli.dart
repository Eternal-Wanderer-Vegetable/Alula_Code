/// Git CLI 封装（docs/03 Git 行 / docs/09 W4）。
///
/// 通过 `git` 子进程操作工作区仓库（不引 Rust 侧改动，Dart Process 即可）。
/// [runner] 可注入：单测用假 runner 验证参数与解析，集成测试/真机走 Process.run。
///
/// 口径约定：
/// - status 用 `--porcelain -z`（NUL 分隔、路径不转义，中文/空格路径安全）；
/// - 一律以工作区根为 cwd；仓库根 ≠ 工作区根时路径以仓库根为基准（git 语义）。
library;

import 'dart:convert';
import 'dart:io';

/// 进程执行器签名（与 Process.run 对齐，便于注入假实现）。
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> args, {
  String? workingDirectory,
});

/// 默认 runner：显式 UTF-8 解码（Windows 默认系统码表会把 git 的
/// UTF-8 输出解成乱码，中文提交信息/路径尤其如此）。
Future<ProcessResult> processRunnerUtf8(
  String executable,
  List<String> args, {
  String? workingDirectory,
}) {
  return Process.run(
    executable,
    args,
    workingDirectory: workingDirectory,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
}

class GitError implements Exception {
  GitError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 一条 `git status --porcelain` 记录。
class GitStatusEntry {
  const GitStatusEntry({
    required this.x,
    required this.y,
    required this.path,
    this.origPath,
  });

  /// 暂存区状态（' ' M A D R C U ?）。
  final String x;

  /// 工作区状态。
  final String y;

  /// 相对仓库根的路径。
  final String path;

  /// 重命名/复制时的原路径。
  final String? origPath;

  bool get isUntracked => x == '?' && y == '?';
  bool get hasStagedChanges => !(x == ' ' || x == '?');
  bool get hasUnstagedChanges => !(y == ' ' || y == '?');

  /// 展示状态码（未跟踪显示 ??）。
  String get code => isUntracked ? '??' : (x.trim() + y.trim());
}

class GitCli {
  GitCli({required this.root, this.runner = processRunnerUtf8});

  /// 工作区根（git 命令的 cwd）。
  final String root;
  final ProcessRunner runner;

  Future<ProcessResult> _git(List<String> args) async {
    final r = await runner('git', args, workingDirectory: root);
    if (r.exitCode != 0) {
      final err = (r.stderr as String).trim();
      throw GitError(err.isEmpty ? 'git ${args.first} 失败' : err);
    }
    return r;
  }

  /// 是否在 Git 工作树内。
  Future<bool> isRepo() async {
    try {
      final r = await _git(['rev-parse', '--is-inside-work-tree']);
      return (r.stdout as String).trim() == 'true';
    } on GitError {
      return false;
    }
  }

  /// 当前分支名（ detached HEAD 返回 'HEAD'）。
  Future<String> currentBranch() async {
    final r = await _git(['rev-parse', '--abbrev-ref', 'HEAD']);
    return (r.stdout as String).trim();
  }

  /// 工作区状态（含未跟踪）。
  Future<List<GitStatusEntry>> status() async {
    final r = await _git(['status', '--porcelain', '-z']);
    final raw = r.stdout as String;
    final fields = raw.split('\u0000');
    final out = <GitStatusEntry>[];
    for (var i = 0; i < fields.length; i++) {
      final f = fields[i];
      if (f.isEmpty) continue;
      if (f.length < 4) continue; // 'XY ' 至少 4 字符
      final x = f[0];
      final y = f[1];
      // 未跟踪目录带尾部 '/'（git 语义），归一化去掉便于显示
      var path = f.substring(3);
      while (path.endsWith('/')) {
        path = path.substring(0, path.length - 1);
      }
      String? orig;
      // rename/copy 在 -z 格式里紧跟一个原路径字段
      if ((x == 'R' || x == 'C' || y == 'R' || y == 'C') &&
          i + 1 < fields.length) {
        orig = fields[i + 1];
        i++;
      }
      out.add(GitStatusEntry(x: x, y: y, path: path, origPath: orig));
    }
    return out;
  }

  /// 暂存文件（paths 为相对仓库根路径）。
  Future<void> stage(List<String> paths) async {
    if (paths.isEmpty) return;
    await _git(['add', '--', ...paths]);
  }

  /// 取消暂存。
  Future<void> unstage(List<String> paths) async {
    if (paths.isEmpty) return;
    await _git(['reset', '-q', 'HEAD', '--', ...paths]);
  }

  /// 提交暂存内容；成功返回提交摘要首行，失败抛 GitError（如缺 user.email）。
  Future<String> commit(String message) async {
    if (message.trim().isEmpty) {
      throw GitError('提交信息不能为空');
    }
    final r = await _git(['commit', '-m', message.trim()]);
    final out = (r.stdout as String).trim();
    return out.split('\n').first;
  }

  /// diff 文本：默认工作区未暂存变更；[staged] 取暂存区；[path] 限定文件。
  Future<String> diff({String? path, bool staged = false}) async {
    final args = <String>['diff', '--no-color'];
    if (staged) args.add('--cached');
    if (path != null) args.addAll(['--', path]);
    final r = await _git(args);
    return r.stdout as String;
  }

  /// 提交历史（oneline，最新在前）。
  Future<List<String>> log({int limit = 20}) async {
    final r = await _git(['log', '--oneline', '-n', '$limit']);
    return (r.stdout as String)
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
  }
}
