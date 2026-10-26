// LayoutStore 单测：保存/恢复往返、损坏文件回退、临时文件清理。
// 纯 Dart IO（注入临时路径），无 FFI/无 widget。对应 docs/09 W1-4。
import 'dart:io';

import 'package:alula_app/workbench/layout_model.dart';
import 'package:alula_app/workbench/layout_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late LayoutStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('alula_layout_test');
    store = LayoutStore(path: '${tmp.path.replaceAll('\\', '/')}/layout.json');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('无文件 → tryLoad 返回 null（回退默认布局）', () {
    expect(store.tryLoad(), isNull);
  });

  test('save → tryLoad 往返：权重/折叠/嵌套结构一致', () {
    final root = defaultLayout();
    final sidebar = root.leafOf('sidebar')!;
    sidebar.weight = 0.31;
    final panel = root.leafOf('panel')!;
    panel.lastWeight = panel.weight;
    panel.collapsed = true;

    store.save(root);
    final loaded = store.tryLoad();
    expect(loaded, isNotNull);

    expect(loaded!.leafOf('sidebar')!.weight, closeTo(0.31, 1e-9));
    final loadedPanel = loaded.leafOf('panel')!;
    expect(loadedPanel.collapsed, isTrue);
    expect(loadedPanel.lastWeight, closeTo(0.3, 1e-9));
    // 嵌套 split 结构与固定叶子
    expect(loaded.leafOf('activity')!.fixedExtent, 44);
  });

  test('损坏文件 → tryLoad 返回 null 不抛异常', () {
    File(store.resolvePath()).writeAsStringSync('{"t":"split","child');
    expect(store.tryLoad(), isNull);
    File(store.resolvePath()).writeAsStringSync('not json at all');
    expect(store.tryLoad(), isNull);
    // 结构非法（叶子当根）
    File(store.resolvePath())
        .writeAsStringSync('{"t":"leaf","region":"solo"}');
    expect(store.tryLoad(), isNull);
  });

  test('保存不留 .tmp 半写文件（原子替换）', () {
    store.save(defaultLayout());
    store.save(defaultLayout()); // 覆盖已存在文件
    final leftovers = tmp
        .listSync()
        .where((e) => e.path.endsWith('.tmp'))
        .toList();
    expect(leftovers, isEmpty);
    expect(store.tryLoad(), isNotNull);
  });
}
