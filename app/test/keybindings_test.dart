// KeybindingSet 单测：键位串解析、默认表、用户覆盖（追加/移除/损坏回退）。
// 对应 docs/09 W3-2；纯逻辑测试。
import 'package:alula_app/workbench/context_keys.dart';
import 'package:alula_app/workbench/keybindings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const quickOpenId = 'workbench.action.quickOpen';

  test('problem navigation owns F8 in editor focus and preserves rebindings', () {
    for (final platform in [
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    ]) {
      final keys = KeybindingSet.load(platform: platform);
      final context = ContextKeyService();
      addTearDown(context.dispose);
      String? command(String chord, KeybindingSet bindings) => bindings
          .bindingForChord(parseChord(chord)!, matchesWhen: context.matches)
          ?.commandId;

      expect(command('f8', keys), isNull);
      expect(command('shift+f8', keys), isNull);
      context.setValue('editorTextFocus', true);
      expect(command('f8', keys), 'editor.action.marker.nextInFiles');
      expect(command('shift+f8', keys), 'editor.action.marker.prevInFiles');
      expect(command('ctrl+space', keys), 'editor.completion');

      final override = KeybindingSet.load(
        platform: platform,
        userJson: '[{"key":"f8","command":"editor.completion"}]',
      );
      expect(command('f8', override), 'editor.completion');
      expect(command('shift+f8', override), 'editor.action.marker.prevInFiles');
    }
  });

  test('call hierarchy keyboard routing follows direction and stable Peek', () {
    final keys = KeybindingSet.load(platform: TargetPlatform.windows);
    final context = ContextKeyService();
    addTearDown(context.dispose);
    String? command(String key) => keys
        .bindingForChord(parseChord(key)!, matchesWhen: context.matches)
        ?.commandId;
    context.setValues({'editorTextFocus': true});
    expect(command('alt+shift+h'), isNot('editor.showCallHierarchy'));
    context.setValue('editorHasCallHierarchyProvider', true);
    expect(command('alt+shift+h'), 'editor.showCallHierarchy');
    expect(command('shift+enter'), isNot('editor.refocusCallHierarchy'));
    context.setValues({
      'callHierarchyVisible': true,
      'callHierarchyHasRoots': true,
      'callHierarchyIncoming': true,
    });
    expect(command('alt+shift+h'), 'editor.showOutgoingCalls');
    context.setValues({'callHierarchyIncoming': false});
    expect(command('alt+shift+h'), 'editor.showIncomingCalls');
    expect(command('escape'), 'editor.closeCallHierarchy');
    expect(command('shift+enter'), 'editor.refocusCallHierarchy');
    context.setValues({'callHierarchyStablePeek': true});
    expect(command('escape'), isNot('editor.closeCallHierarchy'));
  });

  test('static shortcut filtering keeps alternatives for a live chord', () {
    const command = 'editor.showCallHierarchy';
    final keys = KeybindingSet.load(
      platform: TargetPlatform.windows,
      userJson: '[{"key":"alt+shift+h","command":"workbench.action.quickOpen",'
          '"when":"editorTextFocus"},'
          '{"key":"alt+shift+h","command":"editor.showCallHierarchy",'
          '"when":"editorTextFocus && editorHasCallHierarchyProvider"}]',
    );
    final context = ContextKeyService()
      ..setValues({
        'editorTextFocus': true,
        'editorHasCallHierarchyProvider': true,
      });
    addTearDown(context.dispose);
    final chord = parseChord('alt+shift+h')!;
    expect(
      keys.bindingForChord(chord, matchesWhen: context.matches)?.commandId,
      command,
    );
    final staticBindings = keys.resolveBindings(
      matchesWhen: context.matches,
      excludeCommands: const {command},
    );
    final fallback = staticBindings.entries.singleWhere(
      (entry) =>
          entry.key.trigger == chord.key &&
          entry.key.alt &&
          entry.key.shift &&
          !entry.key.control &&
          !entry.key.meta,
    );
    expect(fallback.value.commandId, quickOpenId);
  });

  test('type hierarchy uses its own direction and close contexts', () {
    final keys = KeybindingSet.load(platform: TargetPlatform.windows);
    final context = ContextKeyService();
    addTearDown(context.dispose);
    String? command(String key) => keys
        .bindingForChord(parseChord(key)!, matchesWhen: context.matches)
        ?.commandId;

    context.setValues({
      'editorTextFocus': true,
      'typeHierarchyVisible': true,
    });
    expect(command('alt+shift+h'), isNot('editor.showCallHierarchy'));
    expect(command('escape'), 'editor.closeTypeHierarchy');
    expect(command('shift+enter'), isNot('editor.refocusTypeHierarchy'));

    context.setValues({'typeHierarchyHasRoots': true});
    expect(command('alt+shift+h'), 'editor.showSupertypes');
    expect(command('shift+enter'), 'editor.refocusTypeHierarchy');
    context.setValues({'typeHierarchySupertypes': true});
    expect(command('alt+shift+h'), 'editor.showSubtypes');
    context.setValues({'typeHierarchyStablePeek': true});
    expect(command('escape'), isNot('editor.closeTypeHierarchy'));
  });

  test('definition commands use the canonical IDs and platform chord', () {
    const go = 'editor.action.revealDefinition';
    const aside = 'editor.action.revealDefinitionAside';
    const oldAside = 'editor.action.openDeclarationToTheSide';
    bool inEditor(String? condition) =>
        condition == null || condition == 'editorTextFocus';
    for (final (platform, modifier) in [
      (TargetPlatform.windows, 'ctrl'),
      (TargetPlatform.linux, 'ctrl'),
      (TargetPlatform.macOS, 'cmd'),
    ]) {
      final keys = KeybindingSet.load(platform: platform);
      final chord = parseChordSequence('$modifier+k f12')!;
      expect(
          keys
              .bindingForChord(parseChord('f12')!, matchesWhen: inEditor)
              ?.commandId,
          go);
      expect(keys.bindingForSequence(chord.chords)?.commandId, aside);
      expect(keys.bindingForSequence(chord.chords)?.when, 'editorTextFocus');
      expect(keys.shortcutFor('editor.gotoDef'), keys.shortcutFor(go));
      expect(keys.shortcutFor('editor.action.goToDeclaration'),
          keys.shortcutFor(go));
      expect(keys.shortcutFor(oldAside), chord.display);
    }
    final custom = KeybindingSet.load(
      platform: TargetPlatform.windows,
      userJson: '''[
        {"key":"f12","command":"-editor.gotoDef"},
        {"key":"ctrl+shift+f7","command":"$oldAside"}
      ]''',
    );
    expect(custom.bindingForChord(parseChord('f12')!, matchesWhen: inEditor),
        isNull);
    expect(custom.bindingForSequence(parseChordSequence('ctrl+k f12')!.chords),
        isNull);
    expect(custom.commandForChord(parseChord('ctrl+shift+f7')!), aside);
    expect(custom.shortcutFor(oldAside), custom.shortcutFor(aside));
  });

  test('Quick Open registers the canonical platform shortcuts', () {
    for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
      final keys = KeybindingSet.load(platform: platform);
      expect(keys.commandForChord(parseChord('ctrl+p')!), quickOpenId);
      expect(keys.commandForChord(parseChord('ctrl+e')!), quickOpenId);
      expect(keys.shortcutFor(quickOpenId), 'Ctrl+P');
      expect(keys.shortcutFor('view.quickOpen'), 'Ctrl+P');
    }
    final mac = KeybindingSet.load(platform: TargetPlatform.macOS);
    expect(mac.commandForChord(parseChord('cmd+p')!), quickOpenId);
    expect(mac.commandForChord(parseChord('ctrl+p')!), isNull);
    expect(mac.commandForChord(parseChord('cmd+e')!), isNot(quickOpenId));
    expect(mac.shortcutFor('view.quickOpen'), parseChord('cmd+p')!.display);
  });

  group('canonical command palette keybindings', () {
    const command = 'workbench.action.showCommands';

    test('F1 and the platform shortcut resolve to a single command', () {
      for (final platform in [
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.macOS,
      ]) {
        final keys = KeybindingSet.load(platform: platform);
        final primary =
            platform == TargetPlatform.macOS ? 'cmd+shift+p' : 'ctrl+shift+p';
        expect(keys.commandForChord(parseChord(primary)!), command);
        expect(keys.commandForChord(parseChord('f1')!), command);
        expect(
            keys.shortcutFor('view.commandPalette'), keys.shortcutFor(command));
        expect(keys.shortcutFor('view.quickInput'), keys.shortcutFor(command));
        expect(keys.shortcutFor('view.panelDiagnostics'), isNull);
      }
    });

    test('legacy command overrides and removals address the canonical command',
        () {
      final rebinding = KeybindingSet.load(
        platform: TargetPlatform.windows,
        userJson: '[{"key":"alt+shift+p","command":"view.commandPalette"}]',
      );
      expect(rebinding.commandForChord(parseChord('alt+shift+p')!), command);
      expect(rebinding.commandForChord(parseChord('f1')!), isNull);
      expect(rebinding.commandForChord(parseChord('ctrl+shift+p')!), isNull);
      expect(rebinding.shortcutFor(command), 'Shift+Alt+P');

      final removal = KeybindingSet.load(
        platform: TargetPlatform.windows,
        userJson: '[{"key":"f1","command":"-view.quickInput"}]',
      );
      expect(removal.commandForChord(parseChord('f1')!), isNull);
      expect(removal.commandForChord(parseChord('ctrl+shift+p')!), command);

      final explicitDiagnostics = KeybindingSet.load(
        platform: TargetPlatform.windows,
        userJson: '[{"key":"f1","command":"view.panelDiagnostics"}]',
      );
      expect(explicitDiagnostics.commandForChord(parseChord('f1')!),
          'view.panelDiagnostics');
    });
  });

  group('Breadcrumb keybindings', () {
    test('punctuation names resolve to the same logical keys', () {
      expect(parseChord('ctrl+shift+period'), parseChord('ctrl+shift+.'));
      expect(parseChord('cmd+shift+semicolon'), parseChord('cmd+shift+;'));
      expect(parseChord('.')!.key, LogicalKeyboardKey.period);
      expect(parseChord(';')!.key, LogicalKeyboardKey.semicolon);
    });

    test('platform defaults retain context and navigation alternatives', () {
      for (final platform in [
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.macOS,
      ]) {
        final keys = KeybindingSet.load(platform: platform);
        final modifier = platform == TargetPlatform.macOS ? 'cmd' : 'ctrl';
        final word = platform == TargetPlatform.macOS ? 'alt' : 'ctrl';
        for (final entry in {
          '$modifier+shift+;': 'breadcrumbs.focus',
          '$modifier+shift+.': 'breadcrumbs.focusAndSelect',
          'arrowright': 'breadcrumbs.focusNext',
          '$word+arrowright': 'breadcrumbs.focusNextWithPicker',
          'arrowleft': 'breadcrumbs.focusPrevious',
          '$word+arrowleft': 'breadcrumbs.focusPreviousWithPicker',
          'enter': 'breadcrumbs.selectFocused',
          'arrowdown': 'breadcrumbs.selectFocused',
          'escape': 'breadcrumbs.selectEditor',
          'space': 'breadcrumbs.revealFocused',
        }.entries) {
          final expectedContext = switch (entry.value) {
            'breadcrumbs.focus' ||
            'breadcrumbs.focusAndSelect' =>
              'breadcrumbsVisible',
            'breadcrumbs.focusNext' ||
            'breadcrumbs.focusPrevious' =>
              'breadcrumbsVisible && breadcrumbsActive && !breadcrumbsPickerOpen',
            'breadcrumbs.focusNextWithPicker' ||
            'breadcrumbs.focusPreviousWithPicker' =>
              'breadcrumbsVisible && breadcrumbsActive && breadcrumbsPickerOpen && breadcrumbsPickerFocused',
            _ => 'breadcrumbsVisible && breadcrumbsActive',
          };
          final binding = keys.bindingForChord(
            parseChord(entry.key)!,
            matchesWhen: (condition) =>
                condition == null || condition == expectedContext,
          )!;
          expect(binding.commandId, entry.value,
              reason: '$platform/${entry.key}');
          expect(binding.when, expectedContext);
        }
        final enableBreadcrumbs = keys.bindingForChord(
          parseChord('$modifier+shift+.')!,
          matchesWhen: (condition) =>
              condition == 'config.breadcrumbs.enabled == false',
        );
        expect(enableBreadcrumbs?.commandId, 'breadcrumbs.toggleToOn');
        final outsidePicker = keys.resolveBindings(
          matchesWhen: (condition) =>
              condition == null ||
              condition ==
                  'breadcrumbsVisible && breadcrumbsActive && !breadcrumbsPickerOpen',
        );
        final outsidePickerNext = outsidePicker.entries.singleWhere(
          (entry) =>
              entry.key.trigger == LogicalKeyboardKey.arrowRight &&
              (platform == TargetPlatform.macOS
                  ? entry.key.alt
                  : entry.key.control) &&
              !entry.key.shift &&
              (platform == TargetPlatform.macOS
                  ? !entry.key.control && !entry.key.meta
                  : !entry.key.alt && !entry.key.meta),
        );
        expect(outsidePickerNext.value.commandId, 'breadcrumbs.focusNext',
            reason: '$platform keeps ordinary navigation outside picker');
        final insidePicker = keys.resolveBindings(
          matchesWhen: (condition) =>
              condition == null ||
              condition ==
                  'breadcrumbsVisible && breadcrumbsActive && breadcrumbsPickerOpen && breadcrumbsPickerFocused',
        );
        final insidePickerNext = insidePicker.entries.singleWhere(
          (entry) =>
              entry.key.trigger == LogicalKeyboardKey.arrowRight &&
              (platform == TargetPlatform.macOS
                  ? entry.key.alt
                  : entry.key.control) &&
              !entry.key.shift &&
              (platform == TargetPlatform.macOS
                  ? !entry.key.control && !entry.key.meta
                  : !entry.key.alt && !entry.key.meta),
        );
        expect(
            insidePickerNext.value.commandId, 'breadcrumbs.focusNextWithPicker',
            reason: '$platform gives picker navigation precedence while open');
        expect(
          insidePicker.entries.any((entry) =>
              entry.key.trigger == LogicalKeyboardKey.arrowRight &&
              !entry.key.control &&
              !entry.key.alt &&
              !entry.key.shift &&
              !entry.key.meta),
          isFalse,
          reason: 'bare arrows remain available to the popup menu',
        );
        final activeReveal = keys.resolveBindings(
            matchesWhen: (condition) =>
                condition == null ||
                condition == 'breadcrumbsVisible && breadcrumbsActive');
        final reveal = activeReveal.entries.singleWhere((entry) =>
            entry.key.trigger == LogicalKeyboardKey.enter &&
            !entry.key.shift &&
            !entry.key.alt &&
            (platform == TargetPlatform.macOS
                ? entry.key.meta
                : entry.key.control));
        expect(reveal.value.commandId, 'breadcrumbs.revealFocused');
        final inactive =
            keys.resolveBindings(matchesWhen: (condition) => condition == null);
        expect(
            inactive.values.where(
                (binding) => binding.commandId.startsWith('breadcrumbs.')),
            isEmpty);
        final active = keys.resolveBindings(
            matchesWhen: (condition) =>
                condition == null || condition.startsWith('breadcrumbs'));
        expect(
            active.values.where(
                (binding) => binding.commandId.startsWith('breadcrumbs.')),
            hasLength(11));
      }
    });

    test('user removal and replacement apply to breadcrumb defaults', () {
      final keys = KeybindingSet.load(
        platform: TargetPlatform.windows,
        userJson: '[{"key":"ctrl+shift+;","command":"-breadcrumbs.focus"},'
            '{"key":"ctrl+alt+b","command":"breadcrumbs.focus",'
            '"when":"breadcrumbsPossible"}]',
      );
      expect(keys.bindingForChord(parseChord('ctrl+shift+;')!), isNull);
      final resolved = keys.resolveBindings(
          matchesWhen: (condition) =>
              condition == null || condition == 'breadcrumbsPossible');
      final binding = resolved.entries
          .singleWhere((entry) =>
              entry.key.trigger == LogicalKeyboardKey.keyB &&
              entry.key.control &&
              entry.key.alt)
          .value;
      expect(binding.commandId, 'breadcrumbs.focus');
      expect(binding.when, 'breadcrumbsPossible');
    });
  });

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
        expect(
          keybindings.bindingForSequence(
            [parseChord('ctrl+k')!, parseChord('u')!],
          )?.commandId,
          'workbench.action.closeUnmodifiedEditors',
        );
        expect(
          keybindings.commandForChord(parseChord('ctrl+alt+t')!),
          'workbench.action.closeOtherEditors',
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
      expect(
        mac.bindingForSequence(
          [parseChord('cmd+k')!, parseChord('u')!],
        )?.commandId,
        'workbench.action.closeUnmodifiedEditors',
      );
      expect(
        mac.commandForChord(parseChord('cmd+alt+t')!),
        'workbench.action.closeOtherEditors',
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
      final context = ContextKeyService();
      addTearDown(context.dispose);
      expect(
        mac.bindingForChord(parseChord('ctrl+enter')!,
            matchesWhen: context.matches),
        isNull,
      );
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
      expect(
        windows.bindingForChord(
          parseChord('ctrl+shift+a')!,
          matchesWhen: (condition) => condition == null,
        ),
        isNull,
      );
    });

    test('notification primary action default respects user binding precedence',
        () {
      for (final platform in [
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.macOS,
      ]) {
        final keys = KeybindingSet.load(platform: platform);
        final keySpec =
            platform == TargetPlatform.macOS ? 'cmd+shift+a' : 'ctrl+shift+a';
        final chord = parseChord(keySpec)!;
        final matching = keys.bindingForChord(
          chord,
          matchesWhen: (condition) =>
              condition == null ||
              condition == KeybindingSet.notificationPrimaryActionWhen,
        );
        expect(matching?.commandId, 'notification.acceptPrimaryAction');
        expect(matching?.when, KeybindingSet.notificationPrimaryActionWhen);

        final rebound = KeybindingSet.load(
          platform: platform,
          userJson: '[{"key":"$keySpec","command":"file.save"}]',
        );
        expect(
          rebound
              .bindingForChord(chord, matchesWhen: (condition) => true)
              ?.commandId,
          'file.save',
        );
      }
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
      expect(
          mac.resolveBindings(matchesWhen: (condition) => condition == null)[
              parseChord('alt+arrowleft')!.toActivator()],
          isNull);
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
      final ks = KeybindingSet.load(platform: TargetPlatform.windows);
      final resolved = ks.resolve();
      final expectedChords = KeybindingSet.defaultsFor(TargetPlatform.windows)
          .values
          .expand((value) => value.split(','))
          .map(parseChord)
          .whereType<KeyChord>()
          .toSet()
          .length;
      expect(resolved.keys.length, expectedChords + 21,
          reason: 'tree find, breadcrumbs, notifications and navigation '
              'add contextual bindings');
      expect(
        ks.shortcutFor('editor.action.peekDefinition'),
        'Alt+F12',
      );
      expect(ks.shortcutFor('view.commandPalette'), 'Ctrl+Shift+P');
      expect(
          ks.shortcutFor('workbench.action.files.newUntitledFile'), 'Ctrl+N');
      expect(ks.shortcutFor('file.save'), 'Ctrl+S');
      expect(ks.shortcutFor('file.saveAs'), 'Ctrl+Shift+S');
      expect(ks.shortcutFor('view.panelSyntax'), 'F3');
    });

    test('reference navigation shortcuts override F12 only inside Peek', () {
      for (final platform in [
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.macOS,
      ]) {
        final keys = KeybindingSet.load(platform: platform);
        final context = ContextKeyService();
        addTearDown(context.dispose);
        String? command(String chord,
            {required bool peek, bool editor = true, bool result = false}) {
          context.setValues({
            'referenceSearchVisible': peek,
            'peekResultFocused': result,
            'editorTextFocus': editor,
          });
          return keys
              .bindingForChord(parseChord(chord)!, matchesWhen: context.matches)
              ?.commandId;
        }

        final insertBelow = platform == TargetPlatform.macOS
            ? null
            : 'editor.action.insertLineAfter';
        expect(command('ctrl+enter', peek: false), insertBelow);
        expect(command('ctrl+enter', peek: true), insertBelow);
        expect(command('ctrl+enter', peek: true, result: true),
            'openReferenceToSide');
        expect(keys.shortcutFor('openReferenceToSide'), 'Ctrl+Enter');
        expect(command('f4', peek: false), isNull);
        expect(command('f4', peek: true, editor: false), isNull);
        expect(command('shift+f4', peek: false), isNull);
        expect(command('f12', peek: false), 'editor.action.revealDefinition');
        expect(command('f12', peek: false, editor: false), isNull);
        expect(
            command('shift+f12', peek: false), 'editor.action.goToReferences');
        expect(command('f4', peek: true), 'goToNextReference');
        expect(keys.shortcutFor('goToNextReference'), 'F4');
        expect(keys.shortcutFor('goToPreviousReference'), 'Shift+F4');
        expect(command('f12', peek: true), 'goToNextReference');
        expect(command('shift+f4', peek: true), 'goToPreviousReference');
        expect(command('shift+f12', peek: true), 'goToPreviousReference');
      }

      final remapped = KeybindingSet.load(userJson: '''[
        {"key":"ctrl+shift+f4","command":"goToPreviousReferenceFromEmbeddedEditor"},
        {"key":"f4","command":"-goToNextReferenceFromEmbeddedEditor"}
      ]''');
      expect(remapped.commandForChord(parseChord('ctrl+shift+f4')!),
          'goToPreviousReference');
      expect(remapped.commandForChord(parseChord('f4')!), isNull);
    });

    test('implementation Go and Peek use the platform editor shortcuts', () {
      for (final (platform, modifier) in [
        (TargetPlatform.windows, 'ctrl'),
        (TargetPlatform.linux, 'ctrl'),
        (TargetPlatform.macOS, 'cmd'),
      ]) {
        final keys = KeybindingSet.load(platform: platform);
        final context = ContextKeyService();
        addTearDown(context.dispose);
        String? command(String chord) => keys
            .bindingForChord(parseChord(chord)!, matchesWhen: context.matches)
            ?.commandId;
        expect(command('$modifier+f12'), isNull);
        context.setValue('editorTextFocus', true);
        expect(command('$modifier+f12'), 'editor.action.goToImplementation');
        expect(
            command('$modifier+shift+f12'), 'editor.action.peekImplementation');
        expect(command('shift+f12'), 'editor.action.goToReferences');
        expect(keys.shortcutFor('editor.action.revealDeclaration'), isNull);
        expect(keys.shortcutFor('editor.action.peekTypeDefinition'), isNull);
      }
    });

    test('Peek close defaults honor stable mode and preserve explicit alias',
        () {
      final context = ContextKeyService();
      addTearDown(context.dispose);
      final rebound = KeybindingSet.load(
        platform: TargetPlatform.windows,
        userJson: '''[
          {"key":"ctrl+shift+f9","command":"closeReferenceSearchEditor",
           "when":"referenceSearchVisible"}
        ]''',
      );
      final keys = KeybindingSet.load(platform: TargetPlatform.windows);
      String? command(String chord) => keys
          .bindingForChord(parseChord(chord)!, matchesWhen: context.matches)
          ?.commandId;

      expect(command('escape'), isNull);
      context.setValues({
        'editorTextFocus': true,
        'referenceSearchVisible': true,
        'config.editor.stablePeek': false,
      });
      expect(command('escape'), 'closeReferenceSearch');
      expect(command('shift+escape'), 'closeReferenceSearch');
      context.setValue('config.editor.stablePeek', true);
      expect(command('escape'), isNull);
      expect(command('shift+escape'), isNull);
      expect(
          rebound
              .bindingForChord(
                parseChord('ctrl+shift+f9')!,
                matchesWhen: context.matches,
              )
              ?.commandId,
          'closeReferenceSearch');
    });

    test('Peek focus uses a scoped platform chord', () {
      for (final (platform, modifier) in [
        (TargetPlatform.windows, 'ctrl'),
        (TargetPlatform.linux, 'ctrl'),
        (TargetPlatform.macOS, 'cmd'),
      ]) {
        final keys = KeybindingSet.load(platform: platform);
        final sequence = parseChordSequence('$modifier+k f2')!;
        final binding = keys.bindingForSequence(sequence.chords)!;
        expect(binding.commandId, 'togglePeekWidgetFocus');
        final context = ContextKeyService();
        addTearDown(context.dispose);

        bool hasFocusChord() => keys.hasSequencePrefix(
              sequence.chords.first,
              matchesWhen: context.matches,
              isCommandEnabled: (id) => id == binding.commandId,
            );

        context.setValue('editorTextFocus', true);
        expect(hasFocusChord(), isFalse);
        context.setValue('peekWidgetVisible', true);
        expect(hasFocusChord(), isTrue);
        context.setValue('editorTextFocus', false);
        expect(hasFocusChord(), isFalse);
      }
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
      expect(ks.commandForChord(parseChord('ctrl+alt+f')!), quickOpenId,
          reason: '新键位生效');
      expect(ks.commandForChord(parseChord('ctrl+p')!), isNull,
          reason: '重绑定语义：同命令旧默认键位让位');
      expect(ks.commandForChord(parseChord('ctrl+e')!), isNull);
      expect(ks.shortcutFor('view.quickOpen'), 'Ctrl+Alt+F',
          reason: '展示跟随用户重绑定');
      expect(ks.shortcutFor(quickOpenId), 'Ctrl+Alt+F');
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
      expect(binding.commandId, quickOpenId);
      expect(binding.arguments, {'path': 'src/main.rs'});
      expect(binding.when, 'editorTextFocus');
      expect(
        ks
            .resolveBindings(matchesWhen: (condition) => condition == null)
            .values
            .where((binding) => binding.commandId == quickOpenId),
        isEmpty,
      );
      expect(
        ks
            .resolveBindings(
                matchesWhen: (condition) => condition == 'editorTextFocus')
            .values
            .where((binding) => binding.commandId == quickOpenId),
        hasLength(1),
      );
    });

    test('用户移除：-command 删掉匹配的默认键位', () {
      final ks = KeybindingSet.load(
        platform: TargetPlatform.windows,
        userJson: '[{"key": "ctrl+p", "command": "-view.quickOpen"}]',
      );
      expect(ks.commandForChord(parseChord('ctrl+p')!), isNull,
          reason: '默认 Ctrl+P 已被移除');
      expect(ks.commandForChord(parseChord('ctrl+e')!), quickOpenId);
      expect(ks.shortcutFor('view.quickOpen'), 'Ctrl+E');
    });

    test('移除不匹配的键位串：无操作', () {
      final ks = KeybindingSet.load(
          userJson: '[{"key": "ctrl+q", "command": "-view.quickOpen"}]');
      expect(ks.commandForChord(parseChord('ctrl+p')!), quickOpenId,
          reason: '键位不匹配不移除');
    });

    test('损坏 JSON：只用默认键位', () {
      final ks = KeybindingSet.load(userJson: '[{"key": broken');
      final expectedChords = KeybindingSet.load().resolve().length;
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
    test(
        'Join Lines is command-palette-only on Windows/Linux and Ctrl+J on macOS',
        () {
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
