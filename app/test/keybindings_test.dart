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

  group('parseChordSequence', () {
    test('parses two strokes and displays each chord', () {
      final sequence = parseChordSequence('ctrl+k cmd+x')!;
      expect(sequence.chords, [parseChord('ctrl+k'), parseChord('cmd+x')]);
      expect(sequence.display, 'Ctrl+K Meta+X');
      expect(parseChordSequence('ctrl+k'), isNull);
      expect(parseChordSequence('ctrl+k invalid+x'), isNull);
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
      expect(mac.commandForChord(parseChord('ctrl+k')!), isNull);
      expect(
        mac.bindingForSequence(
          [parseChord('ctrl+k')!, parseChord('cmd+delete')!],
        )?.commandId,
        'deleteAllRight',
      );
    });

    test('trailing-whitespace and move-selection chords are platform sequences',
        () {
      final windows = KeybindingSet.load(platform: TargetPlatform.windows);
      final linux = KeybindingSet.load(platform: TargetPlatform.linux);
      final mac = KeybindingSet.load(platform: TargetPlatform.macOS);
      for (final keybindings in [windows, linux]) {
        expect(
          keybindings.bindingForSequence(
            [parseChord('ctrl+k')!, parseChord('ctrl+x')!],
          )?.commandId,
          'editor.action.trimTrailingWhitespace',
        );
        expect(
          keybindings.bindingForSequence(
            [parseChord('ctrl+k')!, parseChord('ctrl+d')!],
          )?.commandId,
          'editor.action.moveSelectionToNextFindMatch',
        );
      }
      expect(
        mac.bindingForSequence(
          [parseChord('cmd+k')!, parseChord('cmd+x')!],
        )?.commandId,
        'editor.action.trimTrailingWhitespace',
      );
      expect(mac.shortcutFor('editor.action.trimTrailingWhitespace'),
          'Meta+K Meta+X');
      expect(
        windows.hasSequencePrefix(parseChord('ctrl+k')!),
        isTrue,
      );
    });

    test('compare with clipboard uses Ctrl/Cmd+K then C', () {
      final windows = KeybindingSet.load(platform: TargetPlatform.windows);
      final linux = KeybindingSet.load(platform: TargetPlatform.linux);
      final mac = KeybindingSet.load(platform: TargetPlatform.macOS);
      for (final keybindings in [windows, linux]) {
        expect(
          keybindings.bindingForSequence(
            [parseChord('ctrl+k')!, parseChord('c')!],
          )?.commandId,
          'workbench.files.action.compareWithClipboard',
        );
        expect(
          keybindings.shortcutFor(
            'workbench.files.action.compareWithClipboard',
          ),
          'Ctrl+K C',
        );
      }
      expect(
        mac.bindingForSequence(
          [parseChord('cmd+k')!, parseChord('c')!],
        )?.commandId,
        'workbench.files.action.compareWithClipboard',
      );
      expect(
        mac.shortcutFor('workbench.files.action.compareWithClipboard'),
        'Meta+K C',
      );
    });

    test('compare with saved uses Ctrl/Cmd+K then D', () {
      final windows = KeybindingSet.load(platform: TargetPlatform.windows);
      final linux = KeybindingSet.load(platform: TargetPlatform.linux);
      final mac = KeybindingSet.load(platform: TargetPlatform.macOS);
      for (final keybindings in [windows, linux]) {
        expect(
          keybindings.bindingForSequence(
            [parseChord('ctrl+k')!, parseChord('d')!],
          )?.commandId,
          'workbench.files.action.compareWithSaved',
        );
        expect(
          keybindings.shortcutFor('workbench.files.action.compareWithSaved'),
          'Ctrl+K D',
        );
      }
      expect(
        mac.bindingForSequence(
          [parseChord('cmd+k')!, parseChord('d')!],
        )?.commandId,
        'workbench.files.action.compareWithSaved',
      );
      expect(
        mac.shortcutFor('workbench.files.action.compareWithSaved'),
        'Meta+K D',
      );
    });

    test('sticky and editor close commands use the platform defaults', () {
      final windows = KeybindingSet.load(platform: TargetPlatform.windows);
      final linux = KeybindingSet.load(platform: TargetPlatform.linux);
      final mac = KeybindingSet.load(platform: TargetPlatform.macOS);
      for (final keybindings in [windows, linux]) {
        expect(
          keybindings.commandForChord(parseChord('ctrl+w')!),
          'workbench.action.closeActiveEditor',
        );
        expect(
          keybindings.bindingForSequence(
            [parseChord('ctrl+k')!, parseChord('w')!],
          )?.commandId,
          'workbench.action.closeAllEditors',
        );
        expect(
          keybindings.bindingForSequence(
            [parseChord('ctrl+k')!, parseChord('ctrl+w')!],
          )?.commandId,
          'workbench.action.closeAllGroups',
        );
        expect(
          keybindings.bindingForSequence(
            [parseChord('ctrl+k')!, parseChord('ctrl+shift+enter')!],
          )?.commandId,
          'workbench.action.toggleEditorSticky',
        );
      }
      expect(mac.commandForChord(parseChord('cmd+w')!),
          'workbench.action.closeActiveEditor');
      expect(
        mac.bindingForSequence(
          [parseChord('cmd+k')!, parseChord('w')!],
        )?.commandId,
        'workbench.action.closeAllEditors',
      );
      expect(
        mac.bindingForSequence(
          [parseChord('cmd+k')!, parseChord('cmd+w')!],
        )?.commandId,
        'workbench.action.closeAllGroups',
      );
      expect(
        mac.bindingForSequence(
          [parseChord('cmd+k')!, parseChord('cmd+shift+enter')!],
        )?.commandId,
        'workbench.action.toggleEditorSticky',
      );
    });

    test(
        'line insertion uses Ctrl+Enter on Windows/Linux and Cmd+Enter on macOS',
        () {
      final windows = KeybindingSet.load(platform: TargetPlatform.windows);
      final linux = KeybindingSet.load(platform: TargetPlatform.linux);
      final mac = KeybindingSet.load(platform: TargetPlatform.macOS);
      for (final keybindings in [windows, linux]) {
        expect(
          keybindings.commandForChord(parseChord('ctrl+shift+enter')!),
          'editor.action.insertLineBefore',
        );
        expect(
          keybindings.commandForChord(parseChord('ctrl+enter')!),
          'editor.action.insertLineAfter',
        );
      }
      expect(
        mac.commandForChord(parseChord('cmd+shift+enter')!),
        'editor.action.insertLineBefore',
      );
      expect(
        mac.commandForChord(parseChord('cmd+enter')!),
        'editor.action.insertLineAfter',
      );
      expect(mac.commandForChord(parseChord('ctrl+enter')!), isNull);
    });

    test('line deletion uses Ctrl/Cmd+Shift+K on each platform', () {
      final windows = KeybindingSet.load(platform: TargetPlatform.windows);
      final linux = KeybindingSet.load(platform: TargetPlatform.linux);
      final mac = KeybindingSet.load(platform: TargetPlatform.macOS);
      for (final keybindings in [windows, linux]) {
        expect(
          keybindings.commandForChord(parseChord('ctrl+shift+k')!),
          'editor.action.deleteLines',
        );
      }
      expect(
        mac.commandForChord(parseChord('cmd+shift+k')!),
        'editor.action.deleteLines',
      );
      expect(mac.commandForChord(parseChord('ctrl+shift+k')!), isNull);
    });

    test('line comment toggle uses Ctrl+/ or Cmd+/ by platform', () {
      final windows = KeybindingSet.load(platform: TargetPlatform.windows);
      final linux = KeybindingSet.load(platform: TargetPlatform.linux);
      final mac = KeybindingSet.load(platform: TargetPlatform.macOS);
      for (final keybindings in [windows, linux]) {
        expect(
          keybindings.commandForChord(parseChord('ctrl+/')!),
          'editor.action.commentLine',
        );
      }
      expect(
        mac.commandForChord(parseChord('cmd+/')!),
        'editor.action.commentLine',
      );
      expect(mac.commandForChord(parseChord('ctrl+/')!), isNull);
    });

    test('block comment uses Alt+Shift+A or Linux Ctrl+Shift+A', () {
      final windows = KeybindingSet.load(platform: TargetPlatform.windows);
      final linux = KeybindingSet.load(platform: TargetPlatform.linux);
      final mac = KeybindingSet.load(platform: TargetPlatform.macOS);
      for (final keybindings in [windows, mac]) {
        expect(
          keybindings.commandForChord(parseChord('alt+shift+a')!),
          'editor.action.blockComment',
        );
      }
      expect(
        linux.commandForChord(parseChord('ctrl+shift+a')!),
        'editor.action.blockComment',
      );
      expect(windows.commandForChord(parseChord('ctrl+shift+a')!), isNull);
    });

    test('copy-line defaults coexist with platform column-selection chords',
        () {
      final windows = KeybindingSet.load(platform: TargetPlatform.windows);
      final linux = KeybindingSet.load(platform: TargetPlatform.linux);
      final mac = KeybindingSet.load(platform: TargetPlatform.macOS);

      expect(
        windows.commandForChord(parseChord('alt+shift+arrowup')!),
        'editor.action.copyLinesUpAction',
      );
      expect(
        windows.commandForChord(parseChord('alt+shift+arrowdown')!),
        'editor.action.copyLinesDownAction',
      );
      expect(
        windows.commandForChord(parseChord('ctrl+alt+shift+arrowup')!),
        'editor.columnSelectUp',
      );
      expect(
        windows.commandForChord(parseChord('ctrl+alt+shift+arrowdown')!),
        'editor.columnSelectDown',
      );

      expect(
        linux.commandForChord(parseChord('alt+shift+arrowup')!),
        'editor.columnSelectUp',
      );
      expect(
        linux.commandForChord(parseChord('alt+shift+arrowdown')!),
        'editor.columnSelectDown',
      );
      expect(
        linux.commandForChord(parseChord('ctrl+alt+shift+arrowup')!),
        'editor.action.copyLinesUpAction',
      );
      expect(
        linux.commandForChord(parseChord('ctrl+alt+shift+arrowdown')!),
        'editor.action.copyLinesDownAction',
      );

      expect(
        mac.commandForChord(parseChord('alt+shift+arrowup')!),
        'editor.action.copyLinesUpAction',
      );
      expect(
        mac.commandForChord(parseChord('alt+shift+arrowdown')!),
        'editor.action.copyLinesDownAction',
      );
    });

    test('move-line defaults use Alt+Up and Alt+Down on every platform', () {
      for (final platform in [
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.macOS,
      ]) {
        final keybindings = KeybindingSet.load(platform: platform);
        expect(
          keybindings.commandForChord(parseChord('alt+arrowup')!),
          'editor.action.moveLinesUpAction',
          reason: '$platform',
        );
        expect(
          keybindings.commandForChord(parseChord('alt+arrowdown')!),
          'editor.action.moveLinesDownAction',
          reason: '$platform',
        );
      }
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
      final expectedChords = KeybindingSet.defaults.values.fold<int>(
          0,
          (n, v) =>
              n +
              v.split(',').where((spec) => parseChord(spec) != null).length);
      expect(resolved.keys.length, expectedChords, reason: '逗号分隔的多键位各占一条');
      expect(ks.shortcutFor('view.commandPalette'), 'Ctrl+Shift+P');
      expect(ks.shortcutFor('workbench.action.files.newUntitledFile'), 'Ctrl+N');
      expect(ks.shortcutFor('file.save'), 'Ctrl+S');
      expect(ks.shortcutFor('file.saveAs'), 'Ctrl+Shift+S');
      expect(ks.shortcutFor('view.panelSyntax'), 'F3');
    });

    test('New Text File follows Windows/Linux Ctrl+N and macOS Cmd+N', () {
      for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
        final keys = KeybindingSet.load(platform: platform);
        expect(
          keys.commandForChord(parseChord('ctrl+n')!),
          'workbench.action.files.newUntitledFile',
        );
        expect(keys.shortcutFor('workbench.action.files.newUntitledFile'),
            'Ctrl+N');
      }

      final mac = KeybindingSet.load(platform: TargetPlatform.macOS);
      expect(
        mac.commandForChord(parseChord('cmd+n')!),
        'workbench.action.files.newUntitledFile',
      );
      expect(mac.commandForChord(parseChord('ctrl+n')!), isNull);
      expect(
        mac.shortcutFor('workbench.action.files.newUntitledFile'),
        'Meta+N',
      );
    });

    test('New Text File respects a user keybinding override', () {
      final keys = KeybindingSet.load(
        platform: TargetPlatform.windows,
        userJson:
            '[{"key":"ctrl+alt+n","command":"workbench.action.files.newUntitledFile"}]',
      );
      expect(
        keys.commandForChord(parseChord('ctrl+alt+n')!),
        'workbench.action.files.newUntitledFile',
      );
      expect(keys.commandForChord(parseChord('ctrl+n')!), isNull);
      expect(
        keys.shortcutFor('workbench.action.files.newUntitledFile'),
        'Ctrl+Alt+N',
      );
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

    test('用户键位可覆盖与移除双段默认键位', () {
      final ks = KeybindingSet.load(
        userJson: '[{"key":"ctrl+alt+f ctrl+alt+g",'
            '"command":"editor.action.trimTrailingWhitespace"}]',
        platform: TargetPlatform.windows,
      );
      expect(
        ks.bindingForSequence(
          [parseChord('ctrl+alt+f')!, parseChord('ctrl+alt+g')!],
        )?.commandId,
        'editor.action.trimTrailingWhitespace',
      );
      expect(
        ks.bindingForSequence(
          [parseChord('ctrl+k')!, parseChord('ctrl+x')!],
        ),
        isNull,
      );
      expect(ks.shortcutFor('editor.action.trimTrailingWhitespace'),
          'Ctrl+Alt+F Ctrl+Alt+G');

      final removed = KeybindingSet.load(
        userJson: '[{"key":"ctrl+k ctrl+x",'
            '"command":"-editor.action.trimTrailingWhitespace"}]',
        platform: TargetPlatform.windows,
      );
      expect(
        removed.bindingForSequence(
          [parseChord('ctrl+k')!, parseChord('ctrl+x')!],
        ),
        isNull,
      );
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
      final expectedChords = KeybindingSet.defaults.values.fold<int>(
          0,
          (n, v) =>
              n +
              v.split(',').where((spec) => parseChord(spec) != null).length);
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
    test('Join Lines is command-palette-only on Windows/Linux and Ctrl+J on macOS', () {
      final windows = KeybindingSet.load(platform: TargetPlatform.windows);
      final linux = KeybindingSet.load(platform: TargetPlatform.linux);
      final mac = KeybindingSet.load(platform: TargetPlatform.macOS);

      for (final keybindings in [windows, linux]) {
        expect(
          keybindings.commandForChord(parseChord('ctrl+j')!),
          'view.togglePanel',
        );
        expect(keybindings.shortcutFor('editor.action.joinLines'), isNull);
      }
      expect(
        mac.commandForChord(parseChord('ctrl+j')!),
        'editor.action.joinLines',
      );
      expect(mac.shortcutFor('editor.action.joinLines'), 'Ctrl+J');
      expect(mac.commandForChord(parseChord('cmd+j')!), 'view.togglePanel');
      expect(mac.shortcutFor('view.togglePanel'), 'Meta+J');
    });
  });
}
