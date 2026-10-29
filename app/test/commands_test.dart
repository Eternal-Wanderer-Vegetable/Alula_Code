// CommandRegistry 与模糊搜索单测（docs/09 W3-1）。
import 'package:alula_app/workbench/commands.dart';
import 'package:alula_app/workbench/context_keys.dart';
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

  group('命令上下文与统一分发', () {
    test('表达式支持布尔组合、相等比较、分组并对非法表达式关闭', () {
      final context = ContextKeyService()
        ..setValues(
            {'editorActive': true, 'language': 'rust', 'readOnly': false});

      expect(context.matches('editorActive && language == "rust"'), isTrue);
      expect(context.matches('editorActive && (!readOnly || false)'), isTrue);
      expect(
          context.matches('(editorActive && language == "python") || readOnly'),
          isFalse);
      expect(context.matches('editorActive && )'), isFalse);
      context.dispose();
    });

    test('context 变化即时更新可见和启用状态，分发接收 id 与参数', () async {
      final commands = CommandService();
      Object? received;
      commands.register(Command(
        id: 'editor.openAt',
        title: '打开位置',
        category: '编辑器',
        run: () async {},
        when: 'editorActive',
        enablement: 'workspaceOpen',
        runWithArguments: (arguments) async => received = arguments,
      ));

      expect(commands.isVisible('editor.openAt'), isFalse);
      expect(commands.isEnabled('editor.openAt'), isFalse);
      commands.context
          .setValues({'editorActive': true, 'workspaceOpen': false});
      expect(commands.isVisible('editor.openAt'), isTrue);
      expect(commands.isEnabled('editor.openAt'), isFalse);
      expect(await commands.execute('editor.openAt', arguments: 12),
          CommandExecutionStatus.disabled);
      commands.context.setValue('workspaceOpen', true);
      expect(commands.isEnabled('editor.openAt'), isTrue);
      expect(await commands.execute('editor.openAt', arguments: 12),
          CommandExecutionStatus.executed);
      expect(received, 12);
      expect(await commands.execute('missing'), CommandExecutionStatus.unknown);

      commands.context.setValue('editorActive', false);
      expect(commands.isVisible('editor.openAt'), isFalse);
      expect(await commands.execute('editor.openAt'),
          CommandExecutionStatus.hidden);
      commands.dispose();
    });
  });
}
