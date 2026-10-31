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
      expect(parseChord('insert')!.key, LogicalKeyboardKey.insert);
      expect(parseChord(' Control + S ')!.control, isTrue, reason: '空白与大小写容忍');
    });

    test('非法输入返回 null', () {
      expect(parseChord('ctrl+'), isNull);
      expect(parseChord('meta+k'), isNull, reason: '未知修饰键整条作废');
      expect(parseChord(''), isNull);
    });
  });

  group('KeybindingSet', () {
    test('occurrence selection defaults use platform commands', () {
      final windows = KeybindingSet.load(platform: TargetPlatform.windows);
      expect(
        windows.commandForChord(parseChord('ctrl+d')!),
        'editor.selectNextOccurrence',
      );
      expect(windows.commandForChord(parseChord('ctrl+shift+d')!), isNull);

      final mac = KeybindingSet.load(platform: TargetPlatform.macOS);
      expect(
        mac.commandForChord(parseChord('cmd+d')!),
        'editor.selectNextOccurrence',
      );
      expect(mac.commandForChord(parseChord('ctrl+d')!), isNull);
    });

    test('overtype toggle follows the pinned platform keybindings', () {
      final windows = KeybindingSet.load(platform: TargetPlatform.windows);
      final linux = KeybindingSet.load(platform: TargetPlatform.linux);
      final mac = KeybindingSet.load(platform: TargetPlatform.macOS);
      expect(
        windows.commandForChord(parseChord('insert')!),
        'editor.action.toggleOvertypeInsertMode',
      );
      expect(
        linux.commandForChord(parseChord('insert')!),
        'editor.action.toggleOvertypeInsertMode',
      );
      expect(mac.commandForChord(parseChord('insert')!), isNull);
      expect(
        mac.commandForChord(parseChord('cmd+alt+o')!),
        'editor.action.toggleOvertypeInsertMode',
      );
    });

    test('word delete follows the pinned platform keybindings', () {
      final windows = KeybindingSet.load(platform: TargetPlatform.windows);
      final linux = KeybindingSet.load(platform: TargetPlatform.linux);
      final mac = KeybindingSet.load(platform: TargetPlatform.macOS);
      expect(
        windows.commandForChord(parseChord('ctrl+backspace')!),
        'deleteWordLeft',
      );
      expect(
        windows.commandForChord(parseChord('ctrl+delete')!),
        'deleteWordRight',
      );
      expect(
        linux.commandForChord(parseChord('ctrl+backspace')!),
        'deleteWordLeft',
      );
      expect(
        linux.commandForChord(parseChord('ctrl+delete')!),
        'deleteWordRight',
      );
      expect(mac.commandForChord(parseChord('ctrl+backspace')!), isNull);
      expect(mac.commandForChord(parseChord('ctrl+delete')!), isNull);
      expect(
        mac.commandForChord(parseChord('alt+backspace')!),
        'deleteWordLeft',
      );
      expect(
        mac.commandForChord(parseChord('alt+delete')!),
        'deleteWordRight',
      );
    });

    test('line-boundary deletion follows the pinned platform keybindings', () {
      final windows = KeybindingSet.load(platform: TargetPlatform.windows);
      final linux = KeybindingSet.load(platform: TargetPlatform.linux);
      final mac = KeybindingSet.load(platform: TargetPlatform.macOS);
      for (final keybindings in [windows, linux]) {
        expect(
            keybindings.commandForChord(parseChord('cmd+backspace')!), isNull);
        expect(keybindings.commandForChord(parseChord('ctrl+k')!), isNull);
        expect(keybindings.commandForChord(parseChord('cmd+delete')!), isNull);
      }
      expect(
        mac.commandForChord(parseChord('cmd+backspace')!),
        'deleteAllLeft',
      );
      expect(mac.commandForChord(parseChord('ctrl+k')!), 'deleteAllRight');
      expect(
        mac.commandForChord(parseChord('cmd+delete')!),
        'deleteAllRight',
      );
    });

    test('navigation defaults leave platform word-movement chords available',
        () {
      final mac = KeybindingSet.load(platform: TargetPlatform.macOS);
      expect(
        mac.commandForChord(parseChord('ctrl+-')!),
        'workbench.action.navigateBack',
      );
      expect(
        mac.commandForChord(parseChord('ctrl+shift+-')!),
        'workbench.action.navigateForward',
      );
      expect(mac.commandForChord(parseChord('alt+arrowleft')!), isNull);
      expect(mac.commandForChord(parseChord('alt+shift+arrowleft')!), isNull);
      expect(
        mac.commandForChord(parseChord('ctrl+alt+arrowleft')!),
        'editor.wordPartLeft',
      );
      expect(
        mac.commandForChord(parseChord('ctrl+alt+shift+arrowright')!),
        'editor.wordPartRightSelect',
      );

      final linux = KeybindingSet.load(platform: TargetPlatform.linux);
      expect(
        linux.commandForChord(parseChord('ctrl+alt+-')!),
        'workbench.action.navigateBack',
      );
      expect(
        linux.commandForChord(parseChord('ctrl+shift+-')!),
        'workbench.action.navigateForward',
      );
      expect(linux.commandForChord(parseChord('ctrl+alt+arrowleft')!), isNull);

      final windows = KeybindingSet.load(platform: TargetPlatform.windows);
      expect(
        windows.commandForChord(parseChord('alt+arrowleft')!),
        'workbench.action.navigateBack',
      );
      expect(
        windows.commandForChord(parseChord('alt+arrowright')!),
        'workbench.action.navigateForward',
      );
      expect(
          windows.commandForChord(parseChord('ctrl+alt+arrowleft')!), isNull);
    });

    test('默认表可解析且包含核心键位', () {
      final ks = KeybindingSet.load();
      final resolved = ks.resolve();
      final expectedChords = KeybindingSet.defaults.values
          .fold<int>(0, (n, v) => n + v.split(',').length);
      expect(resolved.keys.length, expectedChords, reason: '逗号分隔的多键位各占一条');
      expect(ks.shortcutFor('view.commandPalette'), 'Ctrl+Shift+P');
      expect(ks.shortcutFor('file.save'), 'Ctrl+S');
      expect(ks.shortcutFor('file.saveAs'), 'Ctrl+Shift+S');
      expect(ks.shortcutFor('view.panelSyntax'), 'F3');
    });

    test('用户追加：新键位生效', () {
      final ks = KeybindingSet.load(
          userJson: '[{"key": "ctrl+alt+f", "command": "view.quickOpen"}]');
      expect(ks.commandForChord(parseChord('ctrl+alt+f')!), 'view.quickOpen',
          reason: '新键位生效');
      expect(ks.commandForChord(parseChord('ctrl+p')!), isNull,
          reason: '重绑定语义：同命令旧默认键位让位');
      expect(ks.shortcutFor('view.quickOpen'), 'Ctrl+Alt+F',
          reason: '展示跟随用户重绑定');
    });

    test('键位携带参数和 when 条件并参与上下文过滤', () {
      final ks = KeybindingSet.load(
          userJson: '[{"key":"ctrl+alt+f","command":"view.quickOpen",'
              '"args":{"path":"src/main.rs"},"when":"editorTextFocus"}]');
      final chord = parseChord('ctrl+alt+f')!;
      final binding = ks.bindingForChord(chord)!;
      expect(binding.commandId, 'view.quickOpen');
      expect(binding.arguments, {'path': 'src/main.rs'});
      expect(binding.when, 'editorTextFocus');
      expect(
        ks
            .resolveBindings(matchesWhen: (condition) => condition == null)
            .values
            .where((binding) => binding.commandId == 'view.quickOpen'),
        isEmpty,
      );
      expect(
        ks
            .resolveBindings(
                matchesWhen: (condition) => condition == 'editorTextFocus')
            .values
            .where((binding) => binding.commandId == 'view.quickOpen'),
        hasLength(1),
      );
    });

    test('用户移除：-command 删掉匹配的默认键位', () {
      final ks = KeybindingSet.load(
          userJson: '[{"key": "ctrl+p", "command": "-view.quickOpen"}]');
      expect(ks.commandForChord(parseChord('ctrl+p')!), isNull,
          reason: '默认 Ctrl+P 已被移除');
      expect(ks.shortcutFor('view.quickOpen'), isNull);
    });

    test('移除不匹配的键位串：无操作', () {
      final ks = KeybindingSet.load(
          userJson: '[{"key": "ctrl+q", "command": "-view.quickOpen"}]');
      expect(ks.commandForChord(parseChord('ctrl+p')!), 'view.quickOpen',
          reason: '键位不匹配不移除');
    });

    test('损坏 JSON：只用默认键位', () {
      final ks = KeybindingSet.load(userJson: '[{"key": broken');
      final expectedChords = KeybindingSet.defaults.values
          .fold<int>(0, (n, v) => n + v.split(',').length);
      expect(ks.resolve().length, expectedChords);
      final ks2 = KeybindingSet.load(userJson: '{"not":"an array"}');
      expect(ks2.resolve().length, expectedChords);
    });

    test('非法条目逐条忽略，合法条目仍生效', () {
      final ks = KeybindingSet.load(
          userJson: '[{"nope": 1}, {"key": "meta+x", "command": "file.save"}, '
              '{"key": "ctrl+y", "command": "view.togglePanel"}]');
      expect(ks.commandForChord(parseChord('ctrl+y')!), 'view.togglePanel',
          reason: '合法条目生效');
      expect(ks.commandForChord(parseChord('ctrl+x')!), isNull,
          reason: 'meta 修饰键非法被忽略');
    });
  });
}
