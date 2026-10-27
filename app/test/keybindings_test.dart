// KeybindingSet 单测：键位串解析、默认表、用户覆盖（追加/移除/损坏回退）。
// 对应 docs/09 W3-2；纯逻辑测试。
import 'package:alula_app/workbench/keybindings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseChord', () {
    test('修饰键组合与裸键', () {
      final c = parseChord('ctrl+shift+p')!;
      expect(c.key, LogicalKeyboardKey.keyP);
      expect(c.control, isTrue);
      expect(c.shift, isTrue);
      expect(c.display, 'Ctrl+Shift+P');

      expect(parseChord('f8')!.key, LogicalKeyboardKey.f8);
      expect(parseChord('ctrl+space')!.key, LogicalKeyboardKey.space);
      expect(parseChord(' Control + S ')!.control, isTrue, reason: '空白与大小写容忍');
    });

    test('非法输入返回 null', () {
      expect(parseChord('ctrl+'), isNull);
      expect(parseChord('meta+k'), isNull, reason: '未知修饰键整条作废');
      expect(parseChord(''), isNull);
    });
  });

  group('KeybindingSet', () {
    test('默认表可解析且包含核心键位', () {
      final ks = KeybindingSet.load();
      final resolved = ks.resolve();
      expect(resolved.keys.length, KeybindingSet.defaults.length);
      expect(ks.shortcutFor('view.commandPalette'), 'Ctrl+Shift+P');
      expect(ks.shortcutFor('file.save'), 'Ctrl+S');
      expect(ks.shortcutFor('view.panelSyntax'), 'F3');
    });

    test('用户追加：新键位生效', () {
      final ks = KeybindingSet.load(userJson:
          '[{"key": "ctrl+alt+f", "command": "view.quickOpen"}]');
      expect(ks.commandForChord(parseChord('ctrl+alt+f')!), 'view.quickOpen',
          reason: '追加的新键位生效');
      expect(ks.shortcutFor('view.quickOpen'), 'Ctrl+Alt+F',
          reason: '后写者胜：追加覆盖展示');
    });

    test('用户移除：-command 删掉匹配的默认键位', () {
      final ks = KeybindingSet.load(userJson:
          '[{"key": "ctrl+p", "command": "-view.quickOpen"}]');
      expect(ks.commandForChord(parseChord('ctrl+p')!), isNull,
          reason: '默认 Ctrl+P 已被移除');
      expect(ks.shortcutFor('view.quickOpen'), isNull);
    });

    test('移除不匹配的键位串：无操作', () {
      final ks = KeybindingSet.load(userJson:
          '[{"key": "ctrl+q", "command": "-view.quickOpen"}]');
      expect(ks.commandForChord(parseChord('ctrl+p')!), 'view.quickOpen',
          reason: '键位不匹配不移除');
    });

    test('损坏 JSON：只用默认键位', () {
      final ks = KeybindingSet.load(userJson: '[{"key": broken');
      expect(ks.resolve().length, KeybindingSet.defaults.length);
      final ks2 = KeybindingSet.load(userJson: '{"not":"an array"}');
      expect(ks2.resolve().length, KeybindingSet.defaults.length);
    });

    test('非法条目逐条忽略，合法条目仍生效', () {
      final ks = KeybindingSet.load(userJson:
          '[{"nope": 1}, {"key": "meta+x", "command": "file.save"}, '
          '{"key": "ctrl+y", "command": "view.togglePanel"}]');
      expect(ks.commandForChord(parseChord('ctrl+y')!), 'view.togglePanel',
          reason: '合法条目生效');
      expect(ks.commandForChord(parseChord('ctrl+x')!), isNull,
          reason: 'meta 修饰键非法被忽略');
    });
  });
}
