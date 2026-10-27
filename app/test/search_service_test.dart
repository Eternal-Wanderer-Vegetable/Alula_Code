// SearchService 单测：rg --json / git grep 输出解析 + 临时仓库集成（真实子进程）。
// 对应 docs/09 W4 搜索视图。
import 'dart:io';

import 'package:alula_app/search/search_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/temp_repo.dart';

void main() {
  group('parseRgJsonLine', () {
    test('match 事件解析', () {
      const line = '{"type":"match","data":{"path":{"text":"src/a.rs"},'
          '"line_number":7,"lines":{"text":"fn main() {}\\n"},"absolute_offset":0}}';
      final hit = parseRgJsonLine(line)!;
      expect(hit.path, 'src/a.rs');
      expect(hit.line, 7);
      expect(hit.lineText, 'fn main() {}');
    });

    test('非 match 事件与坏 JSON 返回 null', () {
      expect(parseRgJsonLine('{"type":"begin","data":{}}'), isNull);
      expect(parseRgJsonLine('not json'), isNull);
      expect(parseRgJsonLine(''), isNull);
    });
  });

  group('parseGitGrepLine', () {
    test('path:line:text', () {
      final hit = parseGitGrepLine('src/a.rs:7:fn main() {}')!;
      expect(hit.path, 'src/a.rs');
      expect(hit.line, 7);
      expect(hit.lineText, 'fn main() {}');
    });

    test('路径含冒号：行号段解析失败 → null（rg 为主后端，可接受）', () {
      expect(parseGitGrepLine('a:b.txt:12:hello'), isNull);
    });

    test('Windows 盘符路径：C 会被误判为行号 → null（可接受，rg 优先）', () {
      // 'C:/x.txt:1:hi' → path='C' line=… — 行号解析 '/x.txt' 失败 → null
      expect(parseGitGrepLine('C:/x.txt:1:hi'), isNull);
    });

    test('坏行返回 null', () {
      expect(parseGitGrepLine(''), isNull);
      expect(parseGitGrepLine('no-colon-here'), isNull);
      expect(parseGitGrepLine('path:notanumber:text'), isNull);
    });
  });

  group('集成（真实子进程，临时仓库）', () {
    late Directory repo;

    setUp(() async {
      repo = await createTempRepo(prefix: 'alula_search_it', extraFiles: {
        'src/main.rs': 'fn main() {\n    print("hello alula");\n}\n',
        'docs/note.md': '# 笔记\nhello from markdown\n',
      });
    });

    tearDown(() async {
      if (repo.existsSync()) await repo.delete(recursive: true);
    });

    test('git grep 后端：全量收集 + 行号正确', () async {
      final svc = SearchService(
          root: repo.path,
          defaultBackend: SearchBackend.gitGrep,
          starter: Process.start);
      final hits = await svc.search('hello').toList();
      expect(hits.length, 2, reason: 'main.rs + note.md 各一处');
      final mainHit = hits.firstWhere((h) => h.path.endsWith('main.rs'));
      expect(mainHit.line, 2);
      expect(mainHit.lineText, contains('hello alula'));
    });

    test('rg 后端（若本机可用）：结果与 git grep 一致', () async {
      // CI 可能没有 rg（可执行文件不存在会抛异常，不只是非零退出码）
      var rgAvailable = false;
      try {
        final probe = await Process.run('rg', ['--version']);
        rgAvailable = probe.exitCode == 0;
      } on ProcessException {
        rgAvailable = false;
      }
      if (!rgAvailable) return;
      final svc = SearchService(
          root: repo.path,
          defaultBackend: SearchBackend.ripgrep,
          starter: Process.start);
      final hits = await svc.search('hello').toList();
      expect(hits.length, 2);
      expect(hits.every((h) => h.lineText.contains('hello')), isTrue);
    });

    test('空查询返回空流', () async {
      final svc = SearchService(
          root: repo.path,
          defaultBackend: SearchBackend.gitGrep,
          starter: Process.start);
      expect(await svc.search('  ').toList(), isEmpty);
    });

    test('命中上限：达到 maxHits 后提前终止', () async {
      final svc = SearchService(
          root: repo.path,
          defaultBackend: SearchBackend.gitGrep,
          starter: Process.start,
          maxHits: 1);
      final hits = await svc.search('hello').toList();
      expect(hits.length, 1);
    });
  });
}
