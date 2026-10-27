/// 项目搜索服务（docs/09 W4「搜索视图」）。
///
/// 后端选择（探测顺序）：
/// 1. **ripgrep**（`rg --json`，流式 JSON 行，最快）；
/// 2. **git grep**（仓库内必有 git，速度足够）；
/// 3. 都不可用 → [detectBackend] 返回 null，UI 提示不可用。
///
/// search() 返回流式命中；取消订阅即终止子进程（防无界消耗）。
/// 解析函数独立导出（纯函数可单测）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 一条搜索命中。
class SearchHit {
  const SearchHit({
    required this.path,
    required this.line,
    required this.lineText,
  });

  /// 相对工作区根的路径（'/' 分隔）。
  final String path;

  /// 1-based 行号。
  final int line;

  /// 该行文本（已去行尾换行）。
  final String lineText;
}

/// 解析 ripgrep `--json` 的单行输出；只关心 match 事件，其余返回 null。
SearchHit? parseRgJsonLine(String line) {
  if (line.trim().isEmpty) return null;
  Object? decoded;
  try {
    decoded = jsonDecode(line);
  } catch (_) {
    return null;
  }
  if (decoded is! Map || decoded['type'] != 'match') return null;
  final data = decoded['data'];
  if (data is! Map) return null;
  final pathObj = data['path'];
  final linesObj = data['lines'];
  final lineNum = data['line_number'];
  final textObj = linesObj is Map ? linesObj['text'] : null;
  final pathText = pathObj is Map ? pathObj['text'] : null;
  if (pathText is! String || lineNum is! int || textObj is! String) return null;
  return SearchHit(
      path: pathText, line: lineNum, lineText: textObj.trimRight());
}

/// 解析 `git grep -n` 输出行（path:line:text；路径内含冒号按前三段切）。
SearchHit? parseGitGrepLine(String line) {
  if (line.isEmpty) return null;
  final first = line.indexOf(':');
  if (first < 0) return null;
  final second = line.indexOf(':', first + 1);
  if (second < 0) return null;
  final path = line.substring(0, first);
  final lineNum = int.tryParse(line.substring(first + 1, second));
  if (lineNum == null) return null;
  return SearchHit(
      path: path, line: lineNum, lineText: line.substring(second + 1));
}

/// 进程启动器（与 Process.start 对齐，测试可注入）。
typedef StreamProcessStarter = Future<Process> Function(
  String executable,
  List<String> args, {
  String? workingDirectory,
});

/// 搜索后端。
enum SearchBackend { ripgrep, gitGrep }

class SearchService {
  SearchService({
    required this.root,
    this.starter = Process.start,
    this.maxHits = 500,
    this.defaultBackend,
  });

  final String root;
  final StreamProcessStarter starter;

  /// 单次搜索的命中上限（低内存纪律：结果列表有界）。
  final int maxHits;

  /// 固定后端（测试用）；null = 自动探测。
  final SearchBackend? defaultBackend;

  /// 探测可用后端；都不可用返回 null。
  Future<SearchBackend?> detectBackend() async {
    try {
      final rg = await starter('rg', ['--version'], workingDirectory: root);
      if (await rg.exitCode == 0) return SearchBackend.ripgrep;
    } catch (_) {
      // rg 不存在
    }
    try {
      final git = await starter(
          'git', ['rev-parse', '--is-inside-work-tree'],
          workingDirectory: root);
      if (await git.exitCode == 0) return SearchBackend.gitGrep;
    } catch (_) {
      // git 不可用
    }
    return null;
  }

  /// 流式搜索。[query] 为空时返回空流。取消订阅会终止子进程。
  ///
  /// 大小写：默认不敏感（rg -i / git grep -i）。
  Stream<SearchHit> search(
    String query, {
    bool caseSensitive = false,
    SearchBackend? backend,
  }) {
    late StreamController<SearchHit> controller;
    Process? proc;
    var count = 0;

    Future<void> run() async {
      try {
        if (query.trim().isEmpty) {
          await controller.close();
          return;
        }
        final resolved = backend ?? defaultBackend ?? await detectBackend();
        if (resolved == null || controller.isClosed) {
          if (!controller.isClosed) await controller.close();
          return;
        }
        if (resolved == SearchBackend.ripgrep) {
          proc = await starter(
            'rg',
            [
              '--json',
              '--no-messages',
              if (!caseSensitive) '-i',
              '--',
              query,
              '.', // 必须显式给路径：否则 rg 见 stdin 是管道会等待输入
            ],
            workingDirectory: root,
          );
        } else {
          proc = await starter(
            'git',
            [
              'grep',
              '-n',
              '-I',
              '--untracked', // 未跟踪文件也要搜（新建文件场景）
              if (!caseSensitive) '-i',
              '-e',
              query,
              '--',
              '.',

            ],
            workingDirectory: root,
          );
        }
        proc!.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          if (controller.isClosed) return;
          if (count >= maxHits) {
            proc?.kill();
            return;
          }
          final hit = resolved == SearchBackend.ripgrep
              ? parseRgJsonLine(line)
              : parseGitGrepLine(line);
          if (hit != null) {
            count++;
            controller.add(hit);
          }
        }, onDone: () {
          if (!controller.isClosed) controller.close();
        });
      } catch (e) {
        if (!controller.isClosed) {
          controller.addError(e);
          await controller.close();
        }
      }
    }

    controller = StreamController<SearchHit>(
      onListen: run,
      onCancel: () => proc?.kill(), // 取消订阅即终止子进程
    );
    return controller.stream;
  }
}