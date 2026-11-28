// LayoutStore 单测：保存/恢复往返、损坏文件回退、临时文件清理。
// 纯 Dart IO（注入临时路径），无 FFI/无 widget。对应 docs/09 W1-4。
import 'dart:io';

import 'package:alula_app/bridge/alula_core.dart'
    show HierarchyDirection, HierarchyKind;
import 'package:alula_app/workbench/layout_controller.dart';
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
    final layout = WorkbenchLayout(root: defaultLayout());
    final root = layout.root;
    final sidebar = root.leafOf('sidebar')!;
    sidebar.weight = 0.31;
    final panel = root.leafOf('panel')!;
    panel.lastWeight = panel.weight;
    panel.collapsed = true;
    layout.setRegionCollapsed('activity', true);

    store.save(root);
    final loaded = store.tryLoad();
    expect(loaded, isNotNull);

    expect(loaded!.leafOf('sidebar')!.weight, closeTo(0.31, 1e-9));
    final loadedPanel = loaded.leafOf('panel')!;
    expect(loadedPanel.collapsed, isTrue);
    expect(loadedPanel.lastWeight, closeTo(0.3, 1e-9));
    // 嵌套 split 结构与固定叶子
    final loadedActivity = loaded.leafOf('activity')!;
    expect(loadedActivity.fixedExtent, 48);
    expect(loadedActivity.collapsed, isTrue);
    expect(loadedActivity.lastWeight, 1);
    layout.dispose();
  });

  test('损坏文件 → tryLoad 返回 null 不抛异常', () {
    File(store.resolvePath()).writeAsStringSync('{"t":"split","child');
    expect(store.tryLoad(), isNull);
    File(store.resolvePath()).writeAsStringSync('not json at all');
    expect(store.tryLoad(), isNull);
    // 结构非法（叶子当根）
    File(store.resolvePath()).writeAsStringSync('{"t":"leaf","region":"solo"}');
    expect(store.tryLoad(), isNull);
  });

  test('centered margins are profile-local and invalid pairs use defaults', () {
    const margins = (left: 0.32, right: 0.12);
    expect(store.loadCenteredMargins(), defaultCenteredMargins);

    store.saveCenteredLayout('/workspace-a', true);
    store.saveCenteredMargins(margins);
    expect(LayoutStore(path: store.resolvePath()).loadCenteredMargins(), margins);
    expect(store.loadCenteredLayout('/workspace-a'), isTrue);
    expect(store.loadCenteredLayout('/workspace-b'), isFalse);
    final otherProfile = LayoutStore(path: '${tmp.path}/other-layout.json');
    expect(otherProfile.loadCenteredMargins(), defaultCenteredMargins);

    final file = File('${store.resolvePath()}.centered-margins.json');
    for (final value in [
      '{',
      '{"left":0.12}',
      '{"left":-0.12,"right":0.22}',
      '{"left":0.65,"right":0.35}',
      '{"left":1e999,"right":0.02}',
    ]) {
      file.writeAsStringSync(value);
      expect(store.loadCenteredMargins(), defaultCenteredMargins);
      expect(store.loadCenteredLayout('/workspace-a'), isTrue);
    }
  });

  test('hierarchy directions round-trip independently in the profile', () {
    final reopened = LayoutStore(path: store.resolvePath());
    expect(reopened.loadHierarchyDirection(HierarchyKind.call), isNull);
    expect(reopened.loadHierarchyDirection(HierarchyKind.type), isNull);
    expect(store.saveHierarchyDirection(HierarchyDirection.outgoing), isTrue);
    expect(
        reopened.saveHierarchyDirection(HierarchyDirection.supertypes), isTrue);
    expect(store.loadHierarchyDirection(HierarchyKind.call),
        HierarchyDirection.outgoing);
    expect(store.loadHierarchyDirection(HierarchyKind.type),
        HierarchyDirection.supertypes);
    expect(store.saveHierarchyDirection(HierarchyDirection.incoming), isTrue);
    expect(reopened.loadHierarchyDirection(HierarchyKind.call),
        HierarchyDirection.incoming);
    expect(reopened.loadHierarchyDirection(HierarchyKind.type),
        HierarchyDirection.supertypes);
  });

  test('damaged hierarchy preferences fall back only for their own kind', () {
    expect(store.saveHierarchyDirection(HierarchyDirection.outgoing), isTrue);
    final file = File('${store.resolvePath()}.type-hierarchy.json');
    for (final value in ['{', '22', '"outgoing"', '{"direction":"subtypes"}']) {
      file.writeAsStringSync(value);
      expect(store.loadHierarchyDirection(HierarchyKind.type), isNull);
      expect(store.loadHierarchyDirection(HierarchyKind.call),
          HierarchyDirection.outgoing);
    }
  });

  test(
      'a failed hierarchy write leaves the existing path and no temporary file',
      () {
    final blocked = Directory('${store.resolvePath()}.call-hierarchy.json')
      ..createSync();
    expect(store.saveHierarchyDirection(HierarchyDirection.outgoing), isFalse);
    expect(blocked.existsSync(), isTrue);
    expect(tmp.listSync().map((entry) => entry.path), [blocked.path]);
  });

  test('保存不留 .tmp 半写文件（原子替换）', () {
    store.save(defaultLayout());
    store.save(defaultLayout()); // 覆盖已存在文件
    final leftovers =
        tmp.listSync().where((e) => e.path.endsWith('.tmp')).toList();
    expect(leftovers, isEmpty);
    expect(store.tryLoad(), isNotNull);
  });
}
