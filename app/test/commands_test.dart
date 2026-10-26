// CommandRegistry 与模糊搜索单测（docs/09 W3-1）。
import 'package:alula_app/workbench/commands.dart';
import 'package:flutter_test/flutter_test.dart';

Command _cmd(String id, String category, String title) => Command(
      id: id,
      category: category,
      title: title,
      run: () async {},
    );

void main() {
  group('注册表', () {
    test('注册 / 查找 / 同 id 覆盖 / 注销', () {
      final r = CommandRegistry();
      r.register(_cmd('file.save', '文件', '保存'));
      r.register(_cmd('view.sidebar', '查看', '切换侧栏'));
      expect(r.all.length, 2);
      expect(r.byId('file.save')?.title, '保存');

      r.register(_cmd('file.save', '文件', '保存全部'));
      expect(r.all.length, 2, reason: '同 id 覆盖');
      expect(r.byId('file.save')?.title, '保存全部');

      r.unregister('file.save');
      expect(r.byId('file.save'), isNull);
    });

    test('label 为「分类: 名称」', () {
      expect(_cmd('file.save', '文件', '保存').label, '文件: 保存');
    });
  });

  group('fuzzyScore', () {
    test('子序列命中返回分数，不命中返回 null', () {
      expect(fuzzyScore('保存', '文件: 保存'), isNotNull);
      expect(fuzzyScore('bc', 'abc'), isNotNull);
      expect(fuzzyScore('ca', 'abc'), isNull, reason: '乱序不是子序列');
      expect(fuzzyScore('zzz', '文件: 保存'), isNull);
      expect(fuzzyScore('', '任意'), 0, reason: '空查询匹配一切');
    });

    test('前缀/词首命中比中段命中分高', () {
      final prefix = fuzzyScore('保', '保存')!;
      final middle = fuzzyScore('存', '保存')!;
      expect(prefix, greaterThan(middle));
    });

    test('连续命中比离散命中分高', () {
      final contiguous = fuzzyScore('拆分', '编辑: 拆分编辑器')!;
      final sparse = fuzzyScore('拆器', '编辑: 拆分编辑器')!;
      expect(contiguous, greaterThan(sparse));
    });

    test('大小写不敏感', () {
      expect(fuzzyScore('OPEN', 'file: open folder'), isNotNull);
    });
  });

  group('search 排序', () {
    test('按分数降序，同分按 label 字典序', () {
      final r = CommandRegistry();
      r.register(_cmd('view.panel', '查看', '切换面板'));
      r.register(_cmd('view.sidebar', '查看', '切换侧栏'));
      r.register(_cmd('file.save', '文件', '保存'));
      r.register(_cmd('file.saveAll', '文件', '保存全部'));

      // '保存' 应排最前（完整连续命中）
      final result = r.search('保存');
      expect(result.first.title, anyOf('保存', '保存全部'));
      // 不匹配的被剔除
      expect(r.search('zzz'), isEmpty);
      // 空查询返回全部
      expect(r.search('').length, 4);
      // 同分按 label 字典序：切换侧栏 < 切换面板
      final qie = r.search('切换');
      expect(qie.map((c) => c.title).toList(), ['切换侧栏', '切换面板']);
    });
  });
}
